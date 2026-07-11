class_name ShortcutManager
extends RefCounted

const FEEDBACK_ACTION_ID: String = "Feedback"
const IMPORTANT_ACTION_ID: String = "Important"


static func _plugin() -> Object:
	if Engine.has_singleton("ShortcutPlugin"):
		return Engine.get_singleton("ShortcutPlugin")
	return null


static func add_shortcuts(feedback_title: String, important_title: String) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.addShortcuts(feedback_title, important_title)


static func get_shortcut_key() -> String:
	var p: Object = _plugin()
	if p == null:
		return ""
	return p.getShortcutKey() as String


static func clear_shortcut_key() -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.clearShortcutKey()


static func connect_shortcut_received(callable: Callable) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	if not p.has_signal("shortcut_received"):
		return
	if p.is_connected("shortcut_received", callable):
		return
	p.connect("shortcut_received", callable)
