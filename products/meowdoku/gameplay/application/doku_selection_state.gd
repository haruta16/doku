## 1.22 选题的候选状态。所有 setter 只改变私有副本；落盘、信号和外部服务由用例提交后处理。
## API 保留原策略语义，候选失败直接丢弃，不回滚真实 GameState。
class_name DokuSelectionState
extends RefCounted

var _observed_fields: Dictionary = {}
var _candidate: Dictionary = {}
var _original_candidate: Dictionary = {}
var _selection_context: Dictionary = {}
var _today: String = ""
var _returnee_gap_days: int = 2
var _now_unix: int = 0
var _rng: RandomNumberGenerator
var events: Array[Dictionary] = []
const RECENT_PUZZLES_LIMIT := 100 # 最近出题记录的上限（超出丢最旧的）

const ENDGAME_SNAPSHOT_VERSION: int = 2 # 残局快照结构版本号

const ELO_SELECTED_MAX: int = 2000

const RATING_SELECTED_MAX: int = 2000

const CLOUD_TOOL_KINDS: Array[String] = ["locate", "hint", "draft", "mouse"]

var _current_level: int = 1

var _last_hard_level: int = 0

var _current_strategy: int = 1 # 当前提示策略层 R1~R6，由 DDA 升降

var _consecutive_clean_wins: int = 0 # 连续「干净通关」次数，够阈值就升一层

var _last_level_clean_win: bool = false # 上一关是否干净通关

var _consecutive_fails: int = 0 # 连续失败次数，够阈值就降一层

var _consecutive_retry_levels: int = 0 # 连续重试同一关的关数（重试降档用）

var _retry_tracking_strategy: int = 0 # 统计连续重试时所在的策略层

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

var _nl_v6_alternate_r4_count: int = 0

var _nl_v6_alternate_r4_level: int = 0

var _nl_v6_pool_progress: Dictionary = {}

var _nl_v6_alt_state: Dictionary = {}

var _daily_first_easy_date: String = "" # 最后一次用掉「首次降档」机会的日期

var _main_game_round_stats: Dictionary = {} # 普通模式本局统计（键见 Tracker._ROUND_STAT_KEYS）

var _daily_game_round_stats: Dictionary = {} # 每日挑战本局统计

var _tool_locate: int = 5

var _tool_hint: int = 5 # 提示道具数量（初始 5）

var _tool_mouse: int = 2

var _tool_draft: int = 5

var _recent_win_counts_by_day: Dictionary = {}

var _last_main_win_date: String = ""

var _daily_first_win_entry_date: String = ""

var _pattern_mode_on: bool = false

var _today_date: String = "" # 日切时记下的「今天」，用于判断是否需要跨天重置

var _today_session_count: int = 0 # 今日会话数

var _last_day_session_count: int = 0 # 昨日会话数（日切时从 today 挪过来）

var _active_days: int = 0 # 活跃天数（每次日切 +1，Helpshift 也用）

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

var _elo_v2_attempt: Dictionary = {}

var _elo_v2_won_styles: Array = []

var _elo_v2_source_selected_ids: Dictionary = {}

var _pending_rewards: Array = []

var _restored_today_count: int = 0 # 今日已找回次数（上限 3）

var _daily_auto_mark_enabled: bool = false

var _retry_puzzle_level: int = 0

var _retry_puzzle_params: Dictionary = {} # 重试时要复用的题库参数（配合 _retry_puzzle_level 校验）

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

var _golden_fish_pre_cat_session: Dictionary = {}

var _recent_puzzles: Array = [] # 最近出过的题目记录（含题库进度快照，用于去重与回滚）

var _endgame_snapshot: Dictionary = {} # 残局快照（真实存在 endgame.cfg，玩家档里只写空值）

var _golden_fish_streak_count: int = 0

var _golden_fish_pending: bool = false

var _golden_fish_tutorial_shown: bool = false

var _onefish_consecutive_wins: int = 0

var _onefish_consecutive_skips: int = 0

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

var _pattern_mode_before_color_challenge: int = -1

var _chain_last_replaced_level: int = 0

var _chain_g3_streak: int = 0

var _bsz11801_cycle_hits: int = 0

var _bsz11802_dyn_size: int = 8

var _bsz11802_last_delivered_size: int = 0

var _bsz11802_stuck_streak: int = 0

var _g4_pressure_level_num: int = 0

var _g4_defer_pending: bool = false

var _current_level_dirty: bool = false # 本局是否动过道具/复活（脏了就没有干净通关连击）

var _demoted_this_level: bool = false # 本关是否已经降过档（一关最多降一次）

var _dda_tool_or_revive_used: bool = false # 本局是否用过道具或复活（DDA 降档判据）

var _dda_pending_demote: bool = false # 待执行的降档（下一关是困难/特殊关时先挂起）

var _is_daily_first_easy_level: bool = false # 本局是否走了「每日首次降档」

var _chain_g2_pending: bool = false

var _sr_dda_pending_rank: int = 0

var _sr_dda_pending_is_upgrade: bool = false

var _11503_r3_played_count: int = 0

var _11503_r4_played_count: int = 0

var _daily_first_easy_available: bool = false # 今日是否还能享受首次降档（启动时评估一次）

var _daily_first_easy_evaluated: bool = false # 本次启动是否已评估过首次降档

var _dc_start_toast_pct: Dictionary = {}

const FIELD_MAP: Dictionary = {
  "_tool_hint": {
    "section": "inventory",
    "key": "hint",
    "type": "int"
  },
  "_elo_init_r3": {
    "section": "profile",
    "key": "elo_init_r3",
    "type": "bool"
  },
  "_onefish_pick_switch_anchor": {
    "section": "profile",
    "key": "onefish_pick_switch_anchor",
    "type": "int"
  },
  "_daily_first_easy_date": {
    "section": "profile",
    "key": "daily_first_easy_date",
    "type": "String"
  },
  "_elo_fish_consumed": {
    "section": "profile",
    "key": "elo_fish_consumed",
    "type": "int"
  },
  "_main_bank_progress": {
    "section": "profile",
    "key": "main_bank_progress",
    "type": "Dictionary"
  },
  "_daily_first_win_entry_date": {
    "section": "profile",
    "key": "daily_first_win_entry_date",
    "type": "String"
  },
  "_consecutive_clean_wins": {
    "section": "profile",
    "key": "consecutive_clean_wins",
    "type": "int"
  },
  "_insert_golden_fish_wrong_cat_num": {
    "section": "profile",
    "key": "insert_gf_wrong_cat_num",
    "type": "int"
  },
  "_elo_v2_attempt": {
    "section": "profile",
    "key": "elo_v2_attempt",
    "type": "Dictionary"
  },
  "_returnee_frozen_dda": {
    "section": "profile",
    "key": "returnee_frozen_dda",
    "type": "Dictionary"
  },
  "_golden_fish_tutorial_shown": {
    "section": "profile",
    "key": "golden_fish_tutorial_shown",
    "type": "bool"
  },
  "_elo_band_r4": {
    "section": "profile",
    "key": "elo_band_r4",
    "type": "int"
  },
  "_returnee_from_endgame_save": {
    "section": "profile",
    "key": "returnee_from_endgame_save",
    "type": "bool"
  },
  "_elo_rating_r5": {
    "section": "profile",
    "key": "elo_rating_r5",
    "type": "float"
  },
  "_returnee_group": {
    "section": "profile",
    "key": "returnee_group",
    "type": "int"
  },
  "_today_revive_count": {
    "section": "profile",
    "key": "today_revive_count",
    "type": "int"
  },
  "_11503_r4_played_count": {
    "section": "profile",
    "key": "diff_diff_r4_played_count",
    "type": "int"
  },
  "_current_level": {
    "section": "profile",
    "key": "current_level",
    "type": "int"
  },
  "_today_date": {
    "section": "profile",
    "key": "today_date",
    "type": "String"
  },
  "_last_level_clean_win": {
    "section": "profile",
    "key": "last_level_clean_win",
    "type": "bool"
  },
  "_downgrade_special_pending_level": {
    "section": "profile",
    "key": "downgrade_special_pending_level",
    "type": "int"
  },
  "_g4_defer_pending": {
    "section": "profile",
    "key": "g4_defer_pending",
    "type": "bool"
  },
  "_bsz11801_cycle_hits": {
    "section": "profile",
    "key": "bsz11801_cycle_hits",
    "type": "int"
  },
  "_golden_fish_streak_count": {
    "section": "profile",
    "key": "golden_fish_streak_count",
    "type": "int"
  },
  "_elo_band_r3": {
    "section": "profile",
    "key": "elo_band_r3",
    "type": "int"
  },
  "_pre_cat_fail_count": {
    "section": "profile",
    "key": "pre_cat_fail_count",
    "type": "int"
  },
  "_bank_progress": {
    "section": "profile",
    "key": "bank_progress",
    "type": "Dictionary"
  },
  "_retry_tracking_strategy": {
    "section": "profile",
    "key": "retry_tracking_strategy",
    "type": "int"
  },
  "_chain_last_replaced_level": {
    "section": "profile",
    "key": "chain_last_replaced_level",
    "type": "int"
  },
  "_pre_cat_fail_lv": {
    "section": "profile",
    "key": "pre_cat_fail_lv",
    "type": "int"
  },
  "_elo_rating_r4": {
    "section": "profile",
    "key": "elo_rating_r4",
    "type": "float"
  },
  "_lk_mod_g2_last_replaced_level": {
    "section": "profile",
    "key": "lk_mod_g2_last_replaced_level",
    "type": "int"
  },
  "_tool_mouse": {
    "section": "inventory",
    "key": "mouse",
    "type": "int"
  },
  "_nl_v6_pool_progress": {
    "section": "profile",
    "key": "nl_v6_pool_progress",
    "type": "Dictionary"
  },
  "_pattern_mode_on": {
    "section": "profile",
    "key": "pattern_mode_on",
    "type": "bool"
  },
  "_pending_rewards": {
    "section": "profile",
    "key": "pending_rewards",
    "type": "Array"
  },
  "_onefish_cycle_rounds": {
    "section": "profile",
    "key": "onefish_cycle_rounds",
    "type": "Dictionary"
  },
  "_bsz11802_last_delivered_size": {
    "section": "profile",
    "key": "bsz11802_last_delivered_size",
    "type": "int"
  },
  "_returnee_current_level": {
    "section": "profile",
    "key": "returnee_current_level",
    "type": "int"
  },
  "_pre_cat_pending_demote": {
    "section": "profile",
    "key": "pre_cat_pending_demote",
    "type": "bool"
  },
  "_rating_selected_pids": {
    "section": "profile",
    "key": "rating_selected_pids",
    "type": "Array"
  },
  "_returnee_lower": {
    "section": "profile",
    "key": "returnee_lower",
    "type": "int"
  },
  "_lkmod_progress": {
    "section": "profile",
    "key": "lkmod_progress",
    "type": "Dictionary"
  },
  "_single_region_supp_progress": {
    "section": "profile",
    "key": "single_region_supp_progress",
    "type": "Dictionary"
  },
  "_consecutive_retry_levels": {
    "section": "profile",
    "key": "consecutive_retry_levels",
    "type": "int"
  },
  "_today_mark_placed": {
    "section": "profile",
    "key": "today_mark_placed",
    "type": "int"
  },
  "_game_barrage_daily_keys": {
    "section": "profile",
    "key": "game_barrage_daily_keys",
    "type": "PackedStringArray"
  },
  "_returnee_lkmod_resume_level": {
    "section": "profile",
    "key": "returnee_lkmod_resume_level",
    "type": "int"
  },
  "_elo_init_r5": {
    "section": "profile",
    "key": "elo_init_r5",
    "type": "bool"
  },
  "_main_game_round_stats": {
    "section": "endgame.stats",
    "key": "main_round",
    "type": "Dictionary"
  },
  "_returnee_upper": {
    "section": "profile",
    "key": "returnee_upper",
    "type": "int"
  },
  "_onefish_consecutive_wins": {
    "section": "profile",
    "key": "onefish_consecutive_wins",
    "type": "int"
  },
  "_chain_g3_streak": {
    "section": "profile",
    "key": "chain_g3_streak",
    "type": "int"
  },
  "_nl_v6_alt_state": {
    "section": "profile",
    "key": "nl_v6_alt_state",
    "type": "Dictionary"
  },
  "_onefish_shuffle_orders": {
    "section": "profile",
    "key": "onefish_shuffle_orders",
    "type": "Dictionary"
  },
  "_elo_games_r4": {
    "section": "profile",
    "key": "elo_games_r4",
    "type": "int"
  },
  "_color_challenge_since_gf": {
    "section": "profile",
    "key": "cc_since_gf",
    "type": "int"
  },
  "_retry_puzzle_level": {
    "section": "profile",
    "key": "retry_puzzle_level",
    "type": "int"
  },
  "_tool_draft": {
    "section": "inventory",
    "key": "draft",
    "type": "int"
  },
  "_pre_cat_lock_pre_type": {
    "section": "profile",
    "key": "pre_cat_lock_pre_type",
    "type": "String"
  },
  "_onefish_progress": {
    "section": "profile",
    "key": "onefish_progress",
    "type": "Dictionary"
  },
  "_pre_cat_revived_this_level": {
    "section": "profile",
    "key": "pre_cat_revived_this_level",
    "type": "bool"
  },
  "_onefish_shuffle_group": {
    "section": "profile",
    "key": "onefish_shuffle_group",
    "type": "int"
  },
  "_current_strategy": {
    "section": "profile",
    "key": "current_strategy",
    "type": "int"
  },
  "_elo_band_r5": {
    "section": "profile",
    "key": "elo_band_r5",
    "type": "int"
  },
  "_today_session_count": {
    "section": "profile",
    "key": "today_session_count",
    "type": "int"
  },
  "_golden_fish_insert_delivered": {
    "section": "profile",
    "key": "golden_fish_insert_delivered",
    "type": "int"
  },
  "_sp_tt_progress": {
    "section": "profile",
    "key": "sp_tt_progress",
    "type": "Dictionary"
  },
  "_tool_locate": {
    "section": "inventory",
    "key": "locate",
    "type": "int"
  },
  "_returnee_remaining": {
    "section": "profile",
    "key": "returnee_remaining",
    "type": "int"
  },
  "_retry_puzzle_params": {
    "section": "profile",
    "key": "retry_puzzle_params",
    "type": "Dictionary"
  },
  "_elo_aux_climax_progress": {
    "section": "profile",
    "key": "elo_aux_climax_progress",
    "type": "Dictionary"
  },
  "_elo_games_r5": {
    "section": "profile",
    "key": "elo_games_r5",
    "type": "int"
  },
  "_color_challenge_pending": {
    "section": "profile",
    "key": "cc_pending",
    "type": "bool"
  },
  "_sp_tt_lk_alt_block_source": {
    "section": "profile",
    "key": "sp_tt_lk_alt_block_source",
    "type": "String"
  },
  "_climax_filter_progress": {
    "section": "profile",
    "key": "climax_filter_progress",
    "type": "Dictionary"
  },
  "_onefish_used_bits": {
    "section": "profile",
    "key": "onefish_used_bits",
    "type": "Dictionary"
  },
  "_today_cat_found": {
    "section": "profile",
    "key": "today_cat_found",
    "type": "int"
  },
  "_today_tool_consumed": {
    "section": "profile",
    "key": "today_tool_consumed",
    "type": "int"
  },
  "_super_hard_anchor": {
    "section": "profile",
    "key": "super_hard_anchor",
    "type": "int"
  },
  "_elo_v2_source_selected_ids": {
    "section": "profile",
    "key": "elo_v2_source_selected_ids",
    "type": "Dictionary"
  },
  "_elo_v2_won_styles": {
    "section": "profile",
    "key": "elo_v2_won_styles",
    "type": "Array"
  },
  "_elo_games_r3": {
    "section": "profile",
    "key": "elo_games_r3",
    "type": "int"
  },
  "_sp_tt_category_cursor": {
    "section": "profile",
    "key": "sp_tt_category_cursor",
    "type": "int"
  },
  "_elo_aux_single_region_progress": {
    "section": "profile",
    "key": "elo_aux_single_region_progress",
    "type": "Dictionary"
  },
  "_onefish_consecutive_skips": {
    "section": "profile",
    "key": "onefish_consecutive_skips",
    "type": "int"
  },
  "_color_challenge_progress": {
    "section": "profile",
    "key": "cc_progress",
    "type": "Dictionary"
  },
  "_nl_v6_alternate_r4_count": {
    "section": "profile",
    "key": "nl_v6_alternate_r4_count",
    "type": "int"
  },
  "_pre_cat_pending_hard": {
    "section": "profile",
    "key": "pre_cat_pending_hard",
    "type": "bool"
  },
  "_pattern_mode_before_color_challenge": {
    "section": "profile",
    "key": "pattern_mode_before_cc",
    "type": "int"
  },
  "_daily_game_round_stats": {
    "section": "endgame.stats",
    "key": "daily_round",
    "type": "Dictionary"
  },
  "_golden_fish_pre_cat_session": {
    "section": "profile",
    "key": "golden_fish_pre_cat_session",
    "type": "Dictionary"
  },
  "_bsz11802_stuck_streak": {
    "section": "profile",
    "key": "bsz11802_stuck_streak",
    "type": "int"
  },
  "_returnee_frozen_strategy": {
    "section": "profile",
    "key": "returnee_frozen_strategy",
    "type": "int"
  },
  "_nl_v6_alternate_r4_level": {
    "section": "profile",
    "key": "nl_v6_alternate_r4_level",
    "type": "int"
  },
  "_recent_win_counts_by_day": {
    "section": "profile",
    "key": "recent_win_counts_by_day",
    "type": "Dictionary"
  },
  "_elo_group2_cohort": {
    "section": "profile",
    "key": "elo_group2_cohort",
    "type": "int"
  },
  "_golden_fish_pending": {
    "section": "profile",
    "key": "golden_fish_pending",
    "type": "bool"
  },
  "_sp_tt_last_replaced_level": {
    "section": "profile",
    "key": "sp_tt_last_replaced_level",
    "type": "int"
  },
  "_sp_tt_lk_alt_block_count": {
    "section": "profile",
    "key": "sp_tt_lk_alt_block_count",
    "type": "int"
  },
  "_endgame_snapshot": {
    "section": "endgame",
    "key": "snapshot",
    "type": "Dictionary"
  },
  "_last_day_session_count": {
    "section": "profile",
    "key": "last_day_session_count",
    "type": "int"
  },
  "_g4_pressure_level_num": {
    "section": "profile",
    "key": "g4_pressure_level_num",
    "type": "int"
  },
  "_pre_cat_lock_pos": {
    "section": "profile",
    "key": "pre_cat_lock_pos",
    "type": "Vector2i"
  },
  "_today_active_sec": {
    "section": "profile",
    "key": "today_active_sec",
    "type": "int"
  },
  "_sp_tt_lk_alt_last_replaced_level": {
    "section": "profile",
    "key": "sp_tt_lk_alt_last_replaced_level",
    "type": "int"
  },
  "_recent_puzzles": {
    "section": "profile",
    "key": "recent_puzzles",
    "type": "Array"
  },
  "_today_played_count": {
    "section": "profile",
    "key": "today_played_count",
    "type": "int"
  },
  "_11503_r3_played_count": {
    "section": "profile",
    "key": "diff_diff_r3_played_count",
    "type": "int"
  },
  "_elo_active_puzzle_rating": {
    "section": "profile",
    "key": "elo_active_puzzle_rating",
    "type": "float"
  },
  "_bsz11802_dyn_size": {
    "section": "profile",
    "key": "bsz11802_dyn_size",
    "type": "int"
  },
  "_elo_active_rank": {
    "section": "profile",
    "key": "elo_active_rank",
    "type": "int"
  },
  "_nl11701_shuffle_seed": {
    "section": "profile",
    "key": "nl11701_shuffle_seed",
    "type": "int"
  },
  "_onefish_shuffle_cursors": {
    "section": "profile",
    "key": "onefish_shuffle_cursors",
    "type": "Dictionary"
  },
  "_elo_selected_pids": {
    "section": "profile",
    "key": "elo_selected_pids",
    "type": "Array"
  },
  "_elo_rating_r3": {
    "section": "profile",
    "key": "elo_rating_r3",
    "type": "float"
  },
  "_elo_init_r4": {
    "section": "profile",
    "key": "elo_init_r4",
    "type": "bool"
  },
  "_daily_auto_mark_enabled": {
    "section": "profile",
    "key": "daily_auto_mark_enabled",
    "type": "bool"
  },
  "_consecutive_fails": {
    "section": "profile",
    "key": "consecutive_fails",
    "type": "int"
  },
  "_normal_pass_time_records": {
    "section": "profile",
    "key": "normal_pass_time_records",
    "type": "Array"
  },
  "_pre_cat_lock_lv": {
    "section": "profile",
    "key": "pre_cat_lock_lv",
    "type": "int"
  },
  "_active_days": {
    "section": "profile",
    "key": "active_days",
    "type": "int"
  },
  "_pre_cat_pending_struggle": {
    "section": "profile",
    "key": "pre_cat_pending_struggle",
    "type": "bool"
  },
  "_last_hard_level": {
    "section": "profile",
    "key": "last_hard_level",
    "type": "int"
  },
  "_color_challenge_delivered": {
    "section": "profile",
    "key": "cc_delivered",
    "type": "int"
  },
  "_last_main_win_date": {
    "section": "profile",
    "key": "last_main_win_date",
    "type": "String"
  },
  "_restored_today_count": {
    "section": "profile",
    "key": "restored_today_count",
    "type": "int"
  },
  "_golden_fish_career_count": {
    "section": "profile",
    "key": "golden_fish_career_count",
    "type": "int"
  }
}
const RUNTIME_FIELDS: Array[String] = ["_chain_g2_pending", "_comeback_main_win_consumed", "_comeback_start_level", "_comeback_welcome_shown", "_current_level_dirty", "_daily_first_easy_available", "_daily_first_easy_evaluated", "_dc_start_toast_pct", "_dda_pending_demote", "_dda_tool_or_revive_used", "_demoted_this_level", "_is_daily_first_easy_level", "_returnee_level_at_login", "_returnee_previous_login_date", "_returnee_started_this_cold_start", "_sr_dda_pending_is_upgrade", "_sr_dda_pending_rank", "_stale_endgame_discarded"]

func _init(candidate: Dictionary = {}, context: Dictionary = {}) -> void:
	_candidate = candidate.duplicate(true)
	_original_candidate = candidate.duplicate(true)
	_selection_context = context.duplicate(true)
	_today = str(context.get("today", ""))
	_returnee_gap_days = int(context.get("returnee_gap_days", 2))
	_now_unix = int(context.get("now_unix", 0))
	_rng = context.get("rng", null)
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = int(context.get("seed", 0))
	for name: String in FIELD_MAP:
		var mapping: Dictionary = FIELD_MAP[name]
		var section: Dictionary = _section(_candidate, str(mapping.section))
		if section.has(mapping.key):
			set(name, _copy(section[mapping.key]))
	var runtime: Dictionary = _candidate.get("round_runtime", {})
	for name: String in RUNTIME_FIELDS:
		if runtime.has(name.trim_prefix("_")):
			set(name, _copy(runtime[name.trim_prefix("_")]))
	_daily_first_easy_available = bool(context.get("daily_available", _daily_first_easy_available))


func export_candidate() -> Dictionary:
	var result: Dictionary = _candidate.duplicate(true)
	for name: String in FIELD_MAP:
		var mapping: Dictionary = FIELD_MAP[name]
		var section: Dictionary = _section(result, str(mapping.section), true)
		section[mapping.key] = _copy(get(name))
	var runtime: Dictionary = result.get("round_runtime", {})
	for name: String in RUNTIME_FIELDS:
		runtime[name.trim_prefix("_")] = _copy(get(name))
	result["round_runtime"] = runtime
	return result


func snapshot() -> Dictionary:
	return export_candidate()


func _today_str() -> String:
	return _today


func _save_data() -> void:
	pass


static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value


static func _section(root: Dictionary, path: String, create: bool = false) -> Dictionary:
	var section: Dictionary = root
	for part: String in path.split("."):
		if not section.has(part):
			if not create:
				return {}
			section[part] = {}
		section = section[part]
	return section


func get_current_level() -> int:
	_observe_fields(["_current_level"])
	return _current_level

func get_last_hard_level() -> int:
	_observe_fields(["_last_hard_level"])
	return _last_hard_level

func mark_hard_level(level_num: int) -> void:
	_observe_fields(["_last_hard_level"])
	if _last_hard_level == level_num:
		return
	_last_hard_level = level_num
	_save_data()

func is_daily_first_easy_available() -> bool:
	_observe_fields(["_daily_first_easy_available"])
	return _daily_first_easy_available

func evaluate_daily_first_easy() -> void:
	_observe_fields(["_current_level", "_daily_first_easy_available", "_daily_first_easy_date", "_daily_first_easy_evaluated", "_endgame_snapshot"])
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
	_observe_fields(["_daily_first_easy_available", "_daily_first_easy_date"])
	_daily_first_easy_date = _today_str()
	_daily_first_easy_available = false
	_save_data()

func consume_daily_first_easy_and_mark() -> void:
	_observe_fields(["_is_daily_first_easy_level"])
	consume_daily_first_easy()
	_is_daily_first_easy_level = true

func advance_daily_first_easy_date() -> void:
	_observe_fields(["_daily_first_easy_available", "_daily_first_easy_date"])
	var today: String = _today_str()
	if _daily_first_easy_date >= today:
		return
	_daily_first_easy_date = today
	_daily_first_easy_available = false
	_save_data()
	print("[DailyFirstEasy] 局内跨天+开始新对局, 推进日期消耗机会")

func is_pattern_mode_on() -> bool:
	_observe_fields(["_pattern_mode_on"])
	return _pattern_mode_on

func get_current_strategy() -> int:
	_observe_fields(["_current_strategy"])
	return _current_strategy

func set_current_strategy(value: int) -> void:
	_observe_fields(["_current_strategy"])
	_current_strategy = value
	_save_data()

func get_chain_last_replaced_level() -> int:
	_observe_fields(["_chain_last_replaced_level"])
	return _chain_last_replaced_level

func set_chain_last_replaced_level(value: int) -> void:
	_observe_fields(["_chain_last_replaced_level"])
	_chain_last_replaced_level = value
	_save_data()

func get_chain_g3_streak() -> int:
	_observe_fields(["_chain_g3_streak"])
	return _chain_g3_streak

func set_chain_g3_streak(value: int) -> void:
	_observe_fields(["_chain_g3_streak"])
	_chain_g3_streak = value
	_save_data()

func get_bsz11801_cycle_hits() -> int:
	_observe_fields(["_bsz11801_cycle_hits"])
	return _bsz11801_cycle_hits

func set_bsz11801_cycle_hits(value: int) -> void:
	_observe_fields(["_bsz11801_cycle_hits"])
	_bsz11801_cycle_hits = value
	_save_data()

func get_bsz11802_dyn_size() -> int:
	_observe_fields(["_bsz11802_dyn_size"])
	return _bsz11802_dyn_size

func set_bsz11802_dyn_size(value: int) -> void:
	_observe_fields(["_bsz11802_dyn_size"])
	_bsz11802_dyn_size = value
	_save_data()

func get_bsz11802_last_delivered_size() -> int:
	_observe_fields(["_bsz11802_last_delivered_size"])
	return _bsz11802_last_delivered_size

func set_bsz11802_last_delivered_size(value: int) -> void:
	_observe_fields(["_bsz11802_last_delivered_size"])
	_bsz11802_last_delivered_size = value
	_save_data()

func get_bsz11802_stuck_streak() -> int:
	_observe_fields(["_bsz11802_stuck_streak"])
	return _bsz11802_stuck_streak

func set_bsz11802_stuck_streak(value: int) -> void:
	_observe_fields(["_bsz11802_stuck_streak"])
	_bsz11802_stuck_streak = value
	_save_data()

func get_game_round_stats(game_type: String) -> Dictionary:
	_observe_fields(["_daily_game_round_stats", "_main_game_round_stats"])
	if game_type == "daily":
		return _daily_game_round_stats.duplicate()
	return _main_game_round_stats.duplicate()

func _roll_day_if_needed() -> void:
	_observe_fields(["_today_date"])
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
	_dc_start_toast_pct.clear()
	_active_days += 1

	var cutoff_unix: int = Time.get_unix_time_from_datetime_string(today + "T00:00:00") - 2 * 86400
	for key: String in _recent_win_counts_by_day.keys().duplicate():
		if Time.get_unix_time_from_datetime_string(key + "T00:00:00") < cutoff_unix:
			_recent_win_counts_by_day.erase(key)
	_today_date = today

func get_returnee_login_gap_days() -> int:
	_observe_fields(["_returnee_previous_login_date"])
	return ReturneeClock.day_gap(_returnee_previous_login_date, _today_str())

func should_begin_returnee_event(group: int) -> bool:
	_observe_fields(["_returnee_level_at_login", "_returnee_started_this_cold_start"])
	return (
		_returnee_level_at_login > 30
		and ReturneeLevelPolicy.can_start(
			get_returnee_login_gap_days(),
			group,
			_returnee_started_this_cold_start,
			_returnee_gap_days
		)
	)

func begin_returnee_event(group: int, lower: int, upper: int) -> void:
	_observe_fields(["_consecutive_clean_wins", "_consecutive_fails", "_consecutive_retry_levels", "_current_strategy", "_dda_pending_demote", "_demoted_this_level", "_retry_tracking_strategy", "_returnee_current_level", "_returnee_from_endgame_save", "_returnee_frozen_dda", "_returnee_frozen_strategy", "_returnee_group", "_returnee_lkmod_resume_level", "_returnee_lower", "_returnee_remaining", "_returnee_started_this_cold_start", "_returnee_upper"])
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

func begin_stale_new_easier_level(level_num: int) -> void:
	_observe_fields(["_returnee_current_level", "_returnee_from_endgame_save", "_returnee_group", "_returnee_remaining", "_returnee_started_this_cold_start"])
	_returnee_started_this_cold_start = true
	_returnee_group = 0
	_returnee_remaining = 0
	_returnee_from_endgame_save = true
	_returnee_current_level = level_num
	_save_data()

func get_returnee_remaining(group: int) -> int:
	_observe_fields(["_returnee_group", "_returnee_remaining"])
	return _returnee_remaining if group == _returnee_group else 0

func should_defer_returnee_golden_fish() -> bool:
	return get_returnee_remaining(12001) > 0

func get_available_golden_fish_pending() -> bool:
	_observe_fields(["_golden_fish_pending"])
	return _golden_fish_pending and not should_defer_returnee_golden_fish()

func get_returnee_easy_range() -> Vector2i:
	_observe_fields(["_returnee_lower", "_returnee_upper"])
	return Vector2i(_returnee_lower, _returnee_upper)

func mark_returnee_delivery(group: int, level_num: int, fixed_sp: bool) -> void:
	_observe_fields(["_returnee_current_level", "_returnee_group", "_returnee_remaining"])
	if group != _returnee_group or _returnee_remaining <= 0:
		return
	_returnee_remaining = ReturneeLevelPolicy.remaining_after_delivery(
		_returnee_remaining, fixed_sp
	)
	_returnee_current_level = level_num
	_save_data()

func mark_stale_endgame_discarded() -> void:
	_observe_fields(["_stale_endgame_discarded"])
	_stale_endgame_discarded = true

func claim_comeback_start_level(level_num: int) -> bool:
	_observe_fields(["_comeback_main_win_consumed", "_comeback_start_level", "_comeback_welcome_shown"])
	if not _comeback_welcome_shown or _comeback_main_win_consumed or level_num <= 0:
		return false
	if _comeback_start_level == 0:
		_comeback_start_level = level_num
	return _comeback_start_level == level_num

func consume_comeback_main_win() -> bool:
	_observe_fields(["_comeback_main_win_consumed", "_comeback_welcome_shown"])
	if not _comeback_welcome_shown or _comeback_main_win_consumed:
		return false
	_comeback_main_win_consumed = true
	return true

func get_today_win_count() -> int:
	_observe_fields(["_recent_win_counts_by_day"])
	_roll_day_if_needed()
	return _recent_win_counts_by_day.get(_today_str(), 0)

func has_main_win_today() -> bool:
	_observe_fields(["_last_main_win_date"])
	return _last_main_win_date == _today_str()

func has_daily_first_win_entry_seen_today() -> bool:
	_observe_fields(["_daily_first_win_entry_date"])
	return _daily_first_win_entry_date == _today_str()

func mark_daily_first_win_entry_seen_today() -> void:
	_observe_fields(["_daily_first_win_entry_date"])
	var today: String = _today_str()
	if _daily_first_win_entry_date == today:
		return
	_daily_first_win_entry_date = today
	_save_data()

func get_today_tool_consumed() -> int:
	_observe_fields(["_today_tool_consumed"])
	_roll_day_if_needed()
	return _today_tool_consumed

func get_today_revive_count() -> int:
	_observe_fields(["_today_revive_count"])
	_roll_day_if_needed()
	return _today_revive_count

func get_tool_count(kind: String) -> int:
	_observe_fields(["_tool_draft", "_tool_hint", "_tool_locate", "_tool_mouse"])
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

func is_elo_initialized(rank: int) -> bool:
	_observe_fields(["_elo_init_r3", "_elo_init_r4", "_elo_init_r5"])
	match rank:
		3:
			return _elo_init_r3
		4:
			return _elo_init_r4
		5:
			return _elo_init_r5
		_:
			return false

func ensure_elo_group2_cohort() -> bool:
	_observe_fields(["_current_level", "_elo_group2_cohort"])
	if _elo_group2_cohort == -1:
		_elo_group2_cohort = 1 if _current_level < 100 else 0
		_save_data()
	return _elo_group2_cohort == 1

func is_elo_group2_new_player() -> bool:
	_observe_fields(["_elo_group2_cohort"])
	return _elo_group2_cohort == 1

func get_elo_rating(rank: int) -> float:
	_observe_fields(["_elo_rating_r3", "_elo_rating_r4", "_elo_rating_r5"])
	match rank:
		3:
			return _elo_rating_r3
		4:
			return _elo_rating_r4
		5:
			return _elo_rating_r5
		_:
			return 0.0

func get_elo_games(rank: int) -> int:
	_observe_fields(["_elo_games_r3", "_elo_games_r4", "_elo_games_r5"])
	match rank:
		3:
			return _elo_games_r3
		4:
			return _elo_games_r4
		5:
			return _elo_games_r5
		_:
			return 0

func get_elo_band(rank: int) -> int:
	_observe_fields(["_elo_band_r3", "_elo_band_r4", "_elo_band_r5"])
	match rank:
		3:
			return _elo_band_r3
		4:
			return _elo_band_r4
		5:
			return _elo_band_r5
		_:
			return 0

func init_elo_rating(rank: int, initial_value: float) -> void:
	_observe_fields(["_elo_init_r3", "_elo_init_r4", "_elo_init_r5", "_elo_rating_r3", "_elo_rating_r4", "_elo_rating_r5"])
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

func commit_elo_settlement(rank: int, new_rating: float, new_band: int) -> void:
	if not _apply_elo_rating_state(rank, new_rating, new_band):
		return
	_save_data()
	events.append({"kind": "elo_rating_committed", "rank": rank, "rating": new_rating})

func _apply_elo_rating_state(rank: int, new_rating: float, new_band: int) -> bool:
	_observe_fields(["_elo_band_r3", "_elo_band_r4", "_elo_band_r5", "_elo_games_r3", "_elo_games_r4", "_elo_games_r5", "_elo_rating_r3", "_elo_rating_r4", "_elo_rating_r5"])
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

func begin_elo_v2_attempt(
	level_num: int,
	puzzle_id: String,
	rank: int,
	puzzle_rating: float,
	style_vector: Dictionary,
	eligible: bool
) -> void:
	_observe_fields(["_elo_v2_attempt"])
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

func get_elo_v2_attempt() -> Dictionary:
	_observe_fields(["_elo_v2_attempt"])
	return _elo_v2_attempt.duplicate(true)

func abandon_elo_v2_attempt(level_num: int) -> void:
	_observe_fields(["_elo_v2_attempt"])
	if int(_elo_v2_attempt.get("level", 0)) != level_num:
		return
	_elo_v2_attempt = {}
	_save_data()

func merge_elo_v2_resume_facts(
	restart_count: int, used_tool: bool, fish_consumed: int, death_count: int
) -> void:
	_observe_fields(["_elo_v2_attempt"])
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

func record_elo_v2_action(action: String) -> void:
	_observe_fields(["_elo_v2_attempt"])
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

func set_elo_v2_win_facts(time_total: int, full_hp: bool) -> void:
	_observe_fields(["_elo_v2_attempt"])
	if _elo_v2_attempt.is_empty():
		return
	_elo_v2_attempt["time_total"] = time_total
	_elo_v2_attempt["full_hp"] = full_hp
	_save_data()

func get_recent_elo_v2_won_style_vectors(limit: int) -> Array:
	_observe_fields(["_elo_v2_won_styles"])
	var vectors: Array = []
	var start_index: int = maxi(0, _elo_v2_won_styles.size() - maxi(0, limit))
	for index: int in range(start_index, _elo_v2_won_styles.size()):
		var row: Dictionary = _elo_v2_won_styles[index]
		var vector: Dictionary = row.get("style_vector", {})
		vectors.append(vector.duplicate(true))
	return vectors

func get_elo_v2_source_selected_ids(key: String) -> Array:
	_observe_fields(["_elo_v2_source_selected_ids"])
	var selected: Array = _elo_v2_source_selected_ids.get(key, [])
	return selected.duplicate()

func record_elo_v2_source_selected_id(key: String, entry_id: int) -> void:
	_observe_fields(["_elo_v2_source_selected_ids"])
	if key.is_empty() or entry_id < 0:
		return
	var selected: Array = _elo_v2_source_selected_ids.get(key, [])
	if selected.has(entry_id):
		return
	selected.append(entry_id)
	_elo_v2_source_selected_ids[key] = selected
	_save_data()

func get_elo_active_rank() -> int:
	_observe_fields(["_elo_active_rank"])
	return _elo_active_rank

func get_elo_active_puzzle_rating() -> float:
	_observe_fields(["_elo_active_puzzle_rating"])
	return _elo_active_puzzle_rating

func set_elo_active_delivery(rank: int, puzzle_rating: float) -> void:
	_observe_fields(["_elo_active_puzzle_rating", "_elo_active_rank"])
	_elo_active_rank = rank
	_elo_active_puzzle_rating = puzzle_rating
	_save_data()

func get_elo_fish_consumed() -> int:
	_observe_fields(["_elo_fish_consumed"])
	return _elo_fish_consumed

func is_elo_pid_selected(pid_h: String) -> bool:
	_observe_fields(["_elo_selected_pids"])
	return pid_h != "" and _elo_selected_pids.has(pid_h)

func mark_elo_pid_selected(pid_h: String) -> void:
	_observe_fields(["_elo_selected_pids"])
	if pid_h == "" or _elo_selected_pids.has(pid_h):
		return
	_elo_selected_pids.append(pid_h)
	while _elo_selected_pids.size() > ELO_SELECTED_MAX:
		_elo_selected_pids.pop_front()
	_save_data()

func is_rating_pid_selected(pid_h: String) -> bool:
	_observe_fields(["_rating_selected_pids"])
	return pid_h != "" and _rating_selected_pids.has(pid_h)

func mark_rating_pid_selected(pid_h: String, persist: bool = true) -> void:
	_observe_fields(["_rating_selected_pids"])
	if pid_h == "" or _rating_selected_pids.has(pid_h):
		return
	_rating_selected_pids.append(pid_h)
	while _rating_selected_pids.size() > RATING_SELECTED_MAX:
		_rating_selected_pids.pop_front()
	if persist:
		_save_data()

func get_golden_fish_pending() -> bool:
	_observe_fields(["_golden_fish_pending"])
	return _golden_fish_pending

func has_golden_fish_tutorial_shown() -> bool:
	_observe_fields(["_golden_fish_tutorial_shown"])
	return _golden_fish_tutorial_shown

func mark_golden_fish_tutorial_shown() -> void:
	_observe_fields(["_golden_fish_tutorial_shown"])
	if _golden_fish_tutorial_shown:
		return
	_golden_fish_tutorial_shown = true
	_save_data()

func next_onefish_sequential_draw(sz: int, rank: int, count: int) -> int:
	_observe_fields(["_onefish_progress"])
	if count <= 0:
		return -1
	var key: String = "%d_%d" % [sz, rank]
	var start: int = int(_onefish_progress.get(key, 0)) % count
	for step in count:
		var probe: int = (start + step) % count
		if not _is_used_bit(key, probe):
			return probe
	return start

func _is_used_bit(key: String, idx: int) -> bool:
	_observe_fields(["_onefish_used_bits"])
	if idx < 0:
		return false
	var bits: PackedByteArray = _onefish_used_bits.get(key, PackedByteArray())
	@warning_ignore("integer_division")
	var byte_at: int = idx / 8
	if byte_at >= bits.size():
		return false
	return (bits[byte_at] & (1 << (idx % 8))) != 0

func get_onefish_cycle_round(sz: int, rank: int) -> int:
	_observe_fields(["_onefish_cycle_rounds"])
	return int(_onefish_cycle_rounds.get("%d_%d" % [sz, rank], 0))

func get_onefish_pick_switch_anchor() -> int:
	_observe_fields(["_onefish_pick_switch_anchor"])
	return _onefish_pick_switch_anchor

func next_onefish_shuffle_draw(sz: int, rank: int, count: int) -> Dictionary:
	_observe_fields(["_onefish_cycle_rounds", "_onefish_shuffle_cursors", "_onefish_shuffle_orders"])
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

func commit_onefish_shuffle_delivery(
	sz: int, rank: int, idx: int, count: int, persist: bool = true
) -> void:
	_observe_fields(["_golden_fish_insert_delivered", "_onefish_shuffle_cursors"])
	var key: String = "%d_%d" % [sz, rank]
	_onefish_shuffle_cursors[key] = int(_onefish_shuffle_cursors.get(key, 0)) + 1
	_mark_onefish_used(key, idx, count)
	_golden_fish_insert_delivered += 1
	if persist:
		_save_data()

func note_onefish_pick_group(group: int) -> void:
	_observe_fields(["_golden_fish_insert_delivered", "_onefish_pick_switch_anchor", "_onefish_shuffle_cursors", "_onefish_shuffle_group", "_onefish_shuffle_orders"])
	if group == _onefish_shuffle_group:
		return
	_onefish_shuffle_orders = {}
	_onefish_shuffle_cursors = {}
	_onefish_shuffle_group = group

	_onefish_pick_switch_anchor = _golden_fish_insert_delivered
	_save_data()

func _ensure_onefish_shuffle(key: String, count: int) -> void:
	_observe_fields(["_onefish_shuffle_cursors", "_onefish_shuffle_orders", "_onefish_used_bits"])
	var order: Array = _onefish_shuffle_orders.get(key, [])
	var cursor: int = int(_onefish_shuffle_cursors.get(key, 0))
	var unused_left: int = (
		count - _count_used_bits(_onefish_used_bits.get(key, PackedByteArray()), count)
	)

	if order.is_empty() or cursor >= order.size() or (order.size() - cursor) != unused_left:
		_shuffle_onefish_pool(key, count)
		_save_data()

func _shuffle_onefish_pool(key: String, count: int) -> void:
	_observe_fields(["_onefish_cycle_rounds", "_onefish_shuffle_cursors", "_onefish_shuffle_orders", "_onefish_used_bits"])
	var indices: Array = _onefish_unused_indices(key, count)
	if indices.is_empty():
		_onefish_used_bits[key] = PackedByteArray()
		_onefish_cycle_rounds[key] = int(_onefish_cycle_rounds.get(key, 0)) + 1
		indices = _onefish_unused_indices(key, count)
	var rng: RandomNumberGenerator = _rng

	for i in range(indices.size() - 1, 0, -1):
		var swap_at: int = rng.randi_range(0, i)
		var moved: int = indices[i]
		indices[i] = indices[swap_at]
		indices[swap_at] = moved
	_onefish_shuffle_orders[key] = indices
	_onefish_shuffle_cursors[key] = 0

func _onefish_unused_indices(key: String, count: int) -> Array:
	var out: Array = []
	for i in count:
		if not _is_used_bit(key, i):
			out.append(i)
	return out

func _mark_onefish_used(key: String, idx: int, count: int) -> void:
	_observe_fields(["_onefish_cycle_rounds", "_onefish_used_bits"])
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

func _onefish_used_bits_of(key: String, count: int) -> PackedByteArray:
	_observe_fields(["_onefish_used_bits"])
	@warning_ignore("integer_division")
	var need: int = (count + 7) / 8
	var bits: PackedByteArray = _onefish_used_bits.get(key, PackedByteArray())
	if bits.size() < need:
		bits = bits.duplicate()
		bits.resize(need)
	return bits

func _count_used_bits(bits: PackedByteArray, count: int) -> int:
	var used: int = 0
	for i in count:
		@warning_ignore("integer_division")
		var byte_at: int = i / 8
		if byte_at < bits.size() and (bits[byte_at] & (1 << (i % 8))) != 0:
			used += 1
	return used

func get_golden_fish_insert_delivered() -> int:
	_observe_fields(["_golden_fish_insert_delivered"])
	return _golden_fish_insert_delivered

func get_golden_fish_career_count() -> int:
	_observe_fields(["_golden_fish_career_count"])
	return _golden_fish_career_count

func get_color_challenge_pending() -> bool:
	_observe_fields(["_color_challenge_pending"])
	return _color_challenge_pending

func get_color_challenge_delivered() -> int:
	_observe_fields(["_color_challenge_delivered"])
	return _color_challenge_delivered

func get_color_challenge_index(sz: int, rank: int) -> int:
	_observe_fields(["_color_challenge_progress"])
	return int(_color_challenge_progress.get("%d_%d" % [sz, rank], 0))

func _advance_golden_fish_career_mut() -> void:
	_observe_fields(["_color_challenge_since_gf", "_golden_fish_career_count"])
	_golden_fish_career_count += 1
	_color_challenge_since_gf = ColorChallengeGate.since_gf_after_golden_fish()

func commit_color_challenge_delivery(sz: int, rank: int) -> void:
	_observe_fields(["_color_challenge_delivered", "_color_challenge_progress"])
	var cursor_key: String = "%d_%d" % [sz, rank]
	_color_challenge_progress[cursor_key] = int(_color_challenge_progress.get(cursor_key, 0)) + 1
	_color_challenge_delivered += 1

	_save_data()

func commit_color_challenge_override_delivery() -> void:
	_observe_fields(["_color_challenge_delivered"])
	_color_challenge_delivered += 1
	_save_data()

func begin_color_challenge_pattern_mode() -> void:
	_observe_fields(["_pattern_mode_before_color_challenge", "_pattern_mode_on"])
	if _pattern_mode_before_color_challenge >= 0:
		return
	_pattern_mode_before_color_challenge = 1 if _pattern_mode_on else 0

	_pattern_mode_on = true
	_save_data()

func commit_onefish_delivery(
	sz: int, rank: int, idx: int, count: int, persist: bool = true
) -> void:
	_observe_fields(["_golden_fish_insert_delivered", "_onefish_progress"])
	var key := "%d_%d" % [sz, rank]
	_onefish_progress[key] = int(_onefish_progress.get(key, 0)) + 1
	_mark_onefish_used(key, idx, count)
	_golden_fish_insert_delivered += 1
	if persist:
		_save_data()

func on_golden_fish_settled(won: bool) -> void:
	_observe_fields(["_golden_fish_pending", "_golden_fish_pre_cat_session", "_golden_fish_streak_count", "_insert_golden_fish_wrong_cat_num", "_onefish_consecutive_skips", "_onefish_consecutive_wins"])
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

func clear_current_level_dirty() -> void:
	_observe_fields(["_current_level_dirty"])
	_current_level_dirty = false

func is_dda_tool_or_revive_used() -> bool:
	_observe_fields(["_dda_tool_or_revive_used"])
	return _dda_tool_or_revive_used

func is_current_level_daily_first_easy() -> bool:
	_observe_fields(["_is_daily_first_easy_level"])
	return _is_daily_first_easy_level

func set_chain_g2_pending(value: bool) -> void:
	_observe_fields(["_chain_g2_pending"])
	_chain_g2_pending = value

func consume_chain_g2_pending() -> bool:
	_observe_fields(["_chain_g2_pending"])
	var pending: bool = _chain_g2_pending
	_chain_g2_pending = false
	return pending

func mark_g4_pressure_level(level_num: int) -> void:
	_observe_fields(["_g4_pressure_level_num"])
	_g4_pressure_level_num = level_num

func is_g4_pressure_level(level_num: int) -> bool:
	_observe_fields(["_g4_pressure_level_num"])
	return _g4_pressure_level_num > 0 and _g4_pressure_level_num == level_num

func set_g4_defer_pending(value: bool) -> void:
	_observe_fields(["_g4_defer_pending"])
	_g4_defer_pending = value

func consume_g4_defer_pending() -> bool:
	_observe_fields(["_g4_defer_pending"])
	var pending: bool = _g4_defer_pending
	_g4_defer_pending = false
	return pending

func set_sr_dda_pending(rank: int, is_upgrade: bool) -> void:
	_observe_fields(["_sr_dda_pending_is_upgrade", "_sr_dda_pending_rank"])
	_sr_dda_pending_rank = rank
	_sr_dda_pending_is_upgrade = is_upgrade

func get_sr_dda_pending_rank() -> int:
	_observe_fields(["_sr_dda_pending_rank"])
	return _sr_dda_pending_rank

func get_sr_dda_pending_is_upgrade() -> bool:
	_observe_fields(["_sr_dda_pending_is_upgrade"])
	return _sr_dda_pending_is_upgrade

func inc_11503_r3_played_count() -> void:
	_observe_fields(["_11503_r3_played_count"])
	_11503_r3_played_count += 1
	_save_data()

func inc_11503_r4_played_count() -> void:
	_observe_fields(["_11503_r4_played_count"])
	_11503_r4_played_count += 1
	_save_data()

func compute_11503_r3_probs() -> Vector2:
	_observe_fields(["_11503_r3_played_count"])
	var adj: int = _11503_r3_played_count / 2
	var r2: float = clampf(50.0 - 5.0 * adj, 30.0, 50.0)
	return Vector2(r2, 100.0 - r2)

func compute_11503_r4_probs() -> Vector3:
	_observe_fields(["_11503_r4_played_count"])
	var adj: int = _11503_r4_played_count / 2
	var r2: float = clampf(24.0 - 1.125 * adj, 15.0, 24.0)
	var r3: float = clampf(56.0 - 1.375 * adj, 45.0, 56.0)
	var r4: float = clampf(20.0 + 2.5 * adj, 20.0, 40.0)
	return Vector3(r2, r3, r4)

func compute_11503_r3_weights() -> PackedInt32Array:
	_observe_fields(["_11503_r3_played_count"])
	var adj: int = _11503_r3_played_count / 2
	var w_r2: int = clampi(400 - 40 * adj, 240, 400)
	var w_r3: int = 800 - w_r2
	return PackedInt32Array([w_r2, w_r3])

func compute_11503_r4_weights() -> PackedInt32Array:
	_observe_fields(["_11503_r4_played_count"])
	var adj: int = _11503_r4_played_count / 2
	var w_r2: int = clampi(192 - 9 * adj, 120, 192)
	var w_r3: int = clampi(448 - 11 * adj, 360, 448)
	var w_r4: int = clampi(160 + 20 * adj, 160, 320)
	return PackedInt32Array([w_r2, w_r3, w_r4])

func set_retry_puzzle(level: int, params: Dictionary) -> void:
	_observe_fields(["_retry_puzzle_level", "_retry_puzzle_params"])
	_retry_puzzle_level = level
	_retry_puzzle_params = params
	_save_data()

func get_retry_puzzle(level: int) -> Dictionary:
	_observe_fields(["_retry_puzzle_level", "_retry_puzzle_params"])
	if _retry_puzzle_level == level and not _retry_puzzle_params.is_empty():
		return _retry_puzzle_params
	return {}

func clear_retry_puzzle() -> void:
	_observe_fields(["_retry_puzzle_level", "_retry_puzzle_params"])
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_save_data()

func get_pre_cat_pending() -> Dictionary:
	_observe_fields(["_pre_cat_pending_demote", "_pre_cat_pending_hard", "_pre_cat_pending_struggle"])
	return {
		"hard": _pre_cat_pending_hard,
		"struggle": _pre_cat_pending_struggle,
		"demote": _pre_cat_pending_demote
	}

func begin_golden_fish_pre_cat_session(level_num: int, preserve_source: bool = false) -> void:
	_observe_fields(["_golden_fish_pre_cat_session"])
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

func _is_golden_fish_pre_cat_active(level_num: int) -> bool:
	_observe_fields(["_golden_fish_pre_cat_session"])
	return (
		not _golden_fish_pre_cat_session.is_empty()
		and int(_golden_fish_pre_cat_session.get("level", 0)) == level_num
		and not bool(_golden_fish_pre_cat_session.get("won", false))
		and not bool(_golden_fish_pre_cat_session.get("skipped", false))
	)

func has_golden_fish_pre_cat_followup(level_num: int) -> bool:
	_observe_fields(["_golden_fish_pre_cat_session"])
	return (
		level_num > 0
		and int(_golden_fish_pre_cat_session.get("level", 0)) == level_num
		and (
			bool(_golden_fish_pre_cat_session.get("won", false))
			or bool(_golden_fish_pre_cat_session.get("skipped", false))
		)
	)

func get_golden_fish_pre_cat_followup(
	level_num: int, include_golden_fish: bool, preserve_source: bool
) -> Dictionary:
	_observe_fields(["_golden_fish_pre_cat_session"])
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

func get_golden_fish_pre_cat_source(level_num: int) -> Dictionary:
	_observe_fields(["_golden_fish_pre_cat_session"])
	if not _is_golden_fish_pre_cat_active(level_num):
		return {}
	var source: Dictionary = _golden_fish_pre_cat_session.get("source", {}).duplicate(true)
	return source

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

func mark_golden_fish_pre_cat_revived(level_num: int) -> void:
	_observe_fields(["_golden_fish_pre_cat_session"])
	if (
		not _is_golden_fish_pre_cat_active(level_num)
		or bool(_golden_fish_pre_cat_session.get("revived", false))
	):
		return
	_golden_fish_pre_cat_session["revived"] = true
	_save_data()

func get_golden_fish_pre_cat_lock(level_num: int, puzzle_key: String) -> Dictionary:
	_observe_fields(["_golden_fish_pre_cat_session"])
	if not _is_golden_fish_pre_cat_active(level_num):
		return {}
	var lock: Dictionary = _golden_fish_pre_cat_session.get("lock", {})
	return lock.duplicate(true) if str(lock.get("puzzle_key", "")) == puzzle_key else {}

func set_golden_fish_pre_cat_lock(
	level_num: int,
	puzzle_key: String,
	pre_type: String,
	position: Vector2i,
	allow_pre_cat: bool = true,
	pending: Dictionary = {}
) -> void:
	_observe_fields(["_golden_fish_pre_cat_session"])
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

func get_pre_cat_fail_count(lv: int) -> int:
	_observe_fields(["_pre_cat_fail_count", "_pre_cat_fail_lv"])
	return _pre_cat_fail_count if _pre_cat_fail_lv == lv else 0

func mark_pre_cat_revived() -> void:
	_observe_fields(["_pre_cat_revived_this_level"])
	if _pre_cat_revived_this_level:
		return
	_pre_cat_revived_this_level = true
	_save_data()

func consume_pre_cat_pending() -> Dictionary:
	_observe_fields(["_pre_cat_pending_demote", "_pre_cat_pending_hard", "_pre_cat_pending_struggle"])
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

func get_pre_cat_lock(lv: int, pending: Dictionary = {}) -> Dictionary:
	_observe_fields(["_golden_fish_pre_cat_session", "_pre_cat_lock_lv", "_pre_cat_lock_pos", "_pre_cat_lock_pre_type"])
	if has_golden_fish_pre_cat_followup(lv):
		var main_lock: Dictionary = _golden_fish_pre_cat_session.get("main_lock", {})
		if bool(main_lock.get("locked", false)) and main_lock.get("pending", {}) == pending:
			return main_lock.duplicate(true)
		return {"locked": false, "pre_type": "0", "position": Vector2i(-1, -1)}
	if lv > 0 and _pre_cat_lock_lv == lv:
		return {"locked": true, "pre_type": _pre_cat_lock_pre_type, "position": _pre_cat_lock_pos}
	return {"locked": false, "pre_type": "0", "position": Vector2i(-1, -1)}

func set_pre_cat_lock(
	lv: int, pre_type: String, position: Vector2i, pending: Dictionary = {}
) -> void:
	_observe_fields(["_golden_fish_pre_cat_session", "_pre_cat_lock_lv", "_pre_cat_lock_pos", "_pre_cat_lock_pre_type"])
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

func was_last_level_clean_win() -> bool:
	_observe_fields(["_last_level_clean_win"])
	return _last_level_clean_win

func get_bank_index(sz: int, rank: int, tier: String = "") -> int:
	_observe_fields(["_bank_progress"])
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	return _bank_progress.get(key, 0)

func advance_bank_index(sz: int, rank: int, tier: String = "", persist: bool = true) -> void:
	_observe_fields(["_bank_progress"])
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_bank_progress[key] = _bank_progress.get(key, 0) + 1
	if persist:
		_save_data()

func get_main_progress(sz: int, rank: int, tier: String = "") -> Dictionary:
	_observe_fields(["_main_bank_progress"])
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	if not _main_bank_progress.has(key):
		_main_bank_progress[key] = {"lk_mod": 0, "regular": 0, "lkstyle": 0, "transform": 0}
	return _main_bank_progress[key]

func set_main_progress(
	sz: int, rank: int, tier: String, progress: Dictionary, persist: bool = true
) -> void:
	_observe_fields(["_main_bank_progress"])
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_main_bank_progress[key] = progress
	if persist:
		_save_data()

func ensure_super_hard_anchor(level_num: int) -> int:
	_observe_fields(["_super_hard_anchor"])
	if _super_hard_anchor <= 0:
		_super_hard_anchor = level_num
		_save_data()
	return _super_hard_anchor

func get_super_hard_anchor() -> int:
	_observe_fields(["_super_hard_anchor"])
	return _super_hard_anchor

func get_lkmod_progress(sz: int, rank: int) -> Dictionary:
	_observe_fields(["_lkmod_progress"])
	var key := "%d_%d" % [sz, rank]
	if not _lkmod_progress.has(key):
		_lkmod_progress[key] = {"idx": 0}
	return _lkmod_progress[key]

func set_lkmod_progress(sz: int, rank: int, progress: Dictionary, persist: bool = true) -> void:
	_observe_fields(["_lkmod_progress"])
	var key := "%d_%d" % [sz, rank]
	_lkmod_progress[key] = progress
	if persist:
		_save_data()

func get_bank_progress_snapshot() -> Dictionary:
	_observe_fields(["_bank_progress"])
	return _bank_progress.duplicate(true)

func get_level_selection_progress_snapshot() -> Dictionary:
	_observe_fields(["_bank_progress", "_lkmod_progress", "_main_bank_progress"])
	return {
		"bank_progress": _bank_progress.duplicate(true),
		"main_bank_progress": _main_bank_progress.duplicate(true),
		"lkmod_progress": _lkmod_progress.duplicate(true),
	}

func restore_level_selection_progress(snapshot: Dictionary) -> void:
	_observe_fields(["_bank_progress", "_lkmod_progress", "_main_bank_progress"])
	_bank_progress = (snapshot.get("bank_progress", {}) as Dictionary).duplicate(true)
	_main_bank_progress = (snapshot.get("main_bank_progress", {}) as Dictionary).duplicate(true)
	_lkmod_progress = (snapshot.get("lkmod_progress", {}) as Dictionary).duplicate(true)

func get_sp_tt_category_cursor() -> int:
	_observe_fields(["_sp_tt_category_cursor"])
	return _sp_tt_category_cursor

func get_sp_tt_last_replaced_level() -> int:
	_observe_fields(["_sp_tt_last_replaced_level"])
	return _sp_tt_last_replaced_level

func get_sp_tt_progress(category: int, sz: int, rank: int) -> Dictionary:
	_observe_fields(["_sp_tt_progress"])
	var key := "%d_%d_%d" % [category, sz, rank]
	if not _sp_tt_progress.has(key):
		_sp_tt_progress[key] = {"idx": 0, "t_pos": 0}
	return _sp_tt_progress[key]

func commit_sp_tt_delivery(
	level_num: int, category: int, sz: int, rank: int, progress: Dictionary, next_cursor: int
) -> void:
	_observe_fields(["_sp_tt_category_cursor", "_sp_tt_last_replaced_level", "_sp_tt_progress"])
	_sp_tt_progress["%d_%d_%d" % [category, sz, rank]] = progress
	_sp_tt_category_cursor = next_cursor
	_sp_tt_last_replaced_level = level_num
	_save_data()

func commit_returnee_sp_tt_delivery(
	category: int, sz: int, rank: int, progress: Dictionary, next_cursor: int
) -> void:
	_observe_fields(["_sp_tt_category_cursor", "_sp_tt_progress"])
	_sp_tt_progress["%d_%d_%d" % [category, sz, rank]] = progress
	_sp_tt_category_cursor = next_cursor
	_save_data()

func get_single_region_supp_progress(sz: int, rank: int) -> Dictionary:
	_observe_fields(["_single_region_supp_progress"])
	var key := "%d_%d" % [sz, rank]
	if not _single_region_supp_progress.has(key):
		_single_region_supp_progress[key] = {"idx": 0}
	return _single_region_supp_progress[key]

func get_elo_aux_single_region_progress(sz: int, rank: int) -> Dictionary:
	_observe_fields(["_elo_aux_single_region_progress"])
	var key := "%d_%d" % [sz, rank]
	if not _elo_aux_single_region_progress.has(key):
		_elo_aux_single_region_progress[key] = {"idx": 0}
	return _elo_aux_single_region_progress[key]

func commit_elo_aux_single_region_delivery(sz: int, rank: int, progress: Dictionary) -> void:
	_observe_fields(["_elo_aux_single_region_progress"])
	_elo_aux_single_region_progress["%d_%d" % [sz, rank]] = progress
	_save_data()

func get_elo_aux_climax_progress(sz: int, rank: int) -> Dictionary:
	_observe_fields(["_elo_aux_climax_progress"])
	var key := "%d_%d" % [sz, rank]
	if not _elo_aux_climax_progress.has(key):
		_elo_aux_climax_progress[key] = {"idx": 0, "t_pos": 0}
	return _elo_aux_climax_progress[key]

func commit_elo_aux_climax_delivery(sz: int, rank: int, progress: Dictionary) -> void:
	_observe_fields(["_elo_aux_climax_progress"])
	_elo_aux_climax_progress["%d_%d" % [sz, rank]] = progress
	_save_data()

func commit_single_region_supp_delivery(sz: int, rank: int, progress: Dictionary) -> void:
	_observe_fields(["_single_region_supp_progress"])
	_single_region_supp_progress["%d_%d" % [sz, rank]] = progress
	_save_data()

func get_climax_filter_progress(sz: int, rank: int, single_count: int) -> Dictionary:
	_observe_fields(["_climax_filter_progress"])
	var key := "%d_%d_%d" % [sz, rank, single_count]
	if not _climax_filter_progress.has(key):
		_climax_filter_progress[key] = {"idx": 0, "t_pos": 0}
	return _climax_filter_progress[key]

func commit_climax_filter_delivery(
	sz: int, rank: int, single_count: int, progress: Dictionary
) -> void:
	_observe_fields(["_climax_filter_progress"])
	_climax_filter_progress["%d_%d_%d" % [sz, rank, single_count]] = progress
	_save_data()

func get_lk_mod_g2_last_replaced_level() -> int:
	_observe_fields(["_lk_mod_g2_last_replaced_level"])
	return _lk_mod_g2_last_replaced_level

func commit_lk_mod_g2_delivery(level_num: int, sz: int, rank: int, new_idx: int) -> void:
	_observe_fields(["_lk_mod_g2_last_replaced_level", "_lkmod_progress"])
	_lkmod_progress["%d_%d" % [sz, rank]] = {"idx": new_idx}
	_lk_mod_g2_last_replaced_level = level_num
	_save_data()

func get_sp_tt_lk_alt_last_replaced_level() -> int:
	_observe_fields(["_sp_tt_lk_alt_last_replaced_level"])
	return _sp_tt_lk_alt_last_replaced_level

func get_sp_tt_lk_alt_block_source() -> String:
	_observe_fields(["_sp_tt_lk_alt_block_source"])
	return _sp_tt_lk_alt_block_source

func get_sp_tt_lk_alt_block_count() -> int:
	_observe_fields(["_sp_tt_lk_alt_block_count"])
	return _sp_tt_lk_alt_block_count

func commit_sp_tt_lk_alt_delivery(level_num: int, new_source: String, new_count: int) -> void:
	_observe_fields(["_sp_tt_lk_alt_block_count", "_sp_tt_lk_alt_block_source", "_sp_tt_lk_alt_last_replaced_level"])
	_sp_tt_lk_alt_last_replaced_level = level_num
	_sp_tt_lk_alt_block_source = new_source
	_sp_tt_lk_alt_block_count = new_count
	_save_data()

func get_downgrade_special_pending_level() -> int:
	_observe_fields(["_downgrade_special_pending_level"])
	return _downgrade_special_pending_level

func set_downgrade_special_pending_level(value: int) -> void:
	_observe_fields(["_downgrade_special_pending_level"])
	_downgrade_special_pending_level = value
	_save_data()

func get_normal_pass_time_records() -> Array:
	_observe_fields(["_normal_pass_time_records"])
	return _normal_pass_time_records.duplicate(true)

func ensure_nl11701_shuffle_seed() -> int:
	_observe_fields(["_nl11701_shuffle_seed"])
	if _nl11701_shuffle_seed != 0:
		return _nl11701_shuffle_seed
	var rng: RandomNumberGenerator = _rng
	var s: int = 0
	while s == 0:
		s = rng.randi()
	_nl11701_shuffle_seed = s
	_save_data()
	return _nl11701_shuffle_seed

func get_nl_v6_alternate_r4_count_before(level_num: int) -> int:
	_observe_fields(["_nl_v6_alternate_r4_count", "_nl_v6_alternate_r4_level"])
	if _nl_v6_alternate_r4_level == level_num:
		return _nl_v6_alternate_r4_count - 1
	return _nl_v6_alternate_r4_count

func record_nl_v6_alternate_delivery(
	level_num: int, is_main_r4: bool, persist: bool = true
) -> void:
	_observe_fields(["_nl_v6_alternate_r4_count", "_nl_v6_alternate_r4_level"])
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

func get_nl_v6_pool_progress(key: String) -> Dictionary:
	_observe_fields(["_nl_v6_pool_progress"])
	if not _nl_v6_pool_progress.has(key):
		_nl_v6_pool_progress[key] = {"idx": 0, "transform": 0}
	return _nl_v6_pool_progress[key]

func set_nl_v6_pool_progress(key: String, progress: Dictionary, persist: bool = true) -> void:
	_observe_fields(["_nl_v6_pool_progress"])
	_nl_v6_pool_progress[key] = progress
	if persist:
		_save_data()

func get_nl_v6_alt_state(key: String) -> Dictionary:
	_observe_fields(["_nl_v6_alt_state"])
	var state: Dictionary = _nl_v6_alt_state.get(key, {"ids": [], "round": 0})
	return state.duplicate(true)

func set_nl_v6_alt_state(key: String, state: Dictionary, persist: bool = true) -> void:
	_observe_fields(["_nl_v6_alt_state"])
	_nl_v6_alt_state[key] = state.duplicate(true)
	if persist:
		_save_data()

func get_recent_puzzles() -> Array:
	_observe_fields(["_recent_puzzles"])
	return _recent_puzzles.duplicate(true)

func get_recent_puzzle_count() -> int:
	_observe_fields(["_recent_puzzles"])
	return _recent_puzzles.size()

func get_recent_iso_signatures(limit: int) -> Array:
	_observe_fields(["_recent_puzzles"])
	var result: Array = []
	var start: int = maxi(0, _recent_puzzles.size() - limit)
	for i: int in range(start, _recent_puzzles.size()):
		var sig: Array = _recent_puzzles[i].get("iso_sig", [])
		if not sig.is_empty():
			result.append(sig)
	return result

func get_recent_style_vectors(limit: int) -> Array:
	_observe_fields(["_recent_puzzles"])
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

func find_recent_puzzle(puzzle_id: String) -> Dictionary:
	_observe_fields(["_recent_puzzles"])
	for i: int in range(_recent_puzzles.size() - 1, -1, -1):
		var entry: Dictionary = _recent_puzzles[i]
		if entry.get("puzzle_id", "") == puzzle_id:
			return entry.duplicate(true)
	return {}

func get_latest_selected_normal_level_group(level_num: int) -> int:
	_observe_fields(["_recent_puzzles"])
	for i: int in range(_recent_puzzles.size() - 1, -1, -1):
		var entry: Dictionary = _recent_puzzles[i]
		if int(entry.get("level", -1)) == level_num:
			return int(entry.get("nl", -1))
	return -1

func finalize_selected_puzzle(
	level_num: int, puzzle_record: Dictionary, retry_params: Dictionary
) -> void:
	_observe_fields(["_bank_progress", "_lkmod_progress", "_main_bank_progress", "_recent_puzzles", "_retry_puzzle_level", "_retry_puzzle_params", "_sp_tt_progress"])
	var record: Dictionary = puzzle_record.duplicate(true)
	record["level"] = level_num
	record["ts"] = _now_unix
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

func get_endgame_snapshot() -> Dictionary:
	_observe_fields(["_endgame_snapshot"])
	return _endgame_snapshot

func clear_endgame_snapshot() -> void:
	_observe_fields(["_endgame_snapshot"])
	if _endgame_snapshot.is_empty():
		return
	_endgame_snapshot = {}
	_save_endgame()
	print("[Endgame] cleared")


func _save_endgame() -> void:
	pass


func base_candidate() -> Dictionary:
	return _original_candidate.duplicate(true)


func selection_context() -> Dictionary:
	return _selection_context.duplicate(true)


const PROFILE_FIELDS: Array[String] = ["active_days", "bank_progress", "bsz11801_cycle_hits", "bsz11802_dyn_size", "bsz11802_last_delivered_size", "bsz11802_stuck_streak", "cc_delivered", "cc_pending", "cc_progress", "cc_since_gf", "chain_g3_streak", "chain_last_replaced_level", "climax_filter_progress", "consecutive_clean_wins", "consecutive_fails", "consecutive_retry_levels", "current_level", "current_strategy", "daily_auto_mark_enabled", "daily_first_easy_date", "daily_first_win_entry_date", "diff_diff_r3_played_count", "diff_diff_r4_played_count", "downgrade_special_pending_level", "elo_active_puzzle_rating", "elo_active_rank", "elo_aux_climax_progress", "elo_aux_single_region_progress", "elo_band_r3", "elo_band_r4", "elo_band_r5", "elo_fish_consumed", "elo_games_r3", "elo_games_r4", "elo_games_r5", "elo_group2_cohort", "elo_init_r3", "elo_init_r4", "elo_init_r5", "elo_rating_r3", "elo_rating_r4", "elo_rating_r5", "elo_selected_pids", "elo_v2_attempt", "elo_v2_source_selected_ids", "elo_v2_won_styles", "g4_defer_pending", "g4_pressure_level_num", "game_barrage_daily_keys", "golden_fish_career_count", "golden_fish_insert_delivered", "golden_fish_pending", "golden_fish_pre_cat_session", "golden_fish_streak_count", "golden_fish_tutorial_shown", "insert_gf_wrong_cat_num", "last_day_session_count", "last_hard_level", "last_level_clean_win", "last_main_win_date", "lk_mod_g2_last_replaced_level", "lkmod_progress", "main_bank_progress", "nl11701_shuffle_seed", "nl_v6_alt_state", "nl_v6_alternate_r4_count", "nl_v6_alternate_r4_level", "nl_v6_pool_progress", "normal_pass_time_records", "onefish_consecutive_skips", "onefish_consecutive_wins", "onefish_cycle_rounds", "onefish_pick_switch_anchor", "onefish_progress", "onefish_shuffle_cursors", "onefish_shuffle_group", "onefish_shuffle_orders", "onefish_used_bits", "pattern_mode_before_cc", "pattern_mode_on", "pending_rewards", "pre_cat_fail_count", "pre_cat_fail_lv", "pre_cat_lock_lv", "pre_cat_lock_pos", "pre_cat_lock_pre_type", "pre_cat_pending_demote", "pre_cat_pending_hard", "pre_cat_pending_struggle", "pre_cat_revived_this_level", "rating_selected_pids", "recent_puzzles", "recent_win_counts_by_day", "restored_today_count", "retry_puzzle_level", "retry_puzzle_params", "retry_tracking_strategy", "returnee_current_level", "returnee_from_endgame_save", "returnee_frozen_dda", "returnee_frozen_strategy", "returnee_group", "returnee_lkmod_resume_level", "returnee_lower", "returnee_remaining", "returnee_upper", "single_region_supp_progress", "sp_tt_category_cursor", "sp_tt_last_replaced_level", "sp_tt_lk_alt_block_count", "sp_tt_lk_alt_block_source", "sp_tt_lk_alt_last_replaced_level", "sp_tt_progress", "super_hard_anchor", "today_active_sec", "today_cat_found", "today_date", "today_mark_placed", "today_played_count", "today_revive_count", "today_session_count", "today_tool_consumed"]


func reset_game_round_stats(game_type: String) -> void:
	_observe_fields(["_daily_game_round_stats", "_main_game_round_stats"])
	if game_type == "daily":
		_daily_game_round_stats = {}
	else:
		_main_game_round_stats = {}


func stage_daily_entry(date: String, replay: bool, restoring: bool, auto_mark_variant: int) -> void:
	_observe_fields(["_daily_game_round_stats"])
	_candidate.get("profile", {})["daily_started_date"] = date
	if not restoring:
		_candidate.get("endgame", {})["daily_snapshot"] = {}
		_daily_game_round_stats = {}
		var stats: Dictionary = _candidate.get("endgame", {}).get("stats", {})
		stats["daily_steps"] = {}
		if not replay:
			stats["daily_total"] = {}


func on_color_challenge_settled() -> void:
	_observe_fields(["_color_challenge_pending", "_color_challenge_since_gf", "_pattern_mode_before_color_challenge", "_pattern_mode_on"])
	_color_challenge_pending = false
	_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED
	_candidate.get("profile", {})["color_challenge_skip_count"] = 0
	_candidate.get("profile", {})["color_challenge_defer_until"] = 0
	if _pattern_mode_before_color_challenge >= 0:
		_pattern_mode_on = _pattern_mode_before_color_challenge == 1
		_pattern_mode_before_color_challenge = -1


func get_today_cat_found() -> int:
	_observe_fields(["_today_cat_found"])
	_roll_day_if_needed()
	return _today_cat_found


func get_today_mark_placed() -> int:
	_observe_fields(["_today_mark_placed"])
	_roll_day_if_needed()
	return _today_mark_placed


## 冲突检查只覆盖真正经过的业务读路径；未参与入场的统计可继续更新。
func _observe_fields(names: Array) -> void:
	for name: String in names:
		_observed_fields[name] = true


func observed_selection_fields() -> Array:
	var result: Array = []
	for name: String in _observed_fields:
		if FIELD_MAP.has(name):
			result.append(FIELD_MAP[name].duplicate(true))
		elif RUNTIME_FIELDS.has(name):
			result.append({"section": "round_runtime", "key": name.trim_prefix("_")})
	return result
