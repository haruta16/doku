@tool
class_name BalancedRichTextLabel
extends RichTextLabel

var _last_width: float = -1.0
var _syncing: bool = false

var _pending_recheck: bool = false


func _ready() -> void:
	fit_content = false

	scroll_active = false
	clip_contents = true
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_sync.call_deferred()


func _validate_property(property: Dictionary) -> void:
	if property.name == "fit_content":
		property.usage |= PROPERTY_USAGE_READ_ONLY


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_TRANSLATION_CHANGED:
		_last_width = -1.0
		_sync.call_deferred()


func _set(property: StringName, value: Variant) -> bool:
	if property == &"text" or (property == &"custom_minimum_size" and not _syncing):
		_last_width = -1.0
		_sync.call_deferred()
	return false


func _on_resized() -> void:
	if not is_equal_approx(size.x, _last_width):
		_sync.call_deferred()


func _sync() -> void:
	if _syncing or not is_inside_tree() or size.x <= 0.0:
		return
	_syncing = true
	_last_width = size.x
	var sep: float = float(get_theme_constant("line_separation"))

	var h: float = get_content_height() - sep
	custom_minimum_size = Vector2(custom_minimum_size.x, maxf(h, 0.0))

	var do_recheck: bool = not _pending_recheck
	_pending_recheck = false
	_syncing = false
	if do_recheck:
		_pending_recheck = true
		_sync.call_deferred()
