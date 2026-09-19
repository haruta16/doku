# 规则卡片：三条规则图的左右滑动切换器，支持拖动滑动与圆点跳转
class_name RuleSwipeCard
extends Control

# ---- 动画参数 ----
const _DX: float = 890.0 # 切换时内容的水平位移（像素）
const _OVERSHOOT: float = 10.0 # 滑入的过冲量（像素）
const _OUT_SEC: float = 0.3 # 滑出时长（秒）
const _IN_BACK_SEC: float = 0.16 # 回位时长（秒）
const _DOT_FADE_SEC: float = 0.06 # 圆点透明度渐变时长（秒）
const _DOT_DIM: float = 0.3 # 未选中圆点的透明度
const _SWIPE_THRESHOLD: float = 50.0 # 触发翻页的最小拖动距离（像素）

# ---- 默认值与素材 ----
const _DEFAULT_RULE: int = 2 # 默认展示第 3 条规则（索引 2）

# ---- 三张规则示意图 ----
const _RULE_TEX: Array[Texture2D] = [
	preload("res://assets/sprites/game/rule_diagram_color.png"),
	preload("res://assets/sprites/game/rule_diagram_line.png"),
	preload("res://assets/sprites/game/rule_diagram_touch.png"),
] # 三张规则示意图，按索引取用

# ---- 子节点引用 ----
@onready var _clip: Control = $Clip # 裁剪容器
@onready var _contents: Array[Control] = [$Clip/Content0, $Clip/Content1] # 两层内容交替使用，实现滑动切换
@onready var _dots: Array[TextureButton] = [$Dots/Dot0, $Dots/Dot1, $Dots/Dot2] # 三个圆点按钮

# ---- 运行时状态 ----
var _rules: Array = [] # 规则数据：{texture, text}
var _cur: int = 0 # 当前规则索引
var _active: int = 0 # 当前显示的内容层（0 或 1）
var _tween: Tween = null # 正在跑的切换 Tween
var _press_x: float = 0.0 # 按下时的 x 坐标
var _pressing: bool = false # 是否处于按下状态


# ================= 初始化与切换 =================
# 给三个圆点接上点击
func _ready() -> void:
	for i in range(_dots.size()):
		_dots[i].pressed.connect(_on_dot_pressed.bind(i))


# 注入规则文案（配图按索引取内置素材）
func setup(texts: Array) -> void:
	_rules = []
	for i in range(texts.size()):
		var tex: Texture2D = _RULE_TEX[i] if i < _RULE_TEX.size() else null
		_rules.append({"texture": tex, "text": str(texts[i])})
	_kill_tween()
	# 默认停在第 3 条规则上
	_cur = clampi(_DEFAULT_RULE, 0, maxi(_rules.size() - 1, 0))
	_active = 0
	# 两层内容都归位
	for i in range(_contents.size()):
		_contents[i].position.x = 0.0
		_contents[i].visible = (i == _active)
	_fill_content(_contents[_active], _cur)
	_refresh_dots(true)


# 单行文案的固定测量宽度（像素）
const _LABEL_MEASURE_W: float = 848.0


# 把第 rule_idx 条规则填进指定内容层
func _fill_content(content: Control, rule_idx: int) -> void:
	if rule_idx < 0 or rule_idx >= _rules.size():
		return
	var rule: Dictionary = _rules[rule_idx]
	var diagram := content.get_node("Diagram") as TextureRect
	var holder := content.get_node("LabelHolder") as Control
	var label := content.get_node("LabelHolder/Label") as Label
	# 图片与文案
	diagram.texture = rule.get("texture", null)

	# 先按固定宽度量一次，让长文案能换行
	holder.custom_minimum_size.x = _LABEL_MEASURE_W
	holder.size.x = _LABEL_MEASURE_W
	label.text = str(rule.get("text", ""))
	if label is AutoFitLabel:
		(label as AutoFitLabel).refit()

	# 再按真实文本宽度收窄 holder
	var font: Font = label.get_theme_font(&"font")
	var fs: int = label.get_theme_font_size(&"font_size")
	var disp: String = label.atr(label.text)
	var text_w: float = ceil(
		font.get_multiline_string_size(disp, HORIZONTAL_ALIGNMENT_CENTER, _LABEL_MEASURE_W, fs).x
	)
	holder.custom_minimum_size.x = text_w
	holder.size.x = text_w
	# 尺寸变了，让容器重新排序
	content.queue_sort()


# 切到第 target 条：旧层滑出、新层带回弹滑入
func _go_to(target: int) -> void:
	target = clampi(target, 0, _rules.size() - 1)
	if target == _cur or _rules.is_empty():
		return
	# 方向：向后翻 +1，向前翻 -1
	var dir: int = 1 if target > _cur else -1
	_kill_tween()
	var out_layer: Control = _contents[_active]
	var in_layer: Control = _contents[1 - _active]
	# 新层先摆到屏外
	_fill_content(in_layer, target)
	in_layer.position.x = float(dir) * _DX
	in_layer.visible = true
	out_layer.visible = true
	# 新层先过冲一点再回位
	var overshoot: float = -float(dir) * _OVERSHOOT
	_tween = create_tween()
	_tween.set_parallel(true)

	(
		_tween
		. tween_property(out_layer, "position:x", -float(dir) * _DX, _OUT_SEC)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)

	(
		_tween
		. tween_property(in_layer, "position:x", overshoot, _OUT_SEC)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)

	(
		_tween
		. tween_property(in_layer, "position:x", 0.0, _IN_BACK_SEC)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
		. set_delay(_OUT_SEC)
	)
	var settled_out := out_layer
	# 动画结束后藏掉旧层
	_tween.finished.connect(func() -> void: settled_out.visible = false)
	# 交换活动层
	_active = 1 - _active
	_cur = target
	_refresh_dots(false)


# 刷新圆点状态；instant = true 时直接设值，不淡入淡出
func _refresh_dots(instant: bool) -> void:
	for i in range(_dots.size()):
		var target_a: float = 1.0 if i == _cur else _DOT_DIM
		if instant:
			_dots[i].modulate.a = target_a
		else:
			var tw := create_tween()
			tw.tween_property(_dots[i], "modulate:a", target_a, _DOT_FADE_SEC)


# 点圆点跳页
func _on_dot_pressed(index: int) -> void:
	_go_to(index)


# ================= 滑动手势 =================
# 处理触摸/鼠标的按下与抬起，用位移判断滑动
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_pressing = true
			_press_x = t.position.x
		elif _pressing:
			_pressing = false
			# 抬手时结算滑动
			_resolve_swipe(t.position.x - _press_x)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_press_x = mb.position.x
			elif _pressing:
				_pressing = false
				_resolve_swipe(mb.position.x - _press_x)


# 按位移方向翻页：左滑看下一条，右滑看上一条
func _resolve_swipe(dx: float) -> void:
	# 左滑（负位移）→ 下一条
	if dx <= -_SWIPE_THRESHOLD:
		_go_to(_cur + 1)
	# 右滑 → 上一条
	elif dx >= _SWIPE_THRESHOLD:
		_go_to(_cur - 1)


# 杀掉正在跑的 Tween
func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
