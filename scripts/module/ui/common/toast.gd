class_name Toast
extends CanvasLayer

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Label

const _MAX_PANEL_W: float = 870.0
const _PANEL_Y: float = 750.0
const _FLOAT_DIST: float = 50.0

static var _current: Toast = null


static func popup(msg: String, node: Node) -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	var scene: PackedScene = load("res://assets/prefab/toast.tscn")
	var toast := scene.instantiate() as Toast
	_current = toast
	node.get_tree().root.add_child(toast)
	toast._play(msg)


func _play(msg: String) -> void:
	_label.text = tr(msg)
	_panel.size.x = _MAX_PANEL_W

	await get_tree().process_frame

	var vp_w: float = get_viewport().get_visible_rect().size.x
	var panel_h: float = _panel.get_combined_minimum_size().y
	var line_count: int = _label.get_line_count()

	var font: Font = _label.get_theme_font("font")
	var fs: int = _label.get_theme_font_size("font_size")
	var content_pad: float = 120.0
	var panel_w: float
	if line_count == 1:
		var text_w: float = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		panel_w = minf(text_w + content_pad, _MAX_PANEL_W)
	else:
		var wrap_w: float = _MAX_PANEL_W - content_pad
		var ms: Vector2 = font.get_multiline_string_size(
			_label.text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs
		)
		panel_w = ms.x + content_pad

	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((vp_w - panel_w) * 0.5, _PANEL_Y)

	_panel.modulate.a = 0.0
	var start_y: float = _panel.position.y

	var tw := _panel.create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.2)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

	var tw_pos := _panel.create_tween()
	(
		tw_pos
		. tween_property(_panel, "position:y", start_y - _FLOAT_DIST, 1.55)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
