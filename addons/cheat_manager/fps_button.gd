class_name FpsButton
extends Button


const SNAP_MARGIN: float = 20.0

const DRAG_THRESHOLD: float = 10.0

const SAVE_PATH: String = "user://cheat_prefs.cfg"


signal toggle_panel_requested


var _dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _btn_start_pos: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0

func _ready() -> void :
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_NONE

    var style: = StyleBoxFlat.new()
    style.corner_radius_top_left = 999
    style.corner_radius_top_right = 999
    style.corner_radius_bottom_left = 999
    style.corner_radius_bottom_right = 999
    style.bg_color = Color(0.15, 0.15, 0.15, 0.85)
    add_theme_stylebox_override("normal", style)
    add_theme_stylebox_override("hover", style)
    var pressed_style: StyleBoxFlat = style.duplicate()
    pressed_style.bg_color = Color(0.25, 0.25, 0.25, 0.9)
    add_theme_stylebox_override("pressed", pressed_style)
    _load_position()

func _process(_delta: float) -> void :
    text = "%d" % Engine.get_frames_per_second()
    var buf: InGameLogBuffer = InGameLogBuffer.instance
    if buf != null:
        var highest: int = buf.get_highest_level()
        if highest == InGameLogBuffer.Level.ERROR:
            add_theme_color_override("font_color", Color.RED)
        elif highest == InGameLogBuffer.Level.WARN:
            add_theme_color_override("font_color", Color.YELLOW)
        else:
            remove_theme_color_override("font_color")

func _gui_input(event: InputEvent) -> void :
    if event is InputEventMouseButton:
        var mb: = event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                _dragging = true
                _drag_distance = 0.0
                _drag_start_pos = mb.global_position
                _btn_start_pos = position
            else:
                _dragging = false
                if _drag_distance < DRAG_THRESHOLD:

                    toggle_panel_requested.emit()
                else:

                    _snap_to_edge()
            get_viewport().set_input_as_handled()

    elif event is InputEventMouseMotion and _dragging:
        var mm: = event as InputEventMouseMotion
        var delta: = mm.global_position - _drag_start_pos
        _drag_distance += delta.length()
        position = _btn_start_pos + delta

        var vp_size: = get_viewport_rect().size
        position.x = clamp(position.x, SNAP_MARGIN, vp_size.x - size.x - SNAP_MARGIN)
        position.y = clamp(position.y, SNAP_MARGIN, vp_size.y - size.y - SNAP_MARGIN)
        get_viewport().set_input_as_handled()



func _snap_to_edge() -> void :
    var vp_size: = get_viewport_rect().size
    var center_x: float = position.x + size.x * 0.5
    var target_x: float
    if center_x < vp_size.x * 0.5:
        target_x = SNAP_MARGIN
    else:
        target_x = vp_size.x - size.x - SNAP_MARGIN
    var tw: = create_tween()
    tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
    tw.tween_property(self, "position:x", target_x, 0.2)
    _save_position(Vector2(target_x, position.y))



func _save_position(pos: Vector2) -> void :
    var cfg: = ConfigFile.new()
    cfg.set_value("fps_button", "x", pos.x)
    cfg.set_value("fps_button", "y", pos.y)
    cfg.save(SAVE_PATH)

func _load_position() -> void :
    var cfg: = ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return
    var x: float = cfg.get_value("fps_button", "x", position.x)
    var y: float = cfg.get_value("fps_button", "y", position.y)

    var vp_size: = get_viewport_rect().size
    x = clamp(x, SNAP_MARGIN, maxf(SNAP_MARGIN, vp_size.x - size.x - SNAP_MARGIN))
    y = clamp(y, SNAP_MARGIN, maxf(SNAP_MARGIN, vp_size.y - size.y - SNAP_MARGIN))
    position = Vector2(x, y)
