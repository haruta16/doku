## 1.22 选题的候选状态。所有 setter 只改变私有副本；落盘、信号和外部服务由用例提交后处理。
## API 保留原策略语义，候选失败直接丢弃，不回滚真实 GameState。
class_name DokuSelectionState
extends RefCounted

var _observed_fields: Dictionary = {} # 本次业务路径访问过的字段名集合，导出后用于提交前冲突检查。
var _candidate: Dictionary = {} # 可编辑的核心快照底板；保留 FIELD_MAP 之外的分区及入口直接写入的数据。
var _original_candidate: Dictionary = {} # 创建候选时的原始快照；始终作为预期旧值，不能随 setter 更新。
var _selection_context: Dictionary = {} # 入口冻结的规则、时间与依赖；Array/Dictionary 被复制，资源对象仍按引用传递。
var _today: String = "" # 本次尝试固定使用的日期，避免选题中途跨日导致条件不一致。
var _returnee_gap_days: int = 2 # 回流判定所需的离线天数阈值，来自冻结配置。
var _now_unix: int = 0 # 本次尝试的 Unix 时间（秒），用于最近题目记录。
var _rng: RandomNumberGenerator # 创建时可接收 runtime 的随机源；未提供对象时按 context.seed 初始化。
var events: Array[Dictionary] = [] # 候选内产生的待发布事件；成功提交前不能当作已发生的外部通知。
const RECENT_PUZZLES_LIMIT := 100 # 最近出题记录的上限（超出丢最旧的）

const ENDGAME_SNAPSHOT_VERSION: int = 2 # 残局快照结构版本号

const ELO_SELECTED_MAX: int = 2000

const RATING_SELECTED_MAX: int = 2000

const CLOUD_TOOL_KINDS: Array[String] = ["locate", "hint", "draft", "mouse"]

var _current_level: int = 1 # 主线当前关号，来自 profile.current_level。

var _last_hard_level: int = 0 # 最近标记为困难关的主线关号，用于间隔/去重判定。

var _current_strategy: int = 1 # 当前提示策略层 R1~R6，由 DDA 升降

var _consecutive_clean_wins: int = 0 # 连续「干净通关」次数，够阈值就升一层

var _last_level_clean_win: bool = false # 上一关是否干净通关

var _consecutive_fails: int = 0 # 连续失败次数，够阈值就降一层

var _consecutive_retry_levels: int = 0 # 连续重试同一关的关数（重试降档用）

var _retry_tracking_strategy: int = 0 # 统计连续重试时所在的策略层

var _bank_progress: Dictionary = {} # 基础题库游标：尺寸_段位（可带 _H）→ 累计交付位置。

var _main_bank_progress: Dictionary = {} # 新版题库进度：key → {lk_mod, regular, lkstyle, transform}

var _lkmod_progress: Dictionary = {} # lkmod 玩法进度："尺寸_段位" → {idx}

var _super_hard_anchor: int = 0 # 超级困难关周期的起始关号；0 表示尚未建立锚点。

var _sp_tt_category_cursor: int = 1 # SP/TT 特殊题下次选择的类别游标。

var _sp_tt_last_replaced_level: int = 0 # 最近由 SP/TT 替换的普通主线关号。

var _sp_tt_progress: Dictionary = {} # 类别_尺寸_段位 → {idx, t_pos}，分别保存题目与变换进度。

var _lk_mod_g2_last_replaced_level: int = 0 # LK Mod G2 最近完成替换的主线关号。

var _sp_tt_lk_alt_last_replaced_level: int = 0 # SP/TT 与 LK 交替方案最近替换的关号。

var _sp_tt_lk_alt_block_source: String = "sp_tt" # 当前连续来源块的类型，例如 sp_tt；与 block_count 配合轮换。

var _sp_tt_lk_alt_block_count: int = 0 # 当前来源块已经累计交付的题数。

var _downgrade_special_pending_level: int = 0 # 降档特殊题等待处理的关号；0 表示没有待处理项。

var _single_region_supp_progress: Dictionary = {} # 单格区域补充池：尺寸_段位 → {idx}。

var _climax_filter_progress: Dictionary = {} # 筛选池：尺寸_段位_单格数 → {idx, t_pos}。

var _elo_aux_single_region_progress: Dictionary = {} # Elo 辅助单格区域池的独立游标，避免与普通补充池互相推进。

var _elo_aux_climax_progress: Dictionary = {} # Elo 辅助高潮池的题目/变换游标。

var _nl11701_shuffle_seed: int = 0 # 11701 题库固定洗牌种子；0 表示尚未生成。

var _normal_pass_time_records: Array = [] # 普通关历史通关耗时记录，供选题策略评估节奏。

var _nl_v6_alternate_r4_count: int = 0 # V6 交替方案累计交付的主池 R4 次数。

var _nl_v6_alternate_r4_level: int = 0 # 最近一次已计入 R4 次数的关号，避免同关重选重复累计。

var _nl_v6_pool_progress: Dictionary = {} # V6 各题池的 {idx, transform} 进度。

var _nl_v6_alt_state: Dictionary = {} # V6 交替池的已用 ID 与轮次记录。

var _daily_first_easy_date: String = "" # 最后一次用掉「首次降档」机会的日期

var _main_game_round_stats: Dictionary = {} # 普通模式本局统计（键见 Tracker._ROUND_STAT_KEYS）

var _daily_game_round_stats: Dictionary = {} # 每日挑战本局统计

var _tool_locate: int = 5

var _tool_hint: int = 5 # 提示道具数量（初始 5）

var _tool_mouse: int = 2

var _tool_draft: int = 5

var _recent_win_counts_by_day: Dictionary = {} # 日期 → 当日胜场数；日切时仅保留近期窗口。

var _last_main_win_date: String = "" # 最近一次主线获胜日期，用于今日主线首胜判断。

var _daily_first_win_entry_date: String = "" # 每日首胜入口最近展示日期，避免同日重复触发。

var _pattern_mode_on: bool = false # 当前图案辅助模式；彩色挑战会暂存并临时覆盖它。

var _today_date: String = "" # 日切时记下的「今天」，用于判断是否需要跨天重置

var _today_session_count: int = 0 # 今日会话数

var _last_day_session_count: int = 0 # 昨日会话数（日切时从 today 挪过来）

var _active_days: int = 0 # 活跃天数（每次日切 +1，Helpshift 也用）

var _returnee_group: int = 0 # 当前回流实验组，0 表示没有普通回流组任务。

var _returnee_from_endgame_save: bool = false # 本轮降难是否来自过期残局处理。

var _returnee_remaining: int = 0 # 当前回流组剩余可交付关数，固定特殊题是否扣减由策略规则决定。

var _returnee_lower: int = 1 # 回流选题允许的策略下界。

var _returnee_upper: int = 1 # 回流选题经过降难规则计算后的策略上界。

var _returnee_frozen_strategy: int = 1 # 进入回流流程前的策略层，供结束后恢复。

var _returnee_previous_login_date: String = "" # 本次登录之前的登录日期，来自 round_runtime。

var _returnee_level_at_login: int = 0 # 登录时的主线进度；判定回流门槛不随本次候选推进。

var _returnee_started_this_cold_start: bool = false # 本次冷启动是否已经开启回流流程，避免重复启动。

var _returnee_current_level: int = 0 # 当前归属回流流程的主线关号。

var _returnee_lkmod_resume_level: int = 0 # 回流流程结束后衔接 LK Mod 的关号记录。

var _returnee_frozen_dda: Dictionary = {} # 回流开始前保存的连胜、失败、重试和待降档状态。

var _stale_endgame_discarded: bool = false # 入口是否已经暂存丢弃过期残局的决定。

var _comeback_welcome_shown: bool = false # 回归欢迎入口是否已经展示，约束后续首胜消费。

var _comeback_start_level: int = 0 # 回归欢迎后的首个有效主线关号；0 表示尚未认领。

var _comeback_main_win_consumed: bool = false # 回归主线首胜机会是否已被消费。

var _today_played_count: int = 0 # 今日已开局数

var _today_tool_consumed: int = 0 # 本日消耗道具的累计数量，日切时清零。

var _today_revive_count: int = 0 # 本日复活次数，日切时清零。

var _today_active_sec: int = 0 # 今日前台活跃秒数（SessionManager 每 60 秒累加）

var _today_cat_found: int = 0 # 本日找到猫的累计数量。

var _today_mark_placed: int = 0 # 本日放置标记的累计数量。

var _game_barrage_daily_keys: PackedStringArray = PackedStringArray() # 当日已触发弹幕的去重键集合。

# Elo 按 R3/R4/R5 分别保存玩家评分、结算局数、初始化标记与评分档位，段位之间不共用一份状态。
var _elo_rating_r3: float = 0.0

var _elo_rating_r4: float = 0.0

var _elo_rating_r5: float = 0.0

var _elo_games_r3: int = 0

var _elo_games_r4: int = 0

var _elo_games_r5: int = 0

var _elo_init_r3: bool = false

var _elo_init_r4: bool = false

var _elo_init_r5: bool = false

var _elo_group2_cohort: int = -1 # Elo 第二组固定人群：-1 未判定，1 新玩家，0 老玩家。

var _elo_band_r3: int = 0

var _elo_band_r4: int = 0

var _elo_band_r5: int = 0

var _elo_active_rank: int = 0 # 当前 Elo 题目交付时的段位。

var _elo_active_puzzle_rating: float = 0.0 # 当前交付题目的评分，用于结算时与玩家评分比较。

var _elo_fish_consumed: int = 0 # Elo 流程累计的金鱼消耗事实。

var _elo_selected_pids: Array = [] # Elo 选题已经交付的题目哈希，按时间保留最近 ELO_SELECTED_MAX 项。

var _rating_selected_pids: Array = [] # Rating 选题的独立去重哈希列表，不与 Elo 的已选集合混用。

var _elo_v2_attempt: Dictionary = {} # 以关号和题目 ID 绑定的一次 Elo V2 尝试，重试继续累积行为事实。

var _elo_v2_won_styles: Array = [] # 历史 Elo V2 获胜题目的风格记录。

var _elo_v2_source_selected_ids: Dictionary = {} # 来源键 → 已选择条目 ID 列表；ID 只在对应来源内有意义。

var _pending_rewards: Array = []

var _restored_today_count: int = 0 # 今日已找回次数（上限 3）

var _daily_auto_mark_enabled: bool = false

var _retry_puzzle_level: int = 0 # 重试缓存所属关号；必须与请求关号匹配才可复用。

var _retry_puzzle_params: Dictionary = {} # 重试时要复用的题库参数（配合 _retry_puzzle_level 校验）

var _insert_golden_fish_wrong_cat_num: int = 0

var _pre_cat_fail_lv: int = 0 # 预填猫失败次数对应的关号，防止跨关继承失败计数。

var _pre_cat_fail_count: int = 0 # 对应关号累计失败次数，决定是否触发挣扎预填。

var _pre_cat_revived_this_level: bool = false # 本关是否已经复活，参与预填资格判定。

var _pre_cat_pending_hard: bool = false # 下一次主线入场待消费的困难关预填来源。

var _pre_cat_pending_struggle: bool = false # 下一次主线入场待消费的挣扎预填来源。

var _pre_cat_pending_demote: bool = false # 下一次主线入场待消费的降档预填来源。

var _pre_cat_lock_lv: int = 0 # 普通预填锁所属关号，同关重选复用已确定的结果。

var _pre_cat_lock_pre_type: String = "0" # 已锁定的预填来源类型，字符串 0 表示无来源。

var _pre_cat_lock_pos: Vector2i = Vector2i(-1, -1) # 锁定的棋盘坐标；(-1, -1) 表示没有预填位置。

var _golden_fish_pre_cat_session: Dictionary = {} # 金鱼插入期间冻结的预填来源、失败/复活事实及题目锁。

var _recent_puzzles: Array = [] # 最近出过的题目记录（含题库进度快照，用于去重与回滚）

var _endgame_snapshot: Dictionary = {} # 核心候选 endgame.snapshot 中的主线残局，不在这里读写独立文件。

var _golden_fish_streak_count: int = 0

var _golden_fish_pending: bool = false # 是否排队等待交付金鱼插入题；回流期间可能被暂缓。

var _golden_fish_tutorial_shown: bool = false # 金鱼教程是否已展示，候选提交后才成为持久去重标记。

var _onefish_consecutive_wins: int = 0

var _onefish_consecutive_skips: int = 0

var _onefish_progress: Dictionary = {} # 顺序金鱼池的交付游标，按尺寸_段位分组。

var _onefish_shuffle_orders: Dictionary = {} # 由同组未用题目生成的洗牌顺序；已消费前缀由游标跳过。

var _onefish_shuffle_cursors: Dictionary = {} # 洗牌顺序中的下次读取位置；成功候选交付时才推进。

var _onefish_used_bits: Dictionary = {} # 每组本轮已用题目的位图；每个题目索引占一位。

var _onefish_cycle_rounds: Dictionary = {} # 每组完整用完题池的轮次数。

var _onefish_shuffle_group: int = -1 # 构造现有洗牌缓存的实验组；切组时重建顺序。

var _onefish_pick_switch_anchor: int = 0 # 切换金鱼抽取组时的累计交付数，供间隔计算。

var _golden_fish_insert_delivered: int = 0 # 金鱼插入题累计交付次数，选中候选时暂存增长。

var _golden_fish_career_count: int = 0 # 金鱼已结算次数，由结算入口增长。

var _color_challenge_since_gf: int = ColorChallengeGate.NOT_STARTED # 距金鱼结算的彩色挑战门控状态；使用 ColorChallengeGate 哨兵值。

var _color_challenge_pending: bool = false # 是否已有待交付的彩色挑战。

var _color_challenge_delivered: int = 0 # 彩色挑战累计交付次数，覆盖题面交付也计入。

var _color_challenge_progress: Dictionary = {} # 尺寸_段位 → 彩色挑战题库游标。

var _pattern_mode_before_color_challenge: int = -1 # 进入彩色挑战前的图案模式：-1 未暂存，0 关闭，1 开启。

var _chain_last_replaced_level: int = 0 # Chain 特殊题最近替换的主线关号。

var _chain_g3_streak: int = 0 # Chain 第三组当前累计的连击计数。

var _bsz11801_cycle_hits: int = 0 # 11801 尺寸策略的周期命中次数。

var _bsz11802_dyn_size: int = 8 # 11802 动态棋盘边长，单位格。

var _bsz11802_last_delivered_size: int = 0 # 11802 最近一次实际交付的棋盘边长，单位格。

var _bsz11802_stuck_streak: int = 0 # 11802 尺寸调整所依据的连续卡关计数。

var _g4_pressure_level_num: int = 0 # G4 压力关的关号；0 表示尚未标记。

var _g4_defer_pending: bool = false # G4 流程是否还有一次待处理的延后状态。

var _current_level_dirty: bool = false # 本局是否动过道具/复活（脏了就没有干净通关连击）

var _demoted_this_level: bool = false # 本关是否已经降过档（一关最多降一次）

var _dda_tool_or_revive_used: bool = false # 本局是否用过道具或复活（DDA 降档判据）

var _dda_pending_demote: bool = false # 待执行的降档（下一关是困难/特殊关时先挂起）

var _is_daily_first_easy_level: bool = false # 本局是否走了「每日首次降档」

var _chain_g2_pending: bool = false # Chain 第二组等待消费的一次替换标记。

var _sr_dda_pending_rank: int = 0 # 单格区域 DDA 延后处理的目标段位。

var _sr_dda_pending_is_upgrade: bool = false # 上述延后调整是否为升档，区别于降档处理。

var _11503_r3_played_count: int = 0 # 11503 在 R3 层的交付次数，每两次调整一次抽取权重。

var _11503_r4_played_count: int = 0 # 11503 在 R4 层的交付次数，每两次调整一次抽取权重。

var _daily_first_easy_available: bool = false # 今日是否还能享受首次降档（启动时评估一次）

var _daily_first_easy_evaluated: bool = false # 本次启动是否已评估过首次降档

var _dc_start_toast_pct: Dictionary = {} # 每日挑战开局提示的临时百分比数据；日切清空。

# 私有字段 ↔ 核心存档分区/键的映射；构造时装入、导出时写回。type 记录字段契约，本类不据此强制转换。
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
# 这些局内字段也随候选导入/导出，保存于 round_runtime；键名去掉开头下划线。
const RUNTIME_FIELDS: Array[String] = ["_chain_g2_pending", "_comeback_main_win_consumed", "_comeback_start_level", "_comeback_welcome_shown", "_current_level_dirty", "_daily_first_easy_available", "_daily_first_easy_evaluated", "_dc_start_toast_pct", "_dda_pending_demote", "_dda_tool_or_revive_used", "_demoted_this_level", "_is_daily_first_easy_level", "_returnee_level_at_login", "_returnee_previous_login_date", "_returnee_started_this_cold_start", "_sr_dda_pending_is_upgrade", "_sr_dda_pending_rank", "_stale_endgame_discarded"]

## 深拷贝核心快照，按映射装入策略字段，并保留一份永不随候选修改的原始基线。
## 上下文固定日期和配置；若 runtime 已提供随机源则共用，否则按 seed 建立本地随机源。
func _init(candidate: Dictionary = {}, context: Dictionary = {}) -> void:
	_candidate = candidate.duplicate(true)
	# 底板会承接直接写入，字段也会变化；另留独立原始快照，才能检查准备期间真实状态是否已更新。
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


## 把当前字段合回核心快照的深拷贝，保留未由本类接管的其他分区。
## 返回的是待提交数据；方法名中的 commit/save 都不会让本类自行写盘。
func export_candidate() -> Dictionary:
	# 先保留完整底板，再覆盖映射字段；否则只序列化本类字段会丢掉奖励、推荐等其他分区。
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


## 导出当前候选的完整状态快照；与 base_candidate 的修改前快照不同。
func snapshot() -> Dictionary:
	return export_candidate()


## 返回入口冻结的日期，不在策略执行途中重新读取系统时钟。
func _today_str() -> String:
	return _today


## 保留旧策略 setter 的调用形状，此处刻意为空。
## 候选能否生效由外层事务决定；在这里保存会使试选失败仍污染真实进度。
func _save_data() -> void:
	pass


## 深拷贝普通 Array/Dictionary 以隔离嵌套容器；其他 Variant 按原值返回。
static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value


## 按点分路径取得嵌套分区引用；缺失且允许 create 时在 root 内补建字典，否则返回空字典。
static func _section(root: Dictionary, path: String, create: bool = false) -> Dictionary:
	var section: Dictionary = root
	for part: String in path.split("."):
		if not section.has(part):
			if not create:
				return {}
			section[part] = {}
		section = section[part]
	return section


## 读取候选主线关号，并把该字段登记为提交时需要核对的依赖。
func get_current_level() -> int:
	_observe_fields(["_current_level"])
	return _current_level

## 取得最近一次困难关标记的关号，供困难关间隔判断。
func get_last_hard_level() -> int:
	_observe_fields(["_last_hard_level"])
	return _last_hard_level

## 在候选中记录困难关关号；同一关重复标记不再变化。
func mark_hard_level(level_num: int) -> void:
	_observe_fields(["_last_hard_level"])
	if _last_hard_level == level_num:
		return
	_last_hard_level = level_num
	_save_data()

## 读取入口冻结/候选评估后的每日首次降档资格，不在这里重新评估残局。
func is_daily_first_easy_available() -> bool:
	_observe_fields(["_daily_first_easy_available"])
	return _daily_first_easy_available

## 每次冷启动仅评估一次首次降档资格：已消费或同关有实际操作的存活残局都会使资格失效。
## 所有日期和标记只写候选；预填猫不算玩家已经操作。
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
			# 系统预填位置已经在 placed_cats 中，必须扣除，不能把自动帮助误判为玩家开始操作。
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

## 把冻结日期记为机会消费日，并关闭候选中的可用标记。
func consume_daily_first_easy() -> void:
	_observe_fields(["_daily_first_easy_available", "_daily_first_easy_date"])
	_daily_first_easy_date = _today_str()
	_daily_first_easy_available = false
	_save_data()

## 消费每日机会，同时标明当前关确实走过首次降档，供之后结算使用。
func consume_daily_first_easy_and_mark() -> void:
	_observe_fields(["_is_daily_first_easy_level"])
	consume_daily_first_easy()
	_is_daily_first_easy_level = true

## 当记录落后于本次日期时推进消费日，防止跨天开始新局重新获得同一流程的机会。
func advance_daily_first_easy_date() -> void:
	_observe_fields(["_daily_first_easy_available", "_daily_first_easy_date"])
	var today: String = _today_str()
	if _daily_first_easy_date >= today:
		return
	_daily_first_easy_date = today
	_daily_first_easy_available = false
	_save_data()
	print("[DailyFirstEasy] 局内跨天+开始新对局, 推进日期消耗机会")

## 读取候选的图案模式开关，彩色挑战入口可能已临时将它开启。
func is_pattern_mode_on() -> bool:
	_observe_fields(["_pattern_mode_on"])
	return _pattern_mode_on

## 取得候选当前 DDA 策略层；这不是重新读取实验组。
func get_current_strategy() -> int:
	_observe_fields(["_current_strategy"])
	return _current_strategy

## 暂存 DDA 目标层级；数值边界由调用它的策略负责，本方法不夹取范围。
func set_current_strategy(value: int) -> void:
	_observe_fields(["_current_strategy"])
	_current_strategy = value
	_save_data()

## 读取 Chain 最近替换的主线关号，用于避免同关重复替换。
func get_chain_last_replaced_level() -> int:
	_observe_fields(["_chain_last_replaced_level"])
	return _chain_last_replaced_level

## 在候选中记下本次 Chain 替换归属的关号。
func set_chain_last_replaced_level(value: int) -> void:
	_observe_fields(["_chain_last_replaced_level"])
	_chain_last_replaced_level = value
	_save_data()

## 取得 Chain 第三组累积的连击计数。
func get_chain_g3_streak() -> int:
	_observe_fields(["_chain_g3_streak"])
	return _chain_g3_streak

## 替换候选中的 Chain 第三组连击计数，供对应策略推进或重置周期。
func set_chain_g3_streak(value: int) -> void:
	_observe_fields(["_chain_g3_streak"])
	_chain_g3_streak = value
	_save_data()

## 读取 11801 尺寸方案当前周期的命中次数。
func get_bsz11801_cycle_hits() -> int:
	_observe_fields(["_bsz11801_cycle_hits"])
	return _bsz11801_cycle_hits

## 暂存 11801 周期命中计数；后续提交失败时不会推进真实周期。
func set_bsz11801_cycle_hits(value: int) -> void:
	_observe_fields(["_bsz11801_cycle_hits"])
	_bsz11801_cycle_hits = value
	_save_data()

## 返回 11802 动态尺寸方案当前的棋盘边长，单位格。
func get_bsz11802_dyn_size() -> int:
	_observe_fields(["_bsz11802_dyn_size"])
	return _bsz11802_dyn_size

## 把策略计算出的动态棋盘边长写入候选，尺寸合法性由策略保证。
func set_bsz11802_dyn_size(value: int) -> void:
	_observe_fields(["_bsz11802_dyn_size"])
	_bsz11802_dyn_size = value
	_save_data()

## 读取 11802 最近实际交付的棋盘边长，供本次调整比较。
func get_bsz11802_last_delivered_size() -> int:
	_observe_fields(["_bsz11802_last_delivered_size"])
	return _bsz11802_last_delivered_size

## 暂存本次交付的棋盘边长，区别于下次待使用的动态尺寸。
func set_bsz11802_last_delivered_size(value: int) -> void:
	_observe_fields(["_bsz11802_last_delivered_size"])
	_bsz11802_last_delivered_size = value
	_save_data()

## 读取 11802 连续卡关计数，供动态尺寸升降判断。
func get_bsz11802_stuck_streak() -> int:
	_observe_fields(["_bsz11802_stuck_streak"])
	return _bsz11802_stuck_streak

## 更新候选的卡关连续计数，允许策略在成功后清零。
func set_bsz11802_stuck_streak(value: int) -> void:
	_observe_fields(["_bsz11802_stuck_streak"])
	_bsz11802_stuck_streak = value
	_save_data()

## 按 daily/其他模式返回局内统计的浅拷贝；嵌套容器仍共享，调用方不应修改其中对象。
func get_game_round_stats(game_type: String) -> Dictionary:
	_observe_fields(["_daily_game_round_stats", "_main_game_round_stats"])
	if game_type == "daily":
		return _daily_game_round_stats.duplicate()
	return _main_game_round_stats.duplicate()

## 按冻结日期执行候选内日切：清零今日计数、移动昨日会话数并裁剪旧胜场记录。
## 部分“今日”getter 会调用这里，因此查询也可能产生待提交的日切变化。
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

## 计算上次登录日到冻结日期的间隔天数，不受候选推进关号影响。
func get_returnee_login_gap_days() -> int:
	_observe_fields(["_returnee_previous_login_date"])
	return ReturneeClock.day_gap(_returnee_previous_login_date, _today_str())

## 根据登录时关号、离线天数、实验组和本次启动标记判断是否可开启回流流程。
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

## 在候选中开启十关回流阶段，并冻结进入前的策略层及 DDA 连击/降档状态供恢复。
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

## 记录过期残局转为新降难题的入口；该路径不创建普通回流组的十关配额。
func begin_stale_new_easier_level(level_num: int) -> void:
	_observe_fields(["_returnee_current_level", "_returnee_from_endgame_save", "_returnee_group", "_returnee_remaining", "_returnee_started_this_cold_start"])
	_returnee_started_this_cold_start = true
	_returnee_group = 0
	_returnee_remaining = 0
	_returnee_from_endgame_save = true
	_returnee_current_level = level_num
	_save_data()

## 只返回指定回流组的剩余配额；与当前组不匹配时返回 0。
func get_returnee_remaining(group: int) -> int:
	_observe_fields(["_returnee_group", "_returnee_remaining"])
	return _returnee_remaining if group == _returnee_group else 0

## 回流组 12001 尚有配额时，告知选题流程暂缓金鱼插入。
func should_defer_returnee_golden_fish() -> bool:
	return get_returnee_remaining(12001) > 0

## 返回本次真正可交付的金鱼资格：既要已有待发标记，也不能被回流流程暂缓。
func get_available_golden_fish_pending() -> bool:
	_observe_fields(["_golden_fish_pending"])
	return _golden_fish_pending and not should_defer_returnee_golden_fish()

## 以 (下界, 上界) 返回本轮回流降难的策略范围。
func get_returnee_easy_range() -> Vector2i:
	_observe_fields(["_returnee_lower", "_returnee_upper"])
	return Vector2i(_returnee_lower, _returnee_upper)

## 仅对当前有效回流组记录交付关号；配额是否扣减交给 fixed_sp 对应的规则判断。
func mark_returnee_delivery(group: int, level_num: int, fixed_sp: bool) -> void:
	_observe_fields(["_returnee_current_level", "_returnee_group", "_returnee_remaining"])
	if group != _returnee_group or _returnee_remaining <= 0:
		return
	_returnee_remaining = ReturneeLevelPolicy.remaining_after_delivery(
		_returnee_remaining, fixed_sp
	)
	_returnee_current_level = level_num
	_save_data()

## 暂存“已决定丢弃过期残局”标记，供同一入口后续步骤复用。
func mark_stale_endgame_discarded() -> void:
	_observe_fields(["_stale_endgame_discarded"])
	_stale_endgame_discarded = true

## 欢迎流程有效且首胜未消费时，认领首个正数主线关号；后续仅相同关号返回 true。
func claim_comeback_start_level(level_num: int) -> bool:
	_observe_fields(["_comeback_main_win_consumed", "_comeback_start_level", "_comeback_welcome_shown"])
	if not _comeback_welcome_shown or _comeback_main_win_consumed or level_num <= 0:
		return false
	if _comeback_start_level == 0:
		_comeback_start_level = level_num
	return _comeback_start_level == level_num

## 一次性消费回归主线首胜资格；未展示欢迎或已经消费时返回 false。
func consume_comeback_main_win() -> bool:
	_observe_fields(["_comeback_main_win_consumed", "_comeback_welcome_shown"])
	if not _comeback_welcome_shown or _comeback_main_win_consumed:
		return false
	_comeback_main_win_consumed = true
	return true

## 先执行必要的候选日切，再读取冻结日期对应的胜场数；无记录返回 0。
func get_today_win_count() -> int:
	_observe_fields(["_recent_win_counts_by_day"])
	_roll_day_if_needed()
	return _recent_win_counts_by_day.get(_today_str(), 0)

## 比较最近主线获胜日期与本次日期，判断今日是否已有主线胜场。
func has_main_win_today() -> bool:
	_observe_fields(["_last_main_win_date"])
	return _last_main_win_date == _today_str()

## 判断每日首胜入口在本次日期是否已经展示过。
func has_daily_first_win_entry_seen_today() -> bool:
	_observe_fields(["_daily_first_win_entry_date"])
	return _daily_first_win_entry_date == _today_str()

## 在候选中记下首胜入口展示日期，同日重复调用保持原状态。
func mark_daily_first_win_entry_seen_today() -> void:
	_observe_fields(["_daily_first_win_entry_date"])
	var today: String = _today_str()
	if _daily_first_win_entry_date == today:
		return
	_daily_first_win_entry_date = today
	_save_data()

## 必要时日切后，返回今日道具消耗数量。
func get_today_tool_consumed() -> int:
	_observe_fields(["_today_tool_consumed"])
	_roll_day_if_needed()
	return _today_tool_consumed

## 必要时日切后，返回今日复活次数。
func get_today_revive_count() -> int:
	_observe_fields(["_today_revive_count"])
	_roll_day_if_needed()
	return _today_revive_count

## 按 locate/hint/mouse/draft 读取候选库存；未知道具种类返回 0。
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

## 检查 R3、R4 或 R5 的评分是否初始化；其他段位返回 false。
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

## 仅在尚未分组时按当前关号是否小于 100 固定新/老玩家人群，返回是否新玩家。
func ensure_elo_group2_cohort() -> bool:
	_observe_fields(["_current_level", "_elo_group2_cohort"])
	if _elo_group2_cohort == -1:
		_elo_group2_cohort = 1 if _current_level < 100 else 0
		_save_data()
	return _elo_group2_cohort == 1

## 读取已固定的人群归属；未初始化不被当作新玩家，也不会在查询时重新分组。
func is_elo_group2_new_player() -> bool:
	_observe_fields(["_elo_group2_cohort"])
	return _elo_group2_cohort == 1

## 返回指定 R3/R4/R5 段位的玩家评分，非支持段位返回 0。
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

## 返回指定 Elo 段位已结算的局数；非 R3/R4/R5 返回 0。
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

## 读取指定 Elo 段位的当前档位；未支持段位返回 0。
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

## 为尚未初始化的 R3/R4/R5 设置起始评分；重复初始化或无效段位不改变候选。
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

## 暂存新评分、档位与局数，并排入评分变化事件；事件要等外层提交成功后才发布。
func commit_elo_settlement(rank: int, new_rating: float, new_band: int) -> void:
	if not _apply_elo_rating_state(rank, new_rating, new_band):
		return
	_save_data()
	# 事件名沿用提交语义，但这里只收集描述；外部通知必须排在核心候选成功持久化之后。
	events.append({"kind": "elo_rating_committed", "rank": rank, "rating": new_rating})

## 更新指定 Elo 段位的评分/档位并增加一局；未知段位返回 false，不排入事件。
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

## 以“关号 + 题目 ID”建立 Elo V2 尝试，复制题目风格并初始化行为事实。
## 同题重入保留既有事实，评分资格只允许从有效降为无效，不能借重试重新取得资格。
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
		# 同一题恢复后只收紧评分资格，已有重试/道具等事实不能因为再次 begin 而被清零。
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

## 返回当前 Elo V2 尝试的深拷贝，避免外部直接改写行为事实。
func get_elo_v2_attempt() -> Dictionary:
	_observe_fields(["_elo_v2_attempt"])
	return _elo_v2_attempt.duplicate(true)

## 只清除属于指定关号的 Elo V2 尝试，防止过期入口误清当前题目记录。
func abandon_elo_v2_attempt(level_num: int) -> void:
	_observe_fields(["_elo_v2_attempt"])
	if int(_elo_v2_attempt.get("level", 0)) != level_num:
		return
	_elo_v2_attempt = {}
	_save_data()

## 将残局事实合回同一次尝试：计数取较大值，使用道具取逻辑或，防止恢复后倒退或重复累加。
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

## 向当前尝试累计 restart/tool/fish/death 事实；没有尝试或动作未知时忽略。
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

## 为已有尝试补入通关耗时和满血结果，供随后计算表现分。
func set_elo_v2_win_facts(time_total: int, full_hp: bool) -> void:
	_observe_fields(["_elo_v2_attempt"])
	if _elo_v2_attempt.is_empty():
		return
	_elo_v2_attempt["time_total"] = time_total
	_elo_v2_attempt["full_hp"] = full_hp
	_save_data()

## 取最近 limit 条获胜记录中的风格向量深拷贝，保持由旧到新的顺序；非正上限返回空数组。
func get_recent_elo_v2_won_style_vectors(limit: int) -> Array:
	_observe_fields(["_elo_v2_won_styles"])
	var vectors: Array = []
	var start_index: int = maxi(0, _elo_v2_won_styles.size() - maxi(0, limit))
	for index: int in range(start_index, _elo_v2_won_styles.size()):
		var row: Dictionary = _elo_v2_won_styles[index]
		var vector: Dictionary = row.get("style_vector", {})
		vectors.append(vector.duplicate(true))
	return vectors

## 返回指定来源的已选条目 ID 列表副本，不暴露列表本身。
func get_elo_v2_source_selected_ids(key: String) -> Array:
	_observe_fields(["_elo_v2_source_selected_ids"])
	var selected: Array = _elo_v2_source_selected_ids.get(key, [])
	return selected.duplicate()

## 把非负条目 ID 加入对应来源的已选集合；空来源或重复 ID 不产生变化。
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

## 读取当前交付题目绑定的 Elo 段位。
func get_elo_active_rank() -> int:
	_observe_fields(["_elo_active_rank"])
	return _elo_active_rank

## 读取当前交付题目的评分，供胜负结算使用。
func get_elo_active_puzzle_rating() -> float:
	_observe_fields(["_elo_active_puzzle_rating"])
	return _elo_active_puzzle_rating

## 同时暂存交付题目的段位与评分，避免结算把不同题目的属性混用。
func set_elo_active_delivery(rank: int, puzzle_rating: float) -> void:
	_observe_fields(["_elo_active_puzzle_rating", "_elo_active_rank"])
	_elo_active_rank = rank
	_elo_active_puzzle_rating = puzzle_rating
	_save_data()

## 读取候选里记录的 Elo 金鱼消耗量，供策略评估辅助使用。
func get_elo_fish_consumed() -> int:
	_observe_fields(["_elo_fish_consumed"])
	return _elo_fish_consumed

## 检查非空题目哈希是否已在 Elo 去重记录中出现。
func is_elo_pid_selected(pid_h: String) -> bool:
	_observe_fields(["_elo_selected_pids"])
	return pid_h != "" and _elo_selected_pids.has(pid_h)

## 将新的 Elo 题目哈希加入最近已选记录，超出容量时丢弃最旧项。
func mark_elo_pid_selected(pid_h: String) -> void:
	_observe_fields(["_elo_selected_pids"])
	if pid_h == "" or _elo_selected_pids.has(pid_h):
		return
	_elo_selected_pids.append(pid_h)
	while _elo_selected_pids.size() > ELO_SELECTED_MAX:
		_elo_selected_pids.pop_front()
	_save_data()

## 检查 Rating 选题专用的已选哈希集合，空哈希视为未选。
func is_rating_pid_selected(pid_h: String) -> bool:
	_observe_fields(["_rating_selected_pids"])
	return pid_h != "" and _rating_selected_pids.has(pid_h)

## 更新有容量上限的 Rating 去重记录；persist 仅兼容旧接口，在候选类中不会触发落盘。
func mark_rating_pid_selected(pid_h: String, persist: bool = true) -> void:
	_observe_fields(["_rating_selected_pids"])
	if pid_h == "" or _rating_selected_pids.has(pid_h):
		return
	_rating_selected_pids.append(pid_h)
	while _rating_selected_pids.size() > RATING_SELECTED_MAX:
		_rating_selected_pids.pop_front()
	if persist:
		_save_data()

## 读取原始金鱼待发标记；若要判断此刻能否发题，应使用包含回流门控的可用性接口。
func get_golden_fish_pending() -> bool:
	_observe_fields(["_golden_fish_pending"])
	return _golden_fish_pending

## 读取金鱼教程的已展示标记，供入口决定是否显示教程。
func has_golden_fish_tutorial_shown() -> bool:
	_observe_fields(["_golden_fish_tutorial_shown"])
	return _golden_fish_tutorial_shown

## 只在首次展示时暂存教程标记，重复调用不再变化。
func mark_golden_fish_tutorial_shown() -> void:
	_observe_fields(["_golden_fish_tutorial_shown"])
	if _golden_fish_tutorial_shown:
		return
	_golden_fish_tutorial_shown = true
	_save_data()

## 从尺寸/段位游标循环寻找本轮未用题目索引，不在查询时推进游标。
## 空题池返回 -1；若全已用则返回本轮起点，由交付逻辑处理轮次。
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

## 检查题目索引对应的已用位；负索引或位图尚未覆盖该字节时视为未用。
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

## 取得指定尺寸/段位金鱼题池已完成的轮次数，首次使用为 0。
func get_onefish_cycle_round(sz: int, rank: int) -> int:
	_observe_fields(["_onefish_cycle_rounds"])
	return int(_onefish_cycle_rounds.get("%d_%d" % [sz, rank], 0))

## 读取金鱼抽取实验切组时的累计交付数，作为新组节奏的计数基线。
func get_onefish_pick_switch_anchor() -> int:
	_observe_fields(["_onefish_pick_switch_anchor"])
	return _onefish_pick_switch_anchor

## 确保候选中存在有效洗牌后，返回当前题目索引及轮次；不前移交付游标。
## 因此调用可能重建候选洗牌缓存，但失败尝试仍可整体丢弃。
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

## 暂存洗牌游标前移、题目已用位及交付计数；persist 不会让候选越过外层事务落盘。
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

## 切换抽取实验组时丢弃旧洗牌顺序/游标，并记住切换时的交付计数；已用位仍保留。
func note_onefish_pick_group(group: int) -> void:
	_observe_fields(["_golden_fish_insert_delivered", "_onefish_pick_switch_anchor", "_onefish_shuffle_cursors", "_onefish_shuffle_group", "_onefish_shuffle_orders"])
	if group == _onefish_shuffle_group:
		return
	_onefish_shuffle_orders = {}
	_onefish_shuffle_cursors = {}
	_onefish_shuffle_group = group

	_onefish_pick_switch_anchor = _golden_fish_insert_delivered
	_save_data()

## 当缓存为空、游标耗尽或剩余顺序与未用题数不一致时，重建候选洗牌。
func _ensure_onefish_shuffle(key: String, count: int) -> void:
	_observe_fields(["_onefish_shuffle_cursors", "_onefish_shuffle_orders", "_onefish_used_bits"])
	var order: Array = _onefish_shuffle_orders.get(key, [])
	var cursor: int = int(_onefish_shuffle_cursors.get(key, 0))
	var unused_left: int = (
		count - _count_used_bits(_onefish_used_bits.get(key, PackedByteArray()), count)
	)

	# 缓存剩余长度应与位图未用数一致；切换顺序/洗牌模式或消耗状态变化后，不应继续用旧排列。
	if order.is_empty() or cursor >= order.size() or (order.size() - cursor) != unused_left:
		_shuffle_onefish_pool(key, count)
		_save_data()

## 对本轮尚未使用的索引执行原地洗牌；无剩余题时清空位图并进入下一轮。
## 随机数只来自本次 runtime，生成的新顺序与游标留在候选中。
func _shuffle_onefish_pool(key: String, count: int) -> void:
	_observe_fields(["_onefish_cycle_rounds", "_onefish_shuffle_cursors", "_onefish_shuffle_orders", "_onefish_used_bits"])
	var indices: Array = _onefish_unused_indices(key, count)
	if indices.is_empty():
		_onefish_used_bits[key] = PackedByteArray()
		_onefish_cycle_rounds[key] = int(_onefish_cycle_rounds.get(key, 0)) + 1
		indices = _onefish_unused_indices(key, count)
	var rng: RandomNumberGenerator = _rng

	# Fisher–Yates：每步只在尚未固定的前缀内交换，让剩余每个题目具有相同排列机会。
	for i in range(indices.size() - 1, 0, -1):
		var swap_at: int = rng.randi_range(0, i)
		var moved: int = indices[i]
		indices[i] = indices[swap_at]
		indices[swap_at] = moved
	_onefish_shuffle_orders[key] = indices
	_onefish_shuffle_cursors[key] = 0

## 按索引顺序收集当前位图中未使用的题目，不改写位图。
func _onefish_unused_indices(key: String, count: int) -> Array:
	var out: Array = []
	for i in count:
		if not _is_used_bit(key, i):
			out.append(i)
	return out

## 在候选位图中标记有效索引；本轮所有题都已用时清空位图并增加轮次。
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

## 取得足以容纳 count 个标记位的字节数组；不足时复制扩容，由调用方写回字段。
func _onefish_used_bits_of(key: String, count: int) -> PackedByteArray:
	_observe_fields(["_onefish_used_bits"])
	@warning_ignore("integer_division")
	# 一字节存 8 个题目的已用标记；加 7 后整除相当于向上取整。
	var need: int = (count + 7) / 8
	var bits: PackedByteArray = _onefish_used_bits.get(key, PackedByteArray())
	if bits.size() < need:
		bits = bits.duplicate()
		bits.resize(need)
	return bits

## 仅统计前 count 个题目位，不把末尾字节用于对齐的多余位算作已用题。
func _count_used_bits(bits: PackedByteArray, count: int) -> int:
	var used: int = 0
	for i in count:
		@warning_ignore("integer_division")
		var byte_at: int = i / 8
		if byte_at < bits.size() and (bits[byte_at] & (1 << (i % 8))) != 0:
			used += 1
	return used

## 读取金鱼插入题累计交付数，用于后续插入间隔与切组节奏。
func get_golden_fish_insert_delivered() -> int:
	_observe_fields(["_golden_fish_insert_delivered"])
	return _golden_fish_insert_delivered

## 读取已完成金鱼结算的累计次数，与交付次数区分。
func get_golden_fish_career_count() -> int:
	_observe_fields(["_golden_fish_career_count"])
	return _golden_fish_career_count

## 读取彩色挑战的待交付标记。
func get_color_challenge_pending() -> bool:
	_observe_fields(["_color_challenge_pending"])
	return _color_challenge_pending

## 取得彩色挑战累计交付次数，含覆盖题面入口。
func get_color_challenge_delivered() -> int:
	_observe_fields(["_color_challenge_delivered"])
	return _color_challenge_delivered

## 返回指定尺寸/段位彩色题池的下次交付游标，未出现过的池为 0。
func get_color_challenge_index(sz: int, rank: int) -> int:
	_observe_fields(["_color_challenge_progress"])
	return int(_color_challenge_progress.get("%d_%d" % [sz, rank], 0))

## 推进金鱼结算累计次数，并通过门控规则重置距金鱼的彩色挑战状态。
func _advance_golden_fish_career_mut() -> void:
	_observe_fields(["_color_challenge_since_gf", "_golden_fish_career_count"])
	_golden_fish_career_count += 1
	_color_challenge_since_gf = ColorChallengeGate.since_gf_after_golden_fish()

## 在候选中推进对应彩色题池游标，并累计一次彩色挑战交付。
func commit_color_challenge_delivery(sz: int, rank: int) -> void:
	_observe_fields(["_color_challenge_delivered", "_color_challenge_progress"])
	var cursor_key: String = "%d_%d" % [sz, rank]
	_color_challenge_progress[cursor_key] = int(_color_challenge_progress.get(cursor_key, 0)) + 1
	_color_challenge_delivered += 1

	_save_data()

## 覆盖题面只累计彩色挑战交付数，不推进普通彩色题库游标。
func commit_color_challenge_override_delivery() -> void:
	_observe_fields(["_color_challenge_delivered"])
	_color_challenge_delivered += 1
	_save_data()

## 首次进入彩色挑战时记住原图案模式并临时开启；重复进入不覆盖原设置。
func begin_color_challenge_pattern_mode() -> void:
	_observe_fields(["_pattern_mode_before_color_challenge", "_pattern_mode_on"])
	if _pattern_mode_before_color_challenge >= 0:
		return
	_pattern_mode_before_color_challenge = 1 if _pattern_mode_on else 0

	_pattern_mode_on = true
	_save_data()

## 暂存顺序金鱼池游标、已用题目与累计交付数；实际持久化仍归外层事务。
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

## 在候选中结束金鱼待发状态并推进结算计数；获胜更新连胜，未获胜清除本次预填会话。
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

## 清除候选的本局脏标记，供新局重新计算干净通关资格。
func clear_current_level_dirty() -> void:
	_observe_fields(["_current_level_dirty"])
	_current_level_dirty = false

## 读取 DDA 口径的本局道具/复活使用事实。
func is_dda_tool_or_revive_used() -> bool:
	_observe_fields(["_dda_tool_or_revive_used"])
	return _dda_tool_or_revive_used

## 判断当前关是否实际使用了每日首次降档，而非仅判断今日还有没有机会。
func is_current_level_daily_first_easy() -> bool:
	_observe_fields(["_is_daily_first_easy_level"])
	return _is_daily_first_easy_level

## 暂存 Chain 第二组的一次待处理标记，等待相应入口消费。
func set_chain_g2_pending(value: bool) -> void:
	_observe_fields(["_chain_g2_pending"])
	_chain_g2_pending = value

## 返回并清空候选中的 Chain 第二组待处理标记，保证同一候选内只消费一次。
func consume_chain_g2_pending() -> bool:
	_observe_fields(["_chain_g2_pending"])
	var pending: bool = _chain_g2_pending
	_chain_g2_pending = false
	return pending

## 记下 G4 压力关所属关号，供后续结算或延后逻辑匹配。
func mark_g4_pressure_level(level_num: int) -> void:
	_observe_fields(["_g4_pressure_level_num"])
	_g4_pressure_level_num = level_num

## 只有已记录的正数压力关号与请求关号一致时返回 true。
func is_g4_pressure_level(level_num: int) -> bool:
	_observe_fields(["_g4_pressure_level_num"])
	return _g4_pressure_level_num > 0 and _g4_pressure_level_num == level_num

## 暂存 G4 延后状态，不在这里执行被延后的动作。
func set_g4_defer_pending(value: bool) -> void:
	_observe_fields(["_g4_defer_pending"])
	_g4_defer_pending = value

## 取出并清空 G4 延后状态，使本次候选中的后续调用不重复消费。
func consume_g4_defer_pending() -> bool:
	_observe_fields(["_g4_defer_pending"])
	var pending: bool = _g4_defer_pending
	_g4_defer_pending = false
	return pending

## 把单格区域 DDA 的目标段位和升/降档方向一起暂存。
func set_sr_dda_pending(rank: int, is_upgrade: bool) -> void:
	_observe_fields(["_sr_dda_pending_is_upgrade", "_sr_dda_pending_rank"])
	_sr_dda_pending_rank = rank
	_sr_dda_pending_is_upgrade = is_upgrade

## 读取待处理的单格区域 DDA 目标段位。
func get_sr_dda_pending_rank() -> int:
	_observe_fields(["_sr_dda_pending_rank"])
	return _sr_dda_pending_rank

## 判断已暂存的单格区域 DDA 调整是否属于升档。
func get_sr_dda_pending_is_upgrade() -> bool:
	_observe_fields(["_sr_dda_pending_is_upgrade"])
	return _sr_dda_pending_is_upgrade

## 暂存 11503 在 R3 层新增一次交付，后续概率按每两次交付递进。
func inc_11503_r3_played_count() -> void:
	_observe_fields(["_11503_r3_played_count"])
	_11503_r3_played_count += 1
	_save_data()

## 暂存 11503 在 R4 层新增一次交付，供 R2/R3/R4 混合权重计算。
func inc_11503_r4_played_count() -> void:
	_observe_fields(["_11503_r4_played_count"])
	_11503_r4_played_count += 1
	_save_data()

## 按 R3 交付次数计算 (R2, R3) 百分比；每两次降低 R2 占比，最低为 30%。
func compute_11503_r3_probs() -> Vector2:
	_observe_fields(["_11503_r3_played_count"])
	var adj: int = _11503_r3_played_count / 2
	var r2: float = clampf(50.0 - 5.0 * adj, 30.0, 50.0)
	return Vector2(r2, 100.0 - r2)

## 按 R4 交付次数返回 (R2, R3, R4) 百分比，在各分量边界内逐步提高 R4 占比。
func compute_11503_r4_probs() -> Vector3:
	_observe_fields(["_11503_r4_played_count"])
	var adj: int = _11503_r4_played_count / 2
	var r2: float = clampf(24.0 - 1.125 * adj, 15.0, 24.0)
	var r3: float = clampf(56.0 - 1.375 * adj, 45.0, 56.0)
	var r4: float = clampf(20.0 + 2.5 * adj, 20.0, 40.0)
	return Vector3(r2, r3, r4)

## 把 R3 层混合比例表示为总和 800 的整数权重，顺序为 [R2, R3]。
func compute_11503_r3_weights() -> PackedInt32Array:
	_observe_fields(["_11503_r3_played_count"])
	var adj: int = _11503_r3_played_count / 2
	var w_r2: int = clampi(400 - 40 * adj, 240, 400)
	var w_r3: int = 800 - w_r2
	return PackedInt32Array([w_r2, w_r3])

## 返回 R4 层的整数抽样权重 [R2, R3, R4]，总和保持 800。
func compute_11503_r4_weights() -> PackedInt32Array:
	_observe_fields(["_11503_r4_played_count"])
	var adj: int = _11503_r4_played_count / 2
	var w_r2: int = clampi(192 - 9 * adj, 120, 192)
	var w_r3: int = clampi(448 - 11 * adj, 360, 448)
	var w_r4: int = clampi(160 + 20 * adj, 160, 320)
	return PackedInt32Array([w_r2, w_r3, w_r4])

## 按关号绑定重试参数；当前直接持有 params 字典，调用方后续修改也会影响候选缓存。
func set_retry_puzzle(level: int, params: Dictionary) -> void:
	_observe_fields(["_retry_puzzle_level", "_retry_puzzle_params"])
	_retry_puzzle_level = level
	_retry_puzzle_params = params
	_save_data()

## 仅当请求关号匹配且缓存非空时返回候选内部字典；其他情况返回空字典，不跨关复用。
func get_retry_puzzle(level: int) -> Dictionary:
	_observe_fields(["_retry_puzzle_level", "_retry_puzzle_params"])
	if _retry_puzzle_level == level and not _retry_puzzle_params.is_empty():
		return _retry_puzzle_params
	return {}

## 同时清空重试缓存关号与题面参数，避免留下可误匹配的半份身份。
func clear_retry_puzzle() -> void:
	_observe_fields(["_retry_puzzle_level", "_retry_puzzle_params"])
	_retry_puzzle_level = 0
	_retry_puzzle_params = {}
	_save_data()

## 把困难、挣扎、降档三种预填来源组合成新字典，只读取而不消费。
func get_pre_cat_pending() -> Dictionary:
	_observe_fields(["_pre_cat_pending_demote", "_pre_cat_pending_hard", "_pre_cat_pending_struggle"])
	return {
		"hard": _pre_cat_pending_hard,
		"struggle": _pre_cat_pending_struggle,
		"demote": _pre_cat_pending_demote
	}

## 对正数关号建立金鱼预填会话，冻结插入前的主线预填来源；同关有效会话不会被重入覆盖。
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

## 要求会话关号匹配且尚未获胜/跳过；已结束会话转入主线后续处理。
func _is_golden_fish_pre_cat_active(level_num: int) -> bool:
	_observe_fields(["_golden_fish_pre_cat_session"])
	return (
		not _golden_fish_pre_cat_session.is_empty()
		and int(_golden_fish_pre_cat_session.get("level", 0)) == level_num
		and not bool(_golden_fish_pre_cat_session.get("won", false))
		and not bool(_golden_fish_pre_cat_session.get("skipped", false))
	)

## 判断指定正数关号是否有已获胜或跳过的金鱼会话，需要衔接主线预填。
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

## 根据保留来源、是否进入金鱼及跳过结果，计算金鱼之后主线应收到的预填来源。
## 不保留原来源时，仅在规则允许且失败至少两次或复活过时产生挣扎预填；不消费会话。
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

## 返回同关有效金鱼会话冻结的预填来源深拷贝；已结束或关号不匹配返回空字典。
func get_golden_fish_pre_cat_source(level_num: int) -> Dictionary:
	_observe_fields(["_golden_fish_pre_cat_session"])
	if not _is_golden_fish_pre_cat_active(level_num):
		return {}
	var source: Dictionary = _golden_fish_pre_cat_session.get("source", {}).duplicate(true)
	return source

## 优先计算金鱼后续预填，否则读取普通待发来源；随后清空普通预填标记并返回本次使用值。
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

## 仅为同关有效金鱼会话记一次复活事实，供之后挣扎预填判定。
func mark_golden_fish_pre_cat_revived(level_num: int) -> void:
	_observe_fields(["_golden_fish_pre_cat_session"])
	if (
		not _is_golden_fish_pre_cat_active(level_num)
		or bool(_golden_fish_pre_cat_session.get("revived", false))
	):
		return
	_golden_fish_pre_cat_session["revived"] = true
	_save_data()

## 仅在会话有效且 puzzle_key 一致时返回锁的深拷贝，避免同关换题误用旧坐标。
func get_golden_fish_pre_cat_lock(level_num: int, puzzle_key: String) -> Dictionary:
	_observe_fields(["_golden_fish_pre_cat_session"])
	if not _is_golden_fish_pre_cat_active(level_num):
		return {}
	var lock: Dictionary = _golden_fish_pre_cat_session.get("lock", {})
	return lock.duplicate(true) if str(lock.get("puzzle_key", "")) == puzzle_key else {}

## 为当前有效金鱼会话锁定题目身份、来源和坐标，并重置特效播放标记。
## 预填资格及来源随锁复制保存，同题重入可复用这一次决定。
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

## 只返回对应关号的预填失败计数；其他关号视为 0。
func get_pre_cat_fail_count(lv: int) -> int:
	_observe_fields(["_pre_cat_fail_count", "_pre_cat_fail_lv"])
	return _pre_cat_fail_count if _pre_cat_fail_lv == lv else 0

## 在候选中一次性记录本关已复活，作为预填规则输入。
func mark_pre_cat_revived() -> void:
	_observe_fields(["_pre_cat_revived_this_level"])
	if _pre_cat_revived_this_level:
		return
	_pre_cat_revived_this_level = true
	_save_data()

## 返回三种预填来源的消费前快照，再清空候选中的待发标记。
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

## 取得同关已确定的预填结果；金鱼后续还要求 pending 来源相同才复用主线锁。
## 未命中时返回 locked=false 与无效坐标，调用方应重新计算。
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

## 暂存普通关的预填来源与坐标；若承接金鱼会话，额外复制 pending 作为主线锁的匹配条件。
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

## 读取上一关是否干净通关，供连胜/难度节奏判断。
func was_last_level_clean_win() -> bool:
	_observe_fields(["_last_level_clean_win"])
	return _last_level_clean_win

## 按尺寸、段位及可选 H 难题层读取基础题库游标；未使用题池从 0 开始。
func get_bank_index(sz: int, rank: int, tier: String = "") -> int:
	_observe_fields(["_bank_progress"])
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	return _bank_progress.get(key, 0)

## 在候选内推进一次指定基础题库游标；persist 只保留旧接口语义，不直接写盘。
func advance_bank_index(sz: int, rank: int, tier: String = "", persist: bool = true) -> void:
	_observe_fields(["_bank_progress"])
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_bank_progress[key] = _bank_progress.get(key, 0) + 1
	if persist:
		_save_data()

## 取得主池进度的内部字典；首次读取会在候选内补建 lk_mod/regular/lkstyle/transform 四个游标。
func get_main_progress(sz: int, rank: int, tier: String = "") -> Dictionary:
	_observe_fields(["_main_bank_progress"])
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	if not _main_bank_progress.has(key):
		_main_bank_progress[key] = {"lk_mod": 0, "regular": 0, "lkstyle": 0, "transform": 0}
	return _main_bank_progress[key]

## 用传入字典替换指定主池的进度；不复制参数，调用方应将它作为候选所有的数据使用。
func set_main_progress(
	sz: int, rank: int, tier: String, progress: Dictionary, persist: bool = true
) -> void:
	_observe_fields(["_main_bank_progress"])
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_main_bank_progress[key] = progress
	if persist:
		_save_data()

## 首次使用时将关号设为超级困难关周期锚点；已有正数锚点保持不变。
func ensure_super_hard_anchor(level_num: int) -> int:
	_observe_fields(["_super_hard_anchor"])
	if _super_hard_anchor <= 0:
		_super_hard_anchor = level_num
		_save_data()
	return _super_hard_anchor

## 读取超级困难关周期锚点；尚未建立时为 0。
func get_super_hard_anchor() -> int:
	_observe_fields(["_super_hard_anchor"])
	return _super_hard_anchor

## 返回尺寸/段位对应的 LK Mod 进度引用；首次读取会在候选内建立 idx=0。
func get_lkmod_progress(sz: int, rank: int) -> Dictionary:
	_observe_fields(["_lkmod_progress"])
	var key := "%d_%d" % [sz, rank]
	if not _lkmod_progress.has(key):
		_lkmod_progress[key] = {"idx": 0}
	return _lkmod_progress[key]

## 暂存 LK Mod 题池进度字典；实际写盘仍等待整个选题计划提交。
func set_lkmod_progress(sz: int, rank: int, progress: Dictionary, persist: bool = true) -> void:
	_observe_fields(["_lkmod_progress"])
	var key := "%d_%d" % [sz, rank]
	_lkmod_progress[key] = progress
	if persist:
		_save_data()

## 返回基础题库全部游标的深拷贝，便于一次试选前留存回退点。
func get_bank_progress_snapshot() -> Dictionary:
	_observe_fields(["_bank_progress"])
	return _bank_progress.duplicate(true)

## 同时深拷贝基础、主池与 LK Mod 三组游标；这是局部试选快照，不是完整核心存档。
func get_level_selection_progress_snapshot() -> Dictionary:
	_observe_fields(["_bank_progress", "_lkmod_progress", "_main_bank_progress"])
	return {
		"bank_progress": _bank_progress.duplicate(true),
		"main_bank_progress": _main_bank_progress.duplicate(true),
		"lkmod_progress": _lkmod_progress.duplicate(true),
	}

## 从局部快照恢复三组候选游标；缺失分区置空，不触碰真实 GameState 或其他候选字段。
func restore_level_selection_progress(snapshot: Dictionary) -> void:
	_observe_fields(["_bank_progress", "_lkmod_progress", "_main_bank_progress"])
	_bank_progress = (snapshot.get("bank_progress", {}) as Dictionary).duplicate(true)
	_main_bank_progress = (snapshot.get("main_bank_progress", {}) as Dictionary).duplicate(true)
	_lkmod_progress = (snapshot.get("lkmod_progress", {}) as Dictionary).duplicate(true)

## 读取下一次 SP/TT 交付应使用的类别游标。
func get_sp_tt_category_cursor() -> int:
	_observe_fields(["_sp_tt_category_cursor"])
	return _sp_tt_category_cursor

## 读取最近由普通 SP/TT 替换的主线关号。
func get_sp_tt_last_replaced_level() -> int:
	_observe_fields(["_sp_tt_last_replaced_level"])
	return _sp_tt_last_replaced_level

## 返回类别/尺寸/段位对应的内部进度引用，缺失时补建题目 idx 与变换 t_pos。
func get_sp_tt_progress(category: int, sz: int, rank: int) -> Dictionary:
	_observe_fields(["_sp_tt_progress"])
	var key := "%d_%d_%d" % [category, sz, rank]
	if not _sp_tt_progress.has(key):
		_sp_tt_progress[key] = {"idx": 0, "t_pos": 0}
	return _sp_tt_progress[key]

## 把 SP/TT 题池进度、下一类别游标和替换关号一起暂存到候选。
func commit_sp_tt_delivery(
	level_num: int, category: int, sz: int, rank: int, progress: Dictionary, next_cursor: int
) -> void:
	_observe_fields(["_sp_tt_category_cursor", "_sp_tt_last_replaced_level", "_sp_tt_progress"])
	_sp_tt_progress["%d_%d_%d" % [category, sz, rank]] = progress
	_sp_tt_category_cursor = next_cursor
	_sp_tt_last_replaced_level = level_num
	_save_data()

## 暂存回流 SP/TT 的题池和类别进度，但不更新普通主线的最近替换关号。
func commit_returnee_sp_tt_delivery(
	category: int, sz: int, rank: int, progress: Dictionary, next_cursor: int
) -> void:
	_observe_fields(["_sp_tt_category_cursor", "_sp_tt_progress"])
	_sp_tt_progress["%d_%d_%d" % [category, sz, rank]] = progress
	_sp_tt_category_cursor = next_cursor
	_save_data()

## 读取单格区域补充池的内部 idx 游标；缺失时在候选建立初始记录。
func get_single_region_supp_progress(sz: int, rank: int) -> Dictionary:
	_observe_fields(["_single_region_supp_progress"])
	var key := "%d_%d" % [sz, rank]
	if not _single_region_supp_progress.has(key):
		_single_region_supp_progress[key] = {"idx": 0}
	return _single_region_supp_progress[key]

## 取得 Elo 辅助单格池的独立进度引用，避免消耗普通单格补充池游标。
func get_elo_aux_single_region_progress(sz: int, rank: int) -> Dictionary:
	_observe_fields(["_elo_aux_single_region_progress"])
	var key := "%d_%d" % [sz, rank]
	if not _elo_aux_single_region_progress.has(key):
		_elo_aux_single_region_progress[key] = {"idx": 0}
	return _elo_aux_single_region_progress[key]

## 暂存 Elo 辅助单格池交付后的进度，不推进其他来源题池。
func commit_elo_aux_single_region_delivery(sz: int, rank: int, progress: Dictionary) -> void:
	_observe_fields(["_elo_aux_single_region_progress"])
	_elo_aux_single_region_progress["%d_%d" % [sz, rank]] = progress
	_save_data()

## 取得 Elo 辅助高潮池的内部题目/变换进度，缺失时建立零值游标。
func get_elo_aux_climax_progress(sz: int, rank: int) -> Dictionary:
	_observe_fields(["_elo_aux_climax_progress"])
	var key := "%d_%d" % [sz, rank]
	if not _elo_aux_climax_progress.has(key):
		_elo_aux_climax_progress[key] = {"idx": 0, "t_pos": 0}
	return _elo_aux_climax_progress[key]

## 把 Elo 辅助高潮池交付结果写入候选的独立进度表。
func commit_elo_aux_climax_delivery(sz: int, rank: int, progress: Dictionary) -> void:
	_observe_fields(["_elo_aux_climax_progress"])
	_elo_aux_climax_progress["%d_%d" % [sz, rank]] = progress
	_save_data()

## 更新指定尺寸/段位单格区域补充池的候选进度。
func commit_single_region_supp_delivery(sz: int, rank: int, progress: Dictionary) -> void:
	_observe_fields(["_single_region_supp_progress"])
	_single_region_supp_progress["%d_%d" % [sz, rank]] = progress
	_save_data()

## 按尺寸、段位和单格数量区分筛选池，返回内部 idx/t_pos 进度并按需补建。
func get_climax_filter_progress(sz: int, rank: int, single_count: int) -> Dictionary:
	_observe_fields(["_climax_filter_progress"])
	var key := "%d_%d_%d" % [sz, rank, single_count]
	if not _climax_filter_progress.has(key):
		_climax_filter_progress[key] = {"idx": 0, "t_pos": 0}
	return _climax_filter_progress[key]

## 暂存对应筛选条件的高潮题池进度，防止不同单格数量共用一个游标。
func commit_climax_filter_delivery(
	sz: int, rank: int, single_count: int, progress: Dictionary
) -> void:
	_observe_fields(["_climax_filter_progress"])
	_climax_filter_progress["%d_%d_%d" % [sz, rank, single_count]] = progress
	_save_data()

## 读取 LK Mod G2 最近替换的关号，供替换间隔与同关幂等判断。
func get_lk_mod_g2_last_replaced_level() -> int:
	_observe_fields(["_lk_mod_g2_last_replaced_level"])
	return _lk_mod_g2_last_replaced_level

## 同时暂存 LK Mod 新索引与 G2 替换关号，保持游标和交付归属一致。
func commit_lk_mod_g2_delivery(level_num: int, sz: int, rank: int, new_idx: int) -> void:
	_observe_fields(["_lk_mod_g2_last_replaced_level", "_lkmod_progress"])
	_lkmod_progress["%d_%d" % [sz, rank]] = {"idx": new_idx}
	_lk_mod_g2_last_replaced_level = level_num
	_save_data()

## 读取 SP/TT 与 LK 交替方案最近替换的主线关号。
func get_sp_tt_lk_alt_last_replaced_level() -> int:
	_observe_fields(["_sp_tt_lk_alt_last_replaced_level"])
	return _sp_tt_lk_alt_last_replaced_level

## 取得交替方案当前来源块的类型，供下次决定继续或换源。
func get_sp_tt_lk_alt_block_source() -> String:
	_observe_fields(["_sp_tt_lk_alt_block_source"])
	return _sp_tt_lk_alt_block_source

## 读取当前来源块已累计交付的题数。
func get_sp_tt_lk_alt_block_count() -> int:
	_observe_fields(["_sp_tt_lk_alt_block_count"])
	return _sp_tt_lk_alt_block_count

## 一次暂存交替方案的替换关号、当前来源及块内计数。
func commit_sp_tt_lk_alt_delivery(level_num: int, new_source: String, new_count: int) -> void:
	_observe_fields(["_sp_tt_lk_alt_block_count", "_sp_tt_lk_alt_block_source", "_sp_tt_lk_alt_last_replaced_level"])
	_sp_tt_lk_alt_last_replaced_level = level_num
	_sp_tt_lk_alt_block_source = new_source
	_sp_tt_lk_alt_block_count = new_count
	_save_data()

## 读取等待降档特殊题处理的关号；0 表示无待处理关。
func get_downgrade_special_pending_level() -> int:
	_observe_fields(["_downgrade_special_pending_level"])
	return _downgrade_special_pending_level

## 设置或清除候选中的降档特殊题关号，暂不执行选题。
func set_downgrade_special_pending_level(value: int) -> void:
	_observe_fields(["_downgrade_special_pending_level"])
	_downgrade_special_pending_level = value
	_save_data()

## 返回普通关历史通关耗时记录的深拷贝，供策略只读分析。
func get_normal_pass_time_records() -> Array:
	_observe_fields(["_normal_pass_time_records"])
	return _normal_pass_time_records.duplicate(true)

## 已有非零种子直接复用；否则从本次随机源生成非零种子并暂存，保持该题库后续顺序稳定。
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

## 取得当前关交付前的 R4 累计次数；同关已计数时扣回一次，避免重选再次累加。
func get_nl_v6_alternate_r4_count_before(level_num: int) -> int:
	_observe_fields(["_nl_v6_alternate_r4_count", "_nl_v6_alternate_r4_level"])
	if _nl_v6_alternate_r4_level == level_num:
		return _nl_v6_alternate_r4_count - 1
	return _nl_v6_alternate_r4_count

## 以交付前计数为基线记录本关是否来自主池 R4；同关改选其他来源时撤销此前那一次计数。
func record_nl_v6_alternate_delivery(
	level_num: int, is_main_r4: bool, persist: bool = true
) -> void:
	_observe_fields(["_nl_v6_alternate_r4_count", "_nl_v6_alternate_r4_level"])
	# 先撤回本关可能已占的一次 R4 计数，再按新交付来源决定是否加回，支持同关重选。
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

## 返回 V6 指定题池的内部 idx/transform 进度，首次读取在候选中补建。
func get_nl_v6_pool_progress(key: String) -> Dictionary:
	_observe_fields(["_nl_v6_pool_progress"])
	if not _nl_v6_pool_progress.has(key):
		_nl_v6_pool_progress[key] = {"idx": 0, "transform": 0}
	return _nl_v6_pool_progress[key]

## 替换 V6 指定题池的候选进度，传入字典按引用保存。
func set_nl_v6_pool_progress(key: String, progress: Dictionary, persist: bool = true) -> void:
	_observe_fields(["_nl_v6_pool_progress"])
	_nl_v6_pool_progress[key] = progress
	if persist:
		_save_data()

## 返回 V6 交替池状态的深拷贝；未建立时返回 ids 为空、round 为 0 的初始状态。
func get_nl_v6_alt_state(key: String) -> Dictionary:
	_observe_fields(["_nl_v6_alt_state"])
	var state: Dictionary = _nl_v6_alt_state.get(key, {"ids": [], "round": 0})
	return state.duplicate(true)

## 深拷贝 V6 交替池的已用 ID 和轮次状态，隔离调用方之后的修改。
func set_nl_v6_alt_state(key: String, state: Dictionary, persist: bool = true) -> void:
	_observe_fields(["_nl_v6_alt_state"])
	_nl_v6_alt_state[key] = state.duplicate(true)
	if persist:
		_save_data()

## 返回最近交付记录的深拷贝，包含题目身份、风格与游标快照。
func get_recent_puzzles() -> Array:
	_observe_fields(["_recent_puzzles"])
	return _recent_puzzles.duplicate(true)

## 返回当前保留的最近交付记录数，最多为 RECENT_PUZZLES_LIMIT。
func get_recent_puzzle_count() -> int:
	_observe_fields(["_recent_puzzles"])
	return _recent_puzzles.size()

## 从最近 limit 条记录提取非空同构签名，按旧到新排列；签名数组本身未深拷贝，应只读使用。
func get_recent_iso_signatures(limit: int) -> Array:
	_observe_fields(["_recent_puzzles"])
	var result: Array = []
	var start: int = maxi(0, _recent_puzzles.size() - limit)
	for i: int in range(start, _recent_puzzles.size()):
		var sig: Array = _recent_puzzles[i].get("iso_sig", [])
		if not sig.is_empty():
			result.append(sig)
	return result

## 从最近 limit 条记录提取完整风格向量；仅收集同时存在直方图与步骤顺序的记录。
## 返回外层是新容器，但其中两个数组仍引用候选记录，供只读比较。
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

## 从最新记录向前查找题目 ID，返回首个匹配记录的深拷贝；找不到返回空字典。
func find_recent_puzzle(puzzle_id: String) -> Dictionary:
	_observe_fields(["_recent_puzzles"])
	for i: int in range(_recent_puzzles.size() - 1, -1, -1):
		var entry: Dictionary = _recent_puzzles[i]
		if entry.get("puzzle_id", "") == puzzle_id:
			return entry.duplicate(true)
	return {}

## 倒序查找指定关号最近一次交付时的普通关实验值；没有记录返回 -1。
func get_latest_selected_normal_level_group(level_num: int) -> int:
	_observe_fields(["_recent_puzzles"])
	for i: int in range(_recent_puzzles.size() - 1, -1, -1):
		var entry: Dictionary = _recent_puzzles[i]
		if int(entry.get("level", -1)) == level_num:
			return int(entry.get("nl", -1))
	return -1

## 把本次题目身份、冻结时间和交付后游标记录入最近历史，同时深拷贝重试参数。
## 此时只是完成候选记账；最近记录、重试缓存与题库游标会随同一计划一起提交或丢弃。
func finalize_selected_puzzle(
	level_num: int, puzzle_record: Dictionary, retry_params: Dictionary
) -> void:
	_observe_fields(["_bank_progress", "_lkmod_progress", "_main_bank_progress", "_recent_puzzles", "_retry_puzzle_level", "_retry_puzzle_params", "_sp_tt_progress"])
	var record: Dictionary = puzzle_record.duplicate(true)
	record["level"] = level_num
	record["ts"] = _now_unix
	# 这些是候选完成交付后的游标；拷贝后不会被下一次选题推进，便于还原历史交付位置。
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

## 返回候选主线残局的内部字典引用；需要独立改写副本时由调用方显式复制。
func get_endgame_snapshot() -> Dictionary:
	_observe_fields(["_endgame_snapshot"])
	return _endgame_snapshot

## 在候选中清空非空主线残局；保存钩子为空，真实残局直到外层提交才被清除。
func clear_endgame_snapshot() -> void:
	_observe_fields(["_endgame_snapshot"])
	if _endgame_snapshot.is_empty():
		return
	_endgame_snapshot = {}
	_save_endgame()
	print("[Endgame] cleared")


## 兼容旧残局清理调用的空钩子；禁止候选试算过程中直接写独立残局文件。
func _save_endgame() -> void:
	pass


## 返回创建候选时原始核心快照的深拷贝，作为提交冲突检查的旧值基线。
func base_candidate() -> Dictionary:
	return _original_candidate.duplicate(true)


## 复制入口冻结上下文供后续步骤复用；普通容器深拷贝，随机源等对象仍共享引用。
func selection_context() -> Dictionary:
	return _selection_context.duplicate(true)


# 候选覆盖的 profile 键清单；属于字段范围描述，不等于本次实际读过的字段，读集合由 _observe_fields 单独记录。
const PROFILE_FIELDS: Array[String] = ["active_days", "bank_progress", "bsz11801_cycle_hits", "bsz11802_dyn_size", "bsz11802_last_delivered_size", "bsz11802_stuck_streak", "cc_delivered", "cc_pending", "cc_progress", "cc_since_gf", "chain_g3_streak", "chain_last_replaced_level", "climax_filter_progress", "consecutive_clean_wins", "consecutive_fails", "consecutive_retry_levels", "current_level", "current_strategy", "daily_auto_mark_enabled", "daily_first_easy_date", "daily_first_win_entry_date", "diff_diff_r3_played_count", "diff_diff_r4_played_count", "downgrade_special_pending_level", "elo_active_puzzle_rating", "elo_active_rank", "elo_aux_climax_progress", "elo_aux_single_region_progress", "elo_band_r3", "elo_band_r4", "elo_band_r5", "elo_fish_consumed", "elo_games_r3", "elo_games_r4", "elo_games_r5", "elo_group2_cohort", "elo_init_r3", "elo_init_r4", "elo_init_r5", "elo_rating_r3", "elo_rating_r4", "elo_rating_r5", "elo_selected_pids", "elo_v2_attempt", "elo_v2_source_selected_ids", "elo_v2_won_styles", "g4_defer_pending", "g4_pressure_level_num", "game_barrage_daily_keys", "golden_fish_career_count", "golden_fish_insert_delivered", "golden_fish_pending", "golden_fish_pre_cat_session", "golden_fish_streak_count", "golden_fish_tutorial_shown", "insert_gf_wrong_cat_num", "last_day_session_count", "last_hard_level", "last_level_clean_win", "last_main_win_date", "lk_mod_g2_last_replaced_level", "lkmod_progress", "main_bank_progress", "nl11701_shuffle_seed", "nl_v6_alt_state", "nl_v6_alternate_r4_count", "nl_v6_alternate_r4_level", "nl_v6_pool_progress", "normal_pass_time_records", "onefish_consecutive_skips", "onefish_consecutive_wins", "onefish_cycle_rounds", "onefish_pick_switch_anchor", "onefish_progress", "onefish_shuffle_cursors", "onefish_shuffle_group", "onefish_shuffle_orders", "onefish_used_bits", "pattern_mode_before_cc", "pattern_mode_on", "pending_rewards", "pre_cat_fail_count", "pre_cat_fail_lv", "pre_cat_lock_lv", "pre_cat_lock_pos", "pre_cat_lock_pre_type", "pre_cat_pending_demote", "pre_cat_pending_hard", "pre_cat_pending_struggle", "pre_cat_revived_this_level", "rating_selected_pids", "recent_puzzles", "recent_win_counts_by_day", "restored_today_count", "retry_puzzle_level", "retry_puzzle_params", "retry_tracking_strategy", "returnee_current_level", "returnee_from_endgame_save", "returnee_frozen_dda", "returnee_frozen_strategy", "returnee_group", "returnee_lkmod_resume_level", "returnee_lower", "returnee_remaining", "returnee_upper", "single_region_supp_progress", "sp_tt_category_cursor", "sp_tt_last_replaced_level", "sp_tt_lk_alt_block_count", "sp_tt_lk_alt_block_source", "sp_tt_lk_alt_last_replaced_level", "sp_tt_progress", "super_hard_anchor", "today_active_sec", "today_cat_found", "today_date", "today_mark_placed", "today_played_count", "today_revive_count", "today_session_count", "today_tool_consumed"]


## 清空候选里指定模式的局内统计；daily 以外的模式使用主线统计分区。
func reset_game_round_stats(game_type: String) -> void:
	_observe_fields(["_daily_game_round_stats", "_main_game_round_stats"])
	if game_type == "daily":
		_daily_game_round_stats = {}
	else:
		_main_game_round_stats = {}


## 暂存每日关开始日期；非恢复入口清空本局快照/步骤，非重玩还清空累计统计。
## auto_mark_variant 保留入口接口，本方法当前不使用它来变更自动标记设置。
func stage_daily_entry(date: String, replay: bool, restoring: bool, auto_mark_variant: int) -> void:
	_observe_fields(["_daily_game_round_stats"])
	# 不在 FIELD_MAP 中的每日入口键直接改底板，export_candidate 会保留这些变化。
	_candidate.get("profile", {})["daily_started_date"] = date
	if not restoring:
		_candidate.get("endgame", {})["daily_snapshot"] = {}
		_daily_game_round_stats = {}
		var stats: Dictionary = _candidate.get("endgame", {}).get("stats", {})
		stats["daily_steps"] = {}
		if not replay:
			stats["daily_total"] = {}


## 在候选中结束彩色挑战、清空跳过/延后门控，并恢复进入前暂存的图案模式。
func on_color_challenge_settled() -> void:
	_observe_fields(["_color_challenge_pending", "_color_challenge_since_gf", "_pattern_mode_before_color_challenge", "_pattern_mode_on"])
	_color_challenge_pending = false
	_color_challenge_since_gf = ColorChallengeGate.NOT_STARTED
	_candidate.get("profile", {})["color_challenge_skip_count"] = 0
	_candidate.get("profile", {})["color_challenge_defer_until"] = 0
	if _pattern_mode_before_color_challenge >= 0:
		_pattern_mode_on = _pattern_mode_before_color_challenge == 1
		_pattern_mode_before_color_challenge = -1


## 执行必要的候选日切后，读取今日找到猫的累计数量。
func get_today_cat_found() -> int:
	_observe_fields(["_today_cat_found"])
	_roll_day_if_needed()
	return _today_cat_found


## 执行必要的候选日切后，读取今日放置标记的累计数量。
func get_today_mark_placed() -> int:
	_observe_fields(["_today_mark_placed"])
	_roll_day_if_needed()
	return _today_mark_placed


## 冲突检查只覆盖真正经过的业务读路径；未参与入场的统计可继续更新。
func _observe_fields(names: Array) -> void:
	for name: String in names:
		_observed_fields[name] = true


## 把访问过的私有字段转换为核心分区/键描述，交给提交方核对依赖是否仍与原快照一致。
## 只导出 FIELD_MAP 或 RUNTIME_FIELDS 可定位的字段，不把全部存档都当作读冲突。
func observed_selection_fields() -> Array:
	var result: Array = []
	for name: String in _observed_fields:
		if FIELD_MAP.has(name):
			result.append(FIELD_MAP[name].duplicate(true))
		elif RUNTIME_FIELDS.has(name):
			result.append({"section": "round_runtime", "key": name.trim_prefix("_")})
	return result
