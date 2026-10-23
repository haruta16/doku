## 教程页面：驱动默认及实验教学流程，锁定允许操作的格子并串联提示与演示。
class_name TutorialPage
extends UIFrameWindow

## 遮罩层用的临时格子场景：遮罩压暗整盘时，提示格靠它保持亮色
const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn")
const _G2_COPY: Script = preload("res://scripts/module/tutorial/model/tutorial_g2_copy.gd")
const _FLOW_TRACKING: Script = preload(
	"res://scripts/module/tutorial/model/tutorial_flow_tracking.gd"
)

## 教学关答案（行 → 列），与题库 solution 一致，用于自由阶段的通关判定
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
@onready var _select_frame: Panel = $Root/BoardContainer/HighlightOverlay/SelectFrame
@onready var _msg_panel: Panel = $Root/MessagePanel
@onready var _msg_rich: RichTextLabel = $Root/MessagePanel/MsgRich
@onready var _sub_msg_panel: Panel = $Root/SubMsgPanel
@onready var _sub_msg_rich: RichTextLabel = $Root/SubMsgPanel/SubMsgRich
@onready var _hint_tool_panel: Panel = $Root/HintToolPanel
@onready var _hint_label: RichTextLabel = $Root/HintToolPanel/HintLabel
@onready var _lamp_icon: TextureRect = $Root/HintToolPanel/LampIcon
@onready var _hint_btn: Control = $Root/HintBtn
@onready var _hint_hit: Button = $Root/HintBtn/Hit
@onready var _skip_btn: Button = $Root/SkipBtn
@onready var _confirm_btn: Button = $Root/ConfirmBtn
@onready var _hand_hint: Control = $Root/HandHint
@onready var _hand_spine: SpineSprite = $Root/HandHint/ui_guide_hand
@onready var _hand_static: TextureRect = $Root/HandHint/HandStatic
@onready var _mask_layer: Control = $Root/MaskLayer
@onready var _hint_overlay: HintOverlay = $Root/HintOverlay
@onready var _anim_msg_appear_2: AnimationPlayer = $MessagePanel_appear_2
@onready var _anim_confirm_loop: AnimationPlayer = $ConfirmBtn_loop
@onready var _anim_sub_msg_appear: AnimationPlayer = $SubMsgPanel_appear
@onready var _anim_hint_tool_appear: AnimationPlayer = $HintToolPanel_appear
@onready var _anim_hint_btn_appear: AnimationPlayer = $HintBtn_appear

# ---- 步骤模式与内部信号 ----
enum StepMode { NONE, PLACE_CAT, MARK_CELLS, FREE_PLAY, CONFIRM } # NONE 无 / PLACE_CAT 放猫 / MARK_CELLS 打叉 / FREE_PLAY 自由玩 / CONFIRM 等按钮

signal _step_completed # 仅本页内部使用，不对外广播

# ---- 流程控制（步骤协程 + 防重入令牌） ----
var _flow_token: int = 0 # 每次 on_show 自增；旧协程发现 token 变了就退出

var _current_mode: int = StepMode.NONE # 当前步骤模式，决定输入怎么解释
var _allowed_cells: Array[Vector2i] = [] # 当前步骤允许操作的格子白名单
var _required_marks: int = 0 # 这一步需要打的叉数
var _marked_count: int = 0 # 已经打好的叉数
var _skip_requested: bool = false

var _step7_hint_phase: int = 0 # 第 7 步提示阶段：0 未点提示 / 1 排除蓝行 / 2 排除粉行 / 3 落最后一猫

var _flash_on_wrong_tap: bool = false

var _g2_glow_cells: Array[Vector2i] = []

var _g2_hint_data: Dictionary = {}
var _g2_hint_highlight_layer: CanvasLayer = null

const _G2_GLOW_PLACE: StringName = &"GridGlowing3"
const _G2_GLOW_MARK: StringName = &"GridGlowing4"

const _G2_ROW_LEAD_SEC: float = 0.6
const _G2_MARK_ROW_SEC: float = 0.09
const _G2_RING_LEAD_SEC: float = 0.7
const _G2_MARK_RING_SEC: float = 0.11
const _G2_DEDUCE_PAUSE_SEC: float = 0.6

const _CONFLICT_LINE_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/conflict_line.tscn"
)

const _G2_CONFLICT_GLOW: StringName = &"GridGlowing5"

const _STEP_PAUSE_SEC: float = 0.4

const _FREE_PLAY_COMPLETION_PAUSE_SEC: float = 0.5

const _FAST_FINISH_SEC: float = 1.0

var _mask_hint_cells: Dictionary = {} # 遮罩层上的提示格：格子坐标 → 临时 CellView
var _mask_frozen_source_cells: Dictionary = {}
var _mask_tween: Tween = null # 遮罩淡入淡出用的补间

# ---- 手势状态（拖拽与连点） ----
var _drag_start_cell: Vector2i = Vector2i(-1, -1) # 本次拖拽的起点（行, 列），(-1,-1) 表示没有拖拽
var _drag_last_cell: Vector2i = Vector2i(-1, -1)
var _drag_had_move: bool = false # 本次拖拽是否移动过（移动过就不算单击）

var _drag_target_state: int = CellState.MARK # 拖拽时要写入的状态：MARK 打叉 或 EMPTY 擦除
var _drag_target_pending: bool = false
var _drag_start_processed: bool = false
var _last_tap_cell: Vector2i = Vector2i(-1, -1) # 上一次单击的格子，用于识别「连点两次」

var _double_tap_window_generation: int = 0

const _DEFAULT_DOUBLE_TAP_SEC: float = 0.35
var _last_window_sec: float = _DEFAULT_DOUBLE_TAP_SEC
var _dbg_win_open_ms: int = -1
var _dbg_win_open_cell: Vector2i = Vector2i(-1, -1)

var _swipe_hand_tween: Tween = null # 滑动打叉手势的循环补间

# ---- 埋点与布局测量 ----
var _guide_start_ms: int = 0 # on_show 的时刻（毫秒），用于统计教学耗时

const _GUIDE_BOARD_WIDTH: float = 919.0

var _msg_to_board_gap: float = 0.0 # 消息面板与棋盘之间的初始间距（像素）
var _hint_btn_base_scale: Vector2 = Vector2.ONE
var _skip_btn_base_scale: Vector2 = Vector2.ONE

# ---- 数值常量：消息面板与 IQ 条 ----
const _MSG_PANEL_PADDING_Y: float = 40.0 # 消息面板上下各留的内边距（像素）


func _ready() -> void:
	_board_view.cell_drag_start.connect(_on_board_cell_drag_start)
	_board_view.cell_drag_over.connect(_on_board_cell_drag_over)
	_board_view.cell_drag_end.connect(_on_board_cell_drag_end)
	_hint_btn_base_scale = _hint_btn.scale
	_hint_hit.button_down.connect(
		func() -> void: UIHelper.play_press_scale(_hint_btn, _hint_btn_base_scale)
	)
	_hint_hit.button_up.connect(
		func() -> void: UIHelper.play_release_scale(_hint_btn, _hint_btn_base_scale)
	)
	_skip_btn_base_scale = _skip_btn.scale
	_skip_btn.button_down.connect(
		func() -> void: UIHelper.play_press_scale(_skip_btn, _skip_btn_base_scale)
	)
	_skip_btn.button_up.connect(
		func() -> void: UIHelper.play_release_scale(_skip_btn, _skip_btn_base_scale)
	)

	_hint_tool_panel.gui_input.connect(_on_hint_tool_panel_gui_input)
	_hint_overlay.set_board(_board_view)

	_msg_rich.resized.connect(_on_msg_rich_resized)

	_msg_to_board_gap = _board_container.offset_top - _msg_panel.offset_bottom


## 推进流程令牌并唤醒旧等待，清空交互限制后建立棋盘，选择当前实验对应的教程流程。
func on_show(_params: Dictionary = {}) -> void:
	_flow_token += 1
	_skip_requested = false

	_step_completed.emit()
	_current_mode = StepMode.NONE
	_reset_double_tap_window()
	_drag_start_cell = Vector2i(-1, -1)
	_drag_last_cell = Vector2i(-1, -1)
	_drag_had_move = false
	_drag_target_pending = false
	_drag_start_processed = false
	_reset_ui()
	_sync_skip_button_visibility()
	_setup_board()

	call_deferred("_align_msg_panel_to_board")

	_guide_start_ms = Time.get_ticks_msec()
	Tracker.track_new_guide_show(1)

	if ABTestManager.nu_guide.is_new_guide_flow():
		await _run_guide_flow_g2()
	else:
		await _run_guide_flow_default()


## 使旧教程流程失效，释放步骤等待并停止提示、冲突动画与高亮。
func on_hide() -> void:
	_flow_token += 1
	_current_mode = StepMode.NONE
	_reset_double_tap_window()
	_allowed_cells.clear()
	_step_completed.emit()
	_g2_cancel_conflict()
	_g2_clear_glow()
	_cleanup_g2_hint()


func _run_guide_flow_default() -> void:
	var _tok: int = _flow_token
	await _step_1_place_first_cat()
	if _flow_token != _tok:
		return
	Tracker.track_new_guide_step(1)

	if not ABTestManager.nu_guide.is_confirm_step_removed():
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


func _run_guide_flow_g2() -> void:
	var _tok: int = _flow_token
	for page: int in _G2_COPY.page_sequence():
		await _g2_run_page(page)
		if _flow_token != _tok:
			return
		_track_guide_step(page)
	await _step_finish()


func _g2_run_page(page: int) -> void:
	match page:
		1:
			await _g2_stage_1_place_first_cat()
		2:
			await _g2_stage_2_mark_row_col()
		3:
			await _g2_stage_3_place_second_cat()
		4:
			await _g2_stage_4_neighbor_ring()
		5:
			await _g2_stage_5_free_play()


func _g2_stage_1_place_first_cat() -> void:
	_show_g2_message(1)
	var target := Vector2i(0, 2)
	_allowed_cells = [target]
	_g2_glow([target], _G2_GLOW_PLACE)
	_position_hand_at_cell(target)
	_show_hand()
	_current_mode = StepMode.PLACE_CAT
	await _step_completed
	_current_mode = StepMode.NONE
	_hide_hand()
	_g2_clear_glow()


func _g2_stage_2_mark_row_col() -> void:
	var tok: int = _flow_token
	_show_g2_message(2)
	await get_tree().create_timer(_G2_ROW_LEAD_SEC).timeout
	if _flow_token != tok:
		return

	var row_cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 3)]
	await _g2_auto_mark(row_cells, _G2_MARK_ROW_SEC)
	if _flow_token != tok:
		return

	var col_cells: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
	_allowed_cells = col_cells
	_required_marks = col_cells.size()
	_marked_count = 0
	_g2_glow(col_cells, _G2_GLOW_MARK)
	_current_mode = StepMode.MARK_CELLS
	await _step_completed
	_current_mode = StepMode.NONE
	_g2_clear_glow()


func _g2_stage_3_place_second_cat() -> void:
	var tok: int = _flow_token
	_show_g2_message(3)
	await get_tree().create_timer(_G2_DEDUCE_PAUSE_SEC).timeout
	if _flow_token != tok:
		return
	var target := Vector2i(3, 1)
	_allowed_cells = [target]
	_g2_glow([target], _G2_GLOW_PLACE)
	_current_mode = StepMode.PLACE_CAT
	await _step_completed
	_current_mode = StepMode.NONE
	_g2_clear_glow()


func _g2_stage_4_neighbor_ring() -> void:
	var tok: int = _flow_token
	_show_g2_message(4)
	await get_tree().create_timer(_G2_RING_LEAD_SEC).timeout
	if _flow_token != tok:
		return
	await _g2_auto_mark(_g2_neighbors_in_board(Vector2i(3, 1)), _G2_MARK_RING_SEC)
	if _flow_token != tok:
		return
	await get_tree().create_timer(_G2_DEDUCE_PAUSE_SEC).timeout
	if _flow_token != tok:
		return
	var target := Vector2i(1, 0)
	_allowed_cells = [target]
	_g2_glow([target], _G2_GLOW_PLACE)
	_current_mode = StepMode.PLACE_CAT
	await _step_completed
	_current_mode = StepMode.NONE
	_g2_clear_glow()


func _g2_stage_5_free_play() -> void:
	_show_g2_message(5)
	_allowed_cells = [Vector2i(2, 3)]
	_step7_hint_phase = 0
	_flash_on_wrong_tap = true
	_show_hint_btn()
	_g2_clear_glow()
	_board_view.clear_hint_cells()
	_g2_hint_data = {}
	_current_mode = StepMode.FREE_PLAY
	await _step_completed
	_current_mode = StepMode.NONE
	_flash_on_wrong_tap = false
	_g2_clear_glow()
	_cleanup_g2_hint()
	_hide_hand()
	_hide_hint_btn()
	await get_tree().create_timer(_FREE_PLAY_COMPLETION_PAUSE_SEC).timeout


func _g2_auto_mark(cells: Array[Vector2i], interval_sec: float) -> void:
	var tok: int = _flow_token
	for cell: Vector2i in cells:
		if not CellState.is_blank(_board_view.get_cell_state(cell.x, cell.y)):
			continue
		_board_view.set_cell_state(cell.x, cell.y, CellState.MARK)
		VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_MARK)
		await get_tree().create_timer(interval_sec).timeout

		if _flow_token != tok:
			return


func _g2_glow(cells: Array[Vector2i], anim: StringName) -> void:
	_g2_clear_glow()
	for cell: Vector2i in cells:
		var cv: CellView = _board_view.get_cell_view(cell.x, cell.y)
		if cv == null:
			continue
		cv.play_grid_glow_loop(anim)
		_g2_glow_cells.append(cell)


func _g2_clear_glow() -> void:
	for cell: Vector2i in _g2_glow_cells:
		var cv: CellView = _board_view.get_cell_view(cell.x, cell.y)
		if cv != null:
			cv.stop_grid_glow()
	_g2_glow_cells.clear()


func _g2_stop_glow_at(r: int, c: int) -> void:
	var key := Vector2i(r, c)
	if not _g2_glow_cells.has(key):
		return
	var cv: CellView = _board_view.get_cell_view(r, c)
	if cv != null:
		cv.stop_grid_glow()
	_g2_glow_cells.erase(key)


func _g2_neighbors_in_board(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dr: int in [-1, 0, 1]:
		for dc: int in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var nr: int = cell.x + dr
			var nc: int = cell.y + dc
			if nr >= 0 and nr < 4 and nc >= 0 and nc < 4:
				out.append(Vector2i(nr, nc))
	return out


var _g2_conflict_token: int = 0

var _g2_conflict_busy: bool = false
var _g2_conflict_line: LineCrossConnector = null


func _g2_find_conflict_cat(r: int, c: int) -> Vector2i:
	if _guide_regions.is_empty():
		return Vector2i(-1, -1)
	var placed: Array[Vector2i] = []
	for rr: int in range(4):
		for cc: int in range(4):
			if rr == r and cc == c:
				continue
			if _board_view.get_cell_state(rr, cc) == CellState.CAT:
				placed.append(Vector2i(rr, cc))
	return QueendokuCore.find_priority_conflict_cat(r, c, placed, _guide_regions)


func _g2_conflict_rule_cells(r: int, c: int, conflict_pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if _guide_regions.is_empty():
		return result
	match QueendokuCore.classify_violation(r, c, [conflict_pos], _guide_regions):
		QueendokuCore.Rule.SAME_COLOR:
			var region_id: int = int(_guide_regions[conflict_pos.x][conflict_pos.y])
			for rr: int in range(4):
				for cc: int in range(4):
					if (
						Vector2i(rr, cc) != conflict_pos
						and int(_guide_regions[rr][cc]) == region_id
					):
						result.append(Vector2i(rr, cc))
		QueendokuCore.Rule.SAME_LINE:
			if conflict_pos.x == r:
				for cc: int in range(mini(c, conflict_pos.y) + 1, maxi(c, conflict_pos.y)):
					result.append(Vector2i(r, cc))
			else:
				for rr: int in range(mini(r, conflict_pos.x) + 1, maxi(r, conflict_pos.x)):
					result.append(Vector2i(rr, c))
		QueendokuCore.Rule.NO_TOUCH:
			for dr: int in range(-1, 2):
				for dc: int in range(-1, 2):
					if dr == 0 and dc == 0:
						continue
					var p := Vector2i(conflict_pos.x + dr, conflict_pos.y + dc)
					if p.x >= 0 and p.x < 4 and p.y >= 0 and p.y < 4:
						result.append(p)
	return result


func _g2_play_conflict(r: int, c: int) -> void:
	var tok: int = _g2_conflict_token
	_g2_conflict_busy = true
	var conflict_pos: Vector2i = _g2_find_conflict_cat(r, c)
	var target_cell: CellView = _board_view.get_cell_view(r, c)
	var conflict_cell: CellView = null
	var rule_cells: Array[Vector2i] = []

	if conflict_pos != Vector2i(-1, -1):
		conflict_cell = _board_view.get_cell_view(conflict_pos.x, conflict_pos.y)
		rule_cells = _g2_conflict_rule_cells(r, c, conflict_pos)
		if target_cell != null:
			target_cell.play_wrong_pos_reaction(MisplaceReactionConfig.TARGET_REACTION_ANIM_NAME)
			target_cell.play_grid_glow_named(_G2_CONFLICT_GLOW)
		if conflict_cell != null:
			conflict_cell.play_named_anim(MisplaceReactionConfig.CONFLICT_REACTION_ANIM_NAME)
			conflict_cell.play_grid_glow_named(_G2_CONFLICT_GLOW)
		for pos: Vector2i in rule_cells:
			var cv: CellView = _board_view.get_cell_view(pos.x, pos.y)
			if cv != null:
				cv.play_grid_glow_named(_G2_CONFLICT_GLOW)
		_g2_spawn_conflict_line(r, c, conflict_pos, tok)

	await get_tree().create_timer(MisplaceReactionConfig.CONFLICT_ANIM_DURATION_SEC).timeout

	if tok != _g2_conflict_token:
		return

	_g2_clear_conflict_visuals(target_cell, conflict_cell, rule_cells)

	_board_view.play_error_feedback(r, c)
	_mirror_state_to_mask_hint_cell(r, c, CellState.ERROR)
	_g2_conflict_busy = false


func _g2_spawn_conflict_line(r: int, c: int, conflict_pos: Vector2i, tok: int) -> void:
	get_tree().create_timer(MisplaceReactionConfig.CONFLICT_LINE_DELAY_SEC).timeout.connect(
		func() -> void:
			if tok != _g2_conflict_token or not is_instance_valid(self):
				return
			var line := _CONFLICT_LINE_SCENE.instantiate() as LineCrossConnector
			add_child(line)
			var inv: Transform2D = get_global_transform().affine_inverse()
			line.setup_points(
				inv * _board_view.get_cell_global_center(r, c),
				inv * _board_view.get_cell_global_center(conflict_pos.x, conflict_pos.y)
			)
			line.play_effect()
			_g2_conflict_line = line
	)


func _g2_clear_conflict_visuals(
	target_cell: CellView, conflict_cell: CellView, rule_cells: Array[Vector2i]
) -> void:
	if is_instance_valid(_g2_conflict_line):
		_g2_conflict_line.queue_free()
	_g2_conflict_line = null

	if target_cell != null:
		target_cell.stop_named_anim()
		target_cell.stop_grid_glow()
		target_cell.reset_glow_nodes()
	if conflict_cell != null:
		conflict_cell.stop_grid_glow()
		conflict_cell.reset_glow_nodes()
	for pos: Vector2i in rule_cells:
		var cv: CellView = _board_view.get_cell_view(pos.x, pos.y)
		if cv != null:
			cv.stop_grid_glow()
			cv.reset_glow_nodes()


func _g2_cancel_conflict() -> void:
	_g2_conflict_token += 1
	_g2_conflict_busy = false
	if is_instance_valid(_g2_conflict_line):
		_g2_conflict_line.queue_free()
	_g2_conflict_line = null


func _setup_board() -> void:
	_g2_cancel_conflict()
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
	var guide_regions: Array = BankData.get_region_map(guide_entry)
	for row in guide_regions:
		var int_row: Array = []
		for v in row:
			int_row.append(int(v))
		_guide_regions.append(int_row)
	_guide_color_map.clear()
	for v in guide_entry.get("colorMap", []):
		_guide_color_map.append(int(v))
	_board_view.setup(4, _guide_regions, _guide_color_map)

	for r in range(4):
		for c in range(4):
			var cv: CellView = _board_view.get_cell_view(r, c)
			if cv == null:
				continue
			if cv.get_state() != CellState.EMPTY:
				cv.change_state({"state": CellState.EMPTY, "play_anim": false})

			cv.resume_cat_idle()
			cv.modulate = Color.WHITE

			cv.stop_grid_glow()

			cv.reset_glow_nodes()
	_g2_glow_cells.clear()

	var _guide_intrinsic: Vector2 = BoardView.intrinsic_size_for(4)
	var _guide_scale: float = _GUIDE_BOARD_WIDTH / _guide_intrinsic.x
	_board_view.size = _guide_intrinsic
	_board_view.pivot_offset = Vector2.ZERO
	_board_view.position = Vector2.ZERO
	_board_view.scale = Vector2(_guide_scale, _guide_scale)
	_board_view.apply_compensated_cell_corner_radius()


# ================= 教学步骤（按顺序 await） =================
## 拼第 1 步的操作指引富文本：给关键词加呼吸高亮
func _step1_rich_action_line() -> String:
	var hl: String = tr("TUTORIAL_STEP1_HIGHLIGHT")
	var breath_seg: String = (
		"[breath amp=0.03 freq=5 group=1 count=%d][color=#d94848]%s[/color][/breath]"
		% [hl.length(), hl]
	)
	return tr("TUTORIAL_STEP1_RICH").format({"breath": breath_seg})


func _step1_message() -> String:
	if _uses_group3_step1_copy():
		return tr("TUTORIAL_STEP1_V3")
	return _step1_rich_action_line()


func _uses_group3_step1_copy() -> bool:
	return ABTestManager.nu_guide.is_confirm_step_removed()


func _step_1_place_first_cat() -> void:
	_show_message("[center]" + _step1_message() + "[/center]")
	var target := Vector2i(0, 2)
	_allowed_cells = [target]
	_show_mask_hints([target])
	_position_hand_at_cell(target)
	_show_hand()
	_current_mode = StepMode.PLACE_CAT
	await _step_completed
	_current_mode = StepMode.NONE
	_hide_hand()
	_clear_mask_hint_cells()
	_fade_out_mask_layer()
	await get_tree().create_timer(_STEP_PAUSE_SEC).timeout


## 第 2 步：纯文字确认「每色一只」，点「我知道了」才继续
func _step_2_confirm_one_per_color() -> void:
	_show_message("[center]" + tr("TUTORIAL_STEP2_RICH") + "[/center]")
	_show_confirm_btn(tr("TUTORIAL_GOT_IT"))
	_current_mode = StepMode.CONFIRM
	await _step_completed
	_current_mode = StepMode.NONE
	_hide_confirm_btn()


## 第 3 步：手动打掉 6 个同行同列的排除格，全打完才算过
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


func _step_4_place_second_cat() -> void:
	var _pink_msg: String
	if not ABTestManager.region_color.value() == RegionColorConfig.VALUE_CONTROL:
		var _cbb: String = _color_name_bbcode_for_cell(3, 1)
		_pink_msg = tr("TUTORIAL_STEP4_COLOR_RICH") % _cbb
	else:
		_pink_msg = tr("TUTORIAL_STEP4_PINK_RICH")
	_show_message("[center]" + _pink_msg + "[/center]")
	var target := Vector2i(3, 1)

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
	await get_tree().create_timer(_STEP_PAUSE_SEC).timeout


func _step_5_mark_neighbors() -> void:
	_show_message("[center]" + tr("TUTORIAL_STEP3_RICH") + "[/center]")

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


## 第 6 步：在 (1,0) 放第三只猫
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


func _step_7_free_play() -> void:
	_show_message("[center]" + tr("TUTORIAL_LAST_ONE_RICH") + "[/center]")
	_allowed_cells = [Vector2i(2, 3)]
	_step7_hint_phase = 0
	_hint_label.text = tr("TUTORIAL_STEP7_HINT")
	_show_hint_tool_panel()

	_board_view.clear_hint_cells()

	_flash_on_wrong_tap = false
	_current_mode = StepMode.FREE_PLAY
	await _step_completed
	_current_mode = StepMode.NONE
	_board_view.clear_hint_cells()
	_hide_hand()
	_clear_mask_hint_cells()
	if _mask_layer.visible:
		_fade_out_mask_layer()
	_hide_hint_tool_panel()
	await get_tree().create_timer(_FREE_PLAY_COMPLETION_PAUSE_SEC).timeout


## 第 7 步的提示按钮：分三层升级——先排除蓝猫那行、再排除粉猫那行、最后直接代打答案
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


func _step_finish() -> void:
	if _uses_new_guide_flow() or _uses_group3_step1_copy():
		await _finish_fast()
		return
	_show_message("[center]" + tr("TUTORIAL_STEP6_RICH") + "[/center]")
	_spawn_confetti()
	_show_confirm_btn(tr("TUTORIAL_START_GAME"))
	_track_finish_screen_step()
	_current_mode = StepMode.CONFIRM
	var tok: int = _flow_token
	await _step_completed
	if _flow_token != tok:
		return
	_current_mode = StepMode.NONE
	_track_completion_step()
	complete_tutorial()


func _finish_fast() -> void:
	_spawn_confetti()
	var tok: int = _flow_token
	await get_tree().create_timer(_FAST_FINISH_SEC).timeout

	if _flow_token != tok:
		return
	_track_completion_step()
	complete_tutorial(true)


func _track_finish_screen_step() -> void:
	var finish_screen_step: int = (
		_FLOW_TRACKING
		. finish_screen_step(
			_uses_new_guide_flow(),
			_uses_group3_step1_copy(),
		)
	)
	if finish_screen_step > 0:
		_track_guide_step(finish_screen_step)


func _track_completion_step() -> void:
	var completion_step: int = (
		_FLOW_TRACKING
		. completion_step(
			_uses_new_guide_flow(),
			_uses_group3_step1_copy(),
		)
	)
	if completion_step > 0:
		_track_guide_step(completion_step)


func _track_guide_step(step: int) -> void:
	Tracker.track_new_guide_step(step)


func _uses_new_guide_flow() -> bool:
	return ABTestManager.nu_guide.is_new_guide_flow()


func complete_tutorial(show_pass_toast: bool = false) -> void:
	var time_sec: float = (Time.get_ticks_msec() - _guide_start_ms) / 1000.0
	Tracker.track_new_guide_end(1, time_sec)
	GameState.set_tutorial_done(true)
	var game_params: Dictionary = {"level_index": 1}
	if show_pass_toast:
		game_params["from_tutorial"] = true
	UIManager.show_ui(UiName.GAME, game_params)

	UIManager.hide_ui(UiName.TUTORIAL)


func skip_tutorial() -> void:
	if _skip_requested or not _can_skip_tutorial():
		return
	_skip_requested = true
	_flow_token += 1
	_current_mode = StepMode.NONE
	_allowed_cells.clear()
	_step_completed.emit()
	_g2_cancel_conflict()
	_g2_clear_glow()
	_cleanup_g2_hint()
	if _swipe_hand_tween != null:
		_stop_swipe_hand_loop()
	_clear_mask_hint_cells()
	if _mask_tween != null and _mask_tween.is_valid():
		_mask_tween.kill()
	_mask_tween = null
	if is_instance_valid(_mask_layer):
		_mask_layer.visible = false
		_mask_layer.modulate.a = 1.0
	complete_tutorial(true)


func _can_skip_tutorial() -> bool:
	return ABTestManager.nu_guide.is_skippable()


func _sync_skip_button_visibility() -> void:
	_skip_btn.visible = _can_skip_tutorial()


func _reset_ui() -> void:
	_sub_msg_panel.visible = false
	_hint_tool_panel.visible = false
	_hint_btn.visible = false
	_confirm_btn.visible = false
	_anim_confirm_loop.stop()
	_hand_hint.visible = false
	_select_frame.visible = false
	_mask_layer.visible = false
	_mask_layer.modulate.a = 1.0
	_cleanup_g2_hint()


## 显示主提示文案并播出现动画
func _show_message(text: String) -> void:
	_msg_rich.text = text
	_anim_msg_appear_2.play("MessagePanel_appear_2")


func _show_g2_message(page: int) -> void:
	var top_message_key: StringName = _G2_COPY.top_message_key_for_page(page)
	if top_message_key.is_empty():
		return
	_show_message("[center]" + _translated_g2_message(top_message_key) + "[/center]")
	var bottom_message_key: StringName = _G2_COPY.bottom_message_key_for_page(page)
	if bottom_message_key.is_empty():
		_hide_sub_message()
		return
	_move_sub_msg_below_board()
	_show_sub_message("[center]" + _translated_g2_message(bottom_message_key) + "[/center]")


func _translated_g2_message(message_key: StringName) -> String:
	var translated: String = tr(message_key)
	var color_bbcode: String = _g2_color_bbcode_for_message_key(message_key)
	if color_bbcode.is_empty():
		return translated
	return _G2_COPY.inject_color_bbcode(translated, color_bbcode)


func _g2_color_bbcode_for_message_key(message_key: StringName) -> String:
	var cell: Vector2i = _G2_COPY.color_cell_for_message_key(message_key)
	if cell.x < 0:
		return ""
	return _color_name_bbcode_for_cell(cell.x, cell.y)


## 显示棋盘下方的副提示并播出现动画
func _show_sub_message(text: String) -> void:
	_sub_msg_rich.text = text
	_sub_msg_panel.visible = true
	_anim_sub_msg_appear.play("SubMsgPanel_appear")


func _hide_sub_message() -> void:
	_sub_msg_rich.text = ""
	_sub_msg_panel.visible = false


func _show_hint_tool_panel() -> void:
	_hint_btn.visible = false
	_hint_tool_panel.visible = true
	_anim_hint_tool_appear.play("HintToolPanel_appear")


## 隐藏提示工具条
func _hide_hint_tool_panel() -> void:
	_hint_tool_panel.visible = false


func _show_hint_btn() -> void:
	_hint_tool_panel.visible = false
	_hint_btn.visible = true
	_anim_hint_btn_appear.play("RESET")
	_anim_hint_btn_appear.advance(0.0)
	_anim_hint_btn_appear.play("HintBtn_appear")


func _hide_hint_btn() -> void:
	_hint_btn.visible = false


## 显示确认按钮、写入按钮文案并播呼吸动画
func _show_confirm_btn(text: String) -> void:
	_confirm_btn.set("btn_text", text)
	_confirm_btn.visible = true
	_anim_confirm_loop.play("ConfirmBtn_loop")


## 隐藏确认按钮并停掉呼吸动画
func _hide_confirm_btn() -> void:
	_confirm_btn.visible = false
	_anim_confirm_loop.stop()


## 显示手势提示，并让 Spine 手播 click 动画
func _show_hand() -> void:
	_hand_hint.visible = true
	_hand_spine.get_animation_state().set_animation("click", true, 0)


## 隐藏手势提示
func _hide_hand() -> void:
	_hand_hint.visible = false


# ================= 手势与遮罩提示 =================
## 把选中框对准某格（按 BoardView 缩放换算）；本文件内没有调用点
func _position_select_frame(cell: Vector2i) -> void:
	var s: float = _board_view.scale.x
	var rect: Rect2 = _board_view.cell_to_local_rect(cell.x, cell.y)
	var pad: float = 8.0
	_select_frame.position = rect.position * s - Vector2(pad, pad)
	_select_frame.size = rect.size * s + Vector2(pad * 2.0, pad * 2.0)


const _HAND_BASE_CELL := Vector2i(0, 2)
const _HAND_BASE_OFFSET := Vector2(111.0, -316.0)


func _cell_topleft_rel_center(cell: Vector2i) -> Vector2:
	var s: float = _board_view.scale.x
	return (
		Vector2(_board_container.offset_left, _board_container.offset_top)
		+ _board_view.position
		+ _board_view.cell_to_local_rect(cell.x, cell.y).position * s
	)


func _hand_tip_offset() -> Vector2:
	return _HAND_BASE_OFFSET - _cell_topleft_rel_center(_HAND_BASE_CELL)


func _position_hand_at_cell(cell: Vector2i) -> void:
	var pos: Vector2 = _cell_topleft_rel_center(cell) + _hand_tip_offset()
	_hand_hint.offset_left = pos.x
	_hand_hint.offset_top = pos.y
	_hand_hint.offset_right = pos.x + 110.0
	_hand_hint.offset_bottom = pos.y + 120.0


func _start_swipe_hand_loop(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	_stop_swipe_hand_loop()
	_position_hand_at_cell(cells[0])
	_hand_hint.visible = true
	_hand_hint.modulate.a = 1.0

	_hand_spine.visible = false
	_hand_static.visible = true

	var hand_tip: Vector2 = _hand_tip_offset()
	var offsets: Array[Vector2] = []
	for cell in cells:
		offsets.append(_cell_topleft_rel_center(cell) + hand_tip)
	var tw := create_tween()
	tw.set_loops()

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
	tw.tween_property(_hand_hint, "modulate:a", 0.0, 0.2)
	tw.tween_interval(0.35)
	_swipe_hand_tween = tw


## 停掉滑动手势补间，并把静态手图换回 Spine 手
func _stop_swipe_hand_loop() -> void:
	if _swipe_hand_tween != null and _swipe_hand_tween.is_valid():
		_swipe_hand_tween.kill()
	_swipe_hand_tween = null
	_hand_hint.modulate.a = 1.0
	_hand_static.visible = false
	_hand_spine.visible = true


## 把副提示面板移到棋盘正下方（先等一帧，等布局结算完）
func _move_sub_msg_below_board() -> void:
	await get_tree().process_frame
	var board_bottom: float = _board_container.position.y + _board_container.size.y
	var screen_center_y: float = size.y * 0.5
	var offset_top: float = board_bottom - screen_center_y + 30.0
	_sub_msg_panel.offset_top = offset_top
	_sub_msg_panel.offset_bottom = offset_top + 190.0


## 在遮罩层点亮提示格 cells，并铺出已填好的镜像格 mirror_cells；同时清掉棋盘自带的用法提示
func _show_mask_hints(cells: Array[Vector2i], mirror_cells: Array[Vector2i] = []) -> void:
	for cell in cells:
		_spawn_mask_hint_cell(cell)
	for cell in mirror_cells:
		_spawn_mask_mirror_cell(cell)

	# 提示格改由遮罩层自己画
	_board_view.clear_hint_cells()
	if not _mask_layer.visible:
		_fade_in_mask_layer()


func _instantiate_mask_temp(cell: Vector2i) -> CellView:
	var s: float = _board_view.scale.x
	var local_rect: Rect2 = _board_view.cell_to_local_rect(cell.x, cell.y)
	var top_left: Vector2 = _board_container.position + local_rect.position * s

	var src: CellView = _board_view.get_cell_view(cell.x, cell.y)
	var should_freeze_idle: bool = _uses_new_guide_flow()
	var temp: CellView = _CELL_SCENE.instantiate() as CellView

	temp.pivot_offset_ratio = Vector2.ZERO
	temp.pivot_offset = Vector2.ZERO
	temp.position = top_left
	temp.scale = Vector2(s, s)

	temp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask_layer.add_child(temp)

	temp.set_corner_radius_compensated(s, _board_view.get_puzzle_size())

	temp.set_round_corners(_board_view.corner_round_mask_for(cell.x, cell.y))

	temp.apply_cell_face_px(float(_board_view.get_grid_cell_face_px()))

	temp.apply_cross_art_variant()
	if src != null:
		temp.set_region_color(src.get_region_color())
		if should_freeze_idle:
			src.freeze_cat_idle()
			_mask_frozen_source_cells[cell] = true
	if should_freeze_idle:
		temp.freeze_cat_idle()
	_mask_hint_cells[cell] = temp
	return temp


## 铺一个带「提示闪烁」动画的遮罩格
func _spawn_mask_hint_cell(cell: Vector2i) -> void:
	var temp: CellView = _instantiate_mask_temp(cell)
	temp.play_hint()


## 铺一个镜像格：照抄棋盘上该格的状态，不播提示动画
func _spawn_mask_mirror_cell(cell: Vector2i) -> void:
	var temp: CellView = _instantiate_mask_temp(cell)
	var src: CellView = _board_view.get_cell_view(cell.x, cell.y)
	if src != null:
		temp.change_state({"state": src.get_state(), "play_anim": false})


func _clear_mask_hint_cells() -> void:
	for key in _mask_hint_cells.keys():
		if _mask_frozen_source_cells.has(key):
			var src: CellView = _board_view.get_cell_view(key.x, key.y)
			if src != null:
				src.resume_cat_idle()
		(_mask_hint_cells[key] as CellView).queue_free()
	_mask_hint_cells.clear()
	_mask_frozen_source_cells.clear()


## 棋盘某格状态变了，同步给遮罩层里的同名副本
func _mirror_state_to_mask_hint_cell(r: int, c: int, state: int) -> void:
	var key := Vector2i(r, c)
	if _mask_hint_cells.has(key):
		(_mask_hint_cells[key] as CellView).change_state({"state": state})


func _fade_in_mask_layer() -> void:
	if _mask_tween != null and _mask_tween.is_valid():
		_mask_tween.kill()
	_mask_layer.modulate.a = 0.0
	_mask_layer.visible = true
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask_layer, "modulate:a", 1.0, 0.12)


func _fade_out_mask_layer() -> void:
	if not _mask_layer.visible:
		return
	if _mask_tween != null and _mask_tween.is_valid():
		_mask_tween.kill()
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask_layer, "modulate:a", 0.0, 0.12)
	_mask_tween.tween_callback(
		func() -> void:
			_mask_layer.visible = false
			_mask_layer.modulate.a = 1.0
	)


## 默认流程的彩带效果：页面顶部随机生成 30 片彩色纸片下落，落完自毁
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


func _on_hint_tool_panel_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if _current_mode != StepMode.FREE_PLAY:
		return
	if ABTestManager.nu_guide.is_new_guide_flow():
		_show_g2_game_hint()
	else:
		_step7_show_hint()


func _on_hint_btn_pressed() -> void:
	if _current_mode != StepMode.FREE_PLAY:
		return
	if not ABTestManager.nu_guide.is_new_guide_flow():
		return
	_show_g2_game_hint()


func _show_g2_game_hint() -> void:
	if _hint_overlay.visible or not _g2_hint_data.is_empty():
		return
	var solution: Array = []
	for r: int in range(4):
		var row: Array[bool] = []
		row.resize(4)
		row.fill(false)
		solution.append(row)
	for cell: Vector2i in TUTORIAL_SOLUTION:
		(solution[cell.x] as Array)[cell.y] = true
	_g2_hint_data = (
		_G2_COPY
		. find_next_hint(
			_board_view.get_cell_state_folded_board(),
			_guide_regions,
			solution,
			ABTestManager.hint_func.has_color_exclude(),
			ABTestManager.hint_func.has_reverse_set_locking(),
		)
	)
	if not _g2_hint_data.get("found", false):
		_g2_hint_data = {}
		return
	_show_g2_hint_cells(_g2_hint_data)
	SoundManager.play(SoundManager.Kind.USE_HINT)
	_hint_overlay.show_hint(_g2_hint_data)


func _show_g2_hint_cells(hint: Dictionary) -> void:
	_clear_g2_hint_highlights()
	_board_view.clear_hint_cells()
	_g2_hint_highlight_layer = CanvasLayer.new()
	_g2_hint_highlight_layer.name = "G2HintHighlightLayer"
	_g2_hint_highlight_layer.layer = _hint_overlay.layer + 1
	add_child(_g2_hint_highlight_layer)

	var strategy: String = hint.get("strategy", "")
	if strategy == "R1_mark":
		var cat_cell: Vector2i = hint.get("cat_cell", Vector2i(-1, -1))
		if cat_cell.x >= 0 and cat_cell.y >= 0:
			var cat_copy: CellView = _spawn_g2_hint_temp_cell(cat_cell)
			cat_copy.play_hint()
		var mark_index: int = 0
		var mark_cells: Array = hint.get("unit_cells", [])
		for cell_value: Variant in mark_cells:
			var mark_cell: Vector2i = cell_value as Vector2i
			var mark_copy: CellView = _spawn_g2_hint_temp_cell(mark_cell)
			mark_copy.play_r2_preview(mark_index * 0.06)
			mark_index += 1
	elif hint.has("cell"):
		var target_cell: Vector2i = hint.get("cell", Vector2i(-1, -1))
		if target_cell.x >= 0 and target_cell.y >= 0:
			var target_copy: CellView = _spawn_g2_hint_temp_cell(target_cell)
			target_copy.play_hint()
	else:
		var highlight_cells: Array = hint.get("highlight_cells", [])
		for cell_value: Variant in highlight_cells:
			var highlight_cell: Vector2i = cell_value as Vector2i
			var highlight_copy: CellView = _spawn_g2_hint_temp_cell(highlight_cell)
			highlight_copy.play_hint()


func _spawn_g2_hint_temp_cell(cell: Vector2i) -> CellView:
	var board_scale: float = _board_view.scale.x
	var local_rect: Rect2 = _board_view.cell_to_local_rect(cell.x, cell.y)
	var top_left: Vector2 = _board_view.global_position + local_rect.position * board_scale
	var source: CellView = _board_view.get_cell_view(cell.x, cell.y)
	var temp: CellView = _CELL_SCENE.instantiate() as CellView
	temp.name = "TempCell_%d_%d" % [cell.x, cell.y]
	temp.pivot_offset_ratio = Vector2.ZERO
	temp.pivot_offset = Vector2.ZERO
	temp.position = top_left
	temp.scale = Vector2(board_scale, board_scale)
	temp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_g2_hint_highlight_layer.add_child(temp)
	temp.set_corner_radius_compensated(board_scale, _board_view.get_puzzle_size())
	temp.set_round_corners(_board_view.corner_round_mask_for(cell.x, cell.y))
	temp.apply_cell_face_px(float(_board_view.get_grid_cell_face_px()))
	temp.apply_cross_art_variant()
	if source != null:
		temp.set_region_color(source.get_region_color())
		if source.get_pattern_tex() != null:
			temp.configure_pattern(source.get_pattern_tex(), source.get_pattern_color())
			temp.set_pattern_mode(source.is_pattern_on(), true)
		var source_state: int = source.get_state()
		if not CellState.is_blank(source_state):
			var view_state: int = CellState.CAT if source_state == CellState.CAT else CellState.MARK
			temp.change_state({"state": view_state, "play_anim": false})
	return temp


func _clear_g2_hint_highlights() -> void:
	if _g2_hint_highlight_layer == null:
		return
	if _g2_hint_highlight_layer.is_inside_tree():
		_g2_hint_highlight_layer.get_parent().remove_child(_g2_hint_highlight_layer)
	_g2_hint_highlight_layer.queue_free()
	_g2_hint_highlight_layer = null


func _on_g2_hint_applied() -> void:
	if not ABTestManager.nu_guide.is_new_guide_flow() or _g2_hint_data.is_empty():
		return
	var actions: Array[Dictionary] = (
		_G2_COPY
		. hint_actions(
			_g2_hint_data,
			_board_view.get_cell_state_folded_board(),
			_guide_regions,
		)
	)
	var applied_state: int = CellState.EMPTY
	for action: Dictionary in actions:
		var cell: Vector2i = action.get("cell", Vector2i(-1, -1))
		var state: int = action.get("state", CellState.EMPTY)
		if cell.x < 0:
			continue
		(
			_board_view
			. set_cell_state(
				cell.x,
				cell.y,
				state,
				true,
				true,
				BoardView.ChangeSource.HINT,
			)
		)
		applied_state = state
	if applied_state == CellState.CAT:
		VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_CAT)
	elif applied_state == CellState.MARK:
		VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_MARK)
	elif not actions.is_empty():
		VibrateManager.play_at(VibrateManager.Pos.HINT_CLEAR)
	_cleanup_g2_hint()
	_check_free_play_complete()


func _on_g2_hint_dismissed() -> void:
	_cleanup_g2_hint()


func _on_g2_hint_detail_requested() -> void:
	_hint_overlay.update_desc(_g2_hint_data.get("description", ""))
	_hint_overlay.show_dismiss_btn()


func _cleanup_g2_hint() -> void:
	if _hint_overlay != null:
		_hint_overlay.visible = false
	_clear_g2_hint_highlights()
	if _board_view != null:
		_board_view.clear_hint_cells()
	_g2_hint_data = {}


## 确认按钮回调（场景里接的是 tag_pressed 信号）：只有 CONFIRM 模式放行
func _on_confirm_btn_pressed() -> void:
	if _current_mode != StepMode.CONFIRM:
		return
	_step_completed.emit()


## 判断某格是否在当前步骤允许操作的名单里
func _is_allowed(r: int, c: int) -> bool:
	for cell in _allowed_cells:
		if cell == Vector2i(r, c):
			return true
	return false


func _on_board_cell_drag_start(pos: Vector2) -> void:
	var cell: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)
	if cell.x < 0:
		return
	var row: int = cell.y
	var column: int = cell.x
	var start_state: int = _board_view.get_cell_state(row, column)

	if _current_mode == StepMode.NONE or start_state == CellState.ERROR:
		return
	var can_seed_from_cat: bool = (
		start_state == CellState.CAT and _current_mode in [StepMode.MARK_CELLS, StepMode.FREE_PLAY]
	)
	if start_state == CellState.CAT and not can_seed_from_cat:
		return

	if _current_mode == StepMode.FREE_PLAY and _step7_hint_phase > 0:
		if not can_seed_from_cat and not _is_allowed(row, column):
			return
	elif (
		_current_mode != StepMode.FREE_PLAY
		and not can_seed_from_cat
		and not _is_allowed(row, column)
	):
		return
	_drag_start_cell = Vector2i(row, column)
	_drag_last_cell = _drag_start_cell
	_drag_had_move = false
	_drag_start_processed = false
	_drag_target_pending = false

	if _current_mode == StepMode.FREE_PLAY and (_step7_hint_phase == 0 or _step7_hint_phase == 3):
		if start_state == CellState.CAT:
			_drag_target_pending = true
		else:
			_drag_target_state = (
				CellState.MARK if CellState.is_blank(start_state) else CellState.EMPTY
			)
	if ABTestManager.guide_eliminate.is_press_aligned():
		var mode_before_tap: int = _current_mode
		var hint_phase_before_tap: int = _step7_hint_phase
		var marked_count_before_tap: int = _marked_count
		_drag_start_processed = true
		var consumed_double_tap: bool = _dispatch_tap(row, column)
		var completed_mark_step: bool = (
			mode_before_tap == StepMode.MARK_CELLS
			and _required_marks > 0
			and marked_count_before_tap < _required_marks
			and _marked_count >= _required_marks
		)
		var interaction_advanced: bool = _interaction_advanced(
			mode_before_tap, hint_phase_before_tap
		)
		if consumed_double_tap or completed_mark_step or interaction_advanced:
			_reset_drag_gesture()


func _on_board_cell_drag_over(pos: Vector2) -> void:
	var cell: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)
	if cell.x < 0:
		return
	var stop_when_interaction_advances: bool = ABTestManager.guide_eliminate.is_press_aligned()
	var mode_before_motion: int = _current_mode
	var hint_phase_before_motion: int = _step7_hint_phase
	var row: int = cell.y
	var column: int = cell.x
	if _drag_start_cell == Vector2i(-1, -1):
		return
	var current_cell := Vector2i(row, column)
	if current_cell != _drag_start_cell:
		_drag_had_move = true
	var row_delta: int = current_cell.x - _drag_last_cell.x
	var column_delta: int = current_cell.y - _drag_last_cell.y
	var step_count: int = maxi(absi(row_delta), absi(column_delta))
	var first_step: int = 0 if not _drag_start_processed else 1
	if step_count == 0:
		if not _drag_start_processed:
			_apply_drag_cell(current_cell.x, current_cell.y, true)
			if (
				stop_when_interaction_advances
				and _interaction_advanced(mode_before_motion, hint_phase_before_motion)
			):
				_reset_drag_gesture()
				return
	else:
		for step in range(first_step, step_count + 1):
			var path_row: int = (
				_drag_last_cell.x + int(roundi(float(row_delta) * step / step_count))
			)
			var path_column: int = (
				_drag_last_cell.y + int(roundi(float(column_delta) * step / step_count))
			)
			_apply_drag_cell(path_row, path_column, step == step_count)
			if (
				stop_when_interaction_advances
				and _interaction_advanced(mode_before_motion, hint_phase_before_motion)
			):
				_reset_drag_gesture()
				return
	_drag_last_cell = current_cell
	_drag_start_processed = true


func _apply_drag_cell(row: int, column: int, is_current: bool) -> void:
	if _current_mode == StepMode.MARK_CELLS and _is_allowed(row, column):
		if CellState.is_blank(_board_view.get_cell_state(row, column)):
			_board_view.set_cell_state(row, column, CellState.MARK)
			_mirror_state_to_mask_hint_cell(row, column, CellState.MARK)
			_g2_stop_glow_at(row, column)
			if is_current:
				VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_MARK)
			_marked_count += 1
			if _marked_count >= _required_marks:
				_step_completed.emit()

	elif _current_mode == StepMode.FREE_PLAY and (_step7_hint_phase == 1 or _step7_hint_phase == 2):
		if _is_allowed(row, column) and CellState.is_blank(_board_view.get_cell_state(row, column)):
			_board_view.set_cell_state(row, column, CellState.MARK)
			_mirror_state_to_mask_hint_cell(row, column, CellState.MARK)
			if is_current:
				VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_MARK)
			_step7_check_phase_complete()

	elif _current_mode == StepMode.FREE_PLAY and (_step7_hint_phase == 0 or _step7_hint_phase == 3):
		var current_state: int = _board_view.get_cell_state(row, column)

		if current_state == CellState.CAT or current_state == CellState.ERROR:
			return
		if _drag_target_pending:
			_drag_target_state = (
				CellState.MARK if CellState.is_blank(current_state) else CellState.EMPTY
			)
			_drag_target_pending = false
		if current_state == _drag_target_state:
			return
		_board_view.set_cell_state(row, column, _drag_target_state)
		_mirror_state_to_mask_hint_cell(row, column, _drag_target_state)
		if is_current:
			VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_MARK)


func _on_board_cell_drag_end(release_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _drag_start_cell == Vector2i(-1, -1):
		return
	if ABTestManager.guide_eliminate.is_press_aligned():
		_reset_drag_gesture()
		return
	var release_cell: Vector2i = _board_view.pointer_to_cell(release_pos.x, release_pos.y)
	var release_row_column := Vector2i(release_cell.y, release_cell.x)
	if release_cell.x >= 0 and release_row_column != _drag_last_cell:
		_on_board_cell_drag_over(release_pos)
	if _drag_had_move:
		_reset_drag_gesture()
		return

	var row: int = _drag_start_cell.x
	var column: int = _drag_start_cell.y
	_reset_drag_gesture()
	_dispatch_tap(row, column)


func _dispatch_tap(row: int, column: int) -> bool:
	if _board_view.get_cell_state(row, column) == CellState.CAT:
		return false

	var matched_double_tap_window: bool = _last_tap_cell == Vector2i(row, column)
	_log_double_tap_interval(row, column)
	match _current_mode:
		StepMode.MARK_CELLS:
			_handle_mark_tap(row, column)
		StepMode.PLACE_CAT:
			_handle_place_cat_tap(row, column)
		StepMode.FREE_PLAY:
			_handle_free_play_tap(row, column)
	return matched_double_tap_window and _last_tap_cell != Vector2i(row, column)


func _reset_drag_gesture() -> void:
	_drag_start_cell = Vector2i(-1, -1)
	_drag_last_cell = Vector2i(-1, -1)
	_drag_had_move = false
	_drag_target_pending = false
	_drag_start_processed = false


func _interaction_advanced(mode_before: int, hint_phase_before: int) -> bool:
	return mode_before != _current_mode or hint_phase_before != _step7_hint_phase


func _handle_mark_tap(r: int, c: int) -> void:
	if not CellState.is_blank(_board_view.get_cell_state(r, c)):
		return
	_board_view.set_cell_state(r, c, CellState.MARK)
	_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
	_g2_stop_glow_at(r, c)
	VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_MARK)
	_marked_count += 1
	if _marked_count >= _required_marks:
		_step_completed.emit()


func _handle_place_cat_tap(r: int, c: int) -> void:
	if _last_tap_cell == Vector2i(r, c):
		_last_tap_cell = Vector2i(-1, -1)

		_g2_stop_glow_at(r, c)
		_place_cat(r, c)
		VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_CAT)
		_step_completed.emit()
	else:
		_open_double_tap_window(r, c, true)


func _handle_free_play_tap(r: int, c: int) -> void:
	if _g2_conflict_busy:
		return

	if _step7_hint_phase == 1 or _step7_hint_phase == 2:
		if not _is_allowed(r, c):
			return
		var state := _board_view.get_cell_state(r, c)
		if CellState.is_blank(state):
			_board_view.set_cell_state(r, c, CellState.MARK)
			_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
			VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_MARK)
		elif state == CellState.MARK:
			_board_view.set_cell_state(r, c, CellState.EMPTY)
			_mirror_state_to_mask_hint_cell(r, c, CellState.EMPTY)

		_step7_check_phase_complete()
		return

	if _is_allowed(r, c):
		if _last_tap_cell == Vector2i(r, c):
			_last_tap_cell = Vector2i(-1, -1)
			_place_cat(r, c)

			_mirror_state_to_mask_hint_cell(r, c, CellState.CAT)
			VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_CAT)
			_check_free_play_complete()
		else:
			_open_double_tap_window(r, c, true)
	elif _flash_on_wrong_tap and _last_tap_cell == Vector2i(r, c):
		_last_tap_cell = Vector2i(-1, -1)
		if _board_view.get_cell_state(r, c) == CellState.MARK:
			_board_view.set_cell_state(r, c, CellState.EMPTY)
			_mirror_state_to_mask_hint_cell(r, c, CellState.EMPTY)
		_g2_play_conflict(r, c)
	else:
		_do_single_tap_toggle(r, c)


## 检查第 7 步当前提示阶段的格子是否都打了叉，是则回到「放最后一只猫」状态
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


func _apply_step7_hint() -> void:
	if _step7_hint_phase == 1 or _step7_hint_phase == 2:
		for cell in _allowed_cells:
			if CellState.is_blank(_board_view.get_cell_state(cell.x, cell.y)):
				_board_view.set_cell_state(cell.x, cell.y, CellState.MARK)
				_mirror_state_to_mask_hint_cell(cell.x, cell.y, CellState.MARK)
		VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_MARK)
		_step7_check_phase_complete()
	elif _step7_hint_phase == 3:
		var target := Vector2i(2, 3)
		_place_cat(target.x, target.y)
		VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_CAT)
		_step7_hint_phase = 0
		_hide_hand()
		_clear_mask_hint_cells()
		if _mask_layer.visible:
			_fade_out_mask_layer()
		_check_free_play_complete()


func _do_single_tap_toggle(r: int, c: int) -> void:
	var cur: int = _board_view.get_cell_state(r, c)
	if CellState.is_blank(cur):
		_board_view.set_cell_state(r, c, CellState.MARK)
		_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
		VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_MARK)
	elif cur == CellState.MARK:
		_board_view.set_cell_state(r, c, CellState.EMPTY)
		_mirror_state_to_mask_hint_cell(r, c, CellState.EMPTY)

	_open_double_tap_window(r, c, false)


func _open_double_tap_window(r: int, c: int, on_solution_cat: bool) -> void:
	_double_tap_window_generation += 1
	var generation: int = _double_tap_window_generation
	_last_tap_cell = Vector2i(r, c)
	var sec: float = _double_tap_window_sec(r, c, on_solution_cat)
	_last_window_sec = sec
	_dbg_win_open_ms = Time.get_ticks_msec()
	_dbg_win_open_cell = Vector2i(r, c)
	get_tree().create_timer(sec).timeout.connect(
		func() -> void:
			if generation != _double_tap_window_generation:
				return
			if _last_tap_cell == Vector2i(r, c):
				_last_tap_cell = Vector2i(-1, -1)
	)


func _reset_double_tap_window() -> void:
	_double_tap_window_generation += 1
	_last_tap_cell = Vector2i(-1, -1)
	_dbg_win_open_ms = -1
	_dbg_win_open_cell = Vector2i(-1, -1)


func _double_tap_window_sec(r: int, c: int, on_solution_cat: bool) -> float:
	var cfg := ABTestManager.doubletap_protect
	var truth_has_cat: bool = cfg.needs_truth() and on_solution_cat
	var would_conflict: bool = cfg.needs_conflict() and _would_cat_conflict(r, c)
	return cfg.window_sec(truth_has_cat, would_conflict)


func _would_cat_conflict(r: int, c: int) -> bool:
	if _guide_regions.is_empty():
		return false
	var placed: Array = []
	for rr in range(4):
		for cc in range(4):
			if _board_view.get_cell_state(rr, cc) == CellState.CAT:
				placed.append(Vector2i(rr, cc))
	return QueendokuCore.classify_violation(r, c, placed, _guide_regions) != QueendokuCore.Rule.NONE


func _log_double_tap_interval(r: int, c: int) -> void:
	if r < 0 or OS.has_feature("rel"):
		return
	if _dbg_win_open_ms < 0 or _dbg_win_open_cell != Vector2i(r, c):
		return
	var interval: int = Time.get_ticks_msec() - _dbg_win_open_ms
	var hit: bool = _last_tap_cell == Vector2i(r, c)
	print(
		(
			"[doubletap][tutorial] cell=(%d,%d) interval=%dms window=%dms → %s"
			% [r, c, interval, int(round(_last_window_sec * 1000.0)), "HIT" if hit else "MISS"]
		)
	)
	_dbg_win_open_ms = -1
	_dbg_win_open_cell = Vector2i(-1, -1)


## 往格子里落猫：先清掉同格的叉，格子非空则不动
func _place_cat(r: int, c: int) -> void:
	if _board_view.get_cell_state(r, c) == CellState.MARK:
		_board_view.set_cell_state(r, c, CellState.EMPTY)
	if not CellState.is_blank(_board_view.get_cell_state(r, c)):
		return
	_board_view.set_cell_state(r, c, CellState.CAT)


func _check_free_play_complete() -> void:
	for sol in TUTORIAL_SOLUTION:
		if _board_view.get_cell_state(sol.x, sol.y) != CellState.CAT:
			return
	VibrateManager.play_at(VibrateManager.Pos.TUTORIAL_WIN)
	_step_completed.emit()


# ================= 消息面板与配色文案 =================
## 消息文本尺寸变化时，同步面板高度并重新对齐棋盘
func _on_msg_rich_resized() -> void:
	if not is_inside_tree():
		return
	# 面板高度 = 文本高度 + 上下内边距
	_msg_panel.size.y = _msg_rich.size.y + _MSG_PANEL_PADDING_Y * 2.0
	_align_msg_panel_to_board()


## 把消息面板贴着棋盘上沿摆放，间距用 _ready 里量到的值
func _align_msg_panel_to_board() -> void:
	var board_top: float = _board_container.global_position.y
	var msg_height: float = _msg_panel.size.y
	var pos: Vector2 = _msg_panel.global_position
	pos.y = board_top - _msg_to_board_gap - msg_height
	_msg_panel.global_position = pos


# ================= 颜色名工具 =================
## 取某格区域颜色的富文本片段（带色号），供文案指代「哪种颜色」
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
		[Color("#d3d551"), tr("COLOR_OLIVE_YELLOW")],
		[Color("#d86c90"), tr("COLOR_ROSE")],
		[Color("#767ae4"), tr("COLOR_PURPLE")],
		[Color("#e57ee0"), tr("COLOR_MAGENTA")],
		[Color("#e76f58"), tr("COLOR_ORANGE")],
		[Color("#dccf95"), tr("COLOR_YELLOW")],
		[Color("#7284b3"), tr("COLOR_DARK_BLUE")],
		[Color("#c0d1dc"), tr("COLOR_LIGHT_BLUE")],
		[Color("#399295"), tr("COLOR_TEAL")],
		[Color("#459a5e"), tr("COLOR_DARK_GREEN")],
		[Color("#99dbb1"), tr("COLOR_GREEN")],
		[Color("#a67b63"), tr("COLOR_BROWN")],
		[Color("#dc9e7c"), tr("COLOR_TAN")],
		[Color("#9d9041"), tr("COLOR_OLIVE_YELLOW")],
		[Color("#97cf7e"), tr("COLOR_GREEN")],
		[Color("#618f74"), tr("COLOR_DARK_GREEN")],
		[Color("#60d8d3"), tr("COLOR_TEAL")],
		[Color("#76a9cc"), tr("COLOR_SKY_BLUE")],
		[Color("#6881d0"), tr("COLOR_DARK_BLUE")],
		[Color("#aa68e5"), tr("COLOR_PURPLE")],
		[Color("#d899e4"), tr("COLOR_VIOLET")],
		[Color("#e55ca6"), tr("COLOR_MAGENTA")],
		[Color("#bb7e93"), tr("COLOR_ROSE")],
		[Color("#dc5b6a"), tr("COLOR_RED")],
	]

	if ABTestManager.region_color.is_palette_v13():
		(
			known
			. append_array(
				[
					[Color("#aed994"), tr("COLOR_LIGHT_GREEN")],
					[Color("#fab4d0"), tr("COLOR_LIGHT_PINK")],
					[Color("#e4bb49"), tr("COLOR_LIGHT_YELLOW")],
					[Color("#a7bfd7"), tr("COLOR_TEAL")],
					[Color("#6bbce7"), tr("COLOR_BLUE")],
					[Color("#d57374"), tr("COLOR_RED")],
					[Color("#ad6f48"), tr("COLOR_BROWN")],
					[Color("#5b75b2"), tr("COLOR_DARK_BLUE")],
					[Color("#9778d6"), tr("COLOR_PURPLE")],
					[Color("#48b5b2"), tr("COLOR_TURQUOISE")],
					[Color("#ffaa6d"), tr("COLOR_ORANGE")],
					[Color("#eb85b7"), tr("COLOR_PINK")],
				]
			)
		)
	elif ABTestManager.region_color.is_palette_v14():
		(
			known
			. append_array(
				[
					[Color("#f9d96a"), tr("COLOR_LIGHT_YELLOW")],
					[Color("#faaf5c"), tr("COLOR_ORANGE")],
					[Color("#d47363"), tr("COLOR_RED")],
					[Color("#ee92a7"), tr("COLOR_PINK")],
					[Color("#f9b0f7"), tr("COLOR_LIGHT_PINK")],
					[Color("#80db8c"), tr("COLOR_GREEN")],
					[Color("#c7c94a"), tr("COLOR_LIGHT_GREEN")],
					[Color("#46b4a9"), tr("COLOR_TURQUOISE")],
					[Color("#81d8e9"), tr("COLOR_SKY_BLUE")],
					[Color("#77afde"), tr("COLOR_BLUE")],
					[Color("#a590dd"), tr("COLOR_PURPLE")],
					[Color("#6862a8"), tr("COLOR_DARK_PURPLE")],
				]
			)
		)
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
