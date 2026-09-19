# 新手教学页（注册名 UiName.TUTORIAL）：用一局 4×4 教学关把「放猫 / 打叉 / 滑动排除」演给玩家
# 步骤数据来自题库 SP 里 pattern == "guide" 的那一关；走完最后一步 = 写存档标记 + 直接进正式对局第 1 关
class_name TutorialPage
extends UIFrameWindow

# 遮罩层用的临时格子场景：遮罩压暗整盘时，提示格靠它保持亮色
const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn")

# 教学关答案（行 → 列），与题库 solution 一致，用于自由阶段的通关判定
const TUTORIAL_SOLUTION: Array[Vector2i] = [
	Vector2i(0, 2),
	Vector2i(1, 0),
	Vector2i(2, 3),
	Vector2i(3, 1),
]

# ---- 教学关卡数据（从题库 SP 的 guide 关读入） ----
var _guide_regions: Array = [] # 4×4 区域编号表，决定每格属于哪个颜色区
var _guide_color_map: Array[int] = [] # 区域编号 → 调色板下标的映射

@onready var _board_view: BoardView = $Root/BoardContainer/BoardView
@onready var _board_container: Control = $Root/BoardContainer
@onready var _success_check: Control = $Root/BoardContainer/SuccessCheck
@onready var _select_frame: Panel = $Root/BoardContainer/HighlightOverlay/SelectFrame
@onready var _msg_panel: Panel = $Root/MessagePanel
@onready var _msg_rich: RichTextLabel = $Root/MessagePanel/MsgRich
@onready var _sub_msg_panel: Panel = $Root/SubMsgPanel
@onready var _sub_msg_rich: RichTextLabel = $Root/SubMsgPanel/SubMsgRich
@onready var _hint_tool_panel: Panel = $Root/HintToolPanel
@onready var _hint_label: RichTextLabel = $Root/HintToolPanel/HintLabel
@onready var _confirm_btn: Button = $Root/ConfirmBtn
@onready var _hand_hint: Control = $Root/HandHint
@onready var _hand_spine: SpineSprite = $Root/HandHint/ui_guide_hand
@onready var _hand_static: TextureRect = $Root/HandHint/HandStatic
@onready var _mask_layer: Control = $Root/MaskLayer
@onready var _iq_bar: Control = $Root/IqBar
@onready var _iq_fill: Panel = $Root/IqBar/BarFill
@onready var _iq_label: Label = $Root/IqBar/IqLabel
@onready var _anim_msg_appear_2: AnimationPlayer = $MessagePanel_appear_2
@onready var _anim_confirm_loop: AnimationPlayer = $ConfirmBtn_loop
@onready var _anim_sub_msg_appear: AnimationPlayer = $SubMsgPanel_appear
@onready var _anim_hint_tool_appear: AnimationPlayer = $HintToolPanel_appear
@onready var _anim_guide_encourage: AnimationPlayer = $GuideEncourage
@onready var _anim_effect_iq_bar: AnimationPlayer = $EffectIqBar
@onready var _anim_effect_fireworks: AnimationPlayer = $EffectFlreworks

# ---- 步骤模式与内部信号 ----
enum StepMode { NONE, PLACE_CAT, MARK_CELLS, FREE_PLAY, CONFIRM } # NONE 无 / PLACE_CAT 放猫 / MARK_CELLS 打叉 / FREE_PLAY 自由玩 / CONFIRM 等按钮

signal _step_completed # 仅本页内部使用，不对外广播

# ---- 流程控制（步骤协程 + 防重入令牌） ----
var _flow_token: int = 0 # 每次 on_show 自增；旧协程发现 token 变了就退出

var _current_mode: int = StepMode.NONE # 当前步骤模式，决定输入怎么解释
var _allowed_cells: Array[Vector2i] = [] # 当前步骤允许操作的格子白名单
var _required_marks: int = 0 # 这一步需要打的叉数
var _marked_count: int = 0 # 已经打好的叉数

var _step7_hint_phase: int = 0 # 第 7 步提示阶段：0 未点提示 / 1 排除蓝行 / 2 排除粉行 / 3 落最后一猫

var _mask_hint_cells: Dictionary = {} # 遮罩层上的提示格：格子坐标 → 临时 CellView
var _mask_tween: Tween = null # 遮罩淡入淡出用的补间

# ---- 手势状态（拖拽与连点） ----
var _drag_start_cell: Vector2i = Vector2i(-1, -1) # 本次拖拽的起点（行, 列），(-1,-1) 表示没有拖拽
var _drag_had_move: bool = false # 本次拖拽是否移动过（移动过就不算单击）

var _drag_target_state: int = CellState.MARK # 拖拽时要写入的状态：MARK 打叉 或 EMPTY 擦除
var _last_tap_cell: Vector2i = Vector2i(-1, -1) # 上一次单击的格子，用于识别「连点两次」

var _swipe_hand_tween: Tween = null # 滑动打叉手势的循环补间

# ---- 埋点与布局测量 ----
var _guide_start_ms: int = 0 # on_show 的时刻（毫秒），用于统计教学耗时

var _msg_to_board_gap: float = 0.0 # 消息面板与棋盘之间的初始间距（像素）

# ---- 数值常量：消息面板与 IQ 条 ----
const _MSG_PANEL_PADDING_Y: float = 40.0 # 消息面板上下各留的内边距（像素）

const IQ_INIT: int = 60 # IQ 初始值
const IQ_MAX: int = 180 # IQ 上限
const IQ_STEP: int = 20 # 每次反馈增加的 IQ（点）

const _IQ_BAR_PAD: float = 0.0 # 进度条起点偏移（像素，0 = 从最左开始）
const _IQ_BAR_INNER_W: float = 592.0 # 进度条可填充宽度（像素）
var _iq_value: int = IQ_INIT # 当前 IQ 值，只有 iq 分组流程用得到


# ================= 生命周期与三条流程 =================
# 建连：棋盘拖拽三个信号、提示条点击、消息框尺寸变化，并量一次消息面板与棋盘的初始间距
func _ready() -> void:
	_board_view.cell_drag_start.connect(_on_board_cell_drag_start)
	_board_view.cell_drag_over.connect(_on_board_cell_drag_over)
	_board_view.cell_drag_end.connect(_on_board_cell_drag_end)

	_hint_tool_panel.gui_input.connect(_on_hint_tool_panel_gui_input)

	_msg_rich.resized.connect(_on_msg_rich_resized)

	_msg_to_board_gap = _board_container.offset_top - _msg_panel.offset_bottom # 记下初始间距，供 _align_msg_panel_to_board 复用


# 每次打开本页：复位 UI 与棋盘，再按 A/B 分组跑三条流程之一（默认 / check / iq）
func on_show(_params: Dictionary = {}) -> void:
	_flow_token += 1 # 让上一轮没跑完的步骤协程失效

	_step_completed.emit() # 先放掉上一轮可能还挂着的 await
	_current_mode = StepMode.NONE
	_last_tap_cell = Vector2i(-1, -1)
	_drag_start_cell = Vector2i(-1, -1)
	_drag_had_move = false
	_reset_ui()
	_setup_board()

	# 等布局结算完再把消息面板对齐到棋盘
	call_deferred("_align_msg_panel_to_board")

	_guide_start_ms = Time.get_ticks_msec()
	Tracker.track_new_guide_show(1) # 埋点：教学页展示（关卡号固定 1）

	# 三条流程共用同一批步骤函数，区别只在每步之后的反馈方式
	if ABTestManager.guide_feedback.is_check_guide():
		await _run_guide_flow_check()
	elif ABTestManager.guide_feedback.is_iq_guide():
		await _run_guide_flow_iq()
	else:
		await _run_guide_flow_default()


# 默认流程：7 个步骤顺序 await，每步完成后埋一次进度点
func _run_guide_flow_default() -> void:
	var _tok: int = _flow_token # 本轮令牌，下面每步都校验
	await _step_1_place_first_cat()
	# token 变了说明页面被重开过，旧协程立刻收手（下面每步都做同样的检查）
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(1)
	await _step_2_confirm_one_per_color()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(2)
	await _step_3_mark_row_col()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(3)
	await _step_4_place_second_cat()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(4)
	await _step_5_mark_neighbors()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(5)
	await _step_6_place_third_cat()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(6)
	await _step_7_free_play()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(7)
	await _step_finish()


# check 分组流程：步骤相同，但去掉「每色一只」确认步，改成每步播一次成功反馈动画
func _run_guide_flow_check() -> void:
	var _tok: int = _flow_token
	await _step_1_place_first_cat(_step1_feedback_combined_msg())
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(1)
	await _play_check_feedback()
	if _flow_token != _tok:
		return
	await _step_3_mark_row_col()
	if _flow_token != _tok:
		return
	# check / iq 流程少了确认步，所以步骤号比默认流程少 1
	Tracker.track_new_guide_step(2)
	await _play_check_feedback()
	if _flow_token != _tok:
		return
	await _step_4_place_second_cat()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(3)
	await _play_check_feedback()
	if _flow_token != _tok:
		return
	await _step_5_mark_neighbors()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(4)
	await _play_check_feedback()
	if _flow_token != _tok:
		return
	await _step_6_place_third_cat()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(5)
	await _play_check_feedback()
	if _flow_token != _tok:
		return
	await _step_7_free_play()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(6)
	await _play_check_feedback()
	if _flow_token != _tok:
		return
	await _step_finish()


# check 分组的步骤反馈：播一次成功勾选动画并等它播完
func _play_check_feedback() -> void:
	_anim_guide_encourage.play("SuccessCheck")
	await _anim_guide_encourage.animation_finished


# iq 分组流程：与 check 相同，只是把成功反馈换成 IQ 进度条上涨
func _run_guide_flow_iq() -> void:
	var _tok: int = _flow_token
	_init_iq_bar()
	await _step_1_place_first_cat(_step1_feedback_combined_msg())
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(1)
	await _play_iq_feedback()
	if _flow_token != _tok:
		return
	await _step_3_mark_row_col()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(2)
	await _play_iq_feedback()
	if _flow_token != _tok:
		return
	await _step_4_place_second_cat()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(3)
	await _play_iq_feedback()
	if _flow_token != _tok:
		return
	await _step_5_mark_neighbors()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(4)
	await _play_iq_feedback()
	if _flow_token != _tok:
		return
	await _step_6_place_third_cat()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(5)
	await _play_iq_feedback()
	if _flow_token != _tok:
		return
	await _step_7_free_play()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(6)
	await _play_iq_feedback()
	if _flow_token != _tok:
		return
	await _step_finish(true)


# 初始化 IQ 条：数值回到初始、显示进度条并播出现动画
func _init_iq_bar() -> void:
	_iq_value = IQ_INIT
	_set_iq_fill_right(_iq_fill_right(float(IQ_INIT)))
	_set_iq_number(float(IQ_INIT))
	_iq_bar.visible = true
	_anim_guide_encourage.play("IqBarAppear")


# 播 IQ 条消失动画，播完隐藏
func _play_iq_disappear() -> void:
	_anim_guide_encourage.play("IqBarDisAppear")
	await _anim_guide_encourage.animation_finished
	_iq_bar.visible = false


# 一次 IQ 反馈：数值加一档（封顶），进度条与数字同步补间 0.4 秒
func _play_iq_feedback() -> void:
	var old_v: int = _iq_value
	var new_v: int = min(old_v + IQ_STEP, IQ_MAX)
	_iq_value = new_v

	_anim_effect_iq_bar.play("EffectIqBar02" if new_v >= IQ_MAX else "EffectIqBar01")
	var grow := create_tween()
	grow.set_parallel(true)
	(
		grow
		. tween_method(
			_set_iq_fill_right, _iq_fill_right(float(old_v)), _iq_fill_right(float(new_v)), 0.4
		)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	grow.tween_method(_set_iq_number, float(old_v), float(new_v), 0.4)
	await grow.finished


# 把 IQ 数值换算成进度条右边界坐标（像素）
func _iq_fill_right(v: float) -> float:
	var frac: float = clampf(v / float(IQ_MAX), 0.0, 1.0)
	return _IQ_BAR_PAD + frac * _IQ_BAR_INNER_W


# 补间回调：写进度条填充宽度
func _set_iq_fill_right(x: float) -> void:
	_iq_fill.offset_right = x


# 补间回调：把 IQ 数值写进本地化格式文本
func _set_iq_number(v: float) -> void:
	_iq_label.text = tr("TUTORIAL_IQ_FORMAT") % int(round(v))


# 从题库 SP 列表里挑出 pattern == "guide" 的教学关，铺到 BoardView，再把所有格子清空
func _setup_board() -> void:
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP
	var sp_levels: Array = BankData.get_sp_levels()
	var guide_entry: Dictionary = {}
	for e in sp_levels:
		if e.get("pattern", "") == "guide":
			guide_entry = e
			break
	if guide_entry.is_empty():
		push_error("TutorialPage: SP guide 关卡未找到")
		return
	_guide_regions = []
	for row in guide_entry.get("regionMap", []):
		var int_row: Array = []
		for v in row:
			int_row.append(int(v))
		_guide_regions.append(int_row)
	_guide_color_map.clear()
	for v in guide_entry.get("colorMap", []):
		_guide_color_map.append(int(v))
	_board_view.setup(4, _guide_regions, _guide_color_map)

	# 清掉场景里预置的格子状态，教学固定从空盘开始
	for r in range(4):
		for c in range(4):
			var cv: CellView = _board_view.get_cell_view(r, c)
			if cv != null and cv.get_state() != CellState.EMPTY:
				cv.change_state({"state": CellState.EMPTY, "play_anim": false})


# ================= 教学步骤（按顺序 await） =================
# 拼第 1 步的操作指引富文本：给关键词加呼吸高亮
func _step1_rich_action_line() -> String:
	var hl: String = tr("TUTORIAL_STEP1_HIGHLIGHT")
	var breath_seg: String = (
		"[breath amp=0.03 freq=5 group=1 count=%d][color=#d94848]%s[/color][/breath]"
		% [hl.length(), hl]
	)
	return tr("TUTORIAL_STEP1_RICH").format({"breath": breath_seg})


# 第 1 步的合并文案：规则说明 + 操作指引（check / iq 分组用）
func _step1_feedback_combined_msg() -> String:
	return tr("TUTORIAL_STEP1_ONE_PER_COLOR") + "\n" + _step1_rich_action_line()


# 第 1 步：只允许点 (0,2) 放第一只猫（双击），完成后收起手势与遮罩
func _step_1_place_first_cat(override_msg: String = "") -> void:
	if override_msg != "":
		_show_message("[center]" + override_msg + "[/center]")
	else:
		_show_message("[center]" + _step1_rich_action_line() + "[/center]")
	var target := Vector2i(0, 2) # 目标格（行, 列）
	_allowed_cells = [target]
	_show_mask_hints([target])
	_position_hand_at_cell(target)
	_show_hand()
	# 切到放猫模式后挂起，等 _step_completed 信号
	_current_mode = StepMode.PLACE_CAT
	await _step_completed
	_current_mode = StepMode.NONE
	_hide_hand()
	_clear_mask_hint_cells()
	_fade_out_mask_layer()
	await get_tree().create_timer(0.4).timeout


# 第 2 步：纯文字确认「每色一只」，点「我知道了」才继续
func _step_2_confirm_one_per_color() -> void:
	_show_message("[center]" + tr("TUTORIAL_STEP2_RICH") + "[/center]")
	_show_confirm_btn(tr("TUTORIAL_GOT_IT"))
	_current_mode = StepMode.CONFIRM
	await _step_completed
	_current_mode = StepMode.NONE
	_hide_confirm_btn()


# 第 3 步：手动打掉 6 个同行同列的排除格，全打完才算过
func _step_3_mark_row_col() -> void:
	# 文案 key 沿用 TUTORIAL_STEP5_RICH（历史命名，与步骤号不对应）
	_show_message("[center]" + tr("TUTORIAL_STEP5_RICH") + "[/center]")

	# 这 6 格 = 第一只猫所在的行与列
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(0, 1),
		Vector2i(0, 3),
		Vector2i(1, 2),
		Vector2i(2, 2),
		Vector2i(3, 2),
	]
	_allowed_cells = cells
	_required_marks = cells.size()
	_marked_count = 0

	_show_mask_hints(cells, [Vector2i(0, 2)])
	_move_sub_msg_below_board()
	_show_sub_message("[center]" + tr("TUTORIAL_SUB_EXCLUDE") + "[/center]")
	_current_mode = StepMode.MARK_CELLS
	await _step_completed
	_current_mode = StepMode.NONE
	_hide_sub_message()
	await get_tree().create_timer(0.4).timeout


# 第 4 步：在 (3,1) 放第二只猫；文案按 A/B 分组给真实颜色名或写死的「粉色」
func _step_4_place_second_cat() -> void:
	var _pink_msg: String
	if not ABTestManager.region_color.value() == RegionColorConfig.VALUE_CONTROL:
		var _cbb: String = _color_name_bbcode_for_cell(3, 1)
		_pink_msg = tr("TUTORIAL_STEP4_COLOR_RICH") % _cbb
	else:
		_pink_msg = tr("TUTORIAL_STEP4_PINK_RICH")
	_show_message("[center]" + _pink_msg + "[/center]")
	var target := Vector2i(3, 1) # 目标格（行, 列）

	var hint_cells: Array[Vector2i] = [target]
	var mirror_cells: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2)]
	_allowed_cells = [target]
	_clear_mask_hint_cells()
	_show_mask_hints(hint_cells, mirror_cells)
	_position_hand_at_cell(target)
	_show_hand()
	_current_mode = StepMode.PLACE_CAT
	await _step_completed
	_current_mode = StepMode.NONE
	_hide_hand()
	_clear_mask_hint_cells()
	_fade_out_mask_layer()
	await get_tree().create_timer(0.4).timeout


# 第 5 步：一次滑动打掉 3 个八邻接格，文案与手势在两种 A/B 版本间切换
func _step_5_mark_neighbors() -> void:
	var step3_key: String = (
		"TUTORIAL_STEP3_RICH_DIAGONAL"
		if ABTestManager.tutorial_diagonal.is_diagonal_copy()
		else "TUTORIAL_STEP3_RICH"
	)
	_show_message("[center]" + tr(step3_key) + "[/center]")

	var cells: Array[Vector2i] = [
		Vector2i(2, 0),
		Vector2i(2, 1),
		Vector2i(3, 0),
	]
	_allowed_cells = cells
	_required_marks = cells.size()
	_marked_count = 0

	_show_mask_hints(cells, [Vector2i(3, 1)])
	_move_sub_msg_below_board()
	_show_sub_message("[center]" + tr("TUTORIAL_SUB_SWIPE_EXCLUDE") + "[/center]")

	_start_swipe_hand_loop([Vector2i(3, 0), Vector2i(2, 0), Vector2i(2, 1)])
	_current_mode = StepMode.MARK_CELLS
	await _step_completed
	_current_mode = StepMode.NONE
	_stop_swipe_hand_loop()
	_hide_hand()
	_hide_sub_message()
	await get_tree().create_timer(0.4).timeout


# 第 6 步：在 (1,0) 放第三只猫
func _step_6_place_third_cat() -> void:
	var _blue_msg: String
	if not ABTestManager.region_color.value() == RegionColorConfig.VALUE_CONTROL:
		var _cbb: String = _color_name_bbcode_for_cell(1, 0)
		_blue_msg = tr("TUTORIAL_STEP4_COLOR_RICH") % _cbb
	else:
		_blue_msg = tr("TUTORIAL_STEP4_BLUE_RICH")
	_show_message("[center]" + _blue_msg + "[/center]")
	var target := Vector2i(1, 0) # 目标格（行, 列）

	var hint_cells: Array[Vector2i] = [target]
	var mirror_cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(2, 0),
		Vector2i(2, 1),
		Vector2i(3, 0),
	]
	_allowed_cells = [target]
	_clear_mask_hint_cells()
	_show_mask_hints(hint_cells, mirror_cells)
	_position_hand_at_cell(target)
	_show_hand()
	_current_mode = StepMode.PLACE_CAT
	await _step_completed
	_current_mode = StepMode.NONE
	_hide_hand()
	_clear_mask_hint_cells()
	_fade_out_mask_layer()
	await get_tree().create_timer(0.4).timeout


# 第 7 步：只剩一格，交给玩家自由点；提示按钮可用，摆完即通关
func _step_7_free_play() -> void:
	_show_message("[center]" + tr("TUTORIAL_LAST_ONE_RICH") + "[/center]")
	# 整个教学只剩这一格可点
	_allowed_cells = [Vector2i(2, 3)]
	_step7_hint_phase = 0
	_hint_label.text = tr("TUTORIAL_STEP7_HINT") # 提示按钮上的文案
	_show_hint_tool_panel()

	_board_view.clear_hint_cells()
	_current_mode = StepMode.FREE_PLAY
	await _step_completed
	_current_mode = StepMode.NONE
	_board_view.clear_hint_cells()
	_hide_hand()
	_clear_mask_hint_cells()
	if _mask_layer.visible:
		_fade_out_mask_layer()
	_hide_hint_tool_panel()
	await get_tree().create_timer(0.5).timeout


# 第 7 步的提示按钮：分三层升级——先排除蓝猫那行、再排除粉猫那行、最后直接代打答案
func _step7_show_hint() -> void:
	if _step7_hint_phase > 0:
		_apply_step7_hint()
		return

	# 棋盘上已有的两只猫与最终的目标格
	const BLUE_CAT := Vector2i(1, 0)
	const PINK_CAT := Vector2i(3, 1)
	const TARGET := Vector2i(2, 3)
	const SZ := 4

	var blue_row_empty: Array[Vector2i] = []
	for c in range(SZ):
		if c != BLUE_CAT.y and CellState.is_blank(_board_view.get_cell_state(BLUE_CAT.x, c)):
			blue_row_empty.append(Vector2i(BLUE_CAT.x, c))

	var pink_row_empty: Array[Vector2i] = []
	for c in range(SZ):
		if c != PINK_CAT.y and CellState.is_blank(_board_view.get_cell_state(PINK_CAT.x, c)):
			pink_row_empty.append(Vector2i(PINK_CAT.x, c))

	# 第一次点提示：先收掉手势与遮罩
	_hide_hand()
	_clear_mask_hint_cells()
	if _mask_layer.visible:
		_fade_out_mask_layer()
	_allowed_cells = [TARGET]

	# 第一层提示：蓝猫所在行还有空格 → 让玩家先把这一行排除掉
	if blue_row_empty.size() > 0:
		_step7_hint_phase = 1
		_allowed_cells = blue_row_empty
		_show_message("[center]" + tr("TUTORIAL_STEP7_ROW_BLUE") + "[/center]")
		_show_mask_hints(blue_row_empty, [BLUE_CAT])
	# 第二层：蓝行排除完，轮到粉猫所在行
	elif pink_row_empty.size() > 0:
		_step7_hint_phase = 2
		_allowed_cells = pink_row_empty
		_show_message("[center]" + tr("TUTORIAL_STEP7_ROW_PINK") + "[/center]")
		_show_mask_hints(pink_row_empty, [PINK_CAT])
	# 第三层：两行都排除完，只剩 (2,3)，直接示范落猫
	else:
		_step7_hint_phase = 3
		_allowed_cells = [TARGET]
		_show_message("[center]" + tr("TUTORIAL_STEP7_PLACE_LAST") + "[/center]")
		_show_mask_hints([TARGET])
		_position_hand_at_cell(TARGET)
		_show_hand()


# 收尾步：显示结束文案与「开始游戏」按钮，确认后调 complete_tutorial()
func _step_finish(use_fireworks: bool = false) -> void:
	_show_message("[center]" + tr("TUTORIAL_STEP6_RICH") + "[/center]")
	_show_confirm_btn(tr("TUTORIAL_START_GAME")) # 按钮文案：开始游戏

	# iq 分组走烟花结局，其余分组撒彩带
	if use_fireworks:
		_anim_effect_fireworks.play("Flreworks")

		# 烟花播完再收 IQ 条
		_hide_iq_bar_after_fireworks()
	else:
		_spawn_confetti()
	_current_mode = StepMode.CONFIRM
	await _step_completed
	_current_mode = StepMode.NONE
	complete_tutorial()


# 烟花动画播完后再收起 IQ 条（只有 iq 分组走这条路）
func _hide_iq_bar_after_fireworks() -> void:
	await _anim_effect_fireworks.animation_finished
	await _play_iq_disappear()


# 教学完成：上报耗时、写存档标记，然后跳转正式对局第 1 关
func complete_tutorial() -> void:
	# 从 on_show 记下的时刻算起（秒）
	var time_sec: float = (Time.get_ticks_msec() - _guide_start_ms) / 1000.0
	Tracker.track_new_guide_end(1, time_sec)
	# 写存档标记：下次启动不再进教学
	GameState.set_tutorial_done(true)
	# 切到正式对局页，从第 1 关开始
	UIManager.show_ui(UiName.GAME, {"level_index": 1})


# ================= UI 显示与隐藏 =================
# 把所有临时 UI（面板 / 手势 / 遮罩 / IQ 条）复位成初始的不可见状态
func _reset_ui() -> void:
	_sub_msg_panel.visible = false
	_hint_tool_panel.visible = false
	_confirm_btn.visible = false
	_anim_confirm_loop.stop()
	_hand_hint.visible = false
	_select_frame.visible = false
	_success_check.visible = false
	_iq_bar.visible = false
	_mask_layer.visible = false
	_mask_layer.modulate.a = 1.0


# 显示主提示文案并播出现动画
func _show_message(text: String) -> void:
	_msg_rich.text = text
	_anim_msg_appear_2.play("MessagePanel_appear_2")


# 显示棋盘下方的副提示并播出现动画
func _show_sub_message(text: String) -> void:
	_sub_msg_rich.text = text
	_sub_msg_panel.visible = true
	_anim_sub_msg_appear.play("SubMsgPanel_appear")


# 隐藏副提示
func _hide_sub_message() -> void:
	_sub_msg_panel.visible = false


# 显示第 7 步的提示工具条并播出现动画
func _show_hint_tool_panel() -> void:
	_hint_tool_panel.visible = true
	_anim_hint_tool_appear.play("HintToolPanel_appear")


# 隐藏提示工具条
func _hide_hint_tool_panel() -> void:
	_hint_tool_panel.visible = false


# 显示确认按钮、写入按钮文案并播呼吸动画
func _show_confirm_btn(text: String) -> void:
	_confirm_btn.set("btn_text", text)
	_confirm_btn.visible = true
	_anim_confirm_loop.play("ConfirmBtn_loop")


# 隐藏确认按钮并停掉呼吸动画
func _hide_confirm_btn() -> void:
	_confirm_btn.visible = false
	_anim_confirm_loop.stop()


# 显示手势提示，并让 Spine 手播 click 动画
func _show_hand() -> void:
	_hand_hint.visible = true
	_hand_spine.get_animation_state().set_animation("click", true, 0)


# 隐藏手势提示
func _hide_hand() -> void:
	_hand_hint.visible = false


# ================= 手势与遮罩提示 =================
# 把选中框对准某格（按 BoardView 缩放换算）；本文件内没有调用点
func _position_select_frame(cell: Vector2i) -> void:
	var s: float = _board_view.scale.x
	var rect: Rect2 = _board_view.cell_to_local_rect(cell.x, cell.y)
	var pad: float = 8.0
	_select_frame.position = rect.position * s - Vector2(pad, pad)
	_select_frame.size = rect.size * s + Vector2(pad * 2.0, pad * 2.0)


# 把手势提示挪到指定格：以基准格 (0,2) 的偏移为起点，按格宽逐格累加
func _position_hand_at_cell(cell: Vector2i) -> void:
	const BASE_ROW: int = 0
	const BASE_COL: int = 2
	const BASE_OFFSET_LEFT: float = 111.0
	const BASE_OFFSET_TOP: float = -316.0
	var s: float = _board_view.scale.x
	var slot_screen: float = BoardView.SLOT_PX * s
	var d_col: float = (cell.y - BASE_COL) * slot_screen
	var d_row: float = (cell.x - BASE_ROW) * slot_screen
	_hand_hint.offset_left = BASE_OFFSET_LEFT + d_col
	_hand_hint.offset_top = BASE_OFFSET_TOP + d_row
	_hand_hint.offset_right = _hand_hint.offset_left + 110.0
	_hand_hint.offset_bottom = _hand_hint.offset_top + 120.0


# 循环播「滑动打叉」手势：沿给定格子依次平移，最后淡出并从头再来
func _start_swipe_hand_loop(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	_stop_swipe_hand_loop()
	_position_hand_at_cell(cells[0])
	_hand_hint.visible = true
	_hand_hint.modulate.a = 1.0

	_hand_spine.visible = false
	_hand_static.visible = true
	var s: float = _board_view.scale.x
	var slot_screen: float = BoardView.SLOT_PX * s

	var offsets: Array[Vector2] = []
	# 逐格算出目标偏移（基准格 (0,2) 的手势位置）
	for cell in cells:
		offsets.append(
			Vector2(111.0 + (cell.y - 2) * slot_screen, -316.0 + (cell.x - 0) * slot_screen)
		)
	# 建一条无限循环的时间轴
	var tw := create_tween()
	tw.set_loops() # 无限循环

	# 每段：复位到起点 → 平移 → 停顿，循环播放
	var off0: Vector2 = offsets[0]
	tw.tween_callback(
		func() -> void:
			_hand_hint.offset_left = off0.x
			_hand_hint.offset_top = off0.y
			_hand_hint.offset_right = off0.x + 110.0
			_hand_hint.offset_bottom = off0.y + 120.0
			_hand_hint.modulate.a = 1.0
	)
	tw.tween_interval(0.15)

	for i in range(1, offsets.size()):
		var seg_from: Vector2 = offsets[i - 1]
		var seg_to: Vector2 = offsets[i]
		var move_fn: Callable = func(t: float, f: Vector2, d: Vector2) -> void:
			var lerped: Vector2 = f.lerp(d, t)
			_hand_hint.offset_left = lerped.x
			_hand_hint.offset_top = lerped.y
			_hand_hint.offset_right = lerped.x + 110.0
			_hand_hint.offset_bottom = lerped.y + 120.0
		tw.tween_method(move_fn.bind(seg_from, seg_to), 0.0, 1.0, 0.3)
		tw.tween_interval(0.1)

	tw.tween_interval(0.15)
	# 一轮结束：渐隐 + 停顿，循环时由第 0 步复位
	tw.tween_property(_hand_hint, "modulate:a", 0.0, 0.2)
	tw.tween_interval(0.35)
	_swipe_hand_tween = tw # 存下来，_stop_swipe_hand_loop 要 kill 它


# 停掉滑动手势补间，并把静态手图换回 Spine 手
func _stop_swipe_hand_loop() -> void:
	if _swipe_hand_tween != null and _swipe_hand_tween.is_valid():
		_swipe_hand_tween.kill()
	_swipe_hand_tween = null
	_hand_hint.modulate.a = 1.0
	_hand_static.visible = false
	_hand_spine.visible = true


# 把副提示面板移到棋盘正下方（先等一帧，等布局结算完）
func _move_sub_msg_below_board() -> void:
	await get_tree().process_frame
	var board_bottom: float = _board_container.position.y + _board_container.size.y
	var screen_center_y: float = size.y * 0.5
	var offset_top: float = board_bottom - screen_center_y + 30.0
	_sub_msg_panel.offset_top = offset_top
	_sub_msg_panel.offset_bottom = offset_top + 190.0


# 在遮罩层点亮提示格 cells，并铺出已填好的镜像格 mirror_cells；同时清掉棋盘自带的用法提示
func _show_mask_hints(cells: Array[Vector2i], mirror_cells: Array[Vector2i] = []) -> void:
	for cell in cells:
		_spawn_mask_hint_cell(cell)
	for cell in mirror_cells:
		_spawn_mask_mirror_cell(cell)

	# 提示格改由遮罩层自己画
	_board_view.clear_hint_cells()
	if not _mask_layer.visible:
		_fade_in_mask_layer()


# 复制一个格子到遮罩层：同步位置、缩放、圆角与区域色，并登记进 _mask_hint_cells
func _instantiate_mask_temp(cell: Vector2i) -> CellView:
	var s: float = _board_view.scale.x
	var local_rect: Rect2 = _board_view.cell_to_local_rect(cell.x, cell.y)
	var top_left: Vector2 = _board_container.position + local_rect.position * s

	var src: CellView = _board_view.get_cell_view(cell.x, cell.y)
	var temp: CellView = _CELL_SCENE.instantiate() as CellView

	# 位置与缩放都按棋盘缩放换算，保证和棋盘上的格子像素对齐
	temp.pivot_offset_ratio = Vector2.ZERO
	temp.pivot_offset = Vector2.ZERO
	temp.position = top_left
	temp.scale = Vector2(s, s)

	# 遮罩格只做展示，不吃输入
	temp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask_layer.add_child(temp)

	temp.set_corner_radius_compensated(s)
	if src != null:
		temp.set_region_color(src.get_region_color())
	_mask_hint_cells[cell] = temp # 登记，之后同步状态或统一释放
	return temp


# 铺一个带「提示闪烁」动画的遮罩格
func _spawn_mask_hint_cell(cell: Vector2i) -> void:
	var temp: CellView = _instantiate_mask_temp(cell)
	temp.play_hint()


# 铺一个镜像格：照抄棋盘上该格的状态，不播提示动画
func _spawn_mask_mirror_cell(cell: Vector2i) -> void:
	var temp: CellView = _instantiate_mask_temp(cell)
	var src: CellView = _board_view.get_cell_view(cell.x, cell.y)
	if src != null:
		temp.change_state({"state": src.get_state(), "play_anim": false})


# 释放所有遮罩格并清空登记表
func _clear_mask_hint_cells() -> void:
	for key in _mask_hint_cells.keys():
		(_mask_hint_cells[key] as CellView).queue_free()
	_mask_hint_cells.clear()


# 棋盘某格状态变了，同步给遮罩层里的同名副本
func _mirror_state_to_mask_hint_cell(r: int, c: int, state: int) -> void:
	var key := Vector2i(r, c)
	if _mask_hint_cells.has(key):
		(_mask_hint_cells[key] as CellView).change_state({"state": state})


# 淡入遮罩层（0.12 秒）
func _fade_in_mask_layer() -> void:
	if _mask_tween != null and _mask_tween.is_valid():
		_mask_tween.kill()
	# 先归零再淡入，重复调用也不会跳变
	_mask_layer.modulate.a = 0.0
	_mask_layer.visible = true
	# 遮罩压暗后把 IQ 数字换成金色，否则看不清
	if _iq_bar.visible:
		_iq_label.add_theme_color_override("font_color", Color(1, 0.8, 0, 1))
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask_layer, "modulate:a", 1.0, 0.12)


# 淡出遮罩层，结束时隐藏并恢复 IQ 数字颜色
func _fade_out_mask_layer() -> void:
	if not _mask_layer.visible:
		return
	if _mask_tween != null and _mask_tween.is_valid():
		_mask_tween.kill()
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask_layer, "modulate:a", 0.0, 0.12)
	# 淡出结束的回调：隐藏遮罩、还原透明度、恢复 IQ 数字颜色
	_mask_tween.tween_callback(
		func() -> void:
			_mask_layer.visible = false
			_mask_layer.modulate.a = 1.0
			if _iq_bar.visible:
				_iq_label.add_theme_color_override("font_color", Color(0.576, 0.353, 0.353, 1))
	)


# 默认流程的彩带效果：页面顶部随机生成 30 片彩色纸片下落，落完自毁
func _spawn_confetti() -> void:
	var colors: Array[Color] = [
		Color("#FF5252"),
		Color("#448AFF"),
		Color("#69F0AE"),
		Color("#FFD740"),
		Color("#FF4081"),
		Color("#40C4FF"),
	]
	# 30 片纸片各自随机大小、颜色、旋转与起点
	for _i in range(30):
		var rect := ColorRect.new()
		var w: float = randf_range(6.0, 14.0)
		var h: float = randf_range(10.0, 22.0)
		rect.size = Vector2(w, h)
		rect.color = colors[randi() % colors.size()]
		rect.rotation = randf() * PI * 2.0
		rect.position = Vector2(randf_range(40.0, 1040.0), randf_range(-150.0, -40.0))
		# 盖在页面内容之上
		rect.z_index = 10 # 盖在页面内容之上
		add_child(rect)
		var tw := create_tween()
		(
			tw
			. tween_property(rect, "position:y", 1980.0, randf_range(2.0, 3.5))
			. set_delay(randf_range(0.0, 0.6))
			. set_ease(Tween.EASE_IN)
			. set_trans(Tween.TRANS_QUAD)
		)
		tw.tween_callback(rect.queue_free)


# ================= 玩家输入 =================
# 提示工具条的点击处理：只有第 7 步自由阶段才响应
func _on_hint_tool_panel_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _current_mode != StepMode.FREE_PLAY:
		return

	_step7_show_hint()


# 确认按钮回调（场景里接的是 tag_pressed 信号）：只有 CONFIRM 模式放行
func _on_confirm_btn_pressed() -> void:
	if _current_mode != StepMode.CONFIRM:
		return
	_step_completed.emit()


# 判断某格是否在当前步骤允许操作的名单里
func _is_allowed(r: int, c: int) -> bool:
	for cell in _allowed_cells:
		if cell == Vector2i(r, c):
			return true
	return false


# 拖拽开始：记下起点格，并决定这次拖拽是「打叉」还是「擦除」
func _on_board_cell_drag_start(pos: Vector2) -> void:
	var cell: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)
	if cell.x < 0:
		return
	# 注意 pointer_to_cell 返回的是 Vector2i(列, 行)
	var r: int = cell.y
	var c: int = cell.x
	# 不在任何步骤模式，或点到已落定的猫：直接忽略
	if _current_mode == StepMode.NONE or _board_view.get_cell_state(r, c) == CellState.CAT:
		return

	# 第 7 步给过提示后只认提示圈定的格子；其他模式一律按 _allowed_cells 白名单
	if _current_mode == StepMode.FREE_PLAY and _step7_hint_phase > 0:
		if not _is_allowed(r, c):
			return
	elif _current_mode != StepMode.FREE_PLAY and not _is_allowed(r, c):
		return
	_drag_start_cell = Vector2i(r, c) # 记下起点（行, 列）
	_drag_had_move = false

	# 阶段 0 / 3 是自由涂改：空白格盖叉，已有叉的格子擦掉
	if _current_mode == StepMode.FREE_PLAY and (_step7_hint_phase == 0 or _step7_hint_phase == 3):
		var cur: int = _board_view.get_cell_state(r, c)
		_drag_target_state = CellState.MARK if CellState.is_blank(cur) else CellState.EMPTY # 空白 → 盖叉；已有叉 → 擦掉


# 拖拽经过格子：按当前模式实时改状态，并同步遮罩层副本
func _on_board_cell_drag_over(pos: Vector2) -> void:
	var cell: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)
	if cell.x < 0:
		return
	var r: int = cell.y
	var c: int = cell.x
	# 起点是 (-1,-1) 说明没落在棋盘内：忽略
	if _drag_start_cell == Vector2i(-1, -1):
		return
	# 拖过别的格子就只算拖拽，不再当作单击
	if Vector2i(r, c) != _drag_start_cell:
		_drag_had_move = true

	# 打叉步骤：只认白名单里的空格
	if _current_mode == StepMode.MARK_CELLS and _is_allowed(r, c):
		if CellState.is_blank(_board_view.get_cell_state(r, c)):
			_board_view.set_cell_state(r, c, CellState.MARK)
			_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
			VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
			_marked_count += 1 # 进度 +1
			if _marked_count >= _required_marks:
				_step_completed.emit() # 打满即完成这一步

	# 自由阶段 + 提示阶段 1 / 2：只允许在提示格上打叉
	elif _current_mode == StepMode.FREE_PLAY and (_step7_hint_phase == 1 or _step7_hint_phase == 2):
		if _is_allowed(r, c) and CellState.is_blank(_board_view.get_cell_state(r, c)):
			_board_view.set_cell_state(r, c, CellState.MARK)
			_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
			VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
			_step7_check_phase_complete()

	# 自由阶段 + 阶段 0 / 3：按拖拽开始时定下的目标状态刷格子
	elif _current_mode == StepMode.FREE_PLAY and (_step7_hint_phase == 0 or _step7_hint_phase == 3):
		var cur: int = _board_view.get_cell_state(r, c)
		if cur == CellState.CAT or cur == _drag_target_state:
			return
		_board_view.set_cell_state(r, c, _drag_target_state)
		_mirror_state_to_mask_hint_cell(r, c, _drag_target_state)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)


# 拖拽结束：没有移动过就当成单击，按当前模式分派给对应处理
func _on_board_cell_drag_end() -> void:
	if _drag_start_cell == Vector2i(-1, -1):
		return
	# 拖动过就只算拖拽，不触发点击
	if _drag_had_move:
		_drag_start_cell = Vector2i(-1, -1)
		_drag_had_move = false
		return

	var r: int = _drag_start_cell.x
	var c: int = _drag_start_cell.y
	_drag_start_cell = Vector2i(-1, -1)
	_drag_had_move = false

	# 单击按当前模式分派
	match _current_mode:
		StepMode.MARK_CELLS:
			_handle_mark_tap(r, c)
		StepMode.PLACE_CAT:
			_handle_place_cat_tap(r, c)
		StepMode.FREE_PLAY:
			_handle_free_play_tap(r, c)


# ================= 单击处理与通关判定 =================
# 打叉模式单击：空白格盖叉，攒够 _required_marks 即算这一步完成
func _handle_mark_tap(r: int, c: int) -> void:
	if not CellState.is_blank(_board_view.get_cell_state(r, c)):
		return
	_board_view.set_cell_state(r, c, CellState.MARK)
	_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
	_marked_count += 1
	if _marked_count >= _required_marks:
		_step_completed.emit()


# 放猫模式单击：0.35 秒内连点同一格两次才落猫
func _handle_place_cat_tap(r: int, c: int) -> void:
	# 第二次点到同一格才算确认，避免误触
	if _last_tap_cell == Vector2i(r, c):
		_last_tap_cell = Vector2i(-1, -1)
		_place_cat(r, c)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)
		_step_completed.emit()
	# 第一次点：先记下来，超时作废
	else:
		_last_tap_cell = Vector2i(r, c)
		get_tree().create_timer(0.35).timeout.connect(
			func() -> void:
				if _last_tap_cell == Vector2i(r, c):
					_last_tap_cell = Vector2i(-1, -1)
		)


# 自由阶段单击：提示阶段 1 / 2 只打叉，其余双击落猫、单击涂改
func _handle_free_play_tap(r: int, c: int) -> void:
	# 提示阶段：在提示格上打叉 / 取消叉，全部打满才进入下一层
	if _step7_hint_phase == 1 or _step7_hint_phase == 2:
		if not _is_allowed(r, c):
			return
		var state := _board_view.get_cell_state(r, c)
		if CellState.is_blank(state):
			_board_view.set_cell_state(r, c, CellState.MARK)
			_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
			VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
		elif state == CellState.MARK:
			_board_view.set_cell_state(r, c, CellState.EMPTY)
			_mirror_state_to_mask_hint_cell(r, c, CellState.EMPTY)

		_step7_check_phase_complete()
		return

	# 其余阶段：白名单格双击落猫，白名单外的格子单击涂改
	if _is_allowed(r, c):
		if _last_tap_cell == Vector2i(r, c):
			_last_tap_cell = Vector2i(-1, -1)
			_place_cat(r, c)
			VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)
			_check_free_play_complete()
		else:
			_last_tap_cell = Vector2i(r, c)
			get_tree().create_timer(0.35).timeout.connect(
				func() -> void:
					if _last_tap_cell == Vector2i(r, c):
						_last_tap_cell = Vector2i(-1, -1)
			)
	else:
		_do_single_tap_toggle(r, c)


# 检查第 7 步当前提示阶段的格子是否都打了叉，是则回到「放最后一只猫」状态
func _step7_check_phase_complete() -> void:
	# 提示格全部变成叉就收尾
	for cell in _allowed_cells:
		if _board_view.get_cell_state(cell.x, cell.y) != CellState.MARK:
			return

	# 提示阶段结束
	_step7_hint_phase = 0
	# 回到唯一答案格
	_allowed_cells = [Vector2i(2, 3)]
	_hide_hand()
	_clear_mask_hint_cells()
	_fade_out_mask_layer()
	_show_message("[center]" + tr("TUTORIAL_LAST_ONE_RICH") + "[/center]")


# 再点一次提示按钮：直接把当前阶段的答案代打掉（打叉或落猫）
func _apply_step7_hint() -> void:
	# 阶段 1 / 2：把该阶段所有空格直接代打上叉
	if _step7_hint_phase == 1 or _step7_hint_phase == 2:
		for cell in _allowed_cells:
			if CellState.is_blank(_board_view.get_cell_state(cell.x, cell.y)):
				_board_view.set_cell_state(cell.x, cell.y, CellState.MARK)
				_mirror_state_to_mask_hint_cell(cell.x, cell.y, CellState.MARK)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
		_step7_check_phase_complete()
	# 阶段 3：直接把最后一只猫落好
	elif _step7_hint_phase == 3:
		var target := Vector2i(2, 3)
		_place_cat(target.x, target.y)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)
		_step7_hint_phase = 0
		_hide_hand()
		_clear_mask_hint_cells()
		if _mask_layer.visible:
			_fade_out_mask_layer()
		_check_free_play_complete()


# 自由阶段单击非答案格：在「叉」和「空」之间切换，并记录连点时间窗
func _do_single_tap_toggle(r: int, c: int) -> void:
	# 当前状态决定这次点击是盖叉还是擦掉
	var cur: int = _board_view.get_cell_state(r, c)
	if CellState.is_blank(cur):
		_board_view.set_cell_state(r, c, CellState.MARK)
		_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
	elif cur == CellState.MARK:
		_board_view.set_cell_state(r, c, CellState.EMPTY)
		_mirror_state_to_mask_hint_cell(r, c, CellState.EMPTY)
	_last_tap_cell = Vector2i(r, c)
	get_tree().create_timer(0.35).timeout.connect(
		func() -> void:
			if _last_tap_cell == Vector2i(r, c):
				_last_tap_cell = Vector2i(-1, -1)
	)


# 往格子里落猫：先清掉同格的叉，格子非空则不动
func _place_cat(r: int, c: int) -> void:
	if _board_view.get_cell_state(r, c) == CellState.MARK:
		_board_view.set_cell_state(r, c, CellState.EMPTY)
	if not CellState.is_blank(_board_view.get_cell_state(r, c)):
		return
	_board_view.set_cell_state(r, c, CellState.CAT)


# 自由阶段通关判定：TUTORIAL_SOLUTION 四格都是猫就震动并发射步骤完成信号
func _check_free_play_complete() -> void:
	for sol in TUTORIAL_SOLUTION:
		if _board_view.get_cell_state(sol.x, sol.y) != CellState.CAT:
			return
	# 最强一档震动
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL5) # 最强一档震动
	_step_completed.emit()


# ================= 消息面板与配色文案 =================
# 消息文本尺寸变化时，同步面板高度并重新对齐棋盘
func _on_msg_rich_resized() -> void:
	if not is_inside_tree():
		return
	# 面板高度 = 文本高度 + 上下内边距
	_msg_panel.size.y = _msg_rich.size.y + _MSG_PANEL_PADDING_Y * 2.0
	_align_msg_panel_to_board()


# 把消息面板贴着棋盘上沿摆放，间距用 _ready 里量到的值
func _align_msg_panel_to_board() -> void:
	var board_top: float = _board_container.global_position.y
	var msg_height: float = _msg_panel.size.y
	var pos: Vector2 = _msg_panel.global_position
	pos.y = board_top - _msg_to_board_gap - msg_height
	_msg_panel.global_position = pos


# ================= 颜色名工具 =================
# 取某格区域颜色的富文本片段（带色号），供文案指代「哪种颜色」
func _color_name_bbcode_for_cell(r: int, c: int) -> String:
	var region_idx: int = (
		_guide_regions[r][c] if r < _guide_regions.size() and c < _guide_regions[r].size() else -1
	)
	# 拿不到区域编号（越界）时退化成「某色」
	if region_idx < 0:
		return tr("HINT_SOME_COLOR")
	var cell_color: Color = _board_view.get_region_color(region_idx)
	var hex: String
	var name: String
	# 对照组用固定色表：下标 → 颜色名 + 色号
	if ABTestManager.region_color.value() == RegionColorConfig.VALUE_CONTROL:
		var ci: int = _board_view.get_region_color_index(region_idx)
		var color_names: Array[String] = [
			tr("COLOR_PINK"),
			tr("COLOR_ROSE"),
			tr("COLOR_PURPLE"),
			tr("COLOR_MAGENTA"),
			tr("COLOR_ORANGE"),
			tr("COLOR_YELLOW"),
			tr("COLOR_DARK_BLUE"),
			tr("COLOR_LIGHT_BLUE"),
			tr("COLOR_SKY_BLUE"),
			tr("COLOR_TEAL"),
			tr("COLOR_GREEN"),
			tr("COLOR_BROWN"),
		]
		name = color_names[ci] if ci < color_names.size() else tr("HINT_SOME_COLOR")
		var hex_codes: Array[String] = [
			"#D980A4",
			"#BC537C",
			"#8465D6",
			"#F970DE",
			"#FFAA6E",
			"#DDA916",
			"#49658F",
			"#83AAD2",
			"#3497CB",
			"#289692",
			"#78AB5A",
			"#AC6F48"
		]
		hex = hex_codes[ci] if ci < hex_codes.size() else "#ffffff"
	# 其他分组用真实区域色：色号取加深 0.28 的版本，名字取最接近的色名
	else:
		var darkened: Color = cell_color.darkened(0.28)
		hex = (
			"#%02x%02x%02x" % [int(darkened.r * 255), int(darkened.g * 255), int(darkened.b * 255)]
		)
		name = _nearest_color_name(cell_color)
	return "[color=%s]%s[/color]" % [hex, name]


# 在预置色表里找最接近的颜色名（比较 RGB 距离平方，省一次开方）
func _nearest_color_name(color: Color) -> String:
	var known: Array = [
		[Color("#CBCB24"), tr("COLOR_OLIVE_YELLOW")],
		[Color("#E45F8A"), tr("COLOR_ROSE")],
		[Color("#8D7AEB"), tr("COLOR_PURPLE")],
		[Color("#F4A2E4"), tr("COLOR_MAGENTA")],
		[Color("#FF8E3D"), tr("COLOR_ORANGE")],
		[Color("#F4D27B"), tr("COLOR_YELLOW")],
		[Color("#4B7FC0"), tr("COLOR_DARK_BLUE")],
		[Color("#A2C7ED"), tr("COLOR_LIGHT_BLUE")],
		[Color("#0AAECF"), tr("COLOR_SKY_BLUE")],
		[Color("#0DA875"), tr("COLOR_DARK_GREEN")],
		[Color("#88CE7A"), tr("COLOR_GREEN")],
		[Color("#AA7146"), tr("COLOR_BROWN")],
		[Color("#CDA400"), tr("COLOR_OLIVE_YELLOW")],
		[Color("#D36F8F"), tr("COLOR_ROSE")],
		[Color("#8979DA"), tr("COLOR_PURPLE")],
		[Color("#38A9C0"), tr("COLOR_SKY_BLUE")],
		[Color("#2A8C53"), tr("COLOR_DARK_GREEN")],
		[Color("#A86D4A"), tr("COLOR_BROWN")],
		[Color("#ac7147"), tr("COLOR_BROWN")],
		[Color("#f19e80"), tr("COLOR_SALMON")],
		[Color("#c36a8a"), tr("COLOR_ROSE")],
		[Color("#afb4d2"), tr("COLOR_LAVENDER")],
		[Color("#c58ced"), tr("COLOR_PURPLE")],
		[Color("#a4d987"), tr("COLOR_GREEN")],
		[Color("#6584b3"), tr("COLOR_DARK_BLUE")],
		[Color("#e4bc4a"), tr("COLOR_YELLOW")],
		[Color("#fea3e9"), tr("COLOR_PINK")],
		[Color("#4bb5b1"), tr("COLOR_TEAL")],
		[Color("#de7e34"), tr("COLOR_ORANGE")],
		[Color("#89c4e6"), tr("COLOR_SKY_BLUE")],
		[Color("#c9a779"), tr("COLOR_TAN")],
		[Color("#ca6666"), tr("COLOR_RED")],
		[Color("#686dbf"), tr("COLOR_INDIGO")],
		[Color("#9684ec"), tr("COLOR_VIOLET")],
		[Color("#ca7849"), tr("COLOR_ORANGE")],
		[Color("#4aba34"), tr("COLOR_GREEN")],
		[Color("#9de1e3"), tr("COLOR_AQUA")],
		[Color("#4cabdb"), tr("COLOR_DARK_BLUE")],
		[Color("#dc5599"), tr("COLOR_PINK")],
		[Color("#f4a4e7"), tr("COLOR_LILAC")],
		[Color("#7ee388"), tr("COLOR_LIME")],
		[Color("#dbbc48"), tr("COLOR_GOLD")],
		[Color("#b67c54"), tr("COLOR_BROWN")],
		[Color("#ffaf92"), tr("COLOR_PEACH")],
		[Color("#37b95e"), tr("COLOR_GREEN")],
		[Color("#89c4e4"), tr("COLOR_SKY_BLUE")],
		[Color("#a673d8"), tr("COLOR_PURPLE")],
		[Color("#a4da86"), tr("COLOR_LIME")],
		[Color("#6767c3"), tr("COLOR_INDIGO")],
		[Color("#e3bd4d"), tr("COLOR_GOLD")],
		[Color("#fbafea"), tr("COLOR_PINK")],
		[Color("#45b7b3"), tr("COLOR_TEAL")],
		[Color("#dd8240"), tr("COLOR_ORANGE")],
		[Color("#e4699c"), tr("COLOR_ROSE")],
	]
	# 线性扫描取距离最小的那个名字
	var best_name: String = tr("HINT_SOME_COLOR")
	var best_dist: float = INF
	for pair in known:
		var c: Color = pair[0]
		var dr: float = color.r - c.r
		var dg: float = color.g - c.g
		var db: float = color.b - c.b
		var d: float = dr * dr + dg * dg + db * db
		if d < best_dist:
			best_dist = d
			best_name = pair[1]
	return best_name
