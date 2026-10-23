## 每日挑战游戏页：按日期选择题目，管理独立计时、残局恢复、重玩与挑战结算。
class_name DailyGamePage
extends BaseGamePage

const SettingScene: PackedScene = preload("res://scripts/module/setting/ui/setting_page.tscn") # 设置页场景预加载（本脚本内没引用，疑似历史遗留）

const _ELO_EXTRA_PLACEHOLDER: Dictionary = {
	"eloRating": -1.0,
	"eValue": -1.0,
	"kValue": -1.0,
	"playerRating": -1.0,
}
const _ELO_END_EXTRA_PLACEHOLDER: Dictionary = {
	"eloRating": -1.0,
	"eValue": -1.0,
	"kValue": -1.0,
	"playerRating": -1.0,
	"sValue": -1.0,
	"playerRatingNew": -1.0,
}

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _date_label: Label = $Root/VBoxContainer/Header/DateLabel # 头部日期文案（部分实验档会隐藏）
@onready var _level_display_value: Label = $Root/VBoxContainer/Header/LevelDisplay/Value # 头部「月/日」数字显示
## 计时文字（@onready 与变量声明分两行写的那个）
@onready
var _timer_label: Label = $Root/VBoxContainer/CatHeartRow/TimeContainer/HBoxContainer/TimerCtrl/TimerLabel

# ---- 运行时状态 ----
var _start_unix: float = 0.0 # 计时起点（Unix 秒）；广告占用的时长之后会补掉
var _start_date: String = "" # 开局日期 yyyy-mm-dd，通关时写进存档
var _ad_show_unix: float = 0.0 # 广告开始播放的时刻，> 0 表示有一段广告时长待扣除

var _dc_restore_snapshot: Dictionary = {}

var _clock_base_sec: float = 0.0

@onready var _back_setting_header: BackAndSettingHeader = $Root/VBoxContainer/Header

var _entry_btn_lock_seq: int = 0 # 锁按钮的次数，只累加不做判断（排查动画重入用）

var _in_game_costume_id: int = CostumeCatalog.DEFAULT_COSTUME_ID

@onready var _dc_toast: DailyStartToast = $Root/DcStartToast

static var debug_day_override: int = -1 # 调试开关：强制把「今天」当成第 N 天，-1 = 关闭


# ================= 生命周期 =================
## 埋点用的游戏类型：每日挑战
func _game_type() -> String:
	return Tracker.GameType.DAILY


func _ready() -> void:
	super._ready()
	_life_bar.refresh(_lives)

	_hint_overlay.hint_detail_requested.connect(_on_chain_detail_requested)
	_hint_overlay.layer = 10
	_build_strategy_overlay()
	UniKitManager.ad_closed.connect(_on_ad_closed)

	UniKitManager.ad_shown.connect(_on_ad_shown_for_timer)

	claim_button_sound($Root/VBoxContainer/Header/SettingsBtn)

	get_viewport().size_changed.connect(_refresh_short_screen_compaction)

	$Root/VBoxContainer.sort_children.connect(_center_cat_progress_vertically)
	$Root/VBoxContainer.sort_children.connect(_relayout_cat_heart_row_for_progress)

	_endgame_save_timer = Timer.new()
	_endgame_save_timer.one_shot = true
	_endgame_save_timer.wait_time = _ENDGAME_SAVE_DEBOUNCE_SEC
	_endgame_save_timer.timeout.connect(_flush_endgame_snapshot)
	add_child(_endgame_save_timer)


func on_show(params: Dictionary = {}) -> void:
	_disconnect_endgame_persist()
	_reset_game_barrages()

	Tracker.set_active_game_type(Tracker.GameType.DAILY)

	ABTestManager.dye_at_game_start()

	ABTestManager.dye_at_game_start_dc()

	params = params.duplicate()
	_dc_restore_snapshot = _resolve_endgame_restore(params)
	_clock_base_sec = 0.0
	if not _dc_restore_snapshot.is_empty():
		params.merge(DailyEndgameSnapshot.restore_params(_dc_restore_snapshot), true)
		_clock_base_sec = float(int(_dc_restore_snapshot["elapsed_sec"]))
	super.on_show(params)

	_cat_progress_rotate_override = int(params.get("restore_cat_progress_rotate", -1))

	_board_view.visible = false

	var dt_local: Dictionary = Time.get_date_dict_from_system()
	_start_date = _local_date_string()

	var _explicit_status: String = params.get("_tracker_status", "")
	if _explicit_status == Tracker.GameStatus.RESTART:
		_stat_status = Tracker.GameStatus.RESTART
	elif _explicit_status == Tracker.GameStatus.REPLAY:
		_stat_status = Tracker.GameStatus.REPLAY
		Tracker.new_game_id(Tracker.GameType.DAILY)
	elif GameState.get_daily_started_date() == _start_date:
		_stat_status = Tracker.GameStatus.CONTINUE
	else:
		_stat_status = Tracker.GameStatus.NEW
		GameState.set_daily_started_date(_start_date)
		Tracker.new_game_id(Tracker.GameType.DAILY)
	_stat_start_ms = Time.get_ticks_msec()

	_se_last_step = Tracker.get_stat("step_used")
	if not _dc_restore_snapshot.is_empty():
		_se_last_step = mini(int(_dc_restore_snapshot["se_last_step"]), _se_last_step)

	if not CheatBus.command_issued.is_connected(_on_cheat_command):
		CheatBus.command_issued.connect(_on_cheat_command)

	const TRANSFORM_COUNT: int = 8

	var day_offset: int
	if DailyGamePage.debug_day_override >= 0:
		day_offset = DailyGamePage.debug_day_override
		print("[DailyGame] debug day_offset=%d (override)" % day_offset)
	else:
		day_offset = max(
			0,
			(
				_local_date_to_jdn(
					dt_local.get("year", 2026), dt_local.get("month", 4), dt_local.get("day", 21)
				)
				- _local_date_to_jdn(2026, 4, 21)
			)
		)

	var current_lv: int = GameState.get_current_level()
	var pool: Array = []
	var sz: int
	var rank: int
	var tier: String = "N"
	if ABTestManager.dc_level.is_override_enabled():
		sz = ABTestManager.dc_level.get_pool_size(current_lv, day_offset)
		rank = ABTestManager.dc_level.get_pool_rank(current_lv, day_offset)
		if ABTestManager.dc_level.use_gc_bank(sz, day_offset):
			pool = BankData.get_gc_levels(sz, rank)
		else:
			pool = BankData.get_levels(sz, rank)
	else:
		if current_lv <= 100:
			pool = BankData.get_levels(10, 3)
			sz = 10
			rank = 3
		elif current_lv <= 200:
			pool = BankData.get_levels(10, 4)
			sz = 10
			rank = 4
		else:
			pool = BankData.get_lk_style_levels_by_tier(12, 4, "N")
			sz = 12
			rank = 4
			tier = "N"

	if pool.is_empty():
		push_error("DailyGamePage: 无可用关卡（current_lv=%d）" % current_lv)
		return

	var pool_size: int = pool.size()
	var total_virtual: int = pool_size * TRANSFORM_COUNT
	var virtual_idx: int = day_offset % total_virtual
	var transform: int = virtual_idx / pool_size
	var entry_idx: int = virtual_idx % pool_size

	var entry: Dictionary = {}
	var sol_1d: Array = []
	var int_regions: Array = []
	var attempts: int = 0
	while attempts < total_virtual:
		entry = BankData.materialize_entry(pool[entry_idx])
		sol_1d = []
		for v in entry.get("solution", []):
			sol_1d.append(int(v))
		var raw_regions: Array = entry.get("regionMap", [])
		int_regions = []
		for row_arr: Array in raw_regions:
			var int_row: Array = []
			for v in row_arr:
				int_row.append(int(v))
			int_regions.append(int_row)
		if transform > 0:
			var transformed: Array = LevelData.apply_transform(int_regions, sol_1d, sz, transform)
			int_regions = transformed[0]
			sol_1d = transformed[1]
		if QueendokuCore.validate_solution_entry(
			{"regionMap": int_regions, "solution": sol_1d}, sz
		):
			break
		push_error(
			(
				"DailyGamePage: invalid solution day_offset=%d virtual_idx=%d transform=%d entry_idx=%d, advancing"
				% [day_offset, virtual_idx, transform, entry_idx]
			)
		)
		virtual_idx = (virtual_idx + 1) % total_virtual
		transform = virtual_idx / pool_size
		entry_idx = virtual_idx % pool_size
		attempts += 1
	if attempts >= total_virtual:
		push_error("DailyGamePage: 池内所有题目都不合法 sz=%d rank=%d, 容错沿用最后一次 entry" % [sz, rank])

	_strategy_steps[0] = int(entry.get("r1", 0))
	_strategy_steps[1] = int(entry.get("r2", 0))
	_strategy_steps[2] = int(entry.get("r3", 0))
	_strategy_steps[3] = int(entry.get("r4", 0))
	_strategy_steps[4] = int(entry.get("r5", 0))

	if _strategy_btn != null:
		_strategy_btn.visible = not OS.has_feature("rel")

	var sol_2d: Array = []
	for r: int in range(sz):
		var row: Array = []
		row.resize(sz)
		row.fill(false)
		if r < sol_1d.size():
			row[sol_1d[r]] = true
		sol_2d.append(row)

	_level_config = {
		"size": sz,
		"rank": rank,
		"tier": tier,
		"is_daily": true,
		"seed": int(entry.get("seed", entry.get("id", 0))),
		"daily_index": virtual_idx,
		"daily_transform": transform,
		"bank_source": _get_dc_bank_source(current_lv, day_offset),
		"bank_idx": entry_idx + 1,
		"bank_transform": transform,
		"prefill_count": 0,
		"prefill_positions": [],
		"rating": entry.get("rating", 0.0),
	}
	_puzzle = {"regions": int_regions, "solution": sol_2d}

	if not _dc_restore_snapshot.is_empty():
		sz = int(_dc_restore_snapshot["size"])
		_apply_snapshot_puzzle()

	var dt: Dictionary = Time.get_datetime_dict_from_system()

	var month_str: String = tr("MONTH_ABBR_%d" % clampi(int(dt["month"]), 1, 12))
	_date_label.text = "%s %d" % [month_str, dt["day"]]
	_level_display_value.text = "%02d/%02d" % [dt["month"], dt["day"]]

	_date_label.visible = false

	_lives = 3

	_mistake_count = 0

	if not _dc_restore_snapshot.is_empty():
		_lives = clampi(int(_dc_restore_snapshot["lives"]), 1, _life_cap)
		_mistake_count = int(_dc_restore_snapshot["mistake_count"])
	_is_complete = false
	_wrong_guess_pending = false
	_hint_data = {}
	_last_placed_count = -1

	_like_hand_state = {
		"in_game_sec": 0.0,
		"last_cat_sec": 0.0,
		"triggered_count": 0,
		"clock_paused": false,
		"has_seen_first_cat": false,
		"cat_place_times": {},
		"missed_cross_triggered_cats": {},
		"latest_cat_key": "",
		"manually_x_marked_cells": {},
		"hint_marked_x_cells": {},
	}

	_continue_play_sec = 0.0
	_continue_clock_started = false

	_ad_show_unix = 0.0
	_anchor_clock()
	_start_gameplay_timing(true)
	UIManager.hide_ui(UiName.DAILY_FAIL)
	UIManager.hide_ui(UiName.DAILY_WIN)
	_hint_overlay.visible = false

	_life_bar.refresh(_lives)
	_sync_tools_from_state()

	await get_tree().process_frame

	_relayout_board()

	_entry_anim_playing = true

	_lock_entry_buttons()

	_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var board_intro := $Root as BoardContainerCell_01
	if _anim_player.is_playing():
		_anim_player.stop()
		if (
			board_intro != null
			and board_intro.animation_finished.is_connected(_on_appear_animation_finished)
		):
			board_intro.animation_finished.disconnect(_on_appear_animation_finished)

	_dc_defer_inter = ABTestManager.inter_timing.should_delay_start_interstitial()
	_dc_entry_skipped = false
	if not _dc_defer_inter:
		_anim_player.play("Appear")
		SoundManager.play(SoundManager.Kind.BOARD_ENTER)

		if (
			board_intro != null
			and not board_intro.animation_finished.is_connected(_on_appear_animation_finished)
		):
			board_intro.animation_finished.connect(_on_appear_animation_finished, CONNECT_ONE_SHOT)

	refresh_companion_costume_override()
	_in_game_costume_id = CostumeCatalog.DEFAULT_COSTUME_ID
	if _companion_costume_override != 0:
		_in_game_costume_id = _companion_costume_override
	elif ABTestManager.dc_costume.has_costume():
		_in_game_costume_id = ProfileService.get_today_costume()

	_level_config["companion_costume_override"] = _companion_costume_override
	_board_view.set_cat_costume(_in_game_costume_id)

	var color_seed: int = _level_config.get("daily_transform", 0)
	var color_map: Array[int] = LevelGenerator.compute_color_map_with_seed(
		sz, _puzzle["regions"], color_seed
	)

	if board_intro != null:
		board_intro.set_auto_trigger(false)
	_board_view.setup(sz, _puzzle["regions"], color_map, [], true)
	_board_view.set_solution(_puzzle_sol_1d())

	_apply_cat_found_grid_dim()

	_restore_board_from_snapshot()

	if _endgame_persist_active():
		_connect_endgame_persist()
	if board_intro != null:
		board_intro.set_auto_trigger(true)

	if board_intro != null:
		board_intro.set_process(false)
	($Root/VBoxContainer as Container).queue_sort()
	await get_tree().process_frame

	if not _dc_defer_inter:
		if board_intro != null:
			_apply_grid_ui_entry_anim(board_intro)
			board_intro.play()

		_board_view.on_board_entry_started(_grid_intro_sync_total(board_intro))

		_board_view.visible = true

	_update_remaining(true)

	if _combo_feedback_view == null:
		_combo_feedback_view = get_node_or_null("Root/VBoxContainer/ComboFeedback")
	if _combo_feedback_view != null:
		_combo_feedback_view.reset(_score_model.score)
	_connect_combo_signal()

	_reset_idle_hint()

	_idle_hint_round_count = 0

	(
		Tracker
		. track_game_start(
			_build_qid(),
			Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)),
			_stat_status,
			Tracker.GameType.DAILY,
			_get_diffi(),
			GameState.get_current_level(),
			_level_config.get("rank", 0),
			_level_config.get("size", 0),
			0,
			"0",
			0,
			0.0,
			_level_config.get("rating", 0.0),
			_ELO_EXTRA_PLACEHOLDER,
		)
	)

	await _maybe_show_costume_tutorial()

	var ad_pos: String = Tracker.AdPos.NORMAL_START
	if _stat_status == Tracker.GameStatus.RESTART:
		ad_pos = Tracker.AdPos.NORMAL_RESTART
	elif _stat_status == Tracker.GameStatus.CONTINUE:
		ad_pos = Tracker.AdPos.NORMAL_CONTINUE
	elif _stat_status == Tracker.GameStatus.REPLAY:
		ad_pos = Tracker.AdPos.DC_RESTART

	var inter_elig: Dictionary = await _eval_start_interstitial(params, ad_pos)

	if _dc_defer_inter and not inter_elig.get("replace_with_subscription", false):
		_dc_run_deferred_interstitial(ad_pos, inter_elig)

		_show_banner_if_eligible("daily")
		return

	if _dc_defer_inter:
		_dc_defer_inter = false
		_dc_play_entry_animation_now()

	var slot_occupied: bool = false
	if inter_elig.get("replace_with_subscription", false):
		slot_occupied = _show_subscription_instead_of_interstitial(ad_pos, inter_elig)
		if not slot_occupied:
			inter_elig = elig_without_replace_flag(inter_elig)
	if not slot_occupied:
		slot_occupied = _try_show_start_interstitial(ad_pos, inter_elig)
	if slot_occupied:
		_mark_fullscreen_ad_slot_shown()

	_show_banner_if_eligible("daily")


func on_hide() -> void:
	if _endgame_save_timer != null:
		_endgame_save_timer.stop()
	if _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		_flush_endgame_snapshot(true)
		_disconnect_endgame_persist()
	super.on_hide()

	_ad_show_unix = 0.0
	if _dc_toast != null:
		_dc_toast.hide_toast()
	var board_intro := $Root as BoardContainerCell_01
	if (
		board_intro != null
		and board_intro.animation_finished.is_connected(_on_appear_animation_finished)
	):
		board_intro.animation_finished.disconnect(_on_appear_animation_finished)

	_dc_cancel_inter_wait()
	_dc_cancel_late_ad_watch()


func _get_elapsed_sec() -> int:
	return maxi(0, int(Time.get_unix_time_from_system() - _start_unix))


## 用当前或指定 Unix 时间扣除已恢复秒数，建立计时起点并刷新显示。
func _anchor_clock(anchor_unix: float = 0.0) -> void:
	var base_unix: float = anchor_unix if anchor_unix > 0.0 else Time.get_unix_time_from_system()
	_start_unix = base_unix - _clock_base_sec
	if _clock_base_sec > 0.0:
		_apply_elapsed_to_label(int(_clock_base_sec))
	else:
		_timer_label.text = "00:00"


## 计时器心跳：只刷新文字
func _on_clock_timer_timeout() -> void:
	_refresh_timer_label()


## 按当前已用秒数刷新计时文字
func _refresh_timer_label() -> void:
	_apply_elapsed_to_label(_get_elapsed_sec())


## 把秒数写成 mm:ss；超过 1 小时改成 hh:mm:ss 并把字号调小
func _apply_elapsed_to_label(sec: int) -> void:
	if sec >= 3600:
		var h: int = sec / 3600
		var m: int = (sec % 3600) / 60
		var s: int = sec % 60
		_timer_label.text = "%02d:%02d:%02d" % [h, m, s]
		_timer_label.add_theme_font_size_override("font_size", 34)
	else:
		var m: int = sec / 60
		var s: int = sec % 60
		_timer_label.text = "%02d:%02d" % [m, s]
		_timer_label.add_theme_font_size_override("font_size", 50)


func _on_application_focus_out() -> void:
	super._on_application_focus_out()

	if _endgame_save_timer != null:
		_endgame_save_timer.stop()
	_flush_endgame_snapshot()


const _ENDGAME_SAVE_DEBOUNCE_SEC: float = 0.5

var _endgame_save_timer: Timer = null


func _endgame_persist_active() -> bool:
	if not ABTestManager.dc_endgame_save.is_enabled():
		return false
	if DailyGamePage.debug_day_override >= 0:
		return false
	if _stat_status == Tracker.GameStatus.REPLAY:
		return false
	return GameState.get_daily_completed_date() != _start_date


func _connect_endgame_persist() -> void:
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		_board_view.cell_state_changed.connect(_persist_endgame_snapshot)


func _disconnect_endgame_persist() -> void:
	if _endgame_save_timer != null:
		_endgame_save_timer.stop()
	if (
		_board_view != null
		and _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot)
	):
		_board_view.cell_state_changed.disconnect(_persist_endgame_snapshot)


func _persist_endgame_snapshot(_row: int, _col: int, state: int, source: int) -> void:
	if source == BoardView.ChangeSource.RESTORE:
		return
	if state == CellState.CAT or state == CellState.ERROR:
		_endgame_save_timer.stop()
		call_deferred("_flush_endgame_snapshot")
	else:
		_endgame_save_timer.start()


func _flush_endgame_snapshot(keep_saved_session: bool = false) -> void:
	if _is_complete:
		return
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		return
	var override: Dictionary = {}
	if keep_saved_session:
		var saved_session: String = str(
			GameState.get_daily_endgame_snapshot().get("session_id", "")
		)
		if not saved_session.is_empty():
			override["session_id"] = saved_session
	var snapshot: Dictionary = _build_endgame_snapshot(override)
	if not DailyEndgameSnapshot.has_progress(snapshot):
		GameState.clear_daily_endgame_snapshot()
		return
	GameState.set_daily_endgame_snapshot(snapshot)


func _clear_endgame_snapshot() -> void:
	if _endgame_save_timer != null:
		_endgame_save_timer.stop()
	GameState.clear_daily_endgame_snapshot()


func _collect_board_cells(override_cells: Dictionary = {}) -> Dictionary:
	var board: Array = _board_view.get_board()
	var cells: Dictionary = _snapshot_cell_overrides(override_cells)
	var placed_cats: Array = []
	var marks: Array = []
	var errors: Array = []
	for row in range(board.size()):
		var board_row: Array = board[row]
		for col in range(board_row.size()):
			var state: int = int(board_row[col])
			var cell_key: Vector2i = Vector2i(row, col)
			if cells.has(cell_key):
				state = int(cells[cell_key])
			if state == CellState.CAT:
				placed_cats.append([row, col])
			elif state == CellState.MARK:
				marks.append([row, col])
			elif state == CellState.ERROR:
				errors.append([row, col])
	return {"placed_cats": placed_cats, "marks": marks, "errors": errors}


func _build_endgame_snapshot(override: Dictionary = {}) -> Dictionary:
	var override_cells: Dictionary = override.get("cells", {})
	var score_state: Dictionary = {
		"score": _score_model.score,
		"combo": int(override.get("combo", _score_model.combo)),
		"max_combo": _score_model.max_combo,
		"se_count": int(override.get("se_count", _se_count)),
		"se_last_step": _se_last_step,
	}
	var toast_state: Dictionary = {
		"operable_sec": _operable_sec,
		"cat_toast": _cat_toast_tracker.export_state(),
		"cat_progress_rotate_start": _cat_progress_rotate_start,
	}
	return DailyEndgameSnapshot.build(
		_start_date,
		str(override.get("session_id", SessionManager.session_id)),
		_level_config,
		_puzzle["regions"],
		_puzzle_sol_1d(),
		_collect_board_cells(override_cells),
		int(override.get("lives", _lives)),
		_mistake_count,
		score_state,
		_get_elapsed_sec(),
		toast_state
	)


func _local_date_string() -> String:
	var date_dict: Dictionary = Time.get_date_dict_from_system()
	return (
		"%d-%02d-%02d"
		% [date_dict.get("year", 2026), date_dict.get("month", 1), date_dict.get("day", 1)]
	)


func _resolve_endgame_restore(params: Dictionary) -> Dictionary:
	if DailyGamePage.debug_day_override >= 0:
		return {}
	var today: String = _local_date_string()
	var explicit_status: String = params.get("_tracker_status", "")
	var forced_fresh: bool = (
		explicit_status == Tracker.GameStatus.RESTART
		or explicit_status == Tracker.GameStatus.REPLAY
	)
	var snapshot: Dictionary = GameState.get_daily_endgame_snapshot()
	var restorable: bool = DailyEndgameSnapshot.should_restore(
		snapshot,
		ABTestManager.dc_endgame_save.is_enabled(),
		ABTestManager.dc_endgame_save.requires_same_session(),
		forced_fresh,
		GameState.get_daily_started_date() == today,
		today,
		SessionManager.session_id,
		_life_cap
	)
	if restorable:
		return snapshot.duplicate(true)
	GameState.clear_daily_endgame_snapshot()
	return {}


func _apply_snapshot_puzzle() -> void:
	var saved_config: Dictionary = _dc_restore_snapshot["level_config"]
	_level_config = saved_config.duplicate(true)
	for int_key: String in [
		"size", "rank", "daily_index", "daily_transform", "bank_idx", "bank_transform"
	]:
		if _level_config.has(int_key):
			_level_config[int_key] = int(_level_config[int_key])
	_level_config["is_daily"] = true
	_level_config["prefill_count"] = 0
	_level_config["prefill_positions"] = []
	var saved_regions: Array = _dc_restore_snapshot["regions"]
	var int_regions: Array = []
	for region_row: Array in saved_regions:
		var int_row: Array = []
		for region_id: Variant in region_row:
			int_row.append(int(region_id))
		int_regions.append(int_row)
	var saved_solution: Array = _dc_restore_snapshot["solution"]
	var solution_1d: Array = []
	for column: Variant in saved_solution:
		solution_1d.append(int(column))
	_puzzle = {
		"regions": int_regions,
		"solution":
		DailyEndgameSnapshot.solution_grid(solution_1d, int(_dc_restore_snapshot["size"])),
	}


func _restore_board_from_snapshot() -> void:
	if _dc_restore_snapshot.is_empty():
		return
	var placed_cats: Array = _dc_restore_snapshot["placed_cats"]
	for pos: Array in placed_cats:
		_board_view.set_cell_state(
			int(pos[0]), int(pos[1]), CellState.CAT, false, true, BoardView.ChangeSource.RESTORE
		)
	var marks: Array = _dc_restore_snapshot["marks"]
	for pos: Array in marks:
		_board_view.set_cell_state(
			int(pos[0]), int(pos[1]), CellState.MARK, false, true, BoardView.ChangeSource.RESTORE
		)
	var errors: Array = _dc_restore_snapshot["errors"]
	for pos: Array in errors:
		var row: int = int(pos[0])
		var col: int = int(pos[1])
		_board_view.set_cell_state(
			row, col, CellState.MARK, false, true, BoardView.ChangeSource.RESTORE
		)
		_board_view.mark_cell_error(row, col, BoardView.ChangeSource.RESTORE)

	_seed_full_mark_fired_units_from_board("每日残局复原")


func _save_endgame_for_pending_wrong_guess(row: int, col: int) -> void:
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		return
	var override: Dictionary = {
		"cells": {Vector2i(row, col): CellState.ERROR},
		"lives": _lives,
		"combo": 0,
		"se_count": 0,
	}

	_endgame_save_timer.stop()
	GameState.set_daily_endgame_snapshot(_build_endgame_snapshot(override))


func _on_application_focus_in() -> void:
	super._on_application_focus_in()
	_compensate_ad_time()
	_refresh_timer_label()

	if not _dc_inter_wait.is_empty():
		_dc_inter_wait["done"] = true
	elif _dc_late_lock_active:
		_dc_release_late_lock("focus_in")


func _on_ad_shown_for_timer(placement_id: String) -> void:
	if not is_showing():
		return
	if placement_id == AdPlacement.REWARD:
		_ad_show_unix = Time.get_unix_time_from_system()


func _mark_fullscreen_ad_slot_shown() -> void:
	_ad_show_unix = Time.get_unix_time_from_system()
	_anchor_clock(_ad_show_unix)


func _on_interstitial_subscription_closed(
	ad_position: String, elig: Dictionary, should_play_interstitial: bool
) -> bool:
	var shown: bool = super._on_interstitial_subscription_closed(
		ad_position, elig, should_play_interstitial
	)
	if not shown:
		_compensate_ad_time()
		_refresh_timer_label()
	return shown


func _compensate_ad_time() -> void:
	if _ad_show_unix <= 0.0:
		return
	var now_unix: float = Time.get_unix_time_from_system()
	var ad_duration: float = now_unix - _ad_show_unix
	print("[DailyGame] ad compensated %.1fs" % ad_duration)
	_start_unix = minf(_start_unix + ad_duration, now_unix)
	_ad_show_unix = 0.0


func _on_ad_closed(_placement_id: String) -> void:
	if not is_showing():
		return
	_compensate_ad_time()
	_refresh_timer_label()


func _on_gear_btn_pressed() -> void:
	if _is_complete:
		return
	_reset_game_barrages()
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	_clock_timer.stop()

	_exit_draft_mode_and_clear()
	_clear_draft_rollback_state()
	UIManager.hide_all_except([UiName.HOME])
	UIManager.show_ui(UiName.HOME)


func _on_appear_animation_finished() -> void:
	super._on_appear_animation_finished()

	if not _dc_entry_skipped:
		VibrateManager.play_at(VibrateManager.Pos.BOARD_INTRO)

	var lock_seq: int = _entry_btn_lock_seq

	if _try_show_dc_start_toast():
		_unlock_entry_buttons_after_toast(lock_seq)
	else:
		_unlock_entry_buttons()


func _try_show_dc_start_toast() -> bool:
	if not ABTestManager.dc_start_toast.is_enabled():
		return false
	if not _dc_restore_snapshot.is_empty():
		return false

	if GameState.get_current_level() < 11:
		return false
	var is_first: bool = _stat_status == Tracker.GameStatus.NEW
	var pick: Dictionary = DcStartToastTextPool.resolve(is_first)
	(
		_dc_toast
		. show_toast(
			{
				"text_key": pick.text_key,
				"pct_str": pick.pct_str,
			}
		)
	)
	return true


func _wait_dc_toast_hidden_if_any() -> void:
	if _dc_toast == null or not _dc_toast.visible:
		return
	while _dc_toast.visible:
		await _dc_toast.visibility_changed


var _dc_defer_inter: bool = false

var _dc_entry_skipped: bool = false

const _DC_INTER_DELAY_AFTER_BOARD_SEC: float = 0.4

const _DC_SHOW_CONFIRM_SEC: float = 2.0

const _DC_LATE_LOCK_SEC: float = 3.0

var _dc_inter_wait: Dictionary = {}

var _dc_ad_cbs: Array = []
var _dc_show_confirm_timer: Timer = null

var _dc_late_lock_active: bool = false
var _dc_late_cbs: Array = []
var _dc_late_lock_timer: Timer = null


func _dc_run_deferred_interstitial(ad_pos: String, elig: Dictionary) -> void:
	if not elig.get("eligible", false):
		_dc_play_entry_animation_now()
		return
	_dc_place_board_without_intro()

	_anim_player.play("Appear")

	await get_tree().create_timer(_DC_INTER_DELAY_AFTER_BOARD_SEC).timeout
	if not is_showing():
		return

	if not _try_show_start_interstitial(ad_pos, elig):
		_dc_finish_entry_after_interstitial()
		return
	_mark_fullscreen_ad_slot_shown()
	await _dc_await_interstitial_closed()
	if not is_showing():
		return
	_dc_finish_entry_after_interstitial()


func _dc_place_board_without_intro() -> void:
	_dc_entry_skipped = true
	_board_view.visible = true
	_board_view.on_board_entry_started(0.0)
	var board_intro := $Root as BoardContainerCell_01
	if board_intro != null:
		board_intro.set_auto_trigger(false)
		if board_intro.animation_finished.is_connected(_on_appear_animation_finished):
			board_intro.animation_finished.disconnect(_on_appear_animation_finished)
		_dc_reveal_board_container(board_intro)


func _dc_reveal_board_container(board_intro: BoardContainerCell_01) -> void:
	if not (board_intro.board_view is CanvasItem):
		return
	var board_container: CanvasItem = board_intro.board_view as CanvasItem
	var col: Color = board_container.modulate
	col.a = 1.0
	board_container.modulate = col


func _dc_play_entry_animation_now() -> void:
	var board_intro := $Root as BoardContainerCell_01
	if board_intro != null:
		_apply_grid_ui_entry_anim(board_intro)
		board_intro.play()
		if not board_intro.animation_finished.is_connected(_on_appear_animation_finished):
			board_intro.animation_finished.connect(_on_appear_animation_finished, CONNECT_ONE_SHOT)
	_board_view.on_board_entry_started(_grid_intro_sync_total(board_intro))
	_board_view.visible = true
	_anim_player.play("Appear")
	SoundManager.play(SoundManager.Kind.BOARD_ENTER)


func _dc_await_interstitial_closed() -> void:
	var state := {"done": false}
	_dc_inter_wait = state
	var on_closed: Callable = func(pid: String) -> void:
		if pid == AdPlacement.INTERSTITIAL:
			state.done = true
	var on_error: Callable = func(pid: String, _msg: String) -> void:
		if pid == AdPlacement.INTERSTITIAL:
			state.done = true
	UniKitManager.ad_closed.connect(on_closed)
	UniKitManager.ad_error_occurred.connect(on_error)
	_dc_ad_cbs = [on_closed, on_error]
	_dc_arm_show_confirm(state)

	while not state.done:
		await get_tree().process_frame
	_dc_cancel_inter_wait()


func _dc_arm_show_confirm(state: Dictionary) -> void:
	if not UniKitManager.is_ad_impression_signal_available():
		return
	var on_impression: Callable = func(data: Dictionary) -> void:
		if String(data.get("placement_id", "")) != AdPlacement.INTERSTITIAL:
			return

		_dc_disarm_show_confirm()
	UniKitManager.ad_impression_received.connect(on_impression)
	_dc_ad_cbs.append(on_impression)
	_dc_show_confirm_timer = create_countdown(
		_DC_SHOW_CONFIRM_SEC,
		func() -> void:
			_dc_show_confirm_timer = null
			if state.get("done", false):
				return
			print(
				"[DC-Inter] %.1fs 内未收到 ad impression → 判定插屏未上屏,主动恢复进关(防卡死)" % _DC_SHOW_CONFIRM_SEC
			)
			state.done = true

			_dc_arm_late_ad_watch()
	)


func _dc_disarm_show_confirm() -> void:
	if _dc_show_confirm_timer != null:
		remove_timer(_dc_show_confirm_timer)
		_dc_show_confirm_timer = null


func _dc_cancel_inter_wait() -> void:
	if not _dc_inter_wait.is_empty():
		_dc_inter_wait["done"] = true
		_dc_inter_wait = {}
	for cb in _dc_ad_cbs:
		if UniKitManager.ad_closed.is_connected(cb):
			UniKitManager.ad_closed.disconnect(cb)
		if UniKitManager.ad_error_occurred.is_connected(cb):
			UniKitManager.ad_error_occurred.disconnect(cb)
		if UniKitManager.ad_impression_received.is_connected(cb):
			UniKitManager.ad_impression_received.disconnect(cb)
	_dc_ad_cbs = []
	_dc_disarm_show_confirm()


func _dc_arm_late_ad_watch() -> void:
	if not UniKitManager.is_ad_impression_signal_available():
		return
	_dc_cancel_late_ad_watch()
	var on_late: Callable = func(data: Dictionary) -> void:
		if String(data.get("placement_id", "")) != AdPlacement.INTERSTITIAL:
			return
		_dc_on_late_ad_impression()
	UniKitManager.ad_impression_received.connect(on_late)
	_dc_late_cbs = [on_late]


func _dc_on_late_ad_impression() -> void:
	if _dc_late_lock_active:
		return
	_dc_late_lock_active = true
	print("[DC-Inter] 迟到的 ad impression 到达(超时判定后广告仍上屏)→ 重新锁交互")
	_dc_set_late_locked(true)
	var on_closed: Callable = func(pid: String) -> void:
		if pid == AdPlacement.INTERSTITIAL:
			_dc_release_late_lock("ad_closed")
	UniKitManager.ad_closed.connect(on_closed)
	_dc_late_cbs.append(on_closed)
	_dc_late_lock_timer = create_countdown(
		_DC_LATE_LOCK_SEC,
		func() -> void:
			_dc_late_lock_timer = null
			_dc_release_late_lock("timeout")
	)


func _dc_release_late_lock(source: String) -> void:
	if not _dc_late_lock_active:
		return
	_dc_late_lock_active = false
	print("[DC-Inter] 迟到锁解除(source=%s)" % source)
	_dc_set_late_locked(false)
	_dc_cancel_late_ad_watch()


func _dc_cancel_late_ad_watch() -> void:
	if _dc_late_lock_active:
		_dc_late_lock_active = false
		_dc_set_late_locked(false)
	for cb in _dc_late_cbs:
		if UniKitManager.ad_impression_received.is_connected(cb):
			UniKitManager.ad_impression_received.disconnect(cb)
		if UniKitManager.ad_closed.is_connected(cb):
			UniKitManager.ad_closed.disconnect(cb)
	_dc_late_cbs = []
	if _dc_late_lock_timer != null:
		remove_timer(_dc_late_lock_timer)
		_dc_late_lock_timer = null


func _dc_set_late_locked(locked: bool) -> void:
	if _entry_anim_playing:
		return
	if _board_view != null:
		_board_view.set_touch_enabled(not locked)
	if locked:
		_lock_entry_buttons()
	else:
		_unlock_entry_buttons()


func _dc_finish_entry_after_interstitial() -> void:
	_on_appear_animation_finished()


func _unlock_entry_buttons_after_toast(seq: int) -> void:
	await _wait_dc_toast_hidden_if_any()
	if seq != _entry_btn_lock_seq:
		return
	_unlock_entry_buttons()


func _lock_entry_buttons() -> void:
	_entry_btn_lock_seq += 1
	_back_setting_header.lock_buttons()


func _unlock_entry_buttons() -> void:
	_back_setting_header.unlock_buttons()


func _on_restart_requested() -> void:
	_reset_game_barrages()
	_score_model.reset_all()
	_se_count = 0

	_destroy_banner()

	LevelOps.confirm_level_failed_daily(_build_game_end_params(Tracker.GameResult.QUIT))
	LevelOps.on_restart_click()
	on_show({"_tracker_status": Tracker.GameStatus.RESTART})


func _on_rule_violated(rule: int, additive: bool = false) -> void:
	_play_rule_highlight(rule, additive)


func _reward_pos_for(kind: String) -> String:
	if kind == ToolKind.LOCATE:
		return Tracker.AdPos.PROPS_DAILY_LOCATE
	if kind == ToolKind.MOUSE:
		return Tracker.AdPos.PROPS_DAILY_MOUSE
	if kind == ToolKind.DRAFT:
		return Tracker.AdPos.PROPS_DAILY_DRAFT
	return Tracker.AdPos.PROPS_DAILY_HINT


func _on_game_fail() -> void:
	if not _is_complete:
		GameState.on_game_finished()
	_is_complete = true

	_clear_endgame_snapshot()

	_reset_game_barrage_session_state()

	_exit_draft_mode_and_clear()
	_clock_timer.stop()

	pause_like_hand_clock()
	_stop_idle_tool_hint()
	_destroy_banner()
	Tracker.inc_stat("gamedie_count")

	ABTestManager.dye_at_game_fail_end()

	Tracker.track_game_end(_build_game_end_params(Tracker.GameResult.FAIL))
	VibrateManager.play_at(VibrateManager.Pos.DAILY_FAIL)
	var sz: int = _level_config.get("size", 12)
	var placed: int = 0
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				placed += 1
	var remaining_cats: int = sz - placed
	var fail := (
		UIManager
		. show_ui(
			UiName.DAILY_FAIL,
			{
				"level_config": _level_config,
				"remaining_cats": remaining_cats,
				"cat_progress": build_cat_progress_snapshot(),
			}
		)
	)
	if fail != null and not fail.revive_requested.is_connected(_on_revive_requested):
		fail.revive_requested.connect(_on_revive_requested)
	if fail != null and not fail.revive_ad_started.is_connected(_on_revive_ad_started):
		fail.revive_ad_started.connect(_on_revive_ad_started)


## 广告开始播：先把棋盘上的猫全部退回待机，广告结束后再复原
func _on_revive_ad_started() -> void:
	_board_view.revive_all_cat_to_idle()


func _on_revive_requested() -> void:
	UIManager.hide_ui(UiName.DAILY_FAIL)

	_board_view.set_touch_enabled(true)
	_is_complete = false

	_block_near_death_for_current_level()
	GameState.inc_game_total_stat(Tracker.GameType.DAILY, "revive_count")
	GameState.inc_game_total_stat(Tracker.GameType.DAILY, "rv_count")

	_lives = _life_cap
	_life_bar.refresh(_lives)

	_life_bar.revive_all()
	_clock_timer.start()

	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]

	resume_like_hand_clock()

	_board_view.revive_all_cat_to_idle()

	_rollback_draft_lethal_cells()

	_show_banner_if_eligible("daily")
	_restart_game_barrages_after_continue()

	call_deferred("_flush_endgame_snapshot")


func _is_no_mistake_level() -> bool:
	return _mistake_count == 0


func _on_game_win() -> void:
	PowerSaver.wake(_WIN_REPLAY_FULL_FPS_SEC)
	_reset_game_barrage_session_state()

	if _is_complete:
		push_error(
			(
				"[COMPLETE-REENTRY] daily _on_game_win 重入 level=%d"
				% int(_level_config.get("level", -1))
			)
		)
	if not _is_complete:
		GameState.on_game_finished()

		_accumulate_today_win_stats()
	_is_complete = true

	_clear_endgame_snapshot()

	_exit_draft_mode_and_clear()
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_destroy_banner()

	var elapsed_sec: int = _get_elapsed_sec()
	_apply_elapsed_to_label(elapsed_sec)

	var won_with_full_lives: bool = _lives >= 3
	var rank: int = _level_config.get("rank", 4)
	_level_config["elapsed_sec"] = elapsed_sec

	var use_anchor_curve: bool = ABTestManager.dc_beat_percent.is_anchor_curve()
	var sz: int = _level_config.get("size", 12)
	var raw_percent: float = DailyStats.beat_percent(elapsed_sec, rank, sz, use_anchor_curve)

	pause_like_hand_clock()
	_level_config["beat_percent"] = raw_percent

	Tracker.track_game_end(_build_game_end_params(Tracker.GameResult.WIN))
	var mouse_daily_persisted_early: bool = false

	if _mouse_completion_pending:
		GameState.mark_daily_completed(_start_date, elapsed_sec, _level_config["beat_percent"])
		mouse_daily_persisted_early = true
	if not await _await_mouse_completion_anim_if_needed():
		return

	SoundManager.stop(SoundManager.Kind.MARK_CAT)

	_board_view.replay_all_cat_appear(ABTestManager.found_cat_animation.win_replay_anim_name())
	VibrateManager.play_at(VibrateManager.Pos.DAILY_WIN)
	_cleanup_hint()
	await get_tree().process_frame

	if not mouse_daily_persisted_early:
		GameState.mark_daily_completed(_start_date, elapsed_sec, _level_config["beat_percent"])

	var costume_unlocked: bool = false
	if ABTestManager.dc_costume.has_costume() and won_with_full_lives:
		costume_unlocked = ProfileService.unlock_today_costume()

	_level_config["costume_unlock_pending"] = costume_unlocked
	_level_config["costume_id"] = _in_game_costume_id

	await _play_auto_cross_bonus_sequence()

	StreakManager.settle_win(&"challenge")

	var toast_was_shown: bool = await _play_win_toast_and_wait()
	_level_config["toast_was_shown"] = toast_was_shown

	var streak_consumed_appear_delay: bool = false
	if not ABTestManager.daily_streak.is_settle_reorder():
		streak_consumed_appear_delay = await _try_run_streak_flow_after_win(
			&"challenge", toast_was_shown
		)

	var costume_page_shown: bool = await _run_costume_unlock_flow()

	_level_config["skip_appear_delay"] = streak_consumed_appear_delay or costume_page_shown

	_level_config["final_score"] = _score_model.score
	_level_config["max_combo"] = _score_model.max_combo
	var win_page := UIManager.show_ui(
		_win_ui_name(), {"level_config": _level_config, "board_view": _board_view}
	)

	if win_page != null and not win_page.replay_requested.is_connected(_on_win_replay_requested):
		win_page.replay_requested.connect(_on_win_replay_requested)


## 本页对应的通关页 UI 名（每日挑战固定）
func _win_ui_name() -> StringName:
	return UiName.DAILY_WIN


const _TUTORIAL_CLOSE_TIMEOUT_SEC: float = 60.0


func in_game_costume_id() -> int:
	return _in_game_costume_id


func _run_costume_unlock_flow() -> bool:
	if not bool(_level_config.get("costume_unlock_pending", false)):
		return false
	_level_config["costume_unlock_pending"] = false
	var page := (
		UIManager
		. show_ui(
			UiName.DC_COSTUME_UNLOCK,
			{
				"beat_percent": float(_level_config.get("beat_percent", 50.0)),
				"costume_id":
				int(_level_config.get("costume_id", CostumeCatalog.DEFAULT_COSTUME_ID)),
			}
		)
	)
	if page == null:
		push_error("DailyGamePage: dc_costume unlock page 打不开,外观已发但玩家看不到解锁画面")
		return false
	await UIManager.await_hidden(UiName.DC_COSTUME_UNLOCK)
	return true


func _maybe_show_costume_tutorial() -> void:
	if not ABTestManager.dc_costume.has_costume():
		return
	if ProfileService.is_costume_tutorial_shown():
		return

	await get_tree().process_frame
	var page := (
		UIManager
		. show_ui(
			UiName.DC_COSTUME_TUTORIAL,
			{
				"costume_id": _in_game_costume_id,
				"spotlight": _life_capsule_for_tutorial(),
			}
		)
	)
	if page == null:
		push_error("DailyGamePage: dc_costume tutorial page 打不开,跳过教学")
		return

	_hold_clock_for_tutorial()

	var state: Dictionary = {"closed": false}
	var on_closed: Callable = func() -> void: state["closed"] = true
	var tutorial_page := page as DcCostumeTutorialPage
	if tutorial_page == null:
		push_error("DailyGamePage: DC_COSTUME_TUTORIAL 指向的不是 DcCostumeTutorialPage,跳过教学")
		_start_clock_after_tutorial()
		return
	tutorial_page.tutorial_closed.connect(on_closed, CONNECT_ONE_SHOT)

	var clock: Tween = create_tween()
	clock.tween_interval(_TUTORIAL_CLOSE_TIMEOUT_SEC + 1.0)
	while not state["closed"] and clock.get_total_elapsed_time() < _TUTORIAL_CLOSE_TIMEOUT_SEC:
		await get_tree().process_frame
	clock.kill()
	if tutorial_page.tutorial_closed.is_connected(on_closed):
		tutorial_page.tutorial_closed.disconnect(on_closed)

	_start_clock_after_tutorial()
	if not state["closed"]:
		push_error("DailyGamePage: dc_costume 教学页 tutorial_closed 超时未到,放行进关编排")
		return
	ProfileService.mark_costume_tutorial_shown()


func _life_capsule_for_tutorial() -> Control:
	return get_node_or_null("Root/VBoxContainer/CatHeartRow/HeartBg") as Control


func _hold_clock_for_tutorial() -> void:
	_clock_timer.stop()
	_anchor_clock()


func _start_clock_after_tutorial() -> void:
	_anchor_clock()
	_refresh_timer_label()
	_clock_timer.start()


func _on_win_replay_requested() -> void:
	UIManager.hide_ui(UiName.DAILY_WIN)
	UIManager.show_ui(UiName.DAILY_GAME, DcReplayFlow.enter_params())


func _try_run_streak_flow_after_win(_source: StringName, skip_cat_appear: bool = false) -> bool:
	var has_revive: bool = StreakManager.has_pending_revive_decision()
	if not has_revive and not StreakManager.has_pending_show():
		return false

	if not skip_cat_appear:
		await get_tree().create_timer(DailyWinPage.APPEAR_DELAY).timeout
	if has_revive:
		await StreakReviveFlow.run(self)
	if not StreakManager.has_pending_show():
		return true
	await StreakPage.open_after_win()
	return true


func _on_cheat_command(cmd_name: String, args: Array[String]) -> void:
	match cmd_name:
		"win":
			_cmd_win(args)
		"lives":
			_cmd_lives(args)
		"time":
			_cmd_time(args)

		"draft":
			_cmd_draft()
		"draft_win":
			_cmd_draft_win()


func _cmd_time(args: Array[String]) -> void:
	var sec: float = maxf(0.0, float(args[0]) if not args.is_empty() else 90.0)
	_start_unix = Time.get_unix_time_from_system() - sec
	_like_hand_state["in_game_sec"] = sec
	_refresh_timer_label()
	Toast.popup("当前时间已设为 %.1fs" % sec, self)


## 本局题目来自哪个题库（埋点用）：实验组看 use_gc_bank，控制组按等级分 regular / lkstyle
func _get_dc_bank_source(current_lv: int, day_offset: int) -> String:
	if ABTestManager.dc_level.is_override_enabled():
		var sz: int = ABTestManager.dc_level.get_pool_size(current_lv, day_offset)
		if ABTestManager.dc_level.use_gc_bank(sz, day_offset):
			return "gc"
		return "regular"
	return "lkstyle" if current_lv > 200 else "regular"


## 公历日期 → 儒略日序号，用来算两个日期差几天
static func _local_date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045


## 埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.DAILY_GAME


func _current_round_time_sec() -> int:
	var time_sec: int = _level_config.get("elapsed_sec", 0)
	if time_sec <= 0:
		time_sec = _get_elapsed_sec()
	if time_sec == 0:
		time_sec = super._current_round_time_sec()
	return time_sec


func _build_game_end_params(result: String) -> Dictionary:
	var time_sec: int = _current_round_time_sec()

	GameState.inc_game_total_stat(Tracker.GameType.DAILY, "time_total", time_sec)
	var sz: int = _level_config.get("size", 0)
	var cat_n: int = _board_view.count_cat_cells()
	var params: Dictionary = {
		"qid": _build_qid(),
		"qrotate": Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)),
		"result": result,
		"game_type": Tracker.GameType.DAILY,
		"diffi": _get_diffi(),
		"level": GameState.get_current_level(),
		"strategy_layer": _level_config.get("rank", 0),
		"scale": sz,
		"pre_cat_positions": "[]",
		"rating": _level_config.get("rating", 0.0),
		"hint": GameState.get_tool_count("hint"),
		"locate": GameState.get_tool_count("locate"),
		"hint_used": Tracker.get_stat("hint_used"),
		"locate_used": Tracker.get_stat("locate_used"),
		"hint_used_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "hint_used_total"),
		"locate_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "locate_used_total"),
		"mouse": GameState.get_tool_count(ToolKind.MOUSE),
		"mouse_used": Tracker.get_stat("mouse_used"),
		"mouse_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "mouse_used_total"),
		"hint_apply_used": Tracker.get_stat("hint_apply_used"),
		"hint_stop_used": Tracker.get_stat("hint_stop_used"),
		"hint_detail_used": Tracker.get_stat("hint_detail_used"),
		"clear_used": Tracker.get_stat("clear_used"),
		"clear_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "clear_used_total"),
		"draft_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_used_total"),
		"draft_time_total":
		int(GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_time_total_ms") / 1000.0),
		"draft_error_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_error_total"),
		"draft_correct_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_correct_total"),
		"draft_apply_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_apply_used_total"),
		"draft_stop_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "draft_stop_used_total"),
		"coord_count": Tracker.get_stat("coord_count"),
		"step_used": Tracker.get_stat("step_used"),
		"step_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "step_total"),
		"cat_click_num": Tracker.get_stat("cat_click_num"),
		"gamedie_count": Tracker.get_stat("gamedie_count"),
		"restart_count": Tracker.get_stat("restart_count"),
		"time": time_sec,
		"time_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "time_total"),
		"percent": _level_config.get("beat_percent", 0.0),
		"cross_count": _board_view.count_mark_cells(),
		"correct_cross_count": _count_correct_crosses(),
		"false_cross_count": _count_false_crosses(),
		"hint_cross_count": Tracker.get_stat("hint_cross_count"),
		"invalid_sign": _board_view.count_error_cells(),
		"invalid_sign_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "invalid_sign_total"),
		"fail_sign": sz - cat_n,
		"erase_count": Tracker.get_stat("erase_count"),
		"revive_count": GameState.get_game_total_stat(Tracker.GameType.DAILY, "revive_count"),
		"rv_count": GameState.get_game_total_stat(Tracker.GameType.DAILY, "rv_count"),
		"hp_count": _lives,
		"se_score": _score_model.score,
		"is_tap_cat_at_last": _last_cat_at_last_flag(),
	}
	print(
		(
			"[DailyGamePage] game_end cross: correct=%d false=%d hint=%d | cross_count=%d invalid_sign=%d"
			% [
				params["correct_cross_count"],
				params["false_cross_count"],
				params["hint_cross_count"],
				params["cross_count"],
				params["invalid_sign"]
			]
		)
	)
	print(
		(
			"[DailyGamePage] game_end step: step_used=%d step_total=%d | locate_used=%d hint_apply_used=%d"
			% [
				params["step_used"],
				params["step_total"],
				params["locate_used"],
				params["hint_apply_used"]
			]
		)
	)
	print(
		(
			"[DailyGamePage] game_end last_cat: is_tap_cat_at_last=%d | streak=%d/%d cross@1st=%d/阈%d"
			% [
				params["is_tap_cat_at_last"],
				_cat_streak,
				sz,
				_cross_at_first_cat,
				LastCatJudge.cross_threshold(sz)
			]
		)
	)
	params.merge(_ELO_END_EXTRA_PLACEHOLDER)
	params.merge(_companion_game_end_fields(false))
	return params


func _cat_progress_default_path() -> String:
	return "Root/VBoxContainer/CatProgressRow/CatProgressBar"


func _cat_progress_adjacent_path() -> String:
	return "Root/VBoxContainer/BoardContainer/CatProgressBar"


func _cat_progress_adjacent_holder_path() -> String:
	return "Root/VBoxContainer/AdjacentBoardBarHolder"


func _function_area_min_h_for_adjacent_bar() -> float:
	return -1.0


func _set_cat_progress_row_visible(on: bool) -> void:
	var holder: Control = get_node_or_null("Root/VBoxContainer/CatProgressAdaptHolder") as Control
	var row: Control = get_node_or_null("Root/VBoxContainer/CatProgressRow") as Control
	if holder != null:
		holder.visible = on
	if row != null:
		row.visible = on

	_refresh_short_screen_compaction()


func _cat_progress_default_metrics(total: int) -> Dictionary:
	var metrics: Dictionary = CatProgressBar.solve_metrics(total, 0.0)
	metrics["align"] = "center"
	return metrics


func _cat_progress_band_top() -> float:
	var candidates: Array = [
		"Root/VBoxContainer/CatHeartRow/HeartBg",
		"Root/VBoxContainer/CatHeartRow/TimeContainer",
	]
	var bottom: float = 0.0
	var found: bool = false
	for path: String in candidates:
		var node: Control = get_node_or_null(String(path)) as Control
		if node == null or not node.visible:
			continue
		bottom = (
			maxf(bottom, node.get_global_rect().end.y) if found else node.get_global_rect().end.y
		)
		found = true
	if found:
		return bottom
	var row: Control = get_node_or_null("Root/VBoxContainer/CatHeartRow") as Control
	return row.get_global_rect().end.y if row != null else 0.0


func _center_cat_progress_vertically() -> void:
	if _cat_progress == null or not _cat_progress.visible:
		return

	if _cat_progress_uses_adjacent_bar():
		return
	var row: Control = _cat_progress.get_parent() as Control
	var rules_bg: Control = (
		get_node_or_null("Root/VBoxContainer/RuleBar/Control/RulesBg") as Control
	)
	if row == null or rules_bg == null:
		return
	var band_top: float = _cat_progress_band_top()
	var band_bottom: float = rules_bg.get_global_rect().position.y
	var bar_height: float = _cat_progress.size.y
	var gap: float = (band_bottom - band_top - bar_height) * 0.5

	if gap < 0.0:
		return
	var wanted_top: float = band_top + gap - row.get_global_rect().position.y

	if is_equal_approx(_cat_progress.offset_top, wanted_top):
		return
	_cat_progress.offset_top = wanted_top
	_cat_progress.offset_bottom = wanted_top + bar_height


func _layout_cat_progress_bar(metrics: Dictionary) -> void:
	super._layout_cat_progress_bar(metrics)
	_relayout_cat_heart_row_for_progress()
	_center_cat_progress_vertically()


func _relayout_cat_heart_row_for_progress() -> void:
	if _cat_progress == null or not _cat_progress.visible:
		return
	_apply_heart_bg_position_for_progress(true)


func _apply_heart_bg_position_for_progress(cat_bar: bool = false) -> void:
	var row: Control = get_node_or_null("Root/VBoxContainer/CatHeartRow") as Control

	var row_width: float = row.size.x if row != null and row.size.x > 0.0 else 1080.0
	var pairs: Array = [
		["Root/VBoxContainer/CatHeartRow/HeartBg", -285.0, -25.0],
		["Root/VBoxContainer/CatHeartRow/TimeContainer", 25.0, 285.0],
	]
	for p: Array in pairs:
		var node: Control = get_node_or_null(String(p[0])) as Control
		if node == null:
			continue
		if not node.has_meta("_cp_base_l"):
			node.set_meta("_cp_base_l", node.offset_left)
			node.set_meta("_cp_base_r", node.offset_right)
		if cat_bar:
			var anchor_shift: float = (0.5 - node.anchor_left) * row_width
			node.offset_left = float(p[1]) + anchor_shift
			node.offset_right = float(p[2]) + anchor_shift
		else:
			node.offset_left = float(node.get_meta("_cp_base_l"))
			node.offset_right = float(node.get_meta("_cp_base_r"))


const _SHORT_SCREEN_MIN_H: Dictionary = {
	"RuleBarAdaptHolder": 6.0,
	"BoardAdaptHolder": 6.0,
	"FunctionAdaptHolder": 0.0,
	"FunctionArea": 4.0,
	"AdAdaptHolder": 6.0,
}

var _short_screen_applied: bool = false


func _refresh_short_screen_compaction() -> void:
	var vbox: Control = get_node_or_null("Root/VBoxContainer") as Control
	if vbox == null:
		return

	_set_short_screen_compaction(false)
	if not _cat_progress_adds_vbox_height():
		return
	var parent: Control = vbox.get_parent() as Control
	if parent == null:
		return

	var avail: float = (
		parent.size.y * (vbox.anchor_bottom - vbox.anchor_top)
		+ vbox.offset_bottom
		- vbox.offset_top
	)
	if vbox.get_combined_minimum_size().y <= avail:
		return
	_set_short_screen_compaction(true)


func _cat_progress_adds_vbox_height() -> bool:
	var row: Control = get_node_or_null("Root/VBoxContainer/CatProgressRow") as Control
	if row != null and row.visible:
		return true
	var holder_path: String = _cat_progress_adjacent_holder_path()
	if holder_path.is_empty():
		return false
	var holder: Control = get_node_or_null(NodePath(holder_path)) as Control
	return holder != null and holder.visible


func _set_short_screen_compaction(on: bool) -> void:
	if on == _short_screen_applied:
		return
	var node_names: Array = _SHORT_SCREEN_MIN_H.keys()
	for node_name: String in node_names:
		var node: Control = get_node_or_null("Root/VBoxContainer/" + node_name) as Control
		if node == null:
			continue
		if not node.has_meta("_ss_base_min_h"):
			node.set_meta("_ss_base_min_h", node.custom_minimum_size.y)
		node.custom_minimum_size.y = (
			float(_SHORT_SCREEN_MIN_H[node_name]) if on else float(node.get_meta("_ss_base_min_h"))
		)
	_short_screen_applied = on
