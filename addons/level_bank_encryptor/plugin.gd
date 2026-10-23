@tool
extends EditorPlugin

const MENU_LABEL := "Encrypt Level Banks"
const SOURCE_DIR := "res://assets/editor/levels"
const RUNTIME_DIR := "res://assets/resources/levels"
const ENCODER = preload("res://addons/level_bank_encryptor/bank_file_encoder.gd")
const BINARY_FORMAT = preload("res://scripts/module/bank/model/bank_binary_format.gd")


func _enter_tree() -> void:
	add_tool_menu_item(MENU_LABEL, _encrypt_all)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_LABEL)


func _encrypt_all() -> void:
	var source_dir := DirAccess.open(SOURCE_DIR)
	if source_dir == null:
		push_error("LevelBankEncryptor: source directory not found: %s" % SOURCE_DIR)
		return

	var runtime_absolute := ProjectSettings.globalize_path(RUNTIME_DIR)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(runtime_absolute)
	if mkdir_error != OK:
		push_error("LevelBankEncryptor: cannot create %s (error %d)" % [RUNTIME_DIR, mkdir_error])
		return

	var encrypted_count := 0
	source_dir.list_dir_begin()
	var filename := source_dir.get_next()
	while not filename.is_empty():
		if not source_dir.current_is_dir() and filename.get_extension().to_lower() == "json":
			var runtime_filename: String = BINARY_FORMAT.runtime_filename(filename)
			if ENCODER.encrypt_file(SOURCE_DIR.path_join(filename), RUNTIME_DIR.path_join(runtime_filename)):
				encrypted_count += 1
		filename = source_dir.get_next()
	source_dir.list_dir_end()

	EditorInterface.get_resource_filesystem().scan()
	print("LevelBankEncryptor: encrypted %d level bank files" % encrypted_count)
