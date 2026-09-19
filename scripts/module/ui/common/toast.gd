# 全局飘字提示：同一时刻只留一条（新的顶掉旧的），按文本量自适应宽度，再淡入 → 停留 → 淡出并上浮
class_name Toast
extends CanvasLayer

@onready var _panel: PanelContainer = $Panel # 底板容器（宽度按文本算）
@onready var _label: Label = $Panel/Label # 文案

const _MAX_PANEL_W: float = 870.0 # 面板最大宽度（像素）；多行时按「它减内边距」换行
const _PANEL_Y: float = 750.0 # 面板顶部固定 Y（像素，视口坐标）
const _FLOAT_DIST: float = 50.0 # 停留期间向上浮动的距离（像素）

static var _current: Toast = null # 当前存活的 Toast；新的一条会先把旧的 queue_free


# 全局入口：先干掉上一条，再从 prefab 实例化一条挂到根节点上并播
static func popup(msg: String, node: Node) -> void:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	var scene: PackedScene = load("res://assets/prefab/toast.tscn") # toast.tscn 走运行时加载，不用 preload
	var toast := scene.instantiate() as Toast
	_current = toast
	node.get_tree().root.add_child(toast)
	toast._play(msg)


# 真正播一条：先等一帧量文本，再算面板宽高，最后淡入 / 停留 / 淡出并上浮
func _play(msg: String) -> void:
	_label.text = tr(msg) # 文案走翻译表
	_panel.size.x = _MAX_PANEL_W # 先占一个最大宽度，等下一帧排版稳定后再收窄

	await get_tree().process_frame # 等一帧让 Label 完成排版，get_line_count 才准

	var vp_w: float = get_viewport().get_visible_rect().size.x
	var panel_h: float = _panel.get_combined_minimum_size().y
	var line_count: int = _label.get_line_count() # 行数：决定走单行还是多行的宽度算法

	var font: Font = _label.get_theme_font("font")
	var fs: int = _label.get_theme_font_size("font_size")
	var content_pad: float = 120.0
	var panel_w: float
	if line_count == 1: # 单行：按文本实际宽度加内边距，最多不超过上限
		var text_w: float = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		panel_w = minf(text_w + content_pad, _MAX_PANEL_W)
	else:
		var wrap_w: float = _MAX_PANEL_W - content_pad # 多行：按最大宽度减内边距做换行，取换行后的实际宽度
		var ms: Vector2 = font.get_multiline_string_size(
			_label.text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs
		)
		panel_w = ms.x + content_pad

	_panel.size = Vector2(panel_w, panel_h) # 宽度贴内容，高度用最小高度
	_panel.position = Vector2((vp_w - panel_w) * 0.5, _PANEL_Y) # 水平居中，Y 固定

	_panel.modulate.a = 0.0 # 从全透明开始
	var start_y: float = _panel.position.y

	var tw := _panel.create_tween() # 透明度时间线：0.15s 淡入 → 停 1.2s → 0.2s 淡出 → 自销毁
	tw.tween_property(_panel, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.2)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

	var tw_pos := _panel.create_tween() # 位置时间线：1.55s 内缓出地上浮 _FLOAT_DIST
	(
		tw_pos
		. tween_property(_panel, "position:y", start_y - _FLOAT_DIST, 1.55)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
