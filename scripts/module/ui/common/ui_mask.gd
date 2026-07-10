class_name UIMask
extends RefCounted

static var _ref_count: int = 0
static var _blocker: Control = null

static func acquire() -> void :
    _ref_count += 1
    if _ref_count == 1:
        _show()

static func release() -> void :
    _ref_count -= 1
    if _ref_count <= 0:
        _ref_count = 0
        _hide()

static func _show() -> void :
    if _blocker != null:
        return
    var root: Window = Engine.get_main_loop().root
    _blocker = Control.new()
    _blocker.name = "UIMask"
    _blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _blocker.mouse_filter = Control.MOUSE_FILTER_STOP
    _blocker.z_index = 4095
    _blocker.z_as_relative = false
    root.add_child(_blocker)

static func _hide() -> void :
    if _blocker != null and is_instance_valid(_blocker):
        _blocker.queue_free()
    _blocker = null
