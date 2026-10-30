## 普通对局页面：入口参数 → 关卡配置/题面 → 棋盘 → 残局快照 → 通关/失败结算
## 输入链路：BoardView 拖拽信号 → 父类 BaseGamePage 消费 CellAction → _validate_board 调 QueendokuCore 判通关
class_name GamePage
extends BaseGamePage

var _terminal_started_ms: int = 0 # 同一次终局保存重试不延长上报时长。

enum EntryMode { NORMAL, BANK, BANK_SP, DEBUG_CONFIG, DEBUG_PREBUILT } # 入口模式：普通关卡 / 题库 / SP 题库 / 调试配置 / 调试预置

# ================= 成员变量 =================
# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _level_label: Label = $Root/VBoxContainer/Header/LevelLabel # 顶部关卡标题
@onready var _level_display_value: Label = $Root/VBoxContainer/Header/LevelDisplay/Value # 标题里的关卡数字
@onready var _coin_label: Label = $Root/VBoxContainer/Header/CoinLabel # 顶部金币数字（本页只显示，不结算）
@onready var _prev_btn: Button = $Root/VBoxContainer/Header/PrevBtn # 题库内上一题（题量 > 1 才显示）
@onready var _next_btn: Button = $Root/VBoxContainer/Header/NextBtn # 题库内下一题
@onready var _normal_toast: GameNormalToast = $Root/NormalToast # 普通难度开场提示条
@onready var _hard_toast: GameHardToast = $Root/HardToast # 困难难度开场提示条

# ---- 开场提示条与入口按钮锁 ----
var _active_toast: BaseGameToast = null # 当前挂着的提示条，没有则为 null

## 入场动画期间先屏蔽的按钮（设置 / 返回主页）
@onready var _entry_locked_buttons: Array[Button] = [
	$Root/VBoxContainer/Header/SettingsBtn,
	$Root/VBoxContainer/Header/GearBtn,
]

var _entry_btn_lock_seq: int = 0 # 入口按钮锁序号：解锁回调靠它判断自己是否已过期

# ---- 子节点引用：生命预警与挂机引导 ----
@onready var _anim_tips: AnimationPlayer = $AnimTips # 生命预警动画播放器
@onready var _warn_tips: Control = $Root/VBoxContainer/CatHeartRow/Tips # 预警气泡根节点
@onready var _warn_bubble: Control = $Root/VBoxContainer/CatHeartRow/Tips/Bubble # 预警气泡
@onready var _warn_tail: Sprite2D = $Root/VBoxContainer/CatHeartRow/Tips/Bubble/Tail # 指向红心的小尾巴
@onready var _warn_overlay: ColorRect = $Root/Overlay # 预警期间的全屏遮罩
@onready var _warn_mask: Sprite2D = $Root/VBoxContainer/CatHeartRow/HeartBg/EtMask007 # 被预警红心的遮罩贴图
@onready var _idle_guide_overlay: Control = $Root/IdleGuideOverlay # 挂机引导整层
@onready var _idle_guide_hand: Control = $Root/IdleGuideOverlay/HandHint # 引导手指
@onready var _idle_guide_spine: Node = $Root/IdleGuideOverlay/HandHint/ui_guide_hand # 手指的 Spine 动画节点
@onready var _idle_guide_msg_panel: Panel = $Root/IdleGuideOverlay/MsgPanel # 引导文字面板
@onready var _idle_guide_msg_rich: RichTextLabel = $Root/IdleGuideOverlay/MsgPanel/MsgRich # 引导文字（富文本）
@onready var _idle_mask_layer: Control = $Root/IdleMaskLayer # 目标格高亮遮罩层

# ---- 运行时状态 ----
var _nav_index: int = 0 # 题库内当前题号（从 1 开始）
var _nav_total: int = 0 # 题库总题数，0 表示不可翻页
var _is_hard_level: bool = false # 当前关是否 Hard
var _revive_count: int = 0 # 本局复活次数
var _restart_count: int = 0 # 本局重开次数
var _coins: int = 40 # 顶部显示的金币数（本文件内不增减）
var _size_cycle: int = 0 # AB 下发的尺寸表分组值，决定 _get_ab_size 查哪张表

var _toast_first_try_hint: bool = false # 开场提示条是否按「首次挑战」文案

var _entry_handlers: Dictionary = {} # 入口模式 → 初始化函数 的派发表

# ---- 本次进入的选题候选；搭盘成功后一次提交，隐藏/复用后旧流程失效 ----
var _selection_plan: Dictionary = {}
var _selection_retry_params: Dictionary = {}
var _entry_error: Dictionary = {}
var _entry_preparing: bool = false # 为 true 时禁止检查点把旧盘面写成新局

# ---- 残局快照落盘（防抖） ----
var _endgame_persist_timer: Timer = null # 残局快照防抖定时器
var _endgame_save_failed: bool = false
var _endgame_retry_count: int = 0
var _endgame_closing: bool = false
const ENDGAME_RETRY_LIMIT: int = 3
const ENDGAME_PERSIST_DEBOUNCE_SEC: float = 0.5 # 防抖窗口：0.5 秒内的多次改动合并成一次写档

var _is_endgame_restore_session: bool = false # 本次 on_show 是否来自残局快照复原

## 自动标叉新手引导浮层的场景
const _AUTO_MARK_TUTORIAL_SCENE: PackedScene = preload(
	"res://products/meowdoku/gameplay/presentation/main/ui/auto_mark_tutorial_overlay.tscn"
)
var _auto_mark_tutorial_overlay: AutoMarkTutorialOverlay = null # 教学浮层实例（同一时间至多一个）

const _AUTO_MARK_TUTORIAL_COL: int = 2 # 演示用的列号（第 3 列）

# ---- 挂机引导（仅第 1 关） ----
var _idle_guide_shown: bool = false # 本局是否已经弹过挂机引导
var _idle_guide_tween: Tween = null # 文字面板的弹出补间
var _idle_mask_tween: Tween = null # 高亮遮罩的淡入补间
var _idle_mask_cell: CellView = null # 高亮用的临时格子实例

var _idle_guide_block_buttons: Array[Button] = [] # 引导显示期间要先拦下的按钮
const IDLE_GUIDE_DELAY_SEC: float = 10.0 # 挂机多少秒后弹引导（秒）

# ---- 步骤触发的挂机引导 ----
var _step_trigger_had_cat: bool = false # 本局是否已由玩家亲手放下过猫

# ---- 入口动画与插屏广告等待 ----
var _entry_anim_pending_state: Variant = null # 等插屏广告时的占位状态，null 表示没有在等
var _entry_anim_ad_error_cb: Callable = Callable() # 广告失败回调（留着用于断开）
var _entry_anim_ad_closed_cb: Callable = Callable() # 广告关闭回调（留着用于断开）
var _entry_anim_schedule_ts: int = 0 # 排定入口动画时的毫秒时间戳

# ---- 生命预警动画状态 ----
var _warn_revision: int = 0 # 重置/再次展示使旧计时回调失效
var _warn_phase: int = 0 # 预警阶段：0 未触发 / 1 展示中（等点击）/ 2 收尾
var _warn_click_allowed: bool = false # 是否已过保护时间、允许点击关闭


# ================= 顶部标题与难度图标 =================
## 设置顶部关卡标题，可选同步标题里的关卡数字
func _set_level_text(text: String, level_num: int = -1) -> void:
	_level_label.text = text
	if _level_display_value != null and level_num >= 0:
		_level_display_value.text = "%d" % level_num


## 切换标题旁的 Hard 火焰图标，并同步标题的四个 offset（有无图标宽度不同）
func _set_hard_fire_visible(show: bool) -> void:
	var icon: TextureRect = _level_label.get_node_or_null("HardFireIcon")
	if icon != null:
		icon.visible = show
	if show:
		_level_label.offset_left = -299.0
		_level_label.offset_top = 15.0
		_level_label.offset_right = 361.0
		_level_label.offset_bottom = 95.0
		if icon != null:
			_align_hard_fire_icon.call_deferred()
	else:
		_level_label.offset_left = -336.0
		_level_label.offset_top = 18.0
		_level_label.offset_right = 324.0
		_level_label.offset_bottom = 98.0


## 把火焰图标对齐到标题文字右侧（延迟调用：要等字体排版出宽度）
func _align_hard_fire_icon() -> void:
	var icon: TextureRect = _level_label.get_node_or_null("HardFireIcon")
	if icon == null or not icon.visible:
		return
	var font: Font = _level_label.get_theme_font("font")
	var font_size: int = _level_label.get_theme_font_size("font_size")
	var text_width: float = (
		font.get_string_size(_level_label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	)
	var label_width: float = _level_label.size.x
	var icon_width: float = 46.0
	var gap: float = 8.0
	icon.offset_right = (label_width - text_width) / 2.0 - gap
	icon.offset_left = icon.offset_right - icon_width


# ================= 生命周期与入口流程 =================
## 场景就绪：填入口派发表、接棋盘输入/变更信号、建残局快照防抖定时器
func _ready() -> void:
	# 入口模式 → 初始化函数
	_entry_handlers = {
		EntryMode.NORMAL: _setup_entry_normal,
		EntryMode.BANK: _setup_entry_bank,
		EntryMode.BANK_SP: _setup_entry_bank_sp,
		EntryMode.DEBUG_CONFIG: _setup_entry_debug_config,
		EntryMode.DEBUG_PREBUILT: _setup_entry_debug_prebuilt,
	}
	_refresh_hearts()
	# 棋盘手势三段：按下 / 划动 / 抬起，父类据此产出并消费 CellAction
	_board_view.cell_drag_start.connect(_on_board_cell_drag_start)
	_board_view.cell_drag_over.connect(_on_board_cell_drag_over)
	_board_view.cell_drag_end.connect(_on_board_cell_drag_end)

	# 格子变更 → 按剩余猫数决定是否弹「自动完成」按钮
	_board_view.cell_state_changed.connect(_on_board_changed_for_auto_complete)

	# 格子变更 → 放猫后自动带出周围的叉
	_board_view.cell_state_changed.connect(_on_cell_changed_for_auto_mark)

	# 格子变更 → LOCK_X 玩法把新画的叉锁住
	_board_view.cell_state_changed.connect(_on_cell_changed_for_lock_x)

	# 格子变更 → 判断挂机引导的步骤触发条件
	_board_view.cell_state_changed.connect(_on_cell_changed_for_step_trigger)
	# 提示浮层的「查看详情」按钮
	_hint_overlay.hint_detail_requested.connect(_on_chain_detail_requested)
	_hint_overlay.layer = 10

	# 生命预警动画播完的回调
	_anim_tips.animation_finished.connect(_on_warn_anim_finished)
	# 构建规则策略浮层（仅非 release 包可见）
	_build_strategy_overlay()

	# 让设置按钮走统一的按钮音效申请
	claim_button_sound($Root/VBoxContainer/Header/SettingsBtn)

	# 挂机引导显示期间要先拦下的按钮
	_idle_guide_block_buttons = [
		$Root/VBoxContainer/Header/GearBtn,
		$Root/VBoxContainer/Header/SettingsBtn,
	]
	# 残局快照防抖定时器：短时间内多次改动只写一次档
	_endgame_persist_timer = Timer.new()
	_endgame_persist_timer.one_shot = true
	_endgame_persist_timer.wait_time = ENDGAME_PERSIST_DEBOUNCE_SEC
	_endgame_persist_timer.timeout.connect(_flush_endgame_snapshot)
	add_child(_endgame_persist_timer)


## 场景里 ClockTimer(0.5 秒) 的 tick 回调：本页不处理，游戏时长由父类 _process 累计
func _on_clock_timer_timeout() -> void:
	pass


## 把 on_show 入参映射成入口模式：题库 / SP 题库 / 两种调试 / 普通
func _resolve_entry_mode(params: Dictionary) -> EntryMode:
	if params.get("bank_mode", false):
		return EntryMode.BANK_SP if params.get("bank_sp", false) else EntryMode.BANK
	if params.has("debug_config"):
		return EntryMode.DEBUG_CONFIG
	if params.has("debug_prebuilt"):
		return EntryMode.DEBUG_PREBUILT
	return EntryMode.NORMAL


## 页面显示总入口：恢复或选题 → 冻结策略 → 复位与搭盘 → 提交 → 入场。
## 两次布局等待和代次校验保留在这里；下面的准备方法都是同步步骤。
func on_show(params: Dictionary = {}) -> void:
	_cancel_pending_entry_animation_wait()
	_terminal_started_ms = 0
	_endgame_closing = false
	_endgame_save_failed = false
	_endgame_retry_count = 0
	_entry_preparing = true
	if _endgame_persist_timer != null:
		_endgame_persist_timer.stop()
	if _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		_board_view.cell_state_changed.disconnect(_persist_endgame_snapshot)
	# 埋点：本页的对局类型固定为普通
	Tracker.set_active_game_type(Tracker.GameType.NORMAL)

	# 开局染色；完成实际关卡的策略冻结后保存自动标叉组。
	ABTestManager.dye_at_game_start()
	# 父类 on_show：规则条、生命条、撤销系统等公共初始化
	super.on_show(params)
	_selection_plan = {}
	_selection_retry_params = {}
	_entry_error = {}
	var entry_generation: int = _business_generation

	# 清掉上一局草稿死锁留下的临时状态
	_clear_draft_deadlock_state()

	# 收起当前还挂着的提示条
	if _active_toast != null:
		_active_toast.hide_toast()

	# 记录本次是否由残局快照复原而来
	_is_endgame_restore_session = params.get("endgame_restore", false)

	ABTestManager.dye_at_game_start_normal()

	# 每日首局降档：AB 开启时评估今天这局是否该用简单题
	if ABTestManager.daily_first_level_difficulty.is_enabled():
		GameState.evaluate_daily_first_easy()
	var consume_daily_first: bool = ABTestManager.daily_first_level_difficulty.is_enabled() or GameState.is_daily_first_easy_available()

	# 参与降档的前提：有关卡号、且不是题库/调试入口
	var _dfe_lv: int = params.get("level_index", 0)
	var _dfe_is_normal_entry: bool = (
		_dfe_lv > 0
		and not params.get("bank_mode", false)
		and not params.has("debug_config")
		and not params.has("debug_prebuilt")
	)
	var prefer_fresh_daily: bool = false
	if _dfe_is_normal_entry and GameState.is_daily_first_easy_available():
		var _dfe_is_hard: bool = (
			LevelData.is_hard_level_group_j(_dfe_lv)
			if ABTestManager.rule_normal_rank.is_group_j()
			else LevelData.is_hard_level(_dfe_lv)
		)
		prefer_fresh_daily = not _dfe_is_hard and not LevelData.is_special_level(_dfe_lv) and not _has_user_progress_in_endgame_snapshot(_dfe_lv)
	# 未操作的旧题可以被每日降档新题替换，但直到新题提交成功都保留旧存档。

	# 有可用残局快照就直接复原并 return，不再走新题流程
	if not prefer_fresh_daily and _try_consume_endgame_snapshot(params):
		return

	# 没有残局时，尝试取该关缓存的题面（重开/退出再进能回到同一题）
	var _entry_lv_for_cached: int = params.get("level_index", 0)
	if (
		not prefer_fresh_daily
		and _entry_lv_for_cached > 0
		and not params.get("bank_mode", false)
		and not params.has("debug_config")
		and not params.has("debug_prebuilt")
	):
		var _cached: Dictionary = GameState.get_retry_puzzle(_entry_lv_for_cached)
		if not _cached.is_empty():
			# 递归 on_show：把缓存题面当题库入口用，埋点状态标成「续玩」
			var _cached_params: Dictionary = _cached.duplicate()
			_cached_params["_tracker_status"] = Tracker.GameStatus.CONTINUE
			on_show(_cached_params)
			return

	# 判断开场提示条是否该用「首次挑战」文案
	var _entry_lv_idx: int = params.get("level_index", 0)
	_toast_first_try_hint = (
		_entry_lv_idx > 0
		and not params.get("bank_mode", false)
		and not params.has("debug_config")
		and not params.has("debug_prebuilt")
		and (prefer_fresh_daily or GameState.get_retry_puzzle(_entry_lv_idx).is_empty())
	)
	# 记下本局的尺寸表分组（_get_ab_size 用它选表）
	_size_cycle = ABTestManager.size_cycle.value()

	# 入场动画前先藏棋盘
	_board_view.visible = false

	# 埋点状态（NEW/RESTART/CONTINUE）决定 game_start 的上报类型
	_stat_status = params.get("_tracker_status", Tracker.GameStatus.NEW)
	# 本局计时起点（毫秒）
	_stat_start_ms = Time.get_ticks_msec()

	# 订阅调试命令总线
	if not CheatBus.command_issued.is_connected(_on_cheat_command):
		CheatBus.command_issued.connect(_on_cheat_command)

	# 按入口模式载入 _level_config 与 _puzzle
	# 页面会复用：本次入口必须重新交付题面，不能借用上次的完整盘面蒙混通过。
	_level_config = {}
	_puzzle = {}
	var _entry_mode: EntryMode = _resolve_entry_mode(params)
	_entry_handlers[_entry_mode].call(params)
	if params.get("level_definition") is Dictionary:
		_level_config["level_definition"] = params.level_definition.duplicate(true)
	var definition: Dictionary = _level_config.get("level_definition", {})
	var level_rules: Dictionary = definition.get("rules", {})
	if level_rules.has("draft_unlock_level"):
		_round_policy["draft_unlock_level"] = int(level_rules.draft_unlock_level)
	if not ContentContext.content_error().is_empty() and not params.get("endgame_restore", false):
		_entry_error = ContentContext.content_error()
	if not _entry_error.is_empty():
		_fail_entry(_entry_error)
		return
	if not _has_entry_puzzle_shape():
		_fail_entry(OperationResult.failure("invalid_entry_puzzle"))
		return
	# 在搭盘和初始快照之前完成本局规则染色，之后恢复始终使用保存的策略。
	if int(_level_config.get("level", 0)) >= 11:
		ABTestManager.dye_at_game_start_normal_11()
	if int(_level_config.get("level", 0)) >= 21:
		ABTestManager.dye_at_game_start_normal_21()
	_freeze_gameplay_policy(params)

	_reset_round_for_entry(params, level_rules)

	# 等一帧，让容器完成排序后再摆棋盘
	await get_tree().process_frame
	if entry_generation != _business_generation:
		return

	if not _setup_entry_board(definition):
		_fail_entry(OperationResult.failure("entry_board_setup_failed"))
		return
	if not _commit_entry_selection(consume_daily_first):
		return
	if entry_generation != _business_generation:
		return

	_entry_preparing = false
	_entry_ready = true
	Tracker.accept_game_start(Tracker.GameType.NORMAL)
	if not _selection_plan.is_empty():
		PuzzleSessionTracker.record(str(_selection_plan.puzzle_id), int(_selection_plan.level))

	# 手感统计：把盘面上已有的猫当作「刚放下的第一只」
	_seed_like_hand_first_cat_from_board()

	# 普通主线才挂「格子变更 → 残局快照」
	_setup_endgame_persist_for_normal_entry(params)
	if _combo_feedback_view == null:
		_combo_feedback_view = get_node_or_null("Root/VBoxContainer/ComboFeedback")
	if _combo_feedback_view != null:
		_combo_feedback_view.reset(_combo_score)
		_combo_feedback_view.set_hard(_is_hard_level)
	_connect_combo_signal()

	# 刷新剩余猫数显示
	_update_remaining()

	# 入场动画期间：藏棋盘、屏蔽输入、锁入口按钮
	_entry_anim_playing = true
	_board_view.visible = false
	_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_lock_entry_buttons()

	# 打断可能还在播的旧入场动画
	var board_intro := $Root as BoardContainerCell_01
	if _anim_player.is_playing():
		_anim_player.stop()

		if (
			board_intro != null
			and board_intro.animation_finished.is_connected(_on_appear_animation_finished)
		):
			board_intro.animation_finished.disconnect(_on_appear_animation_finished)
	# 按关卡号调整规则条/目标格的强调轨道
	_apply_goal_emphasis_tracks(_level_config.get("level", 0))

	# 按关卡号决定规则条是否折叠
	_apply_rule_swipe_collapse(_level_config.get("level", 0))

	# 复位挂机计时
	_reset_idle_hint()

	# 上报对局开始（题目 id、旋转、难度、关卡号）
	(
		Tracker
		. track_game_start(
			_build_qid(),
			Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)),
			_stat_status,
			Tracker.GameType.NORMAL,
			_get_diffi(),
			_level_config.get("level", 0),
			_level_config.get("rank", 0),
			_level_config.get("size", 0),
		)
	)

	# 插屏广告位：新局 / 重开 / 续玩各一个
	var ad_pos: String = Tracker.AdPos.NORMAL_START
	if _stat_status == Tracker.GameStatus.RESTART:
		ad_pos = Tracker.AdPos.NORMAL_RESTART
	elif _stat_status == Tracker.GameStatus.CONTINUE:
		ad_pos = Tracker.AdPos.NORMAL_CONTINUE
	# 评估本次是否该出插屏（评估结果内部缓存）
	var inter_elig: Dictionary = _eval_start_interstitial(params, ad_pos)

	# 先让容器重排一帧，再排定「入场动画还是插屏」
	var board_intro_pre := $Root as BoardContainerCell_01
	if board_intro_pre != null:
		board_intro_pre.set_process(false)
	($Root/VBoxContainer as Container).queue_sort()
	await get_tree().process_frame
	if entry_generation != _business_generation:
		return
	_schedule_entry_animation_after_interstitial(ad_pos, inter_elig)

	# 首局/回访的横幅广告
	_show_banner_if_eligible("game")

	# 第 21 关起才有草稿功能
	if _level_config.get("level", 0) >= 21:
		if _draft_btn != null:
			_draft_btn.visible = _is_draft_unlocked()

	# 残局复原时把快照里的草稿标记补回来
	_try_restore_draft_marks_from_snapshot()


## 复位本局状态和 HUD；恢复生命/复活次数仍取入口参数，尚未铺盘或提交。
func _reset_round_for_entry(params: Dictionary, level_rules: Dictionary) -> void:
	# 策略层按钮只在非 release 包显示
	_strategy_btn.visible = OS.is_debug_build() and not OS.has_feature("rel")

	# 题库题量 > 1 时才显示左右翻页
	var _nav_enabled := _nav_total > 1
	_prev_btn.visible = _nav_enabled
	_next_btn.visible = _nav_enabled
	if _nav_enabled:
		_prev_btn.text = "‹"
		_next_btn.text = "›"

	# 命数复位；restore_lives 表示承接残局剩余的命
	_lives = int(level_rules.get("initial_lives", 3))

	if params.has("restore_lives"):
		_lives = clampi(int(params["restore_lives"]), 0, 3)
		if _lives < 3:
			_ac_had_wrong_cat = true
	# 本局瞬时状态与提示数据复位
	_is_complete = false
	_mistake_count = 0
	_revive_count = params.get("restore_revive_count", 0)
	if _stat_status == Tracker.GameStatus.RESTART:
		_restart_count += 1
	elif params.has("restore_restart_count"):
		_restart_count = int(params["restore_restart_count"])
	else:
		_restart_count = 0
	_wrong_guess_pending = false
	_hint_data = {}
	_idle_guide_shown = false
	_step_trigger_had_cat = false
	_stop_idle_guide()
	_last_placed_count = -1

	# 手感/节奏统计：本局从零开始
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
	# 启动计时器并复位失败/胜利/提示层
	_clock_timer.start()
	UIManager.hide_ui(UiName.FAIL)
	UIManager.hide_ui(UiName.WIN)
	_hint_overlay.visible = false
	if _strategy_overlay != null:
		_strategy_overlay.visible = false

	# 复位生命预警的视觉与锁
	_reset_life_warning()

	# 刷新顶部金币与红心
	_coin_label.text = str(_coins)
	_refresh_hearts()
	# 把道具数量同步成存档里的值
	_sync_tools_from_state()


## 布局完成后搭盘；预置与恢复都先完成，再交给选题事务保存初始状态。
func _setup_entry_board(definition: Dictionary) -> bool:
	if not _has_entry_puzzle_shape():
		return false
	_relayout_board()

	# 取棋盘边长并接管棋盘的鼠标事件
	var sz: int = _level_config["size"]
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP

	_disconnect_combo_signal()

	# 棋盘入场动画期间关掉容器自动触发，避免和入场动画打架
	var _pat_regions: Array = _level_config.get("patternRegions", [])
	var _board_intro_setup := $Root as BoardContainerCell_01
	if _board_intro_setup != null:
		_board_intro_setup.set_auto_trigger(false)
	# 初始化棋盘：尺寸 / 区域图 / 颜色映射 / 图案区域，并复用已有格子
	var setup_ok: bool = _board_view.setup(
		sz, _puzzle["regions"], _compute_color_map_for_current(sz), _pat_regions, true
	)
	if _board_intro_setup != null:
		_board_intro_setup.set_auto_trigger(true)
	if not setup_ok:
		return false
	ContentSceneBindings.apply(_board_view, definition.get("media", {}))

	# 写入预置猫（教程关或固定开局）
	_prefill_hints()

	# 复原存档里的部分盘面（残局或重开）
	_restore_partial_board()

	# 复原局补齐：给盘面上已有的猫补出该有的叉
	if not _level_config.get("restore_state", {}).is_empty():
		complete_auto_mark_for_restore()
	return true


## 每个入口都要交付完整二维题面；避免入口子函数中断后，外层仍提交一个空盘。
func _has_entry_puzzle_shape() -> bool:
	var size_value: Variant = _level_config.get("size")
	if typeof(size_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(size_value)):
		return false
	var size: int = int(size_value)
	if size <= 0 or size_value != size:
		return false
	for key: String in ["regions", "solution"]:
		var rows: Variant = _puzzle.get(key)
		if not rows is Array or rows.size() != size:
			return false
		for row: Variant in rows:
			if not row is Array or row.size() != size:
				return false
	return true


## 所有失败入口共用同一收尾；保留旧存档，页面不再接受棋盘/道具动作。
func _fail_entry(result: Dictionary) -> void:
	_entry_error = result
	_block_round_entry()
	_cancel_pending_entry_animation_wait()
	_unlock_entry_buttons()
	_report_business_failure(result)


## 搭盘成功后提交入场状态；新题同时提交游标、重试缓存与初始检查点。
func _commit_entry_selection(consume_daily_first: bool) -> bool:
	var auto_mark_variant: int = int(_gameplay_policy.get("auto_mark_variant", 0))
	var new_game_id: String = Tracker.create_game_id() if _stat_status == Tracker.GameStatus.NEW else ""
	var selected: Dictionary
	if _selection_plan.is_empty():
		var clear_dirty: bool = _stat_status == Tracker.GameStatus.CONTINUE and not _is_endgame_restore_session
		selected = LevelData.commit_existing_entry(auto_mark_variant, consume_daily_first, clear_dirty, new_game_id)
	else:
		selected = LevelData.commit_selected(_selection_plan, _business_checkpoint(), _selection_retry_params, auto_mark_variant, consume_daily_first, new_game_id)
	if not selected.get("ok", false):
		_fail_entry(selected)
		return false
	return true


## 题库入口：用外部传入的 regionMap/solution 直接组题面
func _setup_entry_bank(params: Dictionary) -> void:
	var bank_sz: int = params["bank_size"]
	var rank: int = params["bank_rank"]
	var idx: int = params["bank_index"]

	# solution 每行只存一个列号，这里还原成二维布尔盘
	var raw_sol: Array = params.get("prebuilt_solution", [])
	var solution_2d: Array = []
	for r: int in range(bank_sz):
		var row: Array = []
		row.resize(bank_sz)
		row.fill(false)
		if r < raw_sol.size():
			row[int(raw_sol[r])] = true
		solution_2d.append(row)
	# retry_level > 0 说明是从某关跳进题库的题
	var retry_lv: int = params.get("retry_level", 0)
	_level_config = {
		"level": retry_lv,
		"size": bank_sz,
		"rank": rank,
		"seed": params.get("level_seed", 0),
		"prefill_count": 0,
		"prefill_positions": params.get("prefill_positions", []),
		"bank_idx": idx,
		"bank_params": params.duplicate(),
		"bank_source": params.get("bank_source", ""),
		"bank_source_main": params.get("bank_source_main", ""),
		"bank_tier": params.get("bank_tier", ""),
		"restore_state": params.get("restore_state", {}),
		"patternRegions":
		params.get("patternRegions", params.get("bank_params", {}).get("patternRegions", [])),
	}

	# 区域号统一转 int（题库 JSON 里可能是浮点）
	var raw_regions: Array = params.get("prebuilt_regions", [])
	var int_regions: Array = []
	for row_arr in raw_regions:
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		int_regions.append(int_row)
	_puzzle = {
		"regions": int_regions,
		"solution": solution_2d,
	}
	# 有关卡号时标题按关卡显示（可能带 Hard）
	if retry_lv > 0:
		_is_hard_level = (
			LevelData.is_hard_level_group_j(retry_lv)
			if ABTestManager.rule_normal_rank.is_group_j()
			else LevelData.is_hard_level(retry_lv)
		)
		if _is_hard_level:
			_set_level_text(tr("GAME_LEVEL_HARD") % retry_lv, retry_lv)
			_set_hard_fire_visible(true)
		else:
			_set_level_text(tr("GAME_LEVEL_TITLE") % retry_lv, retry_lv)
			_set_hard_fire_visible(false)
	else:
		_is_hard_level = false
		_set_level_text("%d×%d  R%d  #%d" % [bank_sz, bank_sz, rank, idx])
		_set_hard_fire_visible(false)
	# 策略层步数 R1~R5
	_strategy_steps = [
		params.get("r1_steps", 0),
		params.get("r2_steps", 0),
		params.get("r3_steps", 0),
		params.get("r4_steps", 0),
		params.get("r5_steps", 0),
	]
	# 翻页信息：题库内第几题 / 共几题
	_nav_index = params.get("bank_index", 1)
	_nav_total = params.get("bank_total", 1)


## SP 题库入口：组题面，并从 BankData 补上该题的图案名与预置点位
func _setup_entry_bank_sp(params: Dictionary) -> void:
	# 页面参数和表内元数据都可能来自旧缓存；先完成校验，再生成二维盘面。
	_puzzle = {}
	_level_config = {}
	for field: String in ["bank_size", "bank_rank", "bank_index"]:
		if typeof(params.get(field)) != TYPE_INT:
			_entry_error = OperationResult.failure("invalid_sp_entry")
			return
	var bank_sz: int = params["bank_size"]
	var rank: int = params["bank_rank"]
	var idx: int = params["bank_index"]
	var sp_all: Array = BankData.get_sp_levels()
	if bank_sz < 4 or bank_sz > 12 or rank < 1 or rank > 5 or idx < 1 or idx > sp_all.size() or not sp_all[idx - 1] is Dictionary:
		_entry_error = OperationResult.failure("invalid_sp_entry")
		return
	var sp_entry: Dictionary = sp_all[idx - 1]
	if not DokuContentValidator.validate("doku/levels/bankdatasp", {"levels": [sp_entry]}):
		_entry_error = OperationResult.failure("invalid_sp_entry")
		return
	if sp_entry.regionMap.size() != bank_sz or sp_entry.regionMap != params.get("prebuilt_regions") or sp_entry.solution != params.get("prebuilt_solution"):
		_entry_error = OperationResult.failure("sp_entry_content_changed")
		return

	var raw_sol: Array = params.get("prebuilt_solution", [])
	var solution_2d: Array = []
	for r: int in range(bank_sz):
		var row: Array = []
		row.resize(bank_sz)
		row.fill(false)
		if r < raw_sol.size():
			row[int(raw_sol[r])] = true
		solution_2d.append(row)
	var retry_lv: int = params.get("retry_level", 0)
	_level_config = {
		"level": retry_lv,
		"size": bank_sz,
		"rank": rank,
		"seed": params.get("level_seed", 0),
		"prefill_count": 0,
		"prefill_positions": params.get("prefill_positions", []),
		"bank_idx": idx,
		"bank_params": params.duplicate(),
		"bank_source": params.get("bank_source", ""),
		"bank_source_main": params.get("bank_source_main", ""),
		"bank_tier": params.get("bank_tier", ""),
		"patternRegions":
		params.get("patternRegions", params.get("bank_params", {}).get("patternRegions", [])),
	}

	var raw_regions: Array = params.get("prebuilt_regions", [])
	var int_regions: Array = []
	for row_arr in raw_regions:
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		int_regions.append(int_row)
	_puzzle = {
		"regions": int_regions,
		"solution": solution_2d,
	}

	# SP 记录里带 pattern 和 prefill，优先用表里的
	var pattern: String = sp_entry.get("pattern", "SP")
	var raw_prefill: Array = sp_entry.get("prefill_positions", [])
	var int_prefill: Array = []
	for pos: Array in raw_prefill:
		int_prefill.append([int(pos[0]), int(pos[1])])
	_level_config["prefill_positions"] = int_prefill
	# 标题带 SP 图案名
	_set_level_text("SP  %d×%d  #%d  [%s]" % [bank_sz, bank_sz, idx, pattern])
	_strategy_steps = [
		params.get("r1_steps", 0),
		params.get("r2_steps", 0),
		params.get("r3_steps", 0),
		params.get("r4_steps", 0),
		params.get("r5_steps", 0),
	]
	_nav_index = params.get("bank_index", 1)
	_nav_total = params.get("bank_total", 1)


## 调试入口：用编辑器配置现场生成题目（仅编辑器/调试包可用）
func _setup_entry_debug_config(params: Dictionary) -> void:
	var dc: Dictionary = params["debug_config"]
	_level_config = dc.duplicate()
	# 补齐生成器需要的字段
	if not _level_config.has("prefill_count"):
		_level_config["prefill_count"] = 0
	if not _level_config.has("prefill_positions"):
		_level_config["prefill_positions"] = []
	# 关卡生成器脚本，release 包里通常不存在
	const _LGE_PATH := "res://products/meowdoku/editor/queendoku/level_generator_editor.gd"
	var lge: GDScript = load(_LGE_PATH) if ResourceLoader.exists(_LGE_PATH) else null
	# 生成器不可用：报错并保持 _puzzle 为空
	if lge == null:
		push_error("[GamePage] debug_config 入口不可用：LevelGeneratorEditor 不在当前包内")
		return
	# 现场生成题面
	_puzzle = lge.generate_puzzle(_level_config)
	_set_level_text(dc.get("label", "Debug"))
	_strategy_steps = [0, 0, 0, 0, 0]
	_nav_index = 0
	_nav_total = 0


## 调试入口：直接用调用方给的 regions/solution 摆一局（不计关卡进度）
func _setup_entry_debug_prebuilt(params: Dictionary) -> void:
	var dp: Dictionary = params["debug_prebuilt"]
	var dp_sz: int = dp["size"]
	_level_config = {
		"level": 0,
		"size": dp_sz,
		"seed": 0,
		"prefill_count": 0,
		"prefill_positions": [],
	}
	_puzzle = {"regions": dp["regions"], "solution": dp["solution"]}
	_set_level_text(dp.get("label", "Debug"))
	_strategy_steps = [0, 0, 0, 0, 0]
	_nav_index = 0
	_nav_total = 0


## 普通入口：从 LevelData 取题面/难度/预置猫，并处理查重与缓存
func _setup_entry_normal(params: Dictionary) -> void:
	var level_index: int = params.get("level_index", 1)
	# 关卡号至少为 1
	level_index = max(1, level_index)
	_selection_plan = LevelData.resolve_level_entry(level_index, _get_ab_size(level_index), randi())
	if not _selection_plan.get("ok", false):
		_entry_error = _selection_plan
		return
	var lv_entry: Dictionary = _selection_plan.entry
	_round_content_provenance = {"table": lv_entry.get("_content_provenance", {}).duplicate(true), "policy": DokuPolicy.provenance(), "definition": lv_entry.get("_definition_provenance", {}).duplicate(true)}

	# 选题计划已按题面推导并校验尺寸；可选字段缺省时不能再回退普通 AB 尺寸。
	var lv_sz: int = int(_selection_plan.size)
	# 难度档 rank：题库记录优先，否则由策略层换算
	var lv_rank: int = lv_entry.get(
		"_bank_rank", LevelData.strategy_to_rank(LevelData.get_strategy(level_index))
	)
	# solution 一维列号 → 二维布尔盘
	var lv_sol_1d: Array = lv_entry.get("solution", [])
	var lv_sol_2d: Array = []
	for r: int in range(lv_sz):
		var row: Array = []
		row.resize(lv_sz)
		row.fill(false)
		if r < lv_sol_1d.size():
			row[int(lv_sol_1d[r])] = true
		lv_sol_2d.append(row)
	# regionMap 统一转 int
	var lv_raw_regions: Array = lv_entry.get("regionMap", [])
	var lv_int_regions: Array = []
	for row_arr: Array in lv_raw_regions:
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		lv_int_regions.append(int_row)

	# 算出这一关的预置猫位置（最多 1 只）
	var lv_prefill_pos: Array = LevelData.compute_prefill(
		level_index, lv_int_regions, lv_sol_1d, lv_sz
	)
	var definition: Dictionary = lv_entry.get("_level_definition", {})
	var prefill: Array = definition.get("prefill", [lv_prefill_pos] if not lv_prefill_pos.is_empty() else []).duplicate(true)
	_level_config = {
		"level": level_index,
		"size": lv_sz,
		"rank": lv_rank,
		"seed": lv_entry.get("seed", 0),
		"prefill_count": prefill.size(),
		"prefill_positions": prefill,
		"level_definition": definition.duplicate(true),
		"bank_source": lv_entry.get("_bank_source", "regular"),
		"bank_source_main": lv_entry.get("_bank_source_main", ""),
		"bank_idx": lv_entry.get("_bank_idx", 0),
		"bank_tier": lv_entry.get("_bank_tier", ""),
		"bank_transform": lv_entry.get("_bank_transform", 0),
		"custom_color_map": lv_entry.get("colorMap", []),
		"patternRegions": lv_entry.get("patternRegions", []),
	}
	# 当前难度与本题实际难度（首局降档时两者会不同）
	var _gs_strategy: int = GameState.get_current_strategy()
	var _gs_rank: int = LevelData.strategy_to_rank(_gs_strategy)
	var _qid: String = (
		"%s_%d" % [lv_entry.get("_bank_source", "regular"), lv_entry.get("_bank_idx", 0)]
	)
	if bool(_selection_plan.next_selection.runtime.get("is_daily_first_easy_level", false)):
		print(
			(
				"[DailyFirstEasy] level=%d 当前难度R%d, 触发首局降档: 实际难度R%d, qid=%s"
				% [level_index, _gs_rank, lv_rank, _qid]
			)
		)
	else:
		print("[DailyFirstEasy] level=%d 当前难度R%d, qid=%s" % [level_index, lv_rank, _qid])

	# 策略层步数 R1~R5
	_strategy_steps[0] = int(lv_entry.get("r1", 0))
	_strategy_steps[1] = int(lv_entry.get("r2", 0))
	_strategy_steps[2] = int(lv_entry.get("r3", 0))
	_strategy_steps[3] = int(lv_entry.get("r4", 0))
	_strategy_steps[4] = int(lv_entry.get("r5", 0))

	# 老数据没有 r1~r5 时，按 r/steps 兜底
	if _strategy_steps.all(func(v: int) -> bool: return v == 0):
		var fallback_r: int = int(lv_entry.get("r", lv_entry.get("maxR", 0)))
		if fallback_r >= 1 and fallback_r <= 5:
			_strategy_steps[fallback_r - 1] = int(lv_entry.get("steps", 1))
	# 题面汇总成 regions + solution
	_puzzle = {"regions": lv_int_regions, "solution": lv_sol_2d}

	# 查重在私有选择候选中完成；仅提交成功后记入玩家与会话历史。
	var previous: Dictionary = _selection_plan.get("previous", {})
	if not previous.is_empty() and int(previous.get("level", -1)) != level_index:
		push_warning("[LevelSelection] duplicate puzzle %s at level %d (previous %s)" % [_selection_plan.puzzle_id, level_index, previous.get("level", -1)])
	# Hard 判定（J 分组用另一套标准）
	_is_hard_level = (
		LevelData.is_hard_level_group_j(level_index)
		if ABTestManager.rule_normal_rank.is_group_j()
		else LevelData.is_hard_level(level_index)
	)
	# 标题区分 Hard / 普通，并切换火焰图标
	if _is_hard_level:
		_set_level_text(tr("GAME_LEVEL_HARD") % level_index, level_index)
		_set_hard_fire_visible(true)
	else:
		_set_level_text(tr("GAME_LEVEL_TITLE") % level_index, level_index)
		_set_hard_fire_visible(false)

	# 已解析题面先留在候选；棋盘建好后与游标、残局一起提交。
	_selection_retry_params = {
		"bank_mode": true,
		"bank_size": lv_sz,
		"bank_rank": lv_rank,
		"bank_index": lv_entry.get("_bank_idx", 0),
		"prebuilt_regions": lv_int_regions,
		"prebuilt_solution": lv_sol_1d,
		"level_seed": lv_entry.get("seed", 0),
		"prefill_positions": prefill.duplicate(true),
		"level_definition": definition.duplicate(true),
		"custom_color_map": lv_entry.get("colorMap", []),
		"retry_level": level_index,
		"bank_source": lv_entry.get("_bank_source", "regular"),
		"bank_source_main": lv_entry.get("_bank_source_main", ""),
		"bank_tier": lv_entry.get("_bank_tier", ""),
		"r1_steps": _strategy_steps[0],
		"r2_steps": _strategy_steps[1],
		"r3_steps": _strategy_steps[2],
		"r4_steps": _strategy_steps[3],
		"r5_steps": _strategy_steps[4],
	}
	# 普通入口没有题库翻页
	_nav_index = level_index
	_nav_total = 0


## 页面隐藏：取消入场等待、停表、落盘残局快照
func on_hide() -> void:
	_endgame_closing = true
	super.on_hide()

	# 清草稿死锁的临时状态
	_clear_draft_deadlock_state()

	# 取消还在等插屏广告的入场动画
	_cancel_pending_entry_animation_wait()

	var board_intro := $Root as BoardContainerCell_01
	if (
		board_intro != null
		and board_intro.animation_finished.is_connected(_on_appear_animation_finished)
	):
		board_intro.animation_finished.disconnect(_on_appear_animation_finished)
	# 停掉入场动画
	if _anim_player.is_playing():
		_anim_player.stop()
	if _active_toast != null:
		_active_toast.hide_toast()
	_stop_idle_guide()
	# 隐藏后不再监听格子变更（避免继续写档）
	if _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		_board_view.cell_state_changed.disconnect(_persist_endgame_snapshot)

	# 有没落盘的改动就先冲一次档
	if _endgame_persist_timer != null and (_endgame_persist_timer.time_left > 0.0 or _endgame_save_failed):
		_endgame_persist_timer.stop()
		_flush_endgame_snapshot()

	_reset_life_warning()

	# 释放自动标叉教学浮层
	_free_auto_mark_tutorial_overlay()


# ================= 残局快照：复原与落盘 =================
## 若存档里有本关的残局快照就原地复原；返回 true 表示已接管本次 on_show
func _try_consume_endgame_snapshot(params: Dictionary) -> bool:
	# 只有普通入口（非题库/调试）才吃快照
	var lv_idx: int = params.get("level_index", 0)
	if (
		lv_idx <= 0
		or params.get("bank_mode", false)
		or params.has("debug_config")
		or params.has("debug_prebuilt")
	):
		return false

	var snapshot: Dictionary = GameState.get_endgame_snapshot()
	if snapshot.is_empty():
		return false
	# 快照结构校验不通过：丢弃
	if not _validate_endgame_snapshot(snapshot):
		push_warning("[Endgame] snapshot validation failed, clearing")
		GameState.clear_endgame_snapshot()
		return false
	# 已存对局沿用自己的保存策略；旧残局没有该字段时才兼容本次启动值。
	var saved_policy: Variant = snapshot.get("gameplay_policy_snapshot", {})
	var save_enabled: bool = bool(_gameplay_policy.get("normal_endgame_save", true))
	if saved_policy is Dictionary and MeowdokuGameplayPolicy.validate(saved_policy) and saved_policy.has("normal_endgame_save"):
		save_enabled = bool(saved_policy.normal_endgame_save)
	if not save_enabled:
		GameState.clear_endgame_snapshot()
		return false
	# 快照的关卡必须与当前关、入口关号都一致
	var snap_level: int = int(snapshot["level"])
	if snap_level != GameState.get_current_level() or snap_level != lv_idx:
		push_warning(
			(
				"[Endgame] snapshot level=%d mismatch (current_level=%d, entry=%d), clearing"
				% [snap_level, GameState.get_current_level(), lv_idx]
			)
		)
		GameState.clear_endgame_snapshot()
		return false
	# 命已耗尽：交给正常失败/重试流程
	var lives_left: int = int(snapshot["lives"])
	var sz: int = int(snapshot["size"])
	if lives_left <= 0:
		print("[Endgame] lives==0, clear snapshot and fall through to retry/fresh")
		GameState.clear_endgame_snapshot()
		return false
	# 复原出来的盘面其实已经通关：直接结算并进入下一关
	var board: Array = _reconstruct_board_for_check(snapshot, sz)
	if QueendokuCore.is_complete(board, sz, snapshot["regionMap"]):
		print("[Endgame] snapshot is_complete, advancing level=%d and re-entering" % snap_level)
		var business_id: String = str(snapshot.get("business_round_id", ""))
		var generation: int = _business_generation
		var settled: Dictionary
		if business_id.is_empty():
			settled = GameState.settle_legacy_completed_main(snap_level)
		else:
			var attempt_id: String = business_id + "/attempt#" + str(snapshot.get("business_attempt_sequence", 0))
			settled = GameState.settle_main_round(attempt_id, snap_level, "win", {"board": board, "lives": lives_left, "history": snapshot.get("step_history", []), "life_plus_used": snapshot.get("life_plus_used", false)})
		if generation != _business_generation or is_queued_for_deletion():
			return true
		if not settled.get("ok", false):
			_report_business_failure(settled)
			return true
		var new_params: Dictionary = params.duplicate()
		new_params["level_index"] = GameState.get_current_level()
		new_params["_tracker_status"] = Tracker.GameStatus.NEW
		on_show(new_params)
		return true
	# 否则按快照重建入口参数，用题库入口复原这一局
	print(
		(
			"[Endgame] restoring in-progress snapshot level=%d lives=%d cats=%d marks=%d errors=%d locked=%d"
			% [
				snap_level,
				lives_left,
				(snapshot.get("placed_cats", []) as Array).size(),
				(snapshot.get("marks", []) as Array).size(),
				(snapshot.get("errors", []) as Array).size(),
				(snapshot.get("locked_marks", []) as Array).size(),
			]
		)
	)
	# 沿用已保存的题面、策略和业务身份，不重新选择或把已操作的局当成干净局。
	on_show(_build_endgame_restore_params(snapshot))
	return true


## 已校验快照 → 现有题库入口参数；这里只做字段映射，不开局、不写档。
func _build_endgame_restore_params(snapshot: Dictionary) -> Dictionary:
	return {
		"bank_mode": true,
		"bank_size": int(snapshot["size"]),
		"bank_rank": int(snapshot["r"]),
		"bank_index": int(snapshot["id"]),
		"bank_total": 1,
		"prebuilt_regions": snapshot["regionMap"],
		"prebuilt_solution": snapshot["solution"],
		"level_seed": snapshot.get("seed", snapshot["id"]),
		"prefill_positions": snapshot.get("prefill_positions", []),
		"bank_source": snapshot.get("bank_source", ""),
		"bank_source_main": snapshot.get("bank_source_main", ""),
		"bank_tier": snapshot.get("bank_tier", ""),
		"retry_level": int(snapshot["level"]),
		"restore_state":
		{
			"placed_cats": snapshot.get("placed_cats", []),
			"marks": snapshot.get("marks", []),
			"errors": snapshot.get("errors", []),
			"locked_marks": snapshot.get("locked_marks", []),
		},
		"restore_lives": int(snapshot["lives"]),
		"content_release": snapshot.get("content_release", "builtin"),
		"business_round_id": snapshot.get("business_round_id", ""),
		"content_provenance": snapshot.get("content_provenance", {}),
		"business_attempt_sequence": snapshot.get("business_attempt_sequence", 0),
		"policy_snapshot": snapshot.policy_snapshot if snapshot.has("policy_snapshot") else DokuPolicy.snapshot(),
		"gameplay_policy_snapshot": snapshot.get("gameplay_policy_snapshot", {}),
		"level_definition": snapshot.get("level_definition", {}),
		"endgame_restore": true,
		"restore_step_history": snapshot.get("step_history", []),
		"restore_highlight_cursor": snapshot.get("highlight_cursor", -1),
		"restore_combo_count": int(snapshot.get("combo_count", 0)),
		"restore_combo_score": int(snapshot.get("combo_score", 0)),
		"restore_restart_count": int(snapshot.get("restart_count", 0)),
		"restore_revive_count": int(snapshot.get("revive_count", 0)),
		"restore_life_plus_used": bool(snapshot.get("life_plus_used", false)),
		"_tracker_status": Tracker.GameStatus.CONTINUE,
	}

## 快照里除了系统预置猫之外，玩家是否真的动过手
func _has_user_progress_in_endgame_snapshot(level: int) -> bool:
	var snapshot: Dictionary = GameState.get_endgame_snapshot()
	if snapshot.is_empty():
		return false
	if int(snapshot.get("level", 0)) != level:
		return false
	if int(snapshot.get("lives", 0)) <= 0:
		return false
	var prefill_count: int = (snapshot.get("prefill_positions", []) as Array).size()
	var user_cats: int = (snapshot.get("placed_cats", []) as Array).size() - prefill_count
	var user_marks: int = (snapshot.get("marks", []) as Array).size()
	var user_errors: int = (snapshot.get("errors", []) as Array).size()

	var user_locked: int = (snapshot.get("locked_marks", []) as Array).size()
	return user_cats > 0 or user_marks > 0 or user_errors > 0 or user_locked > 0


## 校验快照版本号与必备字段/尺寸（防旧档、坏档）
func _validate_endgame_snapshot(snapshot: Dictionary) -> bool:
	if int(snapshot.get("version", 0)) != GameState.ENDGAME_SNAPSHOT_VERSION:
		return false
	var required: Array = [
		"size",
		"r",
		"id",
		"regionMap",
		"solution",
		"level",
		"lives",
		"placed_cats",
		"marks",
		"errors",
	]
	for key in required:
		if not snapshot.has(key):
			return false
	var sz: int = int(snapshot["size"])
	if sz <= 0:
		return false
	var rm = snapshot["regionMap"]
	if not (rm is Array) or (rm as Array).size() != sz:
		return false
	for row in rm as Array:
		if not (row is Array) or (row as Array).size() != sz:
			return false
	var sol = snapshot["solution"]
	if not (sol is Array) or (sol as Array).size() != sz:
		return false
	return true


## 用快照里的猫位还原一张棋盘数组，交给 QueendokuCore 判是否已通关
func _reconstruct_board_for_check(snapshot: Dictionary, sz: int) -> Array:
	var board: Array = []
	for _r: int in range(sz):
		var row: Array = []
		row.resize(sz)
		row.fill(CellState.EMPTY)
		board.append(row)
	for pos in snapshot.get("placed_cats", []):
		var r: int = int(pos[0])
		var c: int = int(pos[1])
		if r >= 0 and r < sz and c >= 0 and c < sz:
			board[r][c] = CellState.CAT
	return board


## 只给普通主线挂上「格子变更 → 残局快照」
func _setup_endgame_persist_for_normal_entry(params: Dictionary) -> void:
	if _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		_board_view.cell_state_changed.disconnect(_persist_endgame_snapshot)

	if not bool(_gameplay_policy.get("normal_endgame_save", true)):
		return
	var lv_idx: int = params.get("level_index", 0)
	var retry_lv: int = params.get("retry_level", 0)
	var is_normal_mainline: bool = (
		(lv_idx > 0 or retry_lv > 0)
		and not params.has("debug_config")
		and not params.has("debug_prebuilt")
	)
	if is_normal_mainline:
		_board_view.cell_state_changed.connect(_persist_endgame_snapshot)


## 排定入场动画：先看插屏出不出，再决定直接播还是挂广告回调等
func _schedule_entry_animation_after_interstitial(ad_position: String, elig: Dictionary) -> void:
	_entry_anim_schedule_ts = Time.get_ticks_msec()

	_cancel_pending_entry_animation_wait()
	# 没有插屏：直接播入场动画
	if not _try_show_start_interstitial(ad_position, elig):
		var board_intro := $Root as BoardContainerCell_01
		if board_intro != null:
			board_intro.play()
		_play_entry_animation()
		return

	# 有插屏：入场动画先停在第一帧等广告结束
	_anim_player.play(_appear_anim_name())
	_anim_player.seek(0.0, true)
	_anim_player.pause()

	_entry_anim_pending_state = {"done": false}
	_entry_anim_ad_error_cb = func(pid: String, msg: String) -> void:
		if pid != "interstitial":
			return
		_fire_entry_anim("ad_error")
	UniKitManager.ad_error_occurred.connect(_entry_anim_ad_error_cb)

	# iOS/编辑器里广告可能不回调关闭，额外监听 ad_closed
	if OS.has_feature("ios") or OS.has_feature("editor"):
		_entry_anim_ad_closed_cb = func(pid: String) -> void:
			if pid != "interstitial":
				return
			_fire_entry_anim("ad_closed")
		UniKitManager.ad_closed.connect(_entry_anim_ad_closed_cb)


## 广告结束（或回到前台）后真正开播入场动画，只生效一次
func _fire_entry_anim(source: String) -> void:
	var generation: int = _business_generation
	if not _is_current_business_generation(generation):
		return
	if _entry_anim_pending_state == null:
		return
	if _entry_anim_pending_state.get("done", false):
		return
	_entry_anim_pending_state["done"] = true
	_cancel_pending_entry_animation_wait()

	var board_intro := $Root as BoardContainerCell_01
	if board_intro != null:
		board_intro.set_process(false)
	($Root/VBoxContainer as Container).queue_sort()
	await get_tree().process_frame
	if not _is_current_business_generation(generation):
		return
	if board_intro != null:
		board_intro.play()
	_play_entry_animation()


## 回到前台：如果还卡在等广告，就当作广告已结束继续播
func _on_application_focus_in() -> void:
	super._on_application_focus_in()
	if _entry_anim_pending_state != null:
		_fire_entry_anim("focus_in")


## 取消等待：断开广告回调并清掉占位状态
func _cancel_pending_entry_animation_wait() -> void:
	if _entry_anim_pending_state != null:
		_entry_anim_pending_state["done"] = true
		_entry_anim_pending_state = null
	if not _entry_anim_ad_error_cb.is_null():
		if UniKitManager.ad_error_occurred.is_connected(_entry_anim_ad_error_cb):
			UniKitManager.ad_error_occurred.disconnect(_entry_anim_ad_error_cb)
		_entry_anim_ad_error_cb = Callable()
	if not _entry_anim_ad_closed_cb.is_null():
		if UniKitManager.ad_closed.is_connected(_entry_anim_ad_closed_cb):
			UniKitManager.ad_closed.disconnect(_entry_anim_ad_closed_cb)
		_entry_anim_ad_closed_cb = Callable()


## 播入场动画：显示棋盘、播音效、挂一次性结束回调
func _play_entry_animation() -> void:
	_board_view.visible = true
	var board_intro := $Root as BoardContainerCell_01
	_anim_player.play(_appear_anim_name())

	SoundManager.play(SoundManager.Kind.BOARD_ENTER)
	if board_intro != null:
		if not board_intro.animation_finished.is_connected(_on_appear_animation_finished):
			board_intro.animation_finished.connect(_on_appear_animation_finished, CONNECT_ONE_SHOT)


## 入场动画播完：解锁入口按钮、补自动标叉和草稿引导
func _on_appear_animation_finished() -> void:
	if not _is_round_entry_ready():
		return
	# 要不要弹草稿引导，决定棋盘是否继续锁着
	var will_show_onboarding: bool = _should_show_draft_onboarding_now()
	super._on_appear_animation_finished()
	if will_show_onboarding and _board_view != null:
		_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 开场提示条
	_try_show_start_toast()

	_unlock_entry_buttons_after_toast(_entry_btn_lock_seq)
	if will_show_onboarding:
		_try_show_draft_onboarding_after_appear()

	# 给预置猫补自动叉
	_auto_mark_prefill_cats()

	# 自动标叉的首次教学
	_maybe_show_auto_mark_tutorial()


# ================= 挂机引导 =================
## 每帧：处理挂机引导的两种触发（纯挂机开小差 / 走了几步没放猫）
func _process(delta: float) -> void:
	super._process(delta)
	if _idle_guide_shown or _level_config.get("level", 0) != 1 or _entry_anim_playing:
		return

	# 模式一：纯挂机计时
	if ABTestManager.idle_guide.is_idle_guide_enabled():
		if not _is_endgame_restore_session and _can_show_idle_hint():
			if _idle_time >= IDLE_GUIDE_DELAY_SEC:
				_show_idle_guide()

	# 模式二：已经操作过若干步但一只猫都没放
	elif ABTestManager.idle_guide.is_step_trigger_enabled():
		if not _step_trigger_had_cat:
			var sz: int = _level_config.get("size", 0)
			var prefill: Array = _level_config.get("prefill_positions", [])
			var prefill_set: Dictionary = {}
			for pos: Variant in prefill:
				prefill_set[Vector2i(int((pos as Array)[0]), int((pos as Array)[1]))] = true
			if sz > 0:
				for r: int in range(sz):
					for c: int in range(sz):
						var st: int = _board_view.get_cell_state(r, c)
						if st == CellState.CAT and not prefill_set.has(Vector2i(r, c)):
							_step_trigger_had_cat = true
							break
					if _step_trigger_had_cat:
						break

		# 双击窗口内不算挂机，避免误判
		var _in_double_tap_window: bool = (
			_gesture_recognizer != null and _gesture_recognizer._last_tap_cell != Vector2i(-1, -1)
		)

		# 弹引导的前置条件
		var step_trigger_can_show: bool = (
			visible
			and not _is_complete
			and not _wrong_guess_pending
			and not _hint_overlay.visible
			and _lives > 0
		)
		if (
			_step_history.size() >= 3
			and not _in_double_tap_window
			and not _step_trigger_had_cat
			and step_trigger_can_show
		):
			_show_idle_guide()


## 只认玩家亲手放下的猫（复原/预置不算），用来关掉步骤触发
func _on_cell_changed_for_step_trigger(r: int, c: int, state: int, source: int) -> void:
	if _step_trigger_had_cat:
		return
	if source == BoardView.ChangeSource.RESTORE or source == BoardView.ChangeSource.PREFILL:
		return
	if state != CellState.CAT:
		return
	var prefill: Array = _level_config.get("prefill_positions", [])
	for pos: Variant in prefill:
		if int((pos as Array)[0]) == r and int((pos as Array)[1]) == c:
			return
	_step_trigger_had_cat = true


## 弹挂机引导：找「独占一格」的区域当目标，把手和文字面板摆过去
func _show_idle_guide() -> void:
	# 同一时间只允许一个提示类浮层
	if not _hint_mutex.try_acquire("idle_guide"):
		_idle_time = 0.0
		return
	_idle_guide_shown = true

	# 目标格：区域内只有一格的那些格子最容易放猫
	var regions: Array = _puzzle.get("regions", [])
	var sz: int = _level_config.get("size", 0)
	if sz == 0 or regions.is_empty():
		return
	var area_count: Dictionary = {}
	for r: int in range(sz):
		for c: int in range(sz):
			var rid: int = regions[r][c]
			area_count[rid] = area_count.get(rid, 0) + 1
	var target: Vector2i = Vector2i(-1, -1)
	for r: int in range(sz):
		if target.x >= 0:
			break
		for c: int in range(sz):
			var rid: int = regions[r][c]
			if area_count.get(rid, 0) == 1:
				target = Vector2i(r, c)
				break
	if target.x < 0:
		return

	# 手指基准：以第 1 行第 3 列为原点，按格宽换算偏移
	const BASE_ROW: int = 0
	const BASE_COL: int = 2
	const BASE_OFFSET_LEFT: float = 111.0
	const BASE_OFFSET_TOP: float = -316.0
	var board_scale: float = _board_view.scale.x
	var slot_screen: float = BoardView.SLOT_PX * board_scale
	_idle_guide_hand.offset_left = BASE_OFFSET_LEFT + (target.y - BASE_COL) * slot_screen
	_idle_guide_hand.offset_top = BASE_OFFSET_TOP + (target.x - BASE_ROW) * slot_screen
	_idle_guide_hand.offset_right = _idle_guide_hand.offset_left + 110.0
	_idle_guide_hand.offset_bottom = _idle_guide_hand.offset_top + 120.0

	# 文字面板：水平居中、贴在目标格上方
	var csf: float = get_tree().root.content_scale_factor
	var cell_local_y: float = (
		(BoardView.BOARD_PADDING + target.x * BoardView.SLOT_PX) * _board_view.scale.y
	)
	var cell_top_px: float = (_board_view.global_position.y + cell_local_y) / csf
	var vp_w_px: float = get_viewport_rect().size.x
	var panel_w: float = minf(930.0 / csf, vp_w_px - 60.0 / csf)
	var panel_h: float = 190.0 / csf
	var panel_gap: float = 30.0 / csf
	_idle_guide_msg_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_idle_guide_msg_panel.size = Vector2(panel_w, panel_h)
	_idle_guide_msg_panel.position = Vector2(
		(vp_w_px - panel_w) / 2.0, cell_top_px - panel_h - panel_gap
	)

	# 文案：把关键字染红并加呼吸效果
	var hl: String = tr("TUTORIAL_STEP1_HIGHLIGHT")
	var breath_seg: String = (
		"[breath amp=0.03 freq=5 group=1 count=%d][color=#d94848]%s[/color][/breath]"
		% [hl.length(), hl]
	)
	_idle_guide_msg_rich.text = (
		"[center]" + tr("TUTORIAL_STEP1_RICH").format({"breath": breath_seg}) + "[/center]"
	)
	_idle_guide_msg_rich.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_idle_guide_msg_rich.offset_left = 30.0 / csf
	_idle_guide_msg_rich.offset_top = 0.0
	_idle_guide_msg_rich.offset_right = -30.0 / csf
	_idle_guide_msg_rich.offset_bottom = 0.0
	_idle_guide_msg_rich.add_theme_font_size_override("normal_font_size", int(48.0 / csf))

	# 高亮遮罩：复制一个格子视图盖在目标格上
	var local_rect: Rect2 = _board_view.cell_to_local_rect(target.x, target.y)
	var board_global: Vector2 = _board_view.global_position
	var cell_top_left: Vector2 = (
		board_global + local_rect.position * board_scale - _idle_mask_layer.global_position
	)
	if _idle_mask_cell != null:
		_idle_mask_cell.queue_free()
		_idle_mask_cell = null
	var src: CellView = _board_view.get_cell_view(target.x, target.y)
	_idle_mask_cell = _CELL_SCENE.instantiate() as CellView
	_idle_mask_cell.pivot_offset_ratio = Vector2.ZERO
	_idle_mask_cell.pivot_offset = Vector2.ZERO
	_idle_mask_cell.position = cell_top_left

	const _HIGHLIGHT_GROW_PX: float = 2.0
	var grow_scale: float = board_scale + _HIGHLIGHT_GROW_PX / BoardView.CELL_PX
	_idle_mask_cell.scale = Vector2(grow_scale, grow_scale)
	_idle_mask_cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_idle_mask_layer.add_child(_idle_mask_cell)

	_idle_mask_cell.set_corner_radius_compensated(grow_scale)
	if src != null:
		_idle_mask_cell.set_region_color(src.get_region_color())
	_idle_mask_cell.play_hint()
	_idle_mask_layer.modulate.a = 0.0
	_idle_mask_layer.visible = true
	# 遮罩淡入
	if _idle_mask_tween != null and _idle_mask_tween.is_valid():
		_idle_mask_tween.kill()
	_idle_mask_tween = create_tween()
	_idle_mask_tween.tween_property(_idle_mask_layer, "modulate:a", 1.0, 0.12)

	# 手指与面板一起弹出
	_idle_guide_overlay.visible = true
	if _idle_guide_spine.has_method("get_animation_state"):
		_idle_guide_spine.get_animation_state().set_animation("click", true, 0)
	_idle_guide_msg_panel.modulate.a = 0.0
	_idle_guide_msg_panel.scale = Vector2(0.6, 0.6)
	if _idle_guide_tween != null and _idle_guide_tween.is_valid():
		_idle_guide_tween.kill()
	_idle_guide_tween = create_tween().set_parallel(true)
	_idle_guide_tween.tween_property(_idle_guide_msg_panel, "modulate:a", 1.0, 0.25)
	(
		_idle_guide_tween
		. tween_property(_idle_guide_msg_panel, "scale", Vector2(1.0, 1.0), 0.25)
		. set_trans(Tween.TRANS_BACK)
	)


## 收掉挂机引导：补间、遮罩、浮层全清，并释放提示锁
func _stop_idle_guide() -> void:
	_hint_mutex.release("idle_guide")
	if _idle_guide_tween != null and _idle_guide_tween.is_valid():
		_idle_guide_tween.kill()
	_idle_guide_tween = null
	if _idle_mask_tween != null and _idle_mask_tween.is_valid():
		_idle_mask_tween.kill()
	_idle_mask_tween = null
	if _idle_mask_cell != null:
		_idle_mask_cell.queue_free()
		_idle_mask_cell = null
	if _idle_mask_layer != null:
		_idle_mask_layer.visible = false
	if _idle_guide_overlay != null:
		_idle_guide_overlay.visible = false


## 复位挂机计时（顺带收掉引导层）
func _reset_idle_hint() -> void:
	super._reset_idle_hint()
	_stop_idle_guide()


## 挂机引导模式下第 1 关不出道具提示
func _play_idle_tool_hint() -> void:
	if (
		ABTestManager.idle_guide.suppresses_tool_hint_at_level1()
		and _level_config.get("level", 0) == 1
	):
		return
	super._play_idle_tool_hint()


# ================= 开场提示条 =================
## 开场提示条：优先 IQ 文案，否则给「首次挑战/继续挑战」百分比
func _try_show_start_toast() -> void:
	if _is_endgame_restore_session:
		return
	var lv: int = _level_config.get("level", 0)
	if not ABTestManager.normal_start_toast.should_show_toast():
		return
	# 第 11 关起才显示
	if lv < 11:
		return
	var is_hard: bool = (
		LevelData.is_hard_level_group_j(lv)
		if ABTestManager.rule_normal_rank.is_group_j()
		else LevelData.is_hard_level(lv)
	)
	# IQ 文案的前提：开关 + 非 Hard + 上局干净 + 首次挑战
	var is_first_try: bool = _toast_first_try_hint
	var last_clean: bool = GameState.was_last_level_clean_win()
	var iq_eligible: bool = (
		ABTestManager.normal_start_toast.should_show_iq_text()
		and not is_hard
		and last_clean
		and is_first_try
	)

	if iq_eligible:
		var iq_idx: int = _resolve_iq_text_idx(lv)
		_active_toast = _normal_toast
		(
			_active_toast
			. show_toast(
				{
					"iq_text_key": "GAME_TOAST_IQ_%d" % iq_idx,
				}
			)
		)
		return

	# 普通文案：按难度和是否首次挑战取一个区间内的百分比
	var pct: float = _resolve_start_toast_pct(lv, is_hard, is_first_try)
	var text_key: String = "GAME_TOAST_FIRST_TRY" if is_first_try else "GAME_TOAST_KEEP_GOING"
	var params := {
		"text_key": text_key,
		"pct_str": I18nFormat.percent(pct, 1),
	}
	_active_toast = _hard_toast if is_hard else _normal_toast
	_active_toast.show_toast(params)


## IQ 文案序号：每关只随机一次并缓存
func _resolve_iq_text_idx(lv: int) -> int:
	var cached: int = GameState.get_start_toast_iq_idx(lv)
	if cached > 0:
		return cached
	var idx: int = randi_range(1, 6)
	GameState.set_start_toast_iq_idx(lv, idx)
	return idx


## 百分比文案同理：每关每种类型只随机一次（存 GameState）
func _resolve_start_toast_pct(lv: int, is_hard: bool, is_first_try: bool) -> float:
	var kind: String = "first_try" if is_first_try else "keep_going"
	var cached: float = GameState.get_start_toast_pct(lv, kind)
	if cached >= 0.0:
		return cached
	var lo: float
	var hi: float
	if is_first_try:
		lo = 40.0 if is_hard else 60.0
		hi = 60.0 if is_hard else 80.0
	else:
		lo = 50.0 if is_hard else 70.0
		hi = 70.0 if is_hard else 90.0
	var pct: float = lo + randf() * (hi - lo)
	GameState.set_start_toast_pct(lv, kind, pct)
	return pct


# ================= 按钮与输入事件 =================
## 返回主页：关计时、标脏，切到 HOME 界面
func _on_gear_btn_pressed() -> void:
	if _is_complete:
		return
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	_clock_timer.stop()

	var lv: int = _level_config.get("level", 0)
	var generation: int = _business_generation
	if lv > 0:
		GameState.mark_current_level_dirty()
	if not _is_current_business_generation(generation):
		return
	UIManager.show_ui(UiName.HOME)
	UIManager.hide_ui(UiName.GAME)


## 设置里点重开：清草稿/连击/横幅，按原题重开一局
func _on_restart_requested() -> void:
	await _run_round_transition(_restart_round)


func _restart_round(context: Dictionary) -> void:
	var settlement_id: String = _business_settlement_id()
	if not _is_current_round_transition(context):
		return
	var settled: bool = not settlement_id.is_empty() and LevelOps.confirm_level_failed_main(_build_game_end_params(Tracker.GameResult.QUIT), int(_level_config.get("level", 0)), settlement_id, _business_runtime())
	if not _is_current_round_transition(context):
		return
	if not settled:
		_report_business_failure({"error": "settlement_failed"})
		return
	_combo_count = 0
	_combo_score = 0
	_hide_auto_complete_btn()
	_exit_draft_mode_and_clear()
	if not _is_current_round_transition(context):
		return

	_destroy_banner()
	if not _is_current_round_transition(context):
		return

	# 停掉待写的残局快照：重开不沿用旧档
	if _endgame_persist_timer != null and _endgame_persist_timer.time_left > 0.0:
		_endgame_persist_timer.stop()

	var lv: int = _level_config.get("level", 0)
	# 本局以「放弃」上报结束，并按失败结算这条关卡
	LevelOps.on_restart_click()
	if not _is_current_round_transition(context):
		return
	if lv > 0:
		# 关卡局：solution 二维转一维列号，用题库入口重开同一题
		var sol_1d: Array = []
		for row: Array in _puzzle.get("solution", []) as Array:
			var found: bool = false
			for c: int in range(row.size()):
				if row[c]:
					sol_1d.append(c)
					found = true
					break
			if not found:
				sol_1d.append(0)
		on_show(
			{
				"bank_mode": true,
				"bank_size": _level_config.get("size", 4),
				"bank_rank": _level_config.get("rank", 1),
				"bank_index": _level_config.get("bank_idx", 0),
				"prebuilt_regions": _puzzle.get("regions", []),
				"prebuilt_solution": sol_1d,
				"level_seed": _level_config.get("seed", 0),
				"prefill_positions": _level_config.get("prefill_positions", []),
				"custom_color_map": _level_config.get("custom_color_map", []),
				"retry_level": lv,
				"bank_source_main": _level_config.get("bank_source_main", ""),
				"bank_tier": _level_config.get("bank_tier", ""),
				"r1_steps": _strategy_steps[0],
				"r2_steps": _strategy_steps[1],
				"r3_steps": _strategy_steps[2],
				"r4_steps": _strategy_steps[3],
				"r5_steps": _strategy_steps[4],
				"_tracker_status": Tracker.GameStatus.RESTART,
			}
		)
	# 非关卡局（题库/调试）直接用原入参重开
	else:
		var bp: Dictionary = _level_config.get("bank_params", {})
		if not bp.is_empty():
			bp["_tracker_status"] = Tracker.GameStatus.RESTART
			on_show(bp)
		else:
			on_show({"_tracker_status": Tracker.GameStatus.RESTART})


## 错标后：只剩最后一条命时短暂锁棋盘，随后弹生命预警
func _on_wrong_guess(r: int, c: int) -> void:
	var generation: int = _business_generation
	super._on_wrong_guess(r, c)
	if not _is_current_business_generation(generation) or not _is_round_entry_ready():
		return

	if _lives == 1:
		var revision: int = _warn_revision
		_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_tree().create_timer(1.2).timeout.connect(
			func() -> void:
				if generation != _business_generation or revision != _warn_revision or not _is_round_entry_ready() or _is_complete or _settlement_pending or is_queued_for_deletion():
					return
				_board_view.mouse_filter = Control.MOUSE_FILTER_STOP
				if _lives == 1:
					_maybe_show_life_warning()
		)


## 生命预警的一次性判定：AB 开关 + 全局只弹一次
func _maybe_show_life_warning() -> void:
	if not _is_current_business_generation(_business_generation) or not _is_round_entry_ready() or _is_complete:
		return
	if not ABTestManager.warn_life.should_show_life_warning():
		return
	if GameState.has_shown_warn_life():
		return

	var generation: int = _business_generation
	GameState.mark_warn_life_shown()
	if _is_current_business_generation(generation) and _is_round_entry_ready() and not _is_complete:
		_show_life_warning()


## 播生命预警：全屏遮罩 + 气泡动画，0.5 秒后才允许点击关闭
func _show_life_warning() -> void:
	if _anim_tips == null:
		return
	if not _hint_mutex.try_acquire("warn_life"):
		return
	_warn_revision += 1
	var revision: int = _warn_revision
	var generation: int = _business_generation
	_warn_phase = 1
	_warn_click_allowed = false

	if _warn_overlay != null:
		_warn_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	_warn_tips.visible = true

	_align_warn_tail_to_heart()
	_anim_tips.play_section_with_markers("GenericPopup", "", "Mark")

	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if generation == _business_generation and revision == _warn_revision and _is_round_entry_ready() and not is_queued_for_deletion() and _warn_phase == 1:
			_warn_click_allowed = true
	)


## 把气泡尾巴对齐到第 1 颗红心的水平中心
func _align_warn_tail_to_heart() -> void:
	if _warn_tail == null or _heart1 == null:
		return

	var heart_center_x: float = _heart1.get_global_rect().get_center().x
	_warn_tail.global_position.x = heart_center_x


## 预警收尾动画播完：解除输入遮挡并释放提示锁
func _on_warn_anim_finished(anim_name: StringName) -> void:
	if anim_name != "GenericPopup" or _warn_phase != 2:
		return
	_warn_phase = 0
	_hint_mutex.release("warn_life")
	if _warn_overlay != null:
		_warn_overlay.mouse_filter = Control.MOUSE_FILTER_PASS


## 全局输入：引导层拦按钮；预警展示期间任意点击进入收尾
func _input(event: InputEvent) -> void:
	if not _is_current_business_generation(_business_generation) or not _is_round_entry_ready():
		return
	# 挂机引导显示时，先吞掉落在被屏蔽按钮上的按下事件
	if _idle_guide_overlay != null and _idle_guide_overlay.visible:
		var is_guide_press: bool = (
			(event is InputEventScreenTouch and event.pressed)
			or (event is InputEventMouseButton and event.pressed)
		)
		if is_guide_press and _is_press_on_idle_blocked_button(event.position):
			get_viewport().set_input_as_handled()
			return
	# 只处理「预警展示中」这一阶段
	if _warn_phase != 1:
		return
	var is_press: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if not is_press:
		return

	# 保护时间内点击无效，防误触
	if not _warn_click_allowed:
		get_viewport().set_input_as_handled()
		return
	_warn_phase = 2
	_anim_tips.play_section_with_markers("GenericPopup", "Mark", "")
	get_viewport().set_input_as_handled()


## 判断点击是否落在引导期间被屏蔽的按钮上
func _is_press_on_idle_blocked_button(screen_pos: Vector2) -> bool:
	for btn in _idle_guide_block_buttons:
		if (
			btn != null
			and btn.visible
			and not btn.disabled
			and btn.get_global_rect().has_point(screen_pos)
		):
			return true
	return false


## 复位生命预警的全部视觉与状态
func _reset_life_warning() -> void:
	_warn_revision += 1
	_warn_click_allowed = false
	_hint_mutex.release("warn_life")
	_warn_phase = 0
	if _anim_tips != null and _anim_tips.is_playing():
		_anim_tips.stop()
	if _warn_overlay != null:
		_warn_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
		_warn_overlay.color.a = 0.0
	if _warn_bubble != null:
		_warn_bubble.modulate.a = 0.0
	if _warn_mask != null:
		_warn_mask.modulate.a = 0.0


# ================= 结算：失败 / 复活 / 通关 =================
## 三条命耗尽：上报失败、写重试缓存、拉起 FAIL 界面
func _on_game_over() -> void:
	if _is_complete or _settlement_pending:
		return
	await _run_round_transition(_finish_game_over)


func _finish_game_over(context: Dictionary) -> void:
	if _is_complete or _settlement_pending:
		return
	if _terminal_started_ms == 0:
		_terminal_started_ms = Time.get_ticks_msec()
	ABTestManager.dye_at_game_fail_end()
	var settlement_id: String = _business_settlement_id()
	if not _is_current_round_transition(context):
		return
	if settlement_id.is_empty():
		_retry_round_transition(context, OperationResult.failure("round_not_ready"), _on_game_over)
		return
	var retry_params: Dictionary = _build_failed_retry_params()
	var end_params: Dictionary = _build_game_end_params(Tracker.GameResult.FAIL)
	var settled: Dictionary = _settle_current_main_or_preview(settlement_id, "fail", retry_params)
	_publish_round_end(settled, end_params)
	if not _is_current_round_transition(context):
		return
	if not settled.get("ok", false):
		_retry_round_transition(context, settled, _on_game_over)
		return
	# 收起自动完成按钮
	_hide_auto_complete_btn()
	_exit_draft_mode_and_clear()
	if not _is_current_round_transition(context):
		return
	_is_complete = true
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_destroy_banner()
	if not _is_current_round_transition(context):
		return
	# 棋盘上所有猫进入哭泣循环，并震动
	_board_view.play_cat_cry_loop_all()
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL4)
	var lv: int = _level_config.get("level", 0)

	# 统计还差几只猫，给失败界面用
	var _sz: int = _level_config.get("size", 4)
	var _placed: int = 0
	# 草稿死锁回滚过的局，以回滚后的盘面统计
	if _draft_deadlock_pending:
		_placed = (_draft_deadlock_real_marks.get("placed_cats", []) as Array).size()
	else:
		for _r in range(_sz):
			for _c in range(_sz):
				if _board_view.get_cell_state(_r, _c) == CellState.CAT:
					_placed += 1
	var remaining_cats: int = _sz - _placed
	# 拉起失败界面，并接上复活的「开始看广告 / 复活成功」回调
	var fail := (
		UIManager
		. show_ui(
			UiName.FAIL,
			{
				"level_config": _level_config,
				"retry_params": retry_params,
				"remaining_cats": remaining_cats,
				"gameplay_policy_snapshot": _gameplay_policy_snapshot(),
				"gameplay_level": _current_level(),
			}
		)
	)
	if not _is_current_round_transition(context):
		return
	if is_instance_valid(fail) and not fail.revive_requested.is_connected(_on_revive_requested):
		fail.revive_requested.connect(_on_revive_requested)
	if is_instance_valid(fail) and not fail.revive_ad_started.is_connected(_on_revive_ad_started):
		fail.revive_ad_started.connect(_on_revive_ad_started)


## 复活广告开始播放：先把猫恢复成待机动作
func _on_revive_ad_started() -> void:
	_board_view.revive_all_cat_to_idle()


## 看广告复活成功：补命、关失败界面、继续本局
func _on_revive_requested(revive_context: Dictionary = {}) -> void:
	if not _is_complete or not _is_round_entry_ready():
		return
	var rollback: Dictionary = {}
	if _draft_deadlock_pending:
		rollback["board"] = _board_from_saved_marks(_draft_deadlock_real_marks)
	_request_revive(revive_context, rollback, _present_revive)


## 事务成功后的产品统计和演出；生命、尝试序号及失败状态已同步。
func _present_revive() -> void:
	var generation: int = _business_generation
	_terminal_started_ms = 0
	_like_hand_state["clock_paused"] = false
	_revive_count += 1
	# 复活次数统计（两套埋点字段）
	GameState.inc_game_total_stat(Tracker.GameType.NORMAL, "revive_count")
	GameState.inc_game_total_stat(Tracker.GameType.NORMAL, "rv_count")
	UIManager.hide_ui(UiName.FAIL)
	if generation != _business_generation or not _is_round_entry_ready() or _is_complete:
		return

	# 加命：按 AB 配置补，最多 3 条
	_refresh_hearts()

	# 一次补满 3 条命时播红心复活特效
	if int(_gameplay_policy_snapshot().get("revive_lives", 3)) >= 3:
		for slot: LifeSlot in [_heart1, _heart2, _heart3]:
			if slot != null:
				slot.play_revive()

	# 草稿死锁的局要回滚到进草稿前的正式标记
	if _draft_deadlock_pending:
		_rollback_draft_deadlock()
		_clear_draft_deadlock_state()

	# 复活命数、尝试序号与恢复盘面已由用例一起保存。

	# 手感统计：把「上一只猫」的时间戳推到当前
	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]

	_board_view.revive_all_cat_to_idle()

	_show_banner_if_eligible("game")

	# 复活后重新评估步骤触发的挂机引导
	if ABTestManager.idle_guide.is_step_trigger_enabled() and _level_config.get("level", 0) == 1:
		if (
			_step_history.size() >= 3
			and not _step_trigger_had_cat
			and not _is_complete
			and not _hint_overlay.visible
		):
			_idle_guide_shown = false
			_show_idle_guide()


## 通关：结算、上报、写关卡进度，再拉起胜利界面
func _on_game_complete() -> void:
	if _is_complete or _settlement_pending:
		return
	await _run_round_transition(_finish_game_complete)


func _finish_game_complete(context: Dictionary) -> void:
	if _is_complete or _settlement_pending:
		return
	if _terminal_started_ms == 0:
		_terminal_started_ms = Time.get_ticks_msec()
	var settlement_id: String = _business_settlement_id()
	if not _is_current_round_transition(context):
		return
	if settlement_id.is_empty():
		_retry_round_transition(context, OperationResult.failure("round_not_ready"), _on_game_complete)
		return
	var end_params: Dictionary = _build_game_end_params(Tracker.GameResult.WIN)
	var settled: Dictionary = _settle_current_main_or_preview(settlement_id, "win")
	_publish_round_end(settled, end_params)
	if not _is_current_round_transition(context):
		return
	if not settled.get("ok", false):
		_retry_round_transition(context, settled, _on_game_complete)
		return
	_hide_auto_complete_btn()

	# 退出草稿模式（是否保留草稿叉由 AB 决定）
	_exit_draft_mode_and_clear(_get_draft_variant() == DraftModeConfig.VALUE_AUTO_WIN_PERSIST)
	if not _is_current_round_transition(context):
		return
	_is_complete = true
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_destroy_banner()
	if not _is_current_round_transition(context):
		return

	# 停掉标记音效并重播猫的出现动画
	SoundManager.stop(SoundManager.Kind.MARK_CAT)
	_board_view.replay_all_cat_appear()
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL5)
	# 收掉提示相关高亮
	_cleanup_hint()
	await get_tree().process_frame
	if not _is_current_round_transition(context):
		return

	# 把本局统计塞进胜利界面要用的配置
	_level_config["restart_count"] = _restart_count
	_level_config["revive_count"] = _revive_count
	_level_config["mistake_count"] = _mistake_count

	_level_config["elapsed_sec"] = _like_hand_state.get("in_game_sec", 0.0)

	# 等胜利提示条播完
	var toast_was_shown: bool = await _play_win_toast_and_wait()
	if not _is_current_round_transition(context):
		return
	_level_config["toast_was_shown"] = toast_was_shown
	# 连胜流程可能自己占掉出场延迟
	var streak_consumed_appear_delay: bool = await _try_run_streak_flow_after_win(
		&"main", toast_was_shown
	)
	if not _is_current_round_transition(context):
		return
	_level_config["skip_appear_delay"] = streak_consumed_appear_delay
	# 拉起胜利界面
	UIManager.show_ui(_win_ui_name(), {"level_config": _level_config, "board_view": _board_view})


## 胜利界面名（普通对局固定 WIN）
func _win_ui_name() -> StringName:
	return UiName.WIN


## 连胜流程：通知连胜管理器，需要展示就等它关掉再返回
func _try_run_streak_flow_after_win(source: StringName, skip_cat_appear: bool = false) -> bool:
	var generation: int = _business_generation
	if not _is_current_business_generation(generation):
		return false
	if not await _check_in_streak_after_win(source):
		return false
	if not StreakManager.has_pending_show():
		return false
	if not skip_cat_appear:
		await get_tree().create_timer(GameWinPage.APPEAR_DELAY).timeout
	if not _is_current_business_generation(generation):
		return false
	var streak_page: StreakPage

	if StreakManager.get_data().current_streak == 1 and not StreakManager.should_skip_lit():
		streak_page = StreakPage.open_lit()
	else:
		streak_page = StreakPage.open_settle()
	while is_instance_valid(streak_page) and streak_page.visible:
		await streak_page.visibility_changed
		if not _is_current_business_generation(generation):
			return false
	return true


# ================= 尺寸表 AB：按关卡段查棋盘边长 =================
# 尺寸曲线已提取为可验证配表；保留 AB 分组和原分段行为。
func _get_ab_size(level_num: int) -> int:
	return DokuPolicy.cycle_size(_size_cycle if _size_cycle in [3, 4, 5, 6, 7, 8] else 2, level_num)


# ================= 规则提示与自动标叉教学 =================
## 踩规则时闪一下对应的规则图标（受 AB 与关卡范围限制）
func _on_rule_violated(rule: int) -> void:
	var cfg := ABTestManager.rule_highlight
	if not cfg.is_highlight_violated():
		return
	if not cfg.is_all_levels():
		if not GameState.is_tutorial_done():
			return
		if GameState.get_current_level() > 5:
			return

	_play_rule_highlight(rule)


## 把预置猫写进棋盘（来源标 PREFILL，不算玩家操作）
func _prefill_hints() -> void:
	var positions: Array = _level_config.get("prefill_positions", [])
	for pos in positions:
		var r: int = pos[0]
		var c: int = pos[1]

		_board_view.set_cell_state(r, c, CellState.CAT, false, true, BoardView.ChangeSource.PREFILL)


## 开局给预置猫补自动叉（残局复原局跳过）
func _auto_mark_prefill_cats() -> void:
	if _is_endgame_restore_session:
		return
	if not MeowdokuGameplayPolicy.auto_mark_prefill(_gameplay_policy, _current_level()):
		return
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return
	for pos in _level_config.get("prefill_positions", []):
		var cat := Vector2i(pos[0], pos[1])
		if _board_view.get_cell_state(cat.x, cat.y) == CellState.CAT:
			_spread_auto_cross(
				cat, 0.0, DokuActionRules.auto_marks(_board_view.get_board(), _puzzle["regions"], cat, true)
			)


## 自动标叉的首次教学：演示点一下列头，再自动收回
func _maybe_show_auto_mark_tutorial() -> void:
	var generation: int = _business_generation
	if _auto_mark_tutorial_overlay != null:
		return
	if not MeowdokuGameplayPolicy.dot_toggle(_gameplay_policy, _current_level()):
		return
	if GameState.is_auto_mark_tutorial_done():
		return
	if _board_view == null or _board_view.get_puzzle_size() <= _AUTO_MARK_TUTORIAL_COL:
		return

	# 等开场提示条消失再弹
	await _wait_start_toast_hidden_if_any()
	if not _is_current_business_generation(generation):
		return

	if _entry_anim_playing:
		return
	if not visible or _is_complete or _wrong_guess_pending:
		return
	if _auto_mark_tutorial_overlay != null or GameState.is_auto_mark_tutorial_done():
		return
	if _board_view == null or not is_instance_valid(_board_view):
		return
	# 实例化教学浮层，并演示把目标列全打上叉
	_auto_mark_tutorial_overlay = _AUTO_MARK_TUTORIAL_SCENE.instantiate() as AutoMarkTutorialOverlay
	add_child(_auto_mark_tutorial_overlay)
	_auto_mark_tutorial_overlay.closed.connect(_on_auto_mark_tutorial_closed)
	_auto_mark_tutorial_overlay.setup(_board_view, _AUTO_MARK_TUTORIAL_COL)

	var _is_marked_before: bool = _board_view.is_axis_auto_mark_marked(1, _AUTO_MARK_TUTORIAL_COL)
	_on_axis_auto_mark_pressed(1, _AUTO_MARK_TUTORIAL_COL, _is_marked_before)


## 教学浮层关闭：记已完成，并把演示用的叉收回去
func _on_auto_mark_tutorial_closed(_hit_btn: bool) -> void:
	var generation: int = _business_generation
	GameState.mark_auto_mark_tutorial_done()
	_free_auto_mark_tutorial_overlay()
	await _wait_axis_idle_for_tutorial_uncross(_AUTO_MARK_TUTORIAL_COL)
	if not _is_current_business_generation(generation):
		return

	if not is_inside_tree() or not visible or not is_instance_valid(_board_view):
		return
	if not _board_view.is_axis_auto_mark_marked(1, _AUTO_MARK_TUTORIAL_COL):
		return
	_on_axis_auto_mark_pressed(1, _AUTO_MARK_TUTORIAL_COL, true)


## 等该列的自动标叉动画跑完再收叉（token 变了就放弃）
func _wait_axis_idle_for_tutorial_uncross(col: int) -> void:
	var token: int = _auto_mark_token
	var key: String = _axis_key(1, col)
	while _axis_busy_set.has(key):
		await get_tree().process_frame
		if token != _auto_mark_token or not is_inside_tree():
			return


## 释放教学浮层实例
func _free_auto_mark_tutorial_overlay() -> void:
	if _auto_mark_tutorial_overlay == null:
		return
	if is_instance_valid(_auto_mark_tutorial_overlay):
		_auto_mark_tutorial_overlay.queue_free()
	_auto_mark_tutorial_overlay = null


# ================= 盘面复原与草稿回滚 =================
## 从 _level_config 的 restore_state 复原棋盘
func _restore_partial_board() -> void:
	_restore_partial_board_from(_level_config.get("restore_state", {}))


## 按类别复原：猫 / 叉 / 错误叉 / 锁定叉
func _restore_partial_board_from(data: Dictionary) -> void:
	if data.is_empty():
		return
	for pos in data.get("placed_cats", []):
		_board_view.set_cell_state(
			int(pos[0]), int(pos[1]), CellState.CAT, false, true, BoardView.ChangeSource.RESTORE
		)
	for pos in data.get("marks", []):
		_board_view.set_cell_state(
			int(pos[0]), int(pos[1]), CellState.MARK, false, true, BoardView.ChangeSource.RESTORE
		)

	# 错误格：先补叉再打错误标记
	for pos in data.get("errors", []):
		var r: int = int(pos[0])
		var c: int = int(pos[1])
		_board_view.set_cell_state(
			r, c, CellState.MARK, false, true, BoardView.ChangeSource.RESTORE
		)
		_board_view.mark_cell_error(r, c, BoardView.ChangeSource.RESTORE)

	# 锁定叉只有开了 LOCK_X 玩法才补锁定状态
	var lock_x_on: bool = int(_gameplay_policy.get("auto_mark_variant", 0)) == GameAutoMarkConfig.VALUE_LOCK_X
	for pos in data.get("locked_marks", []):
		var lr: int = int(pos[0])
		var lc: int = int(pos[1])
		_board_view.set_cell_state(
			lr, lc, CellState.MARK, false, true, BoardView.ChangeSource.RESTORE
		)
		if lock_x_on:
			_board_view.lock_mark(lr, lc, "StatusLock", false, BoardView.ChangeSource.RESTORE)


## 颜色映射：优先用题目自带色表，否则按区域和种子现算
func _compute_color_map_for_current(sz: int) -> Array[int]:
	var raw_cm: Array = _level_config.get(
		"custom_color_map", _level_config.get("bank_params", {}).get("custom_color_map", [])
	)
	var color_map: Array[int]
	if raw_cm.size() == sz:
		color_map = []
		for v in raw_cm:
			color_map.append(int(v))
	else:
		var color_seed: int = _level_config.get(
			"_bank_transform", _level_config.get("bank_params", {}).get("_bank_transform", 0)
		)
		color_map = LevelGenerator.compute_color_map_with_seed(sz, _puzzle["regions"], color_seed)
	return color_map


## 草稿死锁回滚：重摆棋盘，并复原进草稿前的正式标记
func _rollback_draft_deadlock() -> void:
	if _board_view == null:
		return
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return
	var _pat_regions_rb: Array = _level_config.get("patternRegions", [])
	if not _board_view.setup(
		sz, _puzzle["regions"], _compute_color_map_for_current(sz), _pat_regions_rb, true
	):
		_block_round_entry()
		_report_business_failure(OperationResult.failure("board_setup_failed"))
		return
	_prefill_hints()
	_restore_partial_board_from(_draft_deadlock_real_marks)
	_seed_like_hand_first_cat_from_board()
	_board_view.visible = true
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_update_remaining()


# ================= 调试命令与快照组装 =================
## 调试命令分发（由 CheatBus 触发，仅调试包）
func _on_cheat_command(cmd_name: String, args: Array[String]) -> void:
	match cmd_name:
		"win":
			_cmd_win(args)
		"draft_win":
			_cmd_draft_win(args)
		"level":
			_cmd_level(args)
		"lives":
			_cmd_lives(args)
		"lifeplus":
			_cmd_lifeplus(args)
		"dumpjson":
			_cmd_dumpjson(args)


## cheat：播一次加命特效（参数 0 表示不带引导动画）
func _cmd_lifeplus(args: Array[String]) -> void:
	var first: bool = args.is_empty() or args[0] != "0"
	_play_life_plus_fx(first)


## cheat：直接按答案自动完成本局
func _cmd_win(_args: Array[String]) -> void:
	if not _is_round_entry_ready() or _entry_anim_playing or _is_complete or _settlement_pending or _wrong_guess_pending or _auto_completing:
		return
	if _puzzle.is_empty() or not _puzzle.has("solution"):
		return
	_start_auto_complete()


## cheat：把答案写进草稿再一次性提交（验证草稿流程）
func _cmd_draft_win(_args: Array[String]) -> void:
	if _is_complete:
		return
	if not _draft_mode:
		_enter_draft_mode()
	var sz: int = _level_config.get("size", 0)
	var sol: Array = _puzzle.get("solution", [])
	for r: int in range(sz):
		for c: int in range(sz):
			if not bool(sol[r][c]):
				continue
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				continue
			_set_cell_draft(r, c, CellState.DRAFT_CAT)
	_apply_draft_commit()


## cheat：预留的跳关命令，目前不做事
func _cmd_level(_args: Array[String]) -> void:
	pass


## cheat：把题目或残局快照打成 JSON 复制到剪贴板
func _cmd_dumpjson(args: Array[String]) -> void:
	var mode: int = int(args[0]) if args.size() > 0 else 1
	var base: Dictionary
	if mode == 0:
		base = _build_endgame_snapshot()
	else:
		base = _build_puzzle_base()
		base["prefill_positions"] = _level_config.get("prefill_positions", [])
	var json: String = JSON.stringify(base)
	print("[Cheat dumpjson mode=%d]\n%s" % [mode, json])
	DisplayServer.clipboard_set(json)
	Toast.popup("题目 JSON 已复制到剪贴板", self)


## 题目基础信息：尺寸 / 难度 / 题号 / 种子 / 区域图 / 答案列号
func _build_puzzle_base() -> Dictionary:
	var sz: int = _level_config.get("size", 0)
	var region_map: Array = _puzzle.get("regions", [])

	var sol_1d: Array = []
	for row: Array in _puzzle.get("solution", []) as Array:
		var col: int = -1
		for c: int in range(row.size()):
			if row[c]:
				col = c
				break
		sol_1d.append(col)
	return {
		"size": sz,
		"r": _level_config.get("rank", 0),
		"id": _level_config.get("bank_idx", _level_config.get("level", 0)),
		"seed": _level_config.get("seed", 0),
		"regionMap": region_map,
		"solution": sol_1d,
	}


## 组装残局快照：题面 + 盘面各类格子 + 统计与历史
func _build_endgame_snapshot() -> Dictionary:
	var base: Dictionary = _build_puzzle_base()
	var sz: int = int(base["size"])
	var board: Array = _board_view.get_board()
	var placed_cats: Array = []
	var marks: Array = []
	var errors: Array = []
	var locked_marks: Array = []
	# 扫全盘，按格子状态归类
	for r: int in range(sz):
		for c: int in range(sz):
			var st: int = board[r][c]
			match st:
				CellState.CAT:
					placed_cats.append([r, c])
				CellState.MARK:
					marks.append([r, c])
				CellState.ERROR:
					errors.append([r, c])
				CellState.LOCKED_MARK:
					locked_marks.append([r, c])

	# 快照带版本号，读档时按版本校验
	var snapshot: Dictionary = {"version": GameState.ENDGAME_SNAPSHOT_VERSION, "content_release": _round_content_release, "policy_snapshot": _round_policy.duplicate(true), "gameplay_policy_snapshot": _gameplay_policy_snapshot()}
	snapshot.merge(base)
	snapshot["business_round_id"] = _business_session.round_id() if _business_session != null else _business_restored_id
	snapshot["business_attempt_sequence"] = _business_attempt_sequence
	snapshot["content_provenance"] = _round_content_provenance.duplicate(true)
	snapshot["level_definition"] = _level_config.get("level_definition", {}).duplicate(true)

	snapshot["level"] = int(_level_config.get("level", 0))
	snapshot["bank_source"] = _level_config.get("bank_source", "")
	snapshot["bank_source_main"] = _level_config.get("bank_source_main", "")
	snapshot["bank_tier"] = _level_config.get("bank_tier", "")
	snapshot["prefill_positions"] = _level_config.get("prefill_positions", [])
	snapshot["lives"] = _lives
	snapshot["placed_cats"] = placed_cats
	snapshot["marks"] = marks
	snapshot["errors"] = errors

	snapshot["locked_marks"] = locked_marks

	snapshot["draft_marks"] = _serialize_draft_marks()

	snapshot["step_history"] = _step_history.serialize()
	snapshot["highlight_cursor"] = _highlight_cursor
	snapshot["combo_count"] = _combo_count
	snapshot["combo_score"] = _combo_score
	snapshot["restart_count"] = _restart_count
	snapshot["revive_count"] = _revive_count

	snapshot["life_plus_used"] = _life_plus_used_this_game
	return snapshot


# ================= 存档落盘与引导开关 =================
## 自动叉已经预置到棋盘（动画还没播）就先落一次档
func _on_auto_mark_preset_done() -> void:
	if _endgame_persist_timer == null:
		return
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		return
	_endgame_persist_timer.stop()
	_flush_endgame_snapshot()


## 草稿改动落盘：只有 AUTO_WIN_PERSIST 变体需要
func _on_draft_changed_for_persist(immediate: bool = false) -> void:
	if _get_draft_variant() != DraftModeConfig.VALUE_AUTO_WIN_PERSIST:
		return
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		return
	if immediate:
		_endgame_persist_timer.stop()
		_flush_endgame_snapshot()
	else:
		_endgame_persist_timer.start(ENDGAME_PERSIST_DEBOUNCE_SEC)


## 残局复原后，把快照里的草稿标记补回棋盘
func _try_restore_draft_marks_from_snapshot() -> void:
	if _get_draft_variant() != DraftModeConfig.VALUE_AUTO_WIN_PERSIST:
		return

	if not _is_endgame_restore_session:
		return
	var snapshot: Dictionary = GameState.get_endgame_snapshot()
	if snapshot.is_empty():
		return
	var data: Array = snapshot.get("draft_marks", []) as Array
	if data.is_empty():
		return
	_restore_draft_marks_from_snapshot(data)


## 是否该弹草稿功能新手引导（第 21 关起、没弹过才弹）
func _should_show_draft_onboarding_now() -> bool:
	return (
		_level_config.get("level", 0) >= 21
		and _is_draft_unlocked()
		and not GameState.has_shown_draft_onboarding()
	)


## 入场动画后弹草稿引导；任何一步不满足都要把棋盘解锁
func _try_show_draft_onboarding_after_appear() -> void:
	var generation: int = _business_generation
	await _wait_start_toast_hidden_if_any()
	if not _is_current_business_generation(generation):
		return

	if _entry_anim_playing:
		return

	if not visible or _is_complete or _wrong_guess_pending:
		_unlock_board_after_onboarding_skipped()
		return
	if GameState.has_shown_draft_onboarding():
		_unlock_board_after_onboarding_skipped()
		return
	var tooltip: DraftOnboardingTooltip = _show_draft_onboarding()
	if tooltip == null:
		_unlock_board_after_onboarding_skipped()
		return

	tooltip.tree_exited.connect(func() -> void:
		if _is_current_business_generation(generation):
			_unlock_board_after_onboarding_skipped()
	)


## 等到当前开场提示条自己收起
func _wait_start_toast_hidden_if_any() -> void:
	var active: BaseGameToast = _active_toast
	while is_instance_valid(active) and active.visible:
		await active.visibility_changed


## 锁入口按钮（序号 +1，供解锁回调判断时效）
func _lock_entry_buttons() -> void:
	_entry_btn_lock_seq += 1
	for b in _entry_locked_buttons:
		if is_instance_valid(b):
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 解锁入口按钮
func _unlock_entry_buttons() -> void:
	for b in _entry_locked_buttons:
		if is_instance_valid(b):
			b.mouse_filter = Control.MOUSE_FILTER_STOP


## 提示条收起后解锁入口按钮（序号变了就不再解锁）
func _unlock_entry_buttons_after_toast(seq: int) -> void:
	var generation: int = _business_generation
	await _wait_start_toast_hidden_if_any()
	if seq != _entry_btn_lock_seq or not _is_current_business_generation(generation):
		return
	_unlock_entry_buttons()


## 没弹引导时把棋盘输入还回来
func _unlock_board_after_onboarding_skipped() -> void:
	if _board_view != null and is_instance_valid(_board_view):
		_board_view.mouse_filter = Control.MOUSE_FILTER_STOP


## 草稿引导浮层的场景
const _DRAFT_ONBOARDING_TOOLTIP_SCENE: PackedScene = preload(
	"res://products/meowdoku/gameplay/presentation/main/ui/draft_onboarding_tooltip.tscn"
)


## 实例化草稿引导并对齐到草稿按钮
func _show_draft_onboarding() -> DraftOnboardingTooltip:
	if _draft_btn == null:
		return null
	var tooltip: DraftOnboardingTooltip = (
		_DRAFT_ONBOARDING_TOOLTIP_SCENE.instantiate() as DraftOnboardingTooltip
	)

	get_tree().root.add_child(tooltip)

	var btn_xform: Transform2D = _draft_btn.get_global_transform()
	var visual_tl: Vector2 = btn_xform * Vector2.ZERO
	var visual_br: Vector2 = btn_xform * _draft_btn.size
	var visual_rect: Rect2 = Rect2(visual_tl, visual_br - visual_tl)
	tooltip.show_at(visual_rect)

	tooltip.hit_draft_btn.connect(_on_draft_btn_pressed, CONNECT_ONE_SHOT)
	return tooltip


## 格子变更 → 残局快照：关键状态立刻写，其余延迟 0.5 秒写
func _persist_endgame_snapshot(_r: int, _c: int, state: int, _source: int = 0) -> void:
	_endgame_retry_count = 0
	if state == CellState.CAT or state == CellState.ERROR:
		_endgame_persist_timer.stop()

		_flush_endgame_for_generation.call_deferred(_business_generation)
	else:
		_endgame_persist_timer.start(ENDGAME_PERSIST_DEBOUNCE_SEC)


func _flush_endgame_for_generation(generation: int) -> void:
	if generation == _business_generation:
		_flush_endgame_snapshot()


## 真正写档：GameState.set_endgame_snapshot
func _flush_endgame_snapshot() -> void:
	if _entry_preparing or not _entry_error.is_empty():
		return
	if _is_complete or int(_level_config.get("level", 0)) < GameState.get_current_level():
		return
	if GameState.set_endgame_snapshot(_build_endgame_snapshot()):
		_endgame_save_failed = false
		_endgame_retry_count = 0
		return
	if not _endgame_save_failed:
		_report_business_failure({"error": "checkpoint_save_failed"})
	_endgame_save_failed = true
	# 保留活棋盘，有限重试时重新捕获最新状态；不把旧快照排队覆盖后续动作。
	if not _endgame_closing and _endgame_retry_count < ENDGAME_RETRY_LIMIT:
		_endgame_retry_count += 1
		_endgame_persist_timer.start(float(_endgame_retry_count))


# ================= 题库翻页 =================
## 上一题（先退草稿再翻页）
func _on_prev_btn_pressed() -> void:
	_exit_draft_mode_and_clear()
	_nav_to(_nav_index - 1)


## 下一题
func _on_next_btn_pressed() -> void:
	_exit_draft_mode_and_clear()
	_nav_to(_nav_index + 1)


## 题库翻页：按题库来源取目标题，重新走 GAME 入口
func _nav_to(new_index: int) -> void:
	# 不可翻页
	if _nav_total <= 0:
		return
	# 环形取模，题号从 1 开始
	var idx: int = ((new_index - 1) % _nav_total + _nav_total) % _nav_total + 1

	var bp: Dictionary = _level_config.get("bank_params", {})
	if bp.is_empty():
		UIManager.show_ui(UiName.GAME, {"level_index": idx})
		return

	# 判断题库属于哪条线，取对应的题表
	var is_lk: bool = bp.get("bank_lk", false)
	var is_lk_style: bool = bp.get("bank_lk_style", false)
	var is_sp: bool = bp.get("bank_sp", false)
	var sz: int = bp.get("bank_size", 7)
	var rank: int = bp.get("bank_rank", 1)

	var is_tier_h: bool = bp.get("bank_tier_h", false)
	var bank_tier: String = bp.get("bank_tier", "")
	var is_gc: bool = bp.get("bank_gc", false)
	var levels: Array
	if is_sp:
		levels = BankData.get_sp_levels()
	elif is_lk:
		var is_lk_modified: bool = bp.get("bank_lk_modified", false)
		levels = BankData.get_lk_modified_levels() if is_lk_modified else BankData.get_lk_levels()
	elif is_gc:
		if bank_tier == "H" or bank_tier == "N":
			levels = BankData.get_gc_levels_by_tier(sz, rank, bank_tier)
		else:
			levels = BankData.get_gc_levels(sz, rank)
	elif is_lk_style:
		if bank_tier == "H" or bank_tier == "N":
			levels = BankData.get_lk_style_levels_by_tier(sz, rank, bank_tier)
		else:
			levels = BankData.get_lk_style_levels(sz, rank)
	else:
		if bank_tier == "H" or bank_tier == "N":
			levels = BankData.get_levels_by_tier(sz, rank, bank_tier)
		else:
			levels = BankData.get_levels(sz, rank)

	# 目标题不存在就不跳
	if levels.is_empty() or idx - 1 >= levels.size():
		return

	# 复制入口参数，替换题面与种子
	var entry: Dictionary = levels[idx - 1]
	var new_params: Dictionary = bp.duplicate()
	new_params["bank_index"] = idx
	new_params["prebuilt_regions"] = entry.get("regionMap", [])
	new_params["prebuilt_solution"] = entry.get("solution", [])

	# 混合尺寸题库允许省略 size，不能沿用上一题尺寸或固定默认值。
	if is_sp:
		new_params["bank_size"] = entry.regionMap.size()
		new_params["bank_rank"] = int(entry.get("r", 1))
		new_params["level_seed"] = entry.get("id", 0)
		new_params["custom_color_map"] = entry.get("colorMap", [])
		new_params["r1_steps"] = entry.get("r1", 0)
		new_params["r2_steps"] = entry.get("r2", 0)
		new_params["r3_steps"] = entry.get("r3", 0)
		new_params["r4_steps"] = entry.get("r4", 0)
		new_params["r5_steps"] = entry.get("r5", 0)
	elif is_lk:
		new_params["bank_size"] = entry.regionMap.size()
		new_params["bank_rank"] = entry.get("maxR", 1)
		new_params["level_seed"] = entry.get("id", 0)
	else:
		new_params["level_seed"] = entry.get("seed", 0)
		new_params["r1_steps"] = entry.get("r1", 0)
		new_params["r2_steps"] = entry.get("r2", 0)
		new_params["r3_steps"] = entry.get("r3", 0)
		new_params["r4_steps"] = entry.get("r4", 0)
		new_params["r5_steps"] = entry.get("r5", 0)

	UIManager.show_ui(UiName.GAME, new_params)


# ================= 埋点与上报 =================
## 埋点用的页面名
func get_scr_name() -> String:
	return Tracker.Scr.NORMAL_GAME


## 组装对局结束上报参数（时长、道具、步数、失误等一揽子统计）
func _build_game_end_params(result: String) -> Dictionary:
	var end_ms: int = _terminal_started_ms if _terminal_started_ms > 0 else Time.get_ticks_msec()
	var time_sec: int = (end_ms - _stat_start_ms) / 1000 # 组装参数只读；成功发布时才累计。

	var sz: int = _level_config.get("size", 0)
	var cat_n: int = _board_view.count_cat_cells()
	return {
		"qid": _build_qid(),
		"qrotate": Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)),
		"result": result,
		"game_type": Tracker.GameType.NORMAL,
		"game_id": GameState.get_persisted_game_id(Tracker.GameType.NORMAL),
		"diffi": _get_diffi(),
		"level": _level_config.get("level", 0),
		"strategy_layer": _level_config.get("rank", 0),
		"scale": sz,
		"hint": GameState.get_tool_count("hint"),
		"locate": GameState.get_tool_count("locate"),
		"hint_used": Tracker.get_stat("hint_used"),
		"locate_used": Tracker.get_stat("locate_used"),
		"hint_used_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "hint_used_total"),
		"locate_used_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "locate_used_total"),
		"hint_apply_used": Tracker.get_stat("hint_apply_used"),
		"hint_stop_used": Tracker.get_stat("hint_stop_used"),
		"hint_detail_used": Tracker.get_stat("hint_detail_used"),
		"clear_used": Tracker.get_stat("clear_used"),
		"clear_used_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "clear_used_total"),
		"draft_used_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_used_total"),
		"draft_time_total":
		int(GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_time_total_ms") / 1000.0),
		"draft_error_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_error_total"),
		"draft_correct_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_correct_total"),
		"coord_count": Tracker.get_stat("coord_count"),
		"step_used": Tracker.get_stat("step_used"),
		"step_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "step_total"),
		"gamedie_count": Tracker.get_stat("gamedie_count"),
		"restart_count": Tracker.get_stat("restart_count"),
		"time": time_sec,
		"time_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "time_total"),
		"cross_count": _board_view.count_mark_cells(),
		"invalid_sign": _board_view.count_error_cells(),
		"invalid_sign_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "invalid_sign_total"),
		"fail_sign": sz - cat_n,
		"erase_count": Tracker.get_stat("erase_count"),
		"revive_count": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "revive_count"),
		"rv_count": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "rv_count"),
		"hp_count": _lives,
	}


## 保持原残局 AB 的开关；用例端口将可恢复的主线快照与消费一起提交。
func _business_checkpoint() -> Dictionary:
	if not bool(_gameplay_policy.get("normal_endgame_save", true)) or int(_level_config.get("level", 0)) <= 0:
		return {}
	return _build_endgame_snapshot()


func _settle_current_main_or_preview(attempt_id: String, outcome: String, retry_params: Dictionary = {}) -> Dictionary:
	var level: int = int(_level_config.get("level", 0))
	return GameState.settle_main_round(attempt_id, level, outcome, _business_runtime(), retry_params) if level > 0 else GameState.settle_preview_round(attempt_id, outcome, _business_runtime())


func _board_from_saved_marks(saved: Dictionary) -> Array:
	var size: int = int(_level_config.get("size", 0))
	var board: Array = []
	for row in size:
		var line: Array = []
		line.resize(size)
		line.fill(CellState.EMPTY)
		board.append(line)
	var fields: Dictionary = {"placed_cats": CellState.CAT, "marks": CellState.MARK, "errors": CellState.ERROR, "locked_marks": CellState.LOCKED_MARK}
	for field: String in fields:
		for position: Array in saved.get(field, []):
			board[int(position[0])][int(position[1])] = fields[field]
	return board


func _build_failed_retry_params() -> Dictionary:
	var lv: int = int(_level_config.get("level", 0))
	# 组装重试用参（同一题重来）
	var retry_params: Dictionary = {}
	if lv > 0:
		var sol_1d: Array = []
		var sol_2d: Array = _puzzle.get("solution", [])
		for row: Array in sol_2d:
			var found: bool = false
			for c: int in range(row.size()):
				if row[c]:
					sol_1d.append(c)
					found = true
					break
			if not found:
				sol_1d.append(0)
		retry_params = {
			"bank_mode": true,
			"bank_size": _level_config.get("size", 4),
			"bank_rank": _level_config.get("rank", 1),
			"bank_index": _level_config.get("bank_idx", 0),
			"prebuilt_regions": _puzzle.get("regions", []),
			"prebuilt_solution": sol_1d,
			"level_seed": _level_config.get("seed", 0),
			"prefill_positions": _level_config.get("prefill_positions", []),
			"level_definition": _level_config.get("level_definition", {}).duplicate(true),
			"gameplay_policy_snapshot": _gameplay_policy_snapshot(),
			"content_release": _round_content_release,
			"policy_snapshot": _round_policy.duplicate(true),
			"content_provenance": _round_content_provenance.duplicate(true),
			"custom_color_map": _level_config.get("custom_color_map", []),
			"retry_level": lv,
			"bank_source_main": _level_config.get("bank_source_main", ""),
			"bank_tier": _level_config.get("bank_tier", ""),
			"r1_steps": _strategy_steps[0],
			"r2_steps": _strategy_steps[1],
			"r3_steps": _strategy_steps[2],
			"r4_steps": _strategy_steps[3],
			"r5_steps": _strategy_steps[4],
		}

	else:
		var bp: Dictionary = _level_config.get("bank_params", {})
		if not bp.is_empty():
			retry_params = bp.duplicate()
		else:
			retry_params = {"level_index": 1}

	return retry_params
