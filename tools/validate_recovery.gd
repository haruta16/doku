extends SceneTree

const BYTECODE_ROOT := "res://.autoconverted"
const LEVEL_EDITOR_ROOT := "res://assets/editor/levels"
const LEVEL_RUNTIME_ROOT := "res://assets/resources/levels"
const LEVEL_KEY := "meowdoku-2026-bank-secret"

const EXPECTED_BYTECODE_SCRIPTS := 257
const EXPECTED_SCENES := 74
const EXPECTED_TRANSLATIONS := 75
const EXPECTED_LEVEL_FILES := 26
const EXPECTED_LEVEL_RECORDS := 20746
const EXPECTED_SOLUTION_ENTRIES := 20710
const EXPECTED_RUNTIME_REJECTED_SOLUTIONS := 63


func _initialize() -> void:
	var failures: Array[String] = []

	_validate_main_scene(failures)
	_validate_recovered_scripts(failures)
	_validate_scenes(failures)
	_validate_translations(failures)
	_validate_level_banks(failures)
	_validate_bank_api(failures)

	if failures.is_empty():
		print(
			(
				"VALIDATION_OK: 257 recovered scripts, 74 scenes, 75 translations, "
				+ "26 level banks, 20,746 records, and 20,710 solution entries"
			)
		)
		quit(0)
		return

	for failure in failures:
		push_error("VALIDATION_FAILED: %s" % failure)
	quit(1)


func _validate_main_scene(failures: Array[String]) -> void:
	var main_scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene_path.is_empty() or not ResourceLoader.load(main_scene_path) is PackedScene:
		failures.append("main scene failed to load: %s" % main_scene_path)


func _validate_recovered_scripts(failures: Array[String]) -> void:
	var bytecode_files := _collect_files(BYTECODE_ROOT, ".gdc")
	if bytecode_files.size() != EXPECTED_BYTECODE_SCRIPTS:
		failures.append(
			(
				"expected %d APK bytecode scripts, got %d"
				% [EXPECTED_BYTECODE_SCRIPTS, bytecode_files.size()]
			)
		)

	for bytecode_path in bytecode_files:
		var source_path := (
			bytecode_path.trim_prefix(BYTECODE_ROOT + "/").trim_suffix(".gdc") + ".gd"
		)
		source_path = "res://" + source_path
		if not FileAccess.file_exists(source_path):
			failures.append("recovered source is missing for %s" % bytecode_path)
			continue
		if not ResourceLoader.load(source_path) is GDScript:
			failures.append("recovered script failed to load: %s" % source_path)


func _validate_scenes(failures: Array[String]) -> void:
	var scene_files := _collect_files("res://", ".tscn", ["res://.godot", "res://.autoconverted"])
	if scene_files.size() != EXPECTED_SCENES:
		failures.append("expected %d scenes, got %d" % [EXPECTED_SCENES, scene_files.size()])

	for scene_path in scene_files:
		if not ResourceLoader.load(scene_path) is PackedScene:
			failures.append("scene failed to load: %s" % scene_path)


func _validate_translations(failures: Array[String]) -> void:
	var translation_files := _collect_files("res://assets/localization", ".translation")
	if translation_files.size() != EXPECTED_TRANSLATIONS:
		failures.append(
			(
				"expected %d runtime translations, got %d"
				% [EXPECTED_TRANSLATIONS, translation_files.size()]
			)
		)

	for translation_path in translation_files:
		if not ResourceLoader.load(translation_path) is Translation:
			failures.append("translation failed to load: %s" % translation_path)


func _validate_level_banks(failures: Array[String]) -> void:
	var editor_files := _collect_files(LEVEL_EDITOR_ROOT, ".json")
	var runtime_files := _collect_files(LEVEL_RUNTIME_ROOT, ".json")
	if editor_files.size() != EXPECTED_LEVEL_FILES:
		failures.append(
			"expected %d editor level files, got %d" % [EXPECTED_LEVEL_FILES, editor_files.size()]
		)
	if runtime_files.size() != EXPECTED_LEVEL_FILES:
		failures.append(
			"expected %d runtime level files, got %d" % [EXPECTED_LEVEL_FILES, runtime_files.size()]
		)

	var total_records := 0
	var solution_entries := 0
	var invalid_solution_entries := 0
	for editor_path in editor_files:
		var filename := editor_path.get_file()
		var runtime_path := LEVEL_RUNTIME_ROOT.path_join(filename)
		if not FileAccess.file_exists(runtime_path):
			failures.append("runtime level bank is missing: %s" % filename)
			continue

		var editor_data: Variant = _parse_json_file(editor_path)
		var runtime_data: Variant = _parse_encrypted_json_file(runtime_path)
		if editor_data == null:
			failures.append("editor level bank is invalid JSON: %s" % filename)
			continue
		if runtime_data == null:
			failures.append("runtime level bank failed to decrypt/parse: %s" % filename)
			continue
		if editor_data != runtime_data:
			failures.append("editor/runtime level bank mismatch: %s" % filename)
			continue

		total_records += _count_top_level_records(editor_data)
		var solution_validation := _validate_solution_entries(editor_data)
		solution_entries += solution_validation.x
		invalid_solution_entries += solution_validation.y

	if total_records != EXPECTED_LEVEL_RECORDS:
		failures.append(
			"expected %d level records, got %d" % [EXPECTED_LEVEL_RECORDS, total_records]
		)
	if solution_entries != EXPECTED_SOLUTION_ENTRIES:
		failures.append(
			"expected %d solution entries, got %d" % [EXPECTED_SOLUTION_ENTRIES, solution_entries]
		)
	if invalid_solution_entries != EXPECTED_RUNTIME_REJECTED_SOLUTIONS:
		failures.append(
			"expected %d runtime-rejected original solutions, got %d"
			% [EXPECTED_RUNTIME_REJECTED_SOLUTIONS, invalid_solution_entries]
		)
	print(
		(
			"LEVEL_DATA_INFO: %d original solution entries are rejected by runtime validation"
			% invalid_solution_entries
		)
	)


func _validate_bank_api(failures: Array[String]) -> void:
	var expected_sizes: Array[int] = [4, 5, 6, 7, 8, 9, 10, 12]
	if BankData.get_sizes() != expected_sizes:
		failures.append("unexpected regular level-bank sizes: %s" % [BankData.get_sizes()])

	var special_levels := BankData.get_sp_levels()
	if special_levels.size() != 57:
		failures.append("expected 57 SP levels, got %d" % special_levels.size())
	if not special_levels.any(
		func(entry: Dictionary) -> bool: return entry.get("pattern", "") == "guide"
	):
		failures.append("SP tutorial guide level is missing")


func _validate_solution_entries(value: Variant) -> Vector2i:
	var count := Vector2i.ZERO
	if value is Array:
		for item in value:
			count += _validate_solution_entries(item)
		return count
	if not value is Dictionary:
		return count

	var entry := value as Dictionary
	if entry.has("solution") and entry.has("regionMap"):
		count.x += 1
		var size := (entry.get("regionMap", []) as Array).size()
		if size <= 0 or not QueendokuCore.validate_solution_entry(entry, size):
			count.y += 1
	for child in entry.values():
		if child is Array or child is Dictionary:
			count += _validate_solution_entries(child)
	return count


func _count_top_level_records(value: Variant) -> int:
	if value is Array:
		return (value as Array).size()
	if not value is Dictionary:
		return 0

	var data := value as Dictionary
	if data.has("levels") and data["levels"] is Array:
		return (data["levels"] as Array).size()

	var count := 0
	for child in data.values():
		if child is Array:
			count += (child as Array).size()
	return count


func _parse_json_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return JSON.parse_string(text)


func _parse_encrypted_json_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	for index in bytes.size():
		bytes[index] ^= LEVEL_KEY.unicode_at(index % LEVEL_KEY.length())
	return JSON.parse_string(bytes.get_string_from_utf8())


func _collect_files(
	root: String, suffix: String, excluded_roots: Array[String] = []
) -> Array[String]:
	var result: Array[String] = []
	_collect_files_recursive(root, suffix, excluded_roots, result)
	result.sort()
	return result


func _collect_files_recursive(
	root: String, suffix: String, excluded_roots: Array[String], result: Array[String]
) -> void:
	for excluded_root in excluded_roots:
		if root == excluded_root or root.begins_with(excluded_root + "/"):
			return

	var directory := DirAccess.open(root)
	if directory == null:
		return
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		var path := root.path_join(filename)
		if directory.current_is_dir():
			_collect_files_recursive(path, suffix, excluded_roots, result)
		elif filename.ends_with(suffix):
			result.append(path)
		filename = directory.get_next()
	directory.list_dir_end()
