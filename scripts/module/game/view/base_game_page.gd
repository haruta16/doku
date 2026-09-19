# 对局页面基类：普通关 GamePage 与每日关 DailyGamePage 的共同父类，掌管一整局的主流程
# 棋盘真源是子节点 BoardView（_board_view），本类只做「读棋盘 → 改棋盘 → 刷新周边 UI」的调度
class_name BaseGamePage
# 沿用窗口基类：on_show / on_hide 由 UIManager 在切页时调用
extends UIFrameWindow

# 不少私有成员只给子类用，这里关掉「未使用私有变量」告警
@warning_ignore_start("unused_private_class_variable")

# ---- 预制体：格子、点赞手势、三种规则条 ----
const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn") # 棋盘单格（提示高亮也会临时实例化它）
# 点赞手势（比心 / 鼓掌 / 吹号…）
const _LIKE_HAND_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/game_like_hand.tscn"
)
# 规则条 V0：三条纯文字
const _RULE_INFO_BAR_V0_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/rule_info_bar_v0.tscn"
)
# 规则条 V4：可折叠
const _RULE_INFO_BAR_V4_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/rule_info_bar_v4.tscn"
)
# 规则条 V7：单张滑动卡
const _RULE_INFO_BAR_V7_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/rule_info_bar_v7.tscn"
)

# ---- 规则条「图标 + 文字」的排版度量（像素 / 字号 / 行距） ----
const _RULE_LABEL_MEDIUM_FONT: FontVariation = preload("res://assets/fonts/Roboto-medium.tres") # 规则文字用的中号字体

const _RULE_ICON_TEXT_FONT_SIZE: int = 30 # 字号（像素）

const _RULE_ICON_TEXT_LINE_SPACING_1: int = -4 # 第 1 条的行距
const _RULE_ICON_TEXT_LINE_SPACING_REST: int = -8 # 第 2、3 条的行距

const _RULE_ICON_TEXT_BOX_TOP: float = 34.0 # 文字框上偏移（像素）
const _RULE_ICON_TEXT_BOX_BOTTOM: float = 166.0 # 文字框下偏移（像素）

const _RULE_ICON_TEXT_LETTER_SPACING_1: int = -1 # 第 1 条字间距
const _RULE_ICON_TEXT_LETTER_SPACING_2: int = 0 # 第 2 条字间距
const _RULE_ICON_TEXT_LETTER_SPACING_3: int = 0 # 第 3 条字间距

var _rule_icon_text_fonts: Dictionary = {} # 字间距 → 字体副本缓存，避免每次排版都 duplicate()

# 开场动画里「目标强调」要开关的动画轨道路径
const _GOAL_RULE_HIGHLIGHT_PATHS: PackedStringArray = [
	"Root/VBoxContainer/RuleBar/Control/Glow:self_modulate",
	"Root/VBoxContainer/RuleBar/Control:scale:x",
	"Root/VBoxContainer/RuleBar/Control:scale:y",
]
# 同上，对应猫数量目标那一行
const _GOAL_CAT_HIGHLIGHT_PATHS: PackedStringArray = [
	"Root/VBoxContainer/CatHeartRow/Target/Glow:self_modulate",
	"Root/VBoxContainer/CatHeartRow/Target:scale:x",
	"Root/VBoxContainer/CatHeartRow/Target:scale:y",
]

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _anim_player: AnimationPlayer = $AnimationPlayer # 页面开场动画
@onready var _anim_correct: AnimationPlayer = $AnimCorrectPrompt # 数量变化时的正确提示动画

@onready var _ac_anim: AnimationPlayer = get_node_or_null("AnimationAutoComplete") as AnimationPlayer # 自动完成按钮的显隐动画（节点可能不存在）
@onready var _ac_btn: Button = get_node_or_null("Root/AutoCompleteBtn") as Button # 自动完成按钮

@onready var _draft_anim: AnimationPlayer = get_node_or_null("AnimDraftBtn") as AnimationPlayer # 草稿按钮动画

@onready var _apply_anim: AnimationPlayer = get_node_or_null("AnimApplyBtn") as AnimationPlayer # 草稿「应用」按钮动画

@onready var _fireworks_anim: AnimationPlayer = get_node_or_null("AnimFlreworks") as AnimationPlayer # 通关烟花动画（资源名拼写就是 Flreworks）
@onready var _board_container: Control = $Root/VBoxContainer/BoardContainer # 棋盘容器，尺寸变化时触发重排
@onready var _board_view: BoardView = $Root/VBoxContainer/BoardContainer/BoardView # 棋盘视图：全盘状态的唯一真源
@onready var _clock_timer: Timer = $Root/ClockTimer # 对局计时器，由子类启动
@onready var _hint_overlay: HintOverlay = $Root/HintOverlay # 提示浮层（说明文字 + 应用/关闭按钮）
@onready var _rules_bg: Panel = $Root/VBoxContainer/RuleBar/Control/RulesBg # 规则条背景板

@onready var _rule_label3: Label = $Root/VBoxContainer/RuleBar/Control/RuleLabel3 # 第 3 条规则文字

# 第 1 条规则文字（规则条会被整块替换，故用 get_node_or_null）
@onready var _rule_label1: Label = get_node_or_null("Root/VBoxContainer/RuleBar/Control/RuleLabel1")
@onready var _rule_label2: Label = get_node_or_null("Root/VBoxContainer/RuleBar/Control/RuleLabel2") # 第 2 条规则文字
# 三条规则的小示意图（换规则条后要重新抓引用）
@onready var _rule_diagram1: TextureRect = get_node_or_null(
	"Root/VBoxContainer/RuleBar/Control/RuleDiagram1"
)
@onready var _rule_diagram2: TextureRect = get_node_or_null(
	"Root/VBoxContainer/RuleBar/Control/RuleDiagram2"
)
@onready var _rule_diagram3: TextureRect = get_node_or_null(
	"Root/VBoxContainer/RuleBar/Control/RuleDiagram3"
)
# ---- 底部道具按钮 ----
@onready var _tool_hint_btn: Control = $Root/VBoxContainer/BottomTools/HintBtn # 提示道具
@onready var _tool_locate_btn: Control = $Root/VBoxContainer/BottomTools/RevealBtn # 定位道具（节点名是 RevealBtn）
@onready var _tool_clear_btn: Control = $Root/VBoxContainer/FunctionArea/ClearBtn # 清除按钮
# 撤销道具（关闭撤销 AB 时节点不存在）
@onready
var _tool_undo_btn: Control = get_node_or_null("Root/VBoxContainer/BottomTools/UndoBtn") as Control # 撤销道具按钮
@onready var _remaining_label: RichTextLabel = $Root/VBoxContainer/CatHeartRow/Target/CatCountLabel # 剩余猫数量文字
# ---- 剩余数量进度条（AB: progress_emphasis 用进度条替掉数字） ----
@onready var _progress_slot: Control = (
	get_node_or_null("Root/VBoxContainer/CatHeartRow/ProgressSlot") as Control
)
# 轨道底
@onready var _progress_track_bg: Panel = (
	get_node_or_null("Root/VBoxContainer/CatHeartRow/ProgressSlot/TrackBg") as Panel
)
# 轨道填充
@onready var _progress_track_fill: Panel = (
	get_node_or_null("Root/VBoxContainer/CatHeartRow/ProgressSlot/TrackFill") as Panel
)
# 进度数字
@onready var _progress_count_label: RichTextLabel = (
	get_node_or_null("Root/VBoxContainer/CatHeartRow/ProgressSlot/CountLabel") as RichTextLabel
)
# 数字模式下的目标节点（进度条模式下隐藏）
@onready
var _progress_target: Control = get_node_or_null("Root/VBoxContainer/CatHeartRow/Target") as Control # 猫数量目标节点

# ---- 生命槽：3 条命，按 AB 换成心 / 鱼 / 闪电 ----
var _heart1: Control = null # 第 1 条命
var _heart2: Control = null # 第 2 条命
var _heart3: Control = null # 第 3 条命

# 三种生命图标各自的槽位预制体
const HEART_SLOT_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/heart_slot.tscn"
)
const FISH_SLOT_SCENE: PackedScene = preload("res://scripts/module/game/ui/compont/fish_slot.tscn") # 鱼
# 闪电
const LIGHTNING_SLOT_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/lightning_slot.tscn"
)

# ---- 「生命 +1」飘字图标，Inspector 里拖入 ----
@export var life_plus_icon_heart: Texture2D # 心
@export var life_plus_icon_fish: Texture2D # 鱼
@export var life_plus_icon_lightning: Texture2D # 闪电
# ---- 底部广告位 ----
@onready var _ad_banner: Control = $Root/VBoxContainer/AdBanner # banner 广告占位
@onready var _ad_down_adapt: Control = $Root/VBoxContainer/AdDownAdaptHolder # 底部安全区占位（算 banner 高度用）

# 策略分析按钮（只有非 release 包可见）
@onready
var _strategy_btn: Button = get_node_or_null("Root/VBoxContainer/Header/StrategyBtn") as Button # 策略分析入口

# ---- 草稿按钮（铅笔） ----
@onready
var _draft_btn: Button = get_node_or_null("Root/VBoxContainer/FunctionArea/DraftBtn") as Button # 草稿模式开关
# 草稿按钮底图（进入草稿后换色）
@onready var _draft_btn_bg: TextureRect = (
	get_node_or_null("Root/VBoxContainer/FunctionArea/DraftBtn/Bg") as TextureRect
)
# 草稿按钮上的铅笔图标
@onready var _draft_btn_icon: TextureRect = (
	get_node_or_null("Root/VBoxContainer/FunctionArea/DraftBtn/IconRect") as TextureRect
)

# 草稿按钮上的角标文字
@onready var _draft_btn_label: Label = (
	get_node_or_null("Root/VBoxContainer/FunctionArea/DraftBtn/QLabel") as Label
)

const _PENCIL_TEX_DEFAULT: Texture2D = preload("res://assets/sprites/game/icon_pencil.png") # 铅笔：未选中
# 铅笔：草稿模式中
const _PENCIL_TEX_SELECTED: Texture2D = preload(
	"res://assets/sprites/game/icon_pencil_selected.png"
)

# 草稿「应用」按钮（仅部分草稿变体存在）
@onready
var _apply_btn: Button = get_node_or_null("Root/VBoxContainer/FunctionArea/ApplyBtn") as Button # 把草稿落成正式标记

# 规则条上三块高亮（违规时闪哪条规则）
@onready var _rule_highlights: Array[TextureRect] = [
	$Root/VBoxContainer/RuleBar/Control/RuleHighlight1,
	$Root/VBoxContainer/RuleBar/Control/RuleHighlight2,
	$Root/VBoxContainer/RuleBar/Control/RuleHighlight3,
]

# ---- 规则违规高亮：违规时对应那条规则的色块闪两下 ----
const RULE_HL_PERIOD: float = 0.6 # 一次呼吸的时长（秒）
const RULE_HL_FLOOR: float = 0.4 # 闪烁时最低不透明度

# ---- 本局核心状态 ----
var _level_config: Dictionary = {} # 关卡配置（子类在 on_show 里填：size / level / bank_* 等）
var _puzzle: Dictionary = {} # 题面真源：{"regions": 区域图, "solution": 答案}，子类填
var _lives: int = 3 # 剩余生命（0~3）
var _mistake_count: int = 0 # 本局错误落子次数

var _life_plus_used_this_game: bool = false # 「生命 +1」每局只送一次
var _is_complete: bool = false # 是否已判定通关（之后屏蔽一切操作）
var _wrong_guess_pending: bool = false # 错落反馈播放中，期间屏蔽输入

var _life_plus_appear1_suppress_thumb: bool = false # 首次生命 +1 的引导动画期间压掉点赞手势

# ---- 输入系统：手势识别 + 普通/草稿两套输入方案 ----
var _gesture_recognizer: BoardGestureRecognizer # 手势识别器（按 AB 在普通 / 防误触之间切换）
var _normal_scheme: BoardInputScheme # 普通落子输入方案
var _draft_scheme: BoardInputScheme # 草稿模式输入方案

var _split_pressed_cell: Vector2i = Vector2i(-1, -1) # 长按分裂输入中正按着的格子（-1,-1 表示没有）
var _last_placed_count: int = -1 # 上次显示的已放猫数（-1 表示还没初始化）
var _progress_bar_mode: bool = false # 是否用进度条显示剩余数量
var _progress_track_width: float = 163.0 # 当前进度条轨道宽度（像素）
const _PROGRESS_TRACK_WIDTH_NORMAL: float = 163.0 # 轨道标准宽度（像素）

const _PROGRESS_COUNT_FONT_BASE: int = 46 # 进度数字基准字号
const _PROGRESS_FILL_DEAD_ZONE: float = 33.0 # 填充条起点的死区（像素）

# ---- 连击（AB: combo_encourage） ----
var _combo_count: int = 0 # 当前连击数
var _combo_visual_suppressed: bool = false # 草稿提交期间先不弹连击飘字
var _draft_combo_gain_sum: int = 0 # 草稿提交期间累计的分数
var _combo_score: int = 0 # 本局累计连击分
var _combo_feedback_view: Node = null # 连击飘字视图（子类里赋值）

enum DraftTerminal { NORMAL, CONTRADICTION, ALL_CORRECT } # 草稿结局：正常退出 / 自相矛盾 / 已全对

# ---- 草稿模式状态 ----
var _draft_mode: bool = false # 是否处于草稿模式

var _draft_root: Vector2i = Vector2i(-1, -1) # 草稿起点（第一只草稿猫，-1,-1 表示无）
var _draft_terminal_state: int = DraftTerminal.NORMAL # 当前草稿结局
var _draft_bubble: Label = null # 草稿提示气泡（懒创建）
var _draft_check_token: int = 0 # 终局检查令牌，自增可作废旧的延时检查
var _draft_enter_ms: int = 0 # 进入草稿模式的时刻（毫秒），用于统计停留时长
var _pending_post_cat_auto_apply: bool = false # 已排队「等猫落下动画结束就自动应用草稿」
const _CAT_APPEAR_SEC: float = 1.33 # 猫落下动画时长（秒），期间阻塞输入

var _draft_pre_enter_real_marks: Dictionary = {} # 进草稿前的正式标记快照（死锁时回滚用）
var _draft_deadlock_pending: bool = false # 草稿提交后触发了死锁，待处理
var _draft_deadlock_real_marks: Dictionary = {} # 死锁时要回滚到的正式标记

# ---- 提示：HintEngine 的结果与展示层 ----
var _hint_data: Dictionary = {} # 当前展示中的提示数据
var _hint_cooldown: bool = false # 提示冷却中，防止连点
var _hint_highlight_layer: CanvasLayer = null # 提示高亮用的临时层
var _chain_detail_layer: CanvasLayer = null # 连锁详情层
var _chain_detail_active: bool = false # 连锁详情是否展开中
var _strategy_overlay: CanvasLayer = null # 策略分析浮层
var _strategy_bg: ColorRect = null # 策略浮层遮罩
var _strategy_vbox: VBoxContainer = null # 策略行容器
var _strategy_steps: Array[int] = [0, 0, 0, 0, 0] # 本局各策略（R1~R5）分别被用到的步数

var _last_tool_deplete_ms: int = 0 # 最近一次道具耗尽的时刻（毫秒），用于 800ms 防抖

# ---- 步历史与撤销 ----
var _step_history: StepHistory = StepHistory.new() # 本局步历史
var _undo_executor: UndoHighlightExecutor = UndoHighlightExecutor.new() # 撤销高亮执行器
var _highlight_cursor: int = -1 # 撤销预览游标（-1 未开始 / -2 已到头）
var _current_step_cells: Array[Dictionary] = [] # 当前这一步已改过的格子，抬手时提交

var _hint_mutex: HintMutex = HintMutex.new() # 提示互斥锁（本文件未使用，留给子类）

# ---- 空闲引导：长时间不操作就闪一下道具按钮 ----
var _idle_hint_delay: float = 20.0 # 多久没操作就开始提示（秒）
var _idle_time: float = 0.0 # 已累计的空闲时长（秒）
var _hint_anim_active: bool = false # 提示动画是否正在播
var _idle_hint_active_btn: ToolButton = null # 正在闪的道具按钮

const IDLE_HINT_REPEAT_PLAY_SEC: float = 10.0 # 可重复模式下单次提示播放时长（秒）
var _idle_hint_play_time: float = 0.0 # 本轮提示已播时长（秒）
var _entry_anim_playing: bool = false # 开场动画还在播（期间屏蔽大部分操作）

var _rule_tween: Tween = null # 规则条高亮的循环补间
var _rule_active_highlight: TextureRect = null # 正在高亮的那一块

var _stat_status: String = "" # 埋点用：本次进入对局的状态（new/restart/continue），子类赋值
var _stat_start_ms: int = 0 # 埋点用：本局开始时刻（毫秒），子类赋值

var _goal_emphasis: int = 0 # 目标强调 AB 的取值（0 不强调 / 1 强调猫数量）

# ---- 点赞手势的运行时状态（thumb_up） ----
# 键：in_game_sec 局内秒数、triggered_count 已触发次数、wrong_cat_events 错落事件、missed_cat_* 漏猫候选
var _like_hand_state: Dictionary = {
	"in_game_sec": 0.0,
	"last_cat_sec": 0.0,
	"triggered_count": 0,
	"clock_paused": false,
	"has_seen_first_cat": false,
	"wrong_cat_events": [],
	"missed_cat_candidates": {},
	"missed_cat_prev": {},
}

# 可触发 R4+ 反馈（吹号）的格子缓存
var _r4_plus_cells: Dictionary = {}


# ================= 模式标识与规则条外观 =================
# 本页面的玩法类型标识，子类覆写（基类按普通关算）
func _game_type() -> String:
	return Tracker.GameType.NORMAL


# 按 AB 变体设置第 3 条规则（八邻接）的文案 key
func _apply_third_rule_text() -> void:
	var variant: int = ABTestManager.third_rule_text.get_rule_text_variant()
	var key: String
	match variant:
		ThirdRuleTextConfig.VALUE_VARIANT_A:
			key = "GAME_RULE_NO_TOUCH_A"
		ThirdRuleTextConfig.VALUE_VARIANT_B:
			key = "GAME_RULE_NO_TOUCH_B"
		ThirdRuleTextConfig.VALUE_VARIANT_C:
			key = "GAME_RULE_NO_TOUCH_C"
		_:
			key = "GAME_RULE_NO_TOUCH"
	_rule_label3.text = key


# 按 AB 把规则条换成 V0 / V4 / V7 预制体之一（版本不符就整块重建）
func _apply_rule_info_bar(level: int = 0) -> void:
	var rule_bar := get_node_or_null("Root/VBoxContainer/RuleBar")
	if rule_bar == null:
		return
	var is_v4: bool = ABTestManager.rule_text.is_collapse_10()
	var is_v7: bool = ABTestManager.rule_text.is_single_swipe()

	if is_v4 and level >= 0 and level <= 10:
		is_v4 = false

	if is_v4 and rule_bar is RuleInfoBarV4:
		(rule_bar as RuleInfoBarV4).apply_persisted_state()
		_refresh_rule_bar_node_refs(rule_bar)
		return
	if is_v7 and rule_bar is RuleInfoBarV7:
		_refresh_rule_bar_node_refs(rule_bar)
		return
	if not is_v4 and not is_v7 and rule_bar.get_meta("_rule_bar_v0", false):
		_refresh_rule_bar_node_refs(rule_bar)
		return

	_stop_rule_highlight()
	var vbox: Control = rule_bar.get_parent()
	var idx: int = rule_bar.get_index()
	vbox.remove_child(rule_bar)
	rule_bar.queue_free()
	var scene: PackedScene = (
		_RULE_INFO_BAR_V4_SCENE
		if is_v4
		else (_RULE_INFO_BAR_V7_SCENE if is_v7 else _RULE_INFO_BAR_V0_SCENE)
	)
	var new_bar: Control = scene.instantiate()
	new_bar.name = "RuleBar"
	new_bar.custom_minimum_size = Vector2(1080, 170)
	new_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	new_bar.size_flags_stretch_ratio = 0.0
	if not is_v4 and not is_v7:
		new_bar.set_meta("_rule_bar_v0", true)
	vbox.add_child(new_bar)
	vbox.move_child(new_bar, idx)
	_refresh_rule_bar_node_refs(new_bar)


# 规则条重建后重新抓取内部节点引用（含 3 块高亮）
func _refresh_rule_bar_node_refs(rule_bar: Node) -> void:
	_rules_bg = rule_bar.get_node_or_null("Control/RulesBg") as Panel
	_rule_label1 = rule_bar.get_node_or_null("Control/RuleLabel1") as Label
	_rule_label2 = rule_bar.get_node_or_null("Control/RuleLabel2") as Label
	_rule_label3 = rule_bar.get_node_or_null("Control/RuleLabel3") as Label
	_rule_diagram1 = rule_bar.get_node_or_null("Control/RuleDiagram1") as TextureRect
	_rule_diagram2 = rule_bar.get_node_or_null("Control/RuleDiagram2") as TextureRect
	_rule_diagram3 = rule_bar.get_node_or_null("Control/RuleDiagram3") as TextureRect
	(
		_rule_highlights
		. assign(
			[
				rule_bar.get_node_or_null("Control/RuleHighlight1"),
				rule_bar.get_node_or_null("Control/RuleHighlight2"),
				rule_bar.get_node_or_null("Control/RuleHighlight3"),
			]
		)
	)


# 规则文案入口 AB：决定用信息按钮弹窗，还是直接隐藏规则条
func _apply_rule_text_entry() -> void:
	var info_btn: Button = get_node_or_null("Root/VBoxContainer/Header/InfoBtn") as Button
	if info_btn == null:
		return
	var cfg: RuleTextConfig = ABTestManager.rule_text
	var is_info_popup: bool = cfg.is_info_popup()
	var is_setting_entry: bool = cfg.is_setting_entry()
	var should_hide_rule_bar: bool = is_info_popup or is_setting_entry
	info_btn.visible = is_info_popup

	var rule_bar := get_node_or_null("Root/VBoxContainer/RuleBar") as Control
	if rule_bar != null:
		var rule_inner := rule_bar.get_node_or_null("Control") as CanvasItem
		if rule_inner != null:
			rule_inner.visible = not should_hide_rule_bar


# 标记「已绑定过按压特效」的 meta key，防止重复绑定
const _PRESS_FX_BOUND_META: StringName = &"_press_fx_bound"


# 给顶栏的信息 / 设置按钮绑上按下缩放特效（只绑一次）
func _bind_header_btn_press_fx() -> void:
	for path: String in [
		"Root/VBoxContainer/Header/InfoBtn", "Root/VBoxContainer/Header/SettingsBtn"
	]:
		var btn := get_node_or_null(path) as BaseButton
		if btn != null and not btn.has_meta(_PRESS_FX_BOUND_META):
			btn.set_meta(_PRESS_FX_BOUND_META, true)
			bind_press_release_scale(btn)


# 按 AB 排布规则条：纯图 / 图标+文字 / 仅第 3 条配图 / 纯文字
func _apply_rule_bar_style(level: int = 0) -> void:
	if _rule_diagram1 == null or _rule_diagram3 == null:
		return
	var cfg: RuleTextConfig = ABTestManager.rule_text

	if cfg.is_collapse_10() and level > 0 and level <= 10:
		_layout_pills_third_img()
		return
	if cfg.is_all_img():
		_set_labels_visible(false, false, false)
		_rule_diagram1.visible = true
		_rule_diagram2.visible = true
		_rule_diagram3.visible = true
		_set_rect(_rule_diagram1, 161.0, 261.0, 50.0, 150.0)
		_set_rect(_rule_diagram2, 490.0, 590.0, 50.0, 150.0)
		_set_rect(_rule_diagram3, 819.0, 919.0, 50.0, 150.0)
	elif cfg.is_icon_text():
		_set_labels_visible(true, true, true)
		_apply_icon_text_label_style(
			_rule_label1, _RULE_ICON_TEXT_LETTER_SPACING_1, _RULE_ICON_TEXT_LINE_SPACING_1
		)
		_apply_icon_text_label_style(
			_rule_label2, _RULE_ICON_TEXT_LETTER_SPACING_2, _RULE_ICON_TEXT_LINE_SPACING_REST
		)
		_apply_icon_text_label_style(
			_rule_label3, _RULE_ICON_TEXT_LETTER_SPACING_3, _RULE_ICON_TEXT_LINE_SPACING_REST
		)
		_set_h(_rule_label1, 169.0, 353.0)
		_set_h(_rule_label2, 498.0, 682.0)
		_set_h(_rule_label3, 827.0, 1011.0)
		_rule_diagram1.visible = true
		_rule_diagram2.visible = true
		_rule_diagram3.visible = true
		_set_rect(_rule_diagram1, 69.0, 159.0, 55.0, 145.0)
		_set_rect(_rule_diagram2, 397.0, 487.0, 55.0, 145.0)
		_set_rect(_rule_diagram3, 728.0, 818.0, 55.0, 145.0)
	elif cfg.is_third_img():
		_layout_pills_third_img()
	else:
		_set_labels_visible(true, true, true)
		_set_h(_rule_label1, 56.0, 366.0)
		_set_h(_rule_label2, 385.0, 695.0)
		_set_h(_rule_label3, 714.0, 1024.0)
		_rule_diagram1.visible = false
		_rule_diagram2.visible = false
		_rule_diagram3.visible = false


# 取（并缓存）指定字间距的字体副本
func _get_rule_icon_text_font(letter_spacing: int) -> FontVariation:
	if not _rule_icon_text_fonts.has(letter_spacing):
		var fv := _RULE_LABEL_MEDIUM_FONT.duplicate() as FontVariation
		fv.spacing_glyph = letter_spacing
		_rule_icon_text_fonts[letter_spacing] = fv
	return _rule_icon_text_fonts[letter_spacing]


# 统一「图标 + 文字」模式下的字号、行距与文字框位置
func _apply_icon_text_label_style(label: Label, letter_spacing: int, line_spacing: int) -> void:
	if label == null:
		return
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.offset_top = _RULE_ICON_TEXT_BOX_TOP
	label.offset_bottom = _RULE_ICON_TEXT_BOX_BOTTOM
	label.add_theme_font_override(&"font", _get_rule_icon_text_font(letter_spacing))
	label.add_theme_constant_override(&"line_spacing", line_spacing)

	var auto_fit := label as AutoFitLabel
	if auto_fit != null:
		auto_fit.max_font_size = _RULE_ICON_TEXT_FONT_SIZE
	else:
		label.add_theme_font_size_override(&"font_size", _RULE_ICON_TEXT_FONT_SIZE)


# 一次性设置三条规则文字的可见性
func _set_labels_visible(a: bool, b: bool, c: bool) -> void:
	_rule_label1.visible = a
	_rule_label2.visible = b
	_rule_label3.visible = c


# 只有第 3 条规则配图时的排布
func _layout_pills_third_img() -> void:
	_set_labels_visible(true, true, true)
	_set_h(_rule_label1, 56.0, 366.0)
	_set_h(_rule_label2, 385.0, 695.0)
	_set_h(_rule_label3, 812.0, 1024.0)
	_rule_diagram1.visible = false
	_rule_diagram2.visible = false
	_rule_diagram3.visible = true
	_set_rect(_rule_diagram3, 720.0, 812.0, 54.0, 146.0)


# 把关卡号告诉 V7 规则条，决定它能不能折叠
func _apply_rule_swipe_collapse(level: int) -> void:
	var bar := get_node_or_null("Root/VBoxContainer/RuleBar")
	if bar is RuleInfoBarV7:
		(bar as RuleInfoBarV7).apply_level(level)


# 设置控件的左右偏移
func _set_h(node: Control, left: float, right: float) -> void:
	node.offset_left = left
	node.offset_right = right


# 设置控件的四边偏移
func _set_rect(node: Control, left: float, right: float, top: float, bottom: float) -> void:
	node.offset_left = left
	node.offset_right = right
	node.offset_top = top
	node.offset_bottom = bottom


# 打开「怎么玩」页面
func _on_info_btn_pressed() -> void:
	UIManager.show_ui(UiName.HOW_TO_PLAY)


# 按 AB 调整规则条与猫数量行的上下顺序（适配占位始终夹在中间）
func _apply_rules_ui_order() -> void:
	var vbox: Node = $Root/VBoxContainer
	var rule_bar: Node = vbox.get_node_or_null("RuleBar")
	var cat_heart_row: Node = vbox.get_node_or_null("CatHeartRow")
	var holder: Node = vbox.get_node_or_null("RuleBarAdaptHolder")
	if rule_bar == null or cat_heart_row == null or holder == null:
		return
	var want_rule_above: bool = ABTestManager.game_page_rules_ui.is_rule_bar_above()
	var top: Node = rule_bar if want_rule_above else cat_heart_row
	var bottom: Node = cat_heart_row if want_rule_above else rule_bar
	if top.get_index() < holder.get_index() and holder.get_index() < bottom.get_index():
		return
	var min_idx: int = min(rule_bar.get_index(), cat_heart_row.get_index(), holder.get_index())
	vbox.move_child(top, min_idx)
	vbox.move_child(holder, min_idx + 1)
	vbox.move_child(bottom, min_idx + 2)


# 按规则条位置选开场动画名（Appear / Appear2）
func _appear_anim_name() -> String:
	return "Appear2" if ABTestManager.game_page_rules_ui.is_rule_bar_above() else "Appear"


# 由 UIManager 在页面显示时调用：重置开场状态、挂生命/进度条、连信号、进开场动画
func on_show(params: Dictionary = {}) -> void:
	_eval_interstitial_cache = null
	super.on_show(params)

	SoundManager.start_bgm()

	HelpshiftManager.request_unread()

	set_process(true)

	_auto_mark_token += 1

	_lock_x_token += 1

	# 续局时恢复连击分数与「生命 +1 是否已用」
	_combo_count = params.get("restore_combo_count", 0)
	_combo_score = params.get("restore_combo_score", 0)

	_life_plus_used_this_game = bool(params.get("restore_life_plus_used", false))

	var rule_text_level: int = params.get("level_index", params.get("retry_level", 0))
	_apply_rule_info_bar(rule_text_level)
	_apply_third_rule_text()

	_apply_rule_text_entry()

	_bind_header_btn_press_fx()

	_apply_rule_bar_style(rule_text_level)

	_apply_rules_ui_order()

	_mount_life_bar()
	_mount_progress_bar()
	_goal_emphasis = ABTestManager.goal_emphasis.value()

	# 接棋盘信号：R4+ 反馈缓存 + 轴自动打叉 + 轴按钮刷新
	if not _board_view.cell_state_changed.is_connected(_on_board_cell_state_changed_for_r4):
		_board_view.cell_state_changed.connect(_on_board_cell_state_changed_for_r4)

	if not _board_view.axis_auto_mark_pressed.is_connected(_on_axis_auto_mark_pressed):
		_board_view.axis_auto_mark_pressed.connect(_on_axis_auto_mark_pressed)
	if not _board_view.cell_state_changed.is_connected(_on_cell_changed_refresh_axis_btn):
		_board_view.cell_state_changed.connect(_on_cell_changed_refresh_axis_btn)
	_axis_busy_set.clear()

	_ac_shown = false
	_ac_had_wrong_cat = false
	if _ac_anim != null:
		_ac_anim.play("RESET")

	_exit_draft_mode_and_clear()

	# 草稿按钮：按 AB 变体与关卡号决定是否可见
	var unlocked: bool = _is_draft_unlocked()
	if _draft_btn != null:
		_draft_btn.visible = unlocked
	if _apply_btn != null:
		_apply_btn.visible = false

	_anim_player.play(_appear_anim_name())
	_anim_player.seek(0.0, true)
	_anim_player.pause()

	var rb_after_seek := get_node_or_null("Root/VBoxContainer/RuleBar")
	if rb_after_seek is RuleInfoBarV4:
		(rb_after_seek as RuleInfoBarV4).apply_persisted_state()

	_set_rule_info_bar_v4_interactive(false)

	# 恢复或重建撤销系统（续局会带 step_history）
	_setup_undo_system(params.get("restore_step_history", []))

	if not _board_container.resized.is_connected(_on_board_container_resized):
		connect_managed(_board_container.resized, _on_board_container_resized)

	if not GameState.tool_count_changed.is_connected(_on_tool_count_changed):
		connect_managed(GameState.tool_count_changed, _on_tool_count_changed)


# 按 AB 与关卡号开关开场动画里的高亮轨道与光效（规则条 / 猫数量）
func _apply_goal_emphasis_tracks(level: int) -> void:
	var rule_control: CanvasItem = (
		get_node_or_null("Root/VBoxContainer/RuleBar/Control") as CanvasItem
	)
	var keep_rule: bool = true
	var keep_cat: bool = false
	if _goal_emphasis == 1 and level > 10:
		keep_rule = false
		keep_cat = true

	var rule_bar_collapsed: bool = (
		ABTestManager.rule_text.is_collapse_10()
		and level > 10
		and GameState.is_rule_info_bar_collapsed()
	)
	if rule_bar_collapsed:
		keep_rule = false
		if rule_control != null:
			rule_control.modulate = Color(1, 1, 1, 1)

	var rule_glow: CanvasItem = (
		get_node_or_null("Root/VBoxContainer/RuleBar/Control/Glow") as CanvasItem
	)
	if rule_glow != null:
		rule_glow.visible = keep_rule
	var cat_glow: CanvasItem = (
		get_node_or_null("Root/VBoxContainer/CatHeartRow/Target/Glow") as CanvasItem
	)
	if cat_glow != null:
		cat_glow.visible = keep_cat
	var anim: Animation = _anim_player.get_animation(_appear_anim_name())
	if anim == null:
		return
	for i in anim.get_track_count():
		var p: String = str(anim.track_get_path(i))
		if p in _GOAL_RULE_HIGHLIGHT_PATHS:
			anim.track_set_enabled(i, keep_rule)
		elif p in _GOAL_CAT_HIGHLIGHT_PATHS:
			anim.track_set_enabled(i, keep_cat)
		elif "RuleBar/Control" in p:
			anim.track_set_enabled(i, not rule_bar_collapsed)


# ================= 道具：提示 / 定位 / 撤销 =================
# 按道具名取按钮（locate / hint / undo）
func _tool_btn_of(kind: String) -> ToolButton:
	match kind:
		"locate":
			return _tool_locate_btn as ToolButton
		"hint":
			return _tool_hint_btn as ToolButton
		"undo":
			return _tool_undo_btn as ToolButton
	return null


# GameState 道具数量变化时刷新按钮角标与状态
func _on_tool_count_changed(kind: String, count: int) -> void:
	var tb := _tool_btn_of(kind)
	if tb == null or tb.state == ToolButton.State.FREE:
		return
	if count > 0:
		tb.set_badge_count(count)
		tb.state = ToolButton.State.HAS_TOOL
	else:
		tb.badge_count = 0
		tb.state = ToolButton.State.NO_TOOL


# 按钮 → 埋点用的道具名
func _btn_to_prop_name(btn: Control) -> String:
	if btn == _tool_hint_btn:
		return Tracker.Prop.HINT
	elif btn == _tool_locate_btn:
		return Tracker.Prop.LOCATE
	elif btn == _tool_undo_btn:
		return "undo"
	return ""


# 把数量写回 GameState（会落存档）
func _save_tool_to_state(btn: Control, count: int) -> void:
	if btn == _tool_locate_btn:
		GameState.set_tool_count("locate", count)
	elif btn == _tool_hint_btn:
		GameState.set_tool_count("hint", count)
	elif btn == _tool_undo_btn:
		GameState.set_tool_count("undo", count)


# 消耗一个道具；FREE 直接放行，数量为 0 则转去请求激励广告并返回 false
func _consume_tool(btn: Control, vibrate: bool = true) -> bool:
	var tb := btn as ToolButton
	if tb == null:
		return false

	if tb.state == ToolButton.State.FREE:
		if vibrate:
			VibrateManager.play_vibrate(VibrateManager.Level.LEVEL4)
		return true
	if tb.badge_count <= 0:
		_request_reward_for_tool(btn)
		return false
	var new_count: int = tb.badge_count - 1
	if new_count == 0:
		_last_tool_deplete_ms = Time.get_ticks_msec()

	_save_tool_to_state(btn, new_count)
	if vibrate:
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL4)

	var prop_name: String = _btn_to_prop_name(btn)
	if prop_name != "":
		Tracker.track_prop_use(prop_name, Tracker.get_current_source(), 1, new_count)
	return true


# 用 GameState 的数量整体同步三个道具按钮（含免费区与调试强制免费）
func _sync_tools_from_state() -> void:
	var tb_r := _tool_locate_btn as ToolButton
	var tb_h := _tool_hint_btn as ToolButton
	if tb_r != null:
		if GameState.get_tool_count("locate") > 0:
			tb_r.state = ToolButton.State.HAS_TOOL
			tb_r.set_badge_count(GameState.get_tool_count("locate"))
		else:
			tb_r.badge_count = 0
			tb_r.state = ToolButton.State.NO_TOOL
	if tb_h != null:
		if GameState.get_tool_count("hint") > 0:
			tb_h.state = ToolButton.State.HAS_TOOL
			tb_h.set_badge_count(GameState.get_tool_count("hint"))
		else:
			tb_h.badge_count = 0
			tb_h.state = ToolButton.State.NO_TOOL

	var tb_u := _tool_undo_btn as ToolButton
	if tb_u != null:
		if ABTestManager.undo_btn.is_free():
			tb_u.state = ToolButton.State.FREE
		elif GameState.get_tool_count("undo") > 0:
			tb_u.state = ToolButton.State.HAS_TOOL
			tb_u.set_badge_count(GameState.get_tool_count("undo"))
		else:
			tb_u.badge_count = 0
			tb_u.state = ToolButton.State.NO_TOOL

	if _is_free_tool_zone():
		if tb_r != null:
			tb_r.state = ToolButton.State.FREE
		if tb_h != null:
			tb_h.state = ToolButton.State.FREE
		if tb_u != null:
			tb_u.state = ToolButton.State.FREE

	match debug_force_free_tool:
		"hint":
			if tb_h != null:
				tb_h.state = ToolButton.State.FREE
		"locate":
			if tb_r != null:
				tb_r.state = ToolButton.State.FREE
		"undo":
			if tb_u != null:
				tb_u.state = ToolButton.State.FREE
		"all":
			if tb_r != null:
				tb_r.state = ToolButton.State.FREE
			if tb_h != null:
				tb_h.state = ToolButton.State.FREE
			if tb_u != null:
				tb_u.state = ToolButton.State.FREE


# 当前关卡是否处于「道具全免费」区间
func _is_free_tool_zone() -> bool:
	return not ABTestManager.reward_unlock_level.is_reward_required_at(
		GameState.get_current_level()
	)


# 从外部设置某道具数量（写回 GameState）
func set_tool_count(tool_name: String, count: int) -> void:
	var btn: Control
	match tool_name:
		"locate":
			btn = _tool_locate_btn
		"hint":
			btn = _tool_hint_btn
		"undo":
			btn = _tool_undo_btn
		_:
			return
	var tb := btn as ToolButton
	if tb == null:
		return

	_save_tool_to_state(btn, count)


# 道具用尽时请求激励视频；看完才发道具，800ms 内重复点击忽略
func _request_reward_for_tool(btn: Control) -> void:
	if Time.get_ticks_msec() - _last_tool_deplete_ms < 800:
		return
	var pos: String = _reward_pos_for(btn)

	var show_id := UniKitManager.gen_show_id()
	if not UniKitManager.is_reward_ready("reward", pos, show_id):
		Toast.popup("AD_TOAST_NOT_READY", self)
		return

	var on_rewarded := func(placement_id: String) -> void:
		if placement_id != "reward":
			return
		GameState.inc_game_total_stat(_game_type(), "rv_count")
		_grant_tool_reward(btn)
	var on_closed := func(placement_id: String) -> void:
		if placement_id != "reward":
			return

	_disconnect_self_reward_callbacks()
	UniKitManager.ad_rewarded.connect(on_rewarded, CONNECT_ONE_SHOT)
	UniKitManager.ad_closed.connect(on_closed, CONNECT_ONE_SHOT)
	UniKitManager.show_reward("reward", pos, show_id)


# 看完广告后经 AwardManager 发 1 个对应道具，并按来源埋点
func _grant_tool_reward(btn: Control) -> void:
	var tb := btn as ToolButton
	if tb == null:
		return
	var prop_name: String = _btn_to_prop_name(btn)
	if prop_name == "":
		return
	var source: String
	match prop_name:
		Tracker.Prop.HINT:
			source = Tracker.PropSource.HINT_REWARD_AD
		Tracker.Prop.LOCATE:
			source = Tracker.PropSource.LOCATE_REWARD_AD
		_:
			source = Tracker.PropSource.UNDO_REWARD_AD

	AwardManager.dispatch([AwardItem.make(prop_name, 1)], AwardManager.DisplayType.DIRECT, source)


# ================= 开局广告（插屏 / banner） =================
# 开局插屏判定结果缓存（同一次 on_show 内只算一次）
var _eval_interstitial_cache: Variant = null


# 开局插屏判定入口：默认走缓存，dry_run 时只探测不落库
func _eval_start_interstitial(
	params: Dictionary = {}, ad_position: String = "", dry_run: bool = false
) -> Dictionary:
	if not dry_run and _eval_interstitial_cache != null:
		return _eval_interstitial_cache
	var result: Dictionary = _compute_start_interstitial(params, ad_position, dry_run)
	if not dry_run:
		_eval_interstitial_cache = result
	return result


# 真正判开局插屏：概率组 → 解锁门槛 → 内存/额外保护 → 冷却 → 广告填充
func _compute_start_interstitial(
	params: Dictionary = {}, ad_position: String = "", dry_run: bool = false
) -> Dictionary:
	if ABTestManager.inter_prob.is_enabled():
		var view_count: int = GameState.get_session_reward_view_count()
		var threshold: int = ABTestManager.inter_prob.get_threshold()
		var pct_log: int = ABTestManager.inter_prob.get_show_percent()
		print(
			(
				"[InterProb] enabled grp=%d view_count=%d threshold=%d show_pct=%d dry_run=%s"
				% [ABTestManager.inter_prob.value(), view_count, threshold, pct_log, str(dry_run)]
			)
		)
		if view_count >= threshold:
			if dry_run:
				params = params.duplicate()
				params["_dry_run_prob_pending_pct"] = ABTestManager.inter_prob.get_show_percent()
				print(
					(
						"[InterProb] reach threshold but dry_run → skip reset/roll, mark pending_pct=%d"
						% pct_log
					)
				)
			else:
				GameState.reset_session_reward_view_count()
				var ip_cfg: AbConfigBase = ABTestManager.inter_prob
				if ip_cfg.is_debug_disabled():
					print(
						"[InterProb] reach threshold → reset done, debug_disabled → bypass roll, pass-through"
					)
				else:
					var pct: int = ABTestManager.inter_prob.get_show_percent()
					var roll: int = randi() % 100
					if roll >= pct:
						print(
							(
								"[InterProb] reach threshold → reset done, roll=%d vs pct=%d → miss(拦截)"
								% [roll, pct]
							)
						)
						return {"eligible": false, "reason": "inter_prob 概率未命中(%d%%)" % (100 - pct)}
					print(
						(
							"[InterProb] reach threshold → reset done, roll=%d vs pct=%d → hit(放行)"
							% [roll, pct]
						)
					)
		else:
			print("[InterProb] view_count<threshold → no reset/roll, pass-through")

	if params.get("endgame_restore", false):
		return {"eligible": false, "reason": "残局复原入口不播"}

	if not UniKitManager.is_debug_ad_enabled():
		return {"eligible": false, "reason": "dev 广告总开关已关闭"}

	if not GameState.is_interstitial_unlocked():
		var ul_cfg: AbConfigBase = ABTestManager.inter_unlock_level
		var level_unlocked: bool = ABTestManager.inter_unlock_level.is_unlocked_at(
			GameState.get_current_level()
		)
		if not ul_cfg.is_debug_disabled() and not level_unlocked:
			return {"eligible": false, "reason": "未达关卡门槛 inter_unlock_level"}

		var us_cfg: AbConfigBase = ABTestManager.inter_unlock_session
		var session_unlocked: bool = ABTestManager.inter_unlock_session.is_unlocked()
		if not us_cfg.is_debug_disabled() and not session_unlocked:
			return {"eligible": false, "reason": "未达 session 门槛 inter_unlock_session"}

		if level_unlocked and session_unlocked and not dry_run:
			GameState.mark_interstitial_unlocked()

	var um_cfg: AbConfigBase = ABTestManager.inter_unlock_memory
	if (
		not um_cfg.is_debug_disabled()
		and not ABTestManager.inter_unlock_memory.is_unlocked_for_device()
	):
		return {"eligible": false, "reason": "设备内存低于门槛 inter_unlock_memory"}

	var protect_cfg: AbConfigBase = ABTestManager.inter_extra_protect_lc
	if not protect_cfg.is_debug_disabled():
		var protect: Dictionary = ABTestManager.inter_extra_protect_lc.eval_start_interstitial()
		if protect.get("blocked", false):
			return {"eligible": false, "reason": protect.get("reason", "被额外保护拦截")}

	if UniKitManager.is_interstitial_in_cd():
		return {"eligible": false, "reason": "插屏冷却中(CD 未到)"}

	var inter_show_id: String = ""
	if dry_run:
		if not UniKitManager.is_interstitial_valid("interstitial", ad_position):
			return {"eligible": false, "reason": "无广告填充"}
	else:
		inter_show_id = UniKitManager.gen_show_id()
		if not UniKitManager.is_interstitial_ready("interstitial", ad_position, inter_show_id):
			return {"eligible": false, "reason": "无广告填充"}

	if params.has("_dry_run_prob_pending_pct"):
		var pct_dry: int = int(params["_dry_run_prob_pending_pct"])
		return {
			"eligible": false,
			"reason": "其他闸全过;inter_prob 真实调用时 %d%% 概率拦截(dry_run 未掷骰)" % (100 - pct_dry)
		}
	return {"eligible": true, "reason": "", "show_id": inter_show_id}


# 最近一次开局插屏的结果描述，供调试面板查看
static var last_interstitial_status: String = "尚未触发开局插屏"

# 调试用：强制某道具免费（"" 关闭 / hint / locate / undo / all）
static var debug_force_free_tool: String = ""

# 调试用：触发「生命 +1」所需的最短游戏时长（秒）
static var debug_life_plus_min_sec: float = 60.0


# 真的去播开局插屏，并把结果显示到调试状态里
func _try_show_start_interstitial(ad_position: String, elig: Dictionary) -> bool:
	if not elig.get("eligible", false):
		last_interstitial_status = elig.get("reason", "未知原因")
		return false

	var show_id: String = elig.get("show_id", "")
	var shown: bool = UniKitManager.try_show_interstitial("interstitial", ad_position, show_id)
	last_interstitial_status = "已显示" if shown else "已通过判定但无填充(未显示)"
	return shown


# 判 banner 是否该展示（解锁门槛 / 额外保护 / 棋盘尺寸范围）
func _eval_start_banner() -> Dictionary:
	if not UniKitManager.is_debug_ad_enabled():
		return {"eligible": false, "reason": "dev 广告总开关已关闭"}

	if not GameState.is_banner_unlocked():
		var bus_cfg: AbConfigBase = ABTestManager.banner_unlock_session
		var session_unlocked: bool = ABTestManager.banner_unlock_session.is_unlocked()
		if not bus_cfg.is_debug_disabled() and not session_unlocked:
			return {"eligible": false, "reason": "未达 session 门槛 banner_unlock_session"}

		var bul_cfg: AbConfigBase = ABTestManager.banner_unlock_level
		var has_level: bool = _level_config.has("level")
		var level_unlocked: bool = (
			has_level
			and ABTestManager.banner_unlock_level.is_unlocked_at(_level_config.get("level", 0))
		)
		if not bul_cfg.is_debug_disabled() and has_level and not level_unlocked:
			return {"eligible": false, "reason": "未达关卡门槛 banner_unlock_level"}

		if has_level and session_unlocked and level_unlocked:
			GameState.mark_banner_unlocked()

	var bep_cfg: AbConfigBase = ABTestManager.banner_extra_protect_lc
	if not bep_cfg.is_debug_disabled():
		var protect: Dictionary = ABTestManager.banner_extra_protect_lc.eval_start_banner()
		if protect.get("blocked", false):
			return {
				"eligible": false,
				"reason": protect.get("reason", "被额外保护拦截 banner_extra_protect_lc")
			}

	var bud_cfg: AbConfigBase = ABTestManager.banner_unlock_diff_lc
	if (
		not bud_cfg.is_debug_disabled()
		and not ABTestManager.banner_unlock_diff_lc.is_unlocked_for_size(
			_level_config.get("size", 0)
		)
	):
		return {"eligible": false, "reason": "当前 size 不在展示范围 banner_unlock_diff_lc"}
	return {"eligible": true, "reason": ""}


# 最近一次 banner 的结果描述，供调试面板查看
static var last_banner_status: String = "尚未触发 banner"


# 判定通过就展示 banner，高度避开底部安全区
func _show_banner_if_eligible(ad_position: String) -> void:
	var elig: Dictionary = _eval_start_banner()
	if not elig.get("eligible", false):
		last_banner_status = elig.get("reason", "未知原因")
		return
	var banner_h: int = int(_ad_banner.custom_minimum_size.y)
	var adapt_h: int = int(_ad_down_adapt.size.y)
	UniKitManager.show_banner("banner", ad_position, true, 0, banner_h + adapt_h)
	last_banner_status = "已展示"


# 销毁 banner 广告
func _destroy_banner() -> void:
	UniKitManager.destroy_ad("banner")


# banner 广告位名：每日关用 daily，其余用 game
func _banner_ad_position() -> String:
	return "daily" if _game_type() == Tracker.GameType.DAILY else "game"


# ================= 生命周期与空闲引导 =================
# 前后台切换通知：回前台重置空闲计时，并按需重播自动完成按钮
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_idle_time = 0.0
		_on_application_focus_in()
		if _ac_shown and _ac_anim != null:
			_ac_anim.play("appear")
		else:
			_refresh_auto_complete_btn()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_application_focus_out()


# 回到前台的钩子，子类覆写
func _on_application_focus_in() -> void:
	pass


# 切到后台的钩子，子类覆写（每日关用它停表）
func _on_application_focus_out() -> void:
	pass


# 齿轮按钮回调，子类覆写
func _on_gear_btn_pressed() -> void:
	pass


# 系统返回键回调，子类覆写
func _on_back_request() -> void:
	pass


# 每帧：推进点赞手势时钟并清理过期事件；空闲够久就闪道具按钮
func _process(delta: float) -> void:
	if not _like_hand_state["clock_paused"]:
		_like_hand_state["in_game_sec"] += delta
		_prune_wrong_cat_events()
	if not _can_show_idle_hint():
		return

	if _hint_anim_active and ABTestManager.prop_highlight.is_repeatable():
		_idle_hint_play_time += delta
		if _idle_hint_play_time >= IDLE_HINT_REPEAT_PLAY_SEC:
			_stop_idle_tool_hint()
			_idle_time = 0.0
			return
	_idle_time += delta
	if _idle_time >= _idle_hint_delay and not _hint_anim_active:
		_play_idle_tool_hint()


# 有任何操作就清零空闲计时并停掉提示动画
func _reset_idle_hint() -> void:
	_idle_time = 0.0
	_stop_idle_tool_hint()


# 按 AB 选要闪哪个道具按钮（可指定 locate/hint，也可随机或按持有量挑）
func _select_idle_tool_btn() -> ToolButton:
	match ABTestManager.prop_highlight.target_prop():
		"locate":
			return _tool_locate_btn as ToolButton
		"hint":
			return _tool_hint_btn as ToolButton
		"none":
			return null
		"random":
			var locate_n: int = GameState.get_tool_count("locate")
			var hint_n: int = GameState.get_tool_count("hint")

			if (locate_n > 0) == (hint_n > 0):
				return (_tool_hint_btn if randf() < 0.5 else _tool_locate_btn) as ToolButton
			return (_tool_locate_btn if locate_n > 0 else _tool_hint_btn) as ToolButton
		_:
			if GameState.get_tool_count("locate") > 0:
				return _tool_locate_btn as ToolButton
			if GameState.get_tool_count("hint") > 0:
				return _tool_hint_btn as ToolButton
			return _tool_locate_btn as ToolButton


# 让选中的道具按钮循环播提示动画，并记一次「已展示」
func _play_idle_tool_hint() -> void:
	var tb: ToolButton = _select_idle_tool_btn()
	if tb == null:
		return
	var ap: AnimationPlayer = tb.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	ap.play("tool_loop")
	_hint_anim_active = true
	_idle_hint_play_time = 0.0
	_idle_hint_active_btn = tb

	GameState.mark_prop_highlight_shown()


# 停止空闲提示动画并复位按钮
func _stop_idle_tool_hint() -> void:
	if not _hint_anim_active:
		return

	if _idle_hint_active_btn != null:
		var ap: AnimationPlayer = (
			_idle_hint_active_btn.get_node_or_null("AnimationPlayer") as AnimationPlayer
		)
		if ap != null and ap.has_animation("RESET"):
			ap.play("RESET")
	_hint_anim_active = false
	_idle_hint_active_btn = null


# ================= 页面按钮与通用回调 =================
# 坐标按钮：切换棋盘坐标显示，并计一次埋点
func _on_coord_btn_pressed() -> void:
	if _entry_anim_playing:
		return
	Tracker.track_btn_click(Tracker.Btn.COORD, self)
	Tracker.inc_stat("coord_count")
	_stop_idle_tool_hint()
	_board_view.toggle_coords()


# 设置按钮：暂停手势时钟后打开设置页，关闭时恢复时钟
func _on_settings_btn_pressed() -> void:
	if _is_complete:
		return
	Tracker.track_btn_click(Tracker.Btn.OPTIONS, self)

	pause_like_hand_clock()
	(
		UIManager
		. show_ui(
			UiName.SETTING,
			{
				"is_game_mode": true,
				"on_restart": _on_restart_requested,
				"on_close": Callable(self, "resume_like_hand_clock"),
			}
		)
	)


# 玩家关掉提示：清理高亮，然后尝试展示 banner
func _on_hint_dismissed() -> void:
	Tracker.track_btn_click(Tracker.Btn.HINT_STOP, self)
	Tracker.inc_stat("hint_stop_used")
	_cleanup_hint()

	_show_banner_if_eligible(_banner_ad_position())


# 清空提示数据与所有临时高亮
func _cleanup_hint() -> void:
	_close_chain_detail()
	_clear_hint_highlights()
	_board_view.clear_hint_cells()
	_hint_data = {}


# 关掉连锁详情层并恢复提示浮层
func _close_chain_detail() -> void:
	_chain_detail_active = false
	if _chain_detail_layer != null:
		if _chain_detail_layer.is_inside_tree():
			_chain_detail_layer.get_parent().remove_child(_chain_detail_layer)
		_chain_detail_layer.queue_free()
		_chain_detail_layer = null
	_hint_overlay._overlay.visible = true


# 棋盘左右抖一下（错误落子反馈）
func _play_screen_shake() -> void:
	var orig := _board_view.position
	var tw := create_tween()
	tw.tween_property(_board_view, "position:x", orig.x + 8.0, 0.05)
	tw.tween_property(_board_view, "position:x", orig.x - 8.0, 0.05)
	tw.tween_property(_board_view, "position:x", orig.x + 5.0, 0.04)
	tw.tween_property(_board_view, "position:x", orig.x - 5.0, 0.04)
	tw.tween_property(_board_view, "position:x", orig.x, 0.03)


# 作弊指令：直接通关
func _cmd_win(_args: Array[String]) -> void:
	if not _is_complete:
		_on_game_complete()


# 此刻能否弹空闲提示（页面可见、无弹层、AB 条件满足等）
func _can_show_idle_hint() -> bool:
	var base_ok: bool = (
		visible and not _is_complete and not _wrong_guess_pending and not _hint_overlay.visible
	)
	if not base_ok:
		return false
	var ph: PropHighlightConfig = ABTestManager.prop_highlight

	if ph.target_prop() == "none":
		return false

	if ph.is_once_per_lifetime() and GameState.has_prop_highlight_shown():
		return false

	if not ph.is_repeatable() and GameState.has_used_tool():
		return false
	return true


# 销毁提示高亮层
func _clear_hint_highlights() -> void:
	if _hint_highlight_layer != null:
		if _hint_highlight_layer.is_inside_tree():
			_hint_highlight_layer.get_parent().remove_child(_hint_highlight_layer)
		_hint_highlight_layer.queue_free()
		_hint_highlight_layer = null


# 通关回调，子类覆写（进结算页 / 走连胜流程）
func _on_game_complete() -> void:
	pass


# 设置页点「重开」的回调，子类覆写
func _on_restart_requested() -> void:
	pass


# 通关要跳转的 UI 名，子类覆写
func _win_ui_name() -> StringName:
	return &""


# 道具对应的激励广告位名
func _reward_pos_for(btn: Control) -> String:
	if btn == _tool_locate_btn:
		return Tracker.AdPos.PROPS_NORMAL_LOCATE
	elif btn == _tool_undo_btn:
		return "props_normal_undo"
	return Tracker.AdPos.PROPS_NORMAL_HINT


# 展示通关 toast 并等它消失（返回是否真的展示了）
func _play_win_toast_and_wait() -> bool:
	var toast: CanvasLayer = _maybe_show_win_toast()
	if toast == null:
		return false
	create_countdown(
		1.3,
		func() -> void:
			if is_instance_valid(toast):
				toast.hide_toast()
	)
	await get_tree().create_timer(1.5).timeout
	return true


# 按步数算档位、看 AB 覆盖范围，决定是否播通关 toast 并挑一句文案
func _maybe_show_win_toast() -> CanvasLayer:
	var scale: int = _level_config.get("size", 0)
	var step: int = Tracker.get_stat("step_used")
	var thresholds: Dictionary = WinToastTier.get_thresholds(scale)
	var ab_enabled: bool = ABTestManager.win_toast.is_enabled()
	if not ab_enabled:
		print(
			(
				"[WinToast] scale=%d step=%d thresholds=%s ab_enabled=false → skip"
				% [scale, step, thresholds]
			)
		)
		return null
	var tier: int = WinToastTier.determine_tier(scale, step)
	var ab_covers: bool = tier >= 0 and ABTestManager.win_toast.covers_tier(tier)
	if tier < 0 or not ab_covers:
		print(
			(
				"[WinToast] scale=%d step=%d thresholds=%s tier=%s ab_covers=%s → skip"
				% [scale, step, thresholds, WinToastTier.tier_name(tier), ab_covers]
			)
		)
		return null
	var toast: CanvasLayer = _resolve_win_toast_node(tier)
	if toast == null:
		print(
			(
				"[WinToast] scale=%d step=%d thresholds=%s tier=%s → node missing, skip"
				% [scale, step, thresholds, WinToastTier.tier_name(tier)]
			)
		)
		return null
	print(
		(
			"[WinToast] scale=%d step=%d thresholds=%s tier=%s ab_covers=true → show %s"
			% [scale, step, thresholds, WinToastTier.tier_name(tier), toast.name]
		)
	)
	toast.set_message(WinToastMessages.pick_random(tier, step, scale))
	toast.show_toast({})
	return toast


# 按档位取对应的 toast 节点
func _resolve_win_toast_node(tier: int) -> CanvasLayer:
	match tier:
		WinToastTier.TIER_PERFECT:
			return get_node_or_null("Root/WinToast04") as CanvasLayer
		WinToastTier.TIER_P5:
			return get_node_or_null("Root/WinToast03") as CanvasLayer
		WinToastTier.TIER_P10:
			return get_node_or_null("Root/WinToast02") as CanvasLayer
		WinToastTier.TIER_P20:
			return get_node_or_null("Root/WinToast01") as CanvasLayer
	return null


# 棋盘容器尺寸变化 → 下一帧重排棋盘
func _on_board_container_resized() -> void:
	_relayout_board.call_deferred()


# 棋盘固定显示宽度（像素），缩放的基准
const FIXED_BOARD_WIDTH: float = 1008.0


# 把棋盘按容器宽度等比缩放并居中，再补偿圆角与自动打叉按钮的反向缩放
func _relayout_board() -> void:
	if _level_config.is_empty() or not _level_config.has("size"):
		return
	var intrinsic: Vector2 = BoardView.intrinsic_size_for(_level_config["size"])
	var board_scale: float = FIXED_BOARD_WIDTH / intrinsic.x
	_board_view.size = intrinsic
	_board_view.pivot_offset = Vector2.ZERO
	_board_view.scale = Vector2(board_scale, board_scale)
	var visible_w: float = intrinsic.x * board_scale
	var visible_h: float = intrinsic.y * board_scale
	_board_view.position = Vector2(
		(_board_container.size.x - visible_w) / 2.0,
		(_board_container.size.y - visible_h) / 2.0,
	)

	_board_view.apply_compensated_cell_corner_radius()

	_board_view.apply_inverse_scale_to_auto_mark_btns()


# 清除按钮距棋盘底边的间距（像素）
const _CLEAR_BTN_GAP_BELOW_BOARD: float = 30.0

# ================= 点赞手势反馈（AB: thumb_up） =================
# 6 种手势动画：比心 / 鼓掌 / 吹号 / 双拇指 / 纠正欢呼 / 鹰眼
enum LikeHandAnim { LIKE, CLAP, BLOW_TRUMPET, DOUBLE_THUMBS, CORRECTION_CHEER, HAWK_EYE }
# 枚举 → 动画名
const _LIKE_HAND_ANIM_NAMES: Dictionary = {
	LikeHandAnim.LIKE: "Like",
	LikeHandAnim.CLAP: "Clap",
	LikeHandAnim.BLOW_TRUMPET: "BlowTrumpet",
	LikeHandAnim.DOUBLE_THUMBS: "DoubleThumbs",
	LikeHandAnim.CORRECTION_CHEER: "CorrectionCheer",
	LikeHandAnim.HAWK_EYE: "HawkEye",
}

const _LIKE_HAND_POOL_MAX: int = 5 # 手势节点对象池上限，超出直接 queue_free
var _like_hand_pool: Array[Node2D] = [] # 闲置的手势节点池


# 在屏幕坐标处播一个手势动画（自动取用对象池，播完归还）
func play_like_hand(global_pos: Vector2, anim: LikeHandAnim) -> void:
	var like_hand: Node2D = _acquire_like_hand()
	like_hand.global_position = global_pos
	like_hand.scale = Vector2.ONE * 0.6
	like_hand.z_index = 41
	var anim_player: AnimationPlayer = like_hand.get_node("AnimationPlayer")

	anim_player.animation_finished.connect(
		func(_n: StringName) -> void: _release_like_hand(like_hand),
		CONNECT_ONE_SHOT,
	)
	anim_player.play(_LIKE_HAND_ANIM_NAMES[anim])
	anim_player.seek(0, true)

	if anim == LikeHandAnim.CLAP:
		SoundManager.play(SoundManager.Kind.CLAP)
	elif anim == LikeHandAnim.BLOW_TRUMPET:
		SoundManager.play(SoundManager.Kind.BLOW_TRUMPET)


# 取一个手势节点：优先复用池里的，否则新实例化
func _acquire_like_hand() -> Node2D:
	if not _like_hand_pool.is_empty():
		var node: Node2D = _like_hand_pool.pop_back()
		node.visible = true
		var ap: AnimationPlayer = node.get_node("AnimationPlayer")
		ap.play("RESET")
		ap.seek(0, true)
		ap.stop()
		return node
	var fresh: Node2D = _LIKE_HAND_SCENE.instantiate()
	add_child(fresh)
	return fresh


# 归还手势节点：池满就直接释放
func _release_like_hand(node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	node.visible = false

	if _like_hand_pool.size() >= _LIKE_HAND_POOL_MAX:
		node.queue_free()
		return
	_like_hand_pool.append(node)


# 手势相对格心的默认 Y 偏移（像素，负数向上）
const _LIKE_HAND_Y_OFFSET: float = -80.0


# 在指定格子上方播手势，并按连击飘字与动画类型调整高度和左右边界
func _play_like_hand_on_cell(r: int, c: int, anim: LikeHandAnim) -> void:
	var cell_view: CellView = _board_view.get_cell_view(r, c)
	if cell_view == null:
		return
	var cell_center: Vector2 = cell_view.get_global_transform_with_canvas() * (cell_view.size * 0.5)
	var y_offset: float = _LIKE_HAND_Y_OFFSET

	if ABTestManager.combo_encourage.is_enabled():
		if ABTestManager.combo_encourage.is_follow_cat():
			var has_score: bool = ABTestManager.combo_encourage.has_score_display()
			var has_encourage: bool = _combo_count >= 3
			if has_score and has_encourage:
				var bs: float = _board_view.scale.x if _board_view != null else 1.0
				y_offset -= (
					ComboFeedbackView.BUBBLE_HEIGHT
					+ ComboFeedbackView.BUBBLE_GAP
					+ ComboFeedbackView.CAT_TOP_UNSCALED * bs
					+ ComboFeedbackView.ENCOURAGE_Y_OFFSET_ABOVE_SCORE
				)
			elif has_score:
				y_offset -= ComboFeedbackView.BUBBLE_HEIGHT
		elif ABTestManager.combo_encourage.has_score_display():
			y_offset -= ComboFeedbackView.BUBBLE_HEIGHT
	if anim == LikeHandAnim.HAWK_EYE:
		y_offset -= 40.0
	cell_center.y += y_offset
	var viewport_w: float = get_viewport().get_visible_rect().size.x
	const _LIKE_HAND_MARGIN: float = 185.0
	const _MARGIN_HAWK_EYE: float = 260.0
	const _MARGIN_SPINE: float = 100.0
	var margin: float
	if anim == LikeHandAnim.HAWK_EYE:
		margin = _MARGIN_HAWK_EYE
	elif anim == LikeHandAnim.CORRECTION_CHEER:
		margin = _MARGIN_SPINE
	else:
		margin = _LIKE_HAND_MARGIN
	cell_center.x = clampf(cell_center.x, margin, viewport_w - margin)
	play_like_hand(cell_center, anim)


# 触发点赞手势的三种来源：玩家双击 / 定位道具 / 应用 R1 提示
enum LikeHandTrigger { PLAYER_DOUBLE_TAP, LOCATE, HINT_R1_APPLY }

# 各棋盘尺寸下「点赞」的最小间隔（秒）与最多触发次数
const _LIKE_HAND_CONFIG_BY_SIZE: Dictionary = {
	6: {"min_interval": 30.0, "max_triggers": 2},
	7: {"min_interval": 30.0, "max_triggers": 2},
	8: {"min_interval": 40.0, "max_triggers": 3},
	9: {"min_interval": 40.0, "max_triggers": 3},
	10: {"min_interval": 40.0, "max_triggers": 3},
	11: {"min_interval": 40.0, "max_triggers": 3},
	12: {"min_interval": 40.0, "max_triggers": 3},
}


# 判断这次放对要不要播「点赞」：仅双击来源，且受间隔与次数限制
func _decide_like_hand_for_correct_cat(trigger: int) -> Dictionary:
	var none: Dictionary = {"should_play": false, "anim": LikeHandAnim.LIKE}
	if trigger != LikeHandTrigger.PLAYER_DOUBLE_TAP:
		return none
	var sz: int = _level_config.get("size", 4)
	if not _LIKE_HAND_CONFIG_BY_SIZE.has(sz):
		return none

	if not _like_hand_state["has_seen_first_cat"]:
		return none
	var cfg: Dictionary = _LIKE_HAND_CONFIG_BY_SIZE[sz]
	if _like_hand_state["triggered_count"] >= int(cfg["max_triggers"]):
		return none
	var override: float = ABTestManager.thumb_up.get_like_interval_override(sz)
	var interval: float = override if override > 0.0 else float(cfg["min_interval"])
	if _like_hand_state["in_game_sec"] - _like_hand_state["last_cat_sec"] < interval:
		return none

	if _count_placed_cats(sz) >= sz:
		return none
	return {"should_play": true, "anim": LikeHandAnim.LIKE}


# 记录一次放对：刷新时间戳、标记见过第一只猫、按需累加触发次数
func _record_correct_cat(decision: Dictionary) -> void:
	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]
	_like_hand_state["has_seen_first_cat"] = true
	if decision.get("should_play", false):
		_like_hand_state["triggered_count"] += 1


# 续局时盘上已有猫，把「见过第一只猫」补上
func _seed_like_hand_first_cat_from_board() -> void:
	if _like_hand_state["has_seen_first_cat"]:
		return
	var sz: int = _level_config.get("size", 4)
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				_like_hand_state["has_seen_first_cat"] = true
				return


# 数盘上正式猫的数量
func _count_placed_cats(sz: int) -> int:
	var n: int = 0
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				n += 1
	return n


# 暂停手势时钟（打开设置页 / 插屏时调用）
func pause_like_hand_clock() -> void:
	_like_hand_state["clock_paused"] = true


# 恢复手势时钟
func resume_like_hand_clock() -> void:
	_like_hand_state["clock_paused"] = false


# 判断要不要「鼓掌」：大棋盘、所在区域至少 3 格且从没被打过叉或出过错
func _decide_clap_for_correct_cat(r: int, c: int) -> Dictionary:
	var none: Dictionary = {"should_play": false, "anim": LikeHandAnim.CLAP}

	var sz: int = _level_config.get("size", 4)
	if sz < 6:
		return none

	if _count_placed_cats(sz) >= sz:
		return none
	if _board_view.get_region_cell_count(r, c) < 3:
		return none
	if _board_view.is_region_ever_marked_x(r, c):
		return none
	if _board_view.is_region_ever_errored(r, c):
		return none
	return {"should_play": true, "anim": LikeHandAnim.CLAP}


# 记录鼓掌已播（刷新手势时间戳）
func _record_clap_played() -> void:
	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]


# 棋盘变化时刷新 R4+ 缓存，并重算「漏猫」候选
func _on_board_cell_state_changed_for_r4(_r: int, _c: int, state: int, _source: int = 0) -> void:
	if state == CellState.CAT:
		call_deferred("_refresh_r4_plus_cache")
	call_deferred("_update_missed_cat_candidates")


# 用当前棋盘重算可吹号（R4+）的格子集合
func _refresh_r4_plus_cache() -> void:
	_r4_plus_cells.clear()
	if _puzzle.is_empty():
		return
	var sz: int = _level_config.get("size", 4)
	var regions: Array = _puzzle.get("regions", [])
	var solution: Array = _puzzle.get("solution", [])
	if regions.is_empty() or solution.is_empty():
		return

	var board: Array = _board_view.get_cell_state_folded_board()
	_r4_plus_cells = HintEngine.compute_r4_plus_cells(board, sz, regions, solution)


# ================= 连击（AB: combo_encourage） =================
# 放下一只猫就累加连击与分数，并按需弹连击 / 分数飘字
func _on_board_cell_state_changed_for_combo(r: int, c: int, state: int, _source: int = 0) -> void:
	if state != CellState.CAT:
		return
	if not ABTestManager.combo_encourage.is_enabled():
		return
	_combo_count += 1
	var ab_val: int = ABTestManager.combo_encourage.value()
	var gain: int = 0
	if (
		ab_val == ComboEncourageConfig.VALUE_ENCOURAGE_SCORE
		or ab_val == ComboEncourageConfig.VALUE_ENCOURAGE_IQ
		or ab_val == ComboEncourageConfig.VALUE_ENCOURAGE_FOLLOW
	):
		gain = _calc_combo_point_gain(ab_val)
		_combo_score += gain
	if _combo_feedback_view == null:
		return
	var cell_global_pos: Vector2 = _board_view.get_cell_global_center(r, c)
	if _combo_visual_suppressed:
		_draft_combo_gain_sum += gain
		if gain > 0:
			_combo_feedback_view.show_score_only(cell_global_pos, gain, _combo_score)
		return
	if _combo_count >= 3:
		_combo_feedback_view.show_combo(_combo_count, cell_global_pos, _combo_score, gain)
	elif gain > 0:
		_combo_feedback_view.show_score_only(cell_global_pos, gain, _combo_score)


# 按连击数与 AB 档位算本次得分（有上限）
func _calc_combo_point_gain(ab_val: int) -> int:
	var base: int
	var step: int
	var cap: int
	if ab_val == ComboEncourageConfig.VALUE_ENCOURAGE_IQ:
		base = 6
		step = 2
		cap = 24
	else:
		base = 600
		step = 80
		cap = 1320
	return mini(base + maxi(0, _combo_count - 1) * step, cap)


# 判断要不要「吹号」：该格属于 R4+ 集合且还没放满
func _decide_blow_trumpet_for_correct_cat(r: int, c: int) -> Dictionary:
	var none: Dictionary = {"should_play": false, "anim": LikeHandAnim.BLOW_TRUMPET}
	var sz: int = _level_config.get("size", 4)

	if _count_placed_cats(sz) >= sz:
		return none
	if not _r4_plus_cells.has(Vector2i(r, c)):
		return none
	return {"should_play": true, "anim": LikeHandAnim.BLOW_TRUMPET}


# 记录吹号已播
func _record_blow_trumpet_played() -> void:
	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]


# 错后纠错的观察窗口（秒）
const _CORRECTION_CHEER_WINDOW_SEC: float = 5.0


# 记一次错落事件（区域 + 时刻），用于纠错欢呼判定
func _record_wrong_cat_event(r: int, c: int) -> void:
	if not ABTestManager.thumb_up.is_feedback_enabled(ThumbUpConfig.Feedback.CORRECTION_CHEER):
		return
	var sz: int = _level_config.get("size", 4)
	if sz < 6:
		return
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return
	var region_id: int = int(regions[r][c])
	var events: Array = _like_hand_state["wrong_cat_events"]
	events.append({"region_id": region_id, "time": _like_hand_state["in_game_sec"]})


# 5 秒内在同区域错过的，这次放对就播「纠正欢呼」
func _decide_correction_cheer_for_correct_cat(r: int, c: int) -> Dictionary:
	var none: Dictionary = {"should_play": false, "anim": LikeHandAnim.CORRECTION_CHEER}
	var sz: int = _level_config.get("size", 4)
	if sz < 6:
		return none
	if _count_placed_cats(sz) >= sz:
		return none
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return none
	var region_id: int = int(regions[r][c])
	var now: float = _like_hand_state["in_game_sec"]
	var events: Array = _like_hand_state["wrong_cat_events"]
	for i in range(events.size() - 1, -1, -1):
		var evt: Dictionary = events[i]
		if now - evt["time"] > _CORRECTION_CHEER_WINDOW_SEC:
			break
		if int(evt["region_id"]) == region_id:
			return {"should_play": true, "anim": LikeHandAnim.CORRECTION_CHEER}
	return none


# 丢掉超出观察窗口的错落事件
func _prune_wrong_cat_events() -> void:
	var now: float = _like_hand_state["in_game_sec"]
	var events: Array = _like_hand_state["wrong_cat_events"]
	while not events.is_empty() and now - events[0]["time"] > _CORRECTION_CHEER_WINDOW_SEC:
		events.pop_front()


# 漏猫提示需要等待的时长（秒）
const _MISSED_CAT_DELAY_SEC: float = 5.0


# 扫区域 / 行 / 列，维护「只剩一格且答案就在这」的候选格与首次出现时刻
func _update_missed_cat_candidates() -> void:
	if not ABTestManager.thumb_up.is_feedback_enabled(ThumbUpConfig.Feedback.MISSED_CAT):
		return
	var sz: int = _level_config.get("size", 4)
	if sz < 6:
		return
	var regions: Array = _puzzle.get("regions", [])
	var solution: Array = _puzzle.get("solution", [])
	if regions.is_empty() or solution.is_empty():
		return
	var candidates: Dictionary = _like_hand_state["missed_cat_candidates"]
	_like_hand_state["missed_cat_prev"] = candidates.duplicate()
	var now: float = _like_hand_state["in_game_sec"]

	var valid_cells: Dictionary = {}

	var region_info: Dictionary = {}
	for r in range(sz):
		for c in range(sz):
			var rid: int = int(regions[r][c])
			if not region_info.has(rid):
				region_info[rid] = {"total": 0, "cat_count": 0, "empty_cells": []}
			var info: Dictionary = region_info[rid]
			info["total"] += 1

			var s: int = _board_view.get_cell_state(r, c)
			if s == CellState.CAT:
				info["cat_count"] += 1
			elif CellState.is_blank(s):
				info["empty_cells"].append(Vector2i(r, c))
	for rid: int in region_info:
		var info: Dictionary = region_info[rid]
		if info["total"] < 3:
			continue
		var empties: Array = info["empty_cells"]
		if info["cat_count"] > 0:
			continue
		if empties.size() != 1:
			continue
		var cell: Vector2i = empties[0]
		if solution[cell.x][cell.y]:
			valid_cells["%d_%d" % [cell.x, cell.y]] = true

	for row in range(sz):
		var cat_count: int = 0
		var sole_empty: Vector2i = Vector2i(-1, -1)
		var empty_count: int = 0
		for c in range(sz):
			var s: int = _board_view.get_cell_state(row, c)
			if s == CellState.CAT:
				cat_count += 1
			elif CellState.is_blank(s):
				empty_count += 1
				sole_empty = Vector2i(row, c)
		if cat_count == 0 and empty_count == 1 and solution[sole_empty.x][sole_empty.y]:
			valid_cells["%d_%d" % [sole_empty.x, sole_empty.y]] = true

	for col in range(sz):
		var cat_count: int = 0
		var sole_empty: Vector2i = Vector2i(-1, -1)
		var empty_count: int = 0
		for r in range(sz):
			var s: int = _board_view.get_cell_state(r, col)
			if s == CellState.CAT:
				cat_count += 1
			elif CellState.is_blank(s):
				empty_count += 1
				sole_empty = Vector2i(r, col)
		if cat_count == 0 and empty_count == 1 and solution[sole_empty.x][sole_empty.y]:
			valid_cells["%d_%d" % [sole_empty.x, sole_empty.y]] = true

	for k: String in candidates.keys():
		if not valid_cells.has(k):
			candidates.erase(k)
	for k: String in valid_cells:
		if not candidates.has(k):
			candidates[k] = now


# 该格在候选里挂了 5 秒以上仍没被填 → 播「漏猫」提示
func _decide_missed_cat_for_correct_cat(r: int, c: int) -> Dictionary:
	var none: Dictionary = {"should_play": false, "anim": LikeHandAnim.LIKE}
	var sz: int = _level_config.get("size", 4)
	if sz < 6:
		return none
	if _count_placed_cats(sz) >= sz:
		return none
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return none
	var prev: Dictionary = _like_hand_state["missed_cat_prev"]
	var now: float = _like_hand_state["in_game_sec"]
	var cell_key: String = "%d_%d" % [r, c]
	if not prev.has(cell_key):
		return none
	var first_met: float = float(prev[cell_key])
	if now - first_met < _MISSED_CAT_DELAY_SEC:
		return none
	var anim_id: int = ABTestManager.thumb_up.get_anim_id_for(ThumbUpConfig.Feedback.MISSED_CAT)
	return {"should_play": true, "anim": anim_id as LikeHandAnim}


# 按 AB 给的优先级逐个试，选出唯一要播的手势反馈
func _arbitrate_feedback_for_correct_cat(r: int, c: int) -> Dictionary:
	var none: Dictionary = {
		"should_play": false, "anim": LikeHandAnim.LIKE, "feedback": -1, "pos": "cell"
	}
	var priority_list: Array = ABTestManager.thumb_up.get_priority_list()
	if priority_list.is_empty():
		return none
	for feedback: int in priority_list:
		var decision: Dictionary = _evaluate_single_feedback(feedback, r, c)
		if decision["should_play"]:
			var anim_id: int = ABTestManager.thumb_up.get_anim_id_for(feedback)
			return {
				"should_play": true,
				"anim": anim_id as LikeHandAnim,
				"feedback": feedback,
				"pos": "cell"
			}
	return none


# 分派到各反馈自己的判定函数
func _evaluate_single_feedback(feedback: int, r: int, c: int) -> Dictionary:
	var result: Dictionary
	match feedback:
		ThumbUpConfig.Feedback.BLOW_TRUMPET:
			result = _decide_blow_trumpet_for_correct_cat(r, c)
			return result
		ThumbUpConfig.Feedback.CLAP:
			result = _decide_clap_for_correct_cat(r, c)
			return result
		ThumbUpConfig.Feedback.LIKE:
			result = _decide_like_hand_for_correct_cat(LikeHandTrigger.PLAYER_DOUBLE_TAP)
			return result
		ThumbUpConfig.Feedback.CORRECTION_CHEER:
			result = _decide_correction_cheer_for_correct_cat(r, c)
			return result
		ThumbUpConfig.Feedback.MISSED_CAT:
			result = _decide_missed_cat_for_correct_cat(r, c)
			return result
	return {"should_play": false, "anim": LikeHandAnim.LIKE}


# 固定位置反馈在「规则条底 ~ 棋盘顶」之间的高度比例
const _HAWK_EYE_Y_RATIO: float = 0.57


# 在棋盘上方固定位置播手势（不贴格子的那种反馈）
func _play_feedback_at_fixed_pos(anim: LikeHandAnim) -> void:
	var board_top: float = _board_view.global_position.y
	var rules_bottom: float = _rules_bg.global_position.y + _rules_bg.size.y
	var board_scale_x: float = _board_view.get_global_transform().get_scale().x
	var center_x: float = _board_view.global_position.x + _board_view.size.x * board_scale_x * 0.5
	var center_y: float = rules_bottom + (board_top - rules_bottom) * _HAWK_EYE_Y_RATIO
	play_like_hand(Vector2(center_x, center_y), anim)


# 某种反馈播完后刷新手势时间戳
func _on_feedback_played(feedback: int) -> void:
	match feedback:
		ThumbUpConfig.Feedback.BLOW_TRUMPET:
			_record_blow_trumpet_played()
		ThumbUpConfig.Feedback.CLAP:
			_record_clap_played()
		ThumbUpConfig.Feedback.CORRECTION_CHEER:
			_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]
		ThumbUpConfig.Feedback.MISSED_CAT:
			_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]


# ================= 通关校验与剩余数量 =================
# 核心判定：棋盘放满且无冲突就通关；否则按 AB 检查草稿是否已全对可自动提交
func _validate_board() -> void:
	if _is_complete or _puzzle.is_empty() or not _puzzle.has("regions"):
		return
	var sz: int = _level_config.get("size", 4)
	# 猫数 = 边长且无冲突 → 直接通关
	if QueendokuCore.is_complete(_board_view.get_board(), sz, _puzzle["regions"]):
		_on_game_complete()
		return

	# 草稿模式中 / 没有草稿 / 已有排队中的自动应用 → 这次不再自动提交
	if _draft_mode or not _has_draft_marks() or _pending_post_cat_auto_apply:
		return
	if not ABTestManager.draft_mode.auto_win_on_complete():
		return
	if not _detect_draft_all_correct():
		return

	_pending_post_cat_auto_apply = true
	UIManager.block_input_briefly(self, _CAT_APPEAR_SEC)
	get_tree().create_timer(_CAT_APPEAR_SEC).timeout.connect(
		func() -> void:
			_pending_post_cat_auto_apply = false
			if _is_complete or not visible or not _has_draft_marks():
				return
			if not _detect_draft_all_correct():
				return
			_draft_terminal_state = DraftTerminal.ALL_CORRECT
			_apply_draft_commit()
	)


# 刷新剩余猫数量（数字或进度条模式），并按需播正确提示动画
func _update_remaining() -> void:
	var sz: int = _level_config.get("size", 4)
	var placed: int = 0
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				placed += 1
	if _progress_bar_mode and _progress_count_label != null:
		if _last_placed_count == -1:
			_apply_progress_track_width(sz)
		_progress_count_label.text = (
			"[color=#00B31B]%d[/color][color=#935A5A]/%d[/color]" % [placed, sz]
		)
		_fit_progress_count_font("%d/%d" % [placed, sz])
		if _progress_track_fill != null:
			var target_right: float
			if placed == 0:
				target_right = _progress_track_fill.offset_left
			else:
				var ratio: float = float(placed) / float(sz)
				var visible_width: float = _progress_track_width - _PROGRESS_FILL_DEAD_ZONE
				target_right = (
					_progress_track_fill.offset_left
					+ _PROGRESS_FILL_DEAD_ZONE
					+ visible_width * ratio
				)
			if _last_placed_count != -1 and placed != _last_placed_count:
				var tween := create_tween()
				(
					tween
					. tween_property(_progress_track_fill, "offset_right", target_right, 0.4)
					. set_ease(Tween.EASE_OUT)
					. set_trans(Tween.TRANS_CUBIC)
				)
			else:
				_progress_track_fill.offset_right = target_right
	else:
		if sz >= 10:
			_remaining_label.text = (
				"[font_size=40][color=#00B31B]%d[/color][color=#935A5A]/%d[/color][/font_size]"
				% [placed, sz]
			)
		else:
			_remaining_label.text = (
				"[color=#00B31B]%d[/color][color=#935A5A]/%d[/color]" % [placed, sz]
			)
		if _last_placed_count != -1 and placed != _last_placed_count:
			_anim_correct.play("CorrectPromptStatus")
	_last_placed_count = placed


# 判定刚落下的猫违反了哪条规则，命中就回调 _on_rule_violated
func _try_emit_rule_violation(r: int, c: int) -> void:
	if _puzzle.is_empty() or not _puzzle.has("regions"):
		return
	var regions: Array = _puzzle["regions"]
	var sz: int = _level_config.get("size", 4)
	var placed: Array = []
	var board: Array = _board_view.get_board()
	for rr in range(sz):
		for cc in range(sz):
			if board[rr][cc] == CellState.CAT:
				placed.append(Vector2i(rr, cc))
	var rule: int = QueendokuCore.classify_violation(r, c, placed, regions)
	if rule != QueendokuCore.Rule.NONE:
		_on_rule_violated(rule)


# 规则违规回调，子类覆写（例如每日关弹提示）
func _on_rule_violated(_rule: int) -> void:
	pass


# 让对应那条规则的高亮块呼吸闪两下
func _play_rule_highlight(rule_index: int) -> void:
	var idx: int = rule_index - 1
	if idx < 0 or idx >= _rule_highlights.size():
		return
	_stop_rule_highlight()
	var highlight: TextureRect = _rule_highlights[idx]

	if not is_instance_valid(highlight):
		return
	_rule_active_highlight = highlight
	_rule_tween = create_tween().set_loops(2)
	_rule_tween.tween_method(
		func(t: float) -> void:
			if not is_instance_valid(highlight):
				return
			var phase: float = sin(t * PI)
			highlight.modulate.a = RULE_HL_FLOOR + (1.0 - RULE_HL_FLOOR) * phase,
		0.0,
		1.0,
		RULE_HL_PERIOD
	)
	_rule_tween.finished.connect(_stop_rule_highlight)


# 停掉规则高亮并复位透明度
func _stop_rule_highlight() -> void:
	if _rule_tween != null and _rule_tween.is_valid():
		_rule_tween.kill()
	_rule_tween = null
	if _rule_active_highlight != null:
		if is_instance_valid(_rule_active_highlight):
			_rule_active_highlight.modulate.a = 0.0
		_rule_active_highlight = null


# 放错猫：扣一条命、清零连击、播错误反馈；命尽则稍后进失败流程
func _on_wrong_guess(r: int, c: int) -> void:
	_record_wrong_cat_event(r, c)
	_mistake_count += 1
	_wrong_guess_pending = true
	_combo_count = 0

	GameState.inc_game_total_stat(_game_type(), "invalid_sign_total")
	var lost_index: int = _lives - 1
	_lives = maxi(_lives - 1, 0)

	_board_view.play_error_feedback(r, c)

	# 命尽：所有猫一起哭，并短暂阻塞输入
	if _lives <= 0:
		_board_view.play_cat_cry_loop_all()

		UIManager.block_input_briefly(self, 2.0)
	else:
		_play_wrong_guess_cat_feedback(r, c)

	_animate_heart_lost(lost_index)

	if not ABTestManager.wrong_cat_effect.should_skip_shake():
		_play_screen_shake()

	get_tree().create_timer(0.4).timeout.connect(
		func() -> void:
			_update_remaining()
			_wrong_guess_pending = false
	)

	if _lives <= 0:
		get_tree().create_timer(0.6).timeout.connect(
			func() -> void:
				if not visible:
					return
				_on_game_over()
		)


# 按 AB 决定哪些猫表现沮丧（全部 / 只让与之冲突的猫）
func _play_wrong_guess_cat_feedback(r: int, c: int) -> void:
	if ABTestManager.error_feedback.no_cats_react():
		return
	if not ABTestManager.error_feedback.only_conflicting_cats_react():
		_board_view.play_cat_frustrated_all()
		return

	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		_board_view.play_cat_frustrated_all()
		return
	var sz: int = _level_config.get("size", 4)
	var placed: Array[Vector2i] = []
	var board: Array = _board_view.get_board()
	for rr in range(sz):
		for cc in range(sz):
			if board[rr][cc] == CellState.CAT:
				placed.append(Vector2i(rr, cc))
	var bad: Array[Vector2i] = QueendokuCore.find_conflicting_cats(r, c, placed, regions)
	if not bad.is_empty():
		_board_view.play_cat_frustrated_at(bad)


# 满足条件时送一条命（每局一次、非每日关、只剩 1 命、处在二选一区域等）
func _maybe_trigger_life_plus(r: int, c: int) -> void:
	if _life_plus_used_this_game:
		return
	if not ABTestManager.game_life_rule.is_life_plus_enabled():
		return
	if _game_type() == Tracker.GameType.DAILY:
		return
	if _lives != 1:
		return
	if float(_like_hand_state["in_game_sec"]) <= debug_life_plus_min_sec:
		return
	var sz: int = _level_config.get("size", 4)
	if _count_placed_cats(sz) >= sz:
		return
	if not _was_two_choice_in_region(r, c):
		return
	var first: bool = not GameState.is_life_plus_first_done()
	if not first and randf() >= 0.5:
		return
	_apply_life_plus(first)


# 该格所在区域是否只剩两个没打叉的格子（二选一困境）
func _was_two_choice_in_region(r: int, c: int) -> bool:
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return false
	var sz: int = _level_config.get("size", 4)
	var region_id: int = int(regions[r][c])
	var board: Array = _board_view.get_cell_state_folded_board()
	var non_mark: int = 0
	for rr in range(sz):
		for cc in range(sz):
			if int(regions[rr][cc]) == region_id and board[rr][cc] != CellState.MARK:
				non_mark += 1
	return non_mark == 2


# 加一条命并播「生命 +1」表现，首次触发时记下引导已看
func _apply_life_plus(show_guide: bool) -> void:
	_lives = mini(_lives + 1, 3)
	_life_plus_used_this_game = true
	_refresh_hearts()
	_pose_gained_heart_for_life_plus()
	_play_life_plus_fx(show_guide)
	if show_guide:
		_life_plus_appear1_suppress_thumb = true
		GameState.mark_life_plus_first_done()


# 把新获得那颗心的初始状态摆好（先藏实心、露出遮罩）
func _pose_gained_heart_for_life_plus() -> void:
	var gained: Node = _gained_heart_slot()
	if gained == null:
		return
	if gained.get_node_or_null("AnimLifePlus") == null:
		return
	var dim := gained.get_node_or_null("Dim") as CanvasItem
	if dim != null:
		dim.visible = true

	var full_paths: Array[String] = ["Content/HeartFull", "Content/FishFull"]
	for path in full_paths:
		var full := gained.get_node_or_null(path) as CanvasItem
		if full != null:
			full.modulate = Color(1, 1, 1, 0)
			return


# 播生命 +1 动画：页面级动画优先，其次心槽动画，都没有就飘字兜底
func _play_life_plus_fx(show_guide: bool) -> void:
	var anim_name: String = "Appear1" if show_guide else "Appear2"
	var played: bool = false
	var life_plus_anim := get_node_or_null("AnimLifePlus") as AnimationPlayer
	if life_plus_anim != null:
		life_plus_anim.play(anim_name)
		played = true

	var gained: Node = _gained_heart_slot()
	if gained != null:
		var heart_anim := gained.get_node_or_null("AnimLifePlus") as AnimationPlayer
		if heart_anim != null:
			var gained_ci := gained as CanvasItem
			if gained_ci != null:
				var saved_z: int = gained_ci.z_index
				gained_ci.z_index = 2
				heart_anim.animation_finished.connect(
					func(_n: StringName) -> void:
						if is_instance_valid(gained_ci):
							gained_ci.z_index = saved_z,
					CONNECT_ONE_SHOT,
				)
			heart_anim.play(anim_name)
			played = true
	if not played:
		_spawn_life_plus_float()


# 取刚获得的那颗心（索引 = 生命数 - 1）
func _gained_heart_slot() -> Node:
	var hearts: Array = [_heart1, _heart2, _heart3]
	var idx: int = _lives - 1
	if idx < 0 or idx >= hearts.size():
		return null
	return hearts[idx]


# 兜底表现：在生命槽旁飘一个 +1
func _spawn_life_plus_float() -> void:
	var anchor: Control = _heart3 if _heart3 != null else _heart1
	if anchor == null:
		return
	var label := Label.new()
	label.text = "+1"
	label.add_theme_color_override("font_color", Color(0.3, 0.85, 0.35))
	label.add_theme_font_size_override("font_size", 64)
	label.z_index = 50
	add_child(label)
	label.global_position = anchor.global_position + Vector2(anchor.size.x + 12.0, 0.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(label, "global_position:y", label.global_position.y - 80.0, 0.7)
	tw.tween_property(label, "modulate:a", 0.0, 0.7)
	tw.finished.connect(label.queue_free)


# 失败回调，子类覆写（弹复活 / 跳失败页）
func _on_game_over() -> void:
	pass


# 作弊指令回调，子类覆写
func _on_cheat_command(_cmd_name: String, _args: Array[String]) -> void:
	pass


# ================= 定位道具与提示高亮 =================
# 定位道具：花一个道具，在候选里挑「区域最小」的答案格直接落猫
func _on_locate_btn_pressed() -> void:
	if _entry_anim_playing:
		return
	Tracker.track_btn_click(Tracker.Btn.LOCATE, self)
	_reset_idle_hint()

	_exit_draft_mode_and_clear(ABTestManager.draft_mode.keep_marks_on_manual_exit())
	if _is_complete or _wrong_guess_pending:
		return
	var consumed: bool = _consume_tool(_tool_locate_btn, false)
	GameState.mark_current_level_dirty()
	GameState.mark_dda_tool_or_revive_used()
	if not consumed:
		return
	Tracker.inc_stat("locate_used")
	GameState.inc_game_total_stat(_game_type(), "locate_used_total")
	var sz: int = _level_config.get("size", 4)
	var sol: Array = _puzzle["solution"]
	var regions: Array = _puzzle["regions"]

	# 统计每个区域还有多少格没被排除（已打叉 / 错误叉不算）
	var region_remaining: Dictionary = {}
	for r in range(sz):
		for c in range(sz):
			var st: int = _board_view.get_cell_state(r, c)
			if st != CellState.MARK and st != CellState.ERROR:
				var rid: int = regions[r][c]
				region_remaining[rid] = region_remaining.get(rid, 0) + 1

	# 候选 = 答案格中还没放猫的，按「剩余格数 → 行 → 列」排序后取第一个
	var candidates: Array = []
	for r in range(sz):
		for c in range(sz):
			if sol[r][c] and _board_view.get_cell_state(r, c) != CellState.CAT:
				candidates.append(
					{"r": r, "c": c, "size": region_remaining.get(regions[r][c], sz * sz)}
				)
	if candidates.is_empty():
		return
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				a["size"] < b["size"]
				if a["size"] != b["size"]
				else (a["r"] < b["r"] if a["r"] != b["r"] else a["c"] < b["c"])
			)
	)
	var best: Dictionary = candidates[0]
	var prev_state: int = _board_view.get_cell_state(best["r"], best["c"])
	_board_view.set_cell_state(
		best["r"], best["c"], CellState.CAT, true, true, BoardView.ChangeSource.LOCATE
	)
	_record_cell_change(best["r"], best["c"], prev_state, CellState.CAT)
	_commit_current_step(true, false)

	_record_correct_cat(_decide_like_hand_for_correct_cat(LikeHandTrigger.LOCATE))
	_update_remaining()
	_validate_board()


# 按提示策略在棋盘上叠一层临时格子，演示这一手该怎么走
func _build_hint_highlights(hint: Dictionary) -> void:
	_clear_hint_highlights()
	var s: float = _board_view.scale.x
	var bpos: Vector2 = _board_view.global_position

	_hint_highlight_layer = CanvasLayer.new()
	_hint_highlight_layer.name = "HintHighlightLayer"
	_hint_highlight_layer.layer = 11
	add_child(_hint_highlight_layer)

	var strategy: String = hint.get("strategy", "")
	var key_cell: Vector2i = hint.get("cell", Vector2i(-1, -1))
	var cells_to_show: Array = hint.get("unit_cells", hint.get("highlight_cells", []))

	var highlight_all: bool = strategy == "R2" or strategy == "R3" or strategy == "R4"
	var is_chain: bool = strategy == "R4_chain" or strategy == "R5_chain"
	var is_r1: bool = strategy == "" or strategy == "R1" or strategy == "R1_mark"

	if not is_r1:
		for cell_v in cells_to_show:
			var cv: Vector2i = cell_v as Vector2i
			var temp: CellView = _spawn_temp_cell(cv, s, bpos)
			if is_chain and cv == key_cell and key_cell.x >= 0:
				temp.play_prompt_cat()
			elif highlight_all or (cv == key_cell and key_cell.x >= 0):
				temp.play_hint()

	if strategy == "R1_mark":
		var cat_cell: Vector2i = hint.get("cat_cell", Vector2i(-1, -1))
		if cat_cell.x >= 0:
			var temp_cat: CellView = _spawn_temp_cell(cat_cell, s, bpos)
			temp_cat.play_hint()
		var mark_idx: int = 0
		for cv_v in cells_to_show:
			var cv: Vector2i = cv_v as Vector2i
			var temp_m: CellView = _spawn_temp_cell(cv, s, bpos)
			temp_m.play_r2_preview(mark_idx * 0.06)
			mark_idx += 1

	if strategy == "" or strategy == "R1":
		if key_cell.x >= 0:
			var temp_key: CellView = _spawn_temp_cell(key_cell, s, bpos)
			temp_key.play_hint()
		var mark_idx: int = 0
		for cv_v in cells_to_show:
			var cv: Vector2i = cv_v as Vector2i
			if cv == key_cell:
				continue
			var raw: int = _board_view.get_cell_state(cv.x, cv.y)
			if raw == CellState.CAT:
				var temp_cat: CellView = _spawn_temp_cell(cv, s, bpos)
				temp_cat.play_hint()
			elif CellState.is_blank(raw):
				var temp_m: CellView = _spawn_temp_cell(cv, s, bpos)
				temp_m.play_r2_preview(mark_idx * 0.04)
				mark_idx += 1

	if strategy == "R3" or strategy == "R4":
		var sz_r: int = _level_config.get("size", 4)
		var regs_r: Array = _puzzle["regions"]
		var reg_set_r: Dictionary = {}
		for reg in hint.get("regions", []):
			reg_set_r[reg] = true
		var mark_cells_r: Array[Vector2i] = []
		for row in hint.get("locked_rows", []):
			for c in range(sz_r):
				if (
					not reg_set_r.has(regs_r[row][c])
					and CellState.is_blank(_board_view.get_cell_state(row, c))
				):
					mark_cells_r.append(Vector2i(row, c))
		for col in hint.get("locked_cols", []):
			for r in range(sz_r):
				if (
					not reg_set_r.has(regs_r[r][col])
					and CellState.is_blank(_board_view.get_cell_state(r, col))
				):
					mark_cells_r.append(Vector2i(r, col))
		var mark_idx_r: int = 0
		for cv in mark_cells_r:
			var temp_r: CellView = _spawn_temp_cell(cv, s, bpos)
			temp_r.play_r2_preview(mark_idx_r * 0.06)
			mark_idx_r += 1

	var contra_cells: Array = hint.get("contra_cells", [])
	if not contra_cells.is_empty():
		var contra_idx: int = 0
		for cv_v in contra_cells:
			var cv: Vector2i = cv_v as Vector2i
			var temp_c: CellView = _spawn_temp_cell(cv, s, bpos)
			temp_c.play_r2_preview(contra_idx * 0.08)
			contra_idx += 1

	if strategy == "R2":
		var mark_cells: Array[Vector2i] = _compute_r2_mark_cells(hint)
		mark_cells.sort_custom(
			func(a: Vector2i, b: Vector2i) -> bool:
				if a.x != b.x:
					return a.x < b.x
				return a.y < b.y
		)
		var mark_idx: int = 0
		for mc in mark_cells:
			var temp_m: CellView = _spawn_temp_cell(mc, s, bpos)
			temp_m.play_r2_preview(mark_idx * 0.1)
			mark_idx += 1


# 在提示高亮层里造一个临时格子
func _spawn_temp_cell(cv: Vector2i, s: float, bpos: Vector2) -> CellView:
	return _spawn_temp_cell_in(_hint_highlight_layer, cv, s, bpos)


# 在指定 CanvasLayer 里造临时格子，并复制源格的区域色与非空状态
func _spawn_temp_cell_in(layer: CanvasLayer, cv: Vector2i, s: float, bpos: Vector2) -> CellView:
	var local_rect: Rect2 = _board_view.cell_to_local_rect(cv.x, cv.y)
	var top_left: Vector2 = bpos + local_rect.position * s
	var src: CellView = _board_view.get_cell_view(cv.x, cv.y)
	var temp: CellView = _CELL_SCENE.instantiate() as CellView
	temp.name = "TempCell_%d_%d" % [cv.x, cv.y]
	temp.pivot_offset_ratio = Vector2.ZERO
	temp.pivot_offset = Vector2.ZERO
	temp.position = top_left
	temp.scale = Vector2(s, s)
	temp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(temp)

	temp.set_corner_radius_compensated(s)
	if src != null:
		temp.set_region_color(src.get_region_color())

		var raw: int = src.get_state()
		if not CellState.is_blank(raw):
			var view_state: int = CellState.CAT if raw == CellState.CAT else CellState.MARK
			temp.change_state({"state": view_state, "play_anim": false})
	return temp


# 算 R2 提示要打叉的格子（按行 / 列 / 区域四种模式）
func _compute_r2_mark_cells(hint: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var sz: int = _level_config.get("size", 4)
	var regs: Array = _puzzle["regions"]
	var reg: int = hint.get("region", -1)
	var row: int = hint.get("row", -1)
	var col: int = hint.get("col", -1)
	match hint.get("mode", ""):
		"r2a_row":
			for c in range(sz):
				if regs[row][c] != reg and CellState.is_blank(_board_view.get_cell_state(row, c)):
					result.append(Vector2i(row, c))
		"r2a_col":
			for r in range(sz):
				if regs[r][col] != reg and CellState.is_blank(_board_view.get_cell_state(r, col)):
					result.append(Vector2i(r, col))
		"r2b_row":
			for r in range(sz):
				for c in range(sz):
					if (
						regs[r][c] == reg
						and r != row
						and CellState.is_blank(_board_view.get_cell_state(r, c))
					):
						result.append(Vector2i(r, c))
		"r2b_col":
			for r in range(sz):
				for c in range(sz):
					if (
						regs[r][c] == reg
						and c != col
						and CellState.is_blank(_board_view.get_cell_state(r, c))
					):
						result.append(Vector2i(r, c))
	return result


# 应用 R3/R4 提示：把锁定的行、列上（非相关区域的）空格全部打叉
func _apply_r3_r4_hint() -> void:
	var sz: int = _level_config.get("size", 4)
	var regs: Array = _puzzle["regions"]
	var reg_set: Dictionary = {}
	for reg in _hint_data.get("regions", []):
		reg_set[reg] = true
	for row in _hint_data.get("locked_rows", []):
		for c in range(sz):
			if reg_set.has(regs[row][c]):
				continue
			if CellState.is_blank(_board_view.get_cell_state(row, c)):
				_record_cell_change(row, c, CellState.EMPTY, CellState.MARK)
				_board_view.set_cell_state(
					row, c, CellState.MARK, true, true, BoardView.ChangeSource.HINT
				)
	for col in _hint_data.get("locked_cols", []):
		for r in range(sz):
			if reg_set.has(regs[r][col]):
				continue
			if CellState.is_blank(_board_view.get_cell_state(r, col)):
				_record_cell_change(r, col, CellState.EMPTY, CellState.MARK)
				_board_view.set_cell_state(
					r, col, CellState.MARK, true, true, BoardView.ChangeSource.HINT
				)
	_validate_board()
	_update_remaining()


# ================= 棋盘输入（拖动 / 手势） =================
# 按上棋盘：初始化输入系统后交给手势识别器
func _on_board_cell_drag_start(pos: Vector2) -> void:
	_ensure_input_system()
	_reset_idle_hint()

	var sc: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)

	var sc_state: int = _board_view.get_cell_state(sc.y, sc.x)
	var is_terminal_x_start: bool = sc_state == CellState.ERROR or sc_state == CellState.LOCKED_MARK
	var allow_x_start: bool = (
		not _draft_mode and ABTestManager.tap_feedback.allows_mark_from_error_start()
	)
	if _is_complete or _wrong_guess_pending or (not allow_x_start and is_terminal_x_start):
		return

	_consume_board_actions(_gesture_recognizer.on_drag_start(pos))


# 拖动经过：先处理长按分裂的中断，再交给手势识别器
func _on_board_cell_drag_over(pos: Vector2) -> void:
	if _is_complete or _wrong_guess_pending:
		return

	if _gesture_recognizer == null:
		return

	if _split_pressed_cell.x >= 0:
		var fc: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)
		if Vector2i(fc.y, fc.x) != _split_pressed_cell:
			_release_split_pressed()
	_consume_board_actions(_gesture_recognizer.on_drag_over(pos))


# 抬手：结束手势、提交这一步并计一次步数
func _on_board_cell_drag_end() -> void:
	if _gesture_recognizer == null:
		return
	_gesture_recognizer.on_drag_end()

	_release_split_pressed()

	if _draft_mode:
		return

	var had_change: bool = not _current_step_cells.is_empty()
	_commit_current_step()
	if had_change:
		_count_board_step()


# 结束长按分裂状态，让正按着的格子做抬起表现
func _release_split_pressed() -> void:
	if _split_pressed_cell.x >= 0:
		_board_view.play_mark_release(_split_pressed_cell.x, _split_pressed_cell.y)
		_split_pressed_cell = Vector2i(-1, -1)


# 懒建输入方案；按 AB 决定用普通识别器还是防误触识别器
func _ensure_input_system() -> void:
	if _normal_scheme == null:
		_normal_scheme = BoardInputScheme.create_normal(_board_view)
		_draft_scheme = BoardInputScheme.create_draft(_board_view)

	var want_guard: bool = ABTestManager.swipe_protect.is_enabled()
	if _gesture_recognizer != null and (_gesture_recognizer is SwipeGuardRecognizer) == want_guard:
		return

	var keep_scheme: BoardInputScheme = (
		_gesture_recognizer.active_scheme if _gesture_recognizer != null else _normal_scheme
	)
	if want_guard:
		_gesture_recognizer = SwipeGuardRecognizer.new(_board_view)
	else:
		_gesture_recognizer = BoardGestureRecognizer.new(_board_view)
	_gesture_recognizer.active_scheme = keep_scheme


# 执行手势识别器产出的动作：双击 / 草稿 / 正式打叉擦除，统一经 BoardView 落地
func _consume_board_actions(actions: Array[CellAction]) -> void:
	if actions.is_empty():
		return
	var applied: bool = false
	for a: CellAction in actions:
		if _board_view.is_cell_input_locked(a.row, a.col):
			continue
		if a.kind == CellAction.Kind.DOUBLE_TAP:
			_consume_double_tap(a.row, a.col)
			applied = true
			continue
		if a.kind == CellAction.Kind.SET_DRAFT:
			_set_cell_draft(a.row, a.col, a.state)
			continue

		if _board_view.get_cell_state(a.row, a.col) == CellState.DRAFT_CAT:
			continue

		var split: bool = ABTestManager.tap_feedback.is_press_release_split()
		if split and _split_pressed_cell.x >= 0 and _split_pressed_cell != Vector2i(a.row, a.col):
			_release_split_pressed()
		if a.record:
			_record_cell_change(a.row, a.col, a.before, a.state)

		var use_split_press: bool = (
			split and (a.state == CellState.MARK or a.state == CellState.EMPTY)
		)
		_board_view.set_cell_state(
			a.row, a.col, a.state, a.play_anim, a.show_cat_visual, a.source, use_split_press
		)
		if use_split_press:
			_split_pressed_cell = Vector2i(a.row, a.col)
		if a.before == CellState.MARK and a.state == CellState.EMPTY:
			Tracker.inc_stat("erase_count")
		if a.vibrate >= 0:
			VibrateManager.play_vibrate(a.vibrate)
		applied = true
	if applied:
		_validate_board()
		_update_remaining()


# 双击：答案格放猫，非答案格记为放错，并提交一步
func _consume_double_tap(r: int, c: int) -> void:
	var cur: int = _board_view.get_cell_state(r, c)
	if cur == CellState.CAT:
		return
	var original_before: int = consume_prior_tap_before(r, c, cur)
	var is_cat: bool = _is_solution_cell(r, c)
	if is_cat:
		do_place_cat(r, c, original_before)
	else:
		do_wrong_guess_mark(r, c, original_before)
	_commit_current_step(is_cat, not is_cat)
	_count_board_step()


# 双击会盖掉上一次单击，这里把上一步并回来，保证撤销能回到最初状态
func consume_prior_tap_before(r: int, c: int, fallback: int) -> int:
	var original_before: int = fallback
	var prev_step: StepHistory.StepRecord = _step_history.peek_last()
	if prev_step != null and prev_step.cells.size() == 1:
		var prev_entry: Dictionary = prev_step.cells[0]
		if prev_entry["pos"] == Vector2i(r, c):
			original_before = prev_entry["before"] as int
			_step_history.pop_last()
	return original_before


# 在格子上放猫：记录变更、尝试送命、按优先级选手势反馈
func do_place_cat(r: int, c: int, original_before: int) -> void:
	_record_cell_change(r, c, original_before, CellState.CAT)
	_board_view.set_cell_state(r, c, CellState.CAT)

	_maybe_trigger_life_plus(r, c)

	var fb_result: Dictionary
	if _life_plus_appear1_suppress_thumb:
		_life_plus_appear1_suppress_thumb = false
		fb_result = {"should_play": false, "anim": LikeHandAnim.LIKE, "feedback": -1, "pos": "cell"}
	else:
		fb_result = _arbitrate_feedback_for_correct_cat(r, c)
	if fb_result["should_play"]:
		_on_feedback_played(fb_result["feedback"])
		if fb_result["pos"] == "board_top":
			_play_feedback_at_fixed_pos(fb_result["anim"])
		else:
			_play_like_hand_on_cell(r, c, fb_result["anim"])

	var like_played: bool = (
		fb_result["should_play"] and fb_result["feedback"] == ThumbUpConfig.Feedback.LIKE
	)
	_record_correct_cat(
		{"should_play": like_played, "anim": fb_result.get("anim", LikeHandAnim.LIKE)}
	)


# ================= 自动打叉（auto mark）与锁叉 =================
# 等猫落下动画播完才开始打叉（秒）
const _AUTO_MARK_CAT_APPEAR_DELAY_SEC: float = 0.733
# 逐圈扩散时每圈的间隔（秒）
const _AUTO_MARK_RING_STEP_SEC: float = 3.0 / 60.0
# 自动打叉令牌，自增可作废进行中的异步扩散
var _auto_mark_token: int = 0


# 当前关卡号（转发 GameState）
func _current_level() -> int:
	return GameState.get_current_level()


# 预生成格子节点避免进场卡顿；期间临时关掉容器入场动画
func prewarm_board(size: int) -> void:
	if _board_view == null:
		return
	var board_intro := get_node_or_null("Root") as BoardContainerCell_01
	if board_intro != null:
		board_intro.set_auto_trigger(false)
	await _board_view.prewarm_cells(size)
	if board_intro != null:
		board_intro.set_auto_trigger(true)


# 放下猫后自动把同行 / 同列 / 邻接 / 同色区域打叉（AB: game_auto_mark）
func _on_cell_changed_for_auto_mark(_r: int, _c: int, state: int, source: int) -> void:
	if state != CellState.CAT:
		return
	if source == BoardView.ChangeSource.RESTORE or source == BoardView.ChangeSource.PREFILL:
		return
	var cat: Vector2i = Vector2i(_r, _c)
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return
	var excluded_cells: Array[Vector2i] = []
	if ABTestManager.game_auto_mark.after_cat_enabled_at(_current_level()):
		excluded_cells = QueendokuCore.cells_excluded_by_cat(cat, sz, _puzzle["regions"])
	elif (
		_game_type() == Tracker.GameType.DAILY
		and ABTestManager.game_auto_mark.is_prop_ad_active_for_daily()
	):
		excluded_cells = QueendokuCore.cells_excluded_by_cat_no_region(cat, sz)
	if excluded_cells.is_empty():
		return
	_spread_auto_cross(cat, _AUTO_MARK_CAT_APPEAR_DELAY_SEC, excluded_cells)


# 等打叉动画播一会儿再开始锁叉（秒）
const _LOCK_X_AFTER_MARK_DELAY_SEC: float = 29.0 / 60.0
# 逐个锁叉的间隔（秒）
const _LOCK_X_STEP_SEC: float = 0.1
# 锁叉令牌，自增可作废进行中的异步锁叉
var _lock_x_token: int = 0


# 某条约束上的格子全打上叉后，把这些叉锁成不可改（AB: lock_x）
func _on_cell_changed_for_lock_x(r: int, c: int, state: int, source: int) -> void:
	if source == BoardView.ChangeSource.RESTORE or source == BoardView.ChangeSource.PREFILL:
		return
	if ABTestManager == null or ABTestManager.game_auto_mark == null:
		return
	if not ABTestManager.game_auto_mark.is_lock_x_enabled_at(_current_level()):
		return

	if state != CellState.CAT and state != CellState.MARK and state != CellState.ERROR:
		return
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return

	var cats: Array[Vector2i] = []
	for rr in range(sz):
		for cc in range(sz):
			if _board_view.get_cell_state(rr, cc) == CellState.CAT:
				cats.append(Vector2i(rr, cc))
	if cats.is_empty():
		return

	var qualified_sets: Array = []
	for cat: Vector2i in cats:
		var sets: Array = QueendokuCore.constraint_cells_for_cat(cat, sz, _puzzle["regions"])
		for set_idx in range(sets.size()):
			var cell_set: Array = sets[set_idx]
			var all_cross: bool = true
			for cell: Vector2i in cell_set:
				if not CellState.is_cross(_board_view.get_cell_state(cell.x, cell.y)):
					all_cross = false
					break
			if not all_cross:
				continue
			var marks: Array[Vector2i] = []
			for cell: Vector2i in cell_set:
				if _board_view.get_cell_state(cell.x, cell.y) == CellState.MARK:
					marks.append(cell)
			if marks.is_empty():
				continue
			qualified_sets.append({"set_type": set_idx, "cat": cat, "marks": marks})
	if qualified_sets.is_empty():
		return

	_lock_x_token += 1
	if state == CellState.CAT:
		var merged: Array[Vector2i] = []
		var seen: Dictionary = {}
		for info in qualified_sets:
			for m: Vector2i in info["marks"]:
				var key: String = "%d:%d" % [m.x, m.y]
				if not seen.has(key):
					seen[key] = true
					merged.append(m)
		_spread_status_lock_from_cat(Vector2i(r, c), merged)
	else:
		for info in qualified_sets:
			var ordered: Array[Vector2i] = _sort_marks_for_set(
				info["set_type"], info["cat"], info["marks"]
			)
			_spread_status_lock_ordered(ordered)


# 以猫为中心按曼哈顿距离逐圈锁叉
func _spread_status_lock_from_cat(cat: Vector2i, marks: Array[Vector2i]) -> void:
	if marks.is_empty():
		return
	var token: int = _lock_x_token
	var rings: Dictionary = {}
	for m: Vector2i in marks:
		var d: int = abs(m.x - cat.x) + abs(m.y - cat.y)
		if not rings.has(d):
			rings[d] = []
		rings[d].append(m)
	for m: Vector2i in marks:
		_board_view.set_cell_input_locked(m.x, m.y, true)
	await get_tree().create_timer(_AUTO_MARK_CAT_APPEAR_DELAY_SEC).timeout
	if token != _lock_x_token:
		return
	var dists: Array = rings.keys()
	dists.sort()
	for d: int in dists:
		for m: Vector2i in rings[d]:
			if _board_view.get_cell_state(m.x, m.y) == CellState.MARK:
				_board_view.lock_mark(m.x, m.y, "StatusLock")
		await get_tree().create_timer(_LOCK_X_STEP_SEC).timeout
		if token != _lock_x_token:
			return


# 按给定顺序逐个锁叉
func _spread_status_lock_ordered(ordered: Array[Vector2i]) -> void:
	if ordered.is_empty():
		return
	var token: int = _lock_x_token
	for m: Vector2i in ordered:
		_board_view.set_cell_input_locked(m.x, m.y, true)
	await get_tree().create_timer(_LOCK_X_AFTER_MARK_DELAY_SEC).timeout
	if token != _lock_x_token:
		return
	for m: Vector2i in ordered:
		if _board_view.get_cell_state(m.x, m.y) == CellState.MARK:
			_board_view.lock_mark(m.x, m.y, "StatusLock")
		await get_tree().create_timer(_LOCK_X_STEP_SEC).timeout
		if token != _lock_x_token:
			return


# 按约束类型排序待锁的叉：行从下往上 / 列从左往右 / 八邻接顺时针 / 同色按对角线
func _sort_marks_for_set(set_type: int, cat: Vector2i, marks: Array[Vector2i]) -> Array[Vector2i]:
	var sorted: Array[Vector2i] = marks.duplicate()
	match set_type:
		0:
			sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
		1:
			sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		2:
			sorted.sort_custom(
				func(a: Vector2i, b: Vector2i) -> bool:
					return _neighbor_clockwise_rank(a, cat) < _neighbor_clockwise_rank(b, cat)
			)
		3:
			sorted.sort_custom(
				func(a: Vector2i, b: Vector2i) -> bool: return (a.y - a.x) < (b.y - b.x)
			)
	return sorted


# 八邻接格相对猫的顺时针序号（0~7），非邻接返回 999
func _neighbor_clockwise_rank(cell: Vector2i, cat: Vector2i) -> int:
	var dx: int = cell.x - cat.x
	var dy: int = cell.y - cat.y
	if dx == 1 and dy == -1:
		return 0
	if dx == 0 and dy == -1:
		return 1
	if dx == -1 and dy == -1:
		return 2
	if dx == -1 and dy == 0:
		return 3
	if dx == -1 and dy == 1:
		return 4
	if dx == 0 and dy == 1:
		return 5
	if dx == 1 and dy == 1:
		return 6
	if dx == 1 and dy == 0:
		return 7
	return 999


# 自动打叉动画：先锁输入并预置，再按距离逐圈显现，最后解锁输入
func _spread_auto_cross(
	cat: Vector2i, initial_delay: float, excluded_cells: Array[Vector2i]
) -> void:
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return
	var token: int = _auto_mark_token
	var rings: Dictionary = {}
	var locked_cells: Array[Vector2i] = []
	for cell: Vector2i in excluded_cells:
		if _board_view.get_cell_state(cell.x, cell.y) != CellState.EMPTY:
			continue
		var d: int = abs(cell.x - cat.x) + abs(cell.y - cat.y)
		if not rings.has(d):
			rings[d] = []
		rings[d].append(cell)
		locked_cells.append(cell)
	if rings.is_empty():
		return

	for cell: Vector2i in locked_cells:
		_board_view.set_cell_input_locked(cell.x, cell.y, true)

	for cell: Vector2i in locked_cells:
		_board_view.preset_auto_cross(cell.x, cell.y)

	_on_auto_mark_preset_done()
	if initial_delay > 0.0:
		await get_tree().create_timer(initial_delay).timeout
		if token != _auto_mark_token:
			return
	var dists: Array = rings.keys()
	dists.sort()
	for d: int in dists:
		for cell: Vector2i in rings[d]:
			_board_view.play_pending_auto_cross_appear(cell.x, cell.y)
		await get_tree().create_timer(_AUTO_MARK_RING_STEP_SEC).timeout
		if token != _auto_mark_token:
			return

	for cell: Vector2i in locked_cells:
		_board_view.set_cell_input_locked(cell.x, cell.y, false)


# 打叉预置完成的钩子，子类覆写（新手引导用）
func _on_auto_mark_preset_done() -> void:
	pass


# 续局恢复时，把已有猫本该打的叉一次性补齐
func complete_auto_mark_for_restore() -> void:
	if ABTestManager == null or ABTestManager.game_auto_mark == null:
		return
	if not ABTestManager.game_auto_mark.after_cat_enabled_at(_current_level()):
		return
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return
	for r: int in range(sz):
		for c: int in range(sz):
			if _board_view.get_cell_state(r, c) != CellState.CAT:
				continue
			for cell: Vector2i in QueendokuCore.cells_excluded_by_cat(Vector2i(r, c), sz, regions):
				if _board_view.get_cell_state(cell.x, cell.y) == CellState.EMPTY:
					_board_view.set_cell_state(
						cell.x, cell.y, CellState.MARK, false, true, BoardView.ChangeSource.RESTORE
					)


# 轴自动打叉的逐格间隔（秒）
const _AUTO_MARK_AXIS_STEP_SEC: float = 4.0 / 60.0

# 正在播动画的轴（键 "轴:序号"），避免重复触发
var _axis_busy_set: Dictionary = {}


# 轴的字典键：轴类型 + 序号
func _axis_key(axis: int, idx: int) -> String:
	return "%d:%d" % [axis, idx]


# 点行 / 列外侧圆点：整条轴打叉或取消（AB: dot_toggle）
func _on_axis_auto_mark_pressed(axis: int, idx: int, is_marked_before: bool) -> void:
	if ABTestManager == null or ABTestManager.game_auto_mark == null:
		return
	if not ABTestManager.game_auto_mark.is_dot_toggle_enabled_at(_current_level()):
		return
	if _axis_busy_set.has(_axis_key(axis, idx)):
		return
	if is_marked_before:
		_spread_axis_uncross(axis, idx)
	else:
		var sz: int = _level_config.get("size", 0)
		if sz <= 0:
			return

		var targets: Array[Vector2i] = []
		if axis == 1:
			for rr in range(sz):
				if _board_view.get_cell_state(rr, idx) == CellState.EMPTY:
					targets.append(Vector2i(rr, idx))
		else:
			for cc in range(sz):
				if _board_view.get_cell_state(idx, cc) == CellState.EMPTY:
					targets.append(Vector2i(idx, cc))
		if targets.is_empty():
			return
		_spread_axis_cross(axis, idx, targets)


# 整条轴逐格打叉的动画
func _spread_axis_cross(axis: int, idx: int, targets: Array[Vector2i]) -> void:
	var token: int = _auto_mark_token
	var key: String = _axis_key(axis, idx)
	_axis_busy_set[key] = true

	var sorted: Array = targets.duplicate()
	if axis == 1:
		sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	else:
		sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y)

	for cell: Vector2i in sorted:
		_board_view.set_cell_input_locked(cell.x, cell.y, true)
	for cell: Vector2i in sorted:
		if token != _auto_mark_token:
			_axis_busy_set.erase(key)
			return
		if _board_view.get_cell_state(cell.x, cell.y) == CellState.EMPTY:
			_board_view.play_auto_cross(cell.x, cell.y)
		await get_tree().create_timer(_AUTO_MARK_AXIS_STEP_SEC).timeout
	if token != _auto_mark_token:
		_axis_busy_set.erase(key)
		return
	for cell: Vector2i in sorted:
		_board_view.set_cell_input_locked(cell.x, cell.y, false)
	_board_view.refresh_axis_auto_mark_state(axis, idx, true)
	_axis_busy_set.erase(key)


# 整条轴逐格取消叉的动画
func _spread_axis_uncross(axis: int, idx: int) -> void:
	var token: int = _auto_mark_token
	var key: String = _axis_key(axis, idx)
	_axis_busy_set[key] = true
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		_axis_busy_set.erase(key)
		return

	var targets: Array[Vector2i] = []
	if axis == 1:
		for r in range(sz):
			if _board_view.get_cell_state(r, idx) == CellState.MARK:
				targets.append(Vector2i(r, idx))
		targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x)
	else:
		for c in range(sz):
			if _board_view.get_cell_state(idx, c) == CellState.MARK:
				targets.append(Vector2i(idx, c))
		targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y > b.y)
	if targets.is_empty():
		_board_view.refresh_axis_auto_mark_state(axis, idx, false)
		_axis_busy_set.erase(key)
		return
	for cell: Vector2i in targets:
		_board_view.set_cell_input_locked(cell.x, cell.y, true)
	for cell: Vector2i in targets:
		if token != _auto_mark_token:
			_axis_busy_set.erase(key)
			return
		if _board_view.get_cell_state(cell.x, cell.y) == CellState.MARK:
			_board_view.play_auto_uncross(cell.x, cell.y)
		await get_tree().create_timer(_AUTO_MARK_AXIS_STEP_SEC).timeout
	if token != _auto_mark_token:
		_axis_busy_set.erase(key)
		return
	for cell: Vector2i in targets:
		_board_view.set_cell_input_locked(cell.x, cell.y, false)
	_board_view.refresh_axis_auto_mark_state(axis, idx, false)
	_axis_busy_set.erase(key)


# 棋盘变化后刷新该行 / 列圆点状态（还有空格=未打叉，没空格=已打叉）
func _on_cell_changed_refresh_axis_btn(r: int, c: int, _state: int, _source: int) -> void:
	if ABTestManager == null or ABTestManager.game_auto_mark == null:
		return
	if not ABTestManager.game_auto_mark.is_dot_toggle_enabled_at(_current_level()):
		return
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return

	for axis_idx in [Vector2i(0, r), Vector2i(1, c)]:
		var axis: int = axis_idx.x
		var idx: int = axis_idx.y
		if _axis_busy_set.has(_axis_key(axis, idx)):
			continue
		var has_empty: bool = false
		if axis == 1:
			for rr in range(sz):
				if _board_view.get_cell_state(rr, idx) == CellState.EMPTY:
					has_empty = true
					break
		else:
			for cc in range(sz):
				if _board_view.get_cell_state(idx, cc) == CellState.EMPTY:
					has_empty = true
					break
		var is_marked: bool = _board_view.is_axis_auto_mark_marked(axis, idx)

		if has_empty and is_marked:
			_board_view.refresh_axis_auto_mark_state(axis, idx, false)
		elif not has_empty and not is_marked:
			_board_view.refresh_axis_auto_mark_state(axis, idx, true)


# ================= 步历史与撤销 =================
# 把格子标成错误叉，并走进错误反馈流程
func do_wrong_guess_mark(r: int, c: int, original_before: int) -> void:
	_record_cell_change(r, c, original_before, CellState.MARK)
	_board_view.set_cell_state(r, c, CellState.MARK)
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)
	_try_emit_rule_violation(r, c)
	_on_wrong_guess(r, c)


# 把一次格子变更累积进「当前这一步」
func _record_cell_change(r: int, c: int, before: int, after: int) -> void:
	_current_step_cells.append({"pos": Vector2i(r, c), "before": before, "after": after})


# 结束当前步：写进步历史、清空累积、复位撤销游标
func _commit_current_step(is_cat: bool = false, is_wrong_guess: bool = false) -> void:
	if _current_step_cells.is_empty():
		return
	var step := StepHistory.StepRecord.new()
	step.cells = _current_step_cells.duplicate()
	step.is_cat_placement = is_cat
	step.is_wrong_guess = is_wrong_guess
	_step_history.push_step(step)
	_current_step_cells.clear()
	_highlight_cursor = -1
	_refresh_undo_btn_state()


# 计一次步数（本局统计 + 累计统计）
func _count_board_step() -> void:
	Tracker.inc_stat("step_used")
	GameState.inc_game_total_stat(_game_type(), "step_total")


# 刷新撤销按钮状态，子类覆写
func _refresh_undo_btn_state() -> void:
	pass


# 初始化撤销系统：恢复步历史、接按钮信号、按 AB 决定显示与底部排版
func _setup_undo_system(restore_data: Array = []) -> void:
	_undo_executor.cancel()
	_step_history.clear()
	_current_step_cells.clear()
	_highlight_cursor = -1
	if not restore_data.is_empty():
		_step_history.deserialize(restore_data)
	_undo_executor.setup(_board_view, self, self)
	var undo_enabled: bool = ABTestManager.undo_btn.is_enabled()
	if _tool_undo_btn != null:
		_tool_undo_btn.visible = undo_enabled
		var tb := _tool_undo_btn as ToolButton
		if tb != null and not tb.pressed.is_connected(_on_undo_btn_pressed):
			tb.pressed.connect(_on_undo_btn_pressed)
	_layout_bottom_tools(undo_enabled)
	_sync_tools_from_state()
	_refresh_undo_btn_state()


# 底部道具排版：两个（无撤销）或三个（有撤销）
func _layout_bottom_tools(three_tools: bool) -> void:
	if three_tools:
		if _tool_locate_btn != null:
			_tool_locate_btn.offset_left = 115.0
			_tool_locate_btn.offset_right = 325.0
		if _tool_hint_btn != null:
			_tool_hint_btn.offset_left = 435.0
			_tool_hint_btn.offset_right = 645.0
		if _tool_undo_btn != null:
			_tool_undo_btn.offset_left = 755.0
			_tool_undo_btn.offset_right = 965.0
	else:
		if _tool_locate_btn != null:
			_tool_locate_btn.offset_left = 250.0
			_tool_locate_btn.offset_right = 460.0
		if _tool_hint_btn != null:
			_tool_hint_btn.offset_left = 620.0
			_tool_hint_btn.offset_right = 830.0


# 撤销按钮：真撤销（回退步历史）或只高亮回顾，两种模式都要花道具
func _on_undo_btn_pressed() -> void:
	if _entry_anim_playing or _hint_cooldown:
		return
	Tracker.track_btn_click("undo", self)
	_reset_idle_hint()
	_exit_draft_mode_and_clear(ABTestManager.draft_mode.keep_marks_on_manual_exit())
	if _is_complete or _wrong_guess_pending:
		return
	if _auto_completing:
		return
	if _undo_executor.is_executing():
		if ABTestManager.undo_btn.is_highlight_only():
			pass
		else:
			Toast.popup("UNDO_IN_PROGRESS", self)
			return
	if not _step_history.has_step():
		if ABTestManager.undo_btn.is_undo_mode():
			Toast.popup("UNDO_CANNOT_UNDO", self)
		else:
			Toast.popup("UNDO_NO_STEP", self)
		return
	var step: StepHistory.StepRecord = _step_history.peek_last()
	if step == null:
		return

	if ABTestManager.undo_btn.is_undo_mode():
		var target_step: StepHistory.StepRecord = null
		var skip_count: int = 0
		for i in range(_step_history.size() - 1, -1, -1):
			var s: StepHistory.StepRecord = _step_history.peek_at(i)
			if s == null or s.is_wrong_guess:
				continue
			var has_revertible: bool = false
			for entry: Dictionary in s.cells:
				var cv: CellView = _board_view.get_cell_view(entry["pos"].x, entry["pos"].y)
				var cur: int = cv.get_state() if cv != null else CellState.EMPTY
				if cur != CellState.CAT and cur != CellState.ERROR:
					has_revertible = true
					break
			if has_revertible:
				target_step = s
				skip_count = _step_history.size() - 1 - i
				break
		if target_step == null:
			Toast.popup("UNDO_CANNOT_UNDO", self)
			return
		var consumed: bool = _consume_tool(_tool_undo_btn)
		if not consumed:
			return
		for j in range(skip_count + 1):
			_step_history.pop_last()
		_refresh_undo_btn_state()
		for entry: Dictionary in target_step.cells:
			var pos: Vector2i = entry["pos"]
			var before_state: int = entry["before"]
			var cv: CellView = _board_view.get_cell_view(pos.x, pos.y)
			var current: int = cv.get_state() if cv != null else CellState.EMPTY
			if current == CellState.CAT or current == CellState.ERROR:
				continue
			_board_view.set_cell_state(
				pos.x, pos.y, before_state, true, true, BoardView.ChangeSource.UNDO
			)
		_validate_board()
		_update_remaining()
	else:
		if _highlight_cursor == -2:
			Toast.popup("UNDO_NO_STEP", self)
			return
		var prev_cursor: int = _highlight_cursor
		if _highlight_cursor == -1:
			_highlight_cursor = _step_history.size() - 1
		else:
			_highlight_cursor -= 1
		if _highlight_cursor < 0:
			_highlight_cursor = -2
			Toast.popup("UNDO_NO_STEP", self)
			return
		var cur_step: StepHistory.StepRecord = _step_history.peek_at(_highlight_cursor)
		if cur_step == null:
			Toast.popup("UNDO_NO_STEP", self)
			return
		var highlight_step := StepHistory.StepRecord.new()
		highlight_step.cells = cur_step.cells.duplicate()

		if cur_step.is_cat_placement or cur_step.is_wrong_guess:
			var has_non_cat_cell: bool = false
			for entry: Dictionary in cur_step.cells:
				if entry["after"] != CellState.CAT:
					has_non_cat_cell = true
					break
			if not has_non_cat_cell:
				var found_prev: bool = false
				for i in range(_highlight_cursor - 1, -1, -1):
					var s: StepHistory.StepRecord = _step_history.peek_at(i)
					if s == null:
						continue
					highlight_step.cells.append_array(s.cells)
					if not s.is_cat_placement and not s.is_wrong_guess:
						_highlight_cursor = i
						found_prev = true
						break
				if not found_prev:
					_highlight_cursor = prev_cursor
					Toast.popup("UNDO_NO_STEP", self)
					return
		var consumed: bool = _consume_tool(_tool_undo_btn)
		if not consumed:
			_highlight_cursor = prev_cursor
			return
		_undo_executor.cancel()
		var cell_count: int = highlight_step.cells.size()
		var duration: float = ABTestManager.undo_btn.get_highlight_duration(cell_count)
		_undo_executor.execute(highlight_step, UndoHighlightExecutor.Mode.HIGHLIGHT_ONLY, duration)
		if not _undo_executor.execution_finished.is_connected(_on_undo_execution_finished):
			_undo_executor.execution_finished.connect(_on_undo_execution_finished, CONNECT_ONE_SHOT)


# 撤销高亮播完：重新校验棋盘并刷新界面
func _on_undo_execution_finished() -> void:
	_validate_board()
	_update_remaining()
	_refresh_undo_btn_state()


# ================= 草稿模式（AB: draft_mode） =================
# 取草稿模式 AB 变体（0 表示没开启）
func _get_draft_variant() -> int:
	if ABTestManager == null or ABTestManager.draft_mode == null:
		return 0
	return ABTestManager.draft_mode.value()


# 草稿是否已解锁：变体非 0 且关卡号 ≥ 21
func _is_draft_unlocked() -> bool:
	if _get_draft_variant() == 0:
		return false
	return GameState.get_current_level() >= 21


# 草稿按钮：在进入 / 退出草稿模式之间切换
func _on_draft_btn_pressed() -> void:
	if _entry_anim_playing:
		return
	if _is_complete or _wrong_guess_pending:
		return
	if not _is_draft_unlocked():
		return

	if _draft_mode:
		var keep: bool = ABTestManager.draft_mode.keep_marks_on_manual_exit()
		_exit_draft_mode_and_clear(keep)
	else:
		_enter_draft_mode()


# 草稿「应用」按钮：把草稿落成正式标记
func _on_apply_btn_pressed() -> void:
	if _entry_anim_playing or _is_complete or _wrong_guess_pending:
		return
	if not _draft_mode:
		return
	_apply_draft_commit()


# 退出草稿时上报：停留时长与草稿正确 / 错误数量
func _record_draft_exit_stats() -> void:
	var gt: String = _game_type()
	if _draft_enter_ms > 0:
		var dur_ms: int = Time.get_ticks_msec() - _draft_enter_ms
		if dur_ms > 0:
			GameState.inc_game_total_stat(gt, "draft_time_total_ms", dur_ms)
	_draft_enter_ms = 0
	var wrong_count: int = 0
	var correct_count: int = 0
	var draft_marks: Dictionary = _collect_draft_marks()
	for key in draft_marks.keys():
		var pos: Vector2i = key as Vector2i
		var mark: int = draft_marks[key]
		var is_sol: bool = _is_solution_cell(pos.x, pos.y)
		if mark == CellState.DRAFT_CAT:
			if is_sol:
				correct_count += 1
			else:
				wrong_count += 1
		elif mark == CellState.DRAFT_CROSS:
			if is_sol:
				wrong_count += 1

	if wrong_count > 0:
		GameState.inc_game_total_stat(gt, "draft_error_total", wrong_count)
	elif correct_count > 0:
		GameState.inc_game_total_stat(gt, "draft_correct_total", correct_count)


# 进入草稿模式：切输入方案、快照正式标记、换铅笔图标、按需露出应用按钮
func _enter_draft_mode() -> void:
	_draft_mode = true

	_ensure_input_system()
	_gesture_recognizer.active_scheme = _draft_scheme
	_gesture_recognizer.reset_for_scheme_switch()

	_draft_pre_enter_real_marks = _snapshot_real_marks()

	GameState.inc_game_total_stat(_game_type(), "draft_used_total")
	_draft_enter_ms = Time.get_ticks_msec()
	_draft_root = Vector2i(-1, -1)
	_draft_terminal_state = DraftTerminal.NORMAL

	if _draft_btn == null:
		return
	if _draft_btn_bg != null:
		_draft_btn_bg.self_modulate = Color(0.95, 0.5, 0.15, 1.0)
	if _draft_btn_icon != null:
		_draft_btn_icon.texture = _PENCIL_TEX_SELECTED

	if ABTestManager.draft_mode.has_independent_apply_button() and _apply_btn != null:
		_apply_btn.visible = true
		_show_apply_btn_animated()

	if _draft_anim != null:
		_draft_anim.play("Appear")
	_refresh_draft_terminal_state()


# 动画显示「应用」按钮
func _show_apply_btn_animated() -> void:
	if _apply_btn == null:
		return
	if _apply_anim != null and _apply_anim.has_animation("Appear"):
		if _apply_anim.is_playing() and _apply_anim.current_animation == "Appear":
			return
		_apply_anim.play("Appear")
	else:
		_apply_btn.modulate = Color.WHITE


# 动画隐藏「应用」按钮
func _hide_apply_btn_animated() -> void:
	if _apply_btn == null:
		return
	if _apply_anim != null and _apply_anim.has_animation("Disappear") and _apply_btn.visible:
		_apply_anim.play("Disappear")
		_apply_anim.animation_finished.connect(
			func(anim_name: StringName) -> void:
				if anim_name == &"Disappear" and _apply_btn != null:
					_apply_btn.visible = false,
			CONNECT_ONE_SHOT
		)
	else:
		_apply_btn.visible = false


# 退出草稿模式：切回普通输入、还原按钮外观，必要时清掉草稿标记（会落存档）
func _exit_draft_mode_and_clear(keep_marks: bool = false, skip_cell_clear: bool = false) -> void:
	var was_in_draft: bool = _draft_mode
	_draft_mode = false

	if was_in_draft:
		_record_draft_exit_stats()

	if _gesture_recognizer != null:
		_gesture_recognizer.active_scheme = _normal_scheme
		_gesture_recognizer.reset_for_scheme_switch()

	_draft_root = Vector2i(-1, -1)
	_draft_terminal_state = DraftTerminal.NORMAL

	if _draft_btn != null:
		if _draft_btn_bg != null:
			_draft_btn_bg.self_modulate = Color.WHITE
		if _draft_btn_icon != null:
			_draft_btn_icon.texture = _PENCIL_TEX_DEFAULT
		_set_draft_btn_text("?", 80)
	if _draft_bubble != null:
		_draft_bubble.visible = false

	if _apply_btn != null:
		if was_in_draft:
			_hide_apply_btn_animated()
		else:
			_apply_btn.visible = false

	if keep_marks:
		return

	if _board_view == null or skip_cell_clear:
		_on_draft_changed_for_persist(true)
		return

	var animate_cross: bool = was_in_draft
	var draft_marks: Dictionary = _collect_draft_marks()
	for key in draft_marks.keys():
		var pos: Vector2i = key as Vector2i
		var cell_view: CellView = _board_view.get_cell_view(pos.x, pos.y)
		if cell_view == null:
			continue
		if animate_cross and draft_marks[key] == CellState.DRAFT_CROSS:
			cell_view.play_draft_cross_disappear()
		else:
			cell_view.change_state({"state": CellState.EMPTY, "play_anim": false})

	_on_draft_changed_for_persist(true)


# 设置单格草稿，维护草稿起点，并调度终局检查与持久化
func _set_cell_draft(r: int, c: int, mark: int) -> void:
	var key := Vector2i(r, c)
	var cell_view: CellView = _board_view.get_cell_view(r, c) if _board_view != null else null
	if cell_view == null:
		return

	var prev_mark: int = cell_view.get_state()
	cell_view.change_state({"state": mark, "play_anim": false})

	if mark == CellState.DRAFT_CAT and _draft_root == Vector2i(-1, -1):
		_draft_root = key
	elif prev_mark == CellState.DRAFT_CAT and mark != CellState.DRAFT_CAT and key == _draft_root:
		_draft_root = Vector2i(-1, -1)
	_schedule_draft_terminal_check()
	_on_draft_changed_for_persist()


# 收集全盘草稿格 → {Vector2i: 状态}
func _collect_draft_marks() -> Dictionary:
	var out: Dictionary = {}
	if _board_view == null:
		return out
	var sz: int = _level_config.get("size", 0)
	for r in range(sz):
		for c in range(sz):
			var s: int = _board_view.get_cell_state(r, c)
			if CellState.is_draft(s):
				out[Vector2i(r, c)] = s
	return out


# 盘上是否还有草稿
func _has_draft_marks() -> bool:
	if _board_view == null:
		return false
	var sz: int = _level_config.get("size", 0)
	for r in range(sz):
		for c in range(sz):
			if CellState.is_draft(_board_view.get_cell_state(r, c)):
				return true
	return false


# 草稿变化的持久化钩子，子类覆写（写快照）
func _on_draft_changed_for_persist(_immediate: bool = false) -> void:
	pass


# 草稿改动后延迟多久做终局检查（秒）
const _DRAFT_TERMINAL_CHECK_DELAY: float = 0.6


# 延迟做一次草稿终局检查（带令牌，连续改动只算最后一次）
func _schedule_draft_terminal_check() -> void:
	if not _draft_mode:
		return
	_draft_check_token += 1
	var token: int = _draft_check_token
	get_tree().create_timer(_DRAFT_TERMINAL_CHECK_DELAY).timeout.connect(
		func() -> void:
			if token != _draft_check_token:
				return
			if not _draft_mode:
				return
			_refresh_draft_terminal_state()
	)


# 刷新草稿结局：全对时按变体露出应用按钮或直接自动应用
func _refresh_draft_terminal_state() -> void:
	if not _draft_mode or _board_view == null or _puzzle.is_empty():
		return
	var next_state: int = DraftTerminal.NORMAL
	if _detect_draft_all_correct():
		next_state = DraftTerminal.ALL_CORRECT
	_draft_terminal_state = next_state
	var variant: int = _get_draft_variant()

	match next_state:
		DraftTerminal.ALL_CORRECT:
			if variant == ABTestManager.draft_mode.VALUE_APPLY_INPLACE:
				if _apply_btn != null:
					_apply_btn.visible = true
					_show_apply_btn_animated()
			elif ABTestManager.draft_mode.auto_win_on_complete():
				_apply_draft_commit()
				return
		_:
			if variant == ABTestManager.draft_mode.VALUE_APPLY_INPLACE and _apply_btn != null:
				_hide_apply_btn_animated()
			if _draft_bubble != null:
				_draft_bubble.visible = false


# 草稿叉转成正式叉的动画时长（秒）
const _DRAFT_APPLY_TO_MARK_SEC: float = 0.77


# 草稿通关表现：等标记转正 → 放烟花 → 庆祝动画 → 再校验通关
func _run_draft_win_with_fireworks(has_mark_transition: bool = true) -> void:
	var flreworks_len: float = _fireworks_anim.get_animation("Flreworks").length
	var pre_delay: float = (_DRAFT_APPLY_TO_MARK_SEC + 0.5) if has_mark_transition else 0.0
	UIManager.block_input_briefly(self, pre_delay + flreworks_len + 0.1)
	if has_mark_transition:
		await get_tree().create_timer(_DRAFT_APPLY_TO_MARK_SEC).timeout
		if not visible or _is_complete:
			return
		await get_tree().create_timer(0.5).timeout
		if not visible or _is_complete:
			return
	_fireworks_anim.play("Flreworks")
	await _fireworks_anim.animation_finished
	if not visible or _is_complete:
		return
	_play_celebrate_effect()
	_validate_board()


# 播一次庆祝动画
func _play_celebrate_effect() -> void:
	if _anim_correct != null and _anim_correct.has_animation("Appear"):
		_anim_correct.stop()
		_anim_correct.play("Appear")


# 快照里草稿叉的编码
const _DRAFT_PERSIST_CROSS: int = 1
# 快照里草稿猫的编码
const _DRAFT_PERSIST_CAT: int = 2


# 草稿标记序列化成 [[r, c, 编码], ...]，供子类写进快照
func _serialize_draft_marks() -> Array:
	var out: Array = []
	var draft_marks: Dictionary = _collect_draft_marks()
	for key in draft_marks.keys():
		var pos: Vector2i = key as Vector2i
		var code: int = (
			_DRAFT_PERSIST_CAT if draft_marks[key] == CellState.DRAFT_CAT else _DRAFT_PERSIST_CROSS
		)
		out.append([pos.x, pos.y, code])
	return out


# 从快照恢复草稿标记（仅 AUTO_WIN_PERSIST 变体；非空格跳过）
func _restore_draft_marks_from_snapshot(data: Array) -> void:
	if _board_view == null or data.is_empty():
		return
	if _get_draft_variant() != ABTestManager.draft_mode.VALUE_AUTO_WIN_PERSIST:
		return
	for item in data:
		if not (item is Array) or item.size() < 3:
			continue
		var r: int = int(item[0])
		var c: int = int(item[1])

		var mark: int = (
			CellState.DRAFT_CAT if int(item[2]) == _DRAFT_PERSIST_CAT else CellState.DRAFT_CROSS
		)
		if not CellState.is_blank(_board_view.get_cell_state(r, c)):
			continue
		_set_cell_draft(r, c, mark)


# 快照当前正式标记：猫 / 叉 / 错误叉 / 锁定叉
func _snapshot_real_marks() -> Dictionary:
	if _board_view == null:
		return {}
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return {}
	var board: Array = _board_view.get_board()
	var placed_cats: Array = []
	var marks: Array = []
	var errors: Array = []
	var locked_marks: Array = []
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

	return {
		"placed_cats": placed_cats, "marks": marks, "errors": errors, "locked_marks": locked_marks
	}


# 答案格是否已经全部放上正式猫
func _is_solution_fully_placed() -> bool:
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return false
	var total: int = 0
	var filled: int = 0
	for r in range(sz):
		for c in range(sz):
			if not _is_solution_cell(r, c):
				continue
			total += 1
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				filled += 1
	return total > 0 and filled == total


# 清空草稿死锁相关状态
func _clear_draft_deadlock_state() -> void:
	_draft_pre_enter_real_marks = {}
	_draft_deadlock_pending = false
	_draft_deadlock_real_marks = {}


# 草稿是否自相矛盾：并进棋盘后有冲突，或某行 / 列 / 区域被填满却没有猫
func _detect_draft_contradiction() -> bool:
	var sz: int = _level_config.get("size", 4)
	if sz <= 0:
		return false
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return false

	var merged: Array = _board_view.get_cell_state_folded_board()
	var draft_marks: Dictionary = _collect_draft_marks()
	for key in draft_marks.keys():
		var pos: Vector2i = key as Vector2i
		if pos.x < 0 or pos.x >= sz or pos.y < 0 or pos.y >= sz:
			continue
		if merged[pos.x][pos.y] != CellState.EMPTY:
			continue
		var m: int = draft_marks[key]
		if m == CellState.DRAFT_CAT:
			merged[pos.x][pos.y] = CellState.CAT
		elif m == CellState.DRAFT_CROSS:
			merged[pos.x][pos.y] = CellState.MARK

	var conflicts: Dictionary = QueendokuCore.find_conflicts(merged, sz, regions)
	if not conflicts.is_empty():
		return true

	for r in range(sz):
		var cat_n: int = 0
		var empty_n: int = 0
		for c in range(sz):
			var s: int = merged[r][c]
			if s == CellState.CAT:
				cat_n += 1
			elif s == CellState.EMPTY:
				empty_n += 1
		if cat_n == 0 and empty_n == 0:
			return true

	for c in range(sz):
		var cat_n: int = 0
		var empty_n: int = 0
		for r in range(sz):
			var s: int = merged[r][c]
			if s == CellState.CAT:
				cat_n += 1
			elif s == CellState.EMPTY:
				empty_n += 1
		if cat_n == 0 and empty_n == 0:
			return true

	var region_cat: Dictionary = {}
	var region_empty: Dictionary = {}
	for r in range(sz):
		for c in range(sz):
			var rid: int = int(regions[r][c])
			var s: int = merged[r][c]
			if s == CellState.CAT:
				region_cat[rid] = int(region_cat.get(rid, 0)) + 1
			elif s == CellState.EMPTY:
				region_empty[rid] = int(region_empty.get(rid, 0)) + 1

	var seen_rids: Dictionary = {}
	for r in range(sz):
		for c in range(sz):
			seen_rids[int(regions[r][c])] = true
	for rid in seen_rids.keys():
		var cat_n: int = int(region_cat.get(rid, 0))
		var empty_n: int = int(region_empty.get(rid, 0))
		if cat_n == 0 and empty_n == 0:
			return true
	return false


# 草稿是否已全对：正式猫 + 草稿猫正好铺满答案格，且草稿猫都落在答案上
func _detect_draft_all_correct() -> bool:
	var sz: int = _level_config.get("size", 4)
	if sz <= 0:
		return false
	var real_cat_n: int = 0
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				real_cat_n += 1
	var draft_cat_n: int = 0
	var draft_marks: Dictionary = _collect_draft_marks()
	for key in draft_marks.keys():
		if draft_marks[key] != CellState.DRAFT_CAT:
			continue
		var pos: Vector2i = key as Vector2i

		if _board_view.get_cell_state(pos.x, pos.y) == CellState.CAT:
			continue
		if not _is_solution_cell(pos.x, pos.y):
			return false
		draft_cat_n += 1
	return (real_cat_n + draft_cat_n) == sz and draft_cat_n > 0


# 提交草稿：草稿猫转正式猫、草稿叉转叉；错的扣命，全对则放烟花通关
func _apply_draft_commit() -> void:
	var was_all_correct: bool = _draft_terminal_state == DraftTerminal.ALL_CORRECT
	var to_apply: Array = []
	var draft_marks: Dictionary = _collect_draft_marks()
	for key in draft_marks.keys():
		to_apply.append({"pos": key as Vector2i, "mark": draft_marks[key]})

	to_apply.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var pa: Vector2i = a["pos"]
			var pb: Vector2i = b["pos"]
			var diag_a: int = pa.y - pa.x
			var diag_b: int = pb.y - pb.x
			if diag_a != diag_b:
				return diag_a < diag_b
			return pa.x > pb.x
	)

	_exit_draft_mode_and_clear(false, true)
	if _board_view == null:
		return
	var wrong_positions: Array[Vector2i] = []
	var has_cross_to_mark: bool = false

	# 提交期间先抑制连击飘字，全部落完再统一展示
	_applying_draft_commit = true
	var has_cat_in_apply: bool = false
	_combo_visual_suppressed = true
	_draft_combo_gain_sum = 0
	var draft_cat_top_right: Vector2i = Vector2i(-1, -1)
	for item in to_apply:
		var pos: Vector2i = item["pos"]
		var m: int = item["mark"]
		var before: int = _board_view.get_cell_state(pos.x, pos.y)
		if before == CellState.CAT:
			continue
		if m == CellState.DRAFT_CAT:
			if _is_solution_cell(pos.x, pos.y):
				_record_cell_change(pos.x, pos.y, before, CellState.CAT)
				has_cat_in_apply = true
				_board_view.set_cell_state(
					pos.x, pos.y, CellState.CAT, true, true, BoardView.ChangeSource.DRAFT_APPLY
				)

				if (
					draft_cat_top_right.x < 0
					or pos.y > draft_cat_top_right.y
					or (pos.y == draft_cat_top_right.y and pos.x < draft_cat_top_right.x)
				):
					draft_cat_top_right = pos
			else:
				_record_cell_change(pos.x, pos.y, before, CellState.MARK)
				_board_view.set_cell_state(
					pos.x, pos.y, CellState.MARK, false, true, BoardView.ChangeSource.DRAFT_APPLY
				)
				wrong_positions.append(pos)
		elif m == CellState.DRAFT_CROSS:
			_record_cell_change(pos.x, pos.y, before, CellState.MARK)
			has_cross_to_mark = true
			var cross_cv: CellView = _board_view.get_cell_view(pos.x, pos.y)
			if cross_cv != null:
				cross_cv.play_draft_cross_apply()
			else:
				_board_view.set_cell_state(
					pos.x, pos.y, CellState.MARK, false, true, BoardView.ChangeSource.DRAFT_APPLY
				)
	_commit_current_step(has_cat_in_apply, wrong_positions.size() > 0)

	_combo_visual_suppressed = false
	if (
		draft_cat_top_right.x >= 0
		and _combo_feedback_view != null
		and ABTestManager.combo_encourage.is_enabled()
	):
		if _combo_count >= 3:
			var pos_global: Vector2 = _board_view.get_cell_global_center(
				draft_cat_top_right.x, draft_cat_top_right.y
			)
			_combo_feedback_view.show_combo_text_only(_combo_count, pos_global)

	_applying_draft_commit = false
	_refresh_auto_complete_btn()

	_update_remaining()
	if wrong_positions.size() > 0:
		_wrong_guess_pending = true
		_mistake_count += wrong_positions.size()
		_combo_count = 0
		var decrement: int = min(_lives, wrong_positions.size())
		GameState.inc_game_total_stat(_game_type(), "invalid_sign_total", decrement)
		var lost_top_index: int = _lives - 1
		_lives -= decrement

		if (
			_lives <= 0
			and _is_solution_fully_placed()
			and not _draft_pre_enter_real_marks.is_empty()
		):
			_draft_deadlock_pending = true
			_draft_deadlock_real_marks = _draft_pre_enter_real_marks

		for pos: Vector2i in wrong_positions:
			_board_view.play_error_feedback(pos.x, pos.y)

		for i in range(decrement):
			_animate_heart_lost(lost_top_index - i)
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)
		if not ABTestManager.wrong_cat_effect.should_skip_shake():
			_play_screen_shake()
		if _lives <= 0:
			_board_view.play_cat_cry_loop_all()

			UIManager.block_input_briefly(self, 2.0)
		elif _is_solution_fully_placed():
			_wrong_guess_pending = false
			if _fireworks_anim != null and _fireworks_anim.has_animation("Flreworks"):
				_run_draft_win_with_fireworks(has_cross_to_mark)
			else:
				_play_celebrate_effect()
				_validate_board()
			return
		else:
			_board_view.play_cat_frustrated_all()

		get_tree().create_timer(0.4).timeout.connect(
			func() -> void:
				_update_remaining()
				_wrong_guess_pending = false
		)

		if _lives <= 0:
			get_tree().create_timer(0.6).timeout.connect(
				func() -> void:
					if not visible:
						return
					_on_game_over()
			)
		return

	if not was_all_correct:
		return

	if _fireworks_anim != null and _fireworks_anim.has_animation("Flreworks"):
		_run_draft_win_with_fireworks(has_cross_to_mark)
	else:
		_play_celebrate_effect()
		_validate_board()


# 该格是否答案格（越界返回 false）
func _is_solution_cell(r: int, c: int) -> bool:
	var sol: Array = _puzzle.get("solution", [])
	if r < 0 or r >= sol.size():
		return false
	var row: Array = sol[r] as Array
	if c < 0 or c >= row.size():
		return false
	return bool(row[c])


# 清空草稿（退出草稿模式并擦掉草稿标记）
func _apply_draft_clear() -> void:
	_exit_draft_mode_and_clear()


# 改草稿按钮上的角标文字与字号
func _set_draft_btn_text(text: String, font_size: int) -> void:
	if _draft_btn == null:
		return
	var qlabel: Label = _draft_btn.get_node_or_null("QLabel") as Label
	if qlabel == null:
		return
	qlabel.text = text
	qlabel.add_theme_font_size_override("font_size", font_size)


# 在草稿按钮上方显示一个提示气泡（懒创建）
func _show_draft_bubble(text: String, bg_color: Color) -> void:
	if _draft_btn == null:
		return
	if _draft_bubble == null:
		_draft_bubble = Label.new()
		_draft_bubble.name = "DraftBubble"
		_draft_bubble.add_theme_font_size_override("font_size", 32)
		_draft_bubble.add_theme_color_override("font_color", Color.WHITE)
		_draft_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_draft_bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_draft_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var parent: Node = _draft_btn.get_parent()
		if parent != null:
			parent.add_child(_draft_bubble)

	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_draft_bubble.add_theme_stylebox_override("normal", sb)
	_draft_bubble.text = text

	_draft_bubble.reset_size()
	var btn_pos: Vector2 = _draft_btn.position
	var btn_size: Vector2 = _draft_btn.size
	var bubble_size: Vector2 = _draft_bubble.size
	_draft_bubble.position = Vector2(
		btn_pos.x + (btn_size.x - bubble_size.x) / 2.0,
		btn_pos.y - bubble_size.y - 8.0,
	)
	_draft_bubble.visible = true


# ================= 开场动画收尾 =================
# 开场动画结束：放开棋盘操作、恢复规则条交互
func _on_appear_animation_finished() -> void:
	_entry_anim_playing = false
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_rule_info_bar_v4_interactive(true)


# 开关 V4 规则条的交互
func _set_rule_info_bar_v4_interactive(enabled: bool) -> void:
	var rule_bar := get_node_or_null("Root/VBoxContainer/RuleBar")
	if rule_bar is RuleInfoBarV4:
		(rule_bar as RuleInfoBarV4).set_interactive(enabled)


# ================= 自动完成（AB: auto_complete） =================
# 自动完成时每条对角线之间的间隔（秒）
const AUTO_MARK_DIAG_INTERVAL_SEC: float = 0.06
# 打叉完到开始放猫的间隔（秒）
const AUTO_MARK_TO_CAT_GAP_SEC: float = 0.2
# 逐只放猫的间隔（秒）
const AUTO_CAT_STEP_SEC: float = 0.12
# 自动完成进行中，屏蔽输入
var _auto_completing: bool = false

# 自动完成令牌，自增即可中断进行中的流程
var _auto_complete_token: int = 0

# 自动完成按钮当前是否已弹出
var _ac_shown: bool = false
# 本局出现过错误落子 → 不再提供自动完成
var _ac_had_wrong_cat: bool = false

# 草稿提交中，期间不弹自动完成按钮
var _applying_draft_commit: bool = false


# 棋盘变化：出现错误叉就收起自动完成按钮，否则尝试弹出
func _on_board_changed_for_auto_complete(_r: int, _c: int, state: int, source: int) -> void:
	if state == CellState.ERROR:
		_ac_had_wrong_cat = true
		if source != BoardView.ChangeSource.RESTORE:
			_hide_auto_complete_btn()
		return
	_refresh_auto_complete_btn()


# 满足条件就弹一次自动完成按钮（只弹一次）
func _refresh_auto_complete_btn() -> void:
	if _ac_anim == null or _ac_shown:
		return
	if _should_offer_auto_complete():
		_ac_shown = true
		_ac_anim.play("appear")


# 收起自动完成按钮
func _hide_auto_complete_btn() -> void:
	if _ac_anim == null:
		return
	if _ac_shown:
		_ac_shown = false
		_ac_anim.play("disappear")


# 是否该提供自动完成：AB 开启、大棋盘、没出过错、且只差最后一只猫
func _should_offer_auto_complete() -> bool:
	if _applying_draft_commit:
		return false
	if _entry_anim_playing or _is_complete or _auto_completing or not visible:
		return false
	if not ABTestManager.auto_complete.is_enabled():
		return false
	var sz: int = _level_config.get("size", 0)
	if sz < 6:
		return false
	if _ac_had_wrong_cat:
		return false
	return _board_view.count_cat_cells() == sz - 1


# 自动完成按钮：遮罩期间自动补齐剩下的猫与叉
func _on_auto_complete_btn_pressed() -> void:
	if _entry_anim_playing or _is_complete or _wrong_guess_pending or _auto_completing:
		return

	if _ac_btn != null and _ac_btn.modulate.a < 1.0:
		return
	if _puzzle.is_empty() or not _puzzle.has("solution"):
		return
	_auto_completing = true
	_auto_complete_token += 1
	_hide_auto_complete_btn()
	_reset_idle_hint()

	_exit_draft_mode_and_clear(true)

	UIMask.acquire()
	await _run_auto_complete(_auto_complete_token)
	UIMask.release()
	_auto_completing = false


# 自动完成流程：按对角线分批打叉、再逐只放猫，最后校验通关
func _run_auto_complete(token: int) -> void:
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return
	var sol: Array = _puzzle["solution"]

	# 按「反对角线」分层，动画沿对角线推进
	var ring := func(v: Vector2i) -> int: return v.y + (sz - 1 - v.x)
	var mark_cells: Array[Vector2i] = []
	var cat_cells: Array[Vector2i] = []
	for r in range(sz):
		for c in range(sz):
			var raw: int = _board_view.get_cell_state(r, c)
			if bool(sol[r][c]):
				if raw != CellState.CAT:
					cat_cells.append(Vector2i(r, c))
			elif CellState.is_blank(raw):
				mark_cells.append(Vector2i(r, c))
	mark_cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return ring.call(a) < ring.call(b)
	)
	cat_cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return ring.call(a) < ring.call(b)
	)

	if not ABTestManager.auto_complete.should_auto_mark_crosses():
		mark_cells.clear()

	if not mark_cells.is_empty():
		SoundManager.set_silent(true)
		var i: int = 0
		while i < mark_cells.size():
			var cur_ring: int = ring.call(mark_cells[i])

			while i < mark_cells.size() and ring.call(mark_cells[i]) == cur_ring:
				_board_view.set_cell_state(
					mark_cells[i].x,
					mark_cells[i].y,
					CellState.MARK,
					true,
					true,
					BoardView.ChangeSource.AUTO_COMPLETE
				)
				i += 1
			await get_tree().create_timer(AUTO_MARK_DIAG_INTERVAL_SEC).timeout
			if token != _auto_complete_token:
				SoundManager.set_silent(false)
				return
		SoundManager.set_silent(false)

	if not cat_cells.is_empty():
		await get_tree().create_timer(AUTO_MARK_TO_CAT_GAP_SEC).timeout
		if token != _auto_complete_token:
			return

	for i in range(cat_cells.size()):
		var cell: Vector2i = cat_cells[i]
		var is_last: bool = i == cat_cells.size() - 1
		if is_last:
			_board_view.set_cell_state(
				cell.x, cell.y, CellState.CAT, false, false, BoardView.ChangeSource.AUTO_COMPLETE
			)
		else:
			_board_view.set_cell_state(
				cell.x, cell.y, CellState.CAT, true, true, BoardView.ChangeSource.AUTO_COMPLETE
			)
		_update_remaining()
		await get_tree().create_timer(AUTO_CAT_STEP_SEC).timeout
		if token != _auto_complete_token:
			return

	_on_draft_changed_for_persist(true)
	_update_remaining()
	_validate_board()


# ================= 信号连接与页面隐藏 =================
# 接上棋盘的格子变化信号（连击统计用）
func _connect_combo_signal() -> void:
	if not _board_view.cell_state_changed.is_connected(_on_board_cell_state_changed_for_combo):
		_board_view.cell_state_changed.connect(_on_board_cell_state_changed_for_combo)


# 断开连击信号
func _disconnect_combo_signal() -> void:
	if _board_view.cell_state_changed.is_connected(_on_board_cell_state_changed_for_combo):
		_board_view.cell_state_changed.disconnect(_on_board_cell_state_changed_for_combo)


# 由 UIManager 在页面隐藏时调用：停表、断信号、收浮层、销毁 banner 并隐藏自己
func on_hide() -> void:
	_disconnect_combo_signal()
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_idle_time = 0.0
	_undo_executor.cancel()

	_auto_complete_token += 1
	_auto_completing = false
	SoundManager.set_silent(false)
	if CheatBus.command_issued.is_connected(_on_cheat_command):
		CheatBus.command_issued.disconnect(_on_cheat_command)
	if _board_view.cell_state_changed.is_connected(_on_board_cell_state_changed_for_r4):
		_board_view.cell_state_changed.disconnect(_on_board_cell_state_changed_for_r4)

	if _strategy_overlay != null and is_instance_valid(_strategy_overlay):
		_strategy_overlay.visible = false
	_disconnect_self_reward_callbacks()
	_destroy_banner()
	visible = false


# ================= 生命条与进度条 =================
# 取生命图标 AB 档位（心 / 鱼 / 闪电）
func _life_bar_style() -> int:
	return int(ABTestManager.life_icon.value())


# 档位对应的生命槽预制体
func _life_bar_scene_for(style: int) -> PackedScene:
	match style:
		LifeIconConfig.VALUE_FISH:
			return FISH_SLOT_SCENE
		LifeIconConfig.VALUE_LIGHTNING:
			return LIGHTNING_SLOT_SCENE
	return HEART_SLOT_SCENE


# 按档位挂载 / 替换 3 个生命槽，并缓存引用与 +1 图标
func _mount_life_bar() -> void:
	var bar: Node = get_node_or_null("Root/VBoxContainer/CatHeartRow/HeartBg")
	if bar == null:
		return
	var style: int = _life_bar_style()
	var scene: PackedScene = _life_bar_scene_for(style)
	if scene != null and int(bar.get_meta("life_style", LifeIconConfig.VALUE_HEART)) != style:
		for slot_name in ["LifeSlot", "LifeSlot2", "LifeSlot3"]:
			var old := bar.get_node_or_null(slot_name) as Control
			if old == null:
				continue
			var idx: int = old.get_index()

			var anchors: Array[float] = [
				old.get_anchor(0), old.get_anchor(1), old.get_anchor(2), old.get_anchor(3)
			]
			var offsets: Array[float] = [
				old.get_offset(0), old.get_offset(1), old.get_offset(2), old.get_offset(3)
			]
			old.free()
			var ns := scene.instantiate() as Control
			ns.name = slot_name
			for side in 4:
				ns.set_anchor(side, anchors[side])
				ns.set_offset(side, offsets[side])
			bar.add_child(ns)
			bar.move_child(ns, idx)
		bar.set_meta("life_style", style)
	_heart1 = bar.get_node_or_null("LifeSlot")
	_heart2 = bar.get_node_or_null("LifeSlot2")
	_heart3 = bar.get_node_or_null("LifeSlot3")
	_apply_life_plus_icon(style)


# 按档位换「生命 +1」飘字里的图标
func _apply_life_plus_icon(style: int) -> void:
	var icon := (
		get_node_or_null("Root/VBoxContainer/CatHeartRow/LifePlus/PlusFloat/HeartIcon")
		as TextureRect
	)
	if icon == null:
		return
	var tex: Texture2D = null
	match style:
		LifeIconConfig.VALUE_FISH:
			tex = life_plus_icon_fish
		LifeIconConfig.VALUE_LIGHTNING:
			tex = life_plus_icon_lightning
		_:
			tex = life_plus_icon_heart
	if tex != null:
		icon.texture = tex


# 按 AB 在「数字」与「进度条」两种剩余量显示之间切换
func _mount_progress_bar() -> void:
	_progress_bar_mode = ABTestManager.progress_emphasis.is_progress_bar()
	if _progress_slot != null:
		_progress_slot.visible = _progress_bar_mode
	if _progress_target != null:
		_progress_target.visible = not _progress_bar_mode
	_align_glow_to_progress()
	_apply_heart_bg_position_for_progress()
	if _progress_bar_mode:
		if _progress_track_fill != null:
			_progress_track_fill.offset_right = _progress_track_fill.offset_left
		_layout_for_progress_bar()


# 进度条模式下微调生命背景位置（所调接口在本仓已缺失）
func _apply_heart_bg_position_for_progress() -> void:
	is_force_pass_scroll_events()


# 把猫数量行的光效对齐到当前显示目标（数字或进度条）
func _align_glow_to_progress() -> void:
	var glow_control: Control = (
		get_node_or_null("Root/VBoxContainer/CatHeartRow/Control") as Control
	)
	if glow_control == null:
		return
	glow_control.visible = true
	var glow_rect: NinePatchRect = glow_control.get_node_or_null("NinePatchRect") as NinePatchRect
	if glow_rect == null:
		return
	var ref: Control = _progress_slot if _progress_bar_mode else _progress_target
	if ref == null:
		return
	const PAD_L: float = -24.0
	const PAD_R: float = 33.0
	const PAD_T: float = -16.0
	const PAD_B: float = 16.0
	glow_rect.offset_left = ref.offset_left + PAD_L
	glow_rect.offset_right = ref.offset_right + PAD_R
	glow_rect.offset_top = ref.offset_top + PAD_T
	glow_rect.offset_bottom = ref.offset_bottom + PAD_B
	var sprite: Node2D = glow_control.get_node_or_null("Sprite2D") as Node2D
	if sprite != null:
		sprite.position.x = (ref.offset_left + ref.offset_right) * 0.5
		sprite.position.y = (ref.offset_top + ref.offset_bottom) * 0.5


# 设置进度条轨道宽度，并把数字挪到轨道右侧
func _apply_progress_track_width(_sz: int) -> void:
	_progress_track_width = _PROGRESS_TRACK_WIDTH_NORMAL
	if _progress_track_bg != null:
		_progress_track_bg.offset_right = _progress_track_bg.offset_left + _progress_track_width
	if _progress_count_label == null:
		return
	_progress_count_label.offset_left = (
		_progress_track_bg.offset_left + _progress_track_width + 12.0
	)


# 数字太长时按宽度等比缩小字号
func _fit_progress_count_font(count_text: String) -> void:
	if _progress_count_label == null:
		return
	var font: Font = _progress_count_label.get_theme_font("normal_font")
	if font == null:
		return
	var box_w: float = _progress_count_label.offset_right - _progress_count_label.offset_left
	var w: float = (
		font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _PROGRESS_COUNT_FONT_BASE).x
	)
	var fit: int = _PROGRESS_COUNT_FONT_BASE
	if box_w > 0.0 and w > box_w and w > 0.0:
		fit = int(floor(_PROGRESS_COUNT_FONT_BASE * box_w / w))
	_progress_count_label.add_theme_font_size_override("normal_font_size", fit)


# 进度条模式下的生命背景位置微调
func _layout_for_progress_bar() -> void:
	var timer_bg: Control = (
		get_node_or_null("Root/VBoxContainer/CatHeartRow/TimeContainer") as Control
	)
	if timer_bg != null:
		return
	var heart_bg: Control = get_node_or_null("Root/VBoxContainer/CatHeartRow/HeartBg") as Control
	if heart_bg == null:
		return

	heart_bg.offset_left = -475.0
	heart_bg.offset_right = -225.0


# 按当前生命数刷新三颗心的生死表现
func _refresh_hearts() -> void:
	var hearts: Array[Control] = [_heart1, _heart2, _heart3]
	for i in range(3):
		var slot := hearts[i] as LifeSlot
		if slot == null:
			continue
		if i < _lives:
			slot.show_alive()
		else:
			slot.show_lost(false)


# 播第 index 颗心的失去动画
func _animate_heart_lost(index: int) -> void:
	var hearts: Array[Control] = [_heart1, _heart2, _heart3]
	if index < 0 or index >= hearts.size():
		return
	var slot := hearts[index] as LifeSlot
	if slot != null:
		slot.show_lost(true)


# 断开自己接在广告激励 / 关闭信号上的回调，避免页面隐藏后仍被回调
func _disconnect_self_reward_callbacks() -> void:
	for c: Dictionary in UniKitManager.ad_rewarded.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_rewarded.disconnect(cb)
	for c: Dictionary in UniKitManager.ad_closed.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_closed.disconnect(cb)


# ================= 区域颜色与提示文案 =================
# 按调色板 AB 返回 12 个区域色的本地化名称
func _resolve_region_color_names() -> Array[String]:
	if ABTestManager.region_color.is_custom_palette():
		return [
			tr("COLOR_OLIVE_YELLOW"),
			tr("COLOR_ROSE"),
			tr("COLOR_PURPLE"),
			tr("COLOR_MAGENTA"),
			tr("COLOR_ORANGE"),
			tr("COLOR_YELLOW"),
			tr("COLOR_DARK_BLUE"),
			tr("COLOR_LIGHT_BLUE"),
			tr("COLOR_SKY_BLUE"),
			tr("COLOR_EMERALD"),
			tr("COLOR_GREEN"),
			tr("COLOR_BROWN")
		]
	if (
		ABTestManager.region_color.is_new_cell_only_palette()
		or ABTestManager.region_color.is_cell_color_v3()
		or ABTestManager.region_color.is_new_cell_recompute()
	):
		return [
			tr("COLOR_OLIVE_YELLOW"),
			tr("COLOR_ROSE"),
			tr("COLOR_PURPLE"),
			tr("COLOR_MAGENTA"),
			tr("COLOR_ORANGE"),
			tr("COLOR_YELLOW"),
			tr("COLOR_DARK_BLUE"),
			tr("COLOR_LIGHT_BLUE"),
			tr("COLOR_SKY_BLUE"),
			tr("COLOR_DARK_GREEN"),
			tr("COLOR_GREEN"),
			tr("COLOR_BROWN")
		]
	if ABTestManager.region_color.is_palette_v5():
		return [
			tr("COLOR_BROWN"),
			tr("COLOR_SALMON"),
			tr("COLOR_ROSE"),
			tr("COLOR_LAVENDER"),
			tr("COLOR_PURPLE"),
			tr("COLOR_GREEN"),
			tr("COLOR_DARK_BLUE"),
			tr("COLOR_YELLOW"),
			tr("COLOR_PINK"),
			tr("COLOR_TEAL"),
			tr("COLOR_ORANGE"),
			tr("COLOR_SKY_BLUE")
		]
	if ABTestManager.region_color.is_palette_v6():
		return [
			tr("COLOR_TAN"),
			tr("COLOR_RED"),
			tr("COLOR_INDIGO"),
			tr("COLOR_VIOLET"),
			tr("COLOR_ORANGE"),
			tr("COLOR_GREEN"),
			tr("COLOR_AQUA"),
			tr("COLOR_DARK_BLUE"),
			tr("COLOR_PINK"),
			tr("COLOR_LILAC"),
			tr("COLOR_LIME"),
			tr("COLOR_GOLD")
		]
	if ABTestManager.region_color.is_palette_v7():
		return [
			tr("COLOR_BROWN"),
			tr("COLOR_PEACH"),
			tr("COLOR_GREEN"),
			tr("COLOR_SKY_BLUE"),
			tr("COLOR_PURPLE"),
			tr("COLOR_LIME"),
			tr("COLOR_INDIGO"),
			tr("COLOR_GOLD"),
			tr("COLOR_PINK"),
			tr("COLOR_TEAL"),
			tr("COLOR_ORANGE"),
			tr("COLOR_ROSE")
		]
	return [
		tr("COLOR_PINK"),
		tr("COLOR_ROSE"),
		tr("COLOR_PURPLE"),
		tr("COLOR_MAGENTA"),
		tr("COLOR_ORANGE"),
		tr("COLOR_YELLOW"),
		tr("COLOR_DARK_BLUE"),
		tr("COLOR_LIGHT_BLUE"),
		tr("COLOR_SKY_BLUE"),
		tr("COLOR_TEAL"),
		tr("COLOR_GREEN"),
		tr("COLOR_BROWN")
	]


# 同上，返回 12 个区域色的十六进制值（给提示文案上色用）
func _resolve_region_color_hex_codes() -> Array[String]:
	if (
		ABTestManager.region_color.is_custom_palette()
		or ABTestManager.region_color.is_new_cell_only_palette()
		or ABTestManager.region_color.is_cell_color_v3()
		or ABTestManager.region_color.is_new_cell_recompute()
	):
		return [
			"#A3A306",
			"#E45F8A",
			"#8D7AEB",
			"#DB84CA",
			"#FF8E3D",
			"#DBAB31",
			"#4B7FC0",
			"#7AA9D9",
			"#0AAECF",
			"#0DA875",
			"#71BB63",
			"#C7834F"
		]
	if ABTestManager.region_color.is_palette_v5():
		return [
			"#B36E3C",
			"#EA825C",
			"#C75C83",
			"#838AB8",
			"#B070DD",
			"#7CC057",
			"#6584B3",
			"#CFA326",
			"#E377CA",
			"#39A7A3",
			"#DE7E34",
			"#66ACD5"
		]
	if ABTestManager.region_color.is_palette_v6():
		return [
			"#BA925B",
			"#CA6666",
			"#686DBF",
			"#9684EC",
			"#CA7849",
			"#4ABA34",
			"#63B9BB",
			"#308DBC",
			"#DC5599",
			"#DF96D3",
			"#7EDF88",
			"#D0B038"
		]
	if ABTestManager.region_color.is_palette_v7():
		return [
			"#B67C54",
			"#E88B69",
			"#37B95E",
			"#75B1D2",
			"#A673D8",
			"#8BC36C",
			"#6767C3",
			"#E3BD4D",
			"#D987C6",
			"#45B7B3",
			"#DD8240",
			"#E4699C"
		]
	return [
		"#D980A4",
		"#BC537C",
		"#8465D6",
		"#F970DE",
		"#FFAA6E",
		"#DDA916",
		"#49658F",
		"#83AAD2",
		"#3497CB",
		"#289692",
		"#78AB5A",
		"#AC6F48"
	]


# 给区域色生成 BBCode 染色文字：控制组查表，其余组按最接近的颜色名
func _color_name_bbcode(region_idx: int) -> String:
	var cell_color: Color = _board_view.get_region_color(region_idx)
	var hex: String
	var name: String
	if ABTestManager.region_color.value() == RegionColorConfig.VALUE_CONTROL:
		var ci: int = _board_view.get_region_color_index(region_idx)
		var names := _resolve_region_color_names()
		name = names[ci] if ci < names.size() else tr("HINT_SOME_COLOR")
		var hex_codes := _resolve_region_color_hex_codes()
		hex = hex_codes[ci] if ci < hex_codes.size() else "#ffffff"
	else:
		var darkened: Color = cell_color.darkened(0.28)
		hex = (
			"#%02x%02x%02x" % [int(darkened.r * 255), int(darkened.g * 255), int(darkened.b * 255)]
		)
		name = _nearest_color_name(cell_color)
	return "[color=%s]%s[/color]" % [hex, name]


# 在一张已知色表里找欧氏距离最近的颜色名
func _nearest_color_name(color: Color) -> String:
	var known: Array = [
		[Color("#CBCB24"), tr("COLOR_OLIVE_YELLOW")],
		[Color("#E45F8A"), tr("COLOR_ROSE")],
		[Color("#8D7AEB"), tr("COLOR_PURPLE")],
		[Color("#F4A2E4"), tr("COLOR_MAGENTA")],
		[Color("#FF8E3D"), tr("COLOR_ORANGE")],
		[Color("#F4D27B"), tr("COLOR_YELLOW")],
		[Color("#4B7FC0"), tr("COLOR_DARK_BLUE")],
		[Color("#A2C7ED"), tr("COLOR_LIGHT_BLUE")],
		[Color("#0AAECF"), tr("COLOR_SKY_BLUE")],
		[Color("#0DA875"), tr("COLOR_DARK_GREEN")],
		[Color("#88CE7A"), tr("COLOR_GREEN")],
		[Color("#AA7146"), tr("COLOR_BROWN")],
		[Color("#CDA400"), tr("COLOR_OLIVE_YELLOW")],
		[Color("#D36F8F"), tr("COLOR_ROSE")],
		[Color("#8979DA"), tr("COLOR_PURPLE")],
		[Color("#38A9C0"), tr("COLOR_SKY_BLUE")],
		[Color("#2A8C53"), tr("COLOR_DARK_GREEN")],
		[Color("#A86D4A"), tr("COLOR_BROWN")],
		[Color("#ac7147"), tr("COLOR_BROWN")],
		[Color("#f19e80"), tr("COLOR_SALMON")],
		[Color("#c36a8a"), tr("COLOR_ROSE")],
		[Color("#afb4d2"), tr("COLOR_LAVENDER")],
		[Color("#c58ced"), tr("COLOR_PURPLE")],
		[Color("#a4d987"), tr("COLOR_GREEN")],
		[Color("#6584b3"), tr("COLOR_DARK_BLUE")],
		[Color("#e4bc4a"), tr("COLOR_YELLOW")],
		[Color("#fea3e9"), tr("COLOR_PINK")],
		[Color("#4bb5b1"), tr("COLOR_TEAL")],
		[Color("#de7e34"), tr("COLOR_ORANGE")],
		[Color("#89c4e6"), tr("COLOR_SKY_BLUE")],
		[Color("#c9a779"), tr("COLOR_TAN")],
		[Color("#ca6666"), tr("COLOR_RED")],
		[Color("#686dbf"), tr("COLOR_INDIGO")],
		[Color("#9684ec"), tr("COLOR_VIOLET")],
		[Color("#ca7849"), tr("COLOR_ORANGE")],
		[Color("#4aba34"), tr("COLOR_GREEN")],
		[Color("#9de1e3"), tr("COLOR_AQUA")],
		[Color("#4cabdb"), tr("COLOR_DARK_BLUE")],
		[Color("#dc5599"), tr("COLOR_PINK")],
		[Color("#f4a4e7"), tr("COLOR_LILAC")],
		[Color("#7ee388"), tr("COLOR_LIME")],
		[Color("#dbbc48"), tr("COLOR_GOLD")],
		[Color("#b67c54"), tr("COLOR_BROWN")],
		[Color("#ffaf92"), tr("COLOR_PEACH")],
		[Color("#37b95e"), tr("COLOR_GREEN")],
		[Color("#89c4e4"), tr("COLOR_SKY_BLUE")],
		[Color("#a673d8"), tr("COLOR_PURPLE")],
		[Color("#a4da86"), tr("COLOR_LIME")],
		[Color("#6767c3"), tr("COLOR_INDIGO")],
		[Color("#e3bd4d"), tr("COLOR_GOLD")],
		[Color("#fbafea"), tr("COLOR_PINK")],
		[Color("#45b7b3"), tr("COLOR_TEAL")],
		[Color("#dd8240"), tr("COLOR_ORANGE")],
		[Color("#e4699c"), tr("COLOR_ROSE")],
	]
	var best_name: String = tr("HINT_SOME_COLOR")
	var best_dist: float = INF
	for pair in known:
		var c: Color = pair[0]
		var dr: float = color.r - c.r
		var dg: float = color.g - c.g
		var db: float = color.b - c.b
		var d: float = dr * dr + dg * dg + db * db
		if d < best_dist:
			best_dist = d
			best_name = pair[1]
	return best_name


# 按策略给提示补上本地化描述文案
func _enrich_hint_description(hint: Dictionary) -> void:
	var strategy: String = hint.get("strategy", "")
	var reg: int = hint.get("region", -1)
	match strategy:
		"R2":
			var mode: String = hint.get("mode", "")
			var col_bb: String = _color_name_bbcode(reg) if reg >= 0 else tr("HINT_SOME_COLOR")
			match mode:
				"r2a_row":
					hint["description"] = tr("HINT_R2A_ROW") % [col_bb, hint.get("row", 0) + 1]
				"r2a_col":
					hint["description"] = tr("HINT_R2A_COL") % [col_bb, hint.get("col", 0) + 1]
				"r2b_row":
					hint["description"] = tr("HINT_R2B_ROW") % [hint.get("row", 0) + 1, col_bb]
				"r2b_col":
					hint["description"] = tr("HINT_R2B_COL") % [hint.get("col", 0) + 1, col_bb]
		"R1_mark":
			var cat: Vector2i = hint.get("cat_cell", Vector2i(-1, -1))
			var count: int = (hint.get("unit_cells", []) as Array).size()
			if cat.x >= 0:
				hint["description"] = tr("HINT_R1_MARK")
			else:
				hint["description"] = tr("HINT_R1_MARK")
		"R1", "":
			var unit_type: String = hint.get("unit_type", "")
			var unit_idx: int = hint.get("unit_index", 0)
			if unit_type == "full_line":
				var col_bb: String = _color_name_bbcode(unit_idx)
				hint["description"] = tr("HINT_FULL_LINE") % col_bb
			elif unit_type == "region":
				var col_bb: String = _color_name_bbcode(unit_idx)
				hint["description"] = tr("HINT_REGION_ONLY") % col_bb
		"R4_chain", "R5_chain":
			var chain: Dictionary = hint.get("chain", {})
			if chain.is_empty():
				return

			if (chain.get("steps", []) as Array).size() > 0:
				hint["description"] = tr("HINT_CHAIN_DESC")


# ================= 连锁提示详情 =================
# 在连锁详情层上画一个带序号的圆点标记
func _add_chain_marker(
	layer: CanvasLayer, cell: Vector2i, label_text: String, color: Color
) -> void:
	var s: float = _board_view.scale.x
	var visible_cs: float = BoardView.CELL_PX * s
	var local_rect: Rect2 = _board_view.cell_to_local_rect(cell.x, cell.y)
	var center: Vector2 = (
		_board_view.global_position + (local_rect.position + local_rect.size * 0.5) * s
	)
	var marker_r: float = visible_cs * 0.28

	var marker := Control.new()
	var ms: float = marker_r * 2.0
	marker.position = Vector2(center.x - ms / 2.0, center.y - ms / 2.0)
	marker.size = Vector2(ms, ms)
	marker.scale = Vector2(0.3, 0.3)
	layer.add_child(marker)

	var sf := StyleBoxFlat.new()
	sf.bg_color = Color(color.r, color.g, color.b, 0.88)
	sf.set_corner_radius_all(int(ms / 2.0))
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", sf)
	marker.add_child(panel)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", int(visible_cs * 0.24))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	panel.add_child(lbl)

	var tw := marker.create_tween()
	tw.tween_property(marker, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(
		Tween.TRANS_BACK
	)


# 玩家点「查看详情」：把连锁的反证单元写进说明并展开详情层
func _on_chain_detail_requested() -> void:
	var chain: Dictionary = _hint_data.get("chain", {})
	if chain.is_empty():
		return
	Tracker.track_btn_click(Tracker.Btn.HINT_DETAIL, self)
	Tracker.inc_stat("hint_detail_used")

	var contra_type: String = chain.get("contra_type", "")
	var contra_idx: int = chain.get("contra_index", 0)
	var contra_bb: String
	match contra_type:
		"row":
			contra_bb = tr("HINT_ROW") % (contra_idx + 1)
		"col":
			contra_bb = tr("HINT_COL") % (contra_idx + 1)
		"region":
			contra_bb = tr("HINT_REGION_UNIT") % _color_name_bbcode(contra_idx)
		_:
			contra_bb = tr("HINT_SOME_UNIT")
	_hint_overlay.update_desc(tr("HINT_CONTRA_UNIT") % contra_bb)
	_hint_overlay.show_dismiss_btn()
	_show_chain_detail(chain)


# 展开连锁详情：标出假设格、推理步与被排除格，按序逐个显现
func _show_chain_detail(chain: Dictionary) -> void:
	var sz: int = _level_config.get("size", 4)
	var regs: Array = _puzzle["regions"]

	var contra_cells: Array[Vector2i] = []
	var contra_type: String = chain.get("contra_type", "")
	var contra_idx: int = chain.get("contra_index", 0)
	if contra_type == "row":
		for c in range(sz):
			if CellState.is_blank(_board_view.get_cell_state(contra_idx, c)):
				contra_cells.append(Vector2i(contra_idx, c))
	elif contra_type == "col":
		for r in range(sz):
			if CellState.is_blank(_board_view.get_cell_state(r, contra_idx)):
				contra_cells.append(Vector2i(r, contra_idx))
	elif contra_type == "region":
		for r in range(sz):
			for c in range(sz):
				if (
					regs[r][c] == contra_idx
					and CellState.is_blank(_board_view.get_cell_state(r, c))
				):
					contra_cells.append(Vector2i(r, c))

	var all_steps: Array = []
	var hypo: Vector2i = _hint_data.get("cell", Vector2i(-1, -1))
	if hypo.x >= 0:
		all_steps.append({"cell": hypo, "label": "?", "color": Color("#ef4444")})
	for i in range((chain.get("steps", []) as Array).size()):
		var step_cell: Vector2i = (chain.get("steps", []) as Array)[i]
		all_steps.append({"cell": step_cell, "label": str(i + 1), "color": Color("#f59e0b")})
	for cc in contra_cells:
		all_steps.append({"cell": cc, "label": "✕", "color": Color("#dc2626")})

	var all_chain_cells: Array[Vector2i] = []
	for step in all_steps:
		all_chain_cells.append(step["cell"] as Vector2i)
	_board_view.set_hint_cells(all_chain_cells, hypo)

	var detail_layer := CanvasLayer.new()
	detail_layer.layer = 12
	add_child(detail_layer)
	_chain_detail_layer = detail_layer
	_chain_detail_active = true

	var s: float = _board_view.scale.x
	var bpos: Vector2 = _board_view.global_position

	var step_delay: float = 0.0
	for step in all_steps:
		var cv: Vector2i = step["cell"] as Vector2i
		var lbl: String = step["label"]
		var delay: float = step_delay
		get_tree().create_timer(delay).timeout.connect(
			func() -> void:
				if (
					not _chain_detail_active
					or detail_layer == null
					or not detail_layer.is_inside_tree()
				):
					return
				var temp: CellView = _spawn_temp_cell_in(detail_layer, cv, s, bpos)
				if lbl == "✕":
					temp.play_r2_preview()
				else:
					temp.play_prompt_cat()
		)
		step_delay += 0.05


# ================= 作弊指令 =================
# 作弊指令：设置生命数（设成 0 直接判失败）
func _cmd_lives(args: Array[String]) -> void:
	var val: int = int(args[0]) if args.size() > 0 else 3
	_lives = clampi(val, 0, 3)
	_refresh_hearts()
	if _lives <= 0:
		_on_game_over()


# ================= 提示主流程（HintEngine） =================
# 提示按钮主流程：依次降级找一条可用提示，展示说明并高亮
func _on_hint_btn_pressed() -> void:
	if _entry_anim_playing or _hint_cooldown:
		return
	ABTestManager.dye_at_hint_use()
	Tracker.track_btn_click(Tracker.Btn.HINT, self)
	_reset_idle_hint()

	_exit_draft_mode_and_clear(ABTestManager.draft_mode.keep_marks_on_manual_exit())
	if _is_complete or _wrong_guess_pending:
		return
	var _hint_tb := _tool_hint_btn as ToolButton

	if _hint_tb != null and _hint_tb.state != ToolButton.State.FREE and _hint_tb.badge_count <= 0:
		_request_reward_for_tool(_tool_hint_btn)
		return
	Tracker.inc_stat("hint_used")
	GameState.inc_game_total_stat(_game_type(), "hint_used_total")
	var sz: int = _level_config.get("size", 4)
	var board: Array = _board_view.get_cell_state_folded_board()
	var regs: Array = _puzzle["regions"]

	# 依次降级求解：错叉 → R1 → R2 → R3/R4 → 连锁推理
	var hint: Dictionary = HintEngine.find_mark_hint(board, sz, regs)
	if not hint["found"]:
		var sol: Array = _puzzle.get("solution", [])
		for r in range(sz):
			for c in range(sz):
				if (sol[r] as Array)[c] and _board_view.get_cell_state(r, c) == CellState.MARK:
					var _wm_cells: Array[Vector2i] = [Vector2i(r, c)]
					hint = {
						"found": true,
						"strategy": "",
						"cell": Vector2i(r, c),
						"unit_cells": _wm_cells,
						"description": tr("HINT_WRONG_MARK"),
						"wrong_mark": true,
					}
					break
			if hint["found"]:
				break
	if not hint["found"]:
		hint = HintEngine.find_r1_hint(board, sz, regs)
	if not hint["found"]:
		hint = HintEngine.find_r2_hint(board, sz, regs)
	if not hint["found"]:
		hint = HintEngine.find_r3_r4_hint(board, sz, regs)
	if not hint["found"]:
		hint = HintEngine.find_chain_hint(board, sz, regs)
	if not hint["found"]:
		if _level_config.get("bank_sp", false):
			_on_locate_btn_pressed()
		return
	if hint.get("strategy", "") == "R1_mark":
		var _empty_cells: Array[Vector2i] = []
		_board_view.set_hint_cells(_empty_cells, hint.get("cat_cell", Vector2i(-1, -1)))
	elif hint.has("cell"):
		var r1_focus: Vector2i = hint.get("cell", Vector2i(-1, -1))
		for uc in hint.get("unit_cells", []):
			var uc_v: Vector2i = uc as Vector2i
			if _board_view.get_cell_state(uc_v.x, uc_v.y) == CellState.CAT:
				r1_focus = uc_v
				break
		_board_view.set_hint_cells([], r1_focus)
	else:
		var hl: Array[Vector2i] = []
		for cell in hint.get("highlight_cells", []):
			hl.append(cell)
		_board_view.set_hint_cells(hl, Vector2i(-1, -1))
	_consume_tool(_tool_hint_btn)
	SoundManager.play(SoundManager.Kind.USE_HINT)
	GameState.mark_current_level_dirty()
	GameState.mark_dda_tool_or_revive_used()

	var _chain: Dictionary = hint.get("chain", {})
	if not _chain.is_empty() and (_chain.get("steps", []) as Array).size() == 0:
		var _key: Vector2i = hint.get("cell", Vector2i(-1, -1))
		var _contra_cells: Array[Vector2i] = []
		var _contra_type: String = _chain.get("contra_type", "")
		var _contra_idx: int = _chain.get("contra_index", 0)
		match _contra_type:
			"row":
				for _cc in range(sz):
					if CellState.is_blank(_board_view.get_cell_state(_contra_idx, _cc)):
						_contra_cells.append(Vector2i(_contra_idx, _cc))
			"col":
				for _rr in range(sz):
					if CellState.is_blank(_board_view.get_cell_state(_rr, _contra_idx)):
						_contra_cells.append(Vector2i(_rr, _contra_idx))
			"region":
				for _rr in range(sz):
					for _cc in range(sz):
						if (
							_puzzle["regions"][_rr][_cc] == _contra_idx
							and CellState.is_blank(_board_view.get_cell_state(_rr, _cc))
						):
							_contra_cells.append(Vector2i(_rr, _cc))
		var _all_cells: Array[Vector2i] = []
		if _key.x >= 0:
			_all_cells.append(_key)
			_board_view.play_r2_preview_cell(_key.x, _key.y)
		for _cv in _contra_cells:
			if _cv != _key:
				_all_cells.append(_cv)

		hint["contra_cells"] = _contra_cells
		_board_view.set_hint_cells(_all_cells, _key)

		var _contra_name: String
		match _contra_type:
			"row":
				_contra_name = tr("HINT_ROW") % (_contra_idx + 1)
			"col":
				_contra_name = tr("HINT_COL") % (_contra_idx + 1)
			"region":
				_contra_name = tr("HINT_REGION_UNIT") % _color_name_bbcode(_contra_idx)
			_:
				_contra_name = tr("HINT_SOME_UNIT")
		hint["description"] = tr("HINT_CONTRA_FULL") % _contra_name

		hint["unit_cells"] = _all_cells

	_enrich_hint_description(hint)

	var _hint_cell: Vector2i = hint.get("cell", Vector2i(-1, -1))
	var _hint_strategy: String = hint.get("strategy", "")
	var _hint_cell_state: int = (
		_board_view.get_cell_state(_hint_cell.x, _hint_cell.y)
		if _hint_cell.x >= 0
		else CellState.EMPTY
	)
	if (
		_hint_cell.x >= 0
		and _hint_strategy != "R1_mark"
		and _hint_strategy != "R2"
		and _hint_strategy != "R3"
		and _hint_strategy != "R4"
		and (_hint_cell_state == CellState.MARK or _hint_cell_state == CellState.DRAFT_CROSS)
	):
		hint["description"] = tr("HINT_WRONG_MARK")
		hint["wrong_mark"] = true
	_hint_data = hint

	_destroy_banner()
	_hint_overlay.show_hint(hint)
	_build_hint_highlights(hint)


# 清除按钮：擦掉全盘所有的叉（草稿 V4 变体下只擦草稿）
func _on_clear_btn_pressed() -> void:
	if _entry_anim_playing:
		return
	Tracker.track_btn_click(Tracker.Btn.CLEAR, self)
	Tracker.inc_stat("clear_used")
	GameState.inc_game_total_stat(_game_type(), "clear_used_total")
	if _is_complete or _wrong_guess_pending:
		return

	var variant: int = _get_draft_variant()
	var is_v4: bool = variant == ABTestManager.draft_mode.VALUE_AUTO_WIN_PERSIST
	if is_v4 and _draft_mode:
		var draft_marks: Dictionary = _collect_draft_marks()
		for key in draft_marks.keys():
			var pos: Vector2i = key as Vector2i
			var cell_view: CellView = _board_view.get_cell_view(pos.x, pos.y)
			if cell_view != null:
				cell_view.change_state({"state": CellState.EMPTY, "play_anim": false})
		_draft_root = Vector2i(-1, -1)
		_refresh_draft_terminal_state()
		_on_draft_changed_for_persist(true)
		return

	_exit_draft_mode_and_clear()
	var sz: int = _level_config.get("size", 4)

	var cleared_any: bool = false
	SoundManager.set_silent(true)
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.MARK:
				_board_view.set_cell_state(r, c, CellState.EMPTY)
				cleared_any = true
	SoundManager.set_silent(false)
	if cleared_any:
		SoundManager.play(SoundManager.Kind.UNMARK_X)
	_update_remaining()


# 应用 R2 提示：按四种模式在相应行 / 列 / 区域打叉
func _apply_r2_hint() -> void:
	var sz: int = _level_config.get("size", 4)
	var regs: Array = _puzzle["regions"]
	var reg: int = _hint_data.get("region", -1)
	var row: int = _hint_data.get("row", -1)
	var col: int = _hint_data.get("col", -1)
	match _hint_data.get("mode", ""):
		"r2a_row":
			for c in range(sz):
				if regs[row][c] != reg and CellState.is_blank(_board_view.get_cell_state(row, c)):
					_record_cell_change(row, c, CellState.EMPTY, CellState.MARK)
					_board_view.set_cell_state(
						row, c, CellState.MARK, true, true, BoardView.ChangeSource.HINT
					)
		"r2a_col":
			for r in range(sz):
				if regs[r][col] != reg and CellState.is_blank(_board_view.get_cell_state(r, col)):
					_record_cell_change(r, col, CellState.EMPTY, CellState.MARK)
					_board_view.set_cell_state(
						r, col, CellState.MARK, true, true, BoardView.ChangeSource.HINT
					)
		"r2b_row":
			for r in range(sz):
				for c in range(sz):
					if (
						regs[r][c] == reg
						and r != row
						and CellState.is_blank(_board_view.get_cell_state(r, c))
					):
						_record_cell_change(r, c, CellState.EMPTY, CellState.MARK)
						_board_view.set_cell_state(
							r, c, CellState.MARK, true, true, BoardView.ChangeSource.HINT
						)
		"r2b_col":
			for r in range(sz):
				for c in range(sz):
					if (
						regs[r][c] == reg
						and c != col
						and CellState.is_blank(_board_view.get_cell_state(r, c))
					):
						_record_cell_change(r, c, CellState.EMPTY, CellState.MARK)
						_board_view.set_cell_state(
							r, c, CellState.MARK, true, true, BoardView.ChangeSource.HINT
						)
	_validate_board()
	_update_remaining()


# 玩家点「应用提示」：按策略把提示落成实际标记 / 猫，并进入短暂冷却
func _on_hint_applied() -> void:
	Tracker.track_btn_click(Tracker.Btn.HINT_APPLY, self)
	Tracker.inc_stat("hint_apply_used")
	var strategy: String = _hint_data.get("strategy", "R1")
	if strategy == "R1_mark":
		for cell_v in _hint_data.get("unit_cells", []) as Array:
			var cell: Vector2i = cell_v as Vector2i
			if CellState.is_blank(_board_view.get_cell_state(cell.x, cell.y)):
				_record_cell_change(cell.x, cell.y, CellState.EMPTY, CellState.MARK)
				_board_view.set_cell_state(
					cell.x, cell.y, CellState.MARK, true, true, BoardView.ChangeSource.HINT
				)
		_validate_board()
		_update_remaining()
	elif strategy == "R3" or strategy == "R4":
		_apply_r3_r4_hint()
	elif strategy == "R2":
		_apply_r2_hint()
	elif strategy == "R4_chain" or strategy == "R5_chain":
		var cell: Vector2i = _hint_data.get("cell", Vector2i(-1, -1))
		if cell.x >= 0:
			_record_cell_change(cell.x, cell.y, CellState.EMPTY, CellState.MARK)
			_board_view.set_cell_state(
				cell.x, cell.y, CellState.MARK, true, true, BoardView.ChangeSource.HINT
			)
			_validate_board()
			_update_remaining()
	else:
		var cell: Vector2i = _hint_data.get("cell", Vector2i(-1, -1))
		if cell.x >= 0:
			if _hint_data.get("wrong_mark", false):
				_record_cell_change(cell.x, cell.y, CellState.MARK, CellState.EMPTY)
				_board_view.set_cell_state(
					cell.x, cell.y, CellState.EMPTY, true, true, BoardView.ChangeSource.HINT
				)
				VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)
			else:
				var prev: int = _board_view.get_cell_state(cell.x, cell.y)
				_record_cell_change(cell.x, cell.y, prev, CellState.CAT)
				_board_view.set_cell_state(
					cell.x, cell.y, CellState.CAT, true, true, BoardView.ChangeSource.HINT
				)
				_record_correct_cat(
					_decide_like_hand_for_correct_cat(LikeHandTrigger.HINT_R1_APPLY)
				)
			_update_remaining()
			_validate_board()
	# 应用完统一提交为一步（放猫的那次标为落猫步，便于撤销处理）
	var is_cat_step: bool = (
		(strategy == "" or strategy == "R1") and not _hint_data.get("wrong_mark", false)
	)
	_commit_current_step(is_cat_step, false)
	_close_chain_detail()
	_clear_hint_highlights()
	_board_view.clear_hint_cells()

	var _cd: float = 0.5
	if strategy == "R1" or strategy == "":
		if not _hint_data.get("wrong_mark", false):
			_cd = 0.8
	_hint_data = {}
	_hint_cooldown = true
	get_tree().create_timer(_cd).timeout.connect(func() -> void: _hint_cooldown = false)

	if not _is_complete and not _wrong_guess_pending:
		_show_banner_if_eligible(_banner_ad_position())


# ================= 埋点信息与策略分析面板 =================
# 拼埋点用的题目 ID：尺寸_题库_策略_序号_变换
func _build_qid() -> String:
	var sz: int = _level_config.get("size", 0)
	var src: String = _level_config.get("bank_source", "regular")
	var rank: int = _level_config.get("rank", 0)
	var tier: String = _level_config.get("bank_tier", "")

	var strategy: int
	if rank == 4 and tier == "H":
		strategy = 5
	elif rank == 5 and tier == "H":
		strategy = 7
	elif rank == 5:
		strategy = 6
	elif rank >= 1:
		strategy = rank
	else:
		strategy = 0
	var idx: int = _level_config.get("bank_idx", 0)
	var t: int = _level_config.get("bank_transform", 0)
	return "%d_%s_%d_%d_%d" % [sz, src, strategy, idx, t]


# 埋点用难度位：是否困难关（按 AB 有两种判定方式）
func _get_diffi() -> int:
	var lv: int = GameState.get_current_level()
	var is_hard: bool = (
		LevelData.is_hard_level_group_j(lv)
		if ABTestManager.rule_normal_rank.is_group_j()
		else LevelData.is_hard_level(lv)
	)
	return 1 if is_hard else 0


# 策略面板的 5 行静态配置：徽标、名称 key、描述 key、配色
const _RANK_STRATEGY_INFO: Array[Dictionary] = [
	{
		rank = 1,
		badge = "R1",
		name = "STRATEGY_UNIQUE_CANDIDATE",
		desc = "STRATEGY_DESC_UNIQUE_CANDIDATE",
		color = Color("#4caf50")
	},
	{
		rank = 2,
		badge = "R2",
		name = "STRATEGY_REGION_CONSTRAINT",
		desc = "STRATEGY_DESC_REGION_CONSTRAINT",
		color = Color("#2196f3")
	},
	{
		rank = 3,
		badge = "R3",
		name = "STRATEGY_SET_LOCKING",
		desc = "STRATEGY_DESC_SET_LOCKING",
		color = Color("#ff9800")
	},
	{
		rank = 4,
		badge = "R4",
		name = "STRATEGY_ADVANCED_LOCKING",
		desc = "STRATEGY_DESC_ADVANCED_LOCKING",
		color = Color("#f44336")
	},
	{
		rank = 5,
		badge = "R5",
		name = "STRATEGY_DEEP_CHAIN",
		desc = "STRATEGY_DESC_DEEP_CHAIN",
		color = Color("#9c27b0")
	},
]


# 取中文翻译；取不到就退回 tr()
func _tr_zh(key: String) -> String:
	var t: Translation = TranslationServer.get_translation_object("zh_CN")
	if t != null:
		var msg: String = t.get_message(key)
		if msg != "":
			return msg
	return tr(key)


# 懒构建策略分析浮层（标题 + 关闭按钮 + 行容器）
func _build_strategy_overlay() -> void:
	if _strategy_overlay != null:
		return
	_strategy_overlay = CanvasLayer.new()
	_strategy_overlay.layer = 20
	_strategy_overlay.visible = false
	get_tree().current_scene.add_child(_strategy_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strategy_overlay.add_child(bg)
	bg.gui_input.connect(func(_e: InputEvent) -> void: pass)
	_strategy_bg = bg

	var sf_panel := StyleBoxFlat.new()
	sf_panel.bg_color = Color(1, 1, 1, 1)
	sf_panel.corner_radius_top_left = 44
	sf_panel.corner_radius_top_right = 44

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sf_panel)
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -1600.0
	panel.offset_bottom = 0.0
	_strategy_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 50)
	margin.add_theme_constant_override("margin_right", 50)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 60)
	panel.add_child(margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 28)
	margin.add_child(outer_vbox)

	var title_row := HBoxContainer.new()
	outer_vbox.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = _tr_zh("GAME_STRATEGY_ANALYSIS")
	title_lbl.add_theme_font_size_override("font_size", 46)
	title_lbl.add_theme_color_override("font_color", Color("#222222"))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)

	var sf_close_n := StyleBoxFlat.new()
	sf_close_n.bg_color = Color(0.88, 0.88, 0.88, 1)
	sf_close_n.set_corner_radius_all(20)
	sf_close_n.content_margin_left = 24
	sf_close_n.content_margin_right = 24
	sf_close_n.content_margin_top = 10
	sf_close_n.content_margin_bottom = 10
	var sf_close_f := StyleBoxFlat.new()
	sf_close_f.bg_color = Color(0, 0, 0, 0)

	var close_btn := Button.new()
	close_btn.text = _tr_zh("GAME_CLOSE")
	close_btn.add_theme_font_size_override("font_size", 32)
	close_btn.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	close_btn.add_theme_stylebox_override("normal", sf_close_n)
	close_btn.add_theme_stylebox_override("hover", sf_close_n)
	close_btn.add_theme_stylebox_override("pressed", sf_close_n)
	close_btn.add_theme_stylebox_override("focus", sf_close_f)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(_on_strategy_close)
	title_row.add_child(close_btn)

	_strategy_vbox = VBoxContainer.new()
	_strategy_vbox.add_theme_constant_override("separation", 18)
	outer_vbox.add_child(_strategy_vbox)


# 打开策略分析浮层并填充内容
func _on_strategy_btn_pressed() -> void:
	if _strategy_overlay == null:
		return
	_populate_strategy_vbox()
	if _strategy_bg != null:
		_strategy_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_strategy_overlay.visible = true


# 关闭策略分析浮层
func _on_strategy_close() -> void:
	if _strategy_bg != null:
		_strategy_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strategy_overlay.visible = false


# 填充策略面板：5 行策略 + 当前档位 + 题库信息
func _populate_strategy_vbox() -> void:
	for child in _strategy_vbox.get_children():
		child.queue_free()
	for info: Dictionary in _RANK_STRATEGY_INFO:
		var steps: int = _strategy_steps[info["rank"] - 1]
		_strategy_vbox.add_child(_make_strategy_row(info, steps))

	var _bs: String = _level_config.get("bank_source", "")
	if not _bs.is_empty():
		var cur_strategy: int = GameState.get_current_strategy()
		var cur_rank: int = LevelData.strategy_to_rank(cur_strategy)
		var cur_tier: String = LevelData.strategy_to_tier(cur_strategy)
		var tier_str: String = "H" if cur_tier == "H" else "N"
		var strategy_lbl := Label.new()
		strategy_lbl.text = "当前档位  strategy=%d  R%d%s" % [cur_strategy, cur_rank, tier_str]
		strategy_lbl.add_theme_font_size_override("font_size", 28)
		strategy_lbl.add_theme_color_override("font_color", Color("#888888"))
		strategy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_strategy_vbox.add_child(strategy_lbl)

	if not _bs.is_empty():
		var src: String = _level_config.get("bank_source", "")
		var idx: int = _level_config.get("bank_idx", 0)
		var sz: int = _level_config.get("size", 0)
		var rank: int = _level_config.get("rank", 1)
		var src_text: String
		match src:
			"regular":
				src_text = _tr_zh("GAME_REGULAR_BANK")
			"lkstyle":
				src_text = _tr_zh("GAME_LK_OPTIMIZED_BANK")
			"lk_mod":
				src_text = "LK改题库"
			"lk":
				src_text = "LK原题库"
			"sp":
				src_text = "SP特殊关卡"
			"gc":
				src_text = "GC题库"
			_:
				src_text = src
		var src_lbl := Label.new()
		src_lbl.text = "%s  %dx%d  R%d  #%d" % [src_text, sz, sz, rank, idx]
		src_lbl.add_theme_font_size_override("font_size", 28)
		src_lbl.add_theme_color_override("font_color", Color("#888888"))
		src_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_strategy_vbox.add_child(src_lbl)


# 造一行策略：徽标、名称、说明与该策略用到的步数
func _make_strategy_row(info: Dictionary, steps: int) -> Control:
	var color: Color = info["color"]
	var used: bool = steps > 0

	var sf_bg := StyleBoxFlat.new()
	sf_bg.bg_color = Color(color.r, color.g, color.b, 0.12) if used else Color(0.95, 0.95, 0.95, 1)
	sf_bg.set_corner_radius_all(18)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", sf_bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	margin.add_child(hbox)

	var sf_badge := StyleBoxFlat.new()
	sf_badge.bg_color = color if used else Color(0.72, 0.72, 0.72, 1)
	sf_badge.set_corner_radius_all(12)
	sf_badge.content_margin_left = 16
	sf_badge.content_margin_right = 16
	sf_badge.content_margin_top = 6
	sf_badge.content_margin_bottom = 6

	var badge_panel := PanelContainer.new()
	badge_panel.add_theme_stylebox_override("panel", sf_badge)
	badge_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(badge_panel)

	var badge_lbl := Label.new()
	badge_lbl.text = info["badge"]
	badge_lbl.add_theme_font_size_override("font_size", 30)
	badge_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	badge_panel.add_child(badge_lbl)

	var desc_vbox := VBoxContainer.new()
	desc_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(desc_vbox)

	var name_lbl := Label.new()
	name_lbl.text = _tr_zh(info["name"])
	name_lbl.add_theme_font_size_override("font_size", 34)
	name_lbl.add_theme_color_override(
		"font_color", Color("#333333") if used else Color(0.65, 0.65, 0.65, 1)
	)
	desc_vbox.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = _tr_zh(info["desc"])
	sub_lbl.add_theme_font_size_override("font_size", 26)
	sub_lbl.add_theme_color_override("font_color", Color("#888888"))
	desc_vbox.add_child(sub_lbl)

	var count_lbl := Label.new()
	count_lbl.text = (_tr_zh("GAME_STEPS") % steps) if used else _tr_zh("GAME_UNUSED")
	count_lbl.add_theme_font_size_override("font_size", 34)
	count_lbl.add_theme_color_override("font_color", color if used else Color(0.72, 0.72, 0.72, 1))
	count_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_lbl.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(count_lbl)

	return panel


# ================= 对外查询（调试接口） =================
# 返回所有答案猫的屏幕坐标，供调试 HTTP 接口截图定位
func get_solution_cat_positions() -> Array:
	var result: Array = []
	if _puzzle.is_empty() or not _puzzle.has("solution"):
		return result
	if _board_view == null:
		return result
	var solution: Array = _puzzle["solution"]
	var canvas_xform: Transform2D = _board_view.get_global_transform_with_canvas()
	var screen_xform: Transform2D = get_viewport().get_screen_transform()
	for r in range(solution.size()):
		var row: Array = solution[r]
		for c in range(row.size()):
			if not row[c]:
				continue
			var local_rect: Rect2 = _board_view.cell_to_local_rect(r, c)
			var local_center: Vector2 = local_rect.position + local_rect.size * 0.5
			var screen_pos: Vector2 = screen_xform * (canvas_xform * local_center)
			result.append({"x": screen_pos.x, "y": screen_pos.y})
	return result
