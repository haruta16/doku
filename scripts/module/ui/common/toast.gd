## 短时文字提示：设置弹出内容并播放自动收起动画。
class_name Toast
extends CanvasLayer

@onready var _panel: PanelContainer = $Panel # 底板容器（宽度按文本算）
@onready var _label: Label = $Panel/Label # 文案

const _MAX_PANEL_W: float = 870.0 # 面板最大宽度（像素）；多行时按「它减内边距」换行

const _CONTENT_PAD: float = 120.0
const _PANEL_Y: float = 750.0 # 面板顶部固定 Y（像素，视口坐标）
const _FLOAT_DIST: float = 50.0 # 停留期间向上浮动的距离（像素）

static var _current: Toast = null # 当前存活的 Toast；新的一条会先把旧的 queue_free


## 全局入口：先干掉上一条，再从 prefab 实例化一条挂到根节点上并播
static func popup(msg: String, node: Node) -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	var scene: PackedScene = load("res://assets/prefab/toast.tscn") # toast.tscn 走运行时加载，不用 preload
	var toast := scene.instantiate() as Toast
	_current = toast
	node.get_tree().root.add_child(toast)
	toast._play(msg)


func _play(msg: String) -> void:
	_label.text = tr(msg)

	_panel.modulate.a = 0.0

	var font: Font = _label.get_theme_font("font")
	var fs: int = _label.get_theme_font_size("font_size")
	var wrap_w: float = _MAX_PANEL_W - _CONTENT_PAD

	_label.size.x = wrap_w
	var line_count: int = _label.get_line_count()

	var panel_w: float
	if line_count == 1:
		var text_w: float = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		panel_w = minf(text_w + _CONTENT_PAD, _MAX_PANEL_W)
	else:
		var wrapped: Vector2 = font.get_multiline_string_size(
			_label.text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs
		)
		panel_w = wrapped.x + _CONTENT_PAD

	_label.size.x = panel_w - _CONTENT_PAD
	var _shaped_line_count: int = _label.get_line_count()
	var panel_h: float = _panel.get_combined_minimum_size().y

	var vp_w: float = get_viewport().get_visible_rect().size.x
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((vp_w - panel_w) * 0.5, _PANEL_Y)

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
