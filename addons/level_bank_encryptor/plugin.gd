@tool
extends EditorPlugin

const MENU_LABEL := "Encrypt Level Banks"
const KEY := "meowdoku-2026-bank-secret"
const SOURCE_DIR := "res://assets/editor/levels"
const RUNTIME_DIR := "res://assets/resources/levels"


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
			if _encrypt_file(SOURCE_DIR.path_join(filename), RUNTIME_DIR.path_join(filename)):
				encrypted_count += 1
		filename = source_dir.get_next()
	source_dir.list_dir_end()

	EditorInterface.get_resource_filesystem().scan()
	print("LevelBankEncryptor: encrypted %d level bank files" % encrypted_count)


func _encrypt_file(source_path: String, target_path: String) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		push_error("LevelBankEncryptor: cannot read %s" % source_path)
		return false
	var bytes := source.get_buffer(source.get_length())
	source.close()

	var parsed := JSON.parse_string(bytes.get_string_from_utf8())
	if parsed == null:
		push_error("LevelBankEncryptor: invalid JSON in %s" % source_path)
		return false

	_xor_in_place(bytes)
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		push_error("LevelBankEncryptor: cannot write %s" % target_path)
		return false
	target.store_buffer(bytes)
	target.close()
	return true


func _xor_in_place(bytes: PackedByteArray) -> void:
	for index in bytes.size():
		bytes[index] ^= KEY.unicode_at(index % KEY.length())
