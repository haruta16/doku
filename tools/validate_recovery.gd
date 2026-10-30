## 1.22.0 恢复验收：预期路径、原文件哈希和数据统计均来自独立原包清单。
extends SceneTree

const PACKAGE_MANIFEST := "res://docs/recovery/1.22.0/package_manifest.json"
const RUNTIME_MANIFEST := "res://docs/recovery/1.22.0/runtime_manifest.json"
const PATHS = preload("res://tools/recovery_paths.gd")
const SOURCE_PACKAGE_SHA256 := "f6664607878fc45cce3e16269425ac8bfaff63a90438e42b8453aad72d466326"
const SUPPORT = preload("res://tools/recovery_level_support.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var package := _read_manifest(PACKAGE_MANIFEST)
	var runtime := _read_manifest(RUNTIME_MANIFEST)
	if package.is_empty() or runtime.is_empty():
		_finish()
		return
	if package["package_sha256"] != runtime["package_sha256"]:
		failures.append("Package and runtime manifests describe different source packages")
	if package.get("package_sha256") != SOURCE_PACKAGE_SHA256:
		failures.append("Unexpected original package identity")
	if package.get("scripts", []).size() != 853 or package.get("scenes", []).size() != 187 or package.get("translations", []).size() != 75 or package.get("level_banks", []).size() != 59:
		failures.append("Unexpected 1.22 original identity counts")
	_validate_mapping(package)
	if not failures.is_empty():
		_finish()
		return
	_validate_resources(package)
	_validate_banks(package, runtime)
	if not SUPPORT.compare_data(SUPPORT.bank_api_snapshot(), runtime.get("bank_api", {}))["equal"]:
		failures.append("BankData API differs from independent original-package baseline")
	if failures.is_empty():
		var records := 0
		var solutions := 0
		var rejected := 0
		var rounding := 0
		for bank in runtime["banks"]:
			records += int(bank["records"])
			solutions += int(bank["solution_entries"])
			rejected += int(bank["runtime_rejected_solutions"])
			rounding += int(bank["json_roundtrip"]["float_rounding_count"])
		print("LEVEL_DATA_INFO: %d original solutions rejected; %d documented JSON float roundings" % [rejected, rounding])
		print("VALIDATION_OK: %d recovered scripts, %d scenes, %d translations, %d level banks, %d records, and %d solution entries" % [
			package["scripts"].size(), package["scenes"].size(), package["translations"].size(),
			runtime["banks"].size(), records, solutions
		])
	_finish()


func _read_manifest(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary:
		failures.append("Missing or invalid manifest: " + path)
		return {}
	return value


## 检查原始身份一一对应实际实现；额外框架文件不计入 853/187 的恢复覆盖。
func _validate_mapping(package: Dictionary) -> void:
	var paths: Dictionary = PATHS.load_paths()
	if paths.is_empty():
		failures.append("Missing recovery mapping")
		return
	var originals: Array[String] = []
	for entry in package["scripts"]:
		originals.append("res://" + String(entry["path"]))
	for scene in package["scenes"]:
		originals.append("res://" + String(scene))
	var seen_originals: Dictionary = {}
	var targets: Dictionary = {}
	for original: String in originals:
		if seen_originals.has(original):
			failures.append("Duplicate original recovery identity: " + original)
		seen_originals[original] = true
		if not paths.has(original):
			failures.append("Unmapped original recovery identity: " + original)
			continue
		var target: Variant = paths[original]
		if not target is String or not target.begins_with("res://") or ".." in target.trim_prefix("res://").split("/") or target.get_extension() != original.get_extension():
			failures.append("Invalid recovery target for " + original)
			continue
		if targets.has(target):
			failures.append("Recovered identities share implementation: %s and %s" % [targets[target], original])
		targets[target] = original
		if not FileAccess.file_exists(target):
			failures.append("Missing relocated implementation: " + target)


func _validate_resources(package: Dictionary) -> void:
	var main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not ResourceLoader.load(main_scene) is PackedScene:
		failures.append("Main scene failed to load: " + main_scene)
	var expected_bytecodes: Array[String] = []
	for entry in package["scripts"]:
		var source_path: String = PATHS.resolve(entry["path"])
		var bytecode_path: String = "res://" + entry["bytecode_path"]
		expected_bytecodes.append(bytecode_path)
		_check_hash(bytecode_path, entry["sha256"])
		var script := ResourceLoader.load(source_path)
		if not script is GDScript or not script.can_instantiate():
			failures.append("Recovered script cannot compile: " + source_path)
	_compare_paths(_collect_files("res://.autoconverted", ".gdc"), expected_bytecodes, "original bytecode")
	for path in package["scenes"]:
		var scene := ResourceLoader.load(PATHS.resolve(path))
		if not scene is PackedScene or not scene.can_instantiate():
			failures.append("Scene failed to load: " + path)
	var expected_translations: Array[String] = []
	for entry in package["translations"]:
		var path: String = PATHS.resolve(entry["path"])
		expected_translations.append(path)
		_check_hash(path, entry["sha256"])
		if not ResourceLoader.load(path) is Translation:
			failures.append("Translation failed to load: " + path)
	_compare_paths(_collect_files("res://products/meowdoku/assets/localization", ".translation"), expected_translations, "translation")


func _validate_banks(package: Dictionary, runtime: Dictionary) -> void:
	var expected_runtime: Array[String] = []
	var expected_editor: Array[String] = []
	for entry in package["level_banks"]:
		var path: String = PATHS.resolve(entry["path"])
		expected_runtime.append(path)
		_check_hash(path, entry["sha256"])
	var actual_runtime := _collect_files("res://products/meowdoku/assets/resources/levels", ".json")
	actual_runtime.append_array(_collect_files("res://products/meowdoku/assets/resources/levels", ".bin"))
	_compare_paths(actual_runtime, expected_runtime, "runtime bank")
	if runtime["banks"].size() != package["level_banks"].size():
		failures.append("Decoded bank manifest does not cover every original bank")
	for bank in runtime["banks"]:
		var editor_path: String = PATHS.resolve(bank["editor_path"])
		var runtime_path: String = PATHS.resolve(bank["runtime_path"])
		expected_editor.append(editor_path)
		_check_hash(editor_path, bank["editor_sha256"])
		var editor_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(editor_path))
		var runtime_data: Variant = SUPPORT.read_runtime(runtime_path)
		if editor_data == null or runtime_data == null:
			failures.append("Cannot read/decode bank: " + runtime_path)
			continue
		runtime_data = SUPPORT.materialize(runtime_data)
		var comparison: Dictionary = SUPPORT.compare_data(editor_data, runtime_data)
		if not comparison["equal"] or not SUPPORT.compare_data(comparison, bank["json_roundtrip"])["equal"]:
			failures.append("Editor/runtime data differs from original baseline: " + runtime_path)
		var statistics: Dictionary = SUPPORT.statistics(runtime_data)
		for key in statistics:
			if statistics[key] != bank[key]:
				failures.append("Unexpected %s for %s: %s" % [key, runtime_path, statistics[key]])
	_compare_paths(_collect_files("res://products/meowdoku/assets/editor/levels", ".json"), expected_editor, "editor bank")


func _check_hash(path: String, expected: String) -> void:
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != expected:
		failures.append("Original hash mismatch or missing file: " + path)


func _compare_paths(actual: Array[String], expected: Array[String], kind: String) -> void:
	actual.sort()
	expected.sort()
	if actual != expected:
		for path in expected:
			if not actual.has(path):
				failures.append("Missing %s: %s" % [kind, path])
		for path in actual:
			if not expected.has(path):
				failures.append("Unexpected/stale %s: %s" % [kind, path])


func _collect_files(root: String, suffix: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return result
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		var path := root.path_join(filename)
		if directory.current_is_dir():
			result.append_array(_collect_files(path, suffix))
		elif filename.ends_with(suffix):
			result.append(path)
		filename = directory.get_next()
	directory.list_dir_end()
	return result


func _finish() -> void:
	for failure in failures:
		push_error("VALIDATION_FAILED: " + failure)
	quit(0 if failures.is_empty() else 1)
