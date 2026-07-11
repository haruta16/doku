extends Node

signal all_data_reset

const SAVE_DIR := "user://save_store/"
const SAVE_PATH_A := "user://save_store/save_a.cfg"
const SAVE_PATH_B := "user://save_store/save_b.cfg"
const SAVE_FLAG := "user://save_store/flag.txt"
const SAVE_PATH_OLD := "user://save.cfg"
const SAVE_PATH_ENDGAME := "user://save_store/endgame.cfg"

const SAVE_PASSWORD := "qd_x9K3mPv7RtN2sLwH8jFcZyA5eBkM1n"

var _player_store: SaveStore
var _endgame_store: SaveStore

var _endgame_dirty: bool = false
var _endgame_coalesce_timer: Timer

signal tool_count_changed(kind: String, count: int)

var _current_level: int = 1
var _tutorial_done: bool = false
var _has_shown_rate_us: bool = false

var _has_used_revive_free: bool = false

var _warn_life_shown: bool = false

var _life_plus_first_done: bool = false

var _current_strategy: int = 1

var _consecutive_clean_wins: int = 0

var _last_level_clean_win: bool = false

var _consecutive_fails: int = 0

var _consecutive_retry_levels: int = 0
var _retry_tracking_strategy: int = 0

var _bank_progress: Dictionary = {}

var _main_bank_progress: Dictionary = {}

var _lkmod_progress: Dictionary = {}

var _daily_index: int = 0

var _daily_completed_date: String = ""

var _max_daily_date: String = ""

var _daily_first_easy_date: String = ""

var _daily_elapsed_sec: int = 0
var _daily_beat_percent: float = 0.0

var _daily_best_beat_percent: float = 0.0

var _daily_started_date: String = ""

var _game_total_stats: Dictionary = {}

var _main_game_total_stats: Dictionary = {}
var _daily_game_total_stats: Dictionary = {}

var _main_game_round_stats: Dictionary = {}
var _daily_game_round_stats: Dictionary = {}

var _main_game_id: String = ""
var _daily_game_id: String = ""

var _tool_locate: int = 5
var _tool_hint: int = 5
var _tool_undo: int = 3

var _last_splash_date: String = ""

var _apply_locale: String = ""

var _is_first_session: bool = true

var _last_first_level_date: String = ""

var _music_on: bool = true

var _music_user_modified: bool = false
var _sound_on: bool = true
var _vibration_on: bool = true

var _people_on: bool = true

var _has_used_tool: bool = false

var _prop_highlight_shown: bool = false
var _push_ask_count: int = 0

var _has_shown_att_guide: bool = false

var _interstitial_unlocked: bool = false

var _banner_unlocked: bool = false

var _has_shown_draft_onboarding: bool = false

var _auto_mark_tutorial_done: bool = false

var _rule_info_bar_collapsed: bool = false

var _grt_level_d90_reported: Array = []

var _grt_reported_events: Array = []

var _first_open_time_ms: int = 0

var _today_date: String = ""

var _session_count: int = 0

var _today_session_count: int = 0

var _last_day_session_count: int = 0

var _active_days: int = 0

var _today_played_count: int = 0

var _today_active_sec: int = 0

var _total_active_sec: int = 0

var _pending_rewards: Array = []

var _reward_history_ts: Array = []

var _restored_today_count: int = 0

var _in_flight_awards: Array = []

var _daily_auto_mark_enabled: bool = false

var _daily_auto_mark_free_consumed: bool = false

var _saved_game_auto_mark: int = -1

var _retry_puzzle_level: int = 0
var _retry_puzzle_params: Dictionary = {}

var _recent_puzzles: Array = []
const RECENT_PUZZLES_LIMIT := 100

var _endgame_snapshot: Dictionary = {}
const ENDGAME_SNAPSHOT_VERSION: int = 2

var _debug_mode: bool = false

var _current_level_dirty: bool = false

var _current_level_retried: bool = false

var _demoted_this_level: bool = false

var _dda_tool_or_revive_used: bool = false

var _dda_revive_used: bool = false

var _dda_pending_demote: bool = false

var _is_daily_first_easy_level: bool = false

var _rnr_mod1_exempt: bool = false

var _rnr_g_prev_was_max: bool = false

var coords_visible: bool = false

var _first_session_runtime: bool = true

var _session_played_count: int = 0

var _has_won_since_cold_start: bool = false

var _daily_first_easy_available: bool = false
var _daily_first_easy_evaluated: bool = false

var _session_consecutive_wins: int = 0

var _session_reward_view_count: int = 0

var _start_toast_pct: Dictionary = {}

var _start_toast_iq_idx: Dictionary = {}

var _fail_text_revive_x: Dictionary = {}

var _last_win_beat_percent: float = -1.0

var _help_last_open_time: int = 0

var _install_version: String = ""


func _ready() -> void:
	_player_store = SaveStore.new(
		SAVE_PASSWORD, SAVE_DIR, true, SAVE_PATH_A, SAVE_PATH_B, SAVE_FLAG, SAVE_PATH_OLD
	)
	_endgame_store = SaveStore.new(SAVE_PASSWORD, SAVE_DIR, false, SAVE_PATH_ENDGAME)
	_endgame_coalesce_timer = Timer.new()
	_endgame_coalesce_timer.one_shot = true
	_endgame_coalesce_timer.wait_time = 0.5
	_endgame_coalesce_timer.timeout.connect(_on_endgame_coalesce_timeout)
	add_child(_endgame_coalesce_timer)
	_migrate_legacy_save()
	_load_data()
	_first_session_runtime = _is_first_session
	VibrateManager.set_enabled(_vibration_on)


func get_current_level() -> int:
	return _current_level


func set_current_level(value: int) -> void:
	_current_level = value
	_save_data()


func is_tutorial_done() -> bool:
	return _tutorial_done


func set_tutorial_done(value: bool) -> void:
	_tutorial_done = value
	_save_data()


func has_shown_rate_us() -> bool:
	return _has_shown_rate_us


func has_used_revive_free() -> bool:
	return _has_used_revive_free


func mark_revive_free_used() -> void:
	if _has_used_revive_free:
		return
	_has_used_revive_free = true
	_save_data()


func has_won_since_cold_start() -> bool:
	return _has_won_since_cold_start


func is_daily_first_easy_available() -> bool:
	return _daily_first_easy_available


func evaluate_daily_first_easy() -> void:
	if _daily_first_easy_evaluated:
		return
	_daily_first_easy_evaluated = true
	var today: String = _today_str()
	if _daily_first_easy_date >= today:
		_daily_first_easy_available = false
		print("[DailyFirstEasy] 今日已消耗过,不可降档")
		return

	var snapshot: Dictionary = _endgame_snapshot
	if not snapshot.is_empty():
		var snap_level: int = int(snapshot.get("level", 0))
		var lives_left: int = int(snapshot.get("lives", 0))

		if snap_level == _current_level and lives_left > 0:
			var prefill_count: int = (snapshot.get("prefill_positions", []) as Array).size()
			var user_cats: int = (snapshot.get("placed_cats", []) as Array).size() - prefill_count
			var user_marks: int = (snapshot.get("marks", []) as Array).size()
			var user_errors: int = (snapshot.get("errors", []) as Array).size()
			if user_cats > 0 or user_marks > 0 or user_errors > 0:
				_daily_first_easy_date = today
				_daily_first_easy_available = false
				_save_data()
				print(
					(
						"[DailyFirstEasy] 有操作残局,机会作废 (level=%d cats=%d marks=%d errors=%d lives=%d)"
						% [snap_level, user_cats, user_marks, user_errors, lives_left]
					)
				)
				return

	_daily_first_easy_available = true
	print("[DailyFirstEasy] 冷启动评估: 可降档")


func consume_daily_first_easy() -> void:
	_daily_first_easy_date = _today_str()
	_daily_first_easy_available = false
	_save_data()


func consume_daily_first_easy_and_mark() -> void:
	consume_daily_first_easy()
	_is_daily_first_easy_level = true


func advance_daily_first_easy_date() -> void:
	var today: String = _today_str()
	if _daily_first_easy_date >= today:
		return
	_daily_first_easy_date = today
	_daily_first_easy_available = false
	_save_data()
	print("[DailyFirstEasy] 局内跨天+开始新对局, 推进日期消耗机会")


func cheat_reset_daily_first_easy() -> void:
	_daily_first_easy_date = ""
	_save_data()


func mark_rnr_mod1_exempt() -> void:
	_rnr_mod1_exempt = true


func clear_rnr_mod1_exempt() -> void:
	_rnr_mod1_exempt = false


func is_rnr_mod1_exempt() -> bool:
	return _rnr_mod1_exempt


func is_rnr_g_prev_was_max() -> bool:
	return _rnr_g_prev_was_max


func set_rnr_g_prev_was_max(was_max: bool) -> void:
	_rnr_g_prev_was_max = was_max


func get_session_consecutive_wins() -> int:
	return _session_consecutive_wins


func get_session_reward_view_count() -> int:
	return _session_reward_view_count


func increment_session_reward_view_count() -> void:
	_session_reward_view_count += 1


func reset_session_reward_view_count() -> void:
	_session_reward_view_count = 0


func set_session_reward_view_count(value: int) -> void:
	_session_reward_view_count = max(0, value)


func mark_rate_us_shown() -> void:
	if _has_shown_rate_us:
		return
	_has_shown_rate_us = true
	_save_data()


func reset_rate_us_shown() -> void:
	if not _has_shown_rate_us:
		return
	_has_shown_rate_us = false
	_save_data()


func has_shown_warn_life() -> bool:
	return _warn_life_shown


func mark_warn_life_shown() -> void:
	if _warn_life_shown:
		return
	_warn_life_shown = true
	_save_data()


func reset_warn_life_shown() -> void:
	if not _warn_life_shown:
		return
	_warn_life_shown = false
	_save_data()


func is_life_plus_first_done() -> bool:
	return _life_plus_first_done


func mark_life_plus_first_done() -> void:
	if _life_plus_first_done:
		return
	_life_plus_first_done = true
	_save_data()


func reset_life_plus_first_done() -> void:
	if not _life_plus_first_done:
		return
	_life_plus_first_done = false
	_save_data()


func has_shown_att_guide() -> bool:
	return _has_shown_att_guide


func mark_att_guide_shown() -> void:
	if _has_shown_att_guide:
		return
	_has_shown_att_guide = true
	_save_data()


func is_interstitial_unlocked() -> bool:
	return _interstitial_unlocked


func mark_interstitial_unlocked() -> void:
	if _interstitial_unlocked:
		return
	_interstitial_unlocked = true
	_save_data()


func is_banner_unlocked() -> bool:
	return _banner_unlocked


func mark_banner_unlocked() -> void:
	if _banner_unlocked:
		return
	_banner_unlocked = true
	_save_data()


func has_shown_draft_onboarding() -> bool:
	return _has_shown_draft_onboarding


func mark_draft_onboarding_shown() -> void:
	if _has_shown_draft_onboarding:
		return
	_has_shown_draft_onboarding = true
	_save_data()


func reset_draft_onboarding_shown() -> void:
	if not _has_shown_draft_onboarding:
		return
	_has_shown_draft_onboarding = false
	_save_data()


func is_auto_mark_tutorial_done() -> bool:
	return _auto_mark_tutorial_done


func mark_auto_mark_tutorial_done() -> void:
	if _auto_mark_tutorial_done:
		return
	_auto_mark_tutorial_done = true
	_save_data()


func reset_auto_mark_tutorial_done() -> void:
	if not _auto_mark_tutorial_done:
		return
	_auto_mark_tutorial_done = false
	_save_data()


func is_daily_auto_mark_enabled_for_today() -> bool:
	_roll_day_if_needed()
	return _daily_auto_mark_enabled


func mark_daily_auto_mark_enabled_today() -> void:
	_roll_day_if_needed()
	if _daily_auto_mark_enabled:
		return
	_daily_auto_mark_enabled = true
	_save_data()


func reset_daily_auto_mark_enabled() -> void:
	if not _daily_auto_mark_enabled:
		return
	_daily_auto_mark_enabled = false
	_save_data()


func is_daily_auto_mark_free_consumed() -> bool:
	return _daily_auto_mark_free_consumed


func mark_daily_auto_mark_free_consumed() -> void:
	if _daily_auto_mark_free_consumed:
		return
	_daily_auto_mark_free_consumed = true
	_save_data()


func reset_daily_auto_mark_free_consumed() -> void:
	if not _daily_auto_mark_free_consumed:
		return
	_daily_auto_mark_free_consumed = false
	_save_data()


func get_saved_game_auto_mark() -> int:
	return _saved_game_auto_mark


func set_saved_game_auto_mark(v: int) -> void:
	if _saved_game_auto_mark == v:
		return
	_saved_game_auto_mark = v
	_save_data()


func is_rule_info_bar_collapsed() -> bool:
	return _rule_info_bar_collapsed


func set_rule_info_bar_collapsed(value: bool) -> void:
	if _rule_info_bar_collapsed == value:
		return
	_rule_info_bar_collapsed = value
	_save_data()


func has_grt_level_d90_reported(level: int) -> bool:
	return _grt_level_d90_reported.has(level)


func mark_grt_level_d90_reported(level: int) -> void:
	if _grt_level_d90_reported.has(level):
		return
	_grt_level_d90_reported.append(level)
	_save_data()


func has_grt_event_reported(event_name: String) -> bool:
	return _grt_reported_events.has(event_name)


func mark_grt_event_reported(event_name: String) -> void:
	if _grt_reported_events.has(event_name):
		return
	_grt_reported_events.append(event_name)
	_save_data()


func get_first_open_time_ms() -> int:
	return _first_open_time_ms


func ensure_first_open_time(sdk_value_ms: int) -> void:
	if _first_open_time_ms > 0:
		return
	if sdk_value_ms > 0:
		_first_open_time_ms = sdk_value_ms
	else:
		_first_open_time_ms = int(Time.get_unix_time_from_system() * 1000.0)
	_save_data()


func get_current_strategy() -> int:
	return _current_strategy


func set_current_strategy(value: int) -> void:
	_current_strategy = value
	_save_data()


func get_daily_completed_date() -> String:
	return _daily_completed_date


func get_daily_started_date() -> String:
	return _daily_started_date


func set_daily_started_date(date: String) -> void:
	_daily_started_date = date
	_save_data()


func inc_game_total_stat(game_type: String, key: String, delta: int = 1) -> void:
	var d: Dictionary = _get_total_stats_dict(game_type)
	d[key] = int(d.get(key, 0)) + delta
	_request_save_endgame()


func get_game_total_stat(game_type: String, key: String) -> int:
	return int(_get_total_stats_dict(game_type).get(key, 0))


func get_persisted_game_id(game_type: String) -> String:
	if game_type == "daily":
		return _daily_game_id
	return _main_game_id


func set_persisted_game_id(game_type: String, value: String) -> void:
	if game_type == "daily":
		_daily_game_id = value
	else:
		_main_game_id = value
	_save_endgame()


func reset_game_total_stats(game_type: String) -> void:
	var d: Dictionary = _get_total_stats_dict(game_type)
	if d.is_empty():
		return
	d.clear()
	_save_endgame()


func get_game_round_stats(game_type: String) -> Dictionary:
	if game_type == "daily":
		return _daily_game_round_stats.duplicate()
	return _main_game_round_stats.duplicate()


func persist_game_round_stats(game_type: String, stats: Dictionary) -> void:
	if game_type == "daily":
		_daily_game_round_stats = stats.duplicate()
	else:
		_main_game_round_stats = stats.duplicate()
	_request_save_endgame()


func reset_game_round_stats(game_type: String) -> void:
	var d: Dictionary = _get_round_stats_dict(game_type)
	if d.is_empty():
		return
	d.clear()
	_save_endgame()


func _get_round_stats_dict(game_type: String) -> Dictionary:
	if game_type == "daily":
		return _daily_game_round_stats
	return _main_game_round_stats


func _get_total_stats_dict(game_type: String) -> Dictionary:
	if game_type == "daily":
		return _daily_game_total_stats
	return _main_game_total_stats


func get_max_daily_date() -> String:
	return _max_daily_date


func advance_max_daily_date(date: String) -> void:
	if date > _max_daily_date:
		_max_daily_date = date
		_save_data()


func get_daily_elapsed_sec() -> int:
	return _daily_elapsed_sec


func get_daily_beat_percent() -> float:
	return _daily_beat_percent


func get_daily_best_beat_percent() -> float:
	return _daily_best_beat_percent


func mark_daily_completed(date: String, elapsed_sec: int, beat_percent: float) -> void:
	_daily_completed_date = date
	_daily_elapsed_sec = elapsed_sec
	_daily_beat_percent = beat_percent

	if beat_percent > _daily_best_beat_percent:
		_daily_best_beat_percent = beat_percent
	_has_won_since_cold_start = true
	_save_data()


func clear_daily_completion() -> void:
	_daily_completed_date = ""
	_daily_elapsed_sec = 0
	_daily_beat_percent = 0.0
	_daily_best_beat_percent = 0.0
	_save_data()


func _roll_day_if_needed() -> void:
	var today: String = _today_str()
	if _today_date == today:
		return
	_last_day_session_count = _today_session_count
	_today_session_count = 0
	_today_played_count = 0
	_today_active_sec = 0
	_restored_today_count = 0
	_daily_auto_mark_enabled = false
	_pending_rewards.clear()
	_active_days += 1
	_today_date = today


func on_session_started() -> void:
	_roll_day_if_needed()
	_session_count += 1
	_today_session_count += 1
	_session_played_count = 0
	_session_consecutive_wins = 0
	_session_reward_view_count = 0
	_save_data()


func get_session_count() -> int:
	return _session_count


func get_active_days() -> int:
	_roll_day_if_needed()
	return _active_days


func get_session_played_count() -> int:
	return _session_played_count


func get_today_played_count() -> int:
	_roll_day_if_needed()
	return _today_played_count


func on_game_finished() -> void:
	_roll_day_if_needed()
	_session_played_count += 1
	_today_played_count += 1
	_save_data()


func get_today_active_sec() -> int:
	_roll_day_if_needed()
	return _today_active_sec


func add_today_active_sec(delta_sec: int) -> void:
	if delta_sec <= 0:
		return
	_roll_day_if_needed()
	_today_active_sec += delta_sec
	_total_active_sec += delta_sec
	_save_data()


func get_total_active_sec() -> int:
	return _total_active_sec


const _REWARD_HISTORY_RETAIN_SEC: int = 7 * 24 * 3600

const _RESTORE_MIN_NORMAL_REWARDS_3D: int = 3
const _RESTORE_NORMAL_LOOKBACK_SEC: int = 3 * 24 * 3600

const _RESTORE_DAILY_MAX: int = 3


func has_pending_rewards() -> bool:
	return not _pending_rewards.is_empty()


func get_pending_rewards() -> Array:
	return _pending_rewards


func add_pending_reward(reward: Dictionary) -> void:
	_pending_rewards.append(reward)
	_save_data()


func pop_all_pending_rewards() -> Array:
	var out: Array = _pending_rewards.duplicate()
	_pending_rewards.clear()
	_save_data()
	return out


func record_normal_reward(ts: int) -> void:
	_reward_history_ts.append(ts)
	var cutoff: int = ts - _REWARD_HISTORY_RETAIN_SEC
	var fresh: Array = []
	for t in _reward_history_ts:
		if int(t) >= cutoff:
			fresh.append(int(t))
	_reward_history_ts = fresh
	_save_data()


func _count_recent_normal_rewards(now_ts: int) -> int:
	var cutoff: int = now_ts - _RESTORE_NORMAL_LOOKBACK_SEC
	var hits: int = 0
	for t in _reward_history_ts:
		if int(t) >= cutoff:
			hits += 1
	return hits


func get_restore_remaining_today(now_ts: int) -> int:
	_roll_day_if_needed()
	var recent: int = _count_recent_normal_rewards(now_ts)
	if recent < _RESTORE_MIN_NORMAL_REWARDS_3D:
		return 0
	return max(0, _RESTORE_DAILY_MAX - _restored_today_count)


func get_restored_today_count() -> int:
	_roll_day_if_needed()
	return _restored_today_count


func add_restored_today_count(n: int) -> void:
	_roll_day_if_needed()
	_restored_today_count += n
	_save_data()


func remove_pending_rewards(entries: Array) -> void:
	for e in entries:
		_pending_rewards.erase(e)
	_save_data()


func get_today_session_count() -> int:
	_roll_day_if_needed()
	return _today_session_count


func get_last_day_session_count() -> int:
	_roll_day_if_needed()
	return _last_day_session_count


func get_tool_count(kind: String) -> int:
	match kind:
		"locate":
			return _tool_locate
		"hint":
			return _tool_hint
		"undo":
			return _tool_undo
		_:
			return 0


func has_used_tool() -> bool:
	return _has_used_tool


func has_prop_highlight_shown() -> bool:
	return _prop_highlight_shown


func mark_prop_highlight_shown() -> void:
	if _prop_highlight_shown:
		return
	_prop_highlight_shown = true
	_save_data()


func get_push_ask_count() -> int:
	return _push_ask_count


func inc_push_ask_count() -> void:
	_push_ask_count += 1
	_save_data()


func set_tool_count(kind: String, count: int) -> void:
	var prev: int = get_tool_count(kind)
	match kind:
		"locate":
			_tool_locate = count
		"hint":
			_tool_hint = count
		"undo":
			_tool_undo = count
		_:
			return
	if count < prev and not _has_used_tool:
		_has_used_tool = true
	_save_data()
	tool_count_changed.emit(kind, count)


func get_in_flight_awards() -> Array:
	return _in_flight_awards.duplicate()


func add_in_flight_award(entry: Dictionary) -> void:
	_in_flight_awards.append(entry)
	_save_data()


func remove_in_flight_award(uid: int) -> void:
	for i in range(_in_flight_awards.size() - 1, -1, -1):
		if int(_in_flight_awards[i].get("uid", -1)) == uid:
			_in_flight_awards.remove_at(i)
			_save_data()
			return


func find_in_flight_award(uid: int) -> Dictionary:
	for entry: Dictionary in _in_flight_awards:
		if int(entry.get("uid", -1)) == uid:
			return entry
	return {}


func get_last_splash_date() -> String:
	return _last_splash_date


func set_last_splash_date(value: String) -> void:
	_last_splash_date = value
	_save_data()


func get_apply_locale() -> String:
	return _apply_locale


func set_apply_locale(value: String) -> void:
	_apply_locale = value
	_save_data()


func is_first_session() -> bool:
	return _first_session_runtime


func mark_first_session_done() -> void:
	if not _first_session_runtime:
		return
	_first_session_runtime = false


func consume_first_session_persist() -> void:
	if not _is_first_session:
		return
	_is_first_session = false
	_save_data()


func is_today_first_level() -> bool:
	return _last_first_level_date != _today_str()


func consume_today_first_level() -> void:
	var today: String = _today_str()
	if _last_first_level_date == today:
		return
	_last_first_level_date = today
	_save_data()


func is_music_on() -> bool:
	return _music_on


func set_music_on(value: bool) -> void:
	_music_on = value
	_music_user_modified = true
	_save_data()


func init_music_default(default_on: bool) -> void:
	if _music_user_modified:
		return
	if _music_on == default_on:
		return
	_music_on = default_on
	_save_data()


func is_sound_on() -> bool:
	return _sound_on


func set_sound_on(value: bool) -> void:
	_sound_on = value
	_save_data()


func is_vibration_on() -> bool:
	return _vibration_on


func set_vibration_on(value: bool) -> void:
	_vibration_on = value
	VibrateManager.set_enabled(value)
	_save_data()


func is_people_on() -> bool:
	return _people_on


func set_people_on(value: bool) -> void:
	_people_on = value
	_save_data()


func is_debug_mode() -> bool:
	return _debug_mode or not OS.has_feature("rel")


func set_debug_mode(value: bool) -> void:
	_debug_mode = value


func is_current_level_dirty() -> bool:
	return _current_level_dirty


func mark_current_level_dirty() -> void:
	_current_level_dirty = true


func clear_current_level_dirty() -> void:
	_current_level_dirty = false


func mark_dda_tool_or_revive_used() -> void:
	_dda_tool_or_revive_used = true


func mark_dda_revive_used() -> void:
	_dda_revive_used = true


func mark_daily_first_easy_level() -> void:
	_is_daily_first_easy_level = true


func is_current_level_daily_first_easy() -> bool:
	return _is_daily_first_easy_level


func is_current_level_retried() -> bool:
	return _current_level_retried


func set_retry_puzzle(level: int, params: Dictionary) -> void:
	_retry_puzzle_level = level
	_retry_puzzle_params = params
	_save_data()


func get_retry_puzzle(level: int) -> Dictionary:
	if _retry_puzzle_level == level and not _retry_puzzle_params.is_empty():
		return _retry_puzzle_params
	return {}


func get_start_toast_pct(level: int, kind: String) -> float:
	var bucket: Dictionary = _start_toast_pct.get(level, {})
	return float(bucket.get(kind, -1.0))


func set_start_toast_pct(level: int, kind: String, pct: float) -> void:
	var bucket: Dictionary = _start_toast_pct.get(level, {})
	bucket[kind] = pct
	_start_toast_pct[level] = bucket


func clear_start_toast_pct(level: int = -1) -> void:
	if level < 0:
		_start_toast_pct.clear()
	else:
		_start_toast_pct.erase(level)


func get_start_toast_iq_idx(level: int) -> int:
	return int(_start_toast_iq_idx.get(level, 0))


func set_start_toast_iq_idx(level: int, idx: int) -> void:
	_start_toast_iq_idx[level] = idx


func clear_start_toast_iq_idx(level: int = -1) -> void:
	if level < 0:
		_start_toast_iq_idx.clear()
	else:
		_start_toast_iq_idx.erase(level)


func get_fail_text_revive_x(level: int) -> float:
	return float(_fail_text_revive_x.get(level, -1.0))


func set_fail_text_revive_x(level: int, x: float) -> void:
	_fail_text_revive_x[level] = x


func clear_fail_text_revive_x(level: int = -1) -> void:
	if level < 0:
		_fail_text_revive_x.clear()
	else:
		_fail_text_revive_x.erase(level)


func get_last_win_beat_percent() -> float:
	return _last_win_beat_percent


func set_last_win_beat_percent(pct: float) -> void:
	_last_win_beat_percent = pct
	_save_data()


func get_help_last_open_time() -> int:
	return _help_last_open_time


func set_help_last_open_time(value: int) -> void:
	_help_last_open_time = value
	_save_data()


func get_install_version() -> String:
	return _install_version


func ensure_install_version(version: String) -> void:
	if not _install_version.is_empty():
		return
	if version.is_empty():
		return
	_install_version = version
	_save_data()


func get_consecutive_clean_wins() -> int:
	return _consecutive_clean_wins


func was_last_level_clean_win() -> bool:
	return _last_level_clean_win


func get_bank_index(sz: int, rank: int, tier: String = "") -> int:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	return _bank_progress.get(key, 0)


func advance_bank_index(sz: int, rank: int, tier: String = "") -> void:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_bank_progress[key] = _bank_progress.get(key, 0) + 1
	_save_data()


func get_main_progress(sz: int, rank: int, tier: String = "") -> Dictionary:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	if not _main_bank_progress.has(key):
		_main_bank_progress[key] = {"lk_mod": 0, "regular": 0, "lkstyle": 0, "transform": 0}
	return _main_bank_progress[key]


func set_main_progress(sz: int, rank: int, tier: String, progress: Dictionary) -> void:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_main_bank_progress[key] = progress
	_save_data()


func get_lkmod_progress(sz: int, rank: int) -> Dictionary:
	var key := "%d_%d" % [sz, rank]
	if not _lkmod_progress.has(key):
		_lkmod_progress[key] = {"idx": 0}
	return _lkmod_progress[key]


func set_lkmod_progress(sz: int, rank: int, progress: Dictionary) -> void:
	var key := "%d_%d" % [sz, rank]
	_lkmod_progress[key] = progress
	_save_data()


func get_bank_progress_snapshot() -> Dictionary:
	return _bank_progress.duplicate(true)


func get_main_bank_progress_snapshot() -> Dictionary:
	return _main_bank_progress.duplicate(true)


func get_lkmod_progress_snapshot() -> Dictionary:
	return _lkmod_progress.duplicate(true)


func record_puzzle(
	puzzle_id: String, level: int, version: String = "", src: String = ""
) -> Dictionary:
	var prev: Dictionary = {}
	for i in range(_recent_puzzles.size() - 1, -1, -1):
		var entry: Dictionary = _recent_puzzles[i]
		if entry.get("puzzle_id", "") == puzzle_id:
			prev = entry.duplicate(true)
			break
	(
		_recent_puzzles
		. append(
			{
				"puzzle_id": puzzle_id,
				"level": level,
				"v": version,
				"src": src,
				"ts": int(Time.get_unix_time_from_system()),
				"bank_progress": _bank_progress.duplicate(true),
				"main_bank_progress": _main_bank_progress.duplicate(true),
				"lkmod_progress": _lkmod_progress.duplicate(true),
			}
		)
	)
	while _recent_puzzles.size() > RECENT_PUZZLES_LIMIT:
		_recent_puzzles.pop_front()
	_save_data()
	return prev


func get_recent_puzzles() -> Array:
	return _recent_puzzles.duplicate(true)


func get_endgame_snapshot() -> Dictionary:
	return _endgame_snapshot


func set_endgame_snapshot(snapshot: Dictionary) -> void:
	_endgame_snapshot = snapshot
	_save_endgame()

	print("[Endgame] saved\n%s" % JSON.stringify(snapshot))


func clear_endgame_snapshot() -> void:
	if _endgame_snapshot.is_empty():
		return
	_endgame_snapshot = {}
	_save_endgame()
	print("[Endgame] cleared")


func _is_endgame_store_empty() -> bool:
	return (
		_endgame_snapshot.is_empty()
		and _main_game_total_stats.is_empty()
		and _daily_game_total_stats.is_empty()
		and _main_game_round_stats.is_empty()
		and _daily_game_round_stats.is_empty()
		and _main_game_id.is_empty()
		and _daily_game_id.is_empty()
	)


func _save_endgame() -> void:
	_endgame_dirty = false
	if _endgame_coalesce_timer != null:
		_endgame_coalesce_timer.stop()
	if _is_endgame_store_empty():
		_endgame_store.remove()
		return
	var cfg := ConfigFile.new()
	cfg.set_value("snapshot", "data", _endgame_snapshot)
	cfg.set_value("stats", "main_total", _main_game_total_stats)
	cfg.set_value("stats", "daily_total", _daily_game_total_stats)
	cfg.set_value("stats", "main_round", _main_game_round_stats)
	cfg.set_value("stats", "daily_round", _daily_game_round_stats)
	cfg.set_value("stats", "main_id", _main_game_id)
	cfg.set_value("stats", "daily_id", _daily_game_id)
	_endgame_store.save_config(cfg)


func _request_save_endgame() -> void:
	_endgame_dirty = true
	if _endgame_coalesce_timer != null and _endgame_coalesce_timer.is_stopped():
		_endgame_coalesce_timer.start()


func _on_endgame_coalesce_timeout() -> void:
	if _endgame_dirty:
		_save_endgame()


func _resolve_endgame_store() -> void:
	var ecfg := _endgame_store.load_config()
	if ecfg != null:
		_endgame_snapshot = ecfg.get_value("snapshot", "data", {})
		_main_game_total_stats = ecfg.get_value("stats", "main_total", {})
		_daily_game_total_stats = ecfg.get_value("stats", "daily_total", {})
		_main_game_round_stats = ecfg.get_value("stats", "main_round", {})
		_daily_game_round_stats = ecfg.get_value("stats", "daily_round", {})
		_main_game_id = ecfg.get_value("stats", "main_id", "")
		_daily_game_id = ecfg.get_value("stats", "daily_id", "")
	elif not _is_endgame_store_empty():
		_save_endgame()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _endgame_dirty:
			_save_endgame()


func on_level_won(level_num: int) -> void:
	var next_level: int = level_num + 1
	if next_level > _current_level:
		_current_level = next_level

	if _rnr_mod1_exempt:
		_rnr_mod1_exempt = false
		_current_level_retried = false
		_current_level_dirty = false
		_dda_tool_or_revive_used = false
		_dda_revive_used = false
		_is_daily_first_easy_level = false
		_demoted_this_level = false
		_retry_puzzle_level = 0
		_retry_puzzle_params = {}
		_start_toast_pct.erase(level_num)
		_start_toast_iq_idx.erase(level_num)
		_has_won_since_cold_start = true
		_session_consecutive_wins += 1
		Tracker.try_track_grt_level_pass(level_num)
		Tracker.try_track_grt_level_window(level_num)
		_save_data()
		return

	if level_num >= 6:
		var max_strategy: int
		if level_num >= 201:
			max_strategy = 6
		elif level_num >= 101:
			max_strategy = 5
		elif level_num >= 51:
			max_strategy = 4
		elif level_num >= 21:
			max_strategy = 3
		else:
			max_strategy = 2
		var win_threshold: int = 1 if level_num >= 51 else 2
		var min_strategy: int = 2 if level_num >= 101 else 1
		var clean_win: bool = not _current_level_dirty
		if clean_win:
			_consecutive_clean_wins += 1
			if _consecutive_clean_wins >= win_threshold and _current_strategy < max_strategy:
				_current_strategy += 1
				_consecutive_clean_wins = 0
		else:
			_consecutive_clean_wins = 0

		var fail_threshold: int = 2 if level_num >= 21 else 1
		if (
			_consecutive_fails >= fail_threshold
			and _current_strategy > min_strategy
			and not _demoted_this_level
		):
			_current_strategy -= 1
			_demoted_this_level = true

		_consecutive_fails = 0

		if level_num >= 21:
			if _current_level_retried:
				if _current_strategy == _retry_tracking_strategy:
					_consecutive_retry_levels += 1
					var min_strategy_retry: int = 2 if level_num >= 101 else 1
					if (
						_consecutive_retry_levels >= 2
						and _current_strategy > min_strategy_retry
						and not _demoted_this_level
					):
						_current_strategy -= 1
						_consecutive_retry_levels = 0
						_retry_tracking_strategy = 0
				else:
					_consecutive_retry_levels = 1
					_retry_tracking_strategy = _current_strategy
			else:
				_consecutive_retry_levels = 0
				_retry_tracking_strategy = 0

		_dda_apply_demote_on_won(level_num, min_strategy)

	_last_level_clean_win = not _current_level_dirty
	_current_level_retried = false
	_current_level_dirty = false
	_dda_tool_or_revive_used = false
	_dda_revive_used = false
	_is_daily_first_easy_level = false
	_rnr_mod1_exempt = false
	_demoted_this_level = false
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_start_toast_pct.erase(level_num)
	_start_toast_iq_idx.erase(level_num)
	_has_won_since_cold_start = true
	_session_consecutive_wins += 1

	Tracker.try_track_grt_level_pass(level_num)

	Tracker.try_track_grt_level_window(level_num)
	_save_data()


func on_level_failed(level_num: int) -> void:
	_current_level_retried = true
	_current_level_dirty = true

	_last_level_clean_win = false
	_session_consecutive_wins = 0

	if _rnr_mod1_exempt:
		_save_data()
		return
	if level_num >= 6:
		_consecutive_clean_wins = 0

		_consecutive_fails += 1

	if ABTestManager.dda_rank.is_any_action_demote():
		_dda_tool_or_revive_used = true
	_save_data()


func _dda_apply_demote_on_won(level_num: int, min_strategy: int) -> void:
	if not (
		ABTestManager.dda_rank.is_retry_once_demote()
		or ABTestManager.dda_rank.is_tool_revive_demote()
		or ABTestManager.dda_rank.is_any_action_demote()
	):
		return

	if _is_daily_first_easy_level:
		return

	var triggered: bool = false
	if ABTestManager.dda_rank.is_retry_once_demote():
		triggered = _current_level_retried or _dda_revive_used
	elif ABTestManager.dda_rank.is_tool_revive_demote():
		triggered = _dda_tool_or_revive_used
	else:
		triggered = _dda_tool_or_revive_used

	var next_level: int = level_num + 1
	var next_is_hard: bool = (
		LevelData.is_hard_level_group_j(next_level)
		if ABTestManager.rule_normal_rank.is_group_j()
		else LevelData.is_hard_level(next_level)
	)
	var next_is_skip: bool = next_is_hard or LevelData.is_special_level(next_level)

	if _dda_pending_demote and not _demoted_this_level:
		_current_strategy = max(min_strategy, _current_strategy - 1)
		_dda_pending_demote = false
		_demoted_this_level = true

	if triggered and not _demoted_this_level:
		if next_is_skip:
			_dda_pending_demote = true
		else:
			_current_strategy = max(min_strategy, _current_strategy - 1)
			_demoted_this_level = true


func cheat_jump_to_level(level: int) -> void:
	level = max(1, level)
	var max_strategy: int
	if level <= 5:
		max_strategy = 1
	elif level <= 20:
		max_strategy = 2
	elif level <= 50:
		max_strategy = 3
	elif level <= 100:
		max_strategy = 4
	elif level <= 200:
		max_strategy = 5
	else:
		max_strategy = 6
	var min_strategy: int
	if level <= 5:
		min_strategy = 1
	elif level <= 50:
		min_strategy = 1
	else:
		min_strategy = 2
	_current_strategy = clampi(_current_strategy, min_strategy, max_strategy)
	_current_level = level

	_tutorial_done = true
	_consecutive_clean_wins = 0
	_consecutive_fails = 0
	_consecutive_retry_levels = 0
	_retry_tracking_strategy = 0
	_current_level_retried = false
	_current_level_dirty = false
	_dda_tool_or_revive_used = false
	_dda_revive_used = false
	_is_daily_first_easy_level = false
	_dda_pending_demote = false
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_start_toast_pct.clear()
	_start_toast_iq_idx.clear()
	_save_data()


func _save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "current_level", _current_level)
	cfg.set_value("progress", "tutorial_done", _tutorial_done)
	cfg.set_value("progress", "current_strategy", _current_strategy)
	cfg.set_value("progress", "consecutive_clean_wins", _consecutive_clean_wins)
	cfg.set_value("progress", "last_level_clean_win", _last_level_clean_win)
	cfg.set_value("progress", "consecutive_fails", _consecutive_fails)
	cfg.set_value("progress", "consecutive_retry_levels", _consecutive_retry_levels)
	cfg.set_value("progress", "retry_tracking_strategy", _retry_tracking_strategy)
	cfg.set_value("progress", "bank_progress", _bank_progress)
	cfg.set_value("progress", "main_bank_progress", _main_bank_progress)
	cfg.set_value("progress", "lkmod_progress", _lkmod_progress)
	cfg.set_value("progress", "has_shown_rate_us", _has_shown_rate_us)
	cfg.set_value("progress", "has_used_revive_free", _has_used_revive_free)
	cfg.set_value("progress", "warn_life_shown", _warn_life_shown)
	cfg.set_value("progress", "life_plus_first_done", _life_plus_first_done)
	cfg.set_value("progress", "daily_index", _daily_index)
	cfg.set_value("progress", "daily_completed_date", _daily_completed_date)
	cfg.set_value("progress", "max_daily_date", _max_daily_date)
	cfg.set_value("progress", "daily_elapsed_sec", _daily_elapsed_sec)
	cfg.set_value("progress", "daily_beat_percent", _daily_beat_percent)
	cfg.set_value("progress", "daily_best_beat_percent", _daily_best_beat_percent)
	cfg.set_value("progress", "daily_started_date", _daily_started_date)
	cfg.set_value("progress", "daily_first_easy_date", _daily_first_easy_date)
	cfg.set_value("progress", "game_total_stats", _game_total_stats)

	cfg.set_value("progress", "main_game_total_stats", {})
	cfg.set_value("progress", "daily_game_total_stats", {})
	cfg.set_value("progress", "main_game_round_stats", {})
	cfg.set_value("progress", "daily_game_round_stats", {})
	cfg.set_value("progress", "main_game_id", "")
	cfg.set_value("progress", "daily_game_id", "")
	cfg.set_value("progress", "tool_locate", _tool_locate)
	cfg.set_value("progress", "tool_hint", _tool_hint)
	cfg.set_value("progress", "tool_undo", _tool_undo)
	cfg.set_value("progress", "last_splash_date", _last_splash_date)
	cfg.set_value("progress", "apply_locale", _apply_locale)
	cfg.set_value("progress", "is_first_session", _is_first_session)
	cfg.set_value("progress", "last_first_level_date", _last_first_level_date)
	cfg.set_value("progress", "music_on", _music_on)
	cfg.set_value("progress", "music_user_modified", _music_user_modified)
	cfg.set_value("progress", "sound_on", _sound_on)
	cfg.set_value("progress", "vibration_on", _vibration_on)
	cfg.set_value("progress", "people_on", _people_on)
	cfg.set_value("progress", "has_used_tool", _has_used_tool)
	cfg.set_value("progress", "prop_highlight_shown", _prop_highlight_shown)
	cfg.set_value("progress", "push_ask_count", _push_ask_count)
	cfg.set_value("progress", "retry_puzzle_level", _retry_puzzle_level)
	cfg.set_value("progress", "retry_puzzle_params", _retry_puzzle_params)
	cfg.set_value("progress", "has_shown_att_guide", _has_shown_att_guide)
	cfg.set_value("progress", "interstitial_unlocked", _interstitial_unlocked)
	cfg.set_value("progress", "banner_unlocked", _banner_unlocked)
	cfg.set_value("progress", "has_shown_draft_onboarding", _has_shown_draft_onboarding)
	cfg.set_value("progress", "auto_mark_tutorial_done", _auto_mark_tutorial_done)
	cfg.set_value("progress", "rule_info_bar_collapsed", _rule_info_bar_collapsed)
	cfg.set_value("progress", "grt_level_d90_reported", _grt_level_d90_reported)
	cfg.set_value("progress", "grt_reported_events", _grt_reported_events)
	cfg.set_value("progress", "first_open_time_ms", _first_open_time_ms)
	cfg.set_value("progress", "recent_puzzles", _recent_puzzles)
	cfg.set_value("progress", "endgame_snapshot", {})
	cfg.set_value("progress", "session_count", _session_count)
	cfg.set_value("progress", "today_session_count", _today_session_count)
	cfg.set_value("progress", "last_day_session_count", _last_day_session_count)
	cfg.set_value("progress", "active_days", _active_days)
	cfg.set_value("progress", "today_played_count", _today_played_count)
	cfg.set_value("progress", "today_active_sec", _today_active_sec)
	cfg.set_value("progress", "total_active_sec", _total_active_sec)
	cfg.set_value("progress", "today_date", _today_date)
	cfg.set_value("progress", "pending_rewards", _pending_rewards)
	cfg.set_value("progress", "in_flight_awards", _in_flight_awards)
	cfg.set_value("progress", "reward_history_ts", _reward_history_ts)
	cfg.set_value("progress", "restored_today_count", _restored_today_count)
	cfg.set_value("progress", "daily_auto_mark_enabled", _daily_auto_mark_enabled)
	cfg.set_value("progress", "daily_auto_mark_free_consumed", _daily_auto_mark_free_consumed)
	cfg.set_value("progress", "saved_game_auto_mark", _saved_game_auto_mark)
	cfg.set_value("progress", "last_win_beat_percent", _last_win_beat_percent)
	cfg.set_value("progress", "help_last_open_time", _help_last_open_time)
	cfg.set_value("progress", "install_version", _install_version)

	_player_store.save_config(cfg)


func _load_data() -> void:
	var cfg := _player_store.load_config()
	if cfg == null:
		_resolve_endgame_store()
		return
	_current_level = cfg.get_value("progress", "current_level", 1)
	_tutorial_done = cfg.get_value("progress", "tutorial_done", false)
	_current_strategy = cfg.get_value("progress", "current_strategy", 1)
	_consecutive_clean_wins = cfg.get_value("progress", "consecutive_clean_wins", 0)
	_last_level_clean_win = cfg.get_value("progress", "last_level_clean_win", false)
	_consecutive_fails = cfg.get_value("progress", "consecutive_fails", 0)
	_consecutive_retry_levels = cfg.get_value("progress", "consecutive_retry_levels", 0)
	_retry_tracking_strategy = cfg.get_value("progress", "retry_tracking_strategy", 0)
	_bank_progress = cfg.get_value("progress", "bank_progress", {})
	_main_bank_progress = cfg.get_value("progress", "main_bank_progress", {})
	_lkmod_progress = cfg.get_value("progress", "lkmod_progress", {})
	_has_shown_rate_us = cfg.get_value("progress", "has_shown_rate_us", false)
	_has_used_revive_free = cfg.get_value("progress", "has_used_revive_free", false)
	_warn_life_shown = cfg.get_value("progress", "warn_life_shown", false)
	_life_plus_first_done = cfg.get_value("progress", "life_plus_first_done", false)
	_daily_index = cfg.get_value("progress", "daily_index", 0)
	_daily_completed_date = cfg.get_value("progress", "daily_completed_date", "")
	_max_daily_date = cfg.get_value("progress", "max_daily_date", "")
	_daily_elapsed_sec = cfg.get_value("progress", "daily_elapsed_sec", 0)
	_daily_beat_percent = cfg.get_value("progress", "daily_beat_percent", 0.0)
	_daily_best_beat_percent = cfg.get_value("progress", "daily_best_beat_percent", 0.0)
	_daily_started_date = cfg.get_value("progress", "daily_started_date", "")
	_daily_first_easy_date = cfg.get_value("progress", "daily_first_easy_date", "")
	_game_total_stats = cfg.get_value("progress", "game_total_stats", {})
	_main_game_total_stats = cfg.get_value("progress", "main_game_total_stats", {})
	_daily_game_total_stats = cfg.get_value("progress", "daily_game_total_stats", {})
	_main_game_round_stats = cfg.get_value("progress", "main_game_round_stats", {})
	_daily_game_round_stats = cfg.get_value("progress", "daily_game_round_stats", {})
	_main_game_id = cfg.get_value("progress", "main_game_id", "")
	_daily_game_id = cfg.get_value("progress", "daily_game_id", "")
	_tool_locate = cfg.get_value("progress", "tool_locate", 5)
	_tool_hint = cfg.get_value("progress", "tool_hint", 5)
	_tool_undo = cfg.get_value("progress", "tool_undo", 3)
	print(
		(
			"[GameState] _load_data: tool_undo=%d tool_hint=%d tool_locate=%d"
			% [_tool_undo, _tool_hint, _tool_locate]
		)
	)
	_last_splash_date = cfg.get_value("progress", "last_splash_date", "")
	_apply_locale = cfg.get_value("progress", "apply_locale", "")
	_is_first_session = cfg.get_value("progress", "is_first_session", true)
	_last_first_level_date = cfg.get_value("progress", "last_first_level_date", "")
	_music_on = cfg.get_value("progress", "music_on", true)
	_music_user_modified = cfg.get_value("progress", "music_user_modified", false)
	_sound_on = cfg.get_value("progress", "sound_on", true)
	_vibration_on = cfg.get_value("progress", "vibration_on", true)
	_people_on = cfg.get_value("progress", "people_on", true)
	_has_used_tool = cfg.get_value("progress", "has_used_tool", false)
	_prop_highlight_shown = cfg.get_value("progress", "prop_highlight_shown", false)
	_push_ask_count = cfg.get_value("progress", "push_ask_count", 0)
	_retry_puzzle_level = cfg.get_value("progress", "retry_puzzle_level", 0)
	_retry_puzzle_params = cfg.get_value("progress", "retry_puzzle_params", {})
	_has_shown_att_guide = cfg.get_value("progress", "has_shown_att_guide", false)
	_interstitial_unlocked = cfg.get_value("progress", "interstitial_unlocked", false)
	_banner_unlocked = cfg.get_value("progress", "banner_unlocked", false)
	_has_shown_draft_onboarding = cfg.get_value("progress", "has_shown_draft_onboarding", false)
	_auto_mark_tutorial_done = cfg.get_value("progress", "auto_mark_tutorial_done", false)
	_rule_info_bar_collapsed = cfg.get_value("progress", "rule_info_bar_collapsed", false)
	_grt_level_d90_reported = cfg.get_value("progress", "grt_level_d90_reported", [])
	_grt_reported_events = cfg.get_value("progress", "grt_reported_events", [])
	_first_open_time_ms = cfg.get_value("progress", "first_open_time_ms", 0)
	_recent_puzzles = cfg.get_value("progress", "recent_puzzles", [])
	_endgame_snapshot = cfg.get_value("progress", "endgame_snapshot", {})
	_session_count = cfg.get_value("progress", "session_count", 0)
	_today_session_count = cfg.get_value("progress", "today_session_count", 0)
	_last_day_session_count = cfg.get_value("progress", "last_day_session_count", 0)
	_active_days = cfg.get_value("progress", "active_days", 0)
	_today_played_count = cfg.get_value("progress", "today_played_count", 0)
	_today_active_sec = cfg.get_value("progress", "today_active_sec", 0)
	_total_active_sec = cfg.get_value("progress", "total_active_sec", 0)
	_today_date = cfg.get_value("progress", "today_date", "")
	_pending_rewards = cfg.get_value("progress", "pending_rewards", [])
	_in_flight_awards = cfg.get_value("progress", "in_flight_awards", [])
	_reward_history_ts = cfg.get_value("progress", "reward_history_ts", [])
	_restored_today_count = cfg.get_value("progress", "restored_today_count", 0)
	_daily_auto_mark_enabled = cfg.get_value("progress", "daily_auto_mark_enabled", false)
	_daily_auto_mark_free_consumed = cfg.get_value(
		"progress", "daily_auto_mark_free_consumed", false
	)
	_saved_game_auto_mark = cfg.get_value("progress", "saved_game_auto_mark", -1)
	_last_win_beat_percent = cfg.get_value("progress", "last_win_beat_percent", -1.0)
	_help_last_open_time = cfg.get_value("progress", "help_last_open_time", 0)
	_install_version = cfg.get_value("progress", "install_version", "")
	_resolve_endgame_store()


func _migrate_legacy_save() -> void:
	if FileAccess.file_exists(SAVE_FLAG):
		return
	if not FileAccess.file_exists(SAVE_PATH_OLD):
		return
	var cfg := ConfigFile.new()
	if cfg.load_encrypted_pass(SAVE_PATH_OLD, SAVE_PASSWORD) != OK:
		return
	if _player_store.save_config(cfg):
		print("[GameState] 旧存档迁移完成")
	else:
		push_error("[GameState] 旧存档迁移失败")


func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%d-%02d-%02d" % [dt.year, dt.month, dt.day]


func reset_all() -> void:
	_current_level = 1
	_tutorial_done = false
	_has_shown_rate_us = false
	_has_used_revive_free = false
	_warn_life_shown = false
	_life_plus_first_done = false
	_current_strategy = 1
	_consecutive_clean_wins = 0
	_last_level_clean_win = false
	_consecutive_fails = 0
	_consecutive_retry_levels = 0
	_retry_tracking_strategy = 0
	_current_level_dirty = false
	_current_level_retried = false
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_bank_progress = {}
	_main_bank_progress = {}
	_lkmod_progress = {}
	_daily_index = 0
	_daily_completed_date = ""
	_max_daily_date = ""
	_daily_elapsed_sec = 0
	_daily_beat_percent = 0.0
	_daily_best_beat_percent = 0.0
	_daily_started_date = ""
	_daily_first_easy_date = ""
	_game_total_stats = {}
	_main_game_total_stats = {}
	_daily_game_total_stats = {}
	_main_game_round_stats = {}
	_daily_game_round_stats = {}
	_main_game_id = ""
	_daily_game_id = ""
	_tool_locate = 5
	_tool_hint = 5
	_tool_undo = 3
	_last_splash_date = ""
	_apply_locale = ""
	_is_first_session = true
	_first_session_runtime = true
	_last_first_level_date = ""
	_music_on = true
	_music_user_modified = false
	_sound_on = true
	_vibration_on = true
	VibrateManager.set_enabled(_vibration_on)
	_people_on = true
	_has_used_tool = false
	_prop_highlight_shown = false
	_push_ask_count = 0
	_has_shown_att_guide = false
	_interstitial_unlocked = false
	_banner_unlocked = false
	_has_shown_draft_onboarding = false
	_auto_mark_tutorial_done = false
	_grt_level_d90_reported = []
	_grt_reported_events = []
	_first_open_time_ms = 0
	_recent_puzzles = []
	_endgame_snapshot = {}
	_session_count = 0
	_today_session_count = 0
	_last_day_session_count = 0
	_active_days = 0
	_today_played_count = 0
	_today_active_sec = 0
	_total_active_sec = 0
	_today_date = ""
	_pending_rewards = []
	_in_flight_awards = []
	_reward_history_ts = []
	_restored_today_count = 0
	_daily_auto_mark_enabled = false
	_daily_auto_mark_free_consumed = false
	_saved_game_auto_mark = -1
	_last_win_beat_percent = -1.0
	_help_last_open_time = 0
	_install_version = ""
	_start_toast_pct = {}
	_start_toast_iq_idx = {}
	_save_data()
	_save_endgame()
	all_data_reset.emit()
