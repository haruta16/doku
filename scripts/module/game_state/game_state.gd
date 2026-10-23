## 全局玩家状态：集中维护关卡进度、选题游标、动态难度、道具、会话及回流活动。
## 玩家档经 SaveStore 双槽落盘；普通与每日残局、解题步骤和局内统计单独写入残局档。
## 选题结果由 finalize_selected_puzzle 提交，通关和失败统一结算；云端只同步明确导出的字段。
extends Node

signal all_data_reset # 全量重置（reset_all）后发出，让各模块清缓存

# ---- 存档路径与口令 ----
## 存档目录（玩家档 + 残局档都放这里）
## 存档目录（两人档 + 残局档都放这里）
const SAVE_DIR := "user://save_store/"
const SAVE_PATH_A := "user://save_store/save_a.cfg" # 双槽中的 A 槽
const SAVE_PATH_B := "user://save_store/save_b.cfg" # 双槽中的 B 槽
const SAVE_FLAG := "user://save_store/flag.txt" # 记录最后写成功的槽（A/B）
const SAVE_PATH_OLD := "user://save.cfg" # 旧版单文件存档，只用于迁移兜底
const SAVE_PATH_ENDGAME := "user://save_store/endgame.cfg" # 残局档：残局快照 + 本局统计 + 对局 ID

const SAVE_PASSWORD := "qd_x9K3mPv7RtN2sLwH8jFcZyA5eBkM1n" # 存档加密口令（ConfigFile 加密读写）

# ---- 两个 SaveStore 实例（_ready 里创建） ----
## 玩家档：双槽轮换 + 原子写
var _player_store: SaveStore
var _endgame_store: SaveStore # 残局档：单槽，不需要轮换

var _endgame_dirty: bool = false # 残局档有未落盘的改动
var _endgame_coalesce_timer: Timer # 0.5 秒合并写盘定时器，避免高频统计每笔都写文件

signal tool_count_changed(kind: String, count: int) # 道具数量变化时发出，局内 UI 监听刷新

signal level_settled(won: bool)

signal main_level_won(game_id: String, kind: int, win_date: Variant)

signal cloud_progress_restored(level_num: int)

signal home_companion_changed

signal elo_rating_committed(rank: int, new_value: float)

# ---- 关卡进度与难度自适应（DDA） ----
## 当前关卡号，从 1 开始
var _current_level: int = 1

var _home_companion_data: Dictionary = {}

var _last_hard_level: int = 0
var _tutorial_done: bool = false # 新手引导是否已完成
var _has_shown_rate_us: bool = false # 是否已弹过评分引导

var _has_used_revive_free: bool = false # 免费复活是否已用过（只送一次）

var _warn_life_shown: bool = false # 是否已提示过「生命告急」

var _life_plus_first_done: bool = false # 生命上限 +1 的首次赠送是否已发

var _countdown_shown_levels: Dictionary = {}

var _current_strategy: int = 1 # 当前提示策略层 R1~R6，由 DDA 升降

var _consecutive_clean_wins: int = 0 # 连续「干净通关」次数，够阈值就升一层

var _last_level_clean_win: bool = false # 上一关是否干净通关

var _consecutive_fails: int = 0 # 连续失败次数，够阈值就降一层

var _consecutive_retry_levels: int = 0 # 连续重试同一关的关数（重试降档用）
var _retry_tracking_strategy: int = 0 # 统计连续重试时所在的策略层

# ---- 题库游标与每日挑战 ----
## 旧版题库游标：key = "尺寸_段位[_H]"（_H 表示困难组）→ 已出题数
var _bank_progress: Dictionary = {}

var _main_bank_progress: Dictionary = {} # 新版题库进度：key → {lk_mod, regular, lkstyle, transform}

var _lkmod_progress: Dictionary = {} # lkmod 玩法进度："尺寸_段位" → {idx}

var _super_hard_anchor: int = 0

var _sp_tt_category_cursor: int = 1

var _sp_tt_last_replaced_level: int = 0

var _sp_tt_progress: Dictionary = {}

var _lk_mod_g2_last_replaced_level: int = 0

var _sp_tt_lk_alt_last_replaced_level: int = 0

var _sp_tt_lk_alt_block_source: String = "sp_tt"

var _sp_tt_lk_alt_block_count: int = 0

var _downgrade_special_pending_level: int = 0

var _single_region_supp_progress: Dictionary = {}

var _climax_filter_progress: Dictionary = {}

var _elo_aux_single_region_progress: Dictionary = {}
var _elo_aux_climax_progress: Dictionary = {}

var _nl11701_shuffle_seed: int = 0
var _normal_pass_time_records: Array = []
const NORMAL_PASS_TIME_LIMIT: int = 10
var _nl12100_restore_strategy: int = 0
var _nl_v6_alternate_r4_count: int = 0
var _nl_v6_alternate_r4_level: int = 0
var _nl_v6_pool_progress: Dictionary = {}
var _nl_v6_alt_state: Dictionary = {}

var _daily_index: int = 0 # 遗留字段：只做读写，已无 accessor

var _daily_completed_date: String = "" # 最近通关的每日挑战日期（YYYY-MM-DD）

var _max_daily_date: String = "" # 已解锁到的最晚每日挑战日期

var _daily_first_easy_date: String = "" # 最后一次用掉「首次降档」机会的日期

var _daily_elapsed_sec: int = 0 # 本次每日挑战用时（秒）
var _daily_beat_percent: float = 0.0 # 本次每日挑战击败的玩家百分比

var _daily_best_beat_percent: float = 0.0 # 历史最好击败百分比

var _daily_started_date: String = "" # 本次每日挑战开始的日期

# ---- 对局统计与对局 ID（这几个字段实际落在 endgame.cfg，玩家档里只写空值） ----
## 旧版汇总统计：已无 accessor，只做兼容读写
var _game_total_stats: Dictionary = {}

var _main_game_total_stats: Dictionary = {} # 普通模式跨局累计统计（如 hint_used_total）
var _daily_game_total_stats: Dictionary = {} # 每日挑战跨局累计统计

var _main_game_round_stats: Dictionary = {} # 普通模式本局统计（键见 Tracker._ROUND_STAT_KEYS）
var _daily_game_round_stats: Dictionary = {} # 每日挑战本局统计
var _main_solution_steps: Dictionary = {}
var _daily_solution_steps: Dictionary = {}

var _main_game_id: String = "" # 普通模式当前对局 ID（埋点串一局用）
var _daily_game_id: String = "" # 每日挑战当前对局 ID

const TOOL_COUNT_MAX: int = 999999

# ---- 道具库存 ----
## 定位道具数量（初始 5）
var _tool_locate: int = 5
var _tool_hint: int = 5 # 提示道具数量（初始 5）

var _tool_mouse: int = 2

var _tool_draft: int = 5

var _tool_undo: int = 3 # 撤销道具数量（初始 3）

# ---- 闪屏与语言 ----
## 最近一次展示闪屏的日期（判断「今天是否第一次启动」）
var _last_splash_date: String = ""

var _splash_durations: Array = []
const SPLASH_DURATION_LIMIT: int = 3

var _apply_locale: String = "" # 已经应用过的语言代码（LanguageManager 判断是否需要重载）

# ---- 首次启动与「当日第一关」 ----
## 是否首次启动（持久化；Launcher 启动时 consume）
var _is_first_session: bool = true

var _last_first_level_date: String = "" # 最近一次「当日第一关」的日期

# ---- 设置项（音乐/音效/震动/people） ----
## 音乐开关（默认开）
var _music_on: bool = true

var _music_user_modified: bool = false # 用户是否手动改过音乐开关（改过就不再套默认值）
var _sound_on: bool = true # 音效开关
var _vibration_on: bool = true # 震动开关

var _people_on: bool = true # 设置项 people（combo_voice 实验开启时才在设置页显示）

# ---- 一次性引导 / 解锁 / 计数标记 ----
## 是否用过道具（首次使用会记下来给 DDA 看）
var _has_used_tool: bool = false

var _prop_highlight_shown: bool = false # 道具高亮引导是否已展示

var _prop_highlight_hint_date: String = ""
var _push_ask_count: int = 0 # 推送授权询问次数（最多问 2 次）

var _push_guide_last_date: String = ""

var _push_guide_shown_count: int = 0

var _push_guide_popup_count: int = 0

var _recent_win_counts_by_day: Dictionary = {}

var _last_main_win_date: String = ""

var _daily_first_win_entry_date: String = ""

var _has_shown_att_guide: bool = false # ATT 授权引导是否已展示

var _interstitial_unlocked: bool = false # 插屏广告是否已解锁

var _banner_unlocked: bool = false # banner 广告是否已解锁

var _has_shown_draft_onboarding: bool = false # 草稿功能引导是否已展示

var _auto_mark_tutorial_done: bool = false # 每日自动标叉教程是否已完成

var _rule_info_bar_collapsed: bool = false # 规则说明栏是否处于折叠状态

var _pattern_mode_on: bool = false

var _pattern_entry_dot_dismissed: bool = false
var _pattern_switch_dot_dismissed: bool = false

var _music_entry_dot_dismissed: bool = false

# ---- GRT 埋点去重（存在存档里，保证每个事件只报一次） ----
## 已上报过的 D90 关卡档位
var _grt_level_d90_reported: Array = []

var _grt_reported_events: Array = [] # 已上报过的 GRT 事件名（关卡窗口 + 时长窗口）

# ---- 会话与活跃时长 ----
## 首次打开时间（毫秒时间戳；SDK 给的值优先，0 表示未知）
var _first_open_time_ms: int = 0

var _today_date: String = "" # 日切时记下的「今天」，用于判断是否需要跨天重置

var _session_count: int = 0 # 累计会话数（每次 on_session_started +1）

var _today_session_count: int = 0 # 今日会话数

var _last_day_session_count: int = 0 # 昨日会话数（日切时从 today 挪过来）

var _active_days: int = 0 # 活跃天数（每次日切 +1，Helpshift 也用）

var _last_login_date: String = ""
var _returnee_group: int = 0
var _returnee_from_endgame_save: bool = false
var _returnee_remaining: int = 0
var _returnee_lower: int = 1
var _returnee_upper: int = 1
var _returnee_frozen_strategy: int = 1
var _returnee_previous_login_date: String = ""
var _returnee_level_at_login: int = 0
var _returnee_started_this_cold_start: bool = false
var _returnee_current_level: int = 0
var _returnee_lkmod_resume_level: int = 0
var _returnee_frozen_dda: Dictionary = {}

var _login_gap_days: int = 0

var _stale_endgame_discarded: bool = false

var _comeback_welcome_shown: bool = false

var _comeback_start_level: int = 0

var _comeback_main_win_consumed: bool = false

var _today_played_count: int = 0 # 今日已开局数

var _today_tool_consumed: int = 0
var _today_revive_count: int = 0

var _today_active_sec: int = 0 # 今日前台活跃秒数（SessionManager 每 60 秒累加）

var _today_cat_found: int = 0

var _today_mark_placed: int = 0

var _game_barrage_daily_keys: PackedStringArray = PackedStringArray()

var _today_win_stats_group: int = -1

var _total_active_sec: int = 0 # 累计前台活跃秒数（GRT 时长埋点用）

var _elo_rating_r3: float = 0.0
var _elo_rating_r4: float = 0.0
var _elo_rating_r5: float = 0.0
var _elo_games_r3: int = 0
var _elo_games_r4: int = 0
var _elo_games_r5: int = 0

var _elo_init_r3: bool = false
var _elo_init_r4: bool = false
var _elo_init_r5: bool = false
var _elo_group2_cohort: int = -1

var _elo_band_r3: int = 0
var _elo_band_r4: int = 0
var _elo_band_r5: int = 0

var _elo_active_rank: int = 0

var _elo_active_puzzle_rating: float = 0.0

var _elo_fish_consumed: int = 0

var _elo_selected_pids: Array = []

var _rating_selected_pids: Array = []

var _elo_boost_state: Dictionary = {}
var _elo_v2_attempt: Dictionary = {}
var _elo_v2_won_styles: Array = []
var _elo_v2_source_selected_ids: Dictionary = {}

# ---- 奖励队列与「找回」 ----
## 待领取奖励队列（发奖失败时入队，主页弹窗领取）
var _pending_rewards: Array = []

var _reward_history_ts: Array = [] # 正常发奖的时间戳历史（只留 7 天，判断能否找回）

var _restored_today_count: int = 0 # 今日已找回次数（上限 3）

var _in_flight_awards: Array = [] # 发放中的奖励（AwardManager 用来防重复发）

# ---- 每日挑战自动标叉 ----
## 今日是否已开启自动标叉（日切时清零）
var _daily_auto_mark_enabled: bool = false

var _daily_auto_mark_free_consumed: bool = false # 今日免费自动标叉次数是否已用

var _saved_game_auto_mark: int = -1 # 上一局保存的自动标叉设置（-1 = 没有）

var _saved_ab_groups: Dictionary = {}

var _saved_peek_ab_groups: Dictionary = {}

var _loading_page_test_force_longest_quote: bool = false

# ---- 重试题目、最近出题与残局快照 ----
## 重试参数对应的关卡号（0 表示没有；只有关卡号匹配才生效）
var _retry_puzzle_level: int = 0
var _retry_puzzle_params: Dictionary = {} # 重试时要复用的题库参数（配合 _retry_puzzle_level 校验）

var _current_wrong_cat_num: int = 0

var _insert_golden_fish_wrong_cat_num: int = 0

var _pre_cat_fail_lv: int = 0
var _pre_cat_fail_count: int = 0
var _pre_cat_revived_this_level: bool = false

var _pre_cat_pending_hard: bool = false

var _pre_cat_pending_struggle: bool = false

var _pre_cat_pending_demote: bool = false

var _pre_cat_lock_lv: int = 0
var _pre_cat_lock_pre_type: String = "0"
var _pre_cat_lock_pos: Vector2i = Vector2i(-1, -1)

var _pre_cat_fx_played_lv: int = 0

var _golden_fish_pre_cat_session: Dictionary = {}

var _recent_puzzles: Array = [] # 最近出过的题目记录（含题库进度快照，用于去重与回滚）
const RECENT_PUZZLES_LIMIT := 100 # 最近出题记录的上限（超出丢最旧的）

var _endgame_snapshot: Dictionary = {} # 残局快照（真实存在 endgame.cfg，玩家档里只写空值）
const ENDGAME_SNAPSHOT_VERSION: int = 2 # 残局快照结构版本号

var _daily_endgame_snapshot: Dictionary = {}

var _golden_fish_streak_count: int = 0

var _golden_fish_pending: bool = false

var _golden_fish_tutorial_shown: bool = false

var _onefish_consecutive_wins: int = 0

var _onefish_consecutive_skips: int = 0

var _onefish_spawn_suppressed: bool = false

var _onefish_progress: Dictionary = {}

var _onefish_shuffle_orders: Dictionary = {}

var _onefish_shuffle_cursors: Dictionary = {}

var _onefish_used_bits: Dictionary = {}

var _onefish_cycle_rounds: Dictionary = {}

var _onefish_shuffle_group: int = -1

var _onefish_pick_switch_anchor: int = 0

var _golden_fish_insert_delivered: int = 0

var _golden_fish_career_count: int = 0

var _color_challenge_since_gf: int = ColorChallengeGate.NOT_STARTED

var _color_challenge_pending: bool = false

var _color_challenge_delivered: int = 0

var _color_challenge_progress: Dictionary = {}

var _color_challenge_skip_count: int = 0

var _color_challenge_deferred_used: bool = false

var _color_challenge_defer_until: int = 0

var _color_challenge_disabled: bool = false

var _pattern_mode_before_color_challenge: int = -1

var _chain_last_replaced_level: int = 0

var _chain_g3_streak: int = 0

var _bsz11801_cycle_hits: int = 0

var _bsz11802_dyn_size: int = 8

var _bsz11802_last_delivered_size: int = 0

var _bsz11802_stuck_streak: int = 0

var _g4_pressure_level_num: int = 0

var _g4_defer_pending: bool = false

# ---- 仅内存的局内状态（不写进 _save_data，重启即丢） ----
## 调试模式（非 rel 构建下 is_debug_mode() 恒为 true）
var _debug_mode: bool = false

var _current_level_dirty: bool = false # 本局是否动过道具/复活（脏了就没有干净通关连击）

var _current_level_retried: bool = false # 本局是否是重试局

var _demoted_this_level: bool = false # 本关是否已经降过档（一关最多降一次）

var _dda_tool_or_revive_used: bool = false # 本局是否用过道具或复活（DDA 降档判据）

var _dda_revive_used: bool = false # 本局是否用过复活

var _dda_pending_demote: bool = false # 待执行的降档（下一关是困难/特殊关时先挂起）

var _is_daily_first_easy_level: bool = false # 本局是否走了「每日首次降档」

var _chain_g2_pending: bool = false

var _sr_dda_pending_rank: int = 0
var _sr_dda_pending_is_upgrade: bool = false

var _persisted_user_tags: Dictionary = {}

var _has_assist_confirmed: bool = false

var _is_gamble_user: int = -1

var _early_l1_l20_bits: Array = []

var _recent_hard_invalid_bits: Array = []

var _11503_r3_played_count: int = 0

var _11503_r4_played_count: int = 0

var coords_visible: bool = false # 坐标显示开关（唯一的 public 成员，UI 直接读写，不落盘）

# ---- 本次运行（冷启动）内的计数（不落盘） ----
## 本次运行是否仍算首次启动，mark_first_session_done 后置 false
var _first_session_runtime: bool = true

var _session_played_count: int = 0 # 本次会话已开局数

var _daily_first_easy_available: bool = false # 今日是否还能享受首次降档（启动时评估一次）
var _daily_first_easy_evaluated: bool = false # 本次启动是否已评估过首次降档

var _direct_open_evaluated_this_cold_start: bool = false

var _startup_permission_prompt_shown: bool = false

var _session_reward_view_count: int = 0 # 本次会话看过几次奖励页（激励广告频控用）

var _session_interstitial_count: int = 0

var _session_game_count: int = 0

# ---- 结算文案的临时缓存（只为少算一次，不落盘） ----
## 关卡 → 提示种类 → 开局提示的击败百分比
var _start_toast_pct: Dictionary = {}

var _start_toast_iq_idx: Dictionary = {} # 关卡 → 开局提示选中的 IQ 文案下标

var _start_toast_variant_idx: Dictionary = {}

var _start_toast_variant_pct: Dictionary = {}

var _dc_start_toast_pct: Dictionary = {}

var _toast_hold_text_sig: int = -999
var _toast_shown_keys: PackedStringArray = PackedStringArray()

var _fail_text_revive_x: Dictionary = {} # 关卡 → 失败页文案的横坐标（避免每帧重算）

var _last_win_beat_percent: float = -1.0 # 最近一次通关的击败百分比（-1 = 无）

var _pass_anim_cat_cycle_count: int = 0

var _pass_anim_cat_cycle_group: int = -1

# ---- 帮助与版本信息 ----
## 最近一次打开帮助/FAQ 的时间戳（Helpshift 限流用）
var _help_last_open_time: int = 0

var _install_version: String = "" # 首次记录到的安装包版本号

var _game_version_pre: String = ""

const VERSION_1_14_0: String = "1.14.0"


## 建立玩家档与残局档、创建半秒合并写盘定时器，迁移并加载旧档后注册云同步。
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

	DataSyncRegistry.register(self)


# ================= 关卡进度与 DDA 状态 =================
## 取当前关卡号
func get_current_level() -> int:
	return _current_level


## 返回主页伙伴状态的深拷贝，防止外部直接改动存档引用。
func get_home_companion_data() -> Dictionary:
	return _home_companion_data.duplicate(true)


## 深拷贝保存伙伴状态，内容改变时写盘并通知主页刷新。
func set_home_companion_data(value: Dictionary) -> void:
	if _home_companion_data == value:
		return
	_home_companion_data = value.duplicate(true)
	_save_data()
	home_companion_changed.emit()


## 设置当前关卡号并立刻写盘
func set_current_level(value: int) -> void:
	_current_level = value
	_save_data()


## 读取持久化用户标签；缺失或类型错误时返回空串。
func get_persisted_user_tag(key: String) -> String:
	var value: Variant = _persisted_user_tags.get(key, "")
	return value if value is String else ""


## 增删指定用户标签，默认立即落盘；批量操作可显式延后保存。
func set_persisted_user_tag(key: String, value: String, persist: bool = true) -> void:
	if key.is_empty():
		return
	if value.is_empty():
		if not _persisted_user_tags.has(key):
			return
		_persisted_user_tags.erase(key)
	elif get_persisted_user_tag(key) == value:
		return
	else:
		_persisted_user_tags[key] = value
	if persist:
		_save_data()


func get_gamble_user_value() -> int:
	return _is_gamble_user


func set_gamble_user_value(value: int, persist: bool = true) -> void:
	_is_gamble_user = value
	if persist:
		_save_data()


func get_gamble_user_early_l1_l20_bits() -> Array:
	return _early_l1_l20_bits.duplicate()


func set_gamble_user_early_l1_l20_bits(bits: Array, persist: bool = true) -> void:
	_early_l1_l20_bits = bits.duplicate()
	if persist:
		_save_data()


func get_gamble_user_recent_hard_invalid_bits() -> Array:
	return _recent_hard_invalid_bits.duplicate()


func set_gamble_user_recent_hard_invalid_bits(bits: Array, persist: bool = true) -> void:
	_recent_hard_invalid_bits = bits.duplicate()
	if persist:
		_save_data()


func get_last_hard_level() -> int:
	return _last_hard_level


## 记录最近一次困难关关号，仅变化时写盘。
func mark_hard_level(level_num: int) -> void:
	if _last_hard_level == level_num:
		return
	_last_hard_level = level_num
	_save_data()


## 新手引导是否已完成
func is_tutorial_done() -> bool:
	return _tutorial_done


## 标记新手引导完成并写盘
func set_tutorial_done(value: bool) -> void:
	_tutorial_done = value
	_save_data()


## 是否已弹过评分引导（主页判断用）
func has_shown_rate_us() -> bool:
	return _has_shown_rate_us


func is_has_assist_confirmed() -> bool:
	return _has_assist_confirmed


func mark_has_assist_confirmed() -> void:
	if _has_assist_confirmed:
		return
	_has_assist_confirmed = true
	_save_data()


func has_countdown_shown_for_level(level: int) -> bool:
	if level <= 0:
		return false
	return _countdown_shown_levels.get(level, false)


func mark_countdown_shown_for_level(level: int) -> void:
	if level <= 0:
		return
	if _countdown_shown_levels.get(level, false):
		return
	_countdown_shown_levels[level] = true
	_save_data()


func mark_startup_permission_prompt_shown() -> void:
	_startup_permission_prompt_shown = true


func has_startup_permission_prompt_shown() -> bool:
	return _startup_permission_prompt_shown


func try_consume_direct_open_gate() -> bool:
	if _direct_open_evaluated_this_cold_start:
		return false
	_direct_open_evaluated_this_cold_start = true
	return true


# ================= 每日挑战：首次降档机会 =================
## 今日是否还能享受「每日首次降档」（结果由 evaluate_daily_first_easy 评估）
func is_daily_first_easy_available() -> bool:
	return _daily_first_easy_available


## 冷启动评估降档机会：今天的机会已用，或残局里已有玩家操作，就作废
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


## 消耗今日降档机会（记日期 + 写盘）
func consume_daily_first_easy() -> void:
	_daily_first_easy_date = _today_str()
	_daily_first_easy_available = false
	_save_data()


## 消耗机会并把本局标成「首次降档局」
func consume_daily_first_easy_and_mark() -> void:
	consume_daily_first_easy()
	_is_daily_first_easy_level = true


## 局内跨天又开新局：把机会日期推进到今天（等于作废今日机会）
func advance_daily_first_easy_date() -> void:
	var today: String = _today_str()
	if _daily_first_easy_date >= today:
		return
	_daily_first_easy_date = today
	_daily_first_easy_available = false
	_save_data()
	print("[DailyFirstEasy] 局内跨天+开始新对局, 推进日期消耗机会")


## 调试用：清空机会日期，让今日重新可用
func cheat_reset_daily_first_easy() -> void:
	_daily_first_easy_date = ""
	_save_data()


## 取本次会话看过的奖励页次数
func get_session_reward_view_count() -> int:
	return _session_reward_view_count


## 奖励页次数 +1（不写盘）
func increment_session_reward_view_count() -> void:
	_session_reward_view_count += 1


## 奖励页计数归零
func reset_session_reward_view_count() -> void:
	_session_reward_view_count = 0


## 直接设置奖励页次数（负数按 0 处理）
func set_session_reward_view_count(value: int) -> void:
	_session_reward_view_count = max(0, value)


func get_session_interstitial_count() -> int:
	return _session_interstitial_count


func increment_session_interstitial_count() -> void:
	_session_interstitial_count += 1


func set_session_interstitial_count(value: int) -> void:
	_session_interstitial_count = max(0, value)


func get_session_game_count() -> int:
	return _session_game_count


func increment_session_game_count() -> void:
	_session_game_count += 1


func set_session_game_count(value: int) -> void:
	_session_game_count = max(0, value)


# ---- 各类「已展示/已用完」标记（多数会写盘） ----
## 标记评分引导已弹过并写盘
func mark_rate_us_shown() -> void:
	if _has_shown_rate_us:
		return
	_has_shown_rate_us = true
	_save_data()


## 清掉评分引导标记并写盘（调试/重置用）
func reset_rate_us_shown() -> void:
	if not _has_shown_rate_us:
		return
	_has_shown_rate_us = false
	_save_data()


## 是否提示过「生命告急」
func has_shown_warn_life() -> bool:
	return _warn_life_shown


## 标记已提示过生命告急
func mark_warn_life_shown() -> void:
	if _warn_life_shown:
		return
	_warn_life_shown = true
	_save_data()


## ATT 授权引导是否已展示
func has_shown_att_guide() -> bool:
	return _has_shown_att_guide


## 标记 ATT 引导已展示
func mark_att_guide_shown() -> void:
	if _has_shown_att_guide:
		return
	_has_shown_att_guide = true
	_save_data()


## 插屏广告是否已解锁
func is_interstitial_unlocked() -> bool:
	return _interstitial_unlocked


## 解锁插屏广告
func mark_interstitial_unlocked() -> void:
	if _interstitial_unlocked:
		return
	_interstitial_unlocked = true
	_save_data()


## banner 广告是否已解锁
func is_banner_unlocked() -> bool:
	return _banner_unlocked


## 解锁 banner 广告
func mark_banner_unlocked() -> void:
	if _banner_unlocked:
		return
	_banner_unlocked = true
	_save_data()


func is_pattern_mode_on() -> bool:
	return _pattern_mode_on


func set_pattern_mode_on(value: bool) -> void:
	print("[PATTERN_DBG] set_pattern_mode_on value=%s (before=%s)" % [value, _pattern_mode_on])
	_pattern_mode_on = value
	_save_data()
	print("[PATTERN_DBG] after save, is_pattern_mode_on=%s" % _pattern_mode_on)


func is_pattern_entry_dot_dismissed() -> bool:
	return _pattern_entry_dot_dismissed


func mark_pattern_entry_dot_dismissed() -> void:
	if _pattern_entry_dot_dismissed:
		return
	_pattern_entry_dot_dismissed = true
	_save_data()


func is_music_entry_dot_dismissed() -> bool:
	return _music_entry_dot_dismissed


func mark_music_entry_dot_dismissed() -> void:
	if _music_entry_dot_dismissed:
		return
	_music_entry_dot_dismissed = true
	_save_data()


func is_pattern_switch_dot_dismissed() -> bool:
	return _pattern_switch_dot_dismissed


func mark_pattern_switch_dot_dismissed() -> void:
	if _pattern_switch_dot_dismissed:
		return
	_pattern_switch_dot_dismissed = true
	_save_data()


func is_music_user_modified() -> bool:
	return _music_user_modified


func get_saved_ab_group(key: String) -> int:
	return int(_saved_ab_groups.get(key, -1))


func set_saved_ab_group(key: String, v: int) -> void:
	if int(_saved_ab_groups.get(key, -1)) == v:
		return
	_saved_ab_groups[key] = v
	_save_data()


## 把指定实验键迁入 peek 存储区并移除旧键，发生迁移才写盘。
func migrate_saved_ab_groups_to_peek(keys: Array[String]) -> void:
	var changed: bool = false
	for key: String in keys:
		if not _saved_ab_groups.has(key):
			continue
		var old_group: int = int(_saved_ab_groups[key])
		if _saved_peek_ab_groups.get(key, null) == null and old_group >= 0:
			_saved_peek_ab_groups[key] = old_group
		_saved_ab_groups.erase(key)
		changed = true
	if changed:
		_save_data()


func cheat_restore_ab_group_before_peek_migration(key: String, group: int) -> void:
	_saved_ab_groups[key] = group
	_saved_peek_ab_groups.erase(key)
	_save_data()


func get_saved_peek_ab_group(key: String) -> Variant:
	return _saved_peek_ab_groups.get(key, null)


func set_saved_peek_ab_group(key: String, v: Variant) -> void:
	if _saved_peek_ab_groups.get(key, null) == v:
		return
	_saved_peek_ab_groups[key] = v
	_save_data()


func erase_saved_peek_ab_group(key: String) -> void:
	if not _saved_peek_ab_groups.has(key):
		return
	_saved_peek_ab_groups.erase(key)
	_save_data()


func set_loading_page_test_peek_override(
	key: String, group: int, force_longest_quote: bool
) -> void:
	if (
		_saved_peek_ab_groups.get(key, null) == group
		and _loading_page_test_force_longest_quote == force_longest_quote
	):
		return
	_saved_peek_ab_groups[key] = group
	_loading_page_test_force_longest_quote = force_longest_quote
	_save_data()


func is_loading_page_test_force_longest_quote() -> bool:
	return _loading_page_test_force_longest_quote


func consume_loading_page_test_force_longest_quote() -> bool:
	if not _loading_page_test_force_longest_quote:
		return false
	_loading_page_test_force_longest_quote = false
	_save_data()
	return true


func clear_loading_page_test_force_longest_quote() -> void:
	if not _loading_page_test_force_longest_quote:
		return
	_loading_page_test_force_longest_quote = false
	_save_data()


# ---- GRT 埋点去重（Tracker 调用；写盘以保证只报一次） ----
## 某个 D90 关卡档位是否已上报过
func has_grt_level_d90_reported(level: int) -> bool:
	return _grt_level_d90_reported.has(level)


## 记录该档位已上报（写盘，保证只报一次）
func mark_grt_level_d90_reported(level: int) -> void:
	if _grt_level_d90_reported.has(level):
		return
	_grt_level_d90_reported.append(level)
	_save_data()


## 某个 GRT 事件是否已上报过
func has_grt_event_reported(event_name: String) -> bool:
	return _grt_reported_events.has(event_name)


## 记录该 GRT 事件已上报
func mark_grt_event_reported(event_name: String) -> void:
	if _grt_reported_events.has(event_name):
		return
	_grt_reported_events.append(event_name)
	_save_data()


# ---- 首次打开时间与策略层 ----
## 取首次打开时间（毫秒时间戳，0 表示还没记录）
func get_first_open_time_ms() -> int:
	return _first_open_time_ms


## 只在首次写入打开时间：优先用 SDK 的值，没有就用本地时间
func ensure_first_open_time(sdk_value_ms: int) -> void:
	if _first_open_time_ms > 0:
		return
	if sdk_value_ms > 0:
		_first_open_time_ms = sdk_value_ms
	else:
		_first_open_time_ms = int(Time.get_unix_time_from_system() * 1000.0)
	_save_data()


## 取当前提示策略层
func get_current_strategy() -> int:
	return _current_strategy


## 设置提示策略层并写盘
func set_current_strategy(value: int) -> void:
	_current_strategy = value
	_save_data()


func get_chain_last_replaced_level() -> int:
	return _chain_last_replaced_level


func set_chain_last_replaced_level(value: int) -> void:
	_chain_last_replaced_level = value
	_save_data()


func get_chain_g3_streak() -> int:
	return _chain_g3_streak


func set_chain_g3_streak(value: int) -> void:
	_chain_g3_streak = value
	_save_data()


func get_bsz11801_cycle_hits() -> int:
	return _bsz11801_cycle_hits


func set_bsz11801_cycle_hits(value: int) -> void:
	_bsz11801_cycle_hits = value
	_save_data()


func get_bsz11802_dyn_size() -> int:
	return _bsz11802_dyn_size


func set_bsz11802_dyn_size(value: int) -> void:
	_bsz11802_dyn_size = value
	_save_data()


func get_bsz11802_last_delivered_size() -> int:
	return _bsz11802_last_delivered_size


func set_bsz11802_last_delivered_size(value: int) -> void:
	_bsz11802_last_delivered_size = value
	_save_data()


func get_bsz11802_stuck_streak() -> int:
	return _bsz11802_stuck_streak


func set_bsz11802_stuck_streak(value: int) -> void:
	_bsz11802_stuck_streak = value
	_save_data()


## 取最近通关的每日挑战日期
func get_daily_completed_date() -> String:
	return _daily_completed_date


## 取本次每日挑战的开始日期
func get_daily_started_date() -> String:
	return _daily_started_date


## 设置每日挑战开始日期
func set_daily_started_date(date: String) -> void:
	_daily_started_date = date
	_save_data()


# ---- 对局统计与对局 ID（走 endgame 槽） ----
## 跨局累计统计 +delta（走 endgame 槽，0.5 秒合并写盘）
func inc_game_total_stat(game_type: String, key: String, delta: int = 1) -> void:
	var d: Dictionary = _get_total_stats_dict(game_type)
	d[key] = int(d.get(key, 0)) + delta
	_request_save_endgame()


## 读跨局累计统计
func get_game_total_stat(game_type: String, key: String) -> int:
	return int(_get_total_stats_dict(game_type).get(key, 0))


## 取某对局类型持久化的 game_id（Tracker 冷启动时读）
func get_persisted_game_id(game_type: String) -> String:
	if game_type == "daily":
		return _daily_game_id
	return _main_game_id


## 写入 game_id 并立即写 endgame 槽
func set_persisted_game_id(game_type: String, value: String) -> void:
	if game_type == "daily":
		_daily_game_id = value
	else:
		_main_game_id = value
	_save_endgame()


## 清空某对局类型的跨局累计统计
func reset_game_total_stats(game_type: String) -> void:
	var d: Dictionary = _get_total_stats_dict(game_type)
	if d.is_empty():
		return
	d.clear()
	_save_endgame()


## 取本局统计的副本（Tracker 冷启动补数据用）
func get_game_round_stats(game_type: String) -> Dictionary:
	if game_type == "daily":
		return _daily_game_round_stats.duplicate()
	return _main_game_round_stats.duplicate()


## 覆盖保存本局统计（Tracker 每次 inc_stat 都调，走合并写盘）
func persist_game_round_stats(game_type: String, stats: Dictionary) -> void:
	if game_type == "daily":
		_daily_game_round_stats = stats.duplicate()
	else:
		_main_game_round_stats = stats.duplicate()
	_request_save_endgame()


## 清空本局统计（开新一局时）
func reset_game_round_stats(game_type: String) -> void:
	var d: Dictionary = _get_round_stats_dict(game_type)
	if d.is_empty():
		return
	d.clear()
	_save_endgame()


## 返回普通或每日局解题步骤的深拷贝，避免外部更改内部统计。
func get_solution_steps(game_type: String) -> Dictionary:
	if game_type == "daily":
		return _daily_solution_steps.duplicate(true)
	return _main_solution_steps.duplicate(true)


## 深拷贝保存解题步骤，并请求合并写入残局档。
func persist_solution_steps(game_type: String, data: Dictionary) -> void:
	if game_type == "daily":
		_daily_solution_steps = data.duplicate(true)
	else:
		_main_solution_steps = data.duplicate(true)
	_request_save_endgame()


## 清空指定模式的解题步骤，立即刷新残局档。
func reset_solution_steps(game_type: String) -> void:
	if game_type == "daily":
		if _daily_solution_steps.is_empty():
			return
		_daily_solution_steps = {}
	else:
		if _main_solution_steps.is_empty():
			return
		_main_solution_steps = {}
	_save_endgame()


## 内部：按对局类型返回本局统计字典的引用（可直接改）
func _get_round_stats_dict(game_type: String) -> Dictionary:
	if game_type == "daily":
		return _daily_game_round_stats
	return _main_game_round_stats


## 内部：按对局类型返回跨局统计字典的引用（可直接改）
func _get_total_stats_dict(game_type: String) -> Dictionary:
	if game_type == "daily":
		return _daily_game_total_stats
	return _main_game_total_stats


# ---- 每日挑战记录 ----
## 取已解锁的最晚每日挑战日期
func get_max_daily_date() -> String:
	return _max_daily_date


## 只往前走：日期比当前记录更晚才更新
func advance_max_daily_date(date: String) -> void:
	if date > _max_daily_date:
		_max_daily_date = date
		_save_data()


## 取本次每日挑战用时（秒）
func get_daily_elapsed_sec() -> int:
	return _daily_elapsed_sec


## 取本次每日挑战的击败百分比
func get_daily_beat_percent() -> float:
	return _daily_beat_percent


## 取历史最好击败百分比
func get_daily_best_beat_percent() -> float:
	return _daily_best_beat_percent


## 记录每日挑战成绩，同日重玩仅接受更短用时，并更新历史最佳击败百分比。
func mark_daily_completed(date: String, elapsed_sec: int, beat_percent: float) -> void:
	var is_same_day_replay: bool = _daily_completed_date == date
	if is_same_day_replay and elapsed_sec >= _daily_elapsed_sec:
		return
	_daily_completed_date = date
	_daily_elapsed_sec = elapsed_sec
	_daily_beat_percent = beat_percent

	if beat_percent > _daily_best_beat_percent:
		_daily_best_beat_percent = beat_percent
	_save_data()


## 清掉每日挑战的通关记录
func clear_daily_completion() -> void:
	_daily_completed_date = ""
	_daily_elapsed_sec = 0
	_daily_beat_percent = 0.0
	_daily_best_beat_percent = 0.0
	_save_data()


## 本地日期变化时清今日计数、临时奖励和每日缓存，同时裁掉较旧的每日通关记录。
func _roll_day_if_needed() -> void:
	var today: String = _today_str()
	if _today_date == today:
		return
	_last_day_session_count = _today_session_count
	_today_session_count = 0
	_today_played_count = 0
	_today_active_sec = 0
	_today_cat_found = 0
	_today_mark_placed = 0
	_today_tool_consumed = 0
	_today_revive_count = 0
	_game_barrage_daily_keys.clear()
	_restored_today_count = 0
	_daily_auto_mark_enabled = false
	_pending_rewards.clear()
	_dc_start_toast_pct.clear()
	_active_days += 1

	var cutoff_unix: int = Time.get_unix_time_from_datetime_string(today + "T00:00:00") - 2 * 86400
	for key: String in _recent_win_counts_by_day.keys().duplicate():
		if Time.get_unix_time_from_datetime_string(key + "T00:00:00") < cutoff_unix:
			_recent_win_counts_by_day.erase(key)
	_today_date = today


## 先做日切，再增加会话计数、重置会话频控字段并保存。
func on_session_started() -> void:
	_roll_day_if_needed()
	_session_count += 1
	_today_session_count += 1
	_session_played_count = 0
	_session_reward_view_count = 0
	_session_interstitial_count = 0
	_session_game_count = 0
	_save_data()


## 取累计会话数
func get_session_count() -> int:
	return _session_count


## 取活跃天数（会先做日切）
func get_active_days() -> int:
	_roll_day_if_needed()
	return _active_days


## 保存本次冷启动前的登录日期和关号，计算离线天数后更新最近登录日并写盘。
func record_cold_start_login() -> void:
	var today: String = _today_str()
	_returnee_previous_login_date = _last_login_date
	_returnee_level_at_login = _current_level
	if _last_login_date == "":
		_login_gap_days = 0
	else:
		_login_gap_days = max(0, _date_str_to_jdn(today) - _date_str_to_jdn(_last_login_date))
	_last_login_date = today
	_save_data()


## 用冷启动前的登录日期与当前日期计算回流间隔，不使用已经更新的最近登录字段。
func get_returnee_login_gap_days() -> int:
	return ReturneeClock.day_gap(_returnee_previous_login_date, _today_str())


## 要求登录时关号超过 30，再结合离线天数、实验组和本次启动触发状态判断回流资格。
func should_begin_returnee_event(group: int) -> bool:
	return (
		_returnee_level_at_login > 30
		and ReturneeLevelPolicy.can_start(
			get_returnee_login_gap_days(),
			group,
			_returnee_started_this_cold_start,
			ABTestManager.normal_endgame_save.returnee_gap_days()
		)
	)


## 仅修改内存中的回流判断日期与启动标记，便于按当前实验门槛模拟回归。
func cheat_mark_returned_user() -> void:
	var timezone_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	_returnee_level_at_login = _current_level
	_returnee_previous_login_date = ReturneeClock.date_at(
		(
			int(Time.get_unix_time_from_system())
			- ABTestManager.normal_endgame_save.returnee_gap_days() * 86400
		),
		timezone_minutes
	)
	_returnee_started_this_cold_start = false


## 建立十次回流额度、降低难度上界，并冻结当前策略和 DDA 计数，随后写盘。
func begin_returnee_event(group: int, lower: int, upper: int) -> void:
	_returnee_started_this_cold_start = true
	_returnee_group = group
	_returnee_from_endgame_save = false
	_returnee_remaining = 10
	_returnee_lower = lower
	_returnee_upper = ReturneeLevelPolicy.easier_upper(lower, upper)
	_returnee_frozen_strategy = _current_strategy
	_returnee_frozen_dda = {
		"clean": _consecutive_clean_wins,
		"fails": _consecutive_fails,
		"retry_levels": _consecutive_retry_levels,
		"retry_strategy": _retry_tracking_strategy,
		"pending_demote": _dda_pending_demote,
		"demoted": _demoted_this_level,
	}
	_returnee_current_level = 0
	_returnee_lkmod_resume_level = 0
	_save_data()


## 把过期残局替换为更简单题目的关号标记为当前回流关，并写入存档。
func begin_stale_new_easier_level(level_num: int) -> void:
	_returnee_started_this_cold_start = true
	_returnee_group = 0
	_returnee_remaining = 0
	_returnee_from_endgame_save = true
	_returnee_current_level = level_num
	_save_data()


## 仅对当前回流实验组返回剩余额度，其他组视为零。
func get_returnee_remaining(group: int) -> int:
	return _returnee_remaining if group == _returnee_group else 0


## 回流 12001 组尚有额度时推迟金鱼关插入。
func should_defer_returnee_golden_fish() -> bool:
	return get_returnee_remaining(12001) > 0


## 把金鱼待触发标记与回流延后规则合并为实际可用状态。
func get_available_golden_fish_pending() -> bool:
	return _golden_fish_pending and not should_defer_returnee_golden_fish()


## 返回回流期间允许选题的策略层级上下界。
func get_returnee_easy_range() -> Vector2i:
	return Vector2i(_returnee_lower, _returnee_upper)


## 查询当前是否标记了一关回流保护关。
func is_returnee_current_level() -> bool:
	return _returnee_current_level > 0


## 仅在关号匹配时清回流关标记及来源，随后保存。
func clear_returnee_current_level(level_num: int) -> void:
	if _returnee_current_level != level_num:
		return
	_returnee_current_level = 0
	_returnee_from_endgame_save = false
	_save_data()


## 确认实验组与额度有效后记录交付关号，并按固定特殊题规则扣减额度。
func mark_returnee_delivery(group: int, level_num: int, fixed_sp: bool) -> void:
	if group != _returnee_group or _returnee_remaining <= 0:
		return
	_returnee_remaining = ReturneeLevelPolicy.remaining_after_delivery(
		_returnee_remaining, fixed_sp
	)
	_returnee_current_level = level_num
	_save_data()


## 把 LK 改题库恢复节点延后五关，并清各题库进度中的 since_lk 间隔计数。
func reset_returnee_lkmod_interval(last_protected_level: int) -> void:
	_returnee_lkmod_resume_level = last_protected_level + 5
	for key: Variant in _main_bank_progress:
		var progress: Dictionary = _main_bank_progress[key]
		progress["since_lk"] = 0
	_save_data()


## 仅向 12001 组返回延后恢复 LK 改题库的关号。
func get_returnee_lkmod_resume_level() -> int:
	return _returnee_lkmod_resume_level if _returnee_group == 12001 else 0


## 清除 LK 改题库的延后恢复节点并写盘。
func clear_returnee_lkmod_resume_level() -> void:
	_returnee_lkmod_resume_level = 0
	_save_data()


## 返回本次冷启动时已经计算好的离线天数。
func get_login_gap_days() -> int:
	return _login_gap_days


func is_stale_endgame_discarded() -> bool:
	return _stale_endgame_discarded


func mark_stale_endgame_discarded() -> void:
	_stale_endgame_discarded = true


func is_comeback_welcome_shown() -> bool:
	return _comeback_welcome_shown


func mark_comeback_welcome_shown() -> void:
	_comeback_welcome_shown = true


func is_comeback_start_level(level_num: int) -> bool:
	return (
		_comeback_welcome_shown
		and not _comeback_main_win_consumed
		and level_num > 0
		and _comeback_start_level == level_num
	)


## 回流欢迎展示后锁定首个有效关号，重复请求只认可同一关。
func claim_comeback_start_level(level_num: int) -> bool:
	if not _comeback_welcome_shown or _comeback_main_win_consumed or level_num <= 0:
		return false
	if _comeback_start_level == 0:
		_comeback_start_level = level_num
	return _comeback_start_level == level_num


## 消费本次回流首次主线胜利资格，重复调用返回 false。
func consume_comeback_main_win() -> bool:
	if not _comeback_welcome_shown or _comeback_main_win_consumed:
		return false
	_comeback_main_win_consumed = true
	return true


func cheat_set_last_login_days_ago(days_ago: int) -> void:
	var timezone_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	_last_login_date = ReturneeClock.date_at(
		int(Time.get_unix_time_from_system()) - maxi(days_ago, 0) * 86400, timezone_minutes
	)
	_save_data()


static func _date_str_to_jdn(date_str: String) -> int:
	var p: PackedStringArray = date_str.split("-")
	if p.size() != 3:
		return 0
	var y: int = int(p[0])
	var m: int = int(p[1])
	var d: int = int(p[2])
	var a: int = int((14 - m) / 12.0)
	var yy: int = y + 4800 - a
	var mm: int = m + 12 * a - 3
	return (
		d
		+ int((153 * mm + 2) / 5.0)
		+ 365 * yy
		+ int(yy / 4.0)
		- int(yy / 100.0)
		+ int(yy / 400.0)
		- 32045
	)


## 取本次会话已开局数
func get_session_played_count() -> int:
	return _session_played_count


## 取今日已开局数
func get_today_played_count() -> int:
	_roll_day_if_needed()
	return _today_played_count


func get_today_win_count() -> int:
	_roll_day_if_needed()
	return _recent_win_counts_by_day.get(_today_str(), 0)


func has_main_win_today() -> bool:
	return _last_main_win_date == _today_str()


func has_daily_first_win_entry_seen_today() -> bool:
	return _daily_first_win_entry_date == _today_str()


func mark_daily_first_win_entry_seen_today() -> void:
	var today: String = _today_str()
	if _daily_first_win_entry_date == today:
		return
	_daily_first_win_entry_date = today
	_save_data()


func cheat_reset_daily_first_win_encourage() -> void:
	_last_main_win_date = ""
	_daily_first_win_entry_date = ""
	_save_data()


func get_today_tool_consumed() -> int:
	_roll_day_if_needed()
	return _today_tool_consumed


func inc_today_tool_consumed() -> void:
	_roll_day_if_needed()
	_today_tool_consumed += 1
	_save_data()


func get_today_revive_count() -> int:
	_roll_day_if_needed()
	return _today_revive_count


func inc_today_revive_count() -> void:
	_roll_day_if_needed()
	_today_revive_count += 1
	_save_data()


## 一局结束（赢或输）时累加今日/本次会话的开局数
func on_game_finished() -> void:
	_roll_day_if_needed()
	_session_played_count += 1
	_today_played_count += 1
	_save_data()


## 取今日前台活跃秒数
func get_today_active_sec() -> int:
	_roll_day_if_needed()
	return _today_active_sec


## 累加前台活跃秒数（今日与总计一起加），SessionManager 每 60 秒调一次
func add_today_active_sec(delta_sec: int) -> void:
	if delta_sec <= 0:
		return
	_roll_day_if_needed()
	_today_active_sec += delta_sec
	_total_active_sec += delta_sec
	_save_data()


func get_today_cat_found() -> int:
	_roll_day_if_needed()
	return _today_cat_found


func get_today_mark_placed() -> int:
	_roll_day_if_needed()
	return _today_mark_placed


func get_game_barrage_daily_keys() -> PackedStringArray:
	_roll_day_if_needed()
	return _game_barrage_daily_keys.duplicate()


func mark_game_barrage_daily_key(key: String) -> void:
	_roll_day_if_needed()
	if key.is_empty() or _game_barrage_daily_keys.has(key):
		return
	_game_barrage_daily_keys.append(key)
	_save_data()


func add_today_win_stats(cat_delta: int, mark_delta: int, group: int) -> Dictionary:
	_roll_day_if_needed()
	_roll_group_if_needed(group)
	var cat_before: int = _today_cat_found
	var mark_before: int = _today_mark_placed
	_today_cat_found += maxi(cat_delta, 0)
	_today_mark_placed += maxi(mark_delta, 0)
	_save_data()
	return {
		"cat_before": cat_before,
		"cat_after": _today_cat_found,
		"mark_before": mark_before,
		"mark_after": _today_mark_placed,
	}


func cheat_set_today_win_stats(cat_total: int, mark_total: int, group: int) -> void:
	_roll_day_if_needed()
	_today_cat_found = maxi(cat_total, 0)
	_today_mark_placed = maxi(mark_total, 0)
	_today_win_stats_group = group
	_save_data()


func _roll_group_if_needed(group: int) -> void:
	if _today_win_stats_group == group:
		return

	print(
		(
			"[今日战绩] pass_text 分组 %d → %d,两个计数归零重新累积(作废 猫=%d 叉=%d)"
			% [_today_win_stats_group, group, _today_cat_found, _today_mark_placed]
		)
	)
	_today_cat_found = 0
	_today_mark_placed = 0
	_today_win_stats_group = group


## 取累计前台活跃秒数（GRT 时长埋点用）
func get_total_active_sec() -> int:
	return _total_active_sec


# ---- 「找回」规则参数（单位：秒 / 次数） ----
## 正常发奖时间戳保留 7 天，更旧的丢弃
const _REWARD_HISTORY_RETAIN_SEC: int = 7 * 24 * 3600

## 近 3 天至少正常发奖 3 次，才允许「找回」
const _RESTORE_MIN_NORMAL_REWARDS_3D: int = 3
## 「近 3 天」窗口的长度（秒）
const _RESTORE_NORMAL_LOOKBACK_SEC: int = 3 * 24 * 3600

## 每天最多找回 3 次
const _RESTORE_DAILY_MAX: int = 3


# ================= 奖励队列与找回 =================
## 是否有待领取的奖励
func has_pending_rewards() -> bool:
	return not _pending_rewards.is_empty()


## 取待领取奖励列表（返回引用，调用方不要改）
func get_pending_rewards() -> Array:
	return _pending_rewards


## 入队一条待领取奖励（发奖失败时）
func add_pending_reward(reward: Dictionary) -> void:
	_pending_rewards.append(reward)
	_save_data()


## 取走全部待领取奖励并清空（主页弹领取窗时调用）
func pop_all_pending_rewards() -> Array:
	var out: Array = _pending_rewards.duplicate()
	_pending_rewards.clear()
	_save_data()
	return out


## 记录一次正常发奖的时间戳，并裁掉 7 天前的旧记录
func record_normal_reward(ts: int) -> void:
	_reward_history_ts.append(ts)
	var cutoff: int = ts - _REWARD_HISTORY_RETAIN_SEC
	var fresh: Array = []
	for t in _reward_history_ts:
		if int(t) >= cutoff:
			fresh.append(int(t))
	_reward_history_ts = fresh
	_save_data()


## 数一数近 3 天正常发过几次奖励
func _count_recent_normal_rewards(now_ts: int) -> int:
	var cutoff: int = now_ts - _RESTORE_NORMAL_LOOKBACK_SEC
	var hits: int = 0
	for t in _reward_history_ts:
		if int(t) >= cutoff:
			hits += 1
	return hits


## 今日还能找回几次：近 3 天发奖够 3 次才开启，且每日上限 3 次
func get_restore_remaining_today(now_ts: int) -> int:
	_roll_day_if_needed()
	var recent: int = _count_recent_normal_rewards(now_ts)
	if recent < _RESTORE_MIN_NORMAL_REWARDS_3D:
		return 0
	return max(0, _RESTORE_DAILY_MAX - _restored_today_count)


## 取今日已找回次数
func get_restored_today_count() -> int:
	_roll_day_if_needed()
	return _restored_today_count


## 累加今日已找回次数
func add_restored_today_count(n: int) -> void:
	_roll_day_if_needed()
	_restored_today_count += n
	_save_data()


## 从待领取队列里删掉这些条目（已发放）
func remove_pending_rewards(entries: Array) -> void:
	for e in entries:
		_pending_rewards.erase(e)
	_save_data()


## 取今日会话数
func get_today_session_count() -> int:
	_roll_day_if_needed()
	return _today_session_count


## 取昨日会话数
func get_last_day_session_count() -> int:
	_roll_day_if_needed()
	return _last_day_session_count


## 按工具标识读取定位、提示、老鼠或草稿库存，未知标识返回零。
func get_tool_count(kind: String) -> int:
	match kind:
		"locate":
			return _tool_locate
		"hint":
			return _tool_hint
		"mouse":
			return _tool_mouse
		"draft":
			return _tool_draft
		_:
			return 0


## 查询指定 R3～R5 层级的评分是否完成初始化，其他层级不适用。
func is_elo_initialized(rank: int) -> bool:
	match rank:
		3:
			return _elo_init_r3
		4:
			return _elo_init_r4
		5:
			return _elo_init_r5
		_:
			return false


## 首次按是否低于第 100 关固定 Elo 新玩家分组并写盘，之后不随关号变化。
func ensure_elo_group2_cohort() -> bool:
	if _elo_group2_cohort == -1:
		_elo_group2_cohort = 1 if _current_level < 100 else 0
		_save_data()
	return _elo_group2_cohort == 1


## 读取已固定的 Elo 新玩家分组，不在此处重新判定。
func is_elo_group2_new_player() -> bool:
	return _elo_group2_cohort == 1


## 读取对应策略层级的玩家评分，未知层级返回零。
func get_elo_rating(rank: int) -> float:
	match rank:
		3:
			return _elo_rating_r3
		4:
			return _elo_rating_r4
		5:
			return _elo_rating_r5
		_:
			return 0.0


## 读取对应策略层级已提交的 Elo 结算局数。
func get_elo_games(rank: int) -> int:
	match rank:
		3:
			return _elo_games_r3
		4:
			return _elo_games_r4
		5:
			return _elo_games_r5
		_:
			return 0


## 读取对应策略层级当前采用的目标胜率带状态。
func get_elo_band(rank: int) -> int:
	match rank:
		3:
			return _elo_band_r3
		4:
			return _elo_band_r4
		5:
			return _elo_band_r5
		_:
			return 0


## 仅首次为支持的策略层级写入初始评分，并持久化初始化标记。
func init_elo_rating(rank: int, initial_value: float) -> void:
	if is_elo_initialized(rank):
		return
	match rank:
		3:
			_elo_rating_r3 = initial_value
			_elo_init_r3 = true
		4:
			_elo_rating_r4 = initial_value
			_elo_init_r4 = true
		5:
			_elo_rating_r5 = initial_value
			_elo_init_r5 = true
		_:
			return
	_save_data()


## 应用评分、胜率带和局数变化，写盘后发出评分已提交信号。
func commit_elo_settlement(rank: int, new_rating: float, new_band: int) -> void:
	if not _apply_elo_rating_state(rank, new_rating, new_band):
		return
	_save_data()
	elo_rating_committed.emit(rank, new_rating)


## 只修改内存中的层级评分、累计局数和胜率带，持久化由外层负责。
func _apply_elo_rating_state(rank: int, new_rating: float, new_band: int) -> bool:
	match rank:
		3:
			_elo_rating_r3 = new_rating
			_elo_games_r3 += 1
			_elo_band_r3 = new_band
		4:
			_elo_rating_r4 = new_rating
			_elo_games_r4 += 1
			_elo_band_r4 = new_band
		5:
			_elo_rating_r5 = new_rating
			_elo_games_r5 += 1
			_elo_band_r5 = new_band
		_:
			return false
	return true


## 按关号和题目 ID 建立可恢复的评分尝试，同题再次进入保留累计行为且不重新授予资格。
func begin_elo_v2_attempt(
	level_num: int,
	puzzle_id: String,
	rank: int,
	puzzle_rating: float,
	style_vector: Dictionary,
	eligible: bool
) -> void:
	if level_num <= 0 or puzzle_id.is_empty():
		return
	if (
		int(_elo_v2_attempt.get("level", 0)) == level_num
		and str(_elo_v2_attempt.get("puzzle_id", "")) == puzzle_id
	):
		if bool(_elo_v2_attempt.get("eligible", false)) and not eligible:
			_elo_v2_attempt["eligible"] = false
			_save_data()
		return
	_elo_v2_attempt = {
		"level": level_num,
		"puzzle_id": puzzle_id,
		"rank": rank,
		"puzzle_rating": puzzle_rating,
		"eligible": eligible,
		"style_vector": style_vector.duplicate(true),
		"size": int(style_vector.get("style_size", 0)),
		"restart_count": 0,
		"used_tool": false,
		"fish_consumed": 0,
		"death_count": 0,
		"time_total": -1,
		"full_hp": false,
	}
	_save_data()


## 返回当前评分尝试的深拷贝，避免外部直接改动记录。
func get_elo_v2_attempt() -> Dictionary:
	return _elo_v2_attempt.duplicate(true)


## 仅在关号匹配时清除当前评分尝试并写盘。
func abandon_elo_v2_attempt(level_num: int) -> void:
	if int(_elo_v2_attempt.get("level", 0)) != level_num:
		return
	_elo_v2_attempt = {}
	_save_data()


## 恢复残局时取计数较大值、合并用道具标记，避免旧快照抹掉已经发生的行为。
func merge_elo_v2_resume_facts(
	restart_count: int, used_tool: bool, fish_consumed: int, death_count: int
) -> void:
	if _elo_v2_attempt.is_empty():
		return
	_elo_v2_attempt["restart_count"] = maxi(
		int(_elo_v2_attempt.get("restart_count", 0)), restart_count
	)
	_elo_v2_attempt["used_tool"] = bool(_elo_v2_attempt.get("used_tool", false)) or used_tool
	_elo_v2_attempt["fish_consumed"] = maxi(
		int(_elo_v2_attempt.get("fish_consumed", 0)), fish_consumed
	)
	_elo_v2_attempt["death_count"] = maxi(int(_elo_v2_attempt.get("death_count", 0)), death_count)
	_save_data()


## 按重开、道具、耗鱼或死亡事件更新评分尝试并立即保存。
func record_elo_v2_action(action: String) -> void:
	if _elo_v2_attempt.is_empty():
		return
	match action:
		"restart":
			_elo_v2_attempt["restart_count"] = int(_elo_v2_attempt.get("restart_count", 0)) + 1
		"tool":
			_elo_v2_attempt["used_tool"] = true
		"fish":
			_elo_v2_attempt["fish_consumed"] = int(_elo_v2_attempt.get("fish_consumed", 0)) + 1
		"death":
			_elo_v2_attempt["death_count"] = int(_elo_v2_attempt.get("death_count", 0)) + 1
		_:
			return
	_save_data()


## 把最终通关用时和是否满血写入评分尝试，供统一结算读取。
func set_elo_v2_win_facts(time_total: int, full_hp: bool) -> void:
	if _elo_v2_attempt.is_empty():
		return
	_elo_v2_attempt["time_total"] = time_total
	_elo_v2_attempt["full_hp"] = full_hp
	_save_data()


## 返回最近若干已通关题目的风格向量深拷贝，供选题去重。
func get_recent_elo_v2_won_style_vectors(limit: int) -> Array:
	var vectors: Array = []
	var start_index: int = maxi(0, _elo_v2_won_styles.size() - maxi(0, limit))
	for index: int in range(start_index, _elo_v2_won_styles.size()):
		var row: Dictionary = _elo_v2_won_styles[index]
		var vector: Dictionary = row.get("style_vector", {})
		vectors.append(vector.duplicate(true))
	return vectors


## 返回指定来源已选题目 ID 的副本。
func get_elo_v2_source_selected_ids(key: String) -> Array:
	var selected: Array = _elo_v2_source_selected_ids.get(key, [])
	return selected.duplicate()


## 对有效来源键和非负题目 ID 去重记录，新增后写盘。
func record_elo_v2_source_selected_id(key: String, entry_id: int) -> void:
	if key.is_empty() or entry_id < 0:
		return
	var selected: Array = _elo_v2_source_selected_ids.get(key, [])
	if selected.has(entry_id):
		return
	selected.append(entry_id)
	_elo_v2_source_selected_ids[key] = selected
	_save_data()


## 确认尝试仍对应当前锁题后记录胜利风格，历史最多十四条，并清尝试；由外层统一保存。
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
func get_elo_active_rank() -> int:
	return _elo_active_rank


## 返回当前交付题目的评分，供后续结算比较。
func get_elo_active_puzzle_rating() -> float:
	return _elo_active_puzzle_rating


## 保存本次交付题目的策略层级和题目评分。
func set_elo_active_delivery(rank: int, puzzle_rating: float) -> void:
	_elo_active_rank = rank
	_elo_active_puzzle_rating = puzzle_rating
	_save_data()


## 读取当前评分过程累计消耗的鱼数。
func get_elo_fish_consumed() -> int:
	return _elo_fish_consumed


## 累计耗鱼次数并写盘，避免重启丢失评分依据。
func inc_elo_fish_consumed() -> void:
	_elo_fish_consumed += 1
	_save_data()


const ELO_SELECTED_MAX: int = 2000


## 检查非空题目标识是否出现在 Elo 已选记录中。
func is_elo_pid_selected(pid_h: String) -> bool:
	return pid_h != "" and _elo_selected_pids.has(pid_h)


## 去重记录 Elo 题目标识，最多保留两千条并写盘。
func mark_elo_pid_selected(pid_h: String) -> void:
	if pid_h == "" or _elo_selected_pids.has(pid_h):
		return
	_elo_selected_pids.append(pid_h)
	while _elo_selected_pids.size() > ELO_SELECTED_MAX:
		_elo_selected_pids.pop_front()
	_save_data()


const RATING_SELECTED_MAX: int = 2000


## 检查评分带选题是否已经使用过该非空题目标识。
func is_rating_pid_selected(pid_h: String) -> bool:
	return pid_h != "" and _rating_selected_pids.has(pid_h)


## 记录评分带选题标识并限制历史长度，默认写盘，批量提交可延后。
func mark_rating_pid_selected(pid_h: String, persist: bool = true) -> void:
	if pid_h == "" or _rating_selected_pids.has(pid_h):
		return
	_rating_selected_pids.append(pid_h)
	while _rating_selected_pids.size() > RATING_SELECTED_MAX:
		_rating_selected_pids.pop_front()
	if persist:
		_save_data()


## 返回当前保存的评分带已选题目数量。
func get_rating_selected_count() -> int:
	return _rating_selected_pids.size()


## 是否用过道具（首次使用会记下来）
func has_used_tool() -> bool:
	return _has_used_tool


## 道具高亮引导是否已展示
func has_prop_highlight_shown() -> bool:
	return _prop_highlight_shown


## 标记道具高亮引导已展示
func mark_prop_highlight_shown() -> void:
	if _prop_highlight_shown:
		return
	_prop_highlight_shown = true
	_save_data()


func has_prop_highlight_hinted_today() -> bool:
	return _prop_highlight_hint_date == _today_str()


func mark_prop_highlight_hinted_today() -> void:
	var today: String = _today_str()
	if _prop_highlight_hint_date == today:
		return
	_prop_highlight_hint_date = today
	_save_data()


## 取推送授权询问次数
func get_push_ask_count() -> int:
	return _push_ask_count


## 推送授权询问次数 +1
func inc_push_ask_count() -> void:
	_push_ask_count += 1
	_save_data()


func mark_push_guide_triggered() -> void:
	_push_guide_last_date = _today_str()
	_push_guide_shown_count += 1
	_save_data()


func get_push_guide_shown_count() -> int:
	return _push_guide_shown_count


func mark_push_guide_popup_shown() -> void:
	_push_guide_popup_count += 1
	_save_data()


func get_push_guide_popup_count() -> int:
	return _push_guide_popup_count


func is_push_guide_cooldown_elapsed() -> bool:
	if _push_guide_last_date.is_empty():
		return true
	var last_unix: int = Time.get_unix_time_from_datetime_string(
		_push_guide_last_date + "T00:00:00"
	)
	var today_unix: int = Time.get_unix_time_from_datetime_string(_today_str() + "T00:00:00")
	return today_unix - last_unix >= 5 * 86400


func set_tool_count(kind: String, count: int) -> void:
	var prev: int = get_tool_count(kind)
	if not _write_tool_field(kind, count):
		return

	if kind != ToolKind.DRAFT and kind != ToolKind.MOUSE and count < prev and not _has_used_tool:
		_has_used_tool = true
	_save_data()

	tool_count_changed.emit(kind, get_tool_count(kind))


func _write_tool_field(kind: String, count: int) -> bool:
	var clamped_count: int = clampi(count, 0, TOOL_COUNT_MAX)
	match kind:
		ToolKind.LOCATE:
			_tool_locate = clamped_count
		ToolKind.HINT:
			_tool_hint = clamped_count
		ToolKind.MOUSE:
			_tool_mouse = clamped_count
		ToolKind.DRAFT:
			_tool_draft = clamped_count
		_:
			return false
	return true


func exchange_tool_all(from_kind: String, to_kind: String) -> int:
	if from_kind == to_kind:
		return 0
	if not ToolKind.is_valid(from_kind) or not ToolKind.is_valid(to_kind):
		push_error("GameState.exchange_tool_all: 非法道具 kind, from=%s to=%s" % [from_kind, to_kind])
		return 0
	var moved: int = get_tool_count(from_kind)
	if moved <= 0:
		return 0
	var to_total: int = get_tool_count(to_kind) + moved
	_write_tool_field(from_kind, 0)
	_write_tool_field(to_kind, to_total)
	_save_data()

	tool_count_changed.emit(from_kind, get_tool_count(from_kind))
	tool_count_changed.emit(to_kind, get_tool_count(to_kind))
	return moved


## 取「发放中」奖励的快照（AwardManager 防重复发用）
func get_in_flight_awards() -> Array:
	return _in_flight_awards.duplicate()


## 登记一条发放中的奖励
func add_in_flight_award(entry: Dictionary) -> void:
	_in_flight_awards.append(entry)
	_save_data()


## 按 uid 移除发放中的奖励（从后往前找第一个匹配）
func remove_in_flight_award(uid: int) -> void:
	for i in range(_in_flight_awards.size() - 1, -1, -1):
		if int(_in_flight_awards[i].get("uid", -1)) == uid:
			_in_flight_awards.remove_at(i)
			_save_data()
			return


## 按 uid 查发放中的奖励，找不到返回空字典
func find_in_flight_award(uid: int) -> Dictionary:
	for entry: Dictionary in _in_flight_awards:
		if int(entry.get("uid", -1)) == uid:
			return entry
	return {}


func get_splash_durations() -> Array:
	return _splash_durations.duplicate()


func push_splash_duration(sec: float) -> void:
	if sec <= 0.0:
		return
	_splash_durations.append(sec)
	while _splash_durations.size() > SPLASH_DURATION_LIMIT:
		_splash_durations.pop_front()
	_save_data()


func _sanitize_splash_durations(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for item: Variant in raw as Array:
		if not (item is float or item is int):
			continue
		var sec: float = float(item)
		if sec > 0.0:
			out.append(sec)
	while out.size() > SPLASH_DURATION_LIMIT:
		out.pop_front()
	return out


# ================= 闪屏 / 语言 / 首次启动 / 设置 =================
## 取最近展示闪屏的日期
func get_last_splash_date() -> String:
	return _last_splash_date


## 记录最近展示闪屏的日期
func set_last_splash_date(value: String) -> void:
	_last_splash_date = value
	_save_data()


## 取已应用过的语言代码
func get_apply_locale() -> String:
	return _apply_locale


## 记录已应用的语言代码
func set_apply_locale(value: String) -> void:
	_apply_locale = value
	_save_data()


## 本次运行是否算首次启动（冷启动期间有效，不落盘）
func is_first_session() -> bool:
	return _first_session_runtime


## 本次运行内关掉首次启动标记（不写盘，UniKitManager 用来决定是否上报首启）
func mark_first_session_done() -> void:
	if not _first_session_runtime:
		return
	_first_session_runtime = false


## 把持久化的首次启动标记置 false（Launcher 启动时调一次）
func consume_first_session_persist() -> void:
	if not _is_first_session:
		return
	_is_first_session = false
	_save_data()


## 今天是否还没开过第一关
func is_today_first_level() -> bool:
	return _last_first_level_date != _today_str()


## 消耗「今日第一关」资格（记日期）
func consume_today_first_level() -> void:
	var today: String = _today_str()
	if _last_first_level_date == today:
		return
	_last_first_level_date = today
	_save_data()


## 音乐开关是否开启
func is_music_on() -> bool:
	return _music_on


func set_music_on(value: bool) -> void:
	var changed: bool = _music_on != value
	_music_on = value
	_music_user_modified = true
	_save_data()
	if changed:
		_emit_switch_toggle("music", value, "")


func apply_music_switch(default_on: bool) -> void:
	if _music_user_modified:
		return
	if _music_on == default_on:
		return
	_music_on = default_on
	_save_data()

	_emit_switch_toggle("music", default_on, "ab_default")


## 音效开关是否开启
func is_sound_on() -> bool:
	return _sound_on


func set_sound_on(value: bool) -> void:
	var changed: bool = _sound_on != value
	_sound_on = value
	_save_data()
	if changed:
		_emit_switch_toggle("sound", value, "")


## 震动开关是否开启
func is_vibration_on() -> bool:
	return _vibration_on


## 设置震动开关，并同步给 VibrateManager
func set_vibration_on(value: bool) -> void:
	_vibration_on = value
	VibrateManager.set_enabled(value)
	_save_data()


## people 开关是否开启
func is_people_on() -> bool:
	return _people_on


func set_people_on(value: bool) -> void:
	var changed: bool = _people_on != value
	_people_on = value
	_save_data()
	if changed:
		_emit_switch_toggle("people", value, "")


func _emit_switch_toggle(switch_name: String, on: bool, src: String) -> void:
	if not is_instance_valid(EventBus):
		return
	var payload: Dictionary = {"name": switch_name, "on": on}
	if src != "":
		payload["src"] = src
	EventBus.emit_event(EventName.SETTING_TOGGLE, payload)


func get_golden_fish_streak_count() -> int:
	return _golden_fish_streak_count


func get_golden_fish_pending() -> bool:
	return _golden_fish_pending


func has_golden_fish_tutorial_shown() -> bool:
	return _golden_fish_tutorial_shown


func get_onefish_consecutive_wins() -> int:
	return _onefish_consecutive_wins


func get_onefish_consecutive_skips() -> int:
	return _onefish_consecutive_skips


func is_onefish_spawn_suppressed() -> bool:
	return _onefish_spawn_suppressed


func clear_onefish_timing_state() -> void:
	if (
		_onefish_consecutive_wins == 0
		and _onefish_consecutive_skips == 0
		and not _onefish_spawn_suppressed
		and _golden_fish_streak_count == 0
	):
		return
	_onefish_consecutive_wins = 0
	_onefish_consecutive_skips = 0
	_onefish_spawn_suppressed = false
	_golden_fish_streak_count = 0
	_save_data()


func mark_golden_fish_tutorial_shown() -> void:
	if _golden_fish_tutorial_shown:
		return
	_golden_fish_tutorial_shown = true
	_save_data()


## 读取指定尺寸和策略层级的一命关顺序游标，未记录时从零开始。
func get_onefish_index(sz: int, rank: int) -> int:
	return int(_onefish_progress.get("%d_%d" % [sz, rank], 0))


## 查询该尺寸、层级和题目索引对应的使用位。
func is_onefish_used(sz: int, rank: int, idx: int) -> bool:
	return _is_used_bit("%d_%d" % [sz, rank], idx)


## 从当前游标环形查找未使用题目，全用过时回到起点；空题库返回 -1。
func next_onefish_sequential_draw(sz: int, rank: int, count: int) -> int:
	if count <= 0:
		return -1
	var key: String = "%d_%d" % [sz, rank]
	var start: int = int(_onefish_progress.get(key, 0)) % count
	for step in count:
		var probe: int = (start + step) % count
		if not _is_used_bit(key, probe):
			return probe
	return start


## 按每字节八题读取位图，负索引或位图未覆盖的位置视为未使用。
func _is_used_bit(key: String, idx: int) -> bool:
	if idx < 0:
		return false
	var bits: PackedByteArray = _onefish_used_bits.get(key, PackedByteArray())
	@warning_ignore("integer_division")
	var byte_at: int = idx / 8
	if byte_at >= bits.size():
		return false
	return (bits[byte_at] & (1 << (idx % 8))) != 0


## 统计指定题库范围内已经置位的题目数量。
func get_onefish_used_count(sz: int, rank: int, count: int) -> int:
	return _count_used_bits(_onefish_used_bits.get("%d_%d" % [sz, rank], PackedByteArray()), count)


## 枚举使用位图中所有已标记的题目索引。
func get_onefish_used_indices(sz: int, rank: int) -> Array:
	var bits: PackedByteArray = _onefish_used_bits.get("%d_%d" % [sz, rank], PackedByteArray())
	var used: Array = []
	for i in bits.size() * 8:
		@warning_ignore("integer_division")
		var byte_at: int = i / 8
		if (bits[byte_at] & (1 << (i % 8))) != 0:
			used.append(i)
	return used


## 读取该尺寸和层级已经循环过的题库轮数。
func get_onefish_cycle_round(sz: int, rank: int) -> int:
	return int(_onefish_cycle_rounds.get("%d_%d" % [sz, rank], 0))


## 返回上次取题组切换时累计交付的一命关数量。
func get_onefish_pick_switch_anchor() -> int:
	return _onefish_pick_switch_anchor


## 确保洗牌池有效后预览当前题目索引与轮数，不在这里推进游标。
func next_onefish_shuffle_draw(sz: int, rank: int, count: int) -> Dictionary:
	if count <= 0:
		return {}
	var key: String = "%d_%d" % [sz, rank]
	_ensure_onefish_shuffle(key, count)
	var order: Array = _onefish_shuffle_orders.get(key, [])
	var cursor: int = int(_onefish_shuffle_cursors.get(key, 0))
	if order.is_empty() or cursor < 0 or cursor >= order.size():
		return {}
	return {
		"idx": int(order[cursor]),
		"round": int(_onefish_cycle_rounds.get(key, 0)),
	}


## 确认交付后推进洗牌游标、标记题目已用并累计交付数，可延后统一保存。
func commit_onefish_shuffle_delivery(
	sz: int, rank: int, idx: int, count: int, persist: bool = true
) -> void:
	var key: String = "%d_%d" % [sz, rank]
	_onefish_shuffle_cursors[key] = int(_onefish_shuffle_cursors.get(key, 0)) + 1
	_mark_onefish_used(key, idx, count)
	_golden_fish_insert_delivered += 1
	if persist:
		_save_data()


## 返回洗牌顺序副本、游标、轮数、实验组和已使用索引，供调试查看。
func get_onefish_shuffle_debug(sz: int, rank: int) -> Dictionary:
	var key: String = "%d_%d" % [sz, rank]
	var order: Array = _onefish_shuffle_orders.get(key, [])
	return {
		"order": order.duplicate(),
		"cursor": int(_onefish_shuffle_cursors.get(key, 0)),
		"round": int(_onefish_cycle_rounds.get(key, 0)),
		"group": _onefish_shuffle_group,
		"used": get_onefish_used_indices(sz, rank),
	}


## 取题组变化时清洗牌缓存、记录切组交付锚点并保存。
func note_onefish_pick_group(group: int) -> void:
	if group == _onefish_shuffle_group:
		return
	_onefish_shuffle_orders = {}
	_onefish_shuffle_cursors = {}
	_onefish_shuffle_group = group

	_onefish_pick_switch_anchor = _golden_fish_insert_delivered
	_save_data()


## 洗牌池缺失、耗尽或与未使用题数不一致时重建并写盘。
func _ensure_onefish_shuffle(key: String, count: int) -> void:
	var order: Array = _onefish_shuffle_orders.get(key, [])
	var cursor: int = int(_onefish_shuffle_cursors.get(key, 0))
	var unused_left: int = (
		count - _count_used_bits(_onefish_used_bits.get(key, PackedByteArray()), count)
	)

	if order.is_empty() or cursor >= order.size() or (order.size() - cursor) != unused_left:
		_shuffle_onefish_pool(key, count)
		_save_data()


## 只洗牌尚未使用的题目；一轮耗尽时清位图并推进轮数，再生成新顺序。
func _shuffle_onefish_pool(key: String, count: int) -> void:
	var indices: Array = _onefish_unused_indices(key, count)
	if indices.is_empty():
		_onefish_used_bits[key] = PackedByteArray()
		_onefish_cycle_rounds[key] = int(_onefish_cycle_rounds.get(key, 0)) + 1
		indices = _onefish_unused_indices(key, count)
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in range(indices.size() - 1, 0, -1):
		var swap_at: int = rng.randi_range(0, i)
		var moved: int = indices[i]
		indices[i] = indices[swap_at]
		indices[swap_at] = moved
	_onefish_shuffle_orders[key] = indices
	_onefish_shuffle_cursors[key] = 0


## 按使用位图枚举当前题库尚未出现的索引。
func _onefish_unused_indices(key: String, count: int) -> Array:
	var out: Array = []
	for i in count:
		if not _is_used_bit(key, i):
			out.append(i)
	return out


## 置位本次题目；整库用完时清空位图并进入下一轮。
func _mark_onefish_used(key: String, idx: int, count: int) -> void:
	if count <= 0 or idx < 0 or idx >= count:
		return
	var bits: PackedByteArray = _onefish_used_bits_of(key, count)
	@warning_ignore("integer_division")
	var byte_at: int = idx / 8
	bits[byte_at] = bits[byte_at] | (1 << (idx % 8))
	_onefish_used_bits[key] = bits
	if _count_used_bits(bits, count) >= count:
		_onefish_used_bits[key] = PackedByteArray()
		_onefish_cycle_rounds[key] = int(_onefish_cycle_rounds.get(key, 0)) + 1


## 按题目数计算位图所需字节，空间不足时复制扩容。
func _onefish_used_bits_of(key: String, count: int) -> PackedByteArray:
	@warning_ignore("integer_division")
	var need: int = (count + 7) / 8
	var bits: PackedByteArray = _onefish_used_bits.get(key, PackedByteArray())
	if bits.size() < need:
		bits = bits.duplicate()
		bits.resize(need)
	return bits


## 只统计有效题目范围内的置位数，忽略位图尾部填充位。
func _count_used_bits(bits: PackedByteArray, count: int) -> int:
	var used: int = 0
	for i in count:
		@warning_ignore("integer_division")
		var byte_at: int = i / 8
		if byte_at < bits.size() and (bits[byte_at] & (1 << (i % 8))) != 0:
			used += 1
	return used


func get_golden_fish_insert_delivered() -> int:
	return _golden_fish_insert_delivered


func get_golden_fish_career_count() -> int:
	return _golden_fish_career_count


func get_color_challenge_since_gf() -> int:
	return _color_challenge_since_gf


func get_color_challenge_pending() -> bool:
	return _color_challenge_pending


func get_color_challenge_delivered() -> int:
	return _color_challenge_delivered


func get_color_challenge_index(sz: int, rank: int) -> int:
	return int(_color_challenge_progress.get("%d_%d" % [sz, rank], 0))


func get_color_challenge_skip_count() -> int:
	return _color_challenge_skip_count


func has_color_challenge_deferred_used() -> bool:
	return _color_challenge_deferred_used


func get_color_challenge_defer_until() -> int:
	return _color_challenge_defer_until


func is_color_challenge_disabled() -> bool:
	return _color_challenge_disabled


func get_pattern_mode_before_color_challenge() -> int:
	return _pattern_mode_before_color_challenge


func _advance_golden_fish_career_mut() -> void:
	_golden_fish_career_count += 1
	_color_challenge_since_gf = ColorChallengeGate.since_gf_after_golden_fish()


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


func _migrate_color_challenge_quiet_rule_mut() -> void:
	if not _color_challenge_deferred_used and not _color_challenge_disabled:
		return
	print(
		(
			"[ColorChallenge] 防打扰规则变更迁移:清旧状态(deferred_used=%s disabled=%s defer_until=%d)"
			% [
				str(_color_challenge_deferred_used),
				str(_color_challenge_disabled),
				_color_challenge_defer_until
			]
		)
	)
	_color_challenge_deferred_used = false
	_color_challenge_disabled = false
	_color_challenge_defer_until = 0


func commit_color_challenge_delivery(sz: int, rank: int) -> void:
	var cursor_key: String = "%d_%d" % [sz, rank]
	_color_challenge_progress[cursor_key] = int(_color_challenge_progress.get(cursor_key, 0)) + 1
	_color_challenge_delivered += 1

	_save_data()


func commit_color_challenge_override_delivery() -> void:
	_color_challenge_delivered += 1
	_save_data()


func begin_color_challenge_pattern_mode() -> void:
	if _pattern_mode_before_color_challenge >= 0:
		return
	_pattern_mode_before_color_challenge = 1 if _pattern_mode_on else 0

	_pattern_mode_on = true
	_save_data()


func restore_pattern_mode_after_color_challenge() -> void:
	if _restore_pattern_mode_mut():
		_save_data()


func _restore_pattern_mode_mut() -> bool:
	if _pattern_mode_before_color_challenge < 0:
		return false
	_pattern_mode_on = _pattern_mode_before_color_challenge == 1
	_pattern_mode_before_color_challenge = -1
	return true


func cheat_force_color_challenge_pending() -> void:
	_color_challenge_pending = true
	_save_data()


func cheat_unlock_color_challenge() -> void:
	if _golden_fish_career_count >= ColorChallengeGate.UNLOCK_GOLDEN_FISH_COUNT:
		return
	_golden_fish_career_count = ColorChallengeGate.UNLOCK_GOLDEN_FISH_COUNT
	_save_data()


func cheat_reset_color_challenge_career() -> void:
	_color_challenge_delivered = 0
	_color_challenge_progress = {}
	_color_challenge_skip_count = 0
	_color_challenge_deferred_used = false
	_color_challenge_defer_until = 0
	_color_challenge_disabled = false
	_save_data()


func cheat_force_golden_fish_pending() -> void:
	_golden_fish_pre_cat_session = {}
	_golden_fish_pending = true
	_golden_fish_streak_count = 0

	clear_endgame_snapshot()
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_save_data()


func cheat_reset_golden_fish_career() -> void:
	_golden_fish_pre_cat_session = {}
	_golden_fish_streak_count = 0
	_golden_fish_pending = false
	_golden_fish_tutorial_shown = false
	_golden_fish_insert_delivered = 0
	_onefish_progress = {}

	_onefish_shuffle_orders = {}
	_onefish_shuffle_cursors = {}
	_onefish_cycle_rounds = {}
	_onefish_used_bits = {}
	_onefish_shuffle_group = -1
	_onefish_pick_switch_anchor = 0

	_golden_fish_career_count = 0
	clear_golden_fish_endgame_snapshot()
	_save_data()


func commit_onefish_delivery(
	sz: int, rank: int, idx: int, count: int, persist: bool = true
) -> void:
	var key := "%d_%d" % [sz, rank]
	_onefish_progress[key] = int(_onefish_progress.get(key, 0)) + 1
	_mark_onefish_used(key, idx, count)
	_golden_fish_insert_delivered += 1
	if persist:
		_save_data()


func advance_golden_fish_streak(level: int) -> void:
	_advance_golden_fish_streak_mut(level)
	_save_data()


func _advance_golden_fish_streak_mut(level: int) -> void:
	var enabled: bool = ABTestManager.golden_fish_func.is_enabled()

	var timing: GoldenFishTimingConfig = ABTestManager.golden_fish_timing
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


func on_golden_fish_skipped(level: int) -> void:
	if _is_golden_fish_pre_cat_active(level):
		_golden_fish_pre_cat_session["skipped"] = true
		_set_pre_cat_pending_mut(
			get_golden_fish_pre_cat_followup(
				level,
				ABTestManager.golden_fish_precat.includes_golden_fish(),
				ABTestManager.golden_fish_precat.isolates_golden_fish()
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
	clear_golden_fish_endgame_snapshot()


func clear_golden_fish_state() -> void:
	clear_golden_fish_pre_cat_session()

	clear_golden_fish_endgame_snapshot()
	var retry_cleared: bool = _clear_onefish_retry_puzzle()
	if _golden_fish_streak_count == 0 and not _golden_fish_pending:
		if retry_cleared:
			_save_data()
		return
	_golden_fish_streak_count = 0
	_golden_fish_pending = false
	_save_data()


func clear_onefish_retry_puzzle_on_pick_switch() -> void:
	clear_golden_fish_pre_cat_session()
	var retry_cleared: bool = _clear_onefish_retry_puzzle()
	var endgame_cleared: bool = clear_golden_fish_endgame_snapshot()

	if retry_cleared or endgame_cleared:
		_save_data()


func _clear_onefish_retry_puzzle() -> bool:
	if _retry_puzzle_params.is_empty():
		return false
	if str(_retry_puzzle_params.get("bank_source", "")) != GoldenFishGate.INSERT_BANK_SOURCE:
		return false
	print("[GoldenFish] 切组清插入关锁题 lv=%d" % _retry_puzzle_level)
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	return true


func clear_golden_fish_endgame_snapshot() -> bool:
	if _endgame_snapshot.is_empty():
		return false
	var kind: int = int(_endgame_snapshot.get("kind", LevelKind.default_kind()))
	if not LevelKind.is_golden_fish(kind):
		return false
	clear_endgame_snapshot()
	return true


func on_color_challenge_settled() -> void:
	_color_challenge_pending = false
	_reset_color_challenge_quiet_streak_mut("通关")

	_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED

	_restore_pattern_mode_mut()
	_save_data()


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
	clear_color_challenge_endgame_snapshot()


func clear_color_challenge_state(reset_skip_count: bool) -> void:
	clear_color_challenge_endgame_snapshot()
	var retry_cleared: bool = _clear_color_challenge_retry_puzzle()

	var pattern_restored: bool = _restore_pattern_mode_mut()
	var had_quiet_state: bool = (
		_color_challenge_skip_count != 0
		or _color_challenge_deferred_used
		or _color_challenge_defer_until != 0
		or _color_challenge_disabled
	)
	if (
		_color_challenge_since_gf == ColorChallengeGate.NOT_STARTED
		and not _color_challenge_pending
		and not (reset_skip_count and had_quiet_state)
	):
		if retry_cleared or pattern_restored:
			_save_data()
		return
	_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED
	_color_challenge_pending = false
	if reset_skip_count:
		_color_challenge_skip_count = 0
		_color_challenge_deferred_used = false
		_color_challenge_defer_until = 0
		_color_challenge_disabled = false
	_save_data()


func _clear_color_challenge_retry_puzzle() -> bool:
	if _retry_puzzle_params.is_empty():
		return false
	if (
		str(_retry_puzzle_params.get("bank_source", "")) != ColorChallengeGate.BANK_SOURCE
		and not bool(_retry_puzzle_params.get("_returnee_color_override", false))
	):
		return false
	print("[ColorChallenge] 清颜色挑战锁题 lv=%d" % _retry_puzzle_level)
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	return true


func clear_color_challenge_endgame_snapshot() -> bool:
	if _endgame_snapshot.is_empty():
		return false
	var kind: int = int(_endgame_snapshot.get("kind", LevelKind.default_kind()))
	if not LevelKind.is_color_challenge(kind):
		return false
	clear_endgame_snapshot()
	return true


# ================= 仅内存的局内状态（重启即丢） =================
## 是否调试模式：非 rel 构建恒为 true
func is_debug_mode() -> bool:
	return _debug_mode or not OS.has_feature("rel")


## 设置调试模式（不写盘）
func set_debug_mode(value: bool) -> void:
	_debug_mode = value


## 本局是否动过道具/复活
func is_current_level_dirty() -> bool:
	return _current_level_dirty


## 标记本局已「弄脏」（打断干净通关连击）
func mark_current_level_dirty() -> void:
	_current_level_dirty = true


## 清掉弄脏标记（重开或继续本局时）
func clear_current_level_dirty() -> void:
	_current_level_dirty = false


## 标记本局用过道具或复活（DDA 降档判据）
func mark_dda_tool_or_revive_used() -> void:
	_dda_tool_or_revive_used = true


func is_dda_tool_or_revive_used() -> bool:
	return _dda_tool_or_revive_used


## 标记本局用过复活
func mark_dda_revive_used() -> void:
	_dda_revive_used = true


## 把本局标记为「每日首次降档局」
func mark_daily_first_easy_level() -> void:
	_is_daily_first_easy_level = true


## 本局是否走了每日首次降档
func is_current_level_daily_first_easy() -> bool:
	return _is_daily_first_easy_level


func set_chain_g2_pending(value: bool) -> void:
	_chain_g2_pending = value


func consume_chain_g2_pending() -> bool:
	var pending: bool = _chain_g2_pending
	_chain_g2_pending = false
	return pending


func mark_g4_pressure_level(level_num: int) -> void:
	_g4_pressure_level_num = level_num


func is_g4_pressure_level(level_num: int) -> bool:
	return _g4_pressure_level_num > 0 and _g4_pressure_level_num == level_num


func set_g4_defer_pending(value: bool) -> void:
	_g4_defer_pending = value


func consume_g4_defer_pending() -> bool:
	var pending: bool = _g4_defer_pending
	_g4_defer_pending = false
	return pending


func set_sr_dda_pending(rank: int, is_upgrade: bool) -> void:
	_sr_dda_pending_rank = rank
	_sr_dda_pending_is_upgrade = is_upgrade


func get_sr_dda_pending_rank() -> int:
	return _sr_dda_pending_rank


func get_sr_dda_pending_is_upgrade() -> bool:
	return _sr_dda_pending_is_upgrade


func persist_user_tag_state() -> void:
	_save_data()


func inc_11503_r3_played_count() -> void:
	_11503_r3_played_count += 1
	_save_data()


func inc_11503_r4_played_count() -> void:
	_11503_r4_played_count += 1
	_save_data()


func compute_11503_r3_probs() -> Vector2:
	var adj: int = _11503_r3_played_count / 2
	var r2: float = clampf(50.0 - 5.0 * adj, 30.0, 50.0)
	return Vector2(r2, 100.0 - r2)


func compute_11503_r4_probs() -> Vector3:
	var adj: int = _11503_r4_played_count / 2
	var r2: float = clampf(24.0 - 1.125 * adj, 15.0, 24.0)
	var r3: float = clampf(56.0 - 1.375 * adj, 45.0, 56.0)
	var r4: float = clampf(20.0 + 2.5 * adj, 20.0, 40.0)
	return Vector3(r2, r3, r4)


func compute_11503_r3_weights() -> PackedInt32Array:
	var adj: int = _11503_r3_played_count / 2
	var w_r2: int = clampi(400 - 40 * adj, 240, 400)
	var w_r3: int = 800 - w_r2
	return PackedInt32Array([w_r2, w_r3])


func compute_11503_r4_weights() -> PackedInt32Array:
	var adj: int = _11503_r4_played_count / 2
	var w_r2: int = clampi(192 - 9 * adj, 120, 192)
	var w_r3: int = clampi(448 - 11 * adj, 360, 448)
	var w_r4: int = clampi(160 + 20 * adj, 160, 320)
	return PackedInt32Array([w_r2, w_r3, w_r4])


## 本局是否是重试局
func is_current_level_retried() -> bool:
	return _current_level_retried


## 存下重试本关要复用的题库参数（会写盘）
func set_retry_puzzle(level: int, params: Dictionary) -> void:
	_retry_puzzle_level = level
	_retry_puzzle_params = params
	_save_data()


## 取某关的重试参数；关卡号不匹配或没存过就返回空字典
func get_retry_puzzle(level: int) -> Dictionary:
	if _retry_puzzle_level == level and not _retry_puzzle_params.is_empty():
		return _retry_puzzle_params
	return {}


func has_wrong_cat_current_level() -> bool:
	return _current_wrong_cat_num > 0


func inc_current_wrong_cat_num() -> void:
	_current_wrong_cat_num += 1
	_save_data()


func has_insert_golden_fish_wrong_cat() -> bool:
	return _insert_golden_fish_wrong_cat_num > 0


func inc_insert_golden_fish_wrong_cat_num() -> void:
	_insert_golden_fish_wrong_cat_num += 1
	_save_data()


func clear_retry_puzzle() -> void:
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_save_data()


func get_pre_cat_pending() -> Dictionary:
	return {
		"hard": _pre_cat_pending_hard,
		"struggle": _pre_cat_pending_struggle,
		"demote": _pre_cat_pending_demote
	}


func begin_golden_fish_pre_cat_session(level_num: int, preserve_source: bool = false) -> void:
	if level_num <= 0:
		return
	if _is_golden_fish_pre_cat_active(level_num):
		return
	_golden_fish_pre_cat_session = {
		"level": level_num,
		"source": get_pre_cat_pending(),
		"preserve_source": preserve_source,
		"fail_count": 0,
		"revived": false,
		"entered": true,
		"skipped": false,
		"won": false,
		"lock": {},
		"fx_played": false
	}
	_save_data()


## 金鱼预放猫会话必须关号匹配且尚未通关或跳过，才算仍在进行中。
func _is_golden_fish_pre_cat_active(level_num: int) -> bool:
	return (
		not _golden_fish_pre_cat_session.is_empty()
		and int(_golden_fish_pre_cat_session.get("level", 0)) == level_num
		and not bool(_golden_fish_pre_cat_session.get("won", false))
		and not bool(_golden_fish_pre_cat_session.get("skipped", false))
	)


## 检查指定关号是否存在已经通关或跳过的金鱼预放猫会话。
func has_golden_fish_pre_cat_followup(level_num: int) -> bool:
	return (
		level_num > 0
		and int(_golden_fish_pre_cat_session.get("level", 0)) == level_num
		and (
			bool(_golden_fish_pre_cat_session.get("won", false))
			or bool(_golden_fish_pre_cat_session.get("skipped", false))
		)
	)


## 按是否进入、跳过和隔离来源规则，决定后续主线继承原预放来源还是依据金鱼失败表现生成来源。
func get_golden_fish_pre_cat_followup(
	level_num: int, include_golden_fish: bool, preserve_source: bool
) -> Dictionary:
	if not has_golden_fish_pre_cat_followup(level_num):
		return {}
	if (
		not bool(_golden_fish_pre_cat_session.get("entered", true))
		or preserve_source
		or (include_golden_fish and bool(_golden_fish_pre_cat_session.get("skipped", false)))
	):
		return (_golden_fish_pre_cat_session.get("source", {}) as Dictionary).duplicate(true)
	return {
		"hard": false,
		"demote": false,
		"struggle":
		(
			include_golden_fish
			and (
				int(_golden_fish_pre_cat_session.get("fail_count", 0)) >= 2
				or bool(_golden_fish_pre_cat_session.get("revived", false))
			)
		)
	}


## 仅对仍活跃的金鱼会话返回原预放来源的深拷贝。
func get_golden_fish_pre_cat_source(level_num: int) -> Dictionary:
	if not _is_golden_fish_pre_cat_active(level_num):
		return {}
	var source: Dictionary = _golden_fish_pre_cat_session.get("source", {}).duplicate(true)
	return source


## 返回金鱼预放猫会话的完整深拷贝。
func get_golden_fish_pre_cat_session() -> Dictionary:
	return _golden_fish_pre_cat_session.duplicate(true)


## 会话非空时清除并保存，避免后续主线误继承旧来源。
func clear_golden_fish_pre_cat_session() -> void:
	if _golden_fish_pre_cat_session.is_empty():
		return
	_golden_fish_pre_cat_session = {}
	_save_data()


## 优先读取金鱼结束后的后续来源，再消费主线待触发标记。
func consume_main_pre_cat_pending(
	level_num: int = 0, include_golden_fish: bool = false, preserve_source: bool = false
) -> Dictionary:
	var pending: Dictionary = (
		get_golden_fish_pre_cat_followup(level_num, include_golden_fish, preserve_source)
		if has_golden_fish_pre_cat_followup(level_num)
		else get_pre_cat_pending()
	)
	consume_pre_cat_pending()
	return pending


## 把输入字典映射到困难、挣扎和降档三种预放来源，仅修改内存。
func _set_pre_cat_pending_mut(pending: Dictionary) -> void:
	_pre_cat_pending_hard = bool(pending.get("hard", false))
	_pre_cat_pending_struggle = bool(pending.get("struggle", false))
	_pre_cat_pending_demote = bool(pending.get("demote", false))


## 为活跃金鱼会话记录已经复活并保存，重复调用不再写盘。
func mark_golden_fish_pre_cat_revived(level_num: int) -> void:
	if (
		not _is_golden_fish_pre_cat_active(level_num)
		or bool(_golden_fish_pre_cat_session.get("revived", false))
	):
		return
	_golden_fish_pre_cat_session["revived"] = true
	_save_data()


## 只在会话活跃且题目键一致时返回预放锁定结果副本。
func get_golden_fish_pre_cat_lock(level_num: int, puzzle_key: String) -> Dictionary:
	if not _is_golden_fish_pre_cat_active(level_num):
		return {}
	var lock: Dictionary = _golden_fish_pre_cat_session.get("lock", {})
	return lock.duplicate(true) if str(lock.get("puzzle_key", "")) == puzzle_key else {}


## 保存当前金鱼题目的预放位置、来源和许可状态，并重置动画播放标记。
func set_golden_fish_pre_cat_lock(
	level_num: int,
	puzzle_key: String,
	pre_type: String,
	position: Vector2i,
	allow_pre_cat: bool = true,
	pending: Dictionary = {}
) -> void:
	if not _is_golden_fish_pre_cat_active(level_num):
		return
	_golden_fish_pre_cat_session["lock"] = {
		"locked": true,
		"puzzle_key": puzzle_key,
		"pre_type": pre_type,
		"position": position,
		"allow_pre_cat": allow_pre_cat,
		"pending": pending.duplicate(true)
	}
	_golden_fish_pre_cat_session["fx_played"] = false
	_save_data()


## 仅对记录中的关号返回预放猫失败计数，其他关返回零。
func get_pre_cat_fail_count(lv: int) -> int:
	return _pre_cat_fail_count if _pre_cat_fail_lv == lv else 0


## 首次记录本局用过复活并保存，供下局预放猫判定。
func mark_pre_cat_revived() -> void:
	if _pre_cat_revived_this_level:
		return
	_pre_cat_revived_this_level = true
	_save_data()


## 返回三种待触发来源后清空它们，有实际变化时保存，避免重复消费。
func consume_pre_cat_pending() -> Dictionary:
	var out: Dictionary = {
		"hard": _pre_cat_pending_hard,
		"struggle": _pre_cat_pending_struggle,
		"demote": _pre_cat_pending_demote,
	}
	if _pre_cat_pending_hard or _pre_cat_pending_struggle or _pre_cat_pending_demote:
		_pre_cat_pending_hard = false
		_pre_cat_pending_struggle = false
		_pre_cat_pending_demote = false
		_save_data()
	return out


## 优先使用金鱼后续主线的来源匹配锁，否则按关号返回常规锁定位置。
func get_pre_cat_lock(lv: int, pending: Dictionary = {}) -> Dictionary:
	if has_golden_fish_pre_cat_followup(lv):
		var main_lock: Dictionary = _golden_fish_pre_cat_session.get("main_lock", {})
		if bool(main_lock.get("locked", false)) and main_lock.get("pending", {}) == pending:
			return main_lock.duplicate(true)
		return {"locked": false, "pre_type": "0", "position": Vector2i(-1, -1)}
	if lv > 0 and _pre_cat_lock_lv == lv:
		return {"locked": true, "pre_type": _pre_cat_lock_pre_type, "position": _pre_cat_lock_pos}
	return {"locked": false, "pre_type": "0", "position": Vector2i(-1, -1)}


## 记录主线预放位置与来源；存在金鱼后续会话时也保存该来源对应的锁。
func set_pre_cat_lock(
	lv: int, pre_type: String, position: Vector2i, pending: Dictionary = {}
) -> void:
	_pre_cat_lock_lv = lv
	_pre_cat_lock_pre_type = pre_type
	_pre_cat_lock_pos = position
	if has_golden_fish_pre_cat_followup(lv):
		_golden_fish_pre_cat_session["main_lock"] = {
			"locked": true,
			"pre_type": pre_type,
			"position": position,
			"pending": pending.duplicate(true)
		}
	_save_data()


## 按普通或插入金鱼玩法读取本局预放猫动画是否已播放。
func is_pre_cat_fx_played(lv: int, kind: int = LevelKind.MAIN) -> bool:
	if LevelKind.is_insert_golden_fish(kind):
		return (
			_is_golden_fish_pre_cat_active(lv)
			and bool(_golden_fish_pre_cat_session.get("fx_played", false))
		)
	return lv > 0 and _pre_cat_fx_played_lv == lv


## 按玩法分别记录预放动画已播放并保存，防止重进时重复播放。
func mark_pre_cat_fx_played(lv: int, kind: int = LevelKind.MAIN) -> void:
	if LevelKind.is_insert_golden_fish(kind):
		if _is_golden_fish_pre_cat_active(lv) and not is_pre_cat_fx_played(lv, kind):
			_golden_fish_pre_cat_session["fx_played"] = true
			_save_data()
		return
	if lv <= 0 or _pre_cat_fx_played_lv == lv:
		return
	_pre_cat_fx_played_lv = lv
	_save_data()


# ================= 结算文案缓存（同一关只算一次，不落盘） =================
## 取缓存的击败百分比（-1 表示没缓存）
func get_start_toast_pct(level: int, kind: String) -> float:
	var bucket: Dictionary = _start_toast_pct.get(level, {})
	return float(bucket.get(kind, -1.0))


## 缓存开局提示的击败百分比（不落盘）
func set_start_toast_pct(level: int, kind: String, pct: float) -> void:
	var bucket: Dictionary = _start_toast_pct.get(level, {})
	bucket[kind] = pct
	_start_toast_pct[level] = bucket


## 清开局提示缓存（level < 0 表示全清）
func clear_start_toast_pct(level: int = -1) -> void:
	if level < 0:
		_start_toast_pct.clear()
	else:
		_start_toast_pct.erase(level)


## 取开局提示选中的 IQ 文案下标（0 表示没缓存）
func get_start_toast_iq_idx(level: int) -> int:
	return int(_start_toast_iq_idx.get(level, 0))


## 缓存开局提示的 IQ 文案下标
func set_start_toast_iq_idx(level: int, idx: int) -> void:
	_start_toast_iq_idx[level] = idx


## 清 IQ 文案下标缓存（level < 0 表示全清）
func clear_start_toast_iq_idx(level: int = -1) -> void:
	if level < 0:
		_start_toast_iq_idx.clear()
	else:
		_start_toast_iq_idx.erase(level)


func get_start_toast_variant_idx(level: int, group: int, kind_h: String) -> int:
	var bucket: Dictionary = _start_toast_variant_idx.get(level, {})
	var k: String = "%d_%s" % [group, kind_h]
	return int(bucket.get(k, -1))


func set_start_toast_variant_idx(level: int, group: int, kind_h: String, idx: int) -> void:
	var bucket: Dictionary = _start_toast_variant_idx.get(level, {})
	var k: String = "%d_%s" % [group, kind_h]
	bucket[k] = idx
	_start_toast_variant_idx[level] = bucket


func get_start_toast_variant_pct(level: int, group: int, kind_h: String, idx: int) -> float:
	var bucket: Dictionary = _start_toast_variant_pct.get(level, {})
	var k: String = "%d_%s_%d" % [group, kind_h, idx]
	return float(bucket.get(k, -1.0))


func set_start_toast_variant_pct(
	level: int, group: int, kind_h: String, idx: int, pct: float
) -> void:
	var bucket: Dictionary = _start_toast_variant_pct.get(level, {})
	var k: String = "%d_%s_%d" % [group, kind_h, idx]
	bucket[k] = pct
	_start_toast_variant_pct[level] = bucket


func clear_start_toast_variant_state(level: int = -1) -> void:
	if level < 0:
		_start_toast_variant_idx.clear()
		_start_toast_variant_pct.clear()
	else:
		_start_toast_variant_idx.erase(level)
		_start_toast_variant_pct.erase(level)


func get_dc_start_toast_pct(scene: String, idx: int) -> float:
	var cache_key: String = "%s_%d" % [scene, idx]
	return float(_dc_start_toast_pct.get(cache_key, -1.0))


func set_dc_start_toast_pct(scene: String, idx: int, pct: float) -> void:
	var cache_key: String = "%s_%d" % [scene, idx]
	_dc_start_toast_pct[cache_key] = pct


func clear_dc_start_toast_pct() -> void:
	_dc_start_toast_pct.clear()


func get_toast_hold_text_sig() -> int:
	return _toast_hold_text_sig


func set_toast_hold_text_sig(v: int) -> void:
	_toast_hold_text_sig = v
	_save_data()


func get_toast_shown_keys() -> PackedStringArray:
	return _toast_shown_keys


func add_toast_shown_key(key: String) -> void:
	if key.is_empty() or _toast_shown_keys.has(key):
		return
	_toast_shown_keys.append(key)
	_save_data()


func clear_toast_shown_keys() -> void:
	_toast_shown_keys = PackedStringArray()
	_save_data()


## 取失败页文案缓存的横坐标（-1 表示没缓存）
func get_fail_text_revive_x(level: int) -> float:
	return float(_fail_text_revive_x.get(level, -1.0))


## 缓存失败页文案的横坐标（不落盘）
func set_fail_text_revive_x(level: int, x: float) -> void:
	_fail_text_revive_x[level] = x


## 清失败页文案坐标缓存（level < 0 表示全清）
func clear_fail_text_revive_x(level: int = -1) -> void:
	if level < 0:
		_fail_text_revive_x.clear()
	else:
		_fail_text_revive_x.erase(level)


## 取最近一次通关的击败百分比（-1 = 无）
func get_last_win_beat_percent() -> float:
	return _last_win_beat_percent


## 记录最近一次通关的击败百分比
func set_last_win_beat_percent(pct: float) -> void:
	_last_win_beat_percent = pct
	_save_data()


func get_pass_anim_cat_cycle_count() -> int:
	return _pass_anim_cat_cycle_count


func advance_pass_anim_cat_cycle() -> void:
	_pass_anim_cat_cycle_count += 1
	_save_data()


func sync_pass_anim_cat_cycle_group(group: int) -> void:
	if _pass_anim_cat_cycle_group == group:
		return

	print(
		(
			"[PassAnimCat] 分组 %d → %d,循环位置归零(作废 count=%d)"
			% [_pass_anim_cat_cycle_group, group, _pass_anim_cat_cycle_count]
		)
	)
	_pass_anim_cat_cycle_count = 0
	_pass_anim_cat_cycle_group = group
	_save_data()


# ================= 帮助与版本信息 =================
## 取最近打开帮助的时间戳
func get_help_last_open_time() -> int:
	return _help_last_open_time


## 记录最近打开帮助的时间戳
func set_help_last_open_time(value: int) -> void:
	_help_last_open_time = value
	_save_data()


## 取首次记录到的安装包版本号
func get_install_version() -> String:
	return _install_version


## 只在第一次写入安装包版本号（版本号为空则忽略）
func ensure_install_version(version: String) -> void:
	if not _install_version.is_empty():
		return
	if version.is_empty():
		return
	_install_version = version
	_save_data()


func resolve_version_upgrade(cur: String) -> void:
	if cur.is_empty():
		push_warning("GameState.resolve_version_upgrade: cur 版本号为空，跳过升级检测")
		return

	var pre_before_bump: String = _game_version_pre
	if (
		(pre_before_bump.is_empty() or _compare_version_str(pre_before_bump, VERSION_1_14_0) < 0)
		and _compare_version_str(cur, VERSION_1_14_0) >= 0
	):
		_music_user_modified = false
	if _compare_version_str(cur, _game_version_pre) > 0:
		_game_version_pre = cur

	_save_data()


func get_game_version_pre() -> String:
	return _game_version_pre


static func _compare_version_str(a: String, b: String) -> int:
	var pa: PackedStringArray = a.split(".")
	var pb: PackedStringArray = b.split(".")
	var n: int = maxi(pa.size(), pb.size())
	for i in range(n):
		var va: int = pa[i].to_int() if i < pa.size() else 0
		var vb: int = pb[i].to_int() if i < pb.size() else 0
		if va > vb:
			return 1
		if va < vb:
			return -1
	return 0


## 取连续干净通关次数
func get_consecutive_clean_wins() -> int:
	return _consecutive_clean_wins


## 上一关是否干净通关
func was_last_level_clean_win() -> bool:
	return _last_level_clean_win


# ================= 题库游标 =================
## 取题库游标：key = "尺寸_段位[_H]"，缺省 0（H = 困难组）
func get_bank_index(sz: int, rank: int, tier: String = "") -> int:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	return _bank_progress.get(key, 0)


func advance_bank_index(sz: int, rank: int, tier: String = "", persist: bool = true) -> void:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_bank_progress[key] = _bank_progress.get(key, 0) + 1
	if persist:
		_save_data()


## 取新版题库进度，没有就建默认值 {"lk_mod":0,"regular":0,"lkstyle":0,"transform":0}
func get_main_progress(sz: int, rank: int, tier: String = "") -> Dictionary:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	if not _main_bank_progress.has(key):
		_main_bank_progress[key] = {"lk_mod": 0, "regular": 0, "lkstyle": 0, "transform": 0}
	return _main_bank_progress[key]


func set_main_progress(
	sz: int, rank: int, tier: String, progress: Dictionary, persist: bool = true
) -> void:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_main_bank_progress[key] = progress
	if persist:
		_save_data()


func ensure_super_hard_anchor(level_num: int) -> int:
	if _super_hard_anchor <= 0:
		_super_hard_anchor = level_num
		_save_data()
	return _super_hard_anchor


func get_super_hard_anchor() -> int:
	return _super_hard_anchor


## 取 lkmod 玩法进度，没有就建默认值 {"idx":0}
func get_lkmod_progress(sz: int, rank: int) -> Dictionary:
	var key := "%d_%d" % [sz, rank]
	if not _lkmod_progress.has(key):
		_lkmod_progress[key] = {"idx": 0}
	return _lkmod_progress[key]


func set_lkmod_progress(sz: int, rank: int, progress: Dictionary, persist: bool = true) -> void:
	var key := "%d_%d" % [sz, rank]
	_lkmod_progress[key] = progress
	if persist:
		_save_data()


## 取旧版题库游标的深拷贝快照
func get_bank_progress_snapshot() -> Dictionary:
	return _bank_progress.duplicate(true)


## 取新版题库进度的深拷贝快照
func get_main_bank_progress_snapshot() -> Dictionary:
	return _main_bank_progress.duplicate(true)


## 取 lkmod 进度的深拷贝快照
func get_lkmod_progress_snapshot() -> Dictionary:
	return _lkmod_progress.duplicate(true)


## 深拷贝旧题库、主题库和 LK 改题库游标，供试选题时临时回滚。
func get_level_selection_progress_snapshot() -> Dictionary:
	return {
		"bank_progress": _bank_progress.duplicate(true),
		"main_bank_progress": _main_bank_progress.duplicate(true),
		"lkmod_progress": _lkmod_progress.duplicate(true),
	}


## 从快照深拷贝恢复三类题库游标，仅恢复内存，不在此处写盘。
func restore_level_selection_progress(snapshot: Dictionary) -> void:
	_bank_progress = (snapshot.get("bank_progress", {}) as Dictionary).duplicate(true)
	_main_bank_progress = (snapshot.get("main_bank_progress", {}) as Dictionary).duplicate(true)
	_lkmod_progress = (snapshot.get("lkmod_progress", {}) as Dictionary).duplicate(true)


## 读取下一次 SP_TT 交付使用的分类游标。
func get_sp_tt_category_cursor() -> int:
	return _sp_tt_category_cursor


## 读取最近被 SP_TT 特殊题替换的主线关号。
func get_sp_tt_last_replaced_level() -> int:
	return _sp_tt_last_replaced_level


## 按分类、尺寸、层级取得进度引用，缺失时创建题目与变换位置为零的进度。
func get_sp_tt_progress(category: int, sz: int, rank: int) -> Dictionary:
	var key := "%d_%d_%d" % [category, sz, rank]
	if not _sp_tt_progress.has(key):
		_sp_tt_progress[key] = {"idx": 0, "t_pos": 0}
	return _sp_tt_progress[key]


## 同时提交分类题库进度、下个分类游标和替换关号，再统一写盘。
func commit_sp_tt_delivery(
	level_num: int, category: int, sz: int, rank: int, progress: Dictionary, next_cursor: int
) -> void:
	_sp_tt_progress["%d_%d_%d" % [category, sz, rank]] = progress
	_sp_tt_category_cursor = next_cursor
	_sp_tt_last_replaced_level = level_num
	_save_data()


## 提交回流期间 SP_TT 进度与分类游标，不更新常规替换关号。
func commit_returnee_sp_tt_delivery(
	category: int, sz: int, rank: int, progress: Dictionary, next_cursor: int
) -> void:
	_sp_tt_progress["%d_%d_%d" % [category, sz, rank]] = progress
	_sp_tt_category_cursor = next_cursor
	_save_data()


## 返回单格区域补充题库进度引用，缺失时创建零索引。
func get_single_region_supp_progress(sz: int, rank: int) -> Dictionary:
	var key := "%d_%d" % [sz, rank]
	if not _single_region_supp_progress.has(key):
		_single_region_supp_progress[key] = {"idx": 0}
	return _single_region_supp_progress[key]


## 返回 Elo 单格区域辅助题库进度，缺失时创建零索引。
func get_elo_aux_single_region_progress(sz: int, rank: int) -> Dictionary:
	var key := "%d_%d" % [sz, rank]
	if not _elo_aux_single_region_progress.has(key):
		_elo_aux_single_region_progress[key] = {"idx": 0}
	return _elo_aux_single_region_progress[key]


## 更新 Elo 单格区域辅助题库进度并保存。
func commit_elo_aux_single_region_delivery(sz: int, rank: int, progress: Dictionary) -> void:
	_elo_aux_single_region_progress["%d_%d" % [sz, rank]] = progress
	_save_data()


## 返回 Elo 高潮辅助题库进度，缺失时初始化索引与变换位置。
func get_elo_aux_climax_progress(sz: int, rank: int) -> Dictionary:
	var key := "%d_%d" % [sz, rank]
	if not _elo_aux_climax_progress.has(key):
		_elo_aux_climax_progress[key] = {"idx": 0, "t_pos": 0}
	return _elo_aux_climax_progress[key]


## 提交 Elo 高潮辅助题库进度并保存。
func commit_elo_aux_climax_delivery(sz: int, rank: int, progress: Dictionary) -> void:
	_elo_aux_climax_progress["%d_%d" % [sz, rank]] = progress
	_save_data()


## 提交单格区域补充题库进度并保存。
func commit_single_region_supp_delivery(sz: int, rank: int, progress: Dictionary) -> void:
	_single_region_supp_progress["%d_%d" % [sz, rank]] = progress
	_save_data()


## 按尺寸、层级和单格数量取得高潮筛选题库进度引用。
func get_climax_filter_progress(sz: int, rank: int, single_count: int) -> Dictionary:
	var key := "%d_%d_%d" % [sz, rank, single_count]
	if not _climax_filter_progress.has(key):
		_climax_filter_progress[key] = {"idx": 0, "t_pos": 0}
	return _climax_filter_progress[key]


## 提交对应筛选条件下的高潮题库进度并保存。
func commit_climax_filter_delivery(
	sz: int, rank: int, single_count: int, progress: Dictionary
) -> void:
	_climax_filter_progress["%d_%d_%d" % [sz, rank, single_count]] = progress
	_save_data()


## 读取 LK 改题库第二组最近替换的主线关号。
func get_lk_mod_g2_last_replaced_level() -> int:
	return _lk_mod_g2_last_replaced_level


## 提交 LK 改题库索引及最近替换关号，再写盘。
func commit_lk_mod_g2_delivery(level_num: int, sz: int, rank: int, new_idx: int) -> void:
	_lkmod_progress["%d_%d" % [sz, rank]] = {"idx": new_idx}
	_lk_mod_g2_last_replaced_level = level_num
	_save_data()


## 读取 SP_TT 与 LK 交替规则最近替换的关号。
func get_sp_tt_lk_alt_last_replaced_level() -> int:
	return _sp_tt_lk_alt_last_replaced_level


## 读取交替取题当前连续段使用的题库来源。
func get_sp_tt_lk_alt_block_source() -> String:
	return _sp_tt_lk_alt_block_source


## 读取交替取题当前连续段已交付的数量。
func get_sp_tt_lk_alt_block_count() -> int:
	return _sp_tt_lk_alt_block_count


## 统一提交交替取题的关号、来源和连续段计数。
func commit_sp_tt_lk_alt_delivery(level_num: int, new_source: String, new_count: int) -> void:
	_sp_tt_lk_alt_last_replaced_level = level_num
	_sp_tt_lk_alt_block_source = new_source
	_sp_tt_lk_alt_block_count = new_count
	_save_data()


## 读取降档后等待特殊题替换的关号。
func get_downgrade_special_pending_level() -> int:
	return _downgrade_special_pending_level


## 记录待替换特殊题的关号并保存。
func set_downgrade_special_pending_level(value: int) -> void:
	_downgrade_special_pending_level = value
	_save_data()


## 返回普通关耗时窗口的深拷贝，供 DDA 计算。
func get_normal_pass_time_records() -> Array:
	return _normal_pass_time_records.duplicate(true)


## 每个关号只记一次有效耗时，最多保留十条记录并写盘。
func record_normal_pass_time(level_num: int, size: int, rank: int, sec: int) -> void:
	if level_num <= 0 or size <= 0:
		return
	for record: Dictionary in _normal_pass_time_records:
		if int(record.get("level", 0)) == level_num:
			return
	_normal_pass_time_records.append({"level": level_num, "size": size, "rank": rank, "sec": sec})
	while _normal_pass_time_records.size() > NORMAL_PASS_TIME_LIMIT:
		_normal_pass_time_records.pop_front()
	_save_data()


## 读取已保存的 11701 实验洗牌种子，零表示尚未建立。
func get_nl11701_shuffle_seed() -> int:
	return _nl11701_shuffle_seed


## 首次生成非零随机种子并保存，使后续重启沿用同一洗牌依据。
func ensure_nl11701_shuffle_seed() -> int:
	if _nl11701_shuffle_seed != 0:
		return _nl11701_shuffle_seed
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s: int = 0
	while s == 0:
		s = rng.randi()
	_nl11701_shuffle_seed = s
	_save_data()
	return _nl11701_shuffle_seed


## 读取第六版难度规则已经交付的交替 R4 题数。
func get_nl_v6_alternate_r4_count() -> int:
	return _nl_v6_alternate_r4_count


## 同一关重选时扣除它此前的贡献，取得本次交付前的计数。
func get_nl_v6_alternate_r4_count_before(level_num: int) -> int:
	if _nl_v6_alternate_r4_level == level_num:
		return _nl_v6_alternate_r4_count - 1
	return _nl_v6_alternate_r4_count


## 根据本次是否主线 R4 更新交替计数，同关重选先回退旧贡献，可延后写盘。
func record_nl_v6_alternate_delivery(
	level_num: int, is_main_r4: bool, persist: bool = true
) -> void:
	var base_count: int = get_nl_v6_alternate_r4_count_before(level_num)
	if is_main_r4:
		_nl_v6_alternate_r4_count = base_count + 1
		_nl_v6_alternate_r4_level = level_num
	else:
		_nl_v6_alternate_r4_count = base_count
		if _nl_v6_alternate_r4_level == level_num:
			_nl_v6_alternate_r4_level = 0
	if persist:
		_save_data()


## 返回第六版题池进度引用，缺失时创建索引和变换编号为零的记录。
func get_nl_v6_pool_progress(key: String) -> Dictionary:
	if not _nl_v6_pool_progress.has(key):
		_nl_v6_pool_progress[key] = {"idx": 0, "transform": 0}
	return _nl_v6_pool_progress[key]


## 写入第六版题池进度，默认持久化，可由外层合并保存。
func set_nl_v6_pool_progress(key: String, progress: Dictionary, persist: bool = true) -> void:
	_nl_v6_pool_progress[key] = progress
	if persist:
		_save_data()


## 返回第六版交替题池状态深拷贝，默认包含空 ID 列表和零轮数。
func get_nl_v6_alt_state(key: String) -> Dictionary:
	var state: Dictionary = _nl_v6_alt_state.get(key, {"ids": [], "round": 0})
	return state.duplicate(true)


## 深拷贝保存交替题池状态，避免外部后续修改影响存档。
func set_nl_v6_alt_state(key: String, state: Dictionary, persist: bool = true) -> void:
	_nl_v6_alt_state[key] = state.duplicate(true)
	if persist:
		_save_data()


## 取最近出题记录的深拷贝
func get_recent_puzzles() -> Array:
	return _recent_puzzles.duplicate(true)


## 返回当前保存的近期选题记录数量。
func get_recent_puzzle_count() -> int:
	return _recent_puzzles.size()


## 从最近若干选题记录收集非空同构签名，嵌套签名仍引用原记录。
func get_recent_iso_signatures(limit: int) -> Array:
	var result: Array = []
	var start: int = maxi(0, _recent_puzzles.size() - limit)
	for i: int in range(start, _recent_puzzles.size()):
		var sig: Array = _recent_puzzles[i].get("iso_sig", [])
		if not sig.is_empty():
			result.append(sig)
	return result


## 从最近选题记录提取有效步骤组成、顺序与尺寸，供相似风格筛选。
func get_recent_style_vectors(limit: int) -> Array:
	var result: Array = []
	var start: int = maxi(0, _recent_puzzles.size() - limit)
	for i: int in range(start, _recent_puzzles.size()):
		var record: Dictionary = _recent_puzzles[i]
		var hist: Array = record.get("style_hist", [])
		var order_z: Array = record.get("style_order_z", [])
		if not hist.is_empty() and not order_z.is_empty():
			(
				result
				. append(
					{
						"stepHist": hist,
						"stepOrderZ": order_z,
						"style_size": int(record.get("style_size", -1)),
					}
				)
			)
	return result


## 从新到旧寻找题目 ID，返回首个匹配记录的深拷贝。
func find_recent_puzzle(puzzle_id: String) -> Dictionary:
	for i: int in range(_recent_puzzles.size() - 1, -1, -1):
		var entry: Dictionary = _recent_puzzles[i]
		if entry.get("puzzle_id", "") == puzzle_id:
			return entry.duplicate(true)
	return {}


func get_latest_selected_normal_level_group(level_num: int) -> int:
	for i: int in range(_recent_puzzles.size() - 1, -1, -1):
		var entry: Dictionary = _recent_puzzles[i]
		if int(entry.get("level", -1)) == level_num:
			return int(entry.get("nl", -1))
	return -1


## 深拷贝记录题目、选题时各游标和时间，同时设置重试锁题参数，最后统一写盘。
func finalize_selected_puzzle(
	level_num: int, puzzle_record: Dictionary, retry_params: Dictionary
) -> void:
	var record: Dictionary = puzzle_record.duplicate(true)
	record["level"] = level_num
	record["ts"] = int(Time.get_unix_time_from_system())
	record["bank_progress"] = _bank_progress.duplicate(true)
	record["main_bank_progress"] = _main_bank_progress.duplicate(true)
	record["lkmod_progress"] = _lkmod_progress.duplicate(true)
	record["sp_tt_progress"] = _sp_tt_progress.duplicate(true)
	_recent_puzzles.append(record)
	while _recent_puzzles.size() > RECENT_PUZZLES_LIMIT:
		_recent_puzzles.pop_front()
	_retry_puzzle_level = level_num
	_retry_puzzle_params = retry_params.duplicate(true)
	_save_data()


## 取残局快照（返回引用）
func get_endgame_snapshot() -> Dictionary:
	return _endgame_snapshot


## 为普通残局补应用版本号，保存传入字典引用并立即写入残局档。
func set_endgame_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.is_empty():
		snapshot["app_version"] = UniKitManager.get_version_name()
	_endgame_snapshot = snapshot
	_save_endgame()

	print("[Endgame] saved\n%s" % JSON.stringify(snapshot))


## 清残局快照（本局真正结束/重开时调用）
func clear_endgame_snapshot() -> void:
	if _endgame_snapshot.is_empty():
		return
	_endgame_snapshot = {}
	_save_endgame()
	print("[Endgame] cleared")


## 返回每日残局字典引用，调用方需通过设置入口持久化变更。
func get_daily_endgame_snapshot() -> Dictionary:
	return _daily_endgame_snapshot


## 为每日残局补应用版本号，立即写盘并记录关键局面摘要。
func set_daily_endgame_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.is_empty():
		snapshot["app_version"] = UniKitManager.get_version_name()
	_daily_endgame_snapshot = snapshot
	_save_endgame()
	print(
		(
			"[DailyEndgame] saved cats=%d lives=%d elapsed=%d"
			% [
				(snapshot.get("placed_cats", []) as Array).size(),
				int(snapshot.get("lives", 0)),
				int(snapshot.get("elapsed_sec", 0)),
			]
		)
	)


## 每日残局非空时清除并写盘，不影响普通残局字段。
func clear_daily_endgame_snapshot() -> void:
	if _daily_endgame_snapshot.is_empty():
		return
	_daily_endgame_snapshot = {}
	_save_endgame()
	print("[DailyEndgame] cleared")


## 同时检查两种残局、统计、步骤和对局编号，决定残局文件是否还需保留。
func _is_endgame_store_empty() -> bool:
	return (
		_endgame_snapshot.is_empty()
		and _daily_endgame_snapshot.is_empty()
		and _main_game_total_stats.is_empty()
		and _daily_game_total_stats.is_empty()
		and _main_game_round_stats.is_empty()
		and _daily_game_round_stats.is_empty()
		and _main_solution_steps.is_empty()
		and _daily_solution_steps.is_empty()
		and _main_game_id.is_empty()
		and _daily_game_id.is_empty()
	)


## 取消合并计时并立即保存普通及每日局状态；全部为空时删除单槽残局文件。
func _save_endgame() -> void:
	_endgame_dirty = false
	if _endgame_coalesce_timer != null:
		_endgame_coalesce_timer.stop()
	if _is_endgame_store_empty():
		_endgame_store.remove()
		return
	var cfg := ConfigFile.new()
	cfg.set_value("snapshot", "data", _endgame_snapshot)
	cfg.set_value("daily_snapshot", "data", _daily_endgame_snapshot)
	cfg.set_value("stats", "main_total", _main_game_total_stats)
	cfg.set_value("stats", "daily_total", _daily_game_total_stats)
	cfg.set_value("stats", "main_round", _main_game_round_stats)
	cfg.set_value("stats", "daily_round", _daily_game_round_stats)
	cfg.set_value("stats", "main_steps", _main_solution_steps)
	cfg.set_value("stats", "daily_steps", _daily_solution_steps)
	cfg.set_value("stats", "main_id", _main_game_id)
	cfg.set_value("stats", "daily_id", _daily_game_id)
	_endgame_store.save_config(cfg)


## 请求写 endgame 槽：只置脏标志并启动 0.5 秒合并定时器，避免频繁写盘
func _request_save_endgame() -> void:
	_endgame_dirty = true
	if _endgame_coalesce_timer != null and _endgame_coalesce_timer.is_stopped():
		_endgame_coalesce_timer.start()


## 合并计时到点：脏了才真正写盘
func _on_endgame_coalesce_timeout() -> void:
	if _endgame_dirty:
		_save_endgame()


## 读取残局独立槽覆盖兼容字段；没有独立槽但已有旧字段时补写迁移结果。
func _resolve_endgame_store() -> void:
	var ecfg := _endgame_store.load_config()
	if ecfg != null:
		_endgame_snapshot = ecfg.get_value("snapshot", "data", {})
		_daily_endgame_snapshot = ecfg.get_value("daily_snapshot", "data", {})
		_main_game_total_stats = ecfg.get_value("stats", "main_total", {})
		_daily_game_total_stats = ecfg.get_value("stats", "daily_total", {})
		_main_game_round_stats = ecfg.get_value("stats", "main_round", {})
		_daily_game_round_stats = ecfg.get_value("stats", "daily_round", {})
		_main_solution_steps = ecfg.get_value("stats", "main_steps", {})
		_daily_solution_steps = ecfg.get_value("stats", "daily_steps", {})
		_main_game_id = ecfg.get_value("stats", "main_id", "")
		_daily_game_id = ecfg.get_value("stats", "daily_id", "")
	elif not _is_endgame_store_empty():
		_save_endgame()


## 系统通知：切后台或收到关闭请求时，把还没落盘的 endgame 数据立刻写掉
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _endgame_dirty:
			_save_endgame()


## 完成通关结算和回流保护后，发出主线胜利与统一结算信号，供其他模块更新。
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
					ABTestManager.normal_endgame_save.value()
					== NormalEndgameSaveConfig.VALUE_STALE_NEW_EASIER_TWO_DAYS
				)
			)
			or (
				not _returnee_from_endgame_save
				and _returnee_group == ABTestManager.normal_level.value()
			)
		)
	)
	_apply_level_won(level_num, kind, this_session_rank, this_session_diffi, full_hp, win_date)
	if returnee_level:
		_preserve_returnee_settlement()
		_returnee_current_level = 0
		_returnee_from_endgame_save = false
		_save_data()
	main_level_won.emit(settled_game_id, kind, win_date)

	level_settled.emit(true)


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
		GambleUserTag.update_after_main_level_won(
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
		and (LevelSelector.is_hard_level(level_num) or _is_super_hard_as_hard(level_num))
	)

	if (
		not dda_excluded
		and not _is_dda_excluded_super_hard(level_num)
		and not _is_dda_excluded_g4_pressure(level_num)
		and level_num >= _strategy_engagement_min_level()
	):
		var max_strategy: int = LevelSelector.max_strategy_at(level_num)
		var win_threshold: int = 1 if level_num >= 51 else 2

		if (
			level_num >= 15
			and level_num <= 50
			and (
				ABTestManager.normal_level.value()
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
			ABTestManager.normal_level.value()
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

	Tracker.try_track_grt_level_pass(level_num)

	Tracker.try_track_grt_level_window(level_num)

	if _current_strategy < _pre_cat_strat_before:
		_pre_cat_pending_demote = true

	if not dda_excluded:
		_advance_golden_fish_streak_mut(level_num)

		_advance_color_challenge_mut(level_num, ABTestManager.color_challenge_func.group_value())

	if LevelKind.is_insert_golden_fish(kind):
		_settle_golden_fish_pre_cat_mut(level_num)
	_save_data()
	if not elo_v2_settlement.is_empty():
		elo_rating_committed.emit(
			int(elo_v2_settlement["rank"]), float(elo_v2_settlement["rating"])
		)


func _settle_golden_fish_pre_cat_mut(level_num: int) -> void:
	if int(_golden_fish_pre_cat_session.get("level", 0)) != level_num:
		_set_pre_cat_pending_mut({})
		return
	_golden_fish_pre_cat_session["won"] = true
	_set_pre_cat_pending_mut(
		get_golden_fish_pre_cat_followup(
			level_num,
			ABTestManager.golden_fish_precat.includes_golden_fish(),
			ABTestManager.golden_fish_precat.isolates_golden_fish()
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
	match ABTestManager.normal_level.value():
		NormalLevelConfig.VALUE_TOOL_NO_DEMOTE, NormalLevelConfig.VALUE_IOS_TOOL_NO_DEMOTE:
			return true
		NormalLevelConfig.VALUE_CHANNEL_ASSIST_TOOL_NO_DEMOTE, NormalLevelConfig.VALUE_IOS_CHANNEL_ASSIST_TOOL_NO_DEMOTE, NormalLevelConfig.VALUE_ASSIST_TOOL_WIN_PROMOTE:
			return HasAssistUserTag.cached_value() == 1
		_:
			return false


func _is_super_hard_as_hard(level_num: int) -> bool:
	return (
		ABTestManager.normal_level.is_super_hard_harder_active()
		and LevelSelector.is_super_hard_level(level_num)
	)


func _is_dda_excluded_super_hard(level_num: int) -> bool:
	return (
		ABTestManager.normal_level.is_super_hard_harder_active()
		and LevelSelector.is_super_hard_level(level_num)
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
					ABTestManager.normal_endgame_save.value()
					== NormalEndgameSaveConfig.VALUE_STALE_NEW_EASIER_TWO_DAYS
				)
			)
			or (
				not _returnee_from_endgame_save
				and _returnee_group == ABTestManager.normal_level.value()
			)
		)
	)
	_apply_level_failed(level_num, kind)
	if returnee_level:
		_preserve_returnee_settlement()
		_save_data()
	level_settled.emit(false)


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
		(is_golden and ABTestManager.normal_level.is_onefish_state_fix())
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
	var next_is_hard: bool = LevelSelector.is_hard_level(next_level)

	var next_is_skip: bool = (
		next_is_hard
		or LevelData.is_special_level(next_level)
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

	LevelSelector.apply_won_settlement(ctx)

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

	_pre_cat_fail_lv = 0
	_pre_cat_fail_count = 0
	_pre_cat_revived_this_level = false
	_pre_cat_pending_hard = false
	_pre_cat_pending_struggle = false
	_pre_cat_pending_demote = false
	_pre_cat_lock_lv = 0
	_pre_cat_lock_pre_type = "0"
	_pre_cat_lock_pos = Vector2i(-1, -1)
	_pre_cat_fx_played_lv = 0
	_golden_fish_pre_cat_session = {}
	_dda_tool_or_revive_used = false
	_dda_revive_used = false
	_is_daily_first_easy_level = false
	_dda_pending_demote = false
	_nl12100_restore_strategy = 0
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_start_toast_pct.clear()
	_start_toast_iq_idx.clear()
	clear_start_toast_variant_state()
	_save_data()


## 返回云同步注册使用的核心存档分区名。
func cloud_save_id() -> String:
	return "core"


## 仅按主线关号判断云端进度是否领先。
func is_cloud_ahead(cloud_data: Dictionary) -> bool:
	return int(cloud_data.get("current_level", 0)) > _current_level


const CLOUD_TOOL_KINDS: Array[String] = ["locate", "hint", "draft", "mouse"]

const CompanionSystem: GDScript = preload("res://scripts/module/home/core/home_companion_system.gd")
const CLOUD_COMPANION_KEYS: Array[String] = CompanionSystem.CLOUD_KEYS


## 返回伙伴系统已废弃的云字段副本，供合并流程清理。
func retired_cloud_keys() -> Array[String]:
	return CompanionSystem.RETIRED_CLOUD_KEYS.duplicate()


## 只导出主线进度、策略、指定道具和伙伴字段，其余本地状态不随此入口同步。
func export_cloud_data() -> Dictionary:
	var data: Dictionary = {
		"current_level": _current_level,
		"current_strategy": _current_strategy,
	}
	for kind: String in CLOUD_TOOL_KINDS:
		data["tool_" + kind] = get_tool_count(kind)

	if not _home_companion_data.is_empty():
		var companion: CompanionSystem = CompanionSystem.new(_home_companion_data)
		data.merge(companion.export_cloud())
	return data


## 仅在合并上下文明确采用云端时应用进度、道具和伙伴状态，保存后发出相应更新信号。
func merge_cloud_data(cloud_data: Dictionary, ctx: MergeContext = null) -> void:
	if cloud_data.is_empty():
		return

	if ctx == null or not ctx.use_cloud:
		return
	_current_level = int(cloud_data.get("current_level", _current_level))

	_current_strategy = int(cloud_data.get("current_strategy", _current_strategy))

	if _current_level > 1 and not _tutorial_done:
		_tutorial_done = true

	var changed_tools: Array[String] = []
	for kind: String in CLOUD_TOOL_KINDS:
		var remote_key: String = "tool_" + kind
		if not cloud_data.has(remote_key):
			continue
		var merged_count: int = int(cloud_data[remote_key])
		if merged_count == get_tool_count(kind):
			continue
		if _write_tool_field(kind, merged_count):
			changed_tools.append(kind)

	var companion_changed: bool = false
	if CompanionSystem.has_cloud_data(cloud_data):
		var companion: CompanionSystem = CompanionSystem.new(_home_companion_data)
		companion.restore_cloud(cloud_data)
		var restored: Dictionary = companion.snapshot()
		companion_changed = restored != _home_companion_data
		_home_companion_data = restored
	_save_data()
	if companion_changed:
		home_companion_changed.emit()

	for kind: String in changed_tools:
		tool_count_changed.emit(kind, get_tool_count(kind))
	cloud_progress_restored.emit(_current_level)


## 把持久化玩家字段写入 ConfigFile，再交双槽 SaveStore 保存；残局由独立入口负责。
func _save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "current_level", _current_level)
	cfg.set_value("progress", "last_hard_level", _last_hard_level)
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
	cfg.set_value("progress", "super_hard_anchor", _super_hard_anchor)
	cfg.set_value("progress", "sp_tt_category_cursor", _sp_tt_category_cursor)
	cfg.set_value("progress", "sp_tt_last_replaced_level", _sp_tt_last_replaced_level)
	cfg.set_value("progress", "sp_tt_progress", _sp_tt_progress)
	cfg.set_value("progress", "lk_mod_g2_last_replaced_level", _lk_mod_g2_last_replaced_level)
	cfg.set_value("progress", "sp_tt_lk_alt_last_replaced_level", _sp_tt_lk_alt_last_replaced_level)
	cfg.set_value("progress", "sp_tt_lk_alt_block_source", _sp_tt_lk_alt_block_source)
	cfg.set_value("progress", "sp_tt_lk_alt_block_count", _sp_tt_lk_alt_block_count)
	cfg.set_value("progress", "downgrade_special_pending_level", _downgrade_special_pending_level)
	cfg.set_value("progress", "single_region_supp_progress", _single_region_supp_progress)
	cfg.set_value("progress", "climax_filter_progress", _climax_filter_progress)
	cfg.set_value("progress", "elo_aux_single_region_progress", _elo_aux_single_region_progress)
	cfg.set_value("progress", "elo_aux_climax_progress", _elo_aux_climax_progress)
	cfg.set_value("progress", "nl11701_shuffle_seed", _nl11701_shuffle_seed)
	cfg.set_value("progress", "normal_pass_time_records", _normal_pass_time_records)
	cfg.set_value("progress", "nl12100_restore_strategy", _nl12100_restore_strategy)
	cfg.set_value("progress", "nl_v6_alternate_r4_count", _nl_v6_alternate_r4_count)
	cfg.set_value("progress", "nl_v6_alternate_r4_level", _nl_v6_alternate_r4_level)
	cfg.set_value("progress", "nl_v6_pool_progress", _nl_v6_pool_progress)
	cfg.set_value("progress", "nl_v6_alt_state", _nl_v6_alt_state)
	cfg.set_value("progress", "has_shown_rate_us", _has_shown_rate_us)
	cfg.set_value("progress", "has_used_revive_free", _has_used_revive_free)
	cfg.set_value("progress", "warn_life_shown", _warn_life_shown)
	cfg.set_value("progress", "life_plus_first_done", _life_plus_first_done)
	cfg.set_value("progress", "countdown_shown_levels", _countdown_shown_levels)
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
	cfg.set_value("progress", "tool_mouse", _tool_mouse)
	cfg.set_value("progress", "tool_draft", _tool_draft)
	cfg.set_value("progress", "tool_undo", _tool_undo)
	cfg.set_value("progress", "elo_rating_r3", _elo_rating_r3)
	cfg.set_value("progress", "elo_rating_r4", _elo_rating_r4)
	cfg.set_value("progress", "elo_rating_r5", _elo_rating_r5)
	cfg.set_value("progress", "elo_games_r3", _elo_games_r3)
	cfg.set_value("progress", "elo_games_r4", _elo_games_r4)
	cfg.set_value("progress", "elo_games_r5", _elo_games_r5)
	cfg.set_value("progress", "elo_init_r3", _elo_init_r3)
	cfg.set_value("progress", "elo_init_r4", _elo_init_r4)
	cfg.set_value("progress", "elo_init_r5", _elo_init_r5)
	cfg.set_value("progress", "elo_group2_cohort", _elo_group2_cohort)
	cfg.set_value("progress", "elo_band_r3", _elo_band_r3)
	cfg.set_value("progress", "elo_band_r4", _elo_band_r4)
	cfg.set_value("progress", "elo_band_r5", _elo_band_r5)
	cfg.set_value("progress", "elo_active_rank", _elo_active_rank)
	cfg.set_value("progress", "elo_active_puzzle_rating", _elo_active_puzzle_rating)
	cfg.set_value("progress", "elo_fish_consumed", _elo_fish_consumed)
	cfg.set_value("progress", "elo_selected_pids", _elo_selected_pids)
	cfg.set_value("progress", "rating_selected_pids", _rating_selected_pids)
	cfg.set_value("progress", "elo_boost_state", _elo_boost_state)
	cfg.set_value("progress", "elo_v2_attempt", _elo_v2_attempt)
	cfg.set_value("progress", "elo_v2_won_styles", _elo_v2_won_styles)
	cfg.set_value("progress", "elo_v2_source_selected_ids", _elo_v2_source_selected_ids)
	cfg.set_value("progress", "last_splash_date", _last_splash_date)
	cfg.set_value("progress", "splash_durations", _splash_durations)
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
	cfg.set_value("progress", "prop_highlight_hint_date", _prop_highlight_hint_date)
	cfg.set_value("progress", "push_ask_count", _push_ask_count)
	cfg.set_value("progress", "push_guide_last_date", _push_guide_last_date)
	cfg.set_value("progress", "push_guide_shown_count", _push_guide_shown_count)
	cfg.set_value("progress", "push_guide_popup_count", _push_guide_popup_count)
	cfg.set_value("progress", "recent_win_counts_by_day", _recent_win_counts_by_day)
	cfg.set_value("progress", "last_main_win_date", _last_main_win_date)
	cfg.set_value("progress", "daily_first_win_entry_date", _daily_first_win_entry_date)
	cfg.set_value("progress", "retry_puzzle_level", _retry_puzzle_level)
	cfg.set_value("progress", "retry_puzzle_params", _retry_puzzle_params)
	cfg.set_value("progress", "current_wrong_cat_num", _current_wrong_cat_num)
	cfg.set_value("progress", "insert_gf_wrong_cat_num", _insert_golden_fish_wrong_cat_num)
	cfg.set_value("progress", "pre_cat_fail_lv", _pre_cat_fail_lv)
	cfg.set_value("progress", "pre_cat_fail_count", _pre_cat_fail_count)
	cfg.set_value("progress", "pre_cat_revived_this_level", _pre_cat_revived_this_level)
	cfg.set_value("progress", "pre_cat_pending_hard", _pre_cat_pending_hard)
	cfg.set_value("progress", "pre_cat_pending_struggle", _pre_cat_pending_struggle)
	cfg.set_value("progress", "pre_cat_pending_demote", _pre_cat_pending_demote)
	cfg.set_value("progress", "pre_cat_lock_lv", _pre_cat_lock_lv)
	cfg.set_value("progress", "pre_cat_lock_pre_type", _pre_cat_lock_pre_type)
	cfg.set_value("progress", "pre_cat_lock_pos", _pre_cat_lock_pos)
	cfg.set_value("progress", "pre_cat_fx_played_lv", _pre_cat_fx_played_lv)
	cfg.set_value("progress", "golden_fish_pre_cat_session", _golden_fish_pre_cat_session)
	cfg.set_value("progress", "has_shown_att_guide", _has_shown_att_guide)
	cfg.set_value("progress", "interstitial_unlocked", _interstitial_unlocked)
	cfg.set_value("progress", "banner_unlocked", _banner_unlocked)
	cfg.set_value("progress", "has_shown_draft_onboarding", _has_shown_draft_onboarding)
	cfg.set_value("progress", "auto_mark_tutorial_done", _auto_mark_tutorial_done)
	cfg.set_value("progress", "rule_info_bar_collapsed", _rule_info_bar_collapsed)
	cfg.set_value("progress", "pattern_mode_on", _pattern_mode_on)
	print("[PATTERN_DBG] _save_data writing pattern_mode_on=%s" % _pattern_mode_on)
	cfg.set_value("progress", "pattern_entry_dot_dismissed", _pattern_entry_dot_dismissed)
	cfg.set_value("progress", "pattern_switch_dot_dismissed", _pattern_switch_dot_dismissed)
	cfg.set_value("progress", "music_entry_dot_dismissed", _music_entry_dot_dismissed)
	cfg.set_value("progress", "grt_level_d90_reported", _grt_level_d90_reported)
	cfg.set_value("progress", "grt_reported_events", _grt_reported_events)
	cfg.set_value("progress", "first_open_time_ms", _first_open_time_ms)
	cfg.set_value("progress", "recent_puzzles", _recent_puzzles)
	cfg.set_value("progress", "endgame_snapshot", {})
	cfg.set_value("progress", "chain_last_replaced_level", _chain_last_replaced_level)
	cfg.set_value("progress", "chain_g3_streak", _chain_g3_streak)
	cfg.set_value("progress", "session_count", _session_count)
	cfg.set_value("progress", "today_session_count", _today_session_count)
	cfg.set_value("progress", "last_day_session_count", _last_day_session_count)
	cfg.set_value("progress", "active_days", _active_days)
	cfg.set_value("progress", "last_login_date", _last_login_date)
	cfg.set_value("progress", "returnee_group", _returnee_group)
	cfg.set_value("progress", "returnee_from_endgame_save", _returnee_from_endgame_save)
	cfg.set_value("progress", "returnee_remaining", _returnee_remaining)
	cfg.set_value("progress", "returnee_lower", _returnee_lower)
	cfg.set_value("progress", "returnee_upper", _returnee_upper)
	cfg.set_value("progress", "returnee_frozen_strategy", _returnee_frozen_strategy)
	cfg.set_value("progress", "returnee_current_level", _returnee_current_level)
	cfg.set_value("progress", "returnee_lkmod_resume_level", _returnee_lkmod_resume_level)
	cfg.set_value("progress", "returnee_frozen_dda", _returnee_frozen_dda)
	cfg.set_value("progress", "today_played_count", _today_played_count)
	cfg.set_value("progress", "today_active_sec", _today_active_sec)
	cfg.set_value("progress", "today_cat_found", _today_cat_found)
	cfg.set_value("progress", "today_mark_placed", _today_mark_placed)
	cfg.set_value("progress", "today_tool_consumed", _today_tool_consumed)
	cfg.set_value("progress", "today_revive_count", _today_revive_count)
	cfg.set_value("progress", "game_barrage_daily_keys", _game_barrage_daily_keys)
	cfg.set_value("progress", "today_win_stats_group", _today_win_stats_group)
	cfg.set_value("progress", "total_active_sec", _total_active_sec)
	cfg.set_value("progress", "today_date", _today_date)
	cfg.set_value("progress", "pending_rewards", _pending_rewards)
	cfg.set_value("progress", "in_flight_awards", _in_flight_awards)
	cfg.set_value("progress", "reward_history_ts", _reward_history_ts)
	cfg.set_value("progress", "restored_today_count", _restored_today_count)
	cfg.set_value("progress", "daily_auto_mark_enabled", _daily_auto_mark_enabled)
	cfg.set_value("progress", "daily_auto_mark_free_consumed", _daily_auto_mark_free_consumed)
	cfg.set_value("progress", "saved_game_auto_mark", _saved_game_auto_mark)
	cfg.set_value("progress", "saved_ab_groups", _saved_ab_groups)
	cfg.set_value("progress", "saved_peek_ab_groups", _saved_peek_ab_groups)
	cfg.set_value(
		"progress", "loading_page_test_force_longest_quote", _loading_page_test_force_longest_quote
	)
	cfg.set_value("progress", "last_win_beat_percent", _last_win_beat_percent)
	cfg.set_value("progress", "pass_anim_cat_cycle_count", _pass_anim_cat_cycle_count)
	cfg.set_value("progress", "pass_anim_cat_cycle_group", _pass_anim_cat_cycle_group)
	cfg.set_value("progress", "help_last_open_time", _help_last_open_time)
	cfg.set_value("progress", "install_version", _install_version)
	cfg.set_value("progress", "game_version_pre", _game_version_pre)
	cfg.set_value("progress", "persisted_user_tags", _persisted_user_tags)
	cfg.set_value("progress", "has_assist_confirmed", _has_assist_confirmed)
	cfg.set_value("progress", "toast_hold_text_sig", _toast_hold_text_sig)
	cfg.set_value("progress", "toast_shown_keys", _toast_shown_keys)
	cfg.set_value("progress", "golden_fish_streak_count", _golden_fish_streak_count)
	cfg.set_value("progress", "golden_fish_pending", _golden_fish_pending)
	cfg.set_value("progress", "golden_fish_tutorial_shown", _golden_fish_tutorial_shown)
	cfg.set_value("progress", "onefish_consecutive_wins", _onefish_consecutive_wins)
	cfg.set_value("progress", "onefish_consecutive_skips", _onefish_consecutive_skips)
	cfg.set_value("progress", "onefish_spawn_suppressed", _onefish_spawn_suppressed)
	cfg.set_value("progress", "onefish_progress", _onefish_progress)
	cfg.set_value("progress", "onefish_shuffle_orders", _onefish_shuffle_orders)
	cfg.set_value("progress", "onefish_shuffle_cursors", _onefish_shuffle_cursors)
	cfg.set_value("progress", "onefish_cycle_rounds", _onefish_cycle_rounds)
	cfg.set_value("progress", "onefish_used_bits", _onefish_used_bits)
	cfg.set_value("progress", "onefish_pick_switch_anchor", _onefish_pick_switch_anchor)
	cfg.set_value("progress", "onefish_shuffle_group", _onefish_shuffle_group)
	cfg.set_value("progress", "golden_fish_insert_delivered", _golden_fish_insert_delivered)
	cfg.set_value("progress", "golden_fish_career_count", _golden_fish_career_count)

	cfg.set_value("progress", "cc_since_gf", _color_challenge_since_gf)
	cfg.set_value("progress", "cc_pending", _color_challenge_pending)
	cfg.set_value("progress", "cc_delivered", _color_challenge_delivered)
	cfg.set_value("progress", "cc_progress", _color_challenge_progress)
	cfg.set_value("progress", "cc_skip_count", _color_challenge_skip_count)
	cfg.set_value("progress", "cc_deferred_used", _color_challenge_deferred_used)
	cfg.set_value("progress", "cc_defer_until", _color_challenge_defer_until)
	cfg.set_value("progress", "cc_disabled", _color_challenge_disabled)
	cfg.set_value("progress", "pattern_mode_before_cc", _pattern_mode_before_color_challenge)

	cfg.set_value("progress", "is_gamble_user", _is_gamble_user)
	cfg.set_value("progress", "early_l1_l20_bits", _early_l1_l20_bits)
	cfg.set_value("progress", "recent_hard_invalid_bits", _recent_hard_invalid_bits)
	cfg.set_value("progress", "diff_diff_r3_played_count", _11503_r3_played_count)
	cfg.set_value("progress", "diff_diff_r4_played_count", _11503_r4_played_count)

	cfg.set_value("progress", "bsz11801_cycle_hits", _bsz11801_cycle_hits)
	cfg.set_value("progress", "bsz11802_dyn_size", _bsz11802_dyn_size)
	cfg.set_value("progress", "bsz11802_last_delivered_size", _bsz11802_last_delivered_size)
	cfg.set_value("progress", "bsz11802_stuck_streak", _bsz11802_stuck_streak)

	cfg.set_value("progress", "g4_pressure_level_num", _g4_pressure_level_num)
	cfg.set_value("progress", "g4_defer_pending", _g4_defer_pending)
	cfg.set_value("progress", "home_companion_data", _home_companion_data)

	_player_store.save_config(cfg)


## 从玩家档恢复字段并兼容旧格式，最后读取独立残局槽；玩家档不可用时保留默认值。
func _load_data() -> void:
	var cfg := _player_store.load_config()
	if cfg == null:
		_resolve_endgame_store()
		return
	_current_level = cfg.get_value("progress", "current_level", 1)
	var companion_data: Variant = cfg.get_value("progress", "home_companion_data", {})
	_home_companion_data = companion_data.duplicate(true) if companion_data is Dictionary else {}
	_last_hard_level = cfg.get_value("progress", "last_hard_level", 0)
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
	_super_hard_anchor = cfg.get_value("progress", "super_hard_anchor", 0)
	_sp_tt_category_cursor = cfg.get_value("progress", "sp_tt_category_cursor", 1)
	_sp_tt_last_replaced_level = cfg.get_value("progress", "sp_tt_last_replaced_level", 0)
	_sp_tt_progress = cfg.get_value("progress", "sp_tt_progress", {})
	_lk_mod_g2_last_replaced_level = cfg.get_value("progress", "lk_mod_g2_last_replaced_level", 0)
	_sp_tt_lk_alt_last_replaced_level = cfg.get_value(
		"progress", "sp_tt_lk_alt_last_replaced_level", 0
	)
	_sp_tt_lk_alt_block_source = cfg.get_value("progress", "sp_tt_lk_alt_block_source", "sp_tt")
	_sp_tt_lk_alt_block_count = cfg.get_value("progress", "sp_tt_lk_alt_block_count", 0)
	_downgrade_special_pending_level = cfg.get_value(
		"progress", "downgrade_special_pending_level", 0
	)
	_single_region_supp_progress = cfg.get_value("progress", "single_region_supp_progress", {})
	_climax_filter_progress = cfg.get_value("progress", "climax_filter_progress", {})
	_elo_aux_single_region_progress = cfg.get_value(
		"progress", "elo_aux_single_region_progress", {}
	)
	_elo_aux_climax_progress = cfg.get_value("progress", "elo_aux_climax_progress", {})
	_nl11701_shuffle_seed = cfg.get_value("progress", "nl11701_shuffle_seed", 0)
	_normal_pass_time_records = cfg.get_value("progress", "normal_pass_time_records", [])
	_nl12100_restore_strategy = cfg.get_value("progress", "nl12100_restore_strategy", 0)
	_nl_v6_alternate_r4_count = cfg.get_value("progress", "nl_v6_alternate_r4_count", 0)
	_nl_v6_alternate_r4_level = cfg.get_value("progress", "nl_v6_alternate_r4_level", 0)
	_nl_v6_pool_progress = cfg.get_value("progress", "nl_v6_pool_progress", {})
	_nl_v6_alt_state = cfg.get_value("progress", "nl_v6_alt_state", {})
	_has_shown_rate_us = cfg.get_value("progress", "has_shown_rate_us", false)
	_has_used_revive_free = cfg.get_value("progress", "has_used_revive_free", false)
	_warn_life_shown = cfg.get_value("progress", "warn_life_shown", false)
	_life_plus_first_done = cfg.get_value("progress", "life_plus_first_done", false)
	_countdown_shown_levels = cfg.get_value("progress", "countdown_shown_levels", {})
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

	_tool_locate = clampi(int(cfg.get_value("progress", "tool_locate", 5)), 0, TOOL_COUNT_MAX)
	_tool_hint = clampi(int(cfg.get_value("progress", "tool_hint", 5)), 0, TOOL_COUNT_MAX)
	_tool_mouse = clampi(
		int(cfg.get_value("progress", "tool_mouse", _tool_mouse)), 0, TOOL_COUNT_MAX
	)

	_tool_draft = clampi(int(cfg.get_value("progress", "tool_draft", 5)), 0, TOOL_COUNT_MAX)
	_tool_undo = cfg.get_value("progress", "tool_undo", 3)
	_elo_rating_r3 = float(cfg.get_value("progress", "elo_rating_r3", 0.0))
	_elo_rating_r4 = float(cfg.get_value("progress", "elo_rating_r4", 0.0))
	_elo_rating_r5 = float(cfg.get_value("progress", "elo_rating_r5", 0.0))
	_elo_games_r3 = int(cfg.get_value("progress", "elo_games_r3", 0))
	_elo_games_r4 = int(cfg.get_value("progress", "elo_games_r4", 0))
	_elo_games_r5 = int(cfg.get_value("progress", "elo_games_r5", 0))
	_elo_init_r3 = bool(cfg.get_value("progress", "elo_init_r3", false))
	_elo_init_r4 = bool(cfg.get_value("progress", "elo_init_r4", false))
	_elo_init_r5 = bool(cfg.get_value("progress", "elo_init_r5", false))
	_elo_group2_cohort = int(cfg.get_value("progress", "elo_group2_cohort", -1))
	_elo_band_r3 = int(cfg.get_value("progress", "elo_band_r3", 0))
	_elo_band_r4 = int(cfg.get_value("progress", "elo_band_r4", 0))
	_elo_band_r5 = int(cfg.get_value("progress", "elo_band_r5", 0))
	_elo_active_rank = int(cfg.get_value("progress", "elo_active_rank", 0))
	_elo_active_puzzle_rating = float(cfg.get_value("progress", "elo_active_puzzle_rating", 0.0))
	_elo_fish_consumed = int(cfg.get_value("progress", "elo_fish_consumed", 0))
	_elo_selected_pids = cfg.get_value("progress", "elo_selected_pids", [])
	_rating_selected_pids = cfg.get_value("progress", "rating_selected_pids", [])
	_elo_boost_state = cfg.get_value("progress", "elo_boost_state", {})
	_elo_v2_attempt = cfg.get_value("progress", "elo_v2_attempt", {})
	_elo_v2_won_styles = cfg.get_value("progress", "elo_v2_won_styles", [])
	_elo_v2_source_selected_ids = cfg.get_value("progress", "elo_v2_source_selected_ids", {})
	_last_splash_date = cfg.get_value("progress", "last_splash_date", "")
	_splash_durations = _sanitize_splash_durations(
		cfg.get_value("progress", "splash_durations", [])
	)
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
	_prop_highlight_hint_date = cfg.get_value("progress", "prop_highlight_hint_date", "")
	_push_ask_count = cfg.get_value("progress", "push_ask_count", 0)
	_push_guide_last_date = cfg.get_value("progress", "push_guide_last_date", "")
	_push_guide_shown_count = cfg.get_value("progress", "push_guide_shown_count", 0)
	_push_guide_popup_count = cfg.get_value("progress", "push_guide_popup_count", 0)
	_recent_win_counts_by_day = cfg.get_value("progress", "recent_win_counts_by_day", {})
	var saved_last_main_win_date: Variant = cfg.get_value("progress", "last_main_win_date", null)
	_last_main_win_date = _resolve_last_main_win_date_from_save(
		saved_last_main_win_date, _recent_win_counts_by_day, _today_str()
	)
	_daily_first_win_entry_date = cfg.get_value("progress", "daily_first_win_entry_date", "")
	_retry_puzzle_level = cfg.get_value("progress", "retry_puzzle_level", 0)
	_current_wrong_cat_num = cfg.get_value("progress", "current_wrong_cat_num", 0)
	_insert_golden_fish_wrong_cat_num = cfg.get_value("progress", "insert_gf_wrong_cat_num", 0)
	_retry_puzzle_params = cfg.get_value("progress", "retry_puzzle_params", {})
	_pre_cat_fail_lv = cfg.get_value("progress", "pre_cat_fail_lv", 0)
	_pre_cat_fail_count = cfg.get_value("progress", "pre_cat_fail_count", 0)
	_pre_cat_revived_this_level = cfg.get_value("progress", "pre_cat_revived_this_level", false)
	_pre_cat_pending_hard = cfg.get_value("progress", "pre_cat_pending_hard", false)
	_pre_cat_pending_struggle = cfg.get_value("progress", "pre_cat_pending_struggle", false)
	_pre_cat_pending_demote = cfg.get_value("progress", "pre_cat_pending_demote", false)
	_pre_cat_lock_lv = cfg.get_value("progress", "pre_cat_lock_lv", 0)
	_pre_cat_lock_pre_type = cfg.get_value("progress", "pre_cat_lock_pre_type", "0")
	_pre_cat_lock_pos = cfg.get_value("progress", "pre_cat_lock_pos", Vector2i(-1, -1))
	_pre_cat_fx_played_lv = cfg.get_value("progress", "pre_cat_fx_played_lv", 0)
	_golden_fish_pre_cat_session = cfg.get_value("progress", "golden_fish_pre_cat_session", {})
	_has_shown_att_guide = cfg.get_value("progress", "has_shown_att_guide", false)
	_interstitial_unlocked = cfg.get_value("progress", "interstitial_unlocked", false)
	_banner_unlocked = cfg.get_value("progress", "banner_unlocked", false)
	_has_shown_draft_onboarding = cfg.get_value("progress", "has_shown_draft_onboarding", false)
	_auto_mark_tutorial_done = cfg.get_value("progress", "auto_mark_tutorial_done", false)
	_rule_info_bar_collapsed = cfg.get_value("progress", "rule_info_bar_collapsed", false)
	_pattern_mode_on = cfg.get_value("progress", "pattern_mode_on", false)
	print("[PATTERN_DBG] _load_data read pattern_mode_on=%s" % _pattern_mode_on)
	_pattern_entry_dot_dismissed = cfg.get_value("progress", "pattern_entry_dot_dismissed", false)
	_pattern_switch_dot_dismissed = cfg.get_value("progress", "pattern_switch_dot_dismissed", false)
	_music_entry_dot_dismissed = cfg.get_value("progress", "music_entry_dot_dismissed", false)
	_grt_level_d90_reported = cfg.get_value("progress", "grt_level_d90_reported", [])
	_grt_reported_events = cfg.get_value("progress", "grt_reported_events", [])
	_first_open_time_ms = cfg.get_value("progress", "first_open_time_ms", 0)
	_recent_puzzles = cfg.get_value("progress", "recent_puzzles", [])
	_endgame_snapshot = cfg.get_value("progress", "endgame_snapshot", {})
	_chain_last_replaced_level = cfg.get_value("progress", "chain_last_replaced_level", 0)
	_chain_g3_streak = cfg.get_value("progress", "chain_g3_streak", 0)
	_session_count = cfg.get_value("progress", "session_count", 0)
	_today_session_count = cfg.get_value("progress", "today_session_count", 0)
	_last_day_session_count = cfg.get_value("progress", "last_day_session_count", 0)
	_active_days = cfg.get_value("progress", "active_days", 0)
	_last_login_date = cfg.get_value("progress", "last_login_date", "")
	_returnee_group = cfg.get_value("progress", "returnee_group", 0)
	_returnee_from_endgame_save = cfg.get_value("progress", "returnee_from_endgame_save", false)
	_returnee_remaining = cfg.get_value("progress", "returnee_remaining", 0)
	_returnee_lower = cfg.get_value("progress", "returnee_lower", 1)
	_returnee_upper = cfg.get_value("progress", "returnee_upper", 1)
	_returnee_frozen_strategy = cfg.get_value("progress", "returnee_frozen_strategy", 1)
	_returnee_current_level = cfg.get_value("progress", "returnee_current_level", 0)
	_returnee_lkmod_resume_level = cfg.get_value("progress", "returnee_lkmod_resume_level", 0)
	_returnee_frozen_dda = cfg.get_value("progress", "returnee_frozen_dda", {})
	_today_played_count = cfg.get_value("progress", "today_played_count", 0)
	_today_active_sec = cfg.get_value("progress", "today_active_sec", 0)
	_today_cat_found = cfg.get_value("progress", "today_cat_found", 0)
	_today_mark_placed = cfg.get_value("progress", "today_mark_placed", 0)
	_today_tool_consumed = cfg.get_value("progress", "today_tool_consumed", 0)
	_today_revive_count = cfg.get_value("progress", "today_revive_count", 0)
	_game_barrage_daily_keys = PackedStringArray(
		cfg.get_value("progress", "game_barrage_daily_keys", PackedStringArray())
	)
	_today_win_stats_group = cfg.get_value("progress", "today_win_stats_group", -1)
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
	_saved_ab_groups = cfg.get_value("progress", "saved_ab_groups", {})
	_saved_peek_ab_groups = cfg.get_value("progress", "saved_peek_ab_groups", {})
	_loading_page_test_force_longest_quote = cfg.get_value(
		"progress", "loading_page_test_force_longest_quote", false
	)
	_last_win_beat_percent = cfg.get_value("progress", "last_win_beat_percent", -1.0)
	_pass_anim_cat_cycle_count = int(cfg.get_value("progress", "pass_anim_cat_cycle_count", 0))
	_pass_anim_cat_cycle_group = int(cfg.get_value("progress", "pass_anim_cat_cycle_group", -1))
	_help_last_open_time = cfg.get_value("progress", "help_last_open_time", 0)
	_install_version = cfg.get_value("progress", "install_version", "")
	_game_version_pre = cfg.get_value("progress", "game_version_pre", "")
	_persisted_user_tags = cfg.get_value("progress", "persisted_user_tags", {})
	_has_assist_confirmed = cfg.get_value("progress", "has_assist_confirmed", false)
	_toast_hold_text_sig = cfg.get_value("progress", "toast_hold_text_sig", -999)
	_toast_shown_keys = cfg.get_value("progress", "toast_shown_keys", PackedStringArray())

	_golden_fish_streak_count = cfg.get_value("progress", "golden_fish_streak_count", 0)
	_golden_fish_pending = cfg.get_value("progress", "golden_fish_pending", false)
	_golden_fish_tutorial_shown = cfg.get_value("progress", "golden_fish_tutorial_shown", false)
	_onefish_consecutive_wins = cfg.get_value("progress", "onefish_consecutive_wins", 0)
	_onefish_consecutive_skips = cfg.get_value("progress", "onefish_consecutive_skips", 0)
	_onefish_spawn_suppressed = cfg.get_value("progress", "onefish_spawn_suppressed", false)
	_onefish_progress = cfg.get_value("progress", "onefish_progress", {})

	_onefish_shuffle_orders = cfg.get_value("progress", "onefish_shuffle_orders", {})
	_onefish_shuffle_cursors = cfg.get_value("progress", "onefish_shuffle_cursors", {})
	_onefish_cycle_rounds = cfg.get_value("progress", "onefish_cycle_rounds", {})
	_onefish_used_bits = cfg.get_value("progress", "onefish_used_bits", {})
	_onefish_pick_switch_anchor = cfg.get_value("progress", "onefish_pick_switch_anchor", 0)
	_onefish_shuffle_group = cfg.get_value("progress", "onefish_shuffle_group", -1)
	_golden_fish_insert_delivered = cfg.get_value("progress", "golden_fish_insert_delivered", 0)
	_golden_fish_career_count = cfg.get_value("progress", "golden_fish_career_count", 0)

	_color_challenge_since_gf = cfg.get_value(
		"progress", "cc_since_gf", ColorChallengeGate.NOT_STARTED
	)
	_color_challenge_pending = cfg.get_value("progress", "cc_pending", false)
	_color_challenge_delivered = cfg.get_value("progress", "cc_delivered", 0)
	_color_challenge_progress = cfg.get_value("progress", "cc_progress", {})
	_color_challenge_skip_count = cfg.get_value("progress", "cc_skip_count", 0)
	_color_challenge_deferred_used = cfg.get_value("progress", "cc_deferred_used", false)
	_color_challenge_defer_until = cfg.get_value("progress", "cc_defer_until", 0)
	_color_challenge_disabled = cfg.get_value("progress", "cc_disabled", false)
	_migrate_color_challenge_quiet_rule_mut()
	_pattern_mode_before_color_challenge = cfg.get_value("progress", "pattern_mode_before_cc", -1)

	_is_gamble_user = cfg.get_value("progress", "is_gamble_user", -1)
	_early_l1_l20_bits = cfg.get_value("progress", "early_l1_l20_bits", [])
	_recent_hard_invalid_bits = cfg.get_value("progress", "recent_hard_invalid_bits", [])
	_11503_r3_played_count = cfg.get_value("progress", "diff_diff_r3_played_count", 0)
	_11503_r4_played_count = cfg.get_value("progress", "diff_diff_r4_played_count", 0)

	_bsz11801_cycle_hits = cfg.get_value("progress", "bsz11801_cycle_hits", 0)
	_bsz11802_dyn_size = cfg.get_value("progress", "bsz11802_dyn_size", 8)
	_bsz11802_last_delivered_size = cfg.get_value("progress", "bsz11802_last_delivered_size", 0)
	_bsz11802_stuck_streak = cfg.get_value("progress", "bsz11802_stuck_streak", 0)

	_g4_pressure_level_num = cfg.get_value("progress", "g4_pressure_level_num", 0)
	_g4_defer_pending = cfg.get_value("progress", "g4_defer_pending", false)
	_resolve_endgame_store()


# ================= 存档迁移、日期与全量重置 =================
## 迁移 user://save.cfg 时代的旧档：已有 flag 或没有旧档就跳过；迁移成功才写 flag
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


## 本地日期字符串 YYYY-MM-DD，所有跨天判断都用它
func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%d-%02d-%02d" % [dt.year, dt.month, dt.day]


## 公开当前本地日期字符串，供其他模块沿用同一日期口径。
func current_local_date() -> String:
	return _today_str()


## 有显式通关日期时使用该值，否则使用当前本地日期。
func _date_for_main_win(win_date: Variant) -> String:
	return _today_str() if win_date == null else str(win_date)


## 优先使用已存胜利日期，旧档缺字段时用今日通关计数补判。
func _resolve_last_main_win_date_from_save(
	saved_date: Variant, recent_win_counts: Dictionary, today: String
) -> String:
	if saved_date != null:
		return str(saved_date)
	return today if int(recent_win_counts.get(today, 0)) > 0 else ""


## 增加本地今日通关计数，实际保存由外层结算统一完成。
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
func reset_for_account_delete() -> void:
	var kept: Dictionary = {}
	for f: String in _DELETE_PRESERVE_FIELDS:
		var v: Variant = get(f)

		kept[f] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	reset_all()
	for f: String in kept.keys():
		set(f, kept[f])
	_save_data()
	print("[GameState] 删号清理完成:业务字段已清,保留 %d 个 SDK/风控标记" % kept.size())


## 清空玩家进度、题库记录及活动状态，保存默认档并发送全量重置信号。
func reset_all() -> void:
	_current_level = 1
	_home_companion_data = {}
	_last_hard_level = 0
	_tutorial_done = false
	_has_shown_rate_us = false
	_has_used_revive_free = false
	_warn_life_shown = false
	_life_plus_first_done = false
	_countdown_shown_levels = {}
	_current_strategy = 1
	_consecutive_clean_wins = 0
	_last_level_clean_win = false
	_consecutive_fails = 0
	_consecutive_retry_levels = 0
	_retry_tracking_strategy = 0
	_current_level_dirty = false
	_current_level_retried = false
	_chain_last_replaced_level = 0
	_chain_g3_streak = 0
	_chain_g2_pending = false
	_g4_pressure_level_num = 0
	_g4_defer_pending = false
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_pre_cat_fail_lv = 0
	_pre_cat_fail_count = 0
	_pre_cat_revived_this_level = false
	_pre_cat_pending_hard = false
	_pre_cat_pending_struggle = false
	_pre_cat_pending_demote = false
	_pre_cat_lock_lv = 0
	_pre_cat_lock_pre_type = "0"
	_pre_cat_lock_pos = Vector2i(-1, -1)
	_pre_cat_fx_played_lv = 0
	_golden_fish_pre_cat_session = {}
	_bank_progress = {}
	_main_bank_progress = {}
	_lkmod_progress = {}
	_super_hard_anchor = 0
	_sp_tt_category_cursor = 1
	_sp_tt_last_replaced_level = 0
	_sp_tt_progress = {}
	_lk_mod_g2_last_replaced_level = 0
	_sp_tt_lk_alt_last_replaced_level = 0
	_sp_tt_lk_alt_block_source = "sp_tt"
	_sp_tt_lk_alt_block_count = 0
	_downgrade_special_pending_level = 0
	_single_region_supp_progress = {}
	_climax_filter_progress = {}
	_elo_aux_single_region_progress = {}
	_elo_aux_climax_progress = {}
	_nl11701_shuffle_seed = 0
	_normal_pass_time_records = []
	_nl12100_restore_strategy = 0
	_nl_v6_alternate_r4_count = 0
	_nl_v6_alternate_r4_level = 0
	_nl_v6_pool_progress = {}
	_nl_v6_alt_state = {}
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
	_main_solution_steps = {}
	_daily_solution_steps = {}
	_main_game_id = ""
	_daily_game_id = ""
	_tool_locate = 5
	_tool_hint = 5
	_tool_mouse = 2
	_tool_draft = 5
	_tool_undo = 3
	_elo_rating_r3 = 0.0
	_elo_rating_r4 = 0.0
	_elo_rating_r5 = 0.0
	_elo_games_r3 = 0
	_elo_games_r4 = 0
	_elo_games_r5 = 0
	_elo_init_r3 = false
	_elo_init_r4 = false
	_elo_init_r5 = false
	_elo_group2_cohort = -1
	_elo_band_r3 = 0
	_elo_band_r4 = 0
	_elo_band_r5 = 0
	_elo_active_rank = 0
	_elo_active_puzzle_rating = 0.0
	_elo_fish_consumed = 0
	_elo_selected_pids = []
	_rating_selected_pids = []
	_elo_boost_state = {}
	_elo_v2_attempt = {}
	_elo_v2_won_styles = []
	_elo_v2_source_selected_ids = {}
	_last_splash_date = ""
	_splash_durations = []
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
	_prop_highlight_hint_date = ""
	_push_ask_count = 0
	_push_guide_last_date = ""
	_push_guide_shown_count = 0
	_push_guide_popup_count = 0
	_recent_win_counts_by_day = {}
	_last_main_win_date = ""
	_daily_first_win_entry_date = ""
	_has_shown_att_guide = false
	_interstitial_unlocked = false
	_banner_unlocked = false
	_has_shown_draft_onboarding = false
	_auto_mark_tutorial_done = false
	_pattern_mode_on = false
	_pattern_entry_dot_dismissed = false
	_pattern_switch_dot_dismissed = false
	_music_entry_dot_dismissed = false
	_grt_level_d90_reported = []
	_grt_reported_events = []
	_first_open_time_ms = 0
	_recent_puzzles = []
	_endgame_snapshot = {}
	_daily_endgame_snapshot = {}
	_session_count = 0
	_today_session_count = 0
	_last_day_session_count = 0
	_active_days = 0
	_last_login_date = ""
	_returnee_group = 0
	_returnee_from_endgame_save = false
	_returnee_remaining = 0
	_returnee_lower = 1
	_returnee_upper = 1
	_returnee_frozen_strategy = 1
	_returnee_previous_login_date = ""
	_returnee_level_at_login = 0
	_returnee_started_this_cold_start = false
	_returnee_current_level = 0
	_returnee_lkmod_resume_level = 0
	_returnee_frozen_dda = {}
	_comeback_welcome_shown = false
	_comeback_start_level = 0
	_comeback_main_win_consumed = false
	_today_played_count = 0
	_today_active_sec = 0
	_today_cat_found = 0
	_today_mark_placed = 0
	_today_tool_consumed = 0
	_today_revive_count = 0
	_game_barrage_daily_keys = PackedStringArray()
	_today_win_stats_group = -1
	_total_active_sec = 0
	_today_date = ""
	_pending_rewards = []
	_in_flight_awards = []
	_reward_history_ts = []
	_restored_today_count = 0
	_daily_auto_mark_enabled = false
	_daily_auto_mark_free_consumed = false
	_saved_game_auto_mark = -1
	_saved_ab_groups = {}
	_saved_peek_ab_groups = {}
	_loading_page_test_force_longest_quote = false
	_last_win_beat_percent = -1.0
	_pass_anim_cat_cycle_count = 0
	_pass_anim_cat_cycle_group = -1
	_help_last_open_time = 0
	_install_version = ""
	_game_version_pre = ""
	_persisted_user_tags = {}
	_has_assist_confirmed = false
	_toast_hold_text_sig = -999
	_toast_shown_keys = PackedStringArray()
	_start_toast_pct = {}
	_start_toast_iq_idx = {}
	_start_toast_variant_idx = {}
	_start_toast_variant_pct = {}
	_dc_start_toast_pct = {}
	_golden_fish_streak_count = 0
	_golden_fish_pending = false
	_golden_fish_tutorial_shown = false
	_onefish_consecutive_wins = 0
	_onefish_consecutive_skips = 0
	_onefish_spawn_suppressed = false
	_onefish_progress = {}
	_onefish_shuffle_orders = {}
	_onefish_shuffle_cursors = {}
	_onefish_cycle_rounds = {}
	_onefish_used_bits = {}
	_onefish_pick_switch_anchor = 0
	_onefish_shuffle_group = -1
	_golden_fish_insert_delivered = 0
	_golden_fish_career_count = 0

	_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED
	_color_challenge_pending = false
	_color_challenge_delivered = 0
	_color_challenge_progress = {}
	_color_challenge_skip_count = 0
	_color_challenge_deferred_used = false
	_color_challenge_defer_until = 0
	_color_challenge_disabled = false
	_pattern_mode_before_color_challenge = -1

	_11503_r3_played_count = 0
	_11503_r4_played_count = 0

	_bsz11801_cycle_hits = 0
	_bsz11802_dyn_size = 8
	_bsz11802_last_delivered_size = 0
	_bsz11802_stuck_streak = 0
	_current_wrong_cat_num = 0
	_insert_golden_fish_wrong_cat_num = 0
	GambleUserTag.reset(false)
	_save_data()
	_save_endgame()
	all_data_reset.emit()
