# 连击反馈视图：在棋盘上飘 COMBO 气泡与得分，并按 AB 配置切换跟猫/固定位置、语音与分数板形态
extends Control
class_name ComboFeedbackView

# ---- 场景与数值常量 ----
const SCORE_BUBBLE_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/level_flow_score.tscn"
)
const ENCOURAGE_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/level_encourage.tscn"
)

const IQ_BASELINE: int = 40 # IQ 模式的基础分（显示值 = 基础分 + 实际得分）
const BUBBLE_HEIGHT: float = 83.0 # 气泡高度（像素）
const BUBBLE_GAP: float = 10.0 # 气泡与猫之间的间隙（像素）
const CAT_TOP_UNSCALED: float = 40.0 # 未缩放的猫顶部偏移（像素）
const ENCOURAGE_Y_OFFSET_ABOVE_SCORE: float = 50.0 # 有分数板时鼓励再往上抬的偏移（像素）
const ENCOURAGE_HALF_WIDTHS: Array[float] = [ # 各连击等级鼓励动画的半宽（像素），用于左右夹取
	128.0,
	149.0,
	180.0,
	220.0,
	212.0,
	225.0,
]

# ---- 子节点与兄弟节点引用 ----
@onready var _combo_label: Label = $ComboLabel # COMBO 文字
var _board_view: Node # 棋盘视图
var _score_display: Control # 分数板
var _iq_display: Control # IQ 板
var _level_label: Label # 关卡号文本
var _level_display: Control # 关卡号面板
var _level_value_label: Label # 关卡号数值
var _hard_tag: Control # 困难标记
var _score_value_label: Label # 分数数值
var _iq_value_label: Label # IQ 数值

# ---- 运行时状态 ----
var _encourage_instance: Node2D = null # 当前在播的鼓励实例
var _displayed_score: int = 0 # 当前显示的分数（IQ 模式含基础分）
var _is_hard: bool = false # 本关是否困难


# ================= 生命周期 =================
# 进树：取兄弟节点引用，动态搭一个「困难」标记，并按 AB 决定分数板形态
func _ready() -> void:
	# 压在棋盘之上
	z_index = 10
	# 默认不显示 COMBO 文字
	_combo_label.visible = false
	# 兄弟节点只能运行时取
	_board_view = get_node_or_null("../BoardContainer/BoardView")
	_score_display = get_node_or_null("../Header/ScoreDisplay")
	_iq_display = get_node_or_null("../Header/IQDisplay")
	_level_label = get_node_or_null("../Header/LevelLabel") as Label
	_level_display = get_node_or_null("../Header/LevelDisplay")
	# 分数/IQ/关卡号的数值标签都在各自面板的 Value 下
	if _score_display != null:
		_score_value_label = _score_display.get_node("Value") as Label
	if _iq_display != null:
		_iq_value_label = _iq_display.get_node("Value") as Label
	if _level_display != null:
		_level_value_label = _level_display.get_node("Value") as Label
	# 动态搭一个「困难」标记（Header 里没有现成的）
	var header: Control = get_node_or_null("../Header")
	if header != null:
		_hard_tag = Control.new()
		_hard_tag.layout_mode = 1
		_hard_tag.anchor_top = 0.5
		_hard_tag.anchor_bottom = 0.5
		# 固定在 Header 右上角
		_hard_tag.offset_left = 685.0
		_hard_tag.offset_right = 835.0
		_hard_tag.offset_top = -72.0
		_hard_tag.offset_bottom = 46.0
		_hard_tag.visible = false
		# 只占位不接收输入
		_hard_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hard_tag.z_index = 10
		header.add_child(_hard_tag)
		# 图标
		var icon := TextureRect.new()
		icon.texture = load("res://assets/sprites/game/hard.png")
		icon.expand_mode = 1
		icon.stretch_mode = 5
		icon.layout_mode = 1
		icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		icon.offset_left = -22.0
		icon.offset_right = 22.0
		icon.offset_top = 14.0
		icon.offset_bottom = 62.0
		_hard_tag.add_child(icon)
		# 文案标签
		var lbl := Label.new()

		# 文案交给翻译表
		lbl.text = "GAME_HARD_TAG"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# 颜色/字号/字体都跟着关卡号数值标签走
		lbl.add_theme_color_override("font_color", Color(0.576, 0.353, 0.353, 1.0))
		lbl.add_theme_font_size_override("font_size", 58)
		if _level_value_label != null:
			lbl.add_theme_font_override("font", _level_value_label.get_theme_font("font"))
		# 贴在图标下方
		lbl.layout_mode = 1
		lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		lbl.offset_top = -60.0
		_hard_tag.add_child(lbl)
	# 按 AB 决定显示分数板还是 IQ 板
	_update_display_visibility()
	# IQ 模式从基础分起步
	if ABTestManager.combo_encourage.is_iq_mode():
		_displayed_score = IQ_BASELINE
	else:
		_displayed_score = 0
	_set_score_text_immediate(_displayed_score)


# ================= 对外展示接口 =================
# 显示一次连击反馈：鼓励动画 + 语音 +（可选）分数飘字
func show_combo(combo_count: int, cell_global_pos: Vector2, total_score: int, gain: int) -> void:
	# 这次要不要显示分数
	var has_score: bool = ABTestManager.combo_encourage.has_score_display()
	var base_off: float = _score_bubble_y_offset()
	# 鼓励动画是跟猫还是固定位置
	if ABTestManager.combo_encourage.is_follow_cat():
		if has_score:
			# 有分数板时再抬高一点，避免被气泡压住
			_show_encourage_at_position(
				combo_count, cell_global_pos, base_off + ENCOURAGE_Y_OFFSET_ABOVE_SCORE
			)
		else:
			_show_encourage_at_position(combo_count, cell_global_pos, base_off)
	else:
		_show_encourage_fixed(combo_count)
	# 语音反馈
	_play_combo_feedback_voice(combo_count)
	# 有分数板才更新分数与飘字
	if has_score:
		_update_score_label(total_score)
		_show_score_bubble(cell_global_pos, gain)


# 只显示连击文字与语音，不显示分数
func show_combo_text_only(combo_count: int, cell_global_pos: Vector2) -> void:
	if ABTestManager.combo_encourage.is_follow_cat():
		# 位置策略与 show_combo 一致，只是不弹分数
		var has_score: bool = ABTestManager.combo_encourage.has_score_display()
		var base_off: float = _score_bubble_y_offset()
		var y_off: float = base_off + ENCOURAGE_Y_OFFSET_ABOVE_SCORE if has_score else base_off
		_show_encourage_at_position(combo_count, cell_global_pos, y_off)
	else:
		_show_encourage_fixed(combo_count)
	_play_combo_feedback_voice(combo_count)


# 播连击语音：优先新的语音 AB，其次按鼓励配置
func _play_combo_feedback_voice(combo_count: int) -> void:
	# 优先新的连击语音 AB
	if ABTestManager.combo_voice.is_enabled():
		SoundManager.play_combo_voice_by_path(
			ABTestManager.combo_voice.get_combo_voice(combo_count)
		)
		return
	# 其次看鼓励配置要不要播语音
	if ABTestManager.combo_encourage.should_play_voice():
		SoundManager.play_combo_voice(combo_count, ABTestManager.combo_encourage.is_female_voice())


# 只更新分数与飘字（不显示连击）
func show_score_only(cell_global_pos: Vector2, gain: int, total_score: int) -> void:
	_update_score_label(total_score)
	_show_score_bubble(cell_global_pos, gain)


# 复位：清掉鼓励实例并按当前分数制重设显示值
func reset(initial_score: int = 0) -> void:
	_combo_label.visible = false
	# 清掉还在播的鼓励实例
	if _encourage_instance != null:
		_encourage_instance.queue_free()
		_encourage_instance = null
	_update_display_visibility()
	# IQ 模式把基础分算进去
	if ABTestManager.combo_encourage.is_iq_mode():
		_displayed_score = IQ_BASELINE + initial_score
	else:
		_displayed_score = initial_score
	_set_score_text_immediate(_displayed_score)


# ================= 内部实现 =================
# 固定位置的鼓励动画（屏幕中部）
func _show_encourage_fixed(combo_count: int) -> void:
	# 同一时刻只留一个鼓励实例
	_kill_encourage()
	var instance: Node2D = ENCOURAGE_SCENE.instantiate()
	add_child(instance)
	# 拿不到棋盘信息时的兜底 Y
	var board_top_y: float = 200.0
	if _board_view != null and _board_view is CanvasItem:
		board_top_y = (_board_view as CanvasItem).global_position.y - global_position.y
	# 摆在棋盘上沿与视图中线之间
	instance.position = Vector2(size.x * 0.5, board_top_y * 0.5 + 11)
	_play_encourage_anim(instance, combo_count, 1)


# 跟随格子的鼓励动画（会做左右边界夹取）
func _show_encourage_at_position(combo_count: int, global_pos: Vector2, y_offset: float) -> void:
	_kill_encourage()
	var instance: Node2D = ENCOURAGE_SCENE.instantiate()
	add_child(instance)
	var local_pos: Vector2 = global_pos - global_position
	# 半宽按连击等级查表，越高级动画越宽
	var level_idx: int = clampi(combo_count - 3, 0, 5)
	var half_w: float = ENCOURAGE_HALF_WIDTHS[level_idx]
	# 左右夹取，避免动画超出屏幕
	var clamped_x: float = clampf(local_pos.x, half_w, size.x - half_w)
	instance.position = Vector2(clamped_x, local_pos.y - y_offset)
	_play_encourage_anim(instance, combo_count, 2)


# 播放鼓励动画：按连击数选动画名，播完自毁
func _play_encourage_anim(instance: Node2D, combo_count: int, anim_set: int) -> void:
	_encourage_instance = instance
	# 连击数映射到 1~6 级动画
	var level: int = clampi(combo_count - 2, 1, 6)
	# 命名约定：Encourage{套号}_{等级}
	var anim_name: String = "Encourage%02d_%d" % [anim_set, level]
	var anim: AnimationPlayer = instance.get_node("AnimationPlayer")
	anim.play(anim_name)
	# 播完自毁并清引用
	anim.animation_finished.connect(
		func(_name: StringName) -> void:
			instance.queue_free()
			if _encourage_instance == instance:
				_encourage_instance = null
	)


# 杀掉当前鼓励实例
func _kill_encourage() -> void:
	if _encourage_instance != null:
		_encourage_instance.queue_free()
		_encourage_instance = null


# ================= 分数与布局 =================
# 分数气泡的垂直偏移：气泡高 + 间隙 + 猫顶偏移（含棋盘缩放）
func _score_bubble_y_offset() -> float:
	var board_scale: float = _board_view.scale.x if _board_view != null else 1.0
	return BUBBLE_HEIGHT + BUBBLE_GAP + CAT_TOP_UNSCALED * board_scale


# 弹一个得分气泡（+N）
func _show_score_bubble(global_pos: Vector2, gain: int) -> void:
	var bubble: LevelFlowScore = SCORE_BUBBLE_SCENE.instantiate()
	add_child(bubble)
	# 先填分数（同时决定气泡宽度）
	bubble.set_score(gain)
	bubble.position = (
		global_pos - global_position - Vector2(bubble.size.x * 0.5, _score_bubble_y_offset())
	)
	# 播完自毁
	var anim: AnimationPlayer = bubble.get_node("AnimationPlayer")
	anim.play("Appear")
	anim.animation_finished.connect(func(_name: StringName) -> void: bubble.queue_free())


# 设置是否困难（影响分数板布局）
func set_hard(is_hard: bool) -> void:
	_is_hard = is_hard
	_update_display_visibility()


# 按 AB 配置刷新分数板/IQ 板/关卡号的显隐与横向位置
func _update_display_visibility() -> void:
	var has_score: bool = ABTestManager.combo_encourage.has_score_display()
	var is_iq: bool = ABTestManager.combo_encourage.is_iq_mode()
	if _score_display != null:
		_score_display.visible = has_score and not is_iq
	if _iq_display != null:
		_iq_display.visible = has_score and is_iq
	if _level_label != null:
		_level_label.visible = not has_score
	if _level_display != null:
		_level_display.visible = has_score
	if _hard_tag != null:
		_hard_tag.visible = has_score and _is_hard
	# 困难且显示分数时是三列布局，位置要重排
	var three_cols: bool = has_score and _is_hard
	if _level_display != null:
		_level_display.offset_left = 245.0 if three_cols else 302.0
		_level_display.offset_right = 395.0 if three_cols else 502.0
	# 分数面板横坐标跟着布局走
	var score_node: Control = _iq_display if is_iq else _score_display
	if score_node != null:
		score_node.offset_left = -615.0 if three_cols else -502.0
		score_node.offset_right = -465.0 if three_cols else -302.0


# 设置关卡号
func set_level(level_num: int) -> void:
	if _level_value_label != null:
		_level_value_label.text = "%d" % level_num


# 立即设置分数文本（不走滚动动画）
func _set_score_text_immediate(value: int) -> void:
	# IQ 模式写 IQ 板，否则写分数板
	if ABTestManager.combo_encourage.is_iq_mode():
		if _iq_value_label != null:
			_iq_value_label.text = "%d" % value
	else:
		if _score_value_label != null:
			_score_value_label.text = "%d" % value


# 更新分数：按模式换算目标值并滚动过去
func _update_score_label(total_score: int) -> void:
	var target: int
	# 目标值按模式换算（IQ 含基础分）
	if ABTestManager.combo_encourage.is_iq_mode():
		target = IQ_BASELINE + total_score
		if _iq_value_label != null:
			# 0.35 秒滚动到目标值
			RollingNumber.roll(_iq_value_label, _displayed_score, target, 0.35)
	else:
		target = total_score
		if _score_value_label != null:
			# 0.35 秒滚动到目标值
			RollingNumber.roll(_score_value_label, _displayed_score, target, 0.35)
	_displayed_score = target
