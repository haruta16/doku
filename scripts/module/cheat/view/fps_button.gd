## 帧率调试悬浮按钮：显示运行指标，支持拖动吸边并记住位置。
class_name FpsButton
extends Button

const SNAP_MARGIN: float = 20.0

const DRAG_THRESHOLD: float = 10.0

const SAVE_PATH: String = "user://cheat_prefs.cfg"

var _last_fps: int = -1
var _last_highest: int = -1

signal toggle_panel_requested

const DC_LABEL_GAP: float = 8.0

static var dc_visible: bool = false

var _dc_label: Label = null
var _last_dc_text: String = ""

var _dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _btn_start_pos: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

	var style := StyleBoxFlat.new()
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
	_build_dc_label()
	_load_position()


func _process(_delta: float) -> void:
	var fps: int = Engine.get_frames_per_second()
	if fps != _last_fps:
		_last_fps = fps
		text = "%d" % fps
	_update_dc_label()
	var buf: InGameLogBuffer = InGameLogBuffer.instance
	var highest: int = buf.get_highest_level() if buf != null else InGameLogBuffer.Level.INFO
	if highest == _last_highest:
		return
	_last_highest = highest
	if highest == InGameLogBuffer.Level.ERROR:
		add_theme_color_override("font_color", Color.RED)
	elif highest == InGameLogBuffer.Level.WARN:
		add_theme_color_override("font_color", Color.YELLOW)
	else:
		remove_theme_color_override("font_color")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
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
		var mm := event as InputEventMouseMotion
		var delta := mm.global_position - _drag_start_pos
		_drag_distance += delta.length()
		position = _btn_start_pos + delta

		var vp_size := get_viewport_rect().size
		position.x = clamp(position.x, SNAP_MARGIN, vp_size.x - size.x - SNAP_MARGIN)
		position.y = clamp(position.y, SNAP_MARGIN, vp_size.y - size.y - SNAP_MARGIN)
		get_viewport().set_input_as_handled()


func _build_dc_label() -> void:
	_dc_label = Label.new()
	_dc_label.name = "DcLabel"
	_dc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dc_label.add_theme_font_size_override("font_size", 36)
	_dc_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_dc_label.add_theme_constant_override("outline_size", 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.15, 0.85)
	bg.set_corner_radius_all(12)
	bg.content_margin_left = 10.0
	bg.content_margin_right = 10.0
	_dc_label.add_theme_stylebox_override("normal", bg)
	_dc_label.visible = false
	add_child(_dc_label)


func _update_dc_label() -> void:
	if _dc_label == null:
		return
	if _dc_label.visible != dc_visible:
		_dc_label.visible = dc_visible
		_last_dc_text = ""
	if not dc_visible:
		return
	var t: String = (
		"DC %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	)
	if t == _last_dc_text:
		return
	_last_dc_text = t
	_dc_label.text = t
	_dc_label.reset_size()
	_dc_label.position = Vector2((size.x - _dc_label.size.x) * 0.5, size.y + DC_LABEL_GAP)


func _snap_to_edge() -> void:
	var vp_size := get_viewport_rect().size
	var center_x: float = position.x + size.x * 0.5
	var target_x: float
	if center_x < vp_size.x * 0.5:
		target_x = SNAP_MARGIN
	else:
		target_x = vp_size.x - size.x - SNAP_MARGIN
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "position:x", target_x, 0.2)
	_save_position(Vector2(target_x, position.y))


func _save_position(pos: Vector2) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("fps_button", "x", pos.x)
	cfg.set_value("fps_button", "y", pos.y)
	cfg.save(SAVE_PATH)


func _load_position() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var x: float = cfg.get_value("fps_button", "x", position.x)
	var y: float = cfg.get_value("fps_button", "y", position.y)

	var vp_size := get_viewport_rect().size
	x = clamp(x, SNAP_MARGIN, maxf(SNAP_MARGIN, vp_size.x - size.x - SNAP_MARGIN))
	y = clamp(y, SNAP_MARGIN, maxf(SNAP_MARGIN, vp_size.y - size.y - SNAP_MARGIN))
	position = Vector2(x, y)
