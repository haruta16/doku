class_name TutorialPage
extends UIFrameWindow

const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn")

const TUTORIAL_SOLUTION: Array[Vector2i] = [
	Vector2i(0, 2),
	Vector2i(1, 0),
	Vector2i(2, 3),
	Vector2i(3, 1),
]

var _guide_regions: Array = []
var _guide_color_map: Array[int] = []

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

enum StepMode { NONE, PLACE_CAT, MARK_CELLS, FREE_PLAY, CONFIRM }

signal _step_completed

var _flow_token: int = 0

var _current_mode: int = StepMode.NONE
var _allowed_cells: Array[Vector2i] = []
var _required_marks: int = 0
var _marked_count: int = 0

var _step7_hint_phase: int = 0

var _mask_hint_cells: Dictionary = {}
var _mask_tween: Tween = null

var _drag_start_cell: Vector2i = Vector2i(-1, -1)
var _drag_had_move: bool = false

var _drag_target_state: int = CellState.MARK
var _last_tap_cell: Vector2i = Vector2i(-1, -1)

var _swipe_hand_tween: Tween = null

var _guide_start_ms: int = 0

var _msg_to_board_gap: float = 0.0

const _MSG_PANEL_PADDING_Y: float = 40.0

const IQ_INIT: int = 60
const IQ_MAX: int = 180
const IQ_STEP: int = 20

const _IQ_BAR_PAD: float = 0.0
const _IQ_BAR_INNER_W: float = 592.0
var _iq_value: int = IQ_INIT


func _ready() -> void:
	_board_view.cell_drag_start.connect(_on_board_cell_drag_start)
	_board_view.cell_drag_over.connect(_on_board_cell_drag_over)
	_board_view.cell_drag_end.connect(_on_board_cell_drag_end)

	_hint_tool_panel.gui_input.connect(_on_hint_tool_panel_gui_input)

	_msg_rich.resized.connect(_on_msg_rich_resized)

	_msg_to_board_gap = _board_container.offset_top - _msg_panel.offset_bottom


func on_show(_params: Dictionary = {}) -> void:
	_flow_token += 1

	_step_completed.emit()
	_current_mode = StepMode.NONE
	_last_tap_cell = Vector2i(-1, -1)
	_drag_start_cell = Vector2i(-1, -1)
	_drag_had_move = false
	_reset_ui()
	_setup_board()

	call_deferred("_align_msg_panel_to_board")

	_guide_start_ms = Time.get_ticks_msec()
	Tracker.track_new_guide_show(1)

	if ABTestManager.guide_feedback.is_check_guide():
		await _run_guide_flow_check()
	elif ABTestManager.guide_feedback.is_iq_guide():
		await _run_guide_flow_iq()
	else:
		await _run_guide_flow_default()


func _run_guide_flow_default() -> void:
	var _tok: int = _flow_token
	await _step_1_place_first_cat()
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


func _play_check_feedback() -> void:
	_anim_guide_encourage.play("SuccessCheck")
	await _anim_guide_encourage.animation_finished


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


func _init_iq_bar() -> void:
	_iq_value = IQ_INIT
	_set_iq_fill_right(_iq_fill_right(float(IQ_INIT)))
	_set_iq_number(float(IQ_INIT))
	_iq_bar.visible = true
	_anim_guide_encourage.play("IqBarAppear")


func _play_iq_disappear() -> void:
	_anim_guide_encourage.play("IqBarDisAppear")
	await _anim_guide_encourage.animation_finished
	_iq_bar.visible = false


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


func _iq_fill_right(v: float) -> float:
	var frac: float = clampf(v / float(IQ_MAX), 0.0, 1.0)
	return _IQ_BAR_PAD + frac * _IQ_BAR_INNER_W


func _set_iq_fill_right(x: float) -> void:
	_iq_fill.offset_right = x


func _set_iq_number(v: float) -> void:
	_iq_label.text = tr("TUTORIAL_IQ_FORMAT") % int(round(v))


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

	for r in range(4):
		for c in range(4):
			var cv: CellView = _board_view.get_cell_view(r, c)
			if cv != null and cv.get_state() != CellState.EMPTY:
				cv.change_state({"state": CellState.EMPTY, "play_anim": false})


func _step1_rich_action_line() -> String:
	var hl: String = tr("TUTORIAL_STEP1_HIGHLIGHT")
	var breath_seg: String = (
		"[breath amp=0.03 freq=5 group=1 count=%d][color=#d94848]%s[/color][/breath]"
		% [hl.length(), hl]
	)
	return tr("TUTORIAL_STEP1_RICH").format({"breath": breath_seg})


func _step1_feedback_combined_msg() -> String:
	return tr("TUTORIAL_STEP1_ONE_PER_COLOR") + "\n" + _step1_rich_action_line()


func _step_1_place_first_cat(override_msg: String = "") -> void:
	if override_msg != "":
		_show_message("[center]" + override_msg + "[/center]")
	else:
		_show_message("[center]" + _step1_rich_action_line() + "[/center]")
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
	await get_tree().create_timer(0.4).timeout


func _step_2_confirm_one_per_color() -> void:
	_show_message("[center]" + tr("TUTORIAL_STEP2_RICH") + "[/center]")
	_show_confirm_btn(tr("TUTORIAL_GOT_IT"))
	_current_mode = StepMode.CONFIRM
	await _step_completed
	_current_mode = StepMode.NONE
	_hide_confirm_btn()


func _step_3_mark_row_col() -> void:
	_show_message("[center]" + tr("TUTORIAL_STEP5_RICH") + "[/center]")

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
	await get_tree().create_timer(0.4).timeout


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


func _step_6_place_third_cat() -> void:
	var _blue_msg: String
	if not ABTestManager.region_color.value() == RegionColorConfig.VALUE_CONTROL:
		var _cbb: String = _color_name_bbcode_for_cell(1, 0)
		_blue_msg = tr("TUTORIAL_STEP4_COLOR_RICH") % _cbb
	else:
		_blue_msg = tr("TUTORIAL_STEP4_BLUE_RICH")
	_show_message("[center]" + _blue_msg + "[/center]")
	var target := Vector2i(1, 0)

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


func _step7_show_hint() -> void:
	if _step7_hint_phase > 0:
		_apply_step7_hint()
		return

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

	_hide_hand()
	_clear_mask_hint_cells()
	if _mask_layer.visible:
		_fade_out_mask_layer()
	_allowed_cells = [TARGET]

	if blue_row_empty.size() > 0:
		_step7_hint_phase = 1
		_allowed_cells = blue_row_empty
		_show_message("[center]" + tr("TUTORIAL_STEP7_ROW_BLUE") + "[/center]")
		_show_mask_hints(blue_row_empty, [BLUE_CAT])
	elif pink_row_empty.size() > 0:
		_step7_hint_phase = 2
		_allowed_cells = pink_row_empty
		_show_message("[center]" + tr("TUTORIAL_STEP7_ROW_PINK") + "[/center]")
		_show_mask_hints(pink_row_empty, [PINK_CAT])
	else:
		_step7_hint_phase = 3
		_allowed_cells = [TARGET]
		_show_message("[center]" + tr("TUTORIAL_STEP7_PLACE_LAST") + "[/center]")
		_show_mask_hints([TARGET])
		_position_hand_at_cell(TARGET)
		_show_hand()


func _step_finish(use_fireworks: bool = false) -> void:
	_show_message("[center]" + tr("TUTORIAL_STEP6_RICH") + "[/center]")
	_show_confirm_btn(tr("TUTORIAL_START_GAME"))

	if use_fireworks:
		_anim_effect_fireworks.play("Flreworks")

		_hide_iq_bar_after_fireworks()
	else:
		_spawn_confetti()
	_current_mode = StepMode.CONFIRM
	await _step_completed
	_current_mode = StepMode.NONE
	complete_tutorial()


func _hide_iq_bar_after_fireworks() -> void:
	await _anim_effect_fireworks.animation_finished
	await _play_iq_disappear()


func complete_tutorial() -> void:
	var time_sec: float = (Time.get_ticks_msec() - _guide_start_ms) / 1000.0
	Tracker.track_new_guide_end(1, time_sec)
	GameState.set_tutorial_done(true)
	UIManager.show_ui(UiName.GAME, {"level_index": 1})


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


func _show_message(text: String) -> void:
	_msg_rich.text = text
	_anim_msg_appear_2.play("MessagePanel_appear_2")


func _show_sub_message(text: String) -> void:
	_sub_msg_rich.text = text
	_sub_msg_panel.visible = true
	_anim_sub_msg_appear.play("SubMsgPanel_appear")


func _hide_sub_message() -> void:
	_sub_msg_panel.visible = false


func _show_hint_tool_panel() -> void:
	_hint_tool_panel.visible = true
	_anim_hint_tool_appear.play("HintToolPanel_appear")


func _hide_hint_tool_panel() -> void:
	_hint_tool_panel.visible = false


func _show_confirm_btn(text: String) -> void:
	_confirm_btn.set("btn_text", text)
	_confirm_btn.visible = true
	_anim_confirm_loop.play("ConfirmBtn_loop")


func _hide_confirm_btn() -> void:
	_confirm_btn.visible = false
	_anim_confirm_loop.stop()


func _show_hand() -> void:
	_hand_hint.visible = true
	_hand_spine.get_animation_state().set_animation("click", true, 0)


func _hide_hand() -> void:
	_hand_hint.visible = false


func _position_select_frame(cell: Vector2i) -> void:
	var s: float = _board_view.scale.x
	var rect: Rect2 = _board_view.cell_to_local_rect(cell.x, cell.y)
	var pad: float = 8.0
	_select_frame.position = rect.position * s - Vector2(pad, pad)
	_select_frame.size = rect.size * s + Vector2(pad * 2.0, pad * 2.0)


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
	for cell in cells:
		offsets.append(
			Vector2(111.0 + (cell.y - 2) * slot_screen, -316.0 + (cell.x - 0) * slot_screen)
		)
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


func _stop_swipe_hand_loop() -> void:
	if _swipe_hand_tween != null and _swipe_hand_tween.is_valid():
		_swipe_hand_tween.kill()
	_swipe_hand_tween = null
	_hand_hint.modulate.a = 1.0
	_hand_static.visible = false
	_hand_spine.visible = true


func _move_sub_msg_below_board() -> void:
	await get_tree().process_frame
	var board_bottom: float = _board_container.position.y + _board_container.size.y
	var screen_center_y: float = size.y * 0.5
	var offset_top: float = board_bottom - screen_center_y + 30.0
	_sub_msg_panel.offset_top = offset_top
	_sub_msg_panel.offset_bottom = offset_top + 190.0


func _show_mask_hints(cells: Array[Vector2i], mirror_cells: Array[Vector2i] = []) -> void:
	for cell in cells:
		_spawn_mask_hint_cell(cell)
	for cell in mirror_cells:
		_spawn_mask_mirror_cell(cell)

	_board_view.clear_hint_cells()
	if not _mask_layer.visible:
		_fade_in_mask_layer()


func _instantiate_mask_temp(cell: Vector2i) -> CellView:
	var s: float = _board_view.scale.x
	var local_rect: Rect2 = _board_view.cell_to_local_rect(cell.x, cell.y)
	var top_left: Vector2 = _board_container.position + local_rect.position * s

	var src: CellView = _board_view.get_cell_view(cell.x, cell.y)
	var temp: CellView = _CELL_SCENE.instantiate() as CellView

	temp.pivot_offset_ratio = Vector2.ZERO
	temp.pivot_offset = Vector2.ZERO
	temp.position = top_left
	temp.scale = Vector2(s, s)

	temp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask_layer.add_child(temp)

	temp.set_corner_radius_compensated(s)
	if src != null:
		temp.set_region_color(src.get_region_color())
	_mask_hint_cells[cell] = temp
	return temp


func _spawn_mask_hint_cell(cell: Vector2i) -> void:
	var temp: CellView = _instantiate_mask_temp(cell)
	temp.play_hint()


func _spawn_mask_mirror_cell(cell: Vector2i) -> void:
	var temp: CellView = _instantiate_mask_temp(cell)
	var src: CellView = _board_view.get_cell_view(cell.x, cell.y)
	if src != null:
		temp.change_state({"state": src.get_state(), "play_anim": false})


func _clear_mask_hint_cells() -> void:
	for key in _mask_hint_cells.keys():
		(_mask_hint_cells[key] as CellView).queue_free()
	_mask_hint_cells.clear()


func _mirror_state_to_mask_hint_cell(r: int, c: int, state: int) -> void:
	var key := Vector2i(r, c)
	if _mask_hint_cells.has(key):
		(_mask_hint_cells[key] as CellView).change_state({"state": state})


func _fade_in_mask_layer() -> void:
	if _mask_tween != null and _mask_tween.is_valid():
		_mask_tween.kill()
	_mask_layer.modulate.a = 0.0
	_mask_layer.visible = true
	if _iq_bar.visible:
		_iq_label.add_theme_color_override("font_color", Color(1, 0.8, 0, 1))
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
			if _iq_bar.visible:
				_iq_label.add_theme_color_override("font_color", Color(0.576, 0.353, 0.353, 1))
	)


func _spawn_confetti() -> void:
	var colors: Array[Color] = [
		Color("#FF5252"),
		Color("#448AFF"),
		Color("#69F0AE"),
		Color("#FFD740"),
		Color("#FF4081"),
		Color("#40C4FF"),
	]
	for _i in range(30):
		var rect := ColorRect.new()
		var w: float = randf_range(6.0, 14.0)
		var h: float = randf_range(10.0, 22.0)
		rect.size = Vector2(w, h)
		rect.color = colors[randi() % colors.size()]
		rect.rotation = randf() * PI * 2.0
		rect.position = Vector2(randf_range(40.0, 1040.0), randf_range(-150.0, -40.0))
		rect.z_index = 10
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

	_step7_show_hint()


func _on_confirm_btn_pressed() -> void:
	if _current_mode != StepMode.CONFIRM:
		return
	_step_completed.emit()


func _is_allowed(r: int, c: int) -> bool:
	for cell in _allowed_cells:
		if cell == Vector2i(r, c):
			return true
	return false


func _on_board_cell_drag_start(pos: Vector2) -> void:
	var cell: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)
	if cell.x < 0:
		return
	var r: int = cell.y
	var c: int = cell.x
	if _current_mode == StepMode.NONE or _board_view.get_cell_state(r, c) == CellState.CAT:
		return

	if _current_mode == StepMode.FREE_PLAY and _step7_hint_phase > 0:
		if not _is_allowed(r, c):
			return
	elif _current_mode != StepMode.FREE_PLAY and not _is_allowed(r, c):
		return
	_drag_start_cell = Vector2i(r, c)
	_drag_had_move = false

	if _current_mode == StepMode.FREE_PLAY and (_step7_hint_phase == 0 or _step7_hint_phase == 3):
		var cur: int = _board_view.get_cell_state(r, c)
		_drag_target_state = CellState.MARK if CellState.is_blank(cur) else CellState.EMPTY


func _on_board_cell_drag_over(pos: Vector2) -> void:
	var cell: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)
	if cell.x < 0:
		return
	var r: int = cell.y
	var c: int = cell.x
	if _drag_start_cell == Vector2i(-1, -1):
		return
	if Vector2i(r, c) != _drag_start_cell:
		_drag_had_move = true

	if _current_mode == StepMode.MARK_CELLS and _is_allowed(r, c):
		if CellState.is_blank(_board_view.get_cell_state(r, c)):
			_board_view.set_cell_state(r, c, CellState.MARK)
			_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
			VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
			_marked_count += 1
			if _marked_count >= _required_marks:
				_step_completed.emit()

	elif _current_mode == StepMode.FREE_PLAY and (_step7_hint_phase == 1 or _step7_hint_phase == 2):
		if _is_allowed(r, c) and CellState.is_blank(_board_view.get_cell_state(r, c)):
			_board_view.set_cell_state(r, c, CellState.MARK)
			_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
			VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
			_step7_check_phase_complete()

	elif _current_mode == StepMode.FREE_PLAY and (_step7_hint_phase == 0 or _step7_hint_phase == 3):
		var cur: int = _board_view.get_cell_state(r, c)
		if cur == CellState.CAT or cur == _drag_target_state:
			return
		_board_view.set_cell_state(r, c, _drag_target_state)
		_mirror_state_to_mask_hint_cell(r, c, _drag_target_state)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)


func _on_board_cell_drag_end() -> void:
	if _drag_start_cell == Vector2i(-1, -1):
		return
	if _drag_had_move:
		_drag_start_cell = Vector2i(-1, -1)
		_drag_had_move = false
		return

	var r: int = _drag_start_cell.x
	var c: int = _drag_start_cell.y
	_drag_start_cell = Vector2i(-1, -1)
	_drag_had_move = false

	match _current_mode:
		StepMode.MARK_CELLS:
			_handle_mark_tap(r, c)
		StepMode.PLACE_CAT:
			_handle_place_cat_tap(r, c)
		StepMode.FREE_PLAY:
			_handle_free_play_tap(r, c)


func _handle_mark_tap(r: int, c: int) -> void:
	if not CellState.is_blank(_board_view.get_cell_state(r, c)):
		return
	_board_view.set_cell_state(r, c, CellState.MARK)
	_mirror_state_to_mask_hint_cell(r, c, CellState.MARK)
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
	_marked_count += 1
	if _marked_count >= _required_marks:
		_step_completed.emit()


func _handle_place_cat_tap(r: int, c: int) -> void:
	if _last_tap_cell == Vector2i(r, c):
		_last_tap_cell = Vector2i(-1, -1)
		_place_cat(r, c)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)
		_step_completed.emit()
	else:
		_last_tap_cell = Vector2i(r, c)
		get_tree().create_timer(0.35).timeout.connect(
			func() -> void:
				if _last_tap_cell == Vector2i(r, c):
					_last_tap_cell = Vector2i(-1, -1)
		)


func _handle_free_play_tap(r: int, c: int) -> void:
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


func _step7_check_phase_complete() -> void:
	for cell in _allowed_cells:
		if _board_view.get_cell_state(cell.x, cell.y) != CellState.MARK:
			return

	_step7_hint_phase = 0
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
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
		_step7_check_phase_complete()
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


func _do_single_tap_toggle(r: int, c: int) -> void:
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
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL5)
	_step_completed.emit()


func _on_msg_rich_resized() -> void:
	if not is_inside_tree():
		return
	_msg_panel.size.y = _msg_rich.size.y + _MSG_PANEL_PADDING_Y * 2.0
	_align_msg_panel_to_board()


func _align_msg_panel_to_board() -> void:
	var board_top: float = _board_container.global_position.y
	var msg_height: float = _msg_panel.size.y
	var pos: Vector2 = _msg_panel.global_position
	pos.y = board_top - _msg_to_board_gap - msg_height
	_msg_panel.global_position = pos


func _color_name_bbcode_for_cell(r: int, c: int) -> String:
	var region_idx: int = (
		_guide_regions[r][c] if r < _guide_regions.size() and c < _guide_regions[r].size() else -1
	)
	if region_idx < 0:
		return tr("HINT_SOME_COLOR")
	var cell_color: Color = _board_view.get_region_color(region_idx)
	var hex: String
	var name: String
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
	]
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
