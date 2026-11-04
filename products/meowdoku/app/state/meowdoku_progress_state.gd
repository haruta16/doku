## 1.22 主线结算候选：沿用 DokuSelectionState 的字段投影，计算 DDA、Elo、回流与特殊关进度。
## 本类不写盘、不通知真实单例；父类 _save_data/_save_endgame 在这里是空操作。
## 业务效果先放入 events，由外层成功提交后发布；内部仍会输出预放猫、Elo 等调试日志。
class_name MeowdokuProgressState
extends DokuSelectionState

const ActionFacts = preload("res://products/meowdoku/gameplay/application/meowdoku_action_facts.gd")

var _runtime: DokuSelectionRuntime # 本次冻结的策略/内容上下文，state 指回此候选对象；结束时要拆开循环引用。
var _context: Dictionary = {} # 构造时复制的选题环境，供策略结算复用；不在结算中重新捕获实时 AB。
var _stage_error: Dictionary = {} # 策略计算失败的结果；stage 检查它后中止，不把失败候选交给外层提交。

var _nl12100_restore_strategy: int = 0 # 对应策略组待恢复的难度档，随 profile 投影保存。
var _main_game_total_stats: Dictionary = {} # 普通模式跨局累计统计（如 hint_used_total）
var _daily_game_total_stats: Dictionary = {} # 每日挑战跨局累计统计
var _main_game_id: String = "" # 普通模式当前对局 ID（埋点串一局用）
var _daily_game_id: String = "" # 每日挑战当前对局 ID
var _push_ask_count: int = 0 # 推送授权询问次数（最多问 2 次）
var _push_guide_last_date: String = "" # 已记录的推送引导日期；随候选保留，本类不打开引导页。
var _push_guide_shown_count: int = 0 # 推送引导累计展示次数的候选值。
var _push_guide_popup_count: int = 0 # 推送引导弹窗次数的候选值。
var _has_shown_att_guide: bool = false # ATT 授权引导是否已展示
var _grt_level_d90_reported: Array = [] # 已记录的 D90 关卡上报去重项；本类不直接上报。
var _grt_reported_events: Array = [] # 已上报过的 GRT 事件名（关卡窗口 + 时长窗口）
var _first_open_time_ms: int = 0 # 首次打开的时间戳，单位毫秒；不是本局经过时间。
var _reward_history_ts: Array = [] # 正常发奖的时间戳历史（只留 7 天，判断能否找回）
var _saved_ab_groups: Dictionary = {} # 持久分组记录副本；当前结算规则以 _runtime 中冻结的策略为准。
var _current_wrong_cat_num: int = 0 # 当前主线关卡累计错猫次数，通关占号关时清零。
var _pre_cat_fx_played_lv: int = 0 # 已经播放过预放猫表现的关号，用于重进后的表现去重。
var _onefish_spawn_suppressed: bool = false # 一命关因连续跳过暂时抑制插入的状态。
var _color_challenge_skip_count: int = 0 # 连续未游玩就跳过颜色挑战的次数。
var _color_challenge_defer_until: int = 0 # 颜色挑战延后触发的目标关号；0 表示不处于延后期。
var _current_level_retried: bool = false # 本局是否是重试局
var _dda_revive_used: bool = false # 本局是否用过复活
var _persisted_user_tags: Dictionary = {} # 用户标签的候选记录；外部标签服务更新另通过 events 发出。
var _is_gamble_user: int = -1 # 行为判断结果：-1 尚未判断，后续由 GambleUserTag 规则计算。
var _early_l1_l20_bits: Array = [] # 早期关卡行为位记录，作为用户标签判断的输入。
var _recent_hard_invalid_bits: Array = [] # 近期非简单关的错误记录编码，包含关号与判断位。
var _start_toast_pct: Dictionary = {} # 关号 → 开局百分比文案缓存；对应关结算后清理。
var _start_toast_iq_idx: Dictionary = {} # 关卡 → 开局提示选中的 IQ 文案下标
var _start_toast_variant_idx: Dictionary = {} # 关号 → 开局变体文案下标，避免同关重入反复随机。
var _start_toast_variant_pct: Dictionary = {} # 关号 → 开局变体百分比值，与文案下标一起清理。
var _install_version: String = "" # 首次记录到的安装包版本号

# 结算额外字段的投影表：成员名 → 核心分区/键/类型；与父类 FIELD_MAP 共同读取和导出。
# section 的 endgame.stats 是嵌套路径，不是字面含点的一个键；_section 负责逐层定位。
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
# 本类额外持有的局内字段，导出到 round_runtime；不混入永久 profile，也不能遗忘其事务归属。
const PROGRESS_RUNTIME: Array[String] = ["_current_level_dirty", "_current_level_retried", "_dda_pending_demote", "_dda_revive_used", "_dda_tool_or_revive_used", "_demoted_this_level", "_is_daily_first_easy_level", "_start_toast_iq_idx", "_start_toast_pct", "_start_toast_variant_idx", "_start_toast_variant_pct"]

## 复制候选和冻结环境，建立策略运行时并把它的 state 绑定到本对象；不访问存档。
func _init(candidate: Dictionary = {}, context: Dictionary = {}) -> void:
	super(candidate, context)
	_context = context.duplicate(true)
	_runtime = DokuSelectionRuntime.new(candidate, context)
	# 运行时和状态对象互相引用；stage/stage_skip 在导出或失败后主动断开，避免 RefCounted 留住整个候选。
	_runtime.state = self
	_hydrate_progress(candidate)


## 把核心分区重新投影到父类/本类字段，恢复策略结算返回的候选；每个可变值复制后再持有。
func _hydrate_progress(candidate: Dictionary) -> void:
	_candidate = candidate.duplicate(true)
	# 两个表可能覆盖相同业务字段，统一从同一候选读取，防止父类选题状态与子类结算状态分叉。
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


## 先导出父类选题字段，再写回本类进度和局内字段；返回独立候选，不提交也不发布事件。
func export_candidate() -> Dictionary:
	var candidate := super.export_candidate()
	for name: String in PROGRESS_FIELDS:
		var mapping: Dictionary = PROGRESS_FIELDS[name]
		_section(candidate, str(mapping.section), true)[mapping.key] = _copy(get(name))
	for name: String in PROGRESS_RUNTIME:
		candidate.round_runtime[name.trim_prefix("_")] = _copy(get(name))
	return candidate


## 按本局冻结的策略与特殊表判断困难关，返回 bool；不读取最新全局实验分组。
func _is_hard_level(level: int) -> bool:
	return LevelSelector.is_hard_level(level, _runtime.policy, _runtime)


## 按同一冻结运行时判断超难关；供 DDA 排除与预放猫资格共同使用。
func _is_super_hard_level(level: int) -> bool:
	return LevelSelector.is_super_hard_level(level, _runtime.policy, _runtime)


## 求该关在冻结规则下允许的最高难度档；只查询，不改变当前策略。
func _max_strategy_at(level: int) -> int:
	return LevelSelector.max_strategy_at(level, _runtime.policy, _runtime)


## 让具体选题策略在候选上计算胜利结算；成功接回状态/效果，失败保存错误供最外层中止。
func _apply_strategy_settlement(ctx: LevelSettlementContext) -> void:
	var staged: Dictionary = LevelSelector.stage_won_settlement(export_candidate(), ctx, _runtime.policy, _context)
	# 策略可以同时更新字段与上下文；只接纳成功返回的完整候选，错误交 _stage_error 传回。
	if staged.get("ok", false):
		_hydrate_progress(staged.candidate)
		events.append_array(staged.get("effects", []))
	else:
		_stage_error = staged


## 根据占号关的难度和错误事实更新行为标签候选；标签变更只排队为提交后效果。
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


## 读取候选对应模式的一项累计统计并转为整数；缺键按 0 返回，不补写字段。
func get_game_total_stat(game_type: String, key: String) -> int:
	return int(_get_total_stats_dict(game_type).get(key, 0))


## 取候选里的对局 ID；daily 使用每日槽，其余沿用普通模式槽，不查询或更新真实 Tracker。

func get_persisted_game_id(game_type: String) -> String:
	if game_type == "daily":
		return _daily_game_id
	return _main_game_id


## 选择候选中的跨局统计字典；返回本对象持有的字典引用，只供内部读取/暂存。

func _get_total_stats_dict(game_type: String) -> Dictionary:
	if game_type == "daily":
		return _daily_game_total_stats
	return _main_game_total_stats


# ---- Elo 尝试身份与已胜题型历史 ----
## 将本次匹配题目的 Elo 尝试转入最近已胜题型记录；按关号+题目 ID 去重，仅保留最近 14 项。

func _complete_elo_v2_attempt(level_num: int) -> void:
	if int(_elo_v2_attempt.get("level", 0)) != level_num:
		return
	# 同一关号可能已经换过题；只按关号结算会把旧题尝试的评分事实记到新题上。
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
	# 题型历史只服务近期去重/调整，不让它随全部通关记录无限增长。
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


## 根据金鱼生涯和颜色挑战组推进插入计数；延后期只检查目标关，不同时推进常规计数。

func _advance_color_challenge_mut(level: int, group: int) -> void:
	if not ColorChallengeGate.counting_enabled(_golden_fish_career_count, group):
		_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED
		_color_challenge_pending = false
		_color_challenge_defer_until = 0
		return

	# 延后状态有自己独立的目标关号，达到后只激活 pending，实际交付由后续选题完成。
	if _color_challenge_defer_until > 0:
		if ColorChallengeGate.should_spawn_at_quiet_target(level, _color_challenge_defer_until):
			_color_challenge_pending = true

			_color_challenge_defer_until = 0

			_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED
		return

	if ColorChallengeGate.should_spawn_pending(_color_challenge_since_gf):
		_color_challenge_pending = true
	_color_challenge_since_gf = ColorChallengeGate.next_since_gf_count(_color_challenge_since_gf)

## 清除颜色挑战连续跳过与延后目标；reason 只用于调试输出，不改外部活动状态。
func _reset_color_challenge_quiet_streak_mut(reason: String) -> void:
	if _color_challenge_skip_count == 0 and _color_challenge_defer_until == 0:
		return
	print(
		"[ColorChallenge] 防打扰:%s → 连续跳过 %d→0,恢复常规节奏(锚回一命关)" % [reason, _color_challenge_skip_count]
	)
	_color_challenge_skip_count = 0
	_color_challenge_defer_until = 0

## 恢复进入颜色挑战前保存的图案模式；返回是否实际存在待恢复值，并消费该备份。
func _restore_pattern_mode_mut() -> bool:
	if _pattern_mode_before_color_challenge < 0:
		return false
	_pattern_mode_on = _pattern_mode_before_color_challenge == 1
	_pattern_mode_before_color_challenge = -1
	return true

## 按冻结开关、解锁关号和连续胜负推进一命关节奏；只设置下次插入资格，不实际选题。
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

	# 连续跳过惩罚可以吞掉这次触发；这里保留抑制状态，不能直接当作已交付一局。
	if GoldenFishGate.should_suppress_spawn(
		_onefish_consecutive_skips, _onefish_spawn_suppressed, timing.uses_skip_penalty()
	):
		_onefish_spawn_suppressed = true
		return

	_onefish_spawn_suppressed = false
	_golden_fish_pending = true

## 结束一次金鱼关候选：清待进入资格与错猫数，胜利时更新连胜，最后推进金鱼生涯计数。
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

## 结束颜色挑战候选，清 pending/防打扰计数并恢复原图案模式；不推进主线关号。
func on_color_challenge_settled() -> void:
	_color_challenge_pending = false
	_reset_color_challenge_quiet_streak_mut("通关")

	_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED

	_restore_pattern_mode_mut()
	_save_data()

## 从 pending 字典同时覆盖困难/挣扎/降档三类预放猫资格；缺失项按 false 清除。
func _set_pre_cat_pending_mut(pending: Dictionary) -> void:
	_pre_cat_pending_hard = bool(pending.get("hard", false))
	_pre_cat_pending_struggle = bool(pending.get("struggle", false))
	_pre_cat_pending_demote = bool(pending.get("demote", false))


## 清除开局变体文案缓存：level < 0 清全部，否则只清该关；只改候选字段。

func clear_start_toast_variant_state(level: int = -1) -> void:
	if level < 0:
		_start_toast_variant_idx.clear()
		_start_toast_variant_pct.clear()
	else:
		_start_toast_variant_idx.erase(level)
		_start_toast_variant_pct.erase(level)

## 胜利结算外壳：捕获当前对局身份，推进候选，必要时恢复回流冻结状态，再登记提交后效果。
func on_level_won(
	level_num: int,
	kind: int = LevelKind.MAIN,
	this_session_rank: int = 0,
	this_session_diffi: int = 0,
	full_hp: bool = true,
	win_date: Variant = null
) -> void:
	# 先保留本局身份，后续清锁题/推进关号不能让胜利效果错误绑定下一局。
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


## 暂存胜利后的进度、DDA/Elo、锁题清理与特殊关触发计数；不落盘，外层统一提交。
## kind 决定是否占主线关号及是否参与主线 DDA；rank/diffi/full_hp 是本局冻结的结算事实。

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

	# 占号与参与 DDA 是两个维度：插入关不推进主线，部分占号关也可能排除主线 DDA。
	if LevelKind.occupies_level_number(kind):
		var invalid_sign_total: int = get_game_total_stat("normal", "invalid_sign_total")
		_stage_gamble_tag(
			level_num, this_session_rank, this_session_diffi, invalid_sign_total
		)

	if LevelKind.occupies_level_number(kind):
		var next_level: int = level_num + 1
		if next_level > _current_level:
			_current_level = next_level

	# 记录所有升降档之前的档位，供策略钩子和下一关预放猫资格比较。
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

		# dirty 记录本局干扰事实；冻结组的“道具不降档”例外可以计作干净胜利，复活/重试不适用该例外。
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

		# 失败累计在胜利入口汇总处理；_demoted_this_level 防止多个命中条件在同局重复降档。
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

		# 先做通用规则，再交本局具体策略修正；两者必须使用同一个冻结运行时。
		_dda_apply_demote_on_won(level_num, min_strategy)

		elo_v2_settlement = _dispatch_normal_level_settlement(
			level_num, min_strategy, _pre_cat_strat_before
		)
	if kind == LevelKind.MAIN:
		_complete_elo_v2_attempt(level_num)

	if LevelKind.occupies_level_number(kind):
		_current_wrong_cat_num = 0

	# 先把本局结果存为历史事实，再清局内标志，避免下一局继承重试/复活/dirty 状态。
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

	# 日内胜利、最后主线胜利日期与特殊关触发都属于本次候选；页面动画完成与否不影响它们。
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

## 标记本关金鱼预放猫会话胜利并计算后续资格；会话关号不符时清掉这次候选的后续资格。
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

## 返回主线通用 DDA 开始参与的最小关号；更早关卡不累计这套升降档条件。
func _strategy_engagement_min_level() -> int:
	return 6

## 判断本组是否把使用过道具的本局视为干净胜利；排除复活、重试与每日首局，再看冻结组和辅助标签。
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

## 超难增强组下，把超难关也视作预放猫的困难来源；返回 bool。
func _is_super_hard_as_hard(level_num: int) -> bool:
	return (
		_runtime.config("normal_level").is_super_hard_harder_active()
		and _is_super_hard_level(level_num)
	)

## 超难增强组下排除超难关的通用 DDA；与预放猫用途不同，但共享同一冻结判断。
func _is_dda_excluded_super_hard(level_num: int) -> bool:
	return (
		_runtime.config("normal_level").is_super_hard_harder_active()
		and _is_super_hard_level(level_num)
	)

## 判断是否为 G4 压力关；这些关由专属规则控制，不混入通用 DDA。
func _is_dda_excluded_g4_pressure(level_num: int) -> bool:
	return is_g4_pressure_level(level_num)


## 暂存失败事实并保留适用的回流保护；仅记录 level_settled 效果，不在此发真实信号。

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


## 按玩法隔离规则暂存重试、非干净状态及预放猫/DDA 失败次数；不写盘、不推进关号。

func _apply_level_failed(level_num: int, kind: int = LevelKind.MAIN) -> void:
	var is_golden: bool = LevelKind.is_golden_fish(kind)

	var dda_excluded: bool = LevelKind.is_excluded_from_main_dda(kind)

	# 隔离玩法失败不能污染主线重试连计；仍可在自己的候选里标记本次 dirty。
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

## 胜利时处理重试/复活引发的降档；下一关不能适用时先记 pending，每局最多实际降一次。
func _dda_apply_demote_on_won(level_num: int, min_strategy: int) -> void:
	if _is_daily_first_easy_level:
		return

	var triggered: bool = _current_level_retried or _dda_revive_used

	var next_level: int = level_num + 1
	var next_is_hard: bool = _is_hard_level(next_level)

	# 下一关的特殊表也取冻结 runtime；不能结算时突然使用最新 AB/内容表改变降档去向。
	var next_is_skip: bool = (
		next_is_hard
		or LevelData.is_special_level(next_level, _runtime)
		or _is_dda_excluded_super_hard(next_level)
		or _is_dda_excluded_g4_pressure(next_level)
	)

	# 先兑现前一关延期的降档；本关又命中条件时仍受同一个“已降档”标志保护。
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
	# 结算上下文是纯数据桥：输入本局表现与原交付评分，策略把新档位/评分写回同一对象。
	var ctx := LevelSettlementContext.new()

	ctx.level_num = level_num
	ctx.min_strategy = min_strategy
	ctx.strategy_before_all = strategy_before_all
	ctx.retried = _current_level_retried
	ctx.revive_used = _dda_revive_used
	ctx.tool_or_revive_used = _dda_tool_or_revive_used
	ctx.is_daily_first_easy_level = _is_daily_first_easy_level
	# 原交付的 rank/rating/局数用于 Elo 计算；不能把已调整后的新评分反当作本局输入。
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

	# 具体策略失败会留下 _stage_error；外层 stage 最终会拒绝整个候选，而不是只忽略评分。
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


## 将外部胜利日期转换成字符串；只有 null 才使用本次上下文的今日日期，空串会原样保留。

func _date_for_main_win(win_date: Variant) -> String:
	return _today_str() if win_date == null else str(win_date)


## 在候选按日胜利字典中加一；使用本次环境日期，尚未写入实际存档。

func _inc_today_win_count() -> void:
	var today: String = _today_str()
	_recent_win_counts_by_day[today] = _recent_win_counts_by_day.get(today, 0) + 1


# 沿用原业务的删号保留字段清单；仅保留数据名称，不在结算对象中实现账号删除。
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





## 外层 request 已先校验业务身份；在副本中按 outcome 计算结算，成功才整体替换传入 candidate。
## 返回 {ok, effects} 或失败；effects 只能在外层落盘成功后发布，不能看到 ok 就提前通知页面/SDK。
static func stage(candidate: Dictionary, level: int, outcome: String, context: Dictionary) -> Dictionary:
	# 没有本局冻结策略就拒绝结算，不能为了补齐参数从当前全局分组重新选一套规则。
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
	# 策略失败时丢弃私有候选；传入 candidate 在这条分支尚未被 clear/merge。
	if not progress._stage_error.is_empty():
		var error: Dictionary = progress._stage_error.duplicate(true)
		progress._runtime.state = null
		return error
	# 先完成字段投影和效果快照，再拆循环引用；最后替换调用者候选，仍未触碰权威存档。
	var after: Dictionary = progress.export_candidate()
	var effects: Array = progress.events.duplicate(true)
	progress._runtime.state = null
	candidate.clear()
	candidate.merge(after, true)
	return OperationResult.success({"effects": effects})

## 委托 ActionFacts 暂存日切与工具/复活/结束计数，直接返回其结果，不进入完整选题策略。
## 纯动作计算另有独立脚本供无 Autoload 工程使用；本类只是保持现有业务调用入口。
static func stage_activity(candidate: Dictionary, kind: String, mode: String = "", policy: Dictionary = {}) -> Dictionary:
	return ActionFacts.stage_activity(candidate, kind, mode, policy)


## 把动作回执中的已裁决事实交纯 ActionFacts 写入候选；不靠动画回调再次推断错误或复活。
static func stage_action_facts(candidate: Dictionary, mode: String, receipt: Dictionary, snapshot: Dictionary) -> Dictionary:
	return ActionFacts.stage_action_facts(candidate, mode, receipt, snapshot)

## 跳过金鱼关时暂存预放猫后续、跳过连计与生涯状态，并清旧锁题/残局；不提交。
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
	# 已放弃该特殊关，清掉候选的旧残局，避免提交后再次恢复被跳过的题。
	_candidate.endgame["snapshot"] = {}


## 跳过颜色挑战：区分未进入与失败后跳过，计算适用的延后目标，并恢复图案模式、清残局。
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


## 在独立候选对象中计算特殊关跳过，再整体写回传入 candidate；kind=golden 走金鱼，否则走颜色挑战。
## context 由调用方提供冻结环境，返回 ok 不代表已经落盘，外层仍需提交。
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

## 仅当关号匹配时清回流当前关与旧残局来源标志；避免旧关操作取消另一个保护关。
func clear_returnee_current_level(level_num: int) -> void:
	if _returnee_current_level != level_num:
		return
	_returnee_current_level = 0
	_returnee_from_endgame_save = false
