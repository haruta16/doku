## 1.22 主线结算的完整候选计算；保留原 DDA/回流/特殊关推进，副作用仅记录为提交后事件。
class_name MeowdokuProgressState
extends DokuSelectionState

const ActionFacts = preload("res://products/meowdoku/gameplay/application/meowdoku_action_facts.gd")

var _runtime: DokuSelectionRuntime
var _context: Dictionary = {}
var _stage_error: Dictionary = {}

var _nl12100_restore_strategy: int = 0
var _main_game_total_stats: Dictionary = {} # 普通模式跨局累计统计（如 hint_used_total）
var _daily_game_total_stats: Dictionary = {} # 每日挑战跨局累计统计
var _main_game_id: String = "" # 普通模式当前对局 ID（埋点串一局用）
var _daily_game_id: String = "" # 每日挑战当前对局 ID
var _push_ask_count: int = 0 # 推送授权询问次数（最多问 2 次）
var _push_guide_last_date: String = ""
var _push_guide_shown_count: int = 0
var _push_guide_popup_count: int = 0
var _has_shown_att_guide: bool = false # ATT 授权引导是否已展示
var _grt_level_d90_reported: Array = []
var _grt_reported_events: Array = [] # 已上报过的 GRT 事件名（关卡窗口 + 时长窗口）
var _first_open_time_ms: int = 0
var _reward_history_ts: Array = [] # 正常发奖的时间戳历史（只留 7 天，判断能否找回）
var _saved_ab_groups: Dictionary = {}
var _current_wrong_cat_num: int = 0
var _pre_cat_fx_played_lv: int = 0
var _onefish_spawn_suppressed: bool = false
var _color_challenge_skip_count: int = 0
var _color_challenge_defer_until: int = 0
var _current_level_retried: bool = false # 本局是否是重试局
var _dda_revive_used: bool = false # 本局是否用过复活
var _persisted_user_tags: Dictionary = {}
var _is_gamble_user: int = -1
var _early_l1_l20_bits: Array = []
var _recent_hard_invalid_bits: Array = []
var _start_toast_pct: Dictionary = {}
var _start_toast_iq_idx: Dictionary = {} # 关卡 → 开局提示选中的 IQ 文案下标
var _start_toast_variant_idx: Dictionary = {}
var _start_toast_variant_pct: Dictionary = {}
var _install_version: String = "" # 首次记录到的安装包版本号

const PROGRESS_FIELDS: Dictionary = {
  "_golden_fish_pending": {
    "section": "profile",
    "key": "golden_fish_pending",
    "type": "bool"
  },
  "_pre_cat_fail_count": {
    "section": "profile",
    "key": "pre_cat_fail_count",
    "type": "int"
  },
  "_onefish_consecutive_skips": {
    "section": "profile",
    "key": "onefish_consecutive_skips",
    "type": "int"
  },
  "_daily_game_total_stats": {
    "section": "endgame.stats",
    "key": "daily_total",
    "type": "Dictionary"
  },
  "_returnee_group": {
    "section": "profile",
    "key": "returnee_group",
    "type": "int"
  },
  "_pre_cat_fail_lv": {
    "section": "profile",
    "key": "pre_cat_fail_lv",
    "type": "int"
  },
  "_push_guide_popup_count": {
    "section": "profile",
    "key": "push_guide_popup_count",
    "type": "int"
  },
  "_consecutive_fails": {
    "section": "profile",
    "key": "consecutive_fails",
    "type": "int"
  },
  "_pre_cat_revived_this_level": {
    "section": "profile",
    "key": "pre_cat_revived_this_level",
    "type": "bool"
  },
  "_color_challenge_pending": {
    "section": "profile",
    "key": "cc_pending",
    "type": "bool"
  },
  "_first_open_time_ms": {
    "section": "profile",
    "key": "first_open_time_ms",
    "type": "int"
  },
  "_last_level_clean_win": {
    "section": "profile",
    "key": "last_level_clean_win",
    "type": "bool"
  },
  "_grt_reported_events": {
    "section": "profile",
    "key": "grt_reported_events",
    "type": "Array"
  },
  "_onefish_spawn_suppressed": {
    "section": "profile",
    "key": "onefish_spawn_suppressed",
    "type": "bool"
  },
  "_pre_cat_pending_struggle": {
    "section": "profile",
    "key": "pre_cat_pending_struggle",
    "type": "bool"
  },
  "_returnee_current_level": {
    "section": "profile",
    "key": "returnee_current_level",
    "type": "int"
  },
  "_pattern_mode_before_color_challenge": {
    "section": "profile",
    "key": "pattern_mode_before_cc",
    "type": "int"
  },
  "_elo_fish_consumed": {
    "section": "profile",
    "key": "elo_fish_consumed",
    "type": "int"
  },
  "_pre_cat_lock_pos": {
    "section": "profile",
    "key": "pre_cat_lock_pos",
    "type": "Vector2i"
  },
  "_pre_cat_fx_played_lv": {
    "section": "profile",
    "key": "pre_cat_fx_played_lv",
    "type": "int"
  },
  "_onefish_consecutive_wins": {
    "section": "profile",
    "key": "onefish_consecutive_wins",
    "type": "int"
  },
  "_push_ask_count": {
    "section": "profile",
    "key": "push_ask_count",
    "type": "int"
  },
  "_elo_active_rank": {
    "section": "profile",
    "key": "elo_active_rank",
    "type": "int"
  },
  "_consecutive_retry_levels": {
    "section": "profile",
    "key": "consecutive_retry_levels",
    "type": "int"
  },
  "_install_version": {
    "section": "profile",
    "key": "install_version",
    "type": "String"
  },
  "_early_l1_l20_bits": {
    "section": "profile",
    "key": "early_l1_l20_bits",
    "type": "Array"
  },
  "_daily_game_id": {
    "section": "endgame.stats",
    "key": "daily_id",
    "type": "String"
  },
  "_golden_fish_streak_count": {
    "section": "profile",
    "key": "golden_fish_streak_count",
    "type": "int"
  },
  "_nl12100_restore_strategy": {
    "section": "profile",
    "key": "nl12100_restore_strategy",
    "type": "int"
  },
  "_main_game_total_stats": {
    "section": "endgame.stats",
    "key": "main_total",
    "type": "Dictionary"
  },
  "_golden_fish_career_count": {
    "section": "profile",
    "key": "golden_fish_career_count",
    "type": "int"
  },
  "_is_gamble_user": {
    "section": "profile",
    "key": "is_gamble_user",
    "type": "int"
  },
  "_restored_today_count": {
    "section": "profile",
    "key": "restored_today_count",
    "type": "int"
  },
  "_pre_cat_pending_demote": {
    "section": "profile",
    "key": "pre_cat_pending_demote",
    "type": "bool"
  },
  "_current_strategy": {
    "section": "profile",
    "key": "current_strategy",
    "type": "int"
  },
  "_color_challenge_skip_count": {
    "section": "profile",
    "key": "cc_skip_count",
    "type": "int"
  },
  "_elo_v2_attempt": {
    "section": "profile",
    "key": "elo_v2_attempt",
    "type": "Dictionary"
  },
  "_recent_hard_invalid_bits": {
    "section": "profile",
    "key": "recent_hard_invalid_bits",
    "type": "Array"
  },
  "_insert_golden_fish_wrong_cat_num": {
    "section": "profile",
    "key": "insert_gf_wrong_cat_num",
    "type": "int"
  },
  "_retry_puzzle_level": {
    "section": "profile",
    "key": "retry_puzzle_level",
    "type": "int"
  },
  "_elo_v2_won_styles": {
    "section": "profile",
    "key": "elo_v2_won_styles",
    "type": "Array"
  },
  "_current_wrong_cat_num": {
    "section": "profile",
    "key": "current_wrong_cat_num",
    "type": "int"
  },
  "_reward_history_ts": {
    "section": "profile",
    "key": "reward_history_ts",
    "type": "Array"
  },
  "_consecutive_clean_wins": {
    "section": "profile",
    "key": "consecutive_clean_wins",
    "type": "int"
  },
  "_current_level": {
    "section": "profile",
    "key": "current_level",
    "type": "int"
  },
  "_main_game_id": {
    "section": "endgame.stats",
    "key": "main_id",
    "type": "String"
  },
  "_retry_puzzle_params": {
    "section": "profile",
    "key": "retry_puzzle_params",
    "type": "Dictionary"
  },
  "_pre_cat_lock_lv": {
    "section": "profile",
    "key": "pre_cat_lock_lv",
    "type": "int"
  },
  "_pattern_mode_on": {
    "section": "profile",
    "key": "pattern_mode_on",
    "type": "bool"
  },
  "_push_guide_shown_count": {
    "section": "profile",
    "key": "push_guide_shown_count",
    "type": "int"
  },
  "_persisted_user_tags": {
    "section": "profile",
    "key": "persisted_user_tags",
    "type": "Dictionary"
  },
  "_grt_level_d90_reported": {
    "section": "profile",
    "key": "grt_level_d90_reported",
    "type": "Array"
  },
  "_pre_cat_lock_pre_type": {
    "section": "profile",
    "key": "pre_cat_lock_pre_type",
    "type": "String"
  },
  "_golden_fish_pre_cat_session": {
    "section": "profile",
    "key": "golden_fish_pre_cat_session",
    "type": "Dictionary"
  },
  "_returnee_frozen_dda": {
    "section": "profile",
    "key": "returnee_frozen_dda",
    "type": "Dictionary"
  },
  "_push_guide_last_date": {
    "section": "profile",
    "key": "push_guide_last_date",
    "type": "String"
  },
  "_returnee_frozen_strategy": {
    "section": "profile",
    "key": "returnee_frozen_strategy",
    "type": "int"
  },
  "_retry_tracking_strategy": {
    "section": "profile",
    "key": "retry_tracking_strategy",
    "type": "int"
  },
  "_last_main_win_date": {
    "section": "profile",
    "key": "last_main_win_date",
    "type": "String"
  },
  "_pre_cat_pending_hard": {
    "section": "profile",
    "key": "pre_cat_pending_hard",
    "type": "bool"
  },
  "_color_challenge_since_gf": {
    "section": "profile",
    "key": "cc_since_gf",
    "type": "int"
  },
  "_today_date": {
    "section": "profile",
    "key": "today_date",
    "type": "String"
  },
  "_recent_win_counts_by_day": {
    "section": "profile",
    "key": "recent_win_counts_by_day",
    "type": "Dictionary"
  },
  "_has_shown_att_guide": {
    "section": "profile",
    "key": "has_shown_att_guide",
    "type": "bool"
  },
  "_returnee_from_endgame_save": {
    "section": "profile",
    "key": "returnee_from_endgame_save",
    "type": "bool"
  },
  "_elo_active_puzzle_rating": {
    "section": "profile",
    "key": "elo_active_puzzle_rating",
    "type": "float"
  },
  "_saved_ab_groups": {
    "section": "profile",
    "key": "saved_ab_groups",
    "type": "Dictionary"
  },
  "_color_challenge_defer_until": {
    "section": "profile",
    "key": "cc_defer_until",
    "type": "int"
  }
}
const PROGRESS_RUNTIME: Array[String] = ["_current_level_dirty", "_current_level_retried", "_dda_pending_demote", "_dda_revive_used", "_dda_tool_or_revive_used", "_demoted_this_level", "_is_daily_first_easy_level", "_start_toast_iq_idx", "_start_toast_pct", "_start_toast_variant_idx", "_start_toast_variant_pct"]

func _init(candidate: Dictionary = {}, context: Dictionary = {}) -> void:
	super(candidate, context)
	_context = context.duplicate(true)
	_runtime = DokuSelectionRuntime.new(candidate, context)
	_runtime.state = self
	_hydrate_progress(candidate)


func _hydrate_progress(candidate: Dictionary) -> void:
	_candidate = candidate.duplicate(true)
	for map: Dictionary in [FIELD_MAP, PROGRESS_FIELDS]:
		for name: String in map:
			var mapping: Dictionary = map[name]
			var section := _section(candidate, str(mapping.section))
			if section.has(mapping.key):
				set(name, _copy(section[mapping.key]))
	for name: String in RUNTIME_FIELDS + PROGRESS_RUNTIME:
		var key := name.trim_prefix("_")
		if candidate.get("round_runtime", {}).has(key):
			set(name, _copy(candidate.round_runtime[key]))


func export_candidate() -> Dictionary:
	var candidate := super.export_candidate()
	for name: String in PROGRESS_FIELDS:
		var mapping: Dictionary = PROGRESS_FIELDS[name]
		_section(candidate, str(mapping.section), true)[mapping.key] = _copy(get(name))
	for name: String in PROGRESS_RUNTIME:
		candidate.round_runtime[name.trim_prefix("_")] = _copy(get(name))
	return candidate


func _is_hard_level(level: int) -> bool:
	return LevelSelector.is_hard_level(level, _runtime.policy, _runtime)


func _is_super_hard_level(level: int) -> bool:
	return LevelSelector.is_super_hard_level(level, _runtime.policy, _runtime)


func _max_strategy_at(level: int) -> int:
	return LevelSelector.max_strategy_at(level, _runtime.policy, _runtime)


func _apply_strategy_settlement(ctx: LevelSettlementContext) -> void:
	var staged: Dictionary = LevelSelector.stage_won_settlement(export_candidate(), ctx, _runtime.policy, _context)
	if staged.get("ok", false):
		_hydrate_progress(staged.candidate)
		events.append_array(staged.get("effects", []))
	else:
		_stage_error = staged


func _stage_gamble_tag(level: int, rank: int, difficulty: int, invalid_total: int) -> void:
	var batch: Dictionary = GambleUserTag._decode_non_easy_batch(_recent_hard_invalid_bits)
	var state := {"value": _is_gamble_user, "gamble_update_level": str(_persisted_user_tags.get("gamble_update_level", "-1")), "early_l1_l20_bits": _early_l1_l20_bits, "recent_non_easy_invalid_bits": batch.invalid_bits, "recent_non_easy_levels": batch.levels}
	var result: Dictionary = GambleUserTag.resolve_state_after_main_level_won(state, level, rank, difficulty, invalid_total, _runtime.normal_level.is_super_hard_harder_active())
	_is_gamble_user = int(result.value)
	_early_l1_l20_bits = result.early_l1_l20_bits.duplicate()
	_recent_hard_invalid_bits = GambleUserTag._encode_non_easy_batch(result.recent_non_easy_invalid_bits, result.recent_non_easy_levels)
	_persisted_user_tags["gamble_update_level"] = str(result.gamble_update_level)
	if result.tag_changed:
		events.append({"kind": "user_tag", "key": "is_gamble_user", "value": str(result.value)})
	if result.judgment_completed:
		events.append({"kind": "user_tag", "key": "gamble_update_level", "value": str(result.gamble_update_level)})


func get_game_total_stat(game_type: String, key: String) -> int:
	return int(_get_total_stats_dict(game_type).get(key, 0))


## 取某对局类型持久化的 game_id（Tracker 冷启动时读）

func get_persisted_game_id(game_type: String) -> String:
	if game_type == "daily":
		return _daily_game_id
	return _main_game_id


## 写入 game_id 并立即写 endgame 槽

func _get_total_stats_dict(game_type: String) -> Dictionary:
	if game_type == "daily":
		return _daily_game_total_stats
	return _main_game_total_stats


# ---- 每日挑战记录 ----
## 取已解锁的最晚每日挑战日期

func _complete_elo_v2_attempt(level_num: int) -> void:
	if int(_elo_v2_attempt.get("level", 0)) != level_num:
		return
	if not _elo_v2_attempt_matches_retry(level_num):
		_elo_v2_attempt = {}
		return
	var puzzle_id: String = str(_elo_v2_attempt.get("puzzle_id", ""))
	for row: Dictionary in _elo_v2_won_styles:
		if int(row.get("level", 0)) == level_num and str(row.get("puzzle_id", "")) == puzzle_id:
			_elo_v2_attempt = {}
			return
	_elo_v2_won_styles.append(
		{
			"level": level_num,
			"puzzle_id": puzzle_id,
			"style_vector": _elo_v2_attempt.get("style_vector", {}).duplicate(true)
		}
	)
	while _elo_v2_won_styles.size() > 14:
		_elo_v2_won_styles.pop_front()
	_elo_v2_attempt = {}


## 当前关有锁定题目 ID 时要求尝试与它一致，无可比较锁题时允许通过。

func _elo_v2_attempt_matches_retry(level_num: int) -> bool:
	if _retry_puzzle_level != level_num:
		return true
	var locked_pid: String = str(_retry_puzzle_params.get("_puzzle_id", ""))

	if locked_pid.is_empty():
		return true
	return str(_elo_v2_attempt.get("puzzle_id", "")) == locked_pid


## 返回当前交付题目的 Elo 策略层级。

func _advance_color_challenge_mut(level: int, group: int) -> void:
	if not ColorChallengeGate.counting_enabled(_golden_fish_career_count, group):
		_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED
		_color_challenge_pending = false
		_color_challenge_defer_until = 0
		return

	if _color_challenge_defer_until > 0:
		if ColorChallengeGate.should_spawn_at_quiet_target(level, _color_challenge_defer_until):
			_color_challenge_pending = true

			_color_challenge_defer_until = 0

			_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED
		return

	if ColorChallengeGate.should_spawn_pending(_color_challenge_since_gf):
		_color_challenge_pending = true
	_color_challenge_since_gf = ColorChallengeGate.next_since_gf_count(_color_challenge_since_gf)

func _reset_color_challenge_quiet_streak_mut(reason: String) -> void:
	if _color_challenge_skip_count == 0 and _color_challenge_defer_until == 0:
		return
	print(
		"[ColorChallenge] 防打扰:%s → 连续跳过 %d→0,恢复常规节奏(锚回一命关)" % [reason, _color_challenge_skip_count]
	)
	_color_challenge_skip_count = 0
	_color_challenge_defer_until = 0

func _restore_pattern_mode_mut() -> bool:
	if _pattern_mode_before_color_challenge < 0:
		return false
	_pattern_mode_on = _pattern_mode_before_color_challenge == 1
	_pattern_mode_before_color_challenge = -1
	return true

func _advance_golden_fish_streak_mut(level: int) -> void:
	var enabled: bool = _runtime.config("golden_fish_func").is_enabled()

	var timing: GoldenFishTimingConfig = _runtime.config("golden_fish_timing")
	var min_level: int = timing.unlock_min_level()
	if not GoldenFishGate.insert_counting_enabled(level, enabled, min_level):
		_golden_fish_streak_count = 0
		_golden_fish_pending = false
		return

	var interval: int = GoldenFishGate.effective_interval(
		_onefish_consecutive_wins, timing.uses_sticky_boost()
	)

	var spawn: bool = GoldenFishGate.should_spawn_pending(
		_golden_fish_streak_count, enabled, interval
	)
	_golden_fish_streak_count = GoldenFishGate.next_streak_count(
		_golden_fish_streak_count, enabled, interval
	)
	if not spawn:
		return

	if GoldenFishGate.should_suppress_spawn(
		_onefish_consecutive_skips, _onefish_spawn_suppressed, timing.uses_skip_penalty()
	):
		_onefish_spawn_suppressed = true
		return

	_onefish_spawn_suppressed = false
	_golden_fish_pending = true

func on_golden_fish_settled(won: bool) -> void:
	if not won:
		_golden_fish_pre_cat_session = {}
	_golden_fish_pending = false
	_golden_fish_streak_count = 0
	if won:
		_onefish_consecutive_wins += 1
		_onefish_consecutive_skips = 0

	_insert_golden_fish_wrong_cat_num = 0

	_advance_golden_fish_career_mut()
	_save_data()

func on_color_challenge_settled() -> void:
	_color_challenge_pending = false
	_reset_color_challenge_quiet_streak_mut("通关")

	_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED

	_restore_pattern_mode_mut()
	_save_data()

func _set_pre_cat_pending_mut(pending: Dictionary) -> void:
	_pre_cat_pending_hard = bool(pending.get("hard", false))
	_pre_cat_pending_struggle = bool(pending.get("struggle", false))
	_pre_cat_pending_demote = bool(pending.get("demote", false))


## 为活跃金鱼会话记录已经复活并保存，重复调用不再写盘。

func clear_start_toast_variant_state(level: int = -1) -> void:
	if level < 0:
		_start_toast_variant_idx.clear()
		_start_toast_variant_pct.clear()
	else:
		_start_toast_variant_idx.erase(level)
		_start_toast_variant_pct.erase(level)

func on_level_won(
	level_num: int,
	kind: int = LevelKind.MAIN,
	this_session_rank: int = 0,
	this_session_diffi: int = 0,
	full_hp: bool = true,
	win_date: Variant = null
) -> void:
	var settled_game_id: String = get_persisted_game_id("normal")
	var returnee_level: bool = (
		_returnee_current_level == level_num
		and (
			(
				_returnee_from_endgame_save
				and (
					_runtime.config("normal_endgame_save").value()
					== NormalEndgameSaveConfig.VALUE_STALE_NEW_EASIER_TWO_DAYS
				)
			)
			or (
				not _returnee_from_endgame_save
				and _returnee_group == _runtime.config("normal_level").value()
			)
		)
	)
	_apply_level_won(level_num, kind, this_session_rank, this_session_diffi, full_hp, win_date)
	if returnee_level:
		_preserve_returnee_settlement()
		_returnee_current_level = 0
		_returnee_from_endgame_save = false
		_save_data()
	events.append({"kind": "main_level_won", "game_id": settled_game_id, "level_kind": kind, "win_date": win_date})

	events.append({"kind": "level_settled", "won": true})


## 按关卡类型推进进度、更新 DDA 与 Elo、清本局锁题统计并推进特殊关触发计数，最后写盘。

func _apply_level_won(
	level_num: int,
	kind: int = LevelKind.MAIN,
	this_session_rank: int = 0,
	this_session_diffi: int = 0,
	full_hp: bool = true,
	win_date: Variant = null
) -> void:
	var elo_v2_settlement: Dictionary = {}

	var dda_excluded: bool = LevelKind.is_excluded_from_main_dda(kind)

	if LevelKind.occupies_level_number(kind):
		var invalid_sign_total: int = get_game_total_stat("normal", "invalid_sign_total")
		_stage_gamble_tag(
			level_num, this_session_rank, this_session_diffi, invalid_sign_total
		)

	if LevelKind.occupies_level_number(kind):
		var next_level: int = level_num + 1
		if next_level > _current_level:
			_current_level = next_level

	var _pre_cat_strat_before: int = _current_strategy

	_pre_cat_pending_struggle = (
		(not dda_excluded)
		and (
			(_pre_cat_fail_lv == level_num and _pre_cat_fail_count >= 2)
			or _pre_cat_revived_this_level
		)
	)
	print(
		(
			"[pre_cat] on_level_won lv=%d fail_count=%d revived=%s -> next struggle=%s"
			% [
				level_num,
				_pre_cat_fail_count,
				str(_pre_cat_revived_this_level),
				str(_pre_cat_pending_struggle)
			]
		)
	)

	if LevelKind.occupies_level_number(kind):
		_golden_fish_pre_cat_session = {}
		_pre_cat_fail_count = 0
		_pre_cat_fail_lv = 0
		_pre_cat_revived_this_level = false

		_pre_cat_lock_lv = 0
		_pre_cat_lock_pre_type = "0"
		_pre_cat_lock_pos = Vector2i(-1, -1)

		_pre_cat_fx_played_lv = 0

	_pre_cat_pending_hard = (
		(not dda_excluded)
		and (_is_hard_level(level_num) or _is_super_hard_as_hard(level_num))
	)

	if (
		not dda_excluded
		and not _is_dda_excluded_super_hard(level_num)
		and not _is_dda_excluded_g4_pressure(level_num)
		and level_num >= _strategy_engagement_min_level()
	):
		var max_strategy: int = _max_strategy_at(level_num)
		var win_threshold: int = 1 if level_num >= 51 else 2

		if (
			level_num >= 15
			and level_num <= 50
			and (
				_runtime.config("normal_level").value()
				in [
					NormalLevelConfig.VALUE_LOWER_PROMOTE_THRESHOLD_15_50,
					NormalLevelConfig.VALUE_IOS_LOWER_PROMOTE_THRESHOLD_15_50,
				]
			)
		):
			win_threshold = 1
		var min_strategy: int = 2 if level_num >= 101 else 1

		var clean_win: bool = not _current_level_dirty or _tool_no_demote_counts_as_clean_win()

		var is_g5_fullhp_gate: bool = (
			_runtime.config("normal_level").value()
			in [
				NormalLevelConfig.VALUE_FULLHP_RANK,
				NormalLevelConfig.VALUE_IOS_FULLHP_RANK,
			]
		)
		if clean_win and (not is_g5_fullhp_gate or full_hp):
			_consecutive_clean_wins += 1
			if _consecutive_clean_wins >= win_threshold and _current_strategy < max_strategy:
				_current_strategy += 1
				_consecutive_clean_wins = 0
		elif not clean_win:
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

		elo_v2_settlement = _dispatch_normal_level_settlement(
			level_num, min_strategy, _pre_cat_strat_before
		)
	if kind == LevelKind.MAIN:
		_complete_elo_v2_attempt(level_num)

	if LevelKind.occupies_level_number(kind):
		_current_wrong_cat_num = 0

	_last_level_clean_win = not _current_level_dirty
	_current_level_retried = false
	_current_level_dirty = false
	_dda_tool_or_revive_used = false
	_dda_revive_used = false

	_elo_fish_consumed = 0
	_is_daily_first_easy_level = false
	_demoted_this_level = false
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_start_toast_pct.erase(level_num)
	_start_toast_iq_idx.erase(level_num)
	clear_start_toast_variant_state(level_num)

	_inc_today_win_count()
	var main_win_date: String = _date_for_main_win(win_date)
	if not main_win_date.is_empty():
		_last_main_win_date = main_win_date

	events.append({"kind": "track_level_pass", "level": level_num})

	events.append({"kind": "track_level_window", "level": level_num})

	if _current_strategy < _pre_cat_strat_before:
		_pre_cat_pending_demote = true

	if not dda_excluded:
		_advance_golden_fish_streak_mut(level_num)

		_advance_color_challenge_mut(level_num, _runtime.config("color_challenge_func").group_value())

	if LevelKind.is_insert_golden_fish(kind):
		_settle_golden_fish_pre_cat_mut(level_num)
	_save_data()
	if not elo_v2_settlement.is_empty():
		events.append({"kind": "elo_rating_committed", "rank": int(elo_v2_settlement["rank"]), "rating": float(elo_v2_settlement["rating"])})

func _settle_golden_fish_pre_cat_mut(level_num: int) -> void:
	if int(_golden_fish_pre_cat_session.get("level", 0)) != level_num:
		_set_pre_cat_pending_mut({})
		return
	_golden_fish_pre_cat_session["won"] = true
	_set_pre_cat_pending_mut(
		get_golden_fish_pre_cat_followup(
			level_num,
			_runtime.config("golden_fish_precat").includes_golden_fish(),
			_runtime.config("golden_fish_precat").isolates_golden_fish()
		)
	)

func _strategy_engagement_min_level() -> int:
	return 6

func _tool_no_demote_counts_as_clean_win() -> bool:
	if (
		_is_daily_first_easy_level
		or not _dda_tool_or_revive_used
		or _dda_revive_used
		or _current_level_retried
	):
		return false
	match _runtime.config("normal_level").value():
		NormalLevelConfig.VALUE_TOOL_NO_DEMOTE, NormalLevelConfig.VALUE_IOS_TOOL_NO_DEMOTE:
			return true
		NormalLevelConfig.VALUE_CHANNEL_ASSIST_TOOL_NO_DEMOTE, NormalLevelConfig.VALUE_IOS_CHANNEL_ASSIST_TOOL_NO_DEMOTE, NormalLevelConfig.VALUE_ASSIST_TOOL_WIN_PROMOTE:
			return (1 if _runtime.assist_user else 0) == 1
		_:
			return false

func _is_super_hard_as_hard(level_num: int) -> bool:
	return (
		_runtime.config("normal_level").is_super_hard_harder_active()
		and _is_super_hard_level(level_num)
	)

func _is_dda_excluded_super_hard(level_num: int) -> bool:
	return (
		_runtime.config("normal_level").is_super_hard_harder_active()
		and _is_super_hard_level(level_num)
	)

func _is_dda_excluded_g4_pressure(level_num: int) -> bool:
	return is_g4_pressure_level(level_num)


## 累计适用的预放猫失败状态，执行失败结算并保留回流保护，最后发出失败结算信号。

func on_level_failed(level_num: int, kind: int = LevelKind.MAIN) -> void:
	if LevelKind.is_insert_golden_fish(kind) and _is_golden_fish_pre_cat_active(level_num):
		_golden_fish_pre_cat_session["fail_count"] = (
			int(_golden_fish_pre_cat_session.get("fail_count", 0)) + 1
		)
	var returnee_level: bool = (
		_returnee_current_level == level_num
		and (
			(
				_returnee_from_endgame_save
				and (
					_runtime.config("normal_endgame_save").value()
					== NormalEndgameSaveConfig.VALUE_STALE_NEW_EASIER_TWO_DAYS
				)
			)
			or (
				not _returnee_from_endgame_save
				and _returnee_group == _runtime.config("normal_level").value()
			)
		)
	)
	_apply_level_failed(level_num, kind)
	if returnee_level:
		_preserve_returnee_settlement()
		_save_data()
	events.append({"kind": "level_settled", "won": false})


## 12002 回流组结算后恢复冻结的策略与 DDA 计数，避免保护期影响原难度轨迹。

func _preserve_returnee_settlement() -> void:
	if _returnee_group != 12002:
		return
	_current_strategy = _returnee_frozen_strategy
	_consecutive_clean_wins = int(_returnee_frozen_dda.get("clean", 0))
	_consecutive_fails = int(_returnee_frozen_dda.get("fails", 0))
	_consecutive_retry_levels = int(_returnee_frozen_dda.get("retry_levels", 0))
	_retry_tracking_strategy = int(_returnee_frozen_dda.get("retry_strategy", 0))
	_dda_pending_demote = bool(_returnee_frozen_dda.get("pending_demote", false))
	_demoted_this_level = bool(_returnee_frozen_dda.get("demoted", false))


## 根据玩法隔离规则标记重试和非干净状态，累计适用的预放猫与 DDA 失败次数后写盘。

func _apply_level_failed(level_num: int, kind: int = LevelKind.MAIN) -> void:
	var is_golden: bool = LevelKind.is_golden_fish(kind)

	var dda_excluded: bool = LevelKind.is_excluded_from_main_dda(kind)

	var isolate_main_state: bool = (
		(is_golden and _runtime.config("normal_level").is_onefish_state_fix())
		or LevelKind.is_color_challenge(kind)
	)
	if not isolate_main_state:
		_current_level_retried = true

		_last_level_clean_win = false

	_current_level_dirty = true

	if not dda_excluded:
		if level_num != _pre_cat_fail_lv:
			_pre_cat_fail_lv = level_num
			_pre_cat_fail_count = 0
			_pre_cat_revived_this_level = false
		_pre_cat_fail_count += 1
		print("[pre_cat] on_level_failed lv=%d -> fail_count=%d" % [level_num, _pre_cat_fail_count])

	if (
		not dda_excluded
		and not _is_dda_excluded_super_hard(level_num)
		and not _is_dda_excluded_g4_pressure(level_num)
	):
		if level_num >= _strategy_engagement_min_level():
			_consecutive_clean_wins = 0

			_consecutive_fails += 1
	_save_data()

func _dda_apply_demote_on_won(level_num: int, min_strategy: int) -> void:
	if _is_daily_first_easy_level:
		return

	var triggered: bool = _current_level_retried or _dda_revive_used

	var next_level: int = level_num + 1
	var next_is_hard: bool = _is_hard_level(next_level)

	var next_is_skip: bool = (
		next_is_hard
		or LevelData.is_special_level(next_level, _runtime)
		or _is_dda_excluded_super_hard(next_level)
		or _is_dda_excluded_g4_pressure(next_level)
	)

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


## 把本局表现与 Elo 数据封装为结算上下文交 LevelSelector，再接回策略、降档标记与评分结果。

func _dispatch_normal_level_settlement(
	level_num: int, min_strategy: int, strategy_before_all: int
) -> Dictionary:
	var ctx := LevelSettlementContext.new()

	ctx.level_num = level_num
	ctx.min_strategy = min_strategy
	ctx.strategy_before_all = strategy_before_all
	ctx.retried = _current_level_retried
	ctx.revive_used = _dda_revive_used
	ctx.tool_or_revive_used = _dda_tool_or_revive_used
	ctx.is_daily_first_easy_level = _is_daily_first_easy_level
	if _elo_active_rank in [3, 4, 5]:
		ctx.elo_original_delivery = {
			"rank": _elo_active_rank,
			"puzzle_rating": _elo_active_puzzle_rating,
			"player_rating": get_elo_rating(_elo_active_rank),
			"games_before": get_elo_games(_elo_active_rank),
			"fish_consumed": _elo_fish_consumed,
			"band": get_elo_band(_elo_active_rank),
			"is_new_player": is_elo_group2_new_player(),
		}
	if (
		int(_elo_v2_attempt.get("level", 0)) == level_num
		and _elo_v2_attempt_matches_retry(level_num)
	):
		ctx.elo_v2_attempt = _elo_v2_attempt.duplicate(true)
		var elo_rank: int = int(ctx.elo_v2_attempt.get("rank", 0))
		ctx.elo_v2_attempt["player_rating"] = get_elo_rating(elo_rank)
		ctx.elo_v2_attempt["games_before"] = get_elo_games(elo_rank)
		ctx.elo_v2_attempt["is_new_player"] = is_elo_group2_new_player()
		ctx.elo_v2_attempt["band"] = get_elo_band(elo_rank)
	elif int(_elo_v2_attempt.get("level", 0)) == level_num:
		print(
			(
				"[Level.ELO] SKIP lv=%d reason=stale_puzzle attempt_pid=%s delivered_pid=%s"
				% [
					level_num,
					str(_elo_v2_attempt.get("puzzle_id", "")),
					str(_retry_puzzle_params.get("_puzzle_id", ""))
				]
			)
		)

	ctx.strategy = _current_strategy
	ctx.demoted_this_level = _demoted_this_level
	ctx.pending_restore_strategy = _nl12100_restore_strategy

	_apply_strategy_settlement(ctx)

	_current_strategy = ctx.strategy
	_demoted_this_level = ctx.demoted_this_level
	_nl12100_restore_strategy = ctx.pending_restore_strategy
	var settlement: Dictionary = ctx.elo_v2_settlement
	if settlement.is_empty():
		return {}
	if not _apply_elo_rating_state(
		int(settlement.get("rank", 0)),
		float(settlement.get("rating", 0.0)),
		int(settlement.get("band", 0))
	):
		return {}
	return settlement


## 调试跳关时限制策略范围、清重试和预放猫等临时状态，再保存目标关号。

func _date_for_main_win(win_date: Variant) -> String:
	return _today_str() if win_date == null else str(win_date)


## 优先使用已存胜利日期，旧档缺字段时用今日通关计数补判。

func _inc_today_win_count() -> void:
	var today: String = _today_str()
	_recent_win_counts_by_day[today] = _recent_win_counts_by_day.get(today, 0) + 1


const _DELETE_PRESERVE_FIELDS: Array[String] = [
	"_has_shown_att_guide",
	"_push_ask_count",
	"_push_guide_last_date",
	"_push_guide_shown_count",
	"_push_guide_popup_count",
	"_grt_reported_events",
	"_grt_level_d90_reported",
	"_saved_ab_groups",
	"_install_version",
	"_first_open_time_ms",
	"_restored_today_count",
	"_reward_history_ts",
	"_today_date",
]


## 删除账号时先保留 SDK、权限和风控字段，再重置业务数据、恢复保留项并保存。


## request 已先完成业务身份校验；这里只推进候选，绝不发布真实单例或外部副作用。
static func stage(candidate: Dictionary, level: int, outcome: String, context: Dictionary) -> Dictionary:
	var selection: Dictionary = context.get("selection_context", {}).duplicate(true)
	if selection.is_empty() or selection.get("policy", {}).is_empty():
		return OperationResult.failure("missing_selection_policy", "1.22 结算需要冻结的选题策略")
	var progress := MeowdokuProgressState.new(candidate, selection)
	var kind: int = int(context.get("kind", LevelKind.MAIN))
	if outcome == "win":
		progress.on_level_won(level, kind, int(context.get("rank", 0)), int(context.get("diffi", 0)), bool(context.get("full_hp", true)), context.get("win_date", null))
		if LevelKind.is_golden_fish(kind):
			progress.on_golden_fish_settled(true)
		elif LevelKind.is_color_challenge(kind):
			progress.on_color_challenge_settled()
	else:
		progress.on_level_failed(level, kind)
	if not progress._stage_error.is_empty():
		var error: Dictionary = progress._stage_error.duplicate(true)
		progress._runtime.state = null
		return error
	var after: Dictionary = progress.export_candidate()
	var effects: Array = progress.events.duplicate(true)
	progress._runtime.state = null
	candidate.clear()
	candidate.merge(after, true)
	return OperationResult.success({"effects": effects})

## 保留业务入口；动作事实独立于完整选题/结算策略，可在无 Autoload 工程中执行。
static func stage_activity(candidate: Dictionary, kind: String, mode: String = "", policy: Dictionary = {}) -> Dictionary:
	return ActionFacts.stage_activity(candidate, kind, mode, policy)


static func stage_action_facts(candidate: Dictionary, mode: String, receipt: Dictionary, snapshot: Dictionary) -> Dictionary:
	return ActionFacts.stage_action_facts(candidate, mode, receipt, snapshot)

func on_golden_fish_skipped(level: int) -> void:
	if _is_golden_fish_pre_cat_active(level):
		_golden_fish_pre_cat_session["skipped"] = true
		_set_pre_cat_pending_mut(
			get_golden_fish_pre_cat_followup(
				level,
				_runtime.config("golden_fish_precat").includes_golden_fish(),
				_runtime.config("golden_fish_precat").isolates_golden_fish()
			)
		)
	elif not has_golden_fish_pre_cat_followup(level):
		_golden_fish_pre_cat_session = {
			"level": level,
			"source": get_pre_cat_pending(),
			"entered": false,
			"skipped": true,
			"won": false
		}
	clear_returnee_current_level(level)
	_golden_fish_pending = false
	_golden_fish_streak_count = 0

	_advance_golden_fish_career_mut()

	_onefish_consecutive_skips += 1
	_onefish_consecutive_wins = 0

	if not get_retry_puzzle(level).is_empty():
		clear_retry_puzzle()
	else:
		_save_data()
	_candidate.endgame["snapshot"] = {}


func on_color_challenge_skipped(level: int, group: int, entered_level: bool) -> void:
	_color_challenge_pending = false
	if entered_level:
		_reset_color_challenge_quiet_streak_mut("失败后跳过(算玩过)")
	else:
		_color_challenge_skip_count += 1
		if ColorChallengeGate.is_quiet_active(_color_challenge_skip_count, group):
			_color_challenge_defer_until = ColorChallengeGate.quiet_next_level(level)
			print(
				(
					"[ColorChallenge] 防打扰:连续跳过 %d 次 → 下次出现在 lv%d(再玩 %d 关)"
					% [
						_color_challenge_skip_count,
						_color_challenge_defer_until,
						ColorChallengeGate.QUIET_INTERVAL_LEVELS
					]
				)
			)

	_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED
	_restore_pattern_mode_mut()

	if not get_retry_puzzle(level).is_empty():
		clear_retry_puzzle()
	else:
		_save_data()
	_candidate.endgame["snapshot"] = {}


static func stage_skip(candidate: Dictionary, kind: String, level: int, group: int, entered: bool, context: Dictionary) -> Dictionary:
	var state: MeowdokuProgressState = MeowdokuProgressState.new(candidate, context)
	if kind == "golden":
		state.on_golden_fish_skipped(level)
	else:
		state.on_color_challenge_skipped(level, group, entered)
	var after: Dictionary = state.export_candidate()
	state._runtime.state = null
	candidate.clear()
	candidate.merge(after, true)
	return {"ok": true}

func clear_returnee_current_level(level_num: int) -> void:
	if _returnee_current_level != level_num:
		return
	_returnee_current_level = 0
	_returnee_from_endgame_save = false
