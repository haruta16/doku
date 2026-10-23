## 1.22.0 恢复验收：预期路径、原文件哈希和数据统计均来自独立原包清单。
extends SceneTree

const PACKAGE_MANIFEST := "res://docs/recovery/1.22.0/package_manifest.json"
const RUNTIME_MANIFEST := "res://docs/recovery/1.22.0/runtime_manifest.json"
const SUPPORT = preload("res://tools/recovery_level_support.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var package := _read_manifest(PACKAGE_MANIFEST)
	var runtime := _read_manifest(RUNTIME_MANIFEST)
	if package.is_empty() or runtime.is_empty():
		_finish()
		return
	if package["package_sha256"] != runtime["package_sha256"]:
		failures.append("Package and runtime manifests describe different source packages")
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
		print("VALIDATION_OK: %d recovered scripts, %d scenes, %d translations, %d level files, %d records, %d solution entries" % [
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


func _validate_resources(package: Dictionary) -> void:
	var main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not ResourceLoader.load(main_scene) is PackedScene:
		failures.append("Main scene failed to load: " + main_scene)
	var expected_bytecodes: Array[String] = []
	for entry in package["scripts"]:
		var source_path: String = "res://" + entry["path"]
		var bytecode_path: String = "res://" + entry["bytecode_path"]
		expected_bytecodes.append(bytecode_path)
		_check_hash(bytecode_path, entry["sha256"])
		var script := ResourceLoader.load(source_path)
		if not script is GDScript or not script.can_instantiate():
			failures.append("Recovered script cannot compile: " + source_path)
	_compare_paths(_collect_files("res://.autoconverted", ".gdc"), expected_bytecodes, "original bytecode")
	for path in package["scenes"]:
		var scene := ResourceLoader.load("res://" + path)
		if not scene is PackedScene or not scene.can_instantiate():
			failures.append("Scene failed to load: " + path)
	var expected_translations: Array[String] = []
	for entry in package["translations"]:
		var path: String = "res://" + entry["path"]
		expected_translations.append(path)
		_check_hash(path, entry["sha256"])
		if not ResourceLoader.load(path) is Translation:
			failures.append("Translation failed to load: " + path)
	_compare_paths(_collect_files("res://assets/localization", ".translation"), expected_translations, "translation")


func _validate_banks(package: Dictionary, runtime: Dictionary) -> void:
	var expected_runtime: Array[String] = []
	var expected_editor: Array[String] = []
	for entry in package["level_banks"]:
		var path: String = "res://" + entry["path"]
		expected_runtime.append(path)
		_check_hash(path, entry["sha256"])
	var actual_runtime := _collect_files("res://assets/resources/levels", ".json")
	actual_runtime.append_array(_collect_files("res://assets/resources/levels", ".bin"))
	_compare_paths(actual_runtime, expected_runtime, "runtime bank")
	if runtime["banks"].size() != package["level_banks"].size():
		failures.append("Decoded bank manifest does not cover every original bank")
	for bank in runtime["banks"]:
		var editor_path: String = "res://" + bank["editor_path"]
		var runtime_path: String = "res://" + bank["runtime_path"]
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
	_compare_paths(_collect_files("res://assets/editor/levels", ".json"), expected_editor, "editor bank")


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
