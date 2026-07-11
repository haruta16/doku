@tool
class_name EditorSettingsUtil

const EXTERNAL_EDITOR_SETTING: String = "text_editor/external/editor"

const EXEC_PATH_SETTING: String = "text_editor/external/exec_path"


static func set_external_editor_path(path: String) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	editor_settings.set_setting(EXEC_PATH_SETTING, path)


static func get_external_editor_path() -> String:
	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings.has_setting(EXEC_PATH_SETTING):
		return editor_settings.get_setting(EXEC_PATH_SETTING)
	else:
		return ""


static func get_rider_selector_index() -> int:
	var editor_settings := EditorInterface.get_editor_settings()
	if not editor_settings.has_setting(EXTERNAL_EDITOR_SETTING):
		return 0
	return editor_settings.get_setting(EXTERNAL_EDITOR_SETTING)


static func erase_rider_external_editor_setting() -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings.has_setting(EXTERNAL_EDITOR_SETTING):
		editor_settings.erase(EXTERNAL_EDITOR_SETTING)


static func show_rider_searching_state() -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	editor_settings.set(EXTERNAL_EDITOR_SETTING, 0)
	(
		editor_settings
		. add_property_info(
			{
				"name": EXTERNAL_EDITOR_SETTING,
				"type": TYPE_INT,
				"hint": PROPERTY_HINT_ENUM,
				"hint_string": "Searching — reopen Settings to see the update",
			}
		)
	)


static func register_rider_installations(installations: Array, selected_index: int) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	var entries: Array = ["-"]
	for element in installations:
		var display_name: String = element.get("display", "")
		entries.append(_escape_enum_label(display_name))
	editor_settings.set(EXTERNAL_EDITOR_SETTING, selected_index)
	(
		editor_settings
		. add_property_info(
			{
				"name": EXTERNAL_EDITOR_SETTING,
				"type": TYPE_INT,
				"hint": PROPERTY_HINT_ENUM,
				"hint_string": ",".join(entries),
			}
		)
	)


static func _escape_enum_label(s: String) -> String:
	return s.replace(",", " •").replace(":", " -")
