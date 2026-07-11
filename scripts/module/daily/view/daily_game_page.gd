class_name DailyGamePage
extends BaseGamePage

const SettingScene: PackedScene = preload("res://scripts/module/setting/ui/setting_page.tscn")

@onready var _date_label: Label = $Root/VBoxContainer/Header/DateLabel
@onready var _level_display_value: Label = $Root/VBoxContainer/Header/LevelDisplay/Value
@onready
var _timer_label: Label = $Root/VBoxContainer/CatHeartRow/TimeContainer/HBoxContainer/TimerCtrl/TimerLabel

var _start_unix: float = 0.0
var _start_date: String = ""
var _ad_show_unix: float = 0.0

var _pending_show_auto_mark_popup: bool = false

@onready var _entry_locked_buttons: Array[Button] = [
	$Root/VBoxContainer/Header/SettingsBtn,
	$Root/VBoxContainer/Header/GearBtn,
]

var _entry_btn_lock_seq: int = 0

static var debug_day_override: int = -1


func _game_type() -> String:
	return Tracker.GameType.DAILY


func _ready() -> void:
	_refresh_hearts()
	_board_view.cell_drag_start.connect(_on_board_cell_drag_start)
	_board_view.cell_drag_over.connect(_on_board_cell_drag_over)
	_board_view.cell_drag_end.connect(_on_board_cell_drag_end)

	_board_view.cell_state_changed.connect(_on_board_changed_for_auto_complete)

	_board_view.cell_state_changed.connect(_on_cell_changed_for_auto_mark)

	_board_view.cell_state_changed.connect(_on_cell_changed_for_lock_x)
	_hint_overlay.hint_detail_requested.connect(_on_chain_detail_requested)
	_hint_overlay.layer = 10
	_build_strategy_overlay()
	UniKitManager.ad_closed.connect(_on_ad_closed)

	UniKitManager.ad_shown.connect(_on_ad_shown_for_timer)

	claim_button_sound($Root/VBoxContainer/Header/SettingsBtn)


func on_show(params: Dictionary = {}) -> void:
	Tracker.set_active_game_type(Tracker.GameType.DAILY)

	ABTestManager.dye_at_game_start()
	GameState.set_saved_game_auto_mark(ABTestManager.game_auto_mark.value())

	_pending_show_auto_mark_popup = _should_show_auto_mark_popup()

	params = params.duplicate()
	params["level_index"] = GameState.get_current_level()
	super.on_show(params)

	_board_view.visible = false

	var dt_local: Dictionary = Time.get_date_dict_from_system()
	_start_date = (
		"%d-%02d-%02d"
		% [dt_local.get("year", 2026), dt_local.get("month", 1), dt_local.get("day", 1)]
	)

	var _explicit_status: String = params.get("_tracker_status", "")
	if _explicit_status == Tracker.GameStatus.RESTART:
		_stat_status = Tracker.GameStatus.RESTART
	elif GameState.get_daily_started_date() == _start_date:
		_stat_status = Tracker.GameStatus.CONTINUE
	else:
		_stat_status = Tracker.GameStatus.NEW
		GameState.set_daily_started_date(_start_date)
		Tracker.new_game_id(Tracker.GameType.DAILY)
	_stat_start_ms = Time.get_ticks_msec()

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

	ABTestManager.dye_at_game_start_dc()
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
		entry = pool[entry_idx]
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
	}
	_puzzle = {"regions": int_regions, "solution": sol_2d}

	var dt: Dictionary = Time.get_datetime_dict_from_system()

	var month_str: String = tr("MONTH_ABBR_%d" % clampi(int(dt["month"]), 1, 12))
	_date_label.text = "%s.%d" % [month_str, dt["day"]]
	_level_display_value.text = "%02d/%02d" % [dt["month"], dt["day"]]
	_date_label.visible = not ABTestManager.combo_encourage.has_score_display()

	_lives = 3
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
		"wrong_cat_events": [],
		"missed_cat_candidates": {},
		"missed_cat_prev": {},
	}
	_start_unix = Time.get_unix_time_from_system()
	_timer_label.text = "00:00"
	_clock_timer.start()
	UIManager.hide_ui(UiName.DAILY_FAIL)
	UIManager.hide_ui(UiName.DAILY_WIN)
	_hint_overlay.visible = false

	_refresh_hearts()
	_sync_tools_from_state()

	await get_tree().process_frame

	_relayout_board()

	var sz_v: int = _level_config["size"]

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

	_apply_goal_emphasis_tracks(11)

	_apply_rule_swipe_collapse(11)

	_anim_player.play(_appear_anim_name())
	SoundManager.play(SoundManager.Kind.BOARD_ENTER)

	if (
		board_intro != null
		and not board_intro.animation_finished.is_connected(_on_appear_animation_finished)
	):
		board_intro.animation_finished.connect(_on_appear_animation_finished, CONNECT_ONE_SHOT)

	var color_seed: int = _level_config.get("daily_transform", 0)
	var color_map: Array[int] = LevelGenerator.compute_color_map_with_seed(
		sz, _puzzle["regions"], color_seed
	)

	if board_intro != null:
		board_intro.set_auto_trigger(false)
	_board_view.setup(sz, _puzzle["regions"], color_map, [], true)
	if board_intro != null:
		board_intro.set_auto_trigger(true)

	if board_intro != null:
		board_intro.set_process(false)
	($Root/VBoxContainer as Container).queue_sort()
	await get_tree().process_frame
	if board_intro != null:
		board_intro.play()

	_board_view.visible = true

	var _pid: String = LevelData.compute_puzzle_id(sz, _puzzle["regions"])
	PuzzleSessionTracker.record(_pid)

	_update_remaining()

	if _combo_feedback_view == null:
		_combo_feedback_view = get_node_or_null("Root/VBoxContainer/ComboFeedback")
	if _combo_feedback_view != null:
		_combo_feedback_view.reset(0)
	_connect_combo_signal()

	_reset_idle_hint()

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
		)
	)

	var ad_pos: String = Tracker.AdPos.NORMAL_START
	if _stat_status == Tracker.GameStatus.RESTART:
		ad_pos = Tracker.AdPos.NORMAL_RESTART
	elif _stat_status == Tracker.GameStatus.CONTINUE:
		ad_pos = Tracker.AdPos.NORMAL_CONTINUE

	if not _pending_show_auto_mark_popup:
		var inter_elig: Dictionary = _eval_start_interstitial(params, ad_pos)
		if _try_show_start_interstitial(ad_pos, inter_elig):
			_ad_show_unix = Time.get_unix_time_from_system()
			_start_unix = _ad_show_unix
			_timer_label.text = "00:00"

	_show_banner_if_eligible("daily")


func _should_show_auto_mark_popup() -> bool:
	if not ABTestManager.game_auto_mark.is_prop_ad_mode():
		return false
	if GameState.is_daily_auto_mark_enabled_for_today():
		return false
	if not GameState.is_daily_auto_mark_free_consumed():
		return true
	return UniKitManager.is_reward_valid("reward", Tracker.AdPos.AUTOX_REWARD)


func _get_elapsed_sec() -> int:
	return int(Time.get_unix_time_from_system() - _start_unix)


func _on_clock_timer_timeout() -> void:
	_refresh_timer_label()


func _refresh_timer_label() -> void:
	_apply_elapsed_to_label(_get_elapsed_sec())


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
	pass


func _on_application_focus_in() -> void:
	_compensate_ad_time()
	_refresh_timer_label()


func _on_ad_shown_for_timer(placement_id: String) -> void:
	if placement_id == "reward":
		_ad_show_unix = Time.get_unix_time_from_system()


func _compensate_ad_time() -> void:
	if _ad_show_unix <= 0.0:
		return
	var ad_duration: float = Time.get_unix_time_from_system() - _ad_show_unix
	print("[DailyGame] ad compensated %.1fs" % ad_duration)
	_start_unix += ad_duration
	_ad_show_unix = 0.0


func _on_ad_closed(_placement_id: String) -> void:
	_compensate_ad_time()
	_refresh_timer_label()


func _on_gear_btn_pressed() -> void:
	if _is_complete:
		return
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	_clock_timer.stop()
	UIManager.show_ui(UiName.HOME)
	UIManager.hide_ui(UiName.DAILY_GAME)


func _on_appear_animation_finished() -> void:
	super._on_appear_animation_finished()
	_unlock_entry_buttons()
	if _pending_show_auto_mark_popup:
		_pending_show_auto_mark_popup = false
		UIManager.show_ui(UiName.DAILY_AUTO_MARK_POPUP)


func _lock_entry_buttons() -> void:
	_entry_btn_lock_seq += 1
	for b in _entry_locked_buttons:
		if is_instance_valid(b):
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unlock_entry_buttons() -> void:
	for b in _entry_locked_buttons:
		if is_instance_valid(b):
			b.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_restart_requested() -> void:
	_combo_count = 0
	_combo_score = 0
	_hide_auto_complete_btn()
	_exit_draft_mode_and_clear()

	_destroy_banner()

	LevelOps.confirm_level_failed_daily(_build_game_end_params(Tracker.GameResult.QUIT))
	LevelOps.on_restart_click()
	on_show({"_tracker_status": Tracker.GameStatus.RESTART})


func _on_rule_violated(rule: int) -> void:
	if not ABTestManager.rule_highlight.is_all_levels():
		return
	_play_rule_highlight(rule)


func _reward_pos_for(btn: Control) -> String:
	if btn == _tool_locate_btn:
		return Tracker.AdPos.PROPS_DAILY_LOCATE
	elif btn == _tool_undo_btn:
		return "props_daily_undo"
	return Tracker.AdPos.PROPS_DAILY_HINT


func _on_game_over() -> void:
	_hide_auto_complete_btn()
	if not _is_complete:
		GameState.on_game_finished()
	_exit_draft_mode_and_clear()
	_is_complete = true
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_destroy_banner()
	Tracker.inc_stat("gamedie_count")

	ABTestManager.dye_at_game_fail_end()

	Tracker.track_game_end(_build_game_end_params(Tracker.GameResult.FAIL))
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL4)
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
			}
		)
	)
	if fail != null and not fail.revive_requested.is_connected(_on_revive_requested):
		fail.revive_requested.connect(_on_revive_requested)
	if fail != null and not fail.revive_ad_started.is_connected(_on_revive_ad_started):
		fail.revive_ad_started.connect(_on_revive_ad_started)


func _on_revive_ad_started() -> void:
	_board_view.revive_all_cat_to_idle()


func _on_revive_requested() -> void:
	UIManager.hide_ui(UiName.DAILY_FAIL)
	_is_complete = false
	GameState.inc_game_total_stat(Tracker.GameType.DAILY, "revive_count")
	GameState.inc_game_total_stat(Tracker.GameType.DAILY, "rv_count")

	_lives = mini(_lives + ABTestManager.revive_life.get_lives_to_restore(), 3)
	_refresh_hearts()

	if ABTestManager.revive_life.get_lives_to_restore() >= 3:
		for slot: LifeSlot in [_heart1, _heart2, _heart3]:
			if slot != null:
				slot.play_revive()
	_clock_timer.start()

	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]

	_board_view.revive_all_cat_to_idle()

	_show_banner_if_eligible("daily")


func _on_game_complete() -> void:
	_hide_auto_complete_btn()
	if not _is_complete:
		GameState.on_game_finished()

	_exit_draft_mode_and_clear(ABTestManager.draft_mode.keep_marks_on_manual_exit())
	_is_complete = true
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_destroy_banner()

	var elapsed_sec: int = _get_elapsed_sec()
	_apply_elapsed_to_label(elapsed_sec)
	var rank: int = _level_config.get("rank", 4)
	_level_config["elapsed_sec"] = elapsed_sec
	var raw_percent: float = DailyStats.beat_percent(
		elapsed_sec, rank, _level_config.get("size", 12)
	)

	if (
		ABTestManager.game_auto_mark.is_prop_ad_mode()
		and GameState.is_daily_auto_mark_enabled_for_today()
	):
		raw_percent = minf(raw_percent + 5.0, 99.9)
	_level_config["beat_percent"] = raw_percent

	Tracker.track_game_end(_build_game_end_params(Tracker.GameResult.WIN))

	SoundManager.stop(SoundManager.Kind.MARK_CAT)
	_board_view.replay_all_cat_appear()
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL5)
	_cleanup_hint()
	await get_tree().process_frame
	GameState.mark_daily_completed(_start_date, elapsed_sec, _level_config["beat_percent"])

	var toast_was_shown: bool = await _play_win_toast_and_wait()
	_level_config["toast_was_shown"] = toast_was_shown
	var streak_consumed_appear_delay: bool = await _try_run_streak_flow_after_win(
		&"challenge", toast_was_shown
	)
	_level_config["skip_appear_delay"] = streak_consumed_appear_delay
	UIManager.show_ui(_win_ui_name(), {"level_config": _level_config, "board_view": _board_view})


func _win_ui_name() -> StringName:
	return UiName.DAILY_WIN


func _try_run_streak_flow_after_win(source: StringName, skip_cat_appear: bool = false) -> bool:
	StreakManager.notify_win(source)
	if not StreakManager.has_pending_show():
		return false
	if not skip_cat_appear:
		await get_tree().create_timer(DailyWinPage.APPEAR_DELAY).timeout
	var streak_page: StreakPage

	if StreakManager.get_data().current_streak == 1 and not StreakManager.should_skip_lit():
		streak_page = StreakPage.open_lit()
	else:
		streak_page = StreakPage.open_settle()
	while is_instance_valid(streak_page) and streak_page.visible:
		await streak_page.visibility_changed
	return true


func _on_cheat_command(cmd_name: String, args: Array[String]) -> void:
	match cmd_name:
		"win":
			_cmd_win(args)
		"lives":
			_cmd_lives(args)


func _get_dc_bank_source(current_lv: int, day_offset: int) -> String:
	if ABTestManager.dc_level.is_override_enabled():
		var sz: int = ABTestManager.dc_level.get_pool_size(current_lv, day_offset)
		if ABTestManager.dc_level.use_gc_bank(sz, day_offset):
			return "gc"
		return "regular"
	return "lkstyle" if current_lv > 200 else "regular"


static func _local_date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045


func get_scr_name() -> String:
	return Tracker.Scr.DAILY_GAME


func _build_game_end_params(result: String) -> Dictionary:
	var time_sec: int = _level_config.get("elapsed_sec", 0)
	if time_sec <= 0:
		time_sec = _get_elapsed_sec()
	if time_sec == 0:
		@warning_ignore("integer_division")
		var fallback_sec: int = (Time.get_ticks_msec() - _stat_start_ms) / 1000
		time_sec = fallback_sec

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
		"hint": GameState.get_tool_count("hint"),
		"locate": GameState.get_tool_count("locate"),
		"hint_used": Tracker.get_stat("hint_used"),
		"locate_used": Tracker.get_stat("locate_used"),
		"hint_used_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "hint_used_total"),
		"locate_used_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "locate_used_total"),
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
		"coord_count": Tracker.get_stat("coord_count"),
		"step_used": Tracker.get_stat("step_used"),
		"step_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "step_total"),
		"gamedie_count": Tracker.get_stat("gamedie_count"),
		"restart_count": Tracker.get_stat("restart_count"),
		"time": time_sec,
		"time_total": GameState.get_game_total_stat(Tracker.GameType.DAILY, "time_total"),
		"percent": _level_config.get("beat_percent", 0.0),
		"cross_count": _board_view.count_mark_cells(),
		"invalid_sign": _board_view.count_error_cells(),
		"invalid_sign_total":
		GameState.get_game_total_stat(Tracker.GameType.DAILY, "invalid_sign_total"),
		"fail_sign": sz - cat_n,
		"erase_count": Tracker.get_stat("erase_count"),
		"revive_count": GameState.get_game_total_stat(Tracker.GameType.DAILY, "revive_count"),
		"rv_count": GameState.get_game_total_stat(Tracker.GameType.DAILY, "rv_count"),
		"hp_count": _lives,
	}
	return params
