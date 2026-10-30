## Meowdoku 产品的 Autoload 门面：兼容页面字段，协调存档提交与提交后的通知。
## 结算规则在 gameplays/doku/application；持久状态只写入 LocalCoreStore，统计允许合并写盘。
extends Node

signal storage_failed(result: Dictionary)

signal all_data_reset # 全量重置（reset_all）后发出，让各模块清缓存

# ---- 存档路径与口令 ----
## 旧版玩家档与残局档，仅用于一次性迁移。
const SAVE_DIR := "user://save_store/"
const SAVE_PATH_A := "user://save_store/save_a.cfg" # 双槽中的 A 槽
const SAVE_PATH_B := "user://save_store/save_b.cfg" # 双槽中的 B 槽
const SAVE_FLAG := "user://save_store/flag.txt" # 记录最后写成功的槽（A/B）
const SAVE_PATH_OLD := "user://save.cfg" # 旧版单文件存档，只用于迁移兜底
const SAVE_PATH_ENDGAME := "user://save_store/endgame.cfg" # 残局档：残局快照 + 本局统计 + 对局 ID

const ProductStore = preload("res://products/meowdoku/app/state/meowdoku_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const SettlementRules = preload("res://products/meowdoku/gameplay/application/meowdoku_settlement_rules.gd")
const Settlement = preload("res://products/meowdoku/gameplay/application/meowdoku_round_settlement.gd")
const Result = preload("res://scripts/framework/operation_result.gd")
const ROUND_RUNTIME_FIELDS := ["current_level_dirty", "current_level_retried", "demoted_this_level", "dda_tool_or_revive_used", "dda_revive_used", "dda_pending_demote", "is_daily_first_easy_level", "rnr_mod1_exempt", "rnr_g_prev_was_max"]

const SAVE_PASSWORD := "qd_x9K3mPv7RtN2sLwH8jFcZyA5eBkM1n" # 存档加密口令（ConfigFile 加密读写）

# ---- 两个 SaveStore 实例（_ready 里创建） ----
## 玩家档：双槽轮换 + 原子写
var _player_store: SaveStore
var _endgame_store: SaveStore # 只读旧残局，供一次性迁移
var _product_store: RefCounted
var _core_store: RefCounted
var _economy_service: RefCounted
var _storage_ready: bool = false
var _own_core_commit: bool = false
var _published_inventory: Dictionary = {}
var _last_storage_result: Dictionary = {}
var _reset_generation: int = 0 # 成功清档后，旧提交回执不能重新发布会话资格或 SDK 副作用

var _endgame_dirty: bool = false # 对局统计有未合并落盘的改动
var _pending_endgame_stats: Dictionary = {} # 已接收但尚未合并落盘的统计，不包含待提交的棋盘或设置
var _endgame_coalesce_timer: Timer # 0.5 秒合并写盘定时器，避免高频统计每笔都写文件

signal tool_count_changed(kind: String, count: int) # 道具数量变化时发出，局内 UI 监听刷新

# ---- 关卡进度与难度自适应（DDA） ----
## 当前关卡号，从 1 开始
var _current_level: int = 1
var _tutorial_done: bool = false # 新手引导是否已完成
var _has_shown_rate_us: bool = false # 是否已弹过评分引导

var _has_used_revive_free: bool = false # 免费复活是否已用过（只送一次）

var _warn_life_shown: bool = false # 是否已提示过「生命告急」

var _life_plus_first_done: bool = false # 生命上限 +1 的首次赠送是否已发

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

var _main_game_id: String = "" # 普通模式当前对局 ID（埋点串一局用）
var _daily_game_id: String = "" # 每日挑战当前对局 ID

# ---- 道具库存 ----
## 定位道具数量（初始 5）
var _tool_locate: int = 5
var _tool_hint: int = 5 # 提示道具数量（初始 5）
var _tool_undo: int = 3 # 撤销道具数量（初始 3）

# ---- 闪屏与语言 ----
## 最近一次展示闪屏的日期（判断「今天是否第一次启动」）
var _last_splash_date: String = ""

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
var _push_ask_count: int = 0 # 推送授权询问次数（最多问 2 次）

var _has_shown_att_guide: bool = false # ATT 授权引导是否已展示

var _interstitial_unlocked: bool = false # 插屏广告是否已解锁

var _banner_unlocked: bool = false # banner 广告是否已解锁

var _has_shown_draft_onboarding: bool = false # 草稿功能引导是否已展示

var _auto_mark_tutorial_done: bool = false # 每日自动标叉教程是否已完成

var _rule_info_bar_collapsed: bool = false # 规则说明栏是否处于折叠状态

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

var _today_played_count: int = 0 # 今日已开局数

var _today_active_sec: int = 0 # 今日前台活跃秒数（SessionManager 每 60 秒累加）

var _total_active_sec: int = 0 # 累计前台活跃秒数（GRT 时长埋点用）

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

# ---- 重试题目、最近出题与残局快照 ----
## 重试参数对应的关卡号（0 表示没有；只有关卡号匹配才生效）
var _retry_puzzle_level: int = 0
var _retry_puzzle_params: Dictionary = {} # 重试时要复用的题库参数（配合 _retry_puzzle_level 校验）

var _recent_puzzles: Array = [] # 最近出过的题目记录（含题库进度快照，用于去重与回滚）
const RECENT_PUZZLES_LIMIT := 100 # 最近出题记录的上限（超出丢最旧的）

var _endgame_snapshot: Dictionary = {} # 残局快照（真实存在 endgame.cfg，玩家档里只写空值）
const ENDGAME_SNAPSHOT_VERSION: int = 2 # 残局快照结构版本号

# ---- 仅内存的局内状态（不写进 _save_data，重启即丢） ----
## 仅 debug 构建可用的内存调试开关；正式构建始终关闭。
var _debug_mode: bool = false

var _current_level_dirty: bool = false # 本局是否动过道具/复活（脏了就没有干净通关连击）

var _current_level_retried: bool = false # 本局是否是重试局

var _demoted_this_level: bool = false # 本关是否已经降过档（一关最多降一次）

var _dda_tool_or_revive_used: bool = false # 本局是否用过道具或复活（DDA 降档判据）

var _dda_revive_used: bool = false # 本局是否用过复活

var _dda_pending_demote: bool = false # 待执行的降档（下一关是困难/特殊关时先挂起）

var _is_daily_first_easy_level: bool = false # 本局是否走了「每日首次降档」

var _rnr_mod1_exempt: bool = false # RnR 实验 mod1 豁免标记（通关只清理、不调档）

var _rnr_g_prev_was_max: bool = false # 上一段 g 是否取到了最大策略层

var coords_visible: bool = false # 坐标显示开关（唯一的 public 成员，UI 直接读写，不落盘）

# ---- 本次运行（冷启动）内的计数（不落盘） ----
## 本次运行是否仍算首次启动，mark_first_session_done 后置 false
var _first_session_runtime: bool = true

var _session_played_count: int = 0 # 本次会话已开局数

var _has_won_since_cold_start: bool = false # 冷启动后是否赢过（主页评分弹窗的前置条件）

var _daily_first_easy_available: bool = false # 今日是否还能享受首次降档（启动时评估一次）
var _daily_first_easy_evaluated: bool = false # 本次启动是否已评估过首次降档

var _session_consecutive_wins: int = 0 # 本次会话连续通关数（胜利页展示）

var _session_reward_view_count: int = 0 # 本次会话看过几次奖励页（激励广告频控用）

# ---- 结算文案的临时缓存（只为少算一次，不落盘） ----
## 关卡 → 提示种类 → 开局提示的击败百分比
var _start_toast_pct: Dictionary = {}

var _start_toast_iq_idx: Dictionary = {} # 关卡 → 开局提示选中的 IQ 文案下标

var _fail_text_revive_x: Dictionary = {} # 关卡 → 失败页文案的横坐标（避免每帧重算）

var _last_win_beat_percent: float = -1.0 # 最近一次通关的击败百分比（-1 = 无）

# ---- 帮助与版本信息 ----
## 最近一次打开帮助/FAQ 的时间戳（Helpshift 限流用）
var _help_last_open_time: int = 0

var _install_version: String = "" # 首次记录到的安装包版本号


# ================= 生命周期与存档初始化 =================
## 只读迁移旧档，打开统一核心存档，再同步页面兼容字段。
func _ready() -> void:
	_player_store = SaveStore.new(SAVE_PASSWORD, SAVE_DIR, true, SAVE_PATH_A, SAVE_PATH_B, SAVE_FLAG, SAVE_PATH_OLD)
	_endgame_store = SaveStore.new(SAVE_PASSWORD, SAVE_DIR, false, SAVE_PATH_ENDGAME)
	_endgame_coalesce_timer = Timer.new()
	_endgame_coalesce_timer.one_shot = true
	_endgame_coalesce_timer.wait_time = 0.5
	_endgame_coalesce_timer.timeout.connect(_on_endgame_coalesce_timeout)
	add_child(_endgame_coalesce_timer)
	_product_store = ProductStore.new(SAVE_DIR, SAVE_PASSWORD)
	_core_store = _product_store.core
	_last_storage_result = _product_store.open(_encode_profile_config(), _player_store, _endgame_store, "user://streak.cfg")
	_storage_ready = bool(_last_storage_result.get("ok", false))
	if _core_store.is_open():
		_apply_profile_config(ProductStore.profile_config(_core_store.snapshot()))
		_apply_round_runtime(_core_store.snapshot().get("round_runtime", {}))
		_published_inventory = _core_store.snapshot().get("inventory", {}).duplicate(true)
	if not _storage_ready:
		push_error("[GameState] 核心存档未能打开: " + str(_last_storage_result))
	_core_store.committed.connect(_on_core_committed)
	_economy_service = Economy.new(_core_store)
	_first_session_runtime = _is_first_session
	VibrateManager.set_enabled(_vibration_on)


# ================= 关卡进度与 DDA 状态 =================
## 取当前关卡号
func get_current_level() -> int:
	return _current_level


## 设置当前关卡号并立刻写盘
func set_current_level(value: int) -> void:
	_current_level = value
	_save_data()


## 新手引导是否已完成
func is_tutorial_done() -> bool:
	return _tutorial_done


## 标记新手引导完成并写盘
func set_tutorial_done(value: bool) -> bool:
	if _tutorial_done == value:
		return true
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return false
	candidate.profile["tutorial_done"] = value
	return bool(commit_core_candidate(candidate, _core_store.revision()).get("ok", false))


## 是否已弹过评分引导（主页判断用）
func has_shown_rate_us() -> bool:
	return _has_shown_rate_us


## 免费复活是否已用过
func has_used_revive_free() -> bool:
	return _has_used_revive_free


## 标记免费复活已用（重复调用直接返回）
func mark_revive_free_used() -> void:
	if _has_used_revive_free:
		return
	_has_used_revive_free = true
	_save_data()


## 冷启动后是否赢过一局（评分弹窗的前置条件）
func has_won_since_cold_start() -> bool:
	return _has_won_since_cold_start


# ================= 每日挑战：首次降档机会 =================
## 今日是否还能享受「每日首次降档」（结果由 evaluate_daily_first_easy 评估）
func is_daily_first_easy_available() -> bool:
	return _daily_first_easy_available


## 冷启动只评估降档资格；当天机会的日期由搭盘成功后的入场提交写入。
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
				_daily_first_easy_available = false
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
	_is_daily_first_easy_level = true
	consume_daily_first_easy()


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


# ---- RnR 实验标记：通过 round_runtime 与核心状态一起保存 ----
## 标记本局走 RnR mod1 豁免（通关时跳过 DDA 调档）
func mark_rnr_mod1_exempt() -> void:
	_rnr_mod1_exempt = true
	_save_data()


## 清掉 RnR mod1 豁免标记
func clear_rnr_mod1_exempt() -> void:
	_rnr_mod1_exempt = false
	_save_data()


## 查询 RnR mod1 豁免标记
func is_rnr_mod1_exempt() -> bool:
	return _rnr_mod1_exempt


## 上一段 g 是否取到最大策略层
func is_rnr_g_prev_was_max() -> bool:
	return _rnr_g_prev_was_max


## 记录本段 g 是否取到最大策略层
func set_rnr_g_prev_was_max(was_max: bool) -> void:
	_rnr_g_prev_was_max = was_max
	_save_data()


# ---- 本次会话的运行期计数（不落盘） ----
## 取本次会话连续通关数
func get_session_consecutive_wins() -> int:
	return _session_consecutive_wins


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


## 清掉生命告急标记
func reset_warn_life_shown() -> void:
	if not _warn_life_shown:
		return
	_warn_life_shown = false
	_save_data()


## 生命上限 +1 的首次赠送是否已发
func is_life_plus_first_done() -> bool:
	return _life_plus_first_done


## 标记首次赠送已发
func mark_life_plus_first_done() -> void:
	if _life_plus_first_done:
		return
	_life_plus_first_done = true
	_save_data()


## 清掉首次赠送标记
func reset_life_plus_first_done() -> void:
	if not _life_plus_first_done:
		return
	_life_plus_first_done = false
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


## 草稿功能引导是否已展示
func has_shown_draft_onboarding() -> bool:
	return _has_shown_draft_onboarding


## 标记草稿引导已展示
func mark_draft_onboarding_shown() -> void:
	if _has_shown_draft_onboarding:
		return
	_has_shown_draft_onboarding = true
	_save_data()


## 清掉草稿引导标记
func reset_draft_onboarding_shown() -> void:
	if not _has_shown_draft_onboarding:
		return
	_has_shown_draft_onboarding = false
	_save_data()


## 自动标叉教程是否已完成
func is_auto_mark_tutorial_done() -> bool:
	return _auto_mark_tutorial_done


## 标记自动标叉教程完成
func mark_auto_mark_tutorial_done() -> void:
	if _auto_mark_tutorial_done:
		return
	_auto_mark_tutorial_done = true
	_save_data()


## 清掉自动标叉教程标记
func reset_auto_mark_tutorial_done() -> void:
	if not _auto_mark_tutorial_done:
		return
	_auto_mark_tutorial_done = false
	_save_data()


## 今日自动标叉是否已开启（先做日切再读）
func is_daily_auto_mark_enabled_for_today() -> bool:
	_roll_day_if_needed()
	return _daily_auto_mark_enabled


## 免费资格与当日权益一次提交；广告已确认的入口传 false，失败可直接重试保存。
func activate_daily_auto_mark(use_free: bool) -> Dictionary:
	if not is_storage_ready():
		return Result.failure("store_not_open")
	_roll_day_if_needed()
	var candidate := get_core_candidate()
	if candidate.profile.get("daily_auto_mark_enabled", false):
		return Result.success({"duplicate": true})
	if use_free and candidate.profile.get("daily_auto_mark_free_consumed", false):
		return Result.failure("daily_auto_mark_free_unavailable")
	if use_free:
		candidate.profile["daily_auto_mark_free_consumed"] = true
	candidate.profile["daily_auto_mark_enabled"] = true
	return commit_core_candidate(candidate, _core_store.revision())


## 标记今日已开启自动标叉
func mark_daily_auto_mark_enabled_today() -> void:
	_roll_day_if_needed()
	if _daily_auto_mark_enabled:
		return
	_daily_auto_mark_enabled = true
	_save_data()


## 清掉「今日已开启自动标叉」
func reset_daily_auto_mark_enabled() -> void:
	if not _daily_auto_mark_enabled:
		return
	_daily_auto_mark_enabled = false
	_save_data()


## 今日免费自动标叉是否已用掉
func is_daily_auto_mark_free_consumed() -> bool:
	return _daily_auto_mark_free_consumed


## 标记今日免费次数已用
func mark_daily_auto_mark_free_consumed() -> void:
	if _daily_auto_mark_free_consumed:
		return
	_daily_auto_mark_free_consumed = true
	_save_data()


## 清掉免费次数标记
func reset_daily_auto_mark_free_consumed() -> void:
	if not _daily_auto_mark_free_consumed:
		return
	_daily_auto_mark_free_consumed = false
	_save_data()


## 取上一局保存的自动标叉设置（-1 = 没有）
func get_saved_game_auto_mark() -> int:
	return _saved_game_auto_mark


## 保存自动标叉设置，值没变就不写盘
func set_saved_game_auto_mark(v: int) -> void:
	if _saved_game_auto_mark == v:
		return
	_saved_game_auto_mark = v
	_save_data()


## 规则说明栏是否折叠
func is_rule_info_bar_collapsed() -> bool:
	return _rule_info_bar_collapsed


## 记住规则说明栏的折叠状态
func set_rule_info_bar_collapsed(value: bool) -> void:
	if _rule_info_bar_collapsed == value:
		return
	_rule_info_bar_collapsed = value
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


## 每日棋盘准备成功后提交入场；只有 NEW 同时更新日期、统计与埋点身份。
func commit_daily_entry(auto_mark_variant: int, new_game_id: String = "", started_date: String = "") -> Dictionary:
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return Result.failure("store_not_open")
	var before: Dictionary = candidate.duplicate(true)
	candidate.profile["saved_game_auto_mark"] = auto_mark_variant
	if not new_game_id.is_empty():
		candidate.profile["daily_started_date"] = started_date
		candidate.endgame.stats["daily_total"] = {}
		candidate.endgame.stats["daily_round"] = {}
		candidate.endgame.stats["daily_id"] = new_game_id
	if candidate == before:
		return Result.success()
	var result: Dictionary = commit_core_candidate(candidate, _core_store.revision())
	return result if result.get("ok", false) else Result.wrap_failure("entry_commit_failed", result)


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


## 记录每日挑战通关：日期/用时/击败百分比，并刷新最好成绩
func mark_daily_completed(date: String, elapsed_sec: int, beat_percent: float) -> void:
	_daily_completed_date = date
	_daily_elapsed_sec = elapsed_sec
	_daily_beat_percent = beat_percent

	if beat_percent > _daily_best_beat_percent:
		_daily_best_beat_percent = beat_percent
	_has_won_since_cold_start = true
	_save_data()


## 清掉每日挑战的通关记录
func clear_daily_completion() -> void:
	_daily_completed_date = ""
	_daily_elapsed_sec = 0
	_daily_beat_percent = 0.0
	_daily_best_beat_percent = 0.0
	_save_data()


## 跨天重置：清今日计数、把今日会话数挪到昨日、活跃天数 +1（本身不写盘，由调用方负责）
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


# ================= 会话、活跃时长与日切 =================
## 会话开始（SessionManager 调用）：先日切，再累计会话数并清空本次会话的计数
func on_session_started() -> void:
	_roll_day_if_needed()
	_session_count += 1
	_today_session_count += 1
	_session_played_count = 0
	_session_consecutive_wins = 0
	_session_reward_view_count = 0
	_save_data()


## 取累计会话数
func get_session_count() -> int:
	return _session_count


## 取活跃天数（会先做日切）
func get_active_days() -> int:
	_roll_day_if_needed()
	return _active_days


## 取本次会话已开局数
func get_session_played_count() -> int:
	return _session_played_count


## 取今日已开局数
func get_today_played_count() -> int:
	_roll_day_if_needed()
	return _today_played_count


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
func add_today_active_sec(delta_sec: int) -> bool:
	if delta_sec <= 0:
		return true
	_roll_day_if_needed()
	_today_active_sec += delta_sec
	_total_active_sec += delta_sec
	return _save_data()


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


## 取待领取奖励的独立副本；修改副本不会改变待领取资格。
func get_pending_rewards() -> Array:
	return _pending_rewards.duplicate(true)


## 登记成功后调用方才可消费原凭证；重复登记不再写盘。
func add_pending_reward(reward: Dictionary) -> Dictionary:
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return Result.failure("not_open")
	var pending: Array = candidate.profile.get("pending_rewards", [])
	for existing: Dictionary in pending:
		if existing == reward or (not str(reward.get("show_id", "")).is_empty() and existing.get("show_id") == reward.get("show_id")):
			return Result.success({"status": "already_applied"})
	pending.append(reward.duplicate(true))
	candidate.profile["pending_rewards"] = pending
	return commit_core_candidate(candidate, _core_store.revision())


## 取走全部待领取奖励并清空（主页弹领取窗时调用）
func pop_all_pending_rewards() -> Array:
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return []
	var out: Array = candidate.profile.get("pending_rewards", []).duplicate(true)
	if out.is_empty():
		return out
	candidate.profile["pending_rewards"] = []
	return out if commit_core_candidate(candidate, _core_store.revision()).get("ok", false) else []


## 保存一次正常发奖记录；失败由 SDK 适配层保留该事件重试。
func record_normal_reward(ts: int) -> bool:
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return false
	var history: Array = candidate.profile.get("reward_history_ts", [])
	history.append(ts)
	var cutoff: int = ts - _REWARD_HISTORY_RETAIN_SEC
	var fresh: Array = []
	for t in history:
		if int(t) >= cutoff:
			fresh.append(int(t))
	candidate.profile["reward_history_ts"] = fresh
	return bool(commit_core_candidate(candidate, _core_store.revision()).get("ok", false))


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
func remove_pending_rewards(entries: Array) -> bool:
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return false
	var pending: Array = candidate.profile.get("pending_rewards", [])
	for e in entries:
		pending.erase(e)
	candidate.profile["pending_rewards"] = pending
	return bool(commit_core_candidate(candidate, _core_store.revision()).get("ok", false))


## 补偿资格、每日额度、奖励库存同次提交；页面仅在成功后播放领取动画。
func claim_restored_rewards(requests: Array) -> Dictionary:
	if requests.is_empty():
		return Result.failure("empty_request", "", {"status": "empty_request"})
	var remaining := get_restore_remaining_today(int(Time.get_unix_time_from_system()))
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return Result.failure("not_open", "", {"status": "not_open"})
	var queue: Array = candidate.profile.get("pending_rewards", [])
	var all_grants: Array = []
	var claimed: int = 0
	var seen: Dictionary = {}
	for request in requests:
		if not request is Dictionary or not request.get("entry") is Dictionary:
			return Result.failure("invalid_request", "", {"status": "invalid_request"})
		var entry: Dictionary = request.entry
		var identity := str(entry.get("show_id", ""))
		if identity.is_empty():
			identity = JSON.stringify(entry).sha256_text()
		var key := "ad_restore/" + identity
		if seen.has(key):
			continue
		seen[key] = true
		if candidate.claims.has(key):
			continue
		if not queue.has(entry) or claimed >= remaining:
			return Result.failure("no_longer_eligible", "", {"status": "no_longer_eligible"})
		# 奖励内容在业务层按原广告来源重新求值，不接受页面自行改数量。
		var items: Array = UniKitManager.restore_items_for_position(str(entry.get("source", "")))
		var staged: Dictionary = _economy_service.stage_award(candidate, items, 0, Tracker.PropSource.REWARD_FAIL_DLG, "", key)
		if not staged.get("ok", false):
			return staged
		var applied: Dictionary = _economy_service.stage_claim(candidate, int(staged.uid))
		if not applied.get("ok", false):
			return applied
		all_grants.append_array(applied.grants)
		queue.erase(entry)
		claimed += 1
	if claimed == 0:
		return {"ok": true, "status": "already_applied", "grants": []}
	candidate.profile["pending_rewards"] = queue
	candidate.profile["restored_today_count"] = int(candidate.profile.get("restored_today_count", 0)) + claimed
	var result := commit_core_candidate(candidate, _core_store.revision())
	if result.get("ok", false):
		for grant: Dictionary in all_grants:
			Tracker.track_prop_get(str(grant.kind), str(grant.reason), int(grant.count), int(grant.balance))
		result["grants"] = all_grants
	return result


## 取今日会话数
func get_today_session_count() -> int:
	_roll_day_if_needed()
	return _today_session_count


## 取昨日会话数
func get_last_day_session_count() -> int:
	_roll_day_if_needed()
	return _last_day_session_count


# ================= 道具库存与发放中的奖励 =================
## 按 kind（locate/hint/undo）取道具数量，未知 kind 返回 0
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


## 取推送授权询问次数
func get_push_ask_count() -> int:
	return _push_ask_count


## 推送授权询问次数 +1
func inc_push_ask_count() -> void:
	_push_ask_count += 1
	_save_data()


## 设置道具数量：变少即视为消耗（首次会置 has_used_tool），写盘并发 tool_count_changed
func set_tool_count(kind: String, count: int) -> bool:
	if kind not in ["locate", "hint", "undo"] or count < 0:
		return false
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return false
	var previous: int = int(candidate.inventory.get(kind, 0))
	candidate.inventory[kind] = count
	if count < previous:
		candidate.profile["has_used_tool"] = true
	return bool(commit_core_candidate(candidate, _core_store.revision()).get("ok", false))


## 取「发放中」奖励的快照（AwardManager 防重复发用）
func get_in_flight_awards() -> Array:
	return _in_flight_awards.duplicate(true)


## 登记一条发放中的奖励
func add_in_flight_award(_entry: Dictionary) -> void:
	push_error("[GameState] 请使用 EconomyService.register_award 登记奖励")


## 按 uid 移除发放中的奖励（从后往前找第一个匹配）
func remove_in_flight_award(_uid: int) -> void:
	push_error("[GameState] 奖励只能通过 EconomyService.claim_award 原子入账并移除")


## 按 uid 查发放中的奖励，找不到返回空字典
func find_in_flight_award(uid: int) -> Dictionary:
	for entry: Dictionary in _in_flight_awards:
		if int(entry.get("uid", -1)) == uid:
			return entry.duplicate(true)
	return {}


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
func set_apply_locale(value: String) -> bool:
	return _commit_preferences({"apply_locale": value})


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


## 设置音乐开关，并记住「用户手动改过」
func set_music_on(value: bool) -> bool:
	return _commit_preferences({"music_on": value, "music_user_modified": true})


## 用户没手动改过时，按地区默认值初始化音乐开关
func init_music_default(default_on: bool) -> void:
	if _music_user_modified:
		return
	if _music_on == default_on:
		return
	_commit_preferences({"music_on": default_on})


## 音效开关是否开启
func is_sound_on() -> bool:
	return _sound_on


## 设置音效开关
func set_sound_on(value: bool) -> bool:
	return _commit_preferences({"sound_on": value})


## 震动开关是否开启
func is_vibration_on() -> bool:
	return _vibration_on


## 设置震动开关，并同步给 VibrateManager
func set_vibration_on(value: bool) -> bool:
	if not _commit_preferences({"vibration_on": value}):
		return false
	VibrateManager.set_enabled(value)
	return true


## people 开关是否开启
func is_people_on() -> bool:
	return _people_on


## 设置 people 开关
func set_people_on(value: bool) -> bool:
	return _commit_preferences({"people_on": value})


## 偏好只有提交成功才投影到页面；平台副作用由调用者在成功后执行。
func _commit_preferences(values: Dictionary) -> bool:
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return false
	candidate.profile.merge(values, true)
	return bool(commit_core_candidate(candidate, _core_store.revision()).get("ok", false))


# ================= 局内 DDA 标记与仅内存调试开关 =================
## 正式构建始终关闭；debug 构建保留旧 rel 标签与内存开关的行为。
func is_debug_mode() -> bool:
	return OS.is_debug_build() and (_debug_mode or not OS.has_feature("rel"))


## 设置调试模式（不写盘）
func set_debug_mode(value: bool) -> void:
	_debug_mode = value


## 本局是否动过道具/复活
func is_current_level_dirty() -> bool:
	return _current_level_dirty


## 标记本局已「弄脏」（打断干净通关连击）
func mark_current_level_dirty() -> void:
	_current_level_dirty = true
	_save_data()


## 清掉弄脏标记（重开或继续本局时）
func clear_current_level_dirty() -> void:
	_current_level_dirty = false
	_save_data()


## 标记本局用过道具或复活（DDA 降档判据）
func mark_dda_tool_or_revive_used() -> void:
	_dda_tool_or_revive_used = true
	_save_data()


## 标记本局用过复活
func mark_dda_revive_used() -> void:
	_dda_revive_used = true
	_save_data()


## 把本局标记为「每日首次降档局」
func mark_daily_first_easy_level() -> void:
	_is_daily_first_easy_level = true
	_save_data()


## 本局是否走了每日首次降档
func is_current_level_daily_first_easy() -> bool:
	return _is_daily_first_easy_level


## 本局是否是重试局
func is_current_level_retried() -> bool:
	return _current_level_retried


## 存下重试本关要复用的题库参数（会写盘）
func set_retry_puzzle(level: int, params: Dictionary) -> void:
	_retry_puzzle_level = level
	_retry_puzzle_params = params.duplicate(true)
	_save_data()


## 取某关重试参数的独立副本；关卡号不匹配或没存过就返回空字典。
func get_retry_puzzle(level: int) -> Dictionary:
	if _retry_puzzle_level == level and not _retry_puzzle_params.is_empty():
		return _retry_puzzle_params.duplicate(true)
	return {}


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


## 题库游标 +1（出题后调用，会写盘）
func advance_bank_index(sz: int, rank: int, tier: String = "") -> void:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_bank_progress[key] = _bank_progress.get(key, 0) + 1
	_save_data()


## 取新版题库进度的独立副本；缺省值不写入活状态，修改后通过 setter 保存。
func get_main_progress(sz: int, rank: int, tier: String = "") -> Dictionary:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	return (_main_bank_progress.get(key, {"lk_mod": 0, "regular": 0, "lkstyle": 0, "transform": 0}) as Dictionary).duplicate(true)


## 写回新版题库进度
func set_main_progress(sz: int, rank: int, tier: String, progress: Dictionary) -> void:
	var key := "%d_%d%s" % [sz, rank, "_H" if tier == "H" else ""]
	_main_bank_progress[key] = progress.duplicate(true)
	_save_data()


## 取 lkmod 进度的独立副本；查询缺省进度不创建记录。
func get_lkmod_progress(sz: int, rank: int) -> Dictionary:
	var key := "%d_%d" % [sz, rank]
	return (_lkmod_progress.get(key, {"idx": 0}) as Dictionary).duplicate(true)


## 写回 lkmod 玩法进度
func set_lkmod_progress(sz: int, rank: int, progress: Dictionary) -> void:
	var key := "%d_%d" % [sz, rank]
	_lkmod_progress[key] = progress.duplicate(true)
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


# ================= 出题去重与残局快照 =================
## 记录一次出题（连同三份题库进度快照，供去重/回滚），返回同一题上一次的记录
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


## 取最近出题记录的深拷贝
func get_recent_puzzles() -> Array:
	return _recent_puzzles.duplicate(true)


## 取残局快照副本，调用方不能绕过提交修改存档。
func get_endgame_snapshot() -> Dictionary:
	return _endgame_snapshot.duplicate(true)


## 存残局快照，与玩家核心状态一并提交。
func set_endgame_snapshot(snapshot: Dictionary) -> bool:
	_endgame_snapshot = snapshot.duplicate(true)
	return _save_endgame()


## 清残局快照（本局真正结束/重开时调用）
func clear_endgame_snapshot() -> bool:
	if _endgame_snapshot.is_empty():
		return true
	_endgame_snapshot = {}
	return _save_endgame()


## endgame 槽的 7 个字段是否全空（全空就直接删文件）
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


## 残局和统计共用核心提交，不再单独写 endgame.cfg。
func _save_endgame() -> bool:
	return _save_data()


## 接收统计快照并启动 0.5 秒合并定时器；失败回投影也保留这份已接收数据。
func _request_save_endgame() -> void:
	_endgame_dirty = true
	_pending_endgame_stats = _capture_endgame_stats()
	if _endgame_coalesce_timer != null and _endgame_coalesce_timer.is_stopped():
		_endgame_coalesce_timer.start()


## 合并计时到点：脏了才真正写盘
func _on_endgame_coalesce_timeout() -> void:
	if _endgame_dirty:
		_save_endgame()


## 兼容旧刷新入口，只读当前核心快照。
func _resolve_endgame_store() -> void:
	_load_data()


## 系统通知：切后台或收到关闭请求时，把还没落盘的 endgame 数据立刻写掉
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _endgame_dirty:
			_save_endgame()


# ================= 通关 / 失败结算与 DDA 调档 =================
## 通关结算：推进关卡号、按干净通关/连续失败/重试情况升降策略层，并补报 GRT 关卡埋点
func on_level_won(level_num: int) -> void:
	_apply_legacy_main_progress(level_num, "win")


## 失败结算：标记重试与弄脏、清掉干净通关连击，并累计失败次数供降档
func on_level_failed(level_num: int) -> void:
	_apply_legacy_main_progress(level_num, "fail")


## 旧进度入口复用纯数据规则，不再维护第二套 DDA 实现。
func _apply_legacy_main_progress(level_num: int, outcome: String) -> void:
	# 兼容只更新进度的旧调用；完整游戏结算应使用带稳定 id 的 settle_main_round。
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return
	var policy := _settlement_dda_policy(level_num)
	if outcome == "win":
		SettlementRules.main_win(candidate.profile, candidate.round_runtime, level_num, policy)
	else:
		SettlementRules.main_fail(candidate.profile, candidate.round_runtime, level_num, policy)
	if not commit_core_candidate(candidate, _core_store.revision()).get("ok", false):
		return
	if outcome == "win":
		_start_toast_pct.erase(level_num)
		_start_toast_iq_idx.erase(level_num)
		_has_won_since_cold_start = true
		_session_consecutive_wins += 1
		Tracker.try_track_grt_level_pass(level_num)
		Tracker.try_track_grt_level_window(level_num)
	else:
		_session_consecutive_wins = 0


## 调试用：直接跳到某关，把策略层夹到该关允许区间并清空所有局内标记
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


# ================= 存档读写 =================
## 旧字段编码适配；只构造数据，不再写旧玩家文件。
func _encode_profile_config() -> ConfigFile:
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

	# 以下 6 个字段归 endgame 槽管，这里显式写空值，避免玩家档里留下旧副本
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

	return cfg


## 将经过 schema 验证的核心状态投影为旧字段，供现有页面读取。
func _apply_profile_config(cfg: ConfigFile) -> void:
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
	if _daily_first_easy_date >= _today_str():
		_daily_first_easy_available = false
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


# ================= 存档迁移、日期与全量重置 =================
## 显式业务事务入口；旧存档只在 ProductStore 初次打开时读取。
func get_core_store() -> RefCounted:
	return _core_store


func get_economy_service() -> RefCounted:
	return _economy_service


func is_storage_ready() -> bool:
	return _storage_ready


func get_last_storage_result() -> Dictionary:
	return _last_storage_result.duplicate(true)


## id 是一次生命耗尽/退出/通关尝试的稳定身份，复活后的下一尝试使用新 id。
func settle_main_round(round_id: String, level: int, outcome: String, runtime_snapshot: Dictionary = {}, retry_params: Dictionary = {}) -> Dictionary:
	return _settle_round(Settlement.main_round(round_id, level, outcome, runtime_snapshot, retry_params))


func settle_daily_round(round_id: String, date: String, outcome: String, elapsed_sec: int = 0, beat_percent: float = 0.0, runtime_snapshot: Dictionary = {}) -> Dictionary:
	return _settle_round(Settlement.daily_round(round_id, date, outcome, elapsed_sec, beat_percent, runtime_snapshot))


func settle_preview_round(round_id: String, outcome: String, runtime_snapshot: Dictionary = {}) -> Dictionary:
	return _settle_round(Settlement.preview_round(round_id, outcome, runtime_snapshot))


## 旧完整残局的校验与幂等规则也在产品结算中，入口只保留页面兼容。
func settle_legacy_completed_main(level: int) -> Dictionary:
	return _settle_round(Settlement.legacy_main(level))


func _settle_round(request: MeowdokuRoundSettlement) -> Dictionary:
	var generation: int = _reset_generation
	var candidate := get_core_candidate()
	var expected_revision: int = _core_store.revision() if _core_store != null else 0
	var policy := request.saved_dda_policy(candidate)
	if request.mode == "main" and request.level > 0 and policy.is_empty():
		policy = _settlement_dda_policy(request.level)
	var staged := request.stage(candidate, _economy_service, _today_str(), policy)
	if not staged.ok or staged.get("duplicate", false):
		return staged
	var result := commit_core_candidate(candidate, expected_revision)
	if not result.ok:
		return result
	if generation == _reset_generation:
		_publish_settlement(request, staged.grants, generation)
	result["grants"] = staged.grants
	result["duplicate"] = false
	return result


## 会话计数和 SDK 通知只在持久提交成功后更新；重复结算不会到达这里。
func _publish_settlement(request: MeowdokuRoundSettlement, grants: Array, generation: int) -> void:
	for grant: Dictionary in grants:
		Tracker.track_prop_get(str(grant.kind), str(grant.reason), int(grant.count), int(grant.balance))
		if generation != _reset_generation:
			return
	if not request.legacy_completed:
		_session_played_count += 1
	if request.mode == "main" and request.level > 0:
		if request.outcome == "win":
			_start_toast_pct.erase(request.level)
			_start_toast_iq_idx.erase(request.level)
			_has_won_since_cold_start = true
			_session_consecutive_wins += 1
			Tracker.try_track_grt_level_pass(request.level)
			if generation != _reset_generation:
				return
			Tracker.try_track_grt_level_window(request.level)
		else:
			_session_consecutive_wins = 0
	elif request.mode == "daily" and request.outcome == "win":
		_has_won_since_cold_start = true


func _settlement_dda_policy(level: int) -> Dictionary:
	var next_level := level + 1
	var next_is_hard: bool = LevelData.is_hard_level_group_j(next_level) if ABTestManager.rule_normal_rank.is_group_j() else LevelData.is_hard_level(next_level)
	return {
		"retry_once": ABTestManager.dda_rank.is_retry_once_demote(),
		"tool_revive": ABTestManager.dda_rank.is_tool_revive_demote(),
		"any_action": ABTestManager.dda_rank.is_any_action_demote(),
		"next_is_skip": next_is_hard or LevelData.is_special_level(next_level),
	}


## 将旧字段尚未合并的统计一起纳入候选，避免别的业务提交把它们覆盖。
func get_core_candidate() -> Dictionary:
	if _core_store == null or not _core_store.is_open():
		return {}
	var candidate: Dictionary = _core_store.snapshot()
	var encoded := ProductStore.capture_profile(_encode_profile_config())
	candidate["profile"] = encoded.profile
	candidate["inventory"] = encoded.inventory
	candidate["endgame"] = _capture_endgame()
	candidate["round_runtime"] = _capture_round_runtime()
	return candidate


func _capture_round_runtime() -> Dictionary:
	var runtime: Dictionary = {}
	for field: String in ROUND_RUNTIME_FIELDS:
		runtime[field] = bool(get("_" + field))
	return runtime


func _apply_round_runtime(runtime: Dictionary) -> void:
	for field: String in ROUND_RUNTIME_FIELDS:
		set("_" + field, bool(runtime.get(field, false)))


func _capture_endgame() -> Dictionary:
	return {"snapshot": _endgame_snapshot.duplicate(true), "stats": _capture_endgame_stats()}


func _capture_endgame_stats() -> Dictionary:
	return {
		"main_total": _main_game_total_stats.duplicate(true), "daily_total": _daily_game_total_stats.duplicate(true),
		"main_round": _main_game_round_stats.duplicate(true), "daily_round": _daily_game_round_stats.duplicate(true),
		"main_id": _main_game_id, "daily_id": _daily_game_id,
	}


func commit_core_candidate(candidate: Dictionary, expected_revision: int) -> Dictionary:
	if _core_store == null or not _core_store.is_open():
		return Result.failure("not_open", "核心存档不可用", {"status": "not_open"})
	_own_core_commit = true
	var result: Dictionary = _core_store.commit(candidate, expected_revision)
	_own_core_commit = false
	_last_storage_result = result
	if not result.get("ok", false):
		_load_data()
		storage_failed.emit(result)
		push_error("[GameState] 保存未完成: " + str(result))
	return result


func _save_data() -> bool:
	if _core_store == null or not _core_store.is_open():
		return false
	return bool(commit_core_candidate(get_core_candidate(), _core_store.revision()).get("ok", false))


func _load_data() -> void:
	if _core_store != null and _core_store.is_open():
		_apply_core_snapshot(_core_store.snapshot(), true)


func _apply_core_snapshot(state: Dictionary, preserve_pending_stats: bool) -> void:
	# 未落盘统计是已接收的独立操作；失败候选的棋盘、设置等仍恢复为权威快照。
	if preserve_pending_stats and _endgame_dirty:
		state = state.duplicate(true)
		state.endgame["stats"] = _pending_endgame_stats.duplicate(true)
	_apply_profile_config(ProductStore.profile_config(state))
	_apply_round_runtime(state.get("round_runtime", {}))


func _on_core_committed(_revision: int) -> void:
	# 独立库存提交与尚未合并的统计无关，保留后者直到其自己的合并写盘。
	var own_commit: bool = _own_core_commit
	_own_core_commit = false
	if own_commit:
		# 本次候选已经包含先前登记的数据。先清理，再通知观察者；
		# 通知中新登记的统计或嵌套提交不属于这次收尾，不能在返回时清掉。
		_endgame_dirty = false
		_pending_endgame_stats.clear()
		if _endgame_coalesce_timer != null:
			_endgame_coalesce_timer.stop()
	var state: Dictionary = _core_store.snapshot()
	_apply_core_snapshot(state, not own_commit)
	_storage_ready = true
	var publication_revision: int = _core_store.revision()
	for kind in state.inventory:
		var count: int = int(state.inventory[kind])
		if _published_inventory.get(kind, -1) != count:
			# 逐项记录已发布值。监听者同步提交时，会接手尚未通知的字段；
			# 外层不再重复发最新值，也不把旧余额发到新状态之后。
			_published_inventory[kind] = count
			tool_count_changed.emit(kind, count)
			if _core_store.revision() != publication_revision:
				return


func get_streak_data() -> Dictionary:
	if _core_store == null or not _core_store.is_open():
		return {}
	return _core_store.snapshot().get("features", {}).get("streak", {}).duplicate(true)


func commit_streak_data(data: Dictionary) -> bool:
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return false
	var merged: Dictionary = candidate.features.streak.duplicate(true)
	merged.merge(data, true)
	candidate.features["streak"] = merged
	return bool(commit_core_candidate(candidate, _core_store.revision()).get("ok", false))


## 切组资格与补偿礼包一起登记；弹窗是否播放不再决定奖励能否恢复。
func commit_streak_transition(data: Dictionary, items: Array, reason: String) -> Dictionary:
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return Result.failure("not_open", "", {"status": "not_open"})
	var stored: Dictionary = candidate.features.streak
	if stored.get("last_group", -1) == data.get("last_group", -1):
		return {"ok": true, "status": "duplicate", "uid": int(stored.get("switch_award_uid", 0))}
	var merged := stored.duplicate(true)
	merged.merge(data, true)
	var staged: Dictionary = _economy_service.stage_award(candidate, items, 0, reason)
	if not staged.get("ok", false):
		return staged
	merged["switch_award_uid"] = int(staged.uid)
	candidate.features["streak"] = merged
	var result := commit_core_candidate(candidate, _core_store.revision())
	if result.get("ok", false):
		result["uid"] = int(staged.uid)
	return result


## 签到资格和待领取奖励在同一候选中提交；业务重试不会再次登记奖励。
func commit_streak_checkin(data: Dictionary, items: Array, reason: String, bonus_reason: String) -> Dictionary:
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return Result.failure("not_open", "", {"status": "not_open"})
	var date: String = str(data.get("last_checkin_date", ""))
	if date.is_empty():
		return Result.failure("invalid_date", "", {"status": "invalid_date"})
	var key := "streak/checkin/" + date
	if candidate.claims.has(key) or candidate.features.streak.get("last_checkin_date", "") == date:
		return {"ok": true, "status": "duplicate", "duplicate": true, "uid": int(candidate.claims.get(key, 0))}
	var merged: Dictionary = candidate.features.streak.duplicate(true)
	merged.merge(data, true)
	candidate.features["streak"] = merged
	var uid: int = 0
	if not items.is_empty():
		var staged: Dictionary = _economy_service.stage_award(candidate, items, 1, reason, bonus_reason, key)
		if not staged.get("ok", false):
			return staged
		uid = int(staged.uid)
	else:
		candidate.claims[key] = 0
	var result := commit_core_candidate(candidate, _core_store.revision())
	if result.get("ok", false):
		result["uid"] = uid
	return result


## 本地日期字符串 YYYY-MM-DD，所有跨天判断都用它
func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%d-%02d-%02d" % [dt.year, dt.month, dt.day]


## 全量重置：所有字段恢复默认（含设置），写盘后发 all_data_reset 让各模块清缓存
func reset_all() -> bool:
	if not is_storage_ready():
		return false
	var generation: int = _reset_generation
	var previous_first_session: bool = _first_session_runtime
	var previous_toasts: Dictionary = _start_toast_pct.duplicate(true)
	var previous_iq: Dictionary = _start_toast_iq_idx.duplicate(true)
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
	_people_on = true
	_has_used_tool = false
	_prop_highlight_shown = false
	_push_ask_count = 0
	_has_shown_att_guide = false
	_interstitial_unlocked = false
	_banner_unlocked = false
	_has_shown_draft_onboarding = false
	_auto_mark_tutorial_done = false
	_rule_info_bar_collapsed = false
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
	# 保留奖励发号水位，旧回调不能在重置后撞上新奖励。
	var candidate := get_core_candidate()
	if candidate.is_empty():
		return false
	candidate["pending_awards"] = []
	candidate["claims"] = {}
	candidate["features"] = {"streak": {}}
	# 保留每个玩法的发号水位；旧回调不能与重置后的第一局撞号。
	for key in candidate.round_services:
		var record: Dictionary = candidate.round_services[key]
		record["status"] = "reset"
		record["last_receipt"] = {}
		record["settlement"] = {}
	candidate["product_settlements"] = {}
	candidate["round_runtime"] = {}
	if not commit_core_candidate(candidate, _core_store.revision()).get("ok", false):
		# storage_failed 的同步监听也可能已经完成新的清档；旧失败不能恢复其之前的缓存。
		if generation == _reset_generation:
			_first_session_runtime = previous_first_session
			_start_toast_pct = previous_toasts
			_start_toast_iq_idx = previous_iq
		return false
	if generation != _reset_generation:
		return true # 后来的成功清档已发布；旧收尾不能再次清会话或通知消费者。
	# 同进程继续运行的重置入口也必须丢弃旧会话资格；失败时这些字段不动。
	_session_played_count = 0
	_session_consecutive_wins = 0
	_session_reward_view_count = 0
	_has_won_since_cold_start = false
	_daily_first_easy_available = false
	_daily_first_easy_evaluated = false
	_fail_text_revive_x.clear()
	_reset_generation += 1
	VibrateManager.set_enabled(_vibration_on)
	all_data_reset.emit()
	return true
