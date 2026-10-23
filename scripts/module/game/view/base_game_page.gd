## 共享棋盘页面：组织输入、工具、生命、提示、残局与视觉反馈，普通关和每日关在此复用。
class_name BaseGamePage
extends UIFrameWindow

# 不少私有成员只给子类用，这里关掉「未使用私有变量」告警
@warning_ignore_start("unused_private_class_variable")

# ---- 预制体：格子、点赞手势、三种规则条 ----
const _CELL_SCENE: PackedScene = preload("res://assets/prefab/cell.tscn") # 棋盘单格（提示高亮也会临时实例化它）
const _CONFLICT_LINE_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/conflict_line.tscn"
)
## 点赞手势（比心 / 鼓掌 / 吹号…）
const _LIKE_HAND_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/game_like_hand.tscn"
)
## 规则条 V0：三条纯文字
const _RULE_INFO_BAR_V0_SCENE: PackedScene = preload(
	"res://scripts/module/game/ui/compont/rule_info_bar_v0.tscn"
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

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _anim_player: AnimationPlayer = $AnimationPlayer # 页面开场动画
@onready var _anim_correct: AnimationPlayer = $AnimCorrectPrompt # 数量变化时的正确提示动画
@onready var _board_container: Control = $Root/VBoxContainer/BoardContainer # 棋盘容器，尺寸变化时触发重排
@onready var _board_outer_glow: BoardOuterGlow = $Root/VBoxContainer/BoardContainer/BoardOuterGlow

@onready var _anim_board_glow: AnimationPlayer = $AnimBoardGlow
@onready var _board_view: BoardView = $Root/VBoxContainer/BoardContainer/BoardView # 棋盘视图：全盘状态的唯一真源
@onready var _clock_timer: Timer = $Root/ClockTimer # 对局计时器，由子类启动
@onready var _hint_overlay: HintOverlay = $Root/HintOverlay # 提示浮层（说明文字 + 应用/关闭按钮）
@onready var _rules_bg: Panel = $Root/VBoxContainer/RuleBar/Control/RulesBg # 规则条背景板

@onready var _rule_label3: Label = $Root/VBoxContainer/RuleBar/Control/RuleLabel3 # 第 3 条规则文字

## 第 1 条规则文字（规则条会被整块替换，故用 get_node_or_null）
@onready var _rule_label1: Label = get_node_or_null("Root/VBoxContainer/RuleBar/Control/RuleLabel1")
@onready var _rule_label2: Label = get_node_or_null("Root/VBoxContainer/RuleBar/Control/RuleLabel2") # 第 2 条规则文字
## 三条规则的小示意图（换规则条后要重新抓引用）
@onready var _rule_diagram1: TextureRect = get_node_or_null(
	"Root/VBoxContainer/RuleBar/Control/RuleDiagram1"
)
@onready var _rule_diagram2: TextureRect = get_node_or_null(
	"Root/VBoxContainer/RuleBar/Control/RuleDiagram2"
)
@onready var _rule_diagram3: TextureRect = get_node_or_null(
	"Root/VBoxContainer/RuleBar/Control/RuleDiagram3"
)

@onready var _bt: BottomTools = $Root/VBoxContainer/ToolsRow/BottomTools

@onready var _apply_btn: Button = get_node_or_null("Root/VBoxContainer/ToolsRow/ApplyBtn") as Button

@onready var _apply_anim: AnimationPlayer = get_node_or_null("AnimApplyBtn") as AnimationPlayer # 草稿「应用」按钮动画
@onready var _remaining_label: RichTextLabel = $Root/VBoxContainer/CatHeartRow/Target/CatCountLabel # 剩余猫数量文字
## 数字模式下的目标节点（进度条模式下隐藏）
@onready
var _progress_target: Control = get_node_or_null("Root/VBoxContainer/CatHeartRow/Target") as Control # 猫数量目标节点

@onready var _target_cat_face_icon: TextureRect = (
	get_node_or_null("Root/VBoxContainer/CatHeartRow/Target/CatFaceIcon") as TextureRect
)

@onready var _target_costume_cat: SpineSprite = (
	get_node_or_null("Root/VBoxContainer/CatHeartRow/Target/CostumeCat") as SpineSprite
)

var _target_costume_applied_id: int = -1

var _cat_progress: Control = null

var _cat_progress_total: int = -1

var _cat_progress_region_order: Array[int] = []

var _cat_progress_rotate_start: int = -1

var _cat_progress_rotate_override: int = -1

@onready var _life_bar_progress: HealthBarBase = $Root/VBoxContainer/CatHeartRow/HeartBg

var _life_bar: HealthBarBase


func _ready() -> void:
	_life_bar = _life_bar_progress

	_bullets_area = BulletsArea.ensure_on_page(self, $Root as Control, _hint_overlay)
	if _bullets_area != null:
		_bullets_area.barrage_displayed.connect(_on_game_barrage_displayed)
		_bullets_area.barrage_spawn_failed.connect(_on_game_barrage_spawn_failed)
	UniKitManager.ad_shown.connect(_on_game_barrage_ad_shown)
	UniKitManager.ad_impression_received.connect(_on_game_barrage_ad_impression)
	UniKitManager.ad_closed.connect(_on_game_barrage_ad_closed)
	UniKitManager.ad_error_occurred.connect(_on_game_barrage_ad_error)


# ---- 底部广告位 ----
@onready var _ad_banner: Control = $Root/VBoxContainer/AdBanner # banner 广告占位
@onready var _ad_down_adapt: Control = $Root/VBoxContainer/AdDownAdaptHolder # 底部安全区占位（算 banner 高度用）

## 策略分析按钮（只有非 release 包可见）
@onready
var _strategy_btn: Button = get_node_or_null("Root/VBoxContainer/Header/StrategyBtn") as Button # 策略分析入口

var _game_barrage_logic: GameBarrageLogic = GameBarrageLogic.new()
var _game_barrage_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _game_barrage_mode: int = GameBarrageLogic.MODE_DISABLED
var _game_barrage_session_active: bool = false
var _game_barrage_page_supported: bool = false
var _game_barrage_ad_active: bool = false
var _game_barrage_settings_open: bool = false
var _bullets_area: BulletsArea = null

## 规则条上三块高亮（违规时闪哪条规则）
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

var _level_kind: int = LevelKind.MAIN
var _lives: int = 3 # 剩余生命（0~3）

var _lives_inf: bool = false

var _life_cap: int = 3
var _mistake_count: int = 0 # 本局错误落子次数
var _is_complete: bool = false # 是否已判定通关（之后屏蔽一切操作）
var _wrong_guess_pending: bool = false # 错落反馈播放中，期间屏蔽输入

var _wrong_guess_lock_token: int = 0

var _screen_shake_tween: Tween = null
var _screen_shake_rest_x: float = 0.0

const _MOUSE_POINTER_INDEX: int = -2

var _touch_slots: Dictionary = {}

var _active_slot: BoardTouchSlot = null
var _normal_scheme: BoardInputScheme # 普通落子输入方案

var _draft_scheme: BoardInputScheme # 草稿模式输入方案

var _current_scheme: BoardInputScheme = null

const _NO_POINTER_INDEX: int = -1

var _locked_pointer_index: int = _NO_POINTER_INDEX

var _last_placed_count: int = -1 # 上次显示的已放猫数（-1 表示还没初始化）

var _score_model: GameScoreModel = GameScoreModel.new()
var _combo_feedback_view: Node = null # 连击飘字视图（子类里赋值）

var _se_count: int = 0

var _se_last_step: int = 0

var _se_step_pending_this_place: bool = false

var _dt_cross_landing_this_place: bool = false

var _se_amortized_step: int = -1

var _se_fly_token: int = 0

var _conflict_anim_token: int = 0

var _active_conflict_lines: Array[LineCrossConnector] = []

var _conflict_target_positions: Array[Vector2i] = []

var _se_last_fly_launch_ms: int = 0

var _missed_cross_token: int = 0

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

var _tool_reward_ad_opportunities: Dictionary = {}

var _tool_reward_ad_seq: int = 0

static var _tool_reward_ad_check_pending: bool = false

const _MOUSE_STEP_INTERVAL_SEC: float = 0.85
const _MOUSE_MARK_ANIM_SEC: float = 1.2
const _MOUSE_CAT_ANIM_SEC: float = 2.0
const _MOUSE_MARK_ANIM: String = "MouseAppear1"
const _MOUSE_LAST_MARK_ANIM: String = "MouseAppear2"
const _MOUSE_CAT_ANIM: String = "MouseAppear3"
var _mouse_tool_busy: bool = false
var _mouse_tool_token: int = 0
var _mouse_completion_pending: bool = false
var _mouse_rng := RandomNumberGenerator.new()

# ---- 草稿模式状态 ----
var _draft_mode: bool = false # 是否处于草稿模式

var _draft_lethal_wrong_cells: Array[Vector2i] = []

## 草稿提交中，期间不弹自动完成按钮
var _applying_draft_commit: bool = false

var _combo_visual_suppressed: bool = false # 草稿提交期间先不弹连击飘字

var _draft_busy: bool = false

var _draft_apply_conflict_shown: bool = false

var _draft_apply_violated_rules: Array[int] = []

var _draft_used_this_level: bool = false

var _draft_enter_ms: int = 0 # 进入草稿模式的时刻（毫秒），用于统计停留时长

const _DRAFT_UI_LOCK_SEC: float = 0.3

var _step_dirty: bool = false

var _hint_mutex: HintMutex = HintMutex.new() # 提示互斥锁（本文件未使用，留给子类）

# ---- 空闲引导：长时间不操作就闪一下道具按钮 ----
var _idle_hint_delay: float = 20.0 # 多久没操作就开始提示（秒）
var _idle_time: float = 0.0 # 已累计的空闲时长（秒）

const IDLE_HINT_REPEAT_PLAY_SEC: float = 10.0 # 可重复模式下单次提示播放时长（秒）

const _WIN_REPLAY_FULL_FPS_SEC: float = 6.0
var _idle_hint_play_time: float = 0.0 # 本轮提示已播时长（秒）

var _idle_hint_round_count: int = 0

var _dead_board_armed: bool = false

var _dead_board_wait_sec: float = 0.0

const _DEAD_BOARD_HARD_HINT_STRATEGIES: Array[String] = ["R4", "R4b", "R4_chain", "R5_chain"]

var _entry_anim_playing: bool = false # 开场动画还在播（期间屏蔽大部分操作）

var _tool_btns_locked: bool = false

var _rule_tweens: Array[Tween] = []
var _rule_active_highlights: Array[TextureRect] = []

var _stat_status: String = "" # 埋点用：本次进入对局的状态（new/restart/continue），子类赋值
var _stat_start_ms: int = 0 # 埋点用：本局开始时刻（毫秒），子类赋值

var _like_hand_state: Dictionary = {
	"in_game_sec": 0.0,
	"last_cat_sec": 0.0,
	"triggered_count": 0,
	"clock_paused": false,
	"has_seen_first_cat": false,
	"cat_place_times": {},
	"missed_cross_triggered_cats": {},
	"latest_cat_key": "",
	"manually_x_marked_cells": {},
	"hint_marked_x_cells": {},
}

var _continue_play_sec: float = 0.0

var _continue_clock_started: bool = false

## 可触发 R4+ 反馈（吹号）的格子缓存
var _r4_plus_cells: Dictionary = {}


# ================= 模式标识与规则条外观 =================
## 本页面的玩法类型标识，子类覆写（基类按普通关算）
func _game_type() -> String:
	return Tracker.GameType.NORMAL


func _apply_rule_info_bar() -> void:
	var rule_bar := get_node_or_null("Root/VBoxContainer/RuleBar")
	if rule_bar == null:
		return

	if rule_bar.get_meta("_rule_bar_v0", false):
		_refresh_rule_bar_node_refs(rule_bar)
		return

	_stop_rule_highlight()
	var vbox: Control = rule_bar.get_parent()
	var idx: int = rule_bar.get_index()
	vbox.remove_child(rule_bar)
	rule_bar.queue_free()
	var new_bar: Control = _RULE_INFO_BAR_V0_SCENE.instantiate()
	new_bar.name = "RuleBar"
	new_bar.custom_minimum_size = Vector2(1080, 170)
	new_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	new_bar.size_flags_stretch_ratio = 0.0
	new_bar.set_meta("_rule_bar_v0", true)
	vbox.add_child(new_bar)
	vbox.move_child(new_bar, idx)
	_refresh_rule_bar_node_refs(new_bar)


## 规则条重建后重新抓取内部节点引用（含 3 块高亮）
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


func _apply_rule_bar_style() -> void:
	if _rule_diagram1 == null or _rule_diagram3 == null:
		return
	_rule_label1.visible = true
	_rule_label2.visible = true
	_rule_label3.visible = true
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


## 取（并缓存）指定字间距的字体副本
func _get_rule_icon_text_font(letter_spacing: int) -> FontVariation:
	if not _rule_icon_text_fonts.has(letter_spacing):
		var fv := _RULE_LABEL_MEDIUM_FONT.duplicate() as FontVariation
		fv.spacing_glyph = letter_spacing
		_rule_icon_text_fonts[letter_spacing] = fv
	return _rule_icon_text_fonts[letter_spacing]


## 统一「图标 + 文字」模式下的字号、行距与文字框位置
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


## 设置控件的左右偏移
func _set_h(node: Control, left: float, right: float) -> void:
	node.offset_left = left
	node.offset_right = right


## 设置控件的四边偏移
func _set_rect(node: Control, left: float, right: float, top: float, bottom: float) -> void:
	node.offset_left = left
	node.offset_right = right
	node.offset_top = top
	node.offset_bottom = bottom


## 恢复本局计分与计时状态，初始化规则、生命和棋盘交互，并更新异步演出令牌。
func on_show(params: Dictionary = {}) -> void:
	_reset_tool_reward_ad_opportunities()

	PowerSaver.wake(PowerSaver.SHOW_FULL_FPS_SEC)

	_eval_interstitial_cache = null

	if LanguageManager.resolve_language_family() == "jp":
		ABTestManager.dye_at_game_start_with_jp()

	ABTestManager.doubletap_protect.reset_high_freq_state()
	super.on_show(params)

	SoundManager.start_bgm()

	HelpshiftManager.request_unread()

	set_process(true)

	(
		_score_model
		. restore(
			{
				"score": params.get("restore_score", 0),
				"combo": params.get("restore_combo", 0),
				"max_combo": params.get("restore_max_combo", 0),
			}
		)
	)
	_se_count = params.get("restore_se_count", 0)

	_se_last_step = int(params.get("restore_se_last_step", 0))

	_operable_sec = float(params.get("restore_operable_sec", 0.0))
	_cat_toast_tracker.restore_state(params.get("restore_cat_toast", {}))

	if params.has("restore_near_death_fired"):
		_near_death_fired = bool(params["restore_near_death_fired"])
		_near_death_level_key = str(params.get("restore_near_death_level_key", ""))

	_near_death_blocked = (
		bool(params.get("restore_near_death_blocked", false))
		or str(params.get("_tracker_status", "")) == Tracker.GameStatus.RESTART
	)

	_wrong_zone_tracker.restore_state(params.get("restore_wrong_zone", {}))
	_wrong_zone_idle_sec = 0.0
	_stop_wrong_zone_highlight()
	_se_amortized_step = -1

	_se_fly_token += 1

	_missed_cross_token += 1

	_full_mark_defer_token += 1

	_cancel_misplace_conflict("_on_show")

	_cancel_mouse_tool_flow()
	_mouse_rng.randomize()

	_apply_rule_info_bar()

	_apply_rule_bar_style()

	_life_bar.apply_kind(false)

	var life_bars: Array[Control] = _life_bar_nodes()
	for bar_node: Control in life_bars:
		if bar_node is HealthBarBase:
			(bar_node as HealthBarBase).stop_highlight_glow()
	_mount_progress_bar()

	_apply_pattern_mode()

	if not _board_view.cell_state_changed.is_connected(_on_board_cell_state_changed_for_r4):
		_board_view.cell_state_changed.connect(_on_board_cell_state_changed_for_r4)
	if not _board_view.cell_state_changed.is_connected(_on_cell_changed_for_hint_cross):
		_board_view.cell_state_changed.connect(_on_cell_changed_for_hint_cross)

	if not _board_view.cell_state_changed.is_connected(_on_cell_changed_for_full_mark):
		_board_view.cell_state_changed.connect(_on_cell_changed_for_full_mark)

	if not _board_view.cell_state_changed.is_connected(_on_cell_changed_for_cat_toast):
		_board_view.cell_state_changed.connect(_on_cell_changed_for_cat_toast)

	if not _board_view.cell_state_changed.is_connected(_on_cell_changed_for_near_death):
		_board_view.cell_state_changed.connect(_on_cell_changed_for_near_death)

	if not _board_view.cell_state_changed.is_connected(_on_cell_changed_for_wrong_zone):
		_board_view.cell_state_changed.connect(_on_cell_changed_for_wrong_zone)

	if not _board_view.cell_state_changed.is_connected(_on_cell_changed_for_today_marks):
		_board_view.cell_state_changed.connect(_on_cell_changed_for_today_marks)

	if (
		not OS.has_feature("rel")
		and not _board_view.cell_state_changed.is_connected(_on_cell_changed_for_today_stats_log)
	):
		_board_view.cell_state_changed.connect(_on_cell_changed_for_today_stats_log)

	if (
		ABTestManager.found_cat_animation.should_blink_all_found()
		and not _board_view.cell_state_changed.is_connected(_on_cell_changed_for_found_blink_all)
	):
		_board_view.cell_state_changed.connect(_on_cell_changed_for_found_blink_all)

	_anim_player.play("Appear")
	_anim_player.seek(0.0, true)
	_anim_player.pause()

	_init_session_state()

	_cat_streak = int(params.get("restore_cat_streak", 0))
	_cross_at_first_cat = int(params.get("restore_cross_at_first_cat", -1))

	if not _board_container.resized.is_connected(_on_board_container_resized):
		connect_managed(_board_container.resized, _on_board_container_resized)

	if not GameState.tool_count_changed.is_connected(_on_tool_count_changed):
		connect_managed(GameState.tool_count_changed, _on_tool_count_changed)

	if not PurchaseManager.vip_status_changed.is_connected(_on_vip_status_changed):
		connect_managed(PurchaseManager.vip_status_changed, _on_vip_status_changed)

	_banner_suppressed = false

	if not UIManager.events.window_shown.is_connected(_on_any_window_shown):
		connect_managed(UIManager.events.window_shown, _on_any_window_shown)
	if not UIManager.events.window_hidden.is_connected(_on_any_window_hidden):
		connect_managed(UIManager.events.window_hidden, _on_any_window_hidden)


func _on_tool_count_changed(kind: String, count: int) -> void:
	_bt.refresh_kind(kind, count)


func _prop_name_of(kind: String) -> String:
	match kind:
		ToolKind.HINT:
			return Tracker.Prop.HINT
		ToolKind.LOCATE:
			return Tracker.Prop.LOCATE
		ToolKind.MOUSE:
			return Tracker.Prop.MOUSE
		ToolKind.DRAFT:
			return Tracker.Prop.DRAFT
	return ""


func _save_tool_count(kind: String, count: int) -> void:
	if kind != "":
		GameState.set_tool_count(kind, count)


func _consume_tool(kind: String, vibrate: bool = true, allow_reward_ad: bool = true) -> bool:
	if kind == "":
		return false

	if _is_free_kind(kind):
		if vibrate:
			VibrateManager.play_at(VibrateManager.Pos.TOOL_USE)

		mark_continue_clock_started()
		_record_game_barrage_action()
		_note_wrong_zone_activity()
		_record_elo_v2_action("tool")
		return true
	var count: int = GameState.get_tool_count(kind)
	if count <= 0:
		if allow_reward_ad:
			_request_reward_for_tool(kind)
		return false
	var new_count: int = count - 1
	if new_count == 0:
		_last_tool_deplete_ms = Time.get_ticks_msec()

	_save_tool_count(kind, new_count)
	if vibrate:
		VibrateManager.play_at(VibrateManager.Pos.TOOL_USE)

	var prop_name: String = _prop_name_of(kind)
	if prop_name != "":
		Tracker.track_prop_use(prop_name, get_scr_name(), 1, new_count)

	mark_continue_clock_started()
	_record_game_barrage_action()
	_note_wrong_zone_activity()
	_record_elo_v2_action("tool")
	return true


func _record_elo_v2_action(_action: String) -> void:
	return


func _sync_tools_from_state() -> void:
	_bt.sync_from_state(_free_kinds())


func _is_free_kind(kind: String) -> bool:
	if kind != ToolKind.LOCATE and kind != ToolKind.HINT:
		return false

	if _is_free_tool_zone():
		return true
	if debug_force_free_tool == "all":
		return true
	return debug_force_free_tool == kind


func _free_kinds() -> Array[String]:
	var candidates: Array[String] = [ToolKind.LOCATE, ToolKind.HINT]
	var out: Array[String] = []
	for kind: String in candidates:
		if _is_free_kind(kind):
			out.append(kind)
	return out


## 当前关卡是否处于「道具全免费」区间
func _is_free_tool_zone() -> bool:
	return not ABTestManager.reward_unlock_level.is_reward_required_at(
		GameState.get_current_level()
	)


func _tool_ad_toast_key() -> String:
	var cfg: NoNetworkRemindConfig = ABTestManager.no_network_remind
	if not cfg.is_enabled():
		return "AD_TOAST_NOT_READY"
	if not UniKitManager.is_online():
		return "AD_TOAST_NO_NETWORK"
	return "AD_TOAST_NOT_FILLED" if cfg.covers_no_fill() else "AD_TOAST_NOT_READY"


static var _ad_valid_query_in_flight: bool = false

var _last_known_has_fill: bool = true

var _fill_positive_epoch: int = 0

const _FILL_RECHECK_MIN_INTERVAL_SEC: float = 5.0
var _last_fill_query_msec: int = 0

var _ad_badge_on: bool = false


func _set_ad_badge(on: bool) -> void:
	_ad_badge_on = on
	_bt.set_ad_unavailable(on)


func _reeval_ad_unavailable_badge() -> void:
	if _bt == null:
		return
	var cfg: NoNetworkRemindConfig = ABTestManager.no_network_remind
	if not cfg.is_enabled():
		_set_ad_badge(false)
		return
	if not cfg.covers_no_fill():
		_set_ad_badge(not UniKitManager.is_online())
		return

	_set_ad_badge(not _last_known_has_fill)


func _refresh_ad_unavailable_badge(known_no_fill: bool = false) -> void:
	if _bt == null:
		return
	if not ABTestManager.no_network_remind.is_enabled():
		_set_ad_badge(false)
		return
	if known_no_fill:
		_last_known_has_fill = false
		_reeval_ad_unavailable_badge()
		return
	if _ad_valid_query_in_flight:
		return

	_ad_valid_query_in_flight = true

	_last_fill_query_msec = Time.get_ticks_msec()

	var epoch_at_request: int = _fill_positive_epoch

	var has_fill: bool = await UniKitManager.is_reward_valid(
		AdPlacement.REWARD, _reward_pos_for(ToolKind.HINT)
	)
	_ad_valid_query_in_flight = false

	if not has_fill and epoch_at_request != _fill_positive_epoch:
		return

	_last_known_has_fill = has_fill

	if not is_showing() or _bt == null:
		return
	_reeval_ad_unavailable_badge()


const _NET_POLL_INTERVAL_SEC: float = 1.0

var _net_poll_timer: Timer = null

var _last_known_online: bool = true


func _arm_network_poll() -> void:
	if not ABTestManager.no_network_remind.is_enabled():
		return
	_last_known_online = UniKitManager.is_online()

	if not UniKitManager.ad_loaded.is_connected(_on_ad_loaded):
		UniKitManager.ad_loaded.connect(_on_ad_loaded)
	if _net_poll_timer != null:
		return
	_net_poll_timer = create_tick(_NET_POLL_INTERVAL_SEC, _on_network_poll_tick)


func _on_network_poll_tick() -> void:
	if _bt == null:
		return
	if not ABTestManager.no_network_remind.is_enabled():
		return
	var online: bool = UniKitManager.is_online()
	if online != _last_known_online:
		_last_known_online = online
		_reeval_ad_unavailable_badge()
	_maybe_recheck_fill()


func _maybe_recheck_fill() -> void:
	if not _ad_badge_on:
		return

	if not ABTestManager.no_network_remind.covers_no_fill():
		return
	if _ad_valid_query_in_flight:
		return
	if Time.get_ticks_msec() - _last_fill_query_msec < int(_FILL_RECHECK_MIN_INTERVAL_SEC * 1000.0):
		return
	_refresh_ad_unavailable_badge()


func _on_ad_loaded(placement_id: String) -> void:
	if placement_id != AdPlacement.REWARD:
		return

	_fill_positive_epoch += 1
	if _bt == null or not is_showing():
		return
	if not ABTestManager.no_network_remind.is_enabled():
		return
	if _last_known_has_fill:
		return
	_last_known_has_fill = true
	_reeval_ad_unavailable_badge()


func set_tool_count(tool_name: String, count: int) -> void:
	_save_tool_count(tool_name, count)


const MOUSE_UNLOCK_LEVEL: int = 21


func _is_mouse_tool_enabled() -> bool:
	return ABTestManager.prop_mouse.is_enabled()


func _is_mouse_tool_unlocked() -> bool:
	return GameState.get_current_level() >= MOUSE_UNLOCK_LEVEL


func _try_start_mouse_tool() -> void:
	if (
		not _is_mouse_tool_enabled()
		or _mouse_tool_busy
		or _entry_anim_playing
		or _hint_cooldown
		or _tool_btns_locked
	):
		return

	if not _is_mouse_tool_unlocked():
		return

	Tracker.track_btn_click(Tracker.Btn.MOUSE, self)
	_reset_idle_hint()
	if _is_complete or _wrong_guess_pending or _puzzle.is_empty():
		return
	var board: Array = _board_view.get_board()
	var solution: Array = _puzzle.get("solution", [])
	var regions: Array = _puzzle.get("regions", [])
	var targets: Array[Dictionary] = MouseToolSelector.select_targets(
		board, solution, regions, _mouse_rng
	)
	if targets.is_empty():
		return

	if not _consume_tool(ToolKind.MOUSE):
		return
	Tracker.inc_stat("mouse_used")
	GameState.inc_game_total_stat(_game_type(), "mouse_used_total")
	GameState.mark_current_level_dirty()
	if not _isolate_onefish_main_state():
		GameState.mark_dda_tool_or_revive_used()
		GameState.inc_today_tool_consumed()

	_count_board_step("mouse")
	_mouse_tool_busy = true
	_mouse_tool_token += 1
	var token: int = _mouse_tool_token

	_reset_all_touch_strokes()
	_board_view.set_touch_enabled(false)
	var last_target: Dictionary = targets[targets.size() - 1]
	var tail_sec: float = _MOUSE_CAT_ANIM_SEC if bool(last_target.is_cat) else _MOUSE_MARK_ANIM_SEC
	var flow_sec: float = float(targets.size() - 1) * _MOUSE_STEP_INTERVAL_SEC + tail_sec

	UIManager.block_input_briefly(self, flow_sec)
	_record_mouse_solution_step(targets)
	_run_mouse_tool_flow(targets, token)


func _run_mouse_tool_flow(targets: Array[Dictionary], token: int) -> void:
	for i: int in range(targets.size()):
		if i > 0:
			await get_tree().create_timer(_MOUSE_STEP_INTERVAL_SEC).timeout
			if not _is_mouse_flow_valid(token):
				return
		var target: Dictionary = targets[i]
		var cell: Vector2i = target.cell
		if bool(target.is_cat):
			(
				_board_view
				. set_cell_state(
					cell.x,
					cell.y,
					CellState.CAT,
					true,
					true,
					BoardView.ChangeSource.MOUSE,
					_MOUSE_CAT_ANIM,
					true,
				)
			)

			_record_correct_cat(_decide_like_hand_for_correct_cat(LikeHandTrigger.LOCATE))

			if QueendokuCore.is_complete(
				_board_view.get_board(), _level_config.get("size", 4), _puzzle.get("regions", [])
			):
				_mouse_completion_pending = true

				_update_remaining()
				_validate_board()
				return
			await get_tree().create_timer(_MOUSE_CAT_ANIM_SEC).timeout
			if not _is_mouse_flow_valid(token):
				return
			_finish_mouse_tool_flow(token)
			return

		var is_last_target: bool = i == targets.size() - 1
		var anim_name: String = _MOUSE_LAST_MARK_ANIM if is_last_target else _MOUSE_MARK_ANIM
		(
			_board_view
			. set_cell_state(
				cell.x,
				cell.y,
				CellState.MARK,
				true,
				true,
				BoardView.ChangeSource.MOUSE,
				anim_name,
				false,
			)
		)
		if is_last_target:
			await get_tree().create_timer(_MOUSE_MARK_ANIM_SEC).timeout
			if not _is_mouse_flow_valid(token):
				return
			_finish_mouse_tool_flow(token)
			return


func _is_mouse_flow_valid(token: int) -> bool:
	return token == _mouse_tool_token and _mouse_tool_busy and is_showing()


func _await_mouse_completion_anim_if_needed() -> bool:
	if not _mouse_completion_pending:
		return true
	var token: int = _mouse_tool_token
	await get_tree().create_timer(_MOUSE_CAT_ANIM_SEC).timeout
	if not _is_mouse_flow_valid(token):
		return false
	_mouse_completion_pending = false
	_mouse_tool_busy = false
	return true


func _finish_mouse_tool_flow(token: int) -> void:
	if not _is_mouse_flow_valid(token):
		return
	_mouse_tool_busy = false
	_update_remaining()
	_validate_board()
	if not _is_complete:
		_board_view.set_touch_enabled(true)


func _cancel_mouse_tool_flow() -> void:
	var was_busy: bool = _mouse_tool_busy
	_mouse_tool_token += 1
	_mouse_tool_busy = false
	_mouse_completion_pending = false
	if _board_view != null and is_instance_valid(_board_view):
		_board_view.set_touch_enabled(true)
	if was_busy:
		var blocker: Node = get_node_or_null("_InputBlocker")
		if blocker != null:
			remove_child(blocker)


func _reset_tool_reward_ad_opportunities() -> void:
	_tool_reward_ad_seq += 1
	_tool_reward_ad_opportunities.clear()


func _get_tool_reward_ad_opportunity(kind: String, position: String) -> Dictionary:
	if not _tool_reward_ad_opportunities.has(kind):
		_tool_reward_ad_opportunities[kind] = {
			"show_id": UniKitManager.stats_ad_show_timing(AdPlacement.REWARD, position),
			"became_valid_reported": false,
		}
	return _tool_reward_ad_opportunities[kind]


func _query_tool_reward_ad_ready(
	opportunity: Dictionary, position: String, is_new_opportunity: bool, seq: int
) -> bool:
	var show_id: String = opportunity["show_id"]
	if not is_new_opportunity:
		_ad_valid_query_in_flight = true
		var ad_valid: bool = await UniKitManager.is_reward_valid(AdPlacement.REWARD, position)
		_ad_valid_query_in_flight = false
		if seq != _tool_reward_ad_seq or not is_showing():
			return false
		if not ad_valid:
			return false
		if not opportunity["became_valid_reported"]:
			UniKitManager.stats_ad_became_valid(AdPlacement.REWARD, position, show_id)
			opportunity["became_valid_reported"] = true
	return await UniKitManager.is_reward_ready(AdPlacement.REWARD, position, show_id)


func _request_reward_for_tool(kind: String) -> void:
	if Time.get_ticks_msec() - _last_tool_deplete_ms < 800:
		return
	if _tool_reward_ad_check_pending or _ad_valid_query_in_flight or not is_showing():
		return
	_tool_reward_ad_check_pending = true
	var seq: int = _tool_reward_ad_seq
	var position: String = _reward_pos_for(kind)
	var is_new_opportunity: bool = not _tool_reward_ad_opportunities.has(kind)
	var opportunity: Dictionary = _get_tool_reward_ad_opportunity(kind, position)
	var show_id: String = opportunity["show_id"]
	var ad_ready: bool = await _query_tool_reward_ad_ready(
		opportunity, position, is_new_opportunity, seq
	)
	_tool_reward_ad_check_pending = false
	if seq != _tool_reward_ad_seq or not is_showing():
		return
	if not ad_ready:
		Toast.popup(_tool_ad_toast_key(), self)

		_refresh_ad_unavailable_badge(true)
		return

	_fill_positive_epoch += 1
	if not _last_known_has_fill:
		_last_known_has_fill = true
		_reeval_ad_unavailable_badge()

	var on_rewarded := func(placement_id: String) -> void:
		if placement_id != AdPlacement.REWARD:
			return
		GameState.inc_game_total_stat(_game_type(), "rv_count")
		_grant_tool_reward(kind)
	var on_closed := func(placement_id: String) -> void:
		if placement_id != AdPlacement.REWARD:
			return

		resume_like_hand_clock()

	_disconnect_self_reward_callbacks()
	UniKitManager.ad_rewarded.connect(on_rewarded, CONNECT_ONE_SHOT)
	UniKitManager.ad_closed.connect(on_closed, CONNECT_ONE_SHOT)

	pause_like_hand_clock()

	_tool_reward_ad_opportunities.erase(kind)
	UniKitManager.show_reward(AdPlacement.REWARD, position, show_id)


func _grant_tool_reward(kind: String) -> void:
	var prop_name: String = _prop_name_of(kind)
	if prop_name == "":
		return
	var source: String
	match prop_name:
		Tracker.Prop.HINT:
			source = Tracker.PropSource.HINT_REWARD_AD
		Tracker.Prop.LOCATE:
			source = Tracker.PropSource.LOCATE_REWARD_AD
		Tracker.Prop.MOUSE:
			source = Tracker.PropSource.MOUSE_REWARD_AD
		Tracker.Prop.DRAFT:
			source = Tracker.PropSource.DRAFT_REWARD_AD
		_:
			source = Tracker.PropSource.UNDO_REWARD_AD

	AwardManager.dispatch([AwardItem.make(prop_name, 1)], AwardManager.DisplayType.DIRECT, source)


# ================= 开局广告（插屏 / banner） =================
## 开局插屏判定结果缓存（同一次 on_show 内只算一次）
var _eval_interstitial_cache: Variant = null


func _eval_start_interstitial(
	params: Dictionary = {}, ad_position: String = "", dry_run: bool = false
) -> Dictionary:
	if not dry_run and _eval_interstitial_cache != null:
		return _eval_interstitial_cache

	var result: Dictionary = await _compute_start_interstitial(params, ad_position, dry_run)
	if not dry_run:
		_eval_interstitial_cache = result
	return result


func _compute_start_interstitial(
	params: Dictionary = {}, ad_position: String = "", dry_run: bool = false
) -> Dictionary:
	if PurchaseManager.is_vip_active():
		return {"eligible": false, "reason": "VIP 已去广告"}

	var prob_cfg: InterProbConfig = ABTestManager.inter_prob
	var view_count: int = GameState.get_session_reward_view_count()
	var session_games: int = GameState.get_session_game_count()
	var living_days: int = ABTestManager.living_days.days_since_first_open()
	var post_probability: bool = prob_cfg.has_post_gate_probability(living_days)
	var show_pct: int = prob_cfg.effective_percent(view_count, session_games, living_days)
	var reset_cd_on_miss: bool = InterProbConfig.should_reset_cd_on_miss_for(
		prob_cfg.live_group(), view_count, session_games, living_days
	)
	if not dry_run and prob_cfg.is_reward_gate_triggered(view_count):
		GameState.reset_session_reward_view_count()
	if show_pct < InterProbConfig.PERCENT_NO_CUT:
		if dry_run:
			params = params.duplicate()
			params["_dry_run_prob_pending_pct"] = show_pct
		elif not post_probability:
			if not _roll_start_interstitial_probability(show_pct, view_count, session_games, false):
				return {"eligible": false, "reason": "inter_prob 概率闸未命中(展示概率 %d%%)" % show_pct}

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
		if not await UniKitManager.is_interstitial_valid(AdPlacement.INTERSTITIAL, ad_position):
			return {"eligible": false, "reason": "无广告填充"}
	else:
		inter_show_id = UniKitManager.stats_ad_show_timing(AdPlacement.INTERSTITIAL, ad_position)
		if not await UniKitManager.is_interstitial_ready(
			AdPlacement.INTERSTITIAL, ad_position, inter_show_id
		):
			return {"eligible": false, "reason": "无广告填充"}

	if params.has("_dry_run_prob_pending_pct"):
		var pct_dry: int = int(params["_dry_run_prob_pending_pct"])
		return {
			"eligible": false,
			"reason": "其他闸全过;inter_prob 概率闸真实调用时 %d%% 概率拦截(dry_run 未掷骰)" % (100 - pct_dry)
		}

	if post_probability and not dry_run and show_pct < InterProbConfig.PERCENT_NO_CUT:
		if not _roll_start_interstitial_probability(
			show_pct, view_count, session_games, reset_cd_on_miss
		):
			return {"eligible": false, "reason": "inter_prob 概率闸未命中(展示概率 %d%%)" % show_pct}

	if not dry_run:
		GameState.increment_session_interstitial_count()

		if (
			PurchaseManager.is_subscription_entry_enabled()
			and ABTestManager.is_vip.should_replace_interstitial_at(
				GameState.get_session_interstitial_count()
			)
			and PurchaseManager.can_show_sub_inter_today()
		):
			PurchaseManager.mark_vip_sub_inter_shown()

			return {
				"eligible": true,
				"reason": "",
				"show_id": inter_show_id,
				"replace_with_subscription": true,
			}
	return {"eligible": true, "reason": "", "show_id": inter_show_id}


func _roll_start_interstitial_probability(
	show_pct: int, view_count: int, session_games: int, reset_cd_on_miss: bool
) -> bool:
	var roll: int = randi() % 100
	var roll_ctx: String = "激励%d次/开局%d局 → 有效 %d%%" % [view_count, session_games, show_pct]
	if roll >= show_pct:
		if reset_cd_on_miss:
			UniKitManager.reset_interstitial_cd()
		last_reward_view_prob_roll = (
			"掷骰 %d(<%d 展示,%s) → 未命中,插屏被拦,重置CD=%s"
			% [roll, show_pct, roll_ctx, str(reset_cd_on_miss)]
		)
		return false
	last_reward_view_prob_roll = "掷骰 %d(<%d 展示,%s) → 命中" % [roll, show_pct, roll_ctx]
	return true


## 最近一次开局插屏的结果描述，供调试面板查看
static var last_interstitial_status: String = "尚未触发开局插屏"

static var last_reward_view_prob_roll: String = "尚未触发(有效概率 100%)"

## 调试用：强制某道具免费（"" 关闭 / hint / locate / undo / all）
static var debug_force_free_tool: String = ""


func _try_show_start_interstitial(ad_position: String, elig: Dictionary) -> bool:
	if not elig.get("eligible", false):
		last_interstitial_status = elig.get("reason", "未知原因")
		return false

	if elig.get("replace_with_subscription", false):
		last_interstitial_status = "is_vip 组2:本次插屏位替换为订阅页"
		return false

	var show_id: String = elig.get("show_id", "")
	var shown: bool = UniKitManager.try_show_interstitial(
		AdPlacement.INTERSTITIAL, ad_position, show_id
	)
	last_interstitial_status = "已显示" if shown else "已通过判定但无填充(未显示)"
	return shown


func _try_show_replaced_interstitial(ad_position: String, elig: Dictionary) -> bool:
	return _try_show_start_interstitial(ad_position, elig_without_replace_flag(elig))


func elig_without_replace_flag(elig: Dictionary) -> Dictionary:
	var out: Dictionary = elig.duplicate()
	out.erase("replace_with_subscription")
	return out


func _show_subscription_instead_of_interstitial(ad_position: String, elig: Dictionary) -> bool:
	var user_state: String = (
		Tracker.SubscriptionUserState.SUBSCRIBED
		if PurchaseManager.is_vip_active()
		else Tracker.SubscriptionUserState.UNSUBSCRIBED
	)
	print(
		(
			"[Purchase (BaseGamePage)] is_vip 组2 插屏位替换为订阅页 ad_pos=%s user_state=%s session_inter_count=%d"
			% [ad_position, user_state, GameState.get_session_interstitial_count()]
		)
	)
	Tracker.track_sub_entry_click(Tracker.SubscriptionSource.INTERSTITIAL_AD_SLOT, user_state)
	var page: UIFrameWindow = UIManager.show_ui(UiName.SUBSCRIPTION, {"from_interstitial": true})
	if page == null or not page.has_signal("interstitial_slot_dismissed"):
		push_error("[Purchase (BaseGamePage)] 插屏位订阅页打开失败,退化为照播原插屏 ad_pos=%s" % ad_position)
		return false
	page.interstitial_slot_dismissed.connect(
		func(should_play: bool) -> void:
			_on_interstitial_subscription_closed(ad_position, elig, should_play),
		CONNECT_ONE_SHOT
	)
	return true


func _on_interstitial_subscription_closed(
	ad_position: String, elig: Dictionary, should_play_interstitial: bool
) -> bool:
	print(
		(
			"[Purchase (BaseGamePage)] is_vip 组2 订阅页已关 replay_interstitial=%s"
			% should_play_interstitial
		)
	)
	if not should_play_interstitial:
		return false
	var shown: bool = _try_show_replaced_interstitial(ad_position, elig)
	print("[Purchase (BaseGamePage)] is_vip 组2 补播插屏 shown=%s（false 多为库存已过期，可接受）" % shown)
	return shown


func _eval_start_banner() -> Dictionary:
	if PurchaseManager.is_vip_active():
		return {"eligible": false, "reason": "VIP 已去广告"}

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


## 最近一次 banner 的结果描述，供调试面板查看
static var last_banner_status: String = "尚未触发 banner"

var _banner_suppressed: bool = false

const _BANNER_TOP_WHITELIST: Array = [
	UiName.GAME,
	UiName.DAILY_GAME,
	UiName.SETTING,
]


func _show_banner_if_eligible(ad_position: String) -> void:
	var elig: Dictionary = _eval_start_banner()
	if not elig.get("eligible", false):
		last_banner_status = elig.get("reason", "未知原因")
		return
	var banner_h: int = int(_ad_banner.custom_minimum_size.y)
	var adapt_h: int = int(_ad_down_adapt.size.y)
	UniKitManager.show_banner(AdPlacement.BANNER, ad_position, true, 0, banner_h + adapt_h)
	last_banner_status = "已展示"


func _destroy_banner() -> void:
	UniKitManager.destroy_ad(AdPlacement.BANNER)


func _on_vip_status_changed(is_active: bool) -> void:
	if is_active:
		_destroy_banner()


func _on_any_window_shown(_ui_name: String, _win: UIFrameWindow) -> void:
	_queue_banner_sync()


func _on_any_window_hidden(_ui_name: String, _win: UIFrameWindow) -> void:
	_queue_banner_sync()


func _queue_banner_sync() -> void:
	call_deferred("_sync_banner_by_top_window")


func _sync_banner_by_top_window() -> void:
	var top: StringName = StringName(UIManager.get_top_ui_name_excluding(UiName.MOCK_BANNER))
	if not _BANNER_TOP_WHITELIST.has(top):
		if UniKitManager.is_banner_show_requested():
			_banner_suppressed = true
			print("[Game] %s 位于最顶层(非白名单) → 暂时移除 banner" % top)
			_destroy_banner()
		return

	if not _banner_suppressed:
		return
	_banner_suppressed = false

	if _is_complete or _wrong_guess_pending:
		return
	print("[Game] 回到 %s → 按 eligibility 恢复 banner" % top)
	_show_banner_if_eligible(_banner_ad_position())


## banner 广告位名：每日关用 daily，其余用 game
func _banner_ad_position() -> String:
	return "daily" if _game_type() == Tracker.GameType.DAILY else "game"


func _start_gameplay_timing(page_supported: bool) -> void:
	_clock_timer.start()
	_start_game_barrage_session(page_supported)


func _start_game_barrage_session(page_supported: bool) -> void:
	_game_barrage_logic.reset()
	_game_barrage_rng.randomize()
	_game_barrage_page_supported = page_supported
	_game_barrage_mode = (
		GameBarrageLogic
		. resolve_mode(
			page_supported and _bullets_area != null,
			ABTestManager.barrage_func.is_single_barrage_mode(),
			ABTestManager.barrage_func.is_multi_barrage_mode(),
		)
	)
	_game_barrage_session_active = _game_barrage_mode != GameBarrageLogic.MODE_DISABLED
	if _bullets_area != null:
		_bullets_area.set_layout_active(_game_barrage_session_active)

	_game_barrage_logic.start_clock(int(Time.get_unix_time_from_system() * 1000.0))
	if _game_barrage_session_active:
		_log_game_barrage_next_time("弹幕会话开始")


func _sync_game_barrage_clock() -> void:
	if _game_barrage_session_active:
		_game_barrage_logic.sync_clock(
			int(Time.get_unix_time_from_system() * 1000.0), _game_barrage_ad_active
		)


func _try_start_game_barrage_wave() -> void:
	if (
		not _game_barrage_session_active
		or _game_barrage_settings_open
		or not _game_barrage_logic.has_remaining_wave_quota()
		or not _game_barrage_logic.is_attempt_due()
	):
		return

	_game_barrage_logic.record_attempt()
	if not UniKitManager.is_online():
		_log_game_barrage_next_time("尝试弹出但无网")
		return
	if _bullets_area == null:
		return
	var daily_keys: Array = Array(GameState.get_game_barrage_daily_keys())
	var wave: Array[Dictionary] = _game_barrage_logic.make_wave(
		_game_barrage_mode, daily_keys, _game_barrage_rng, RobotNicknamePool.NAMES
	)
	if not wave.is_empty():
		print("[局内弹幕] 第 %d 波弹幕开始播放" % _game_barrage_logic.get_started_wave_count())
		if _game_barrage_logic.has_remaining_wave_quota():
			_log_game_barrage_next_time("弹幕弹出")
		else:
			print("[局内弹幕] 弹幕弹出，无后续弹幕")
		_bullets_area.play_wave(wave, _game_barrage_rng)


func _on_game_barrage_displayed(key: String) -> void:
	if _game_barrage_session_active:
		_game_barrage_logic.record_displayed(key)
	if GameBarrageLogic.is_daily_key(key):
		GameState.mark_game_barrage_daily_key(key)


func _on_game_barrage_spawn_failed(key: String) -> void:
	_game_barrage_logic.release_reserved(key)


func _record_game_barrage_action() -> void:
	if _game_barrage_session_active:
		_sync_game_barrage_clock()
		var next_eligible_before_action: float = _game_barrage_logic.get_next_eligible_sec()
		_game_barrage_logic.record_action()
		if _game_barrage_logic.get_next_eligible_sec() > next_eligible_before_action:
			_log_game_barrage_next_time("玩家放猫或使用道具导致延期")


func _log_game_barrage_next_time(event_name: String) -> void:
	var now_unix_msec: int = int(Time.get_unix_time_from_system() * 1000.0)
	var remaining_sec: float = maxf(
		0.0, _game_barrage_logic.get_next_eligible_sec() - _game_barrage_logic.get_elapsed_sec()
	)
	var next_unix_msec: int = now_unix_msec + int(ceil(remaining_sec * 1000.0))
	var timezone_bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local_datetime: String = Time.get_datetime_string_from_unix_time(
		int(next_unix_msec / 1000) + timezone_bias_sec, true
	)
	print("[局内弹幕] %s，下次弹幕时间：%s（unix_ms=%d）" % [event_name, local_datetime, next_unix_msec])


func _reset_game_barrage_session_state() -> void:
	_game_barrage_session_active = false
	_game_barrage_mode = GameBarrageLogic.MODE_DISABLED
	_game_barrage_ad_active = false
	_game_barrage_logic.reset()


func _reset_game_barrages() -> void:
	_reset_game_barrage_session_state()
	_game_barrage_page_supported = false
	if _bullets_area != null:
		_bullets_area.clear_all()
		_bullets_area.set_layout_active(false)


func _restart_game_barrages_after_continue() -> void:
	if _bullets_area != null:
		_bullets_area.clear_all()
	_start_game_barrage_session(_game_barrage_page_supported)


func _on_game_barrage_ad_shown(placement_id: String) -> void:
	if not GameBarrageLogic.is_fullscreen_ad_placement(placement_id):
		return
	if _game_barrage_session_active:
		_sync_game_barrage_clock()
	_game_barrage_ad_active = true


func _on_game_barrage_ad_impression(data: Dictionary) -> void:
	var placement_id: String = str(data.get("placement_id", ""))
	_on_game_barrage_ad_shown(placement_id)


func _on_game_barrage_ad_closed(placement_id: String) -> void:
	if not GameBarrageLogic.is_fullscreen_ad_placement(placement_id):
		return
	var resumed_from_ad: bool = _game_barrage_ad_active
	if _game_barrage_session_active:
		_sync_game_barrage_clock()
	_game_barrage_ad_active = false
	if _game_barrage_session_active and resumed_from_ad:
		_log_game_barrage_next_time("从广告回到前台")


func _on_game_barrage_ad_error(placement_id: String, _message: String) -> void:
	_on_game_barrage_ad_closed(placement_id)


func _on_game_settings_opened() -> void:
	_game_barrage_settings_open = true
	pause_like_hand_clock()


func _on_game_settings_closed() -> void:
	resume_like_hand_clock()
	_game_barrage_settings_open = false
	_sync_game_barrage_clock()
	_try_start_game_barrage_wave()


func _notification(what: int) -> void:
	if not is_showing():
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_is_app_foreground = true
		_idle_time = 0.0

		_cancel_dead_board_wait()

		if _locked_pointer_index != _NO_POINTER_INDEX:
			_locked_pointer_index = _NO_POINTER_INDEX
			_reset_all_touch_strokes()
		_on_application_focus_in()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_is_app_foreground = false
		_on_application_focus_out()


func _on_application_focus_in() -> void:
	var resumed_from_ad: bool = _game_barrage_ad_active
	_sync_game_barrage_clock()

	_game_barrage_ad_active = false
	if _game_barrage_session_active and resumed_from_ad:
		_log_game_barrage_next_time("从广告回到前台")

	_reeval_ad_unavailable_badge()


func _on_application_focus_out() -> void:
	_sync_game_barrage_clock()


## 齿轮按钮回调，子类覆写
func _on_gear_btn_pressed() -> void:
	pass


## 系统返回键回调，子类覆写
func _on_back_request() -> void:
	pass


func _process(delta: float) -> void:
	_sync_game_barrage_clock()
	_try_start_game_barrage_wave()

	if _board_view != null and _board_view.is_touch_point_viz_on():
		var viz_points: Array[Vector2] = []
		var viz_slots: Array = _touch_slots.values()
		for slot: BoardTouchSlot in viz_slots:
			if slot.is_owned():
				viz_points.append(slot.last_drag_pos)
		_board_view.update_touch_points(viz_points)

	if not _like_hand_state["clock_paused"]:
		_like_hand_state["in_game_sec"] += delta

		if _continue_clock_started:
			_continue_play_sec += delta

		if _can_operate_board():
			_operable_sec += minf(delta, _OPERABLE_DELTA_CAP_SEC)

			_tick_wrong_zone_idle(minf(delta, _OPERABLE_DELTA_CAP_SEC))

	if _bt.is_idle_hint_playing():
		_idle_hint_play_time += delta
		if _idle_hint_play_time >= IDLE_HINT_REPEAT_PLAY_SEC:
			_stop_idle_tool_hint()
			_idle_time = 0.0
			return

	if ABTestManager.prop_highlight.triggers_on_dead_board():
		_tick_dead_board_hint(delta)
		return
	if not _can_show_idle_hint():
		return

	if _in_opening_quiet_window():
		_idle_time = 0.0
		return
	_idle_time += delta
	if _idle_time >= _idle_hint_delay and not _bt.is_idle_hint_playing():
		_play_idle_tool_hint()


func _reset_idle_hint() -> void:
	_idle_time = 0.0
	_stop_idle_tool_hint()
	_cancel_dead_board_wait()


func _select_idle_tool_kind() -> String:
	if ABTestManager.prop_highlight.triggers_on_dead_board():
		return _select_dead_board_tool_kind()
	var locate_n: int = GameState.get_tool_count("locate")
	var hint_n: int = GameState.get_tool_count("hint")

	if (locate_n > 0) == (hint_n > 0):
		return ToolKind.HINT if randf() < 0.5 else ToolKind.LOCATE
	return ToolKind.LOCATE if locate_n > 0 else ToolKind.HINT


func _play_idle_tool_hint() -> void:
	var kind: String = _select_idle_tool_kind()
	if kind.is_empty():
		return

	if not _bt.play_idle_hint(kind):
		return
	_idle_hint_play_time = 0.0

	_idle_hint_round_count += 1


func _stop_idle_tool_hint() -> void:
	_bt.stop_idle_hint()


func _select_dead_board_tool_kind() -> String:
	var candidates: Array[String] = [ToolKind.LOCATE, ToolKind.HINT]
	if _is_mouse_tool_enabled() and _is_mouse_tool_unlocked():
		candidates.append(ToolKind.MOUSE)
	var stocked: Array[String] = []
	for kind: String in candidates:
		if _is_free_kind(kind) or GameState.get_tool_count(kind) > 0:
			stocked.append(kind)
	return PropHighlightConfig.pick_dead_board_tool(candidates, stocked, _ad_badge_on)


func _arm_dead_board_hint() -> void:
	_cancel_dead_board_wait()
	if not ABTestManager.prop_highlight.triggers_on_dead_board():
		return
	if _draft_mode or _is_complete or _puzzle.is_empty():
		return
	_dead_board_armed = true


func _cancel_dead_board_wait() -> void:
	_dead_board_armed = false
	_dead_board_wait_sec = 0.0


func _tick_dead_board_hint(delta: float) -> void:
	if (
		_draft_mode
		or _entry_anim_playing
		or not _can_show_idle_hint()
		or not UIManager.is_top_of_stack(self)
	):
		return
	var hard_wait: float = PropHighlightConfig.DEAD_BOARD_HARD_HINT_WAIT_SEC
	var idle_before: float = _idle_time
	_idle_time += delta
	if idle_before < hard_wait and _idle_time >= hard_wait and _next_hint_needs_tool():
		_fire_dead_board_hint()
		return
	if not _dead_board_armed:
		return
	var wait_before: float = _dead_board_wait_sec
	_dead_board_wait_sec += delta
	var visible_wait: float = PropHighlightConfig.DEAD_BOARD_VISIBLE_WAIT_SEC
	if (
		wait_before < visible_wait
		and _dead_board_wait_sec >= visible_wait
		and _is_board_visibly_dead()
	):
		_fire_dead_board_hint()
		return
	if _dead_board_wait_sec < hard_wait:
		return
	_cancel_dead_board_wait()
	if _is_board_visibly_dead():
		_fire_dead_board_hint()


func _fire_dead_board_hint() -> void:
	_cancel_dead_board_wait()
	if not _bt.is_idle_hint_playing():
		_play_idle_tool_hint()


func _is_board_visibly_dead() -> bool:
	var board: Array = _board_view.get_cell_state_folded_board()
	return DeadBoardDetector.is_visibly_dead(
		board, int(_level_config.get("size", 0)), _puzzle["regions"]
	)


func _next_hint_needs_tool() -> bool:
	var hint: Dictionary = _compute_next_hint()
	if not hint.get("found", false):
		return false
	if hint.get("wrong_mark", false) or _hint_targets_marked_cell(hint):
		return true
	return _DEAD_BOARD_HARD_HINT_STRATEGIES.has(str(hint.get("strategy", "")))


func _in_opening_quiet_window() -> bool:
	if not ABTestManager.prop_highlight.has_opening_quiet_window():
		return false
	var window_sec: float = PropHighlightConfig.opening_quiet_window_sec(
		int(_level_config.get("size", 0)), int(_level_config.get("rank", 0))
	)
	return float(_time_total_if_ended_now()) < window_sec


func _time_total_if_ended_now() -> int:
	return GameState.get_game_total_stat(_game_type(), "time_total") + _current_round_time_sec()


func _current_round_time_sec() -> int:
	@warning_ignore("integer_division")
	return (Time.get_ticks_msec() - _stat_start_ms) / 1000


func _is_draft_unlocked() -> bool:
	if ABTestManager == null or ABTestManager.draft_mode == null:
		return false
	if not ABTestManager.draft_mode.is_tool_mode():
		return false
	return GameState.get_current_level() >= _DRAFT_MIN_LEVEL


const _DRAFT_MIN_LEVEL: int = 21


func _on_draft_btn_pressed() -> void:
	if _entry_anim_playing or _tool_btns_locked:
		return
	if _is_complete or _wrong_guess_pending:
		return
	if not _is_draft_unlocked():
		return

	if _draft_busy:
		return

	if not LevelKind.is_color_challenge(_level_kind):
		Tracker.track_btn_click(Tracker.Btn.DRAFT, self)
	_reset_idle_hint()
	_lock_draft_ui_briefly()

	if _draft_mode:
		_exit_draft_mode_and_clear()
		return

	if not _consume_tool(ToolKind.DRAFT):
		return

	GameState.mark_current_level_dirty()

	if not _isolate_onefish_main_state():
		GameState.mark_dda_tool_or_revive_used()
		GameState.inc_today_tool_consumed()

	_enter_draft_mode()


func _on_apply_btn_pressed() -> void:
	if _entry_anim_playing or _tool_btns_locked or _is_complete or _wrong_guess_pending:
		return
	if not _draft_mode:
		return

	if _draft_busy:
		return
	Tracker.track_btn_click(Tracker.Btn.DRAFT_APPLY, self)
	_reset_idle_hint()
	_lock_draft_ui_briefly()
	_apply_draft_commit()


func _lock_draft_ui_briefly() -> void:
	_draft_busy = true
	create_countdown(_DRAFT_UI_LOCK_SEC, func() -> void: _draft_busy = false)


func _enter_draft_mode() -> void:
	_draft_mode = true

	_ensure_input_system()
	_switch_input_scheme(_draft_scheme)

	GameState.inc_game_total_stat(_game_type(), "draft_used_total")
	_draft_enter_ms = Time.get_ticks_msec()

	_draft_used_this_level = true

	_bt.set_kind_selected(ToolKind.DRAFT, true)
	_layout_bottom_tools(ToolLayout.DRAFT_ON)

	if _apply_btn != null:
		_apply_btn.visible = true
		_apply_btn.modulate = Color.WHITE


func _exit_draft_mode_and_clear(skip_cell_clear: bool = false, from_apply: bool = false) -> void:
	var was_in_draft: bool = _draft_mode

	if was_in_draft:
		_record_draft_exit_stats()

		if not from_apply:
			GameState.inc_game_total_stat(_game_type(), "draft_stop_used_total")
	_draft_mode = false

	if _normal_scheme != null:
		_switch_input_scheme(_normal_scheme)

	_bt.set_kind_selected(ToolKind.DRAFT, false)
	_layout_bottom_tools()

	if _apply_btn != null:
		_apply_btn.visible = false

	if _board_view == null or skip_cell_clear:
		return

	var animate_cross: bool = was_in_draft
	var draft_marks: Dictionary = _collect_draft_marks()
	for key: Vector2i in draft_marks.keys():
		var cv: CellView = _board_view.get_cell_view(key.x, key.y)
		if cv == null:
			continue
		if animate_cross and draft_marks[key] == CellState.DRAFT_CROSS:
			cv.play_draft_cross_disappear()
		else:
			cv.change_state({"state": CellState.EMPTY, "play_anim": false})


func _set_cell_draft(r: int, c: int, mark: int) -> void:
	if _board_view == null:
		return
	var cv: CellView = _board_view.get_cell_view(r, c)
	if cv == null:
		return
	cv.change_state({"state": mark, "play_anim": false})


func _collect_draft_marks() -> Dictionary:
	var out: Dictionary = {}
	if _board_view == null:
		return out
	var board: Array = _board_view.get_board()
	for r: int in range(board.size()):
		var row: Array = board[r]
		for c: int in range(row.size()):
			if CellState.is_draft(int(row[c])):
				out[Vector2i(r, c)] = int(row[c])
	return out


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
	for key: Vector2i in draft_marks.keys():
		var mark: int = draft_marks[key]
		var is_sol: bool = _is_solution_cell(key.x, key.y)
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


func _has_draft_marks() -> bool:
	if _board_view == null:
		return false
	var board: Array = _board_view.get_board()
	for r: int in range(board.size()):
		var row: Array = board[r]
		for c: int in range(row.size()):
			if CellState.is_draft(int(row[c])):
				return true
	return false


## 动画显示「应用」按钮
func _show_apply_btn_animated() -> void:
	if _apply_btn == null:
		return
	if _apply_anim != null and _apply_anim.has_animation("Appear"):
		if _apply_anim.is_playing() and _apply_anim.current_animation == "Appear":
			return
		_apply_anim.play("Appear")
	else:
		_apply_btn.modulate = Color.WHITE


## 动画隐藏「应用」按钮
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


func _is_solution_fully_placed() -> bool:
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return false
	var total: int = 0
	var filled: int = 0
	for r: int in range(sz):
		for c: int in range(sz):
			if not _is_solution_cell(r, c):
				continue
			total += 1
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				filled += 1
	return total > 0 and filled == total


func _clear_draft_rollback_state() -> void:
	_draft_lethal_wrong_cells = []


func _apply_draft_commit() -> void:
	var to_apply: Array = []
	var draft_marks: Dictionary = _collect_draft_marks()
	for key: Vector2i in draft_marks.keys():
		to_apply.append({"pos": key, "mark": draft_marks[key]})
	if to_apply.is_empty():
		_exit_draft_mode_and_clear()
		return

	_break_cat_streak_from_non_gesture()

	GameState.inc_game_total_stat(_game_type(), "draft_apply_used_total")

	to_apply.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var pa: Vector2i = left["pos"]
			var pb: Vector2i = right["pos"]
			var diag_a: int = pa.y - pa.x
			var diag_b: int = pb.y - pb.x
			if diag_a != diag_b:
				return diag_a < diag_b
			return pa.x > pb.x
	)

	var wrong_draft_cats: Array[Vector2i] = []
	for item: Dictionary in to_apply:
		var wp: Vector2i = item["pos"]
		if int(item["mark"]) == CellState.DRAFT_CAT and not _is_solution_cell(wp.x, wp.y):
			wrong_draft_cats.append(wp)
	if not _lives_inf and not wrong_draft_cats.is_empty() and wrong_draft_cats.size() >= _lives:
		_apply_draft_commit_lethal(wrong_draft_cats)
		return

	_exit_draft_mode_and_clear(true, true)
	if _board_view == null:
		return
	var wrong_positions: Array[Vector2i] = []

	_applying_draft_commit = true
	_combo_visual_suppressed = true
	var draft_cat_top_right: Vector2i = Vector2i(-1, -1)

	var cross_positions: Array[Vector2i] = []

	SoundManager.set_silent(true)

	var correct_cat_count: int = 0
	for item: Dictionary in to_apply:
		var scan_pos: Vector2i = item["pos"]
		if _board_view.get_cell_state(scan_pos.x, scan_pos.y) == CellState.CAT:
			continue
		if int(item["mark"]) != CellState.DRAFT_CAT:
			continue
		if not _is_solution_cell(scan_pos.x, scan_pos.y):
			continue
		correct_cat_count += 1
	if correct_cat_count > 0:
		_se_amortized_step = ScoreEncourageConfig.amortized_step(
			Tracker.get_stat("step_used") - _se_last_step, correct_cat_count
		)

	for item: Dictionary in to_apply:
		var pos: Vector2i = item["pos"]
		var draft_mark: int = item["mark"]
		if _board_view.get_cell_state(pos.x, pos.y) == CellState.CAT:
			continue
		if draft_mark == CellState.DRAFT_CROSS:
			cross_positions.append(pos)
			continue
		if draft_mark != CellState.DRAFT_CAT:
			continue
		if not _is_solution_cell(pos.x, pos.y):
			wrong_positions.append(pos)
			continue
		_board_view.set_cell_state(
			pos.x,
			pos.y,
			CellState.CAT,
			true,
			true,
			BoardView.ChangeSource.DRAFT_APPLY,
			"",
			false,
			_found_cat_spine_anim(BoardView.ChangeSource.DRAFT_APPLY)
		)

		if (
			draft_cat_top_right.x < 0
			or pos.y > draft_cat_top_right.y
			or (pos.y == draft_cat_top_right.y and pos.x < draft_cat_top_right.x)
		):
			draft_cat_top_right = pos

	_se_amortized_step = -1

	for pos: Vector2i in cross_positions:
		var cross_cv: CellView = _board_view.get_cell_view(pos.x, pos.y)
		if cross_cv != null:
			cross_cv.play_draft_cross_apply()
		else:
			_board_view.set_cell_state(
				pos.x, pos.y, CellState.MARK, false, true, BoardView.ChangeSource.DRAFT_APPLY
			)

	SoundManager.set_silent(false)

	if draft_cat_top_right.x >= 0:
		SoundManager.play(SoundManager.Kind.MARK_CAT)

	_combo_visual_suppressed = false
	_flush_draft_batch_encourage(draft_cat_top_right)
	_applying_draft_commit = false

	if draft_cat_top_right.x >= 0:
		_broadcast_found_blink_all(draft_cat_top_right)

	_update_remaining()

	_flush_full_mark_after_draft_apply()
	if wrong_positions.size() > 0:
		_apply_draft_wrong_cats(wrong_positions)
		return

	_validate_board()


func _apply_draft_commit_lethal(wrong_draft_cats: Array[Vector2i]) -> void:
	_exit_draft_mode_and_clear(false, true)
	if _board_view == null:
		return

	var shown_count: int = mini(wrong_draft_cats.size(), maxi(_lives, 1))
	var shown_wrong: Array[Vector2i] = wrong_draft_cats.slice(0, shown_count)

	_draft_lethal_wrong_cells = shown_wrong.duplicate()

	_update_remaining()
	_apply_draft_wrong_cats(shown_wrong)


func _rollback_draft_lethal_cells() -> void:
	if _draft_lethal_wrong_cells.is_empty():
		return
	var cells: Array[Vector2i] = _draft_lethal_wrong_cells
	_draft_lethal_wrong_cells = []
	if _board_view == null:
		return
	for pos: Vector2i in cells:
		_board_view.set_cell_state(
			pos.x, pos.y, CellState.EMPTY, false, true, BoardView.ChangeSource.DRAFT_ROLLBACK
		)
	_update_remaining()


func _flush_draft_batch_encourage(top_right: Vector2i) -> void:
	if _combo_feedback_view == null or top_right.x < 0:
		return
	if _score_model.combo < 3:
		return
	var pos_global: Vector2 = _board_view.get_cell_global_center(top_right.x, top_right.y)
	_combo_feedback_view.show_combo_text_only(_score_model.combo, pos_global)


func _on_draft_apply_wrong_batch_done() -> void:
	pass


func _apply_draft_wrong_cats(wrong_positions: Array[Vector2i]) -> void:
	_draft_apply_conflict_shown = false
	_draft_apply_violated_rules.clear()
	for pos: Vector2i in wrong_positions:
		do_wrong_guess_mark(pos.x, pos.y, true)

	if not _draft_apply_violated_rules.is_empty():
		_stop_rule_highlight()
		for rule: int in _draft_apply_violated_rules:
			_on_rule_violated(rule, true)

	if _draft_apply_conflict_shown:
		if _lives <= 0:
			UIManager.block_input_briefly(
				self, MisplaceReactionConfig.CONFLICT_ANIM_DURATION_SEC + 2.0
			)

			_board_view.disable_touch_for(MisplaceReactionConfig.CONFLICT_ANIM_DURATION_SEC + 2.0)
		var token: int = _conflict_anim_token
		await get_tree().create_timer(MisplaceReactionConfig.CONFLICT_ANIM_DURATION_SEC).timeout

		if not is_instance_valid(self) or not visible or token != _conflict_anim_token:
			return
	if _lives <= 0:
		_board_view.play_cat_cry_loop_all()

		if not _draft_apply_conflict_shown:
			UIManager.block_input_briefly(self, 2.0)
			_board_view.disable_touch_for(2.0)
	elif _is_solution_fully_placed():
		_wrong_guess_pending = false
		_validate_board()
		return
	else:
		_board_view.play_cat_frustrated_all()

	_on_draft_apply_wrong_batch_done()

	get_tree().create_timer(0.4).timeout.connect(
		func() -> void:
			if not is_instance_valid(self):
				return
			_update_remaining()
			_wrong_guess_pending = false
	)

	if _lives <= 0:
		get_tree().create_timer(0.6).timeout.connect(
			func() -> void:
				if not is_instance_valid(self) or not visible:
					return
				_on_game_fail()
		)


func _cmd_draft() -> void:
	if _is_complete or _wrong_guess_pending:
		return
	if _draft_mode:
		_exit_draft_mode_and_clear()
	else:
		_enter_draft_mode()
	print(
		"[cheat] draft_mode=%s (草稿道具剩余 %d,本次未扣)" % [_draft_mode, GameState.get_tool_count("draft")]
	)


func _cmd_draft_win() -> void:
	if _is_complete:
		return
	if not _draft_mode:
		_enter_draft_mode()
	var sz: int = _level_config.get("size", 0)
	var sol: Array = _puzzle.get("solution", [])
	if sz <= 0 or sol.is_empty():
		return
	for r: int in range(sz):
		for c: int in range(sz):
			if not bool((sol[r] as Array)[c]):
				continue
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				continue
			_set_cell_draft(r, c, CellState.DRAFT_CAT)
	_apply_draft_commit()


func _on_settings_btn_pressed() -> void:
	if _is_complete:
		return
	Tracker.track_btn_click(Tracker.Btn.OPTIONS, self)
	VibrateManager.play_at(VibrateManager.Pos.OPTIONS_BTN)

	_on_game_settings_opened()
	(
		UIManager
		. show_ui(
			UiName.SETTING,
			{
				"is_game_mode": true,
				"on_restart": _on_restart_requested,
				"on_close": Callable(self, "_on_game_settings_closed"),
				"on_pattern_changed": Callable(self, "_apply_pattern_mode"),
			}
		)
	)

	RedDotCenter.dismiss(DotName.PATTERN_ENTRY)


func _apply_pattern_mode() -> void:
	if _board_view == null:
		return
	var on: bool = GameState.is_pattern_mode_on()
	_board_view.set_pattern_mode(on, true)


func _on_hint_dismissed() -> void:
	Tracker.track_btn_click(Tracker.Btn.HINT_STOP, self)
	Tracker.inc_stat("hint_stop_used")
	Tracker.record_solution_step(Tracker.StepAction.HINT_STOP, [])
	_cleanup_hint()

	_show_banner_if_eligible(_banner_ad_position())


## 清空提示数据与所有临时高亮
func _cleanup_hint() -> void:
	_close_chain_detail()
	_clear_hint_highlights()
	_board_view.clear_hint_cells()
	_hint_data = {}


## 关掉连锁详情层并恢复提示浮层
func _close_chain_detail() -> void:
	_chain_detail_active = false
	if _chain_detail_layer != null:
		if _chain_detail_layer.is_inside_tree():
			_chain_detail_layer.get_parent().remove_child(_chain_detail_layer)
		_chain_detail_layer.queue_free()
		_chain_detail_layer = null
	_hint_overlay._overlay.visible = true


func _play_screen_shake() -> void:
	if _screen_shake_tween != null and _screen_shake_tween.is_valid():
		_screen_shake_tween.kill()
	else:
		_screen_shake_rest_x = _board_view.position.x
	var rest_x: float = _screen_shake_rest_x
	_screen_shake_tween = create_tween()
	_screen_shake_tween.tween_property(_board_view, "position:x", rest_x + 8.0, 0.05)
	_screen_shake_tween.tween_property(_board_view, "position:x", rest_x - 8.0, 0.05)
	_screen_shake_tween.tween_property(_board_view, "position:x", rest_x + 5.0, 0.04)
	_screen_shake_tween.tween_property(_board_view, "position:x", rest_x - 5.0, 0.04)
	_screen_shake_tween.tween_property(_board_view, "position:x", rest_x, 0.03)


func _stop_screen_shake() -> void:
	if _screen_shake_tween != null:
		_screen_shake_tween.kill()
		_screen_shake_tween = null


func _cmd_win(_args: Array[String]) -> void:
	if not _is_complete:
		_on_game_win()


func _can_show_idle_hint() -> bool:
	var base_ok: bool = (
		visible and not _is_complete and not _wrong_guess_pending and not _hint_overlay.visible
	)
	if not base_ok:
		return false

	if _idle_hint_round_count >= 1:
		return false
	return true


## 销毁提示高亮层
func _clear_hint_highlights() -> void:
	if _hint_highlight_layer != null:
		if _hint_highlight_layer.is_inside_tree():
			_hint_highlight_layer.get_parent().remove_child(_hint_highlight_layer)
		_hint_highlight_layer.queue_free()
		_hint_highlight_layer = null


func _on_game_win() -> void:
	pass


func _is_no_mistake_level() -> bool:
	return false


func is_full_hp_win() -> bool:
	return _lives == _life_cap


func _display_lives() -> int:
	return 99 if _lives_inf else _lives


func is_perfect_win() -> bool:
	if _lives_inf:
		return true
	return _is_no_mistake_level() and is_full_hp_win()


## 设置页点「重开」的回调，子类覆写
func _on_restart_requested() -> void:
	pass


## 通关要跳转的 UI 名，子类覆写
func _win_ui_name() -> StringName:
	return &""


func _reward_pos_for(kind: String) -> String:
	if kind == ToolKind.LOCATE:
		return Tracker.AdPos.PROPS_NORMAL_LOCATE
	if kind == ToolKind.MOUSE:
		return Tracker.AdPos.PROPS_NORMAL_MOUSE
	if kind == ToolKind.DRAFT:
		return Tracker.AdPos.PROPS_NORMAL_DRAFT
	return Tracker.AdPos.PROPS_NORMAL_HINT


## 展示通关 toast 并等它消失（返回是否真的展示了）
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


func _maybe_show_win_toast() -> CanvasLayer:
	if _auto_x_banner_shown:
		print("[WinToast] auto_x banner shown(本局无手动标叉) → skip toast")
		return null
	var scale: int = _level_config.get("size", 0)
	var step: int = Tracker.get_stat("step_used")
	var thresholds: Dictionary = WinToastTier.get_thresholds(scale)
	var tier: int = WinToastTier.determine_tier(scale, step)
	var covered: bool = tier >= WinToastTier.TIER_PERFECT and tier <= WinToastTier.TIER_P10
	if not covered:
		print(
			(
				"[WinToast] scale=%d step=%d thresholds=%s tier=%s covered=false → skip"
				% [scale, step, thresholds, WinToastTier.tier_name(tier)]
			)
		)
		return null
	var toast: GameWinToast = _resolve_win_toast_node(tier)
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
			"[WinToast] scale=%d step=%d thresholds=%s tier=%s covered=true → show %s"
			% [scale, step, thresholds, WinToastTier.tier_name(tier), toast.name]
		)
	)
	var message: Dictionary = WinToastMessages.pick_random(tier, step, scale, toast.highlight_color)
	toast.set_message(message.get("text", ""))
	toast.show_toast({})
	return toast


func _resolve_win_toast_node(tier: int) -> GameWinToast:
	match tier:
		WinToastTier.TIER_PERFECT:
			return get_node_or_null("Root/WinToast04") as GameWinToast
		WinToastTier.TIER_P5:
			return get_node_or_null("Root/WinToast03") as GameWinToast
		WinToastTier.TIER_P10:
			return get_node_or_null("Root/WinToast02") as GameWinToast
		WinToastTier.TIER_P20:
			return get_node_or_null("Root/WinToast01") as GameWinToast
	return null


## 棋盘容器尺寸变化 → 下一帧重排棋盘
func _on_board_container_resized() -> void:
	_relayout_board.call_deferred()


## 棋盘固定显示宽度（像素），缩放的基准
const FIXED_BOARD_WIDTH: float = 1008.0

const _BOARD_ENLARGE_FACTOR: float = 1.04167
const _BOARD_ENLARGE_MIN_SIZE: int = 8


func _grid_intro_sync_total(board_intro: BoardContainerCell_01) -> float:
	if board_intro == null:
		return 0.0
	return board_intro.get_cell_fade_complete_time()


var _grid_ui_anim_baked_captured: bool = false
var _grid_ui_anim_baked_scale_curve: int = 0
var _grid_ui_anim_baked_scale_dur: float = 0.0
var _grid_ui_anim_baked_scale_curve_res: Curve = null


func _apply_grid_ui_entry_anim(board_intro: BoardContainerCell_01) -> void:
	if board_intro == null:
		return
	if not _grid_ui_anim_baked_captured:
		_grid_ui_anim_baked_scale_curve = int(board_intro.g3_cell_scale_curve)
		_grid_ui_anim_baked_scale_dur = board_intro.g3_cell_scale_duration
		_grid_ui_anim_baked_scale_curve_res = board_intro.g3_cell_scale_custom_curve
		_grid_ui_anim_baked_captured = true
	if ABTestManager.game_grid_ui.is_single_line():
		board_intro.g3_cell_scale_enabled = true
		board_intro.g3_cell_scale_from = 0.0
		board_intro.g3_cell_scale_curve = AutoAnimCurve.EaseType.LINEAR
		board_intro.g3_cell_scale_duration = board_intro.g3_cell_fade_duration
	else:
		board_intro.g3_cell_scale_curve = _grid_ui_anim_baked_scale_curve as AutoAnimCurve.EaseType
		board_intro.g3_cell_scale_duration = _grid_ui_anim_baked_scale_dur
		board_intro.g3_cell_scale_custom_curve = _grid_ui_anim_baked_scale_curve_res


func _relayout_board() -> void:
	if _level_config.is_empty() or not _level_config.has("size"):
		return
	var size_n: int = int(_level_config["size"])
	var intrinsic: Vector2 = BoardView.intrinsic_size_for(size_n)

	var target_width: float = FIXED_BOARD_WIDTH
	if size_n >= _BOARD_ENLARGE_MIN_SIZE:
		target_width = FIXED_BOARD_WIDTH * _BOARD_ENLARGE_FACTOR
	var board_scale: float = target_width / intrinsic.x
	_board_view.size = intrinsic
	_board_view.pivot_offset = Vector2.ZERO
	_board_view.scale = Vector2(board_scale, board_scale)
	var visible_w: float = intrinsic.x * board_scale
	var visible_h: float = intrinsic.y * board_scale

	var wanted_min_h: float = maxf(FIXED_BOARD_WIDTH, visible_h)
	if not is_equal_approx(_board_container.custom_minimum_size.y, wanted_min_h):
		_board_container.custom_minimum_size.y = wanted_min_h

	_stop_screen_shake()
	_board_view.position = Vector2(
		(_board_container.size.x - visible_w) / 2.0,
		(_board_container.size.y - visible_h) / 2.0,
	)
	_board_outer_glow.sync_to_board()

	_board_view.apply_compensated_cell_corner_radius()


enum LikeHandAnim { LIKE, CLAP, BLOW_TRUMPET, STAR_EYE_CAT = 7 }
const _LIKE_HAND_ANIM_NAMES: Dictionary = {
	LikeHandAnim.LIKE: "Like",
	LikeHandAnim.CLAP: "Clap",
	LikeHandAnim.BLOW_TRUMPET: "BlowTrumpet",
	LikeHandAnim.STAR_EYE_CAT: "LikeHand_7",
}

const _LIKE_HAND_POOL_MAX: int = 5 # 手势节点对象池上限，超出直接 queue_free
var _like_hand_pool: Array[Node2D] = [] # 闲置的手势节点池


## 在屏幕坐标处播一个手势动画（自动取用对象池，播完归还）
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


## 取一个手势节点：优先复用池里的，否则新实例化
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


## 归还手势节点：池满就直接释放
func _release_like_hand(node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	node.visible = false

	if _like_hand_pool.size() >= _LIKE_HAND_POOL_MAX:
		node.queue_free()
		return
	_like_hand_pool.append(node)


## 手势相对格心的默认 Y 偏移（像素，负数向上）
const _LIKE_HAND_Y_OFFSET: float = -80.0

const _LIKE_HAND_MARGIN: float = 185.0
const _MARGIN_SPINE: float = 100.0


func _play_like_hand_on_cell(r: int, c: int, anim: LikeHandAnim) -> void:
	var cell_view: CellView = _board_view.get_cell_view(r, c)
	if cell_view == null:
		return
	var cell_center: Vector2 = cell_view.get_global_transform_with_canvas() * (cell_view.size * 0.5)
	var y_offset: float = _LIKE_HAND_Y_OFFSET
	if _combo_feedback_view != null:
		y_offset -= _combo_feedback_view.get_current_effects_height()
	if anim == LikeHandAnim.STAR_EYE_CAT:
		var board_scale_y: float = _board_view.scale.y if _board_view != null else 1.0
		y_offset = -cell_view.size.y * board_scale_y * 0.5
	cell_center.y += y_offset
	if _combo_feedback_view != null and _combo_feedback_view.get_last_clamped_center_x() >= 0.0:
		cell_center.x = _combo_feedback_view.get_last_clamped_center_x()
	else:
		var viewport_w: float = get_viewport().get_visible_rect().size.x
		var margin: float = _get_like_hand_margin_for_anim(anim)
		cell_center.x = clampf(cell_center.x, margin, viewport_w - margin)
	play_like_hand(cell_center, anim)


func _get_like_hand_margin_for_anim(anim: int) -> float:
	if anim == LikeHandAnim.STAR_EYE_CAT:
		return _MARGIN_SPINE
	return _LIKE_HAND_MARGIN


# 触发点赞手势的三种来源：玩家双击 / 定位道具 / 应用 R1 提示
enum LikeHandTrigger { PLAYER_DOUBLE_TAP, LOCATE, HINT_R1_APPLY }

## 各棋盘尺寸下「点赞」的最小间隔（秒）与最多触发次数
const _LIKE_HAND_CONFIG_BY_SIZE: Dictionary = {
	6: {"min_interval": 30.0, "max_triggers": 2},
	7: {"min_interval": 30.0, "max_triggers": 2},
	8: {"min_interval": 40.0, "max_triggers": 3},
	9: {"min_interval": 40.0, "max_triggers": 3},
	10: {"min_interval": 40.0, "max_triggers": 3},
	11: {"min_interval": 40.0, "max_triggers": 3},
	12: {"min_interval": 40.0, "max_triggers": 3},
}


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
	var interval: float = float(cfg["min_interval"])
	if _like_hand_state["in_game_sec"] - _like_hand_state["last_cat_sec"] < interval:
		return none

	return {"should_play": true, "anim": LikeHandAnim.LIKE}


## 记录一次放对：刷新时间戳、标记见过第一只猫、按需累加触发次数
func _record_correct_cat(decision: Dictionary) -> void:
	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]
	_like_hand_state["has_seen_first_cat"] = true
	if decision.get("should_play", false):
		_like_hand_state["triggered_count"] += 1


## 续局时盘上已有猫，把「见过第一只猫」补上
func _seed_like_hand_first_cat_from_board() -> void:
	if _like_hand_state["has_seen_first_cat"]:
		return
	var sz: int = _level_config.get("size", 4)
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				_like_hand_state["has_seen_first_cat"] = true
				return


## 数盘上正式猫的数量
func _count_placed_cats(sz: int) -> int:
	var n: int = 0
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				n += 1
	return n


func _would_be_last_cat_after_place(r: int, c: int) -> bool:
	var sz: int = _level_config.get("size", 4)
	var placed: int = _count_placed_cats(sz)
	if _board_view.get_cell_state(r, c) != CellState.CAT:
		placed += 1
	return placed >= sz


## 暂停手势时钟（打开设置页 / 插屏时调用）
func pause_like_hand_clock() -> void:
	_like_hand_state["clock_paused"] = true


## 恢复手势时钟
func resume_like_hand_clock() -> void:
	_like_hand_state["clock_paused"] = false


func mark_continue_clock_started() -> void:
	if _continue_clock_started:
		return
	_continue_clock_started = true


func _decide_clap_for_correct_cat(r: int, c: int) -> Dictionary:
	var none: Dictionary = {"should_play": false, "anim": LikeHandAnim.CLAP}

	var sz: int = _level_config.get("size", 4)
	if sz < 6:
		return none

	if _board_view.get_region_cell_count(r, c) < 3:
		return none

	if _draft_used_this_level:
		return none
	if _board_view.is_region_ever_marked_x(r, c):
		return none
	if _board_view.is_region_ever_errored(r, c):
		return none
	return {"should_play": true, "anim": LikeHandAnim.CLAP}


## 记录鼓掌已播（刷新手势时间戳）
func _record_clap_played() -> void:
	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]


func _on_board_cell_state_changed_for_r4(r: int, c: int, state: int, source: int = 0) -> void:
	if state == CellState.CAT:
		_record_cat_place_time(r, c)
		call_deferred("_refresh_r4_plus_cache")

	elif state == CellState.MARK and source == BoardView.ChangeSource.HINT:
		_like_hand_state["hint_marked_x_cells"]["%d_%d" % [r, c]] = true


func _record_cat_place_time(r: int, c: int) -> void:
	var key: String = "%d_%d" % [r, c]
	if not _like_hand_state["cat_place_times"].has(key):
		_like_hand_state["cat_place_times"][key] = _like_hand_state["in_game_sec"]
	_like_hand_state["latest_cat_key"] = key


## 用当前棋盘重算可吹号（R4+）的格子集合
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


func _on_board_cell_state_changed_for_combo(r: int, c: int, state: int, source: int = 0) -> void:
	if _combo_feedback_view != null:
		_combo_feedback_view.clear_last_clamped_center_x()
	if state != CellState.CAT:
		return

	_score_model.add_combo()

	if _combo_feedback_view == null:
		return
	var cell_global_pos: Vector2 = _board_view.get_cell_global_center(r, c)

	if _combo_visual_suppressed:
		return

	if _score_model.combo >= 3:
		_combo_feedback_view.show_combo_text_only(_score_model.combo, cell_global_pos)


func _calc_combo_point_gain() -> int:
	return mini(600 + maxi(0, _score_model.combo - 1) * 80, 1320)


func _decide_blow_trumpet_for_correct_cat(r: int, c: int) -> Dictionary:
	var none: Dictionary = {"should_play": false, "anim": LikeHandAnim.BLOW_TRUMPET}

	if not _r4_plus_cells.has(Vector2i(r, c)):
		return none
	return {"should_play": true, "anim": LikeHandAnim.BLOW_TRUMPET}


## 记录吹号已播
func _record_blow_trumpet_played() -> void:
	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]


const _MISSED_CROSS_DELAY_SEC: float = 10.0

static var _missed_cross_delay_override: float = -1.0


func _decide_missed_cross(r: int, c: int) -> Dictionary:
	var none: Dictionary = {"should_play": false, "anim": LikeHandAnim.STAR_EYE_CAT, "cats": []}
	var sz: int = _level_config.get("size", 4)
	if sz < 6:
		return none
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return none
	var target: Vector2i = Vector2i(r, c)
	var target_key: String = "%d_%d" % [r, c]
	var now: float = _like_hand_state["in_game_sec"]
	var place_times: Dictionary = _like_hand_state["cat_place_times"]
	var triggered: Dictionary = _like_hand_state["missed_cross_triggered_cats"]

	if _like_hand_state["hint_marked_x_cells"].has(target_key):
		print("[thumb_up] X(%d,%d) SKIP:该格 hint 道具曾打过 X" % [r, c])
		return none

	var latest_key: String = _like_hand_state["latest_cat_key"]
	if latest_key != "":
		var lp: PackedStringArray = latest_key.split("_")
		var latest_cat: Vector2i = Vector2i(int(lp[0]), int(lp[1]))
		if target in QueendokuCore.cells_excluded_by_cat(latest_cat, sz, regions):
			print("[thumb_up] X(%d,%d) SKIP:落在最新猫(%s)排除区内" % [r, c, latest_key])
			return none

	var missed_cross_delay: float = (
		_missed_cross_delay_override
		if _missed_cross_delay_override >= 0.0
		else _MISSED_CROSS_DELAY_SEC
	)
	var committed_x: Dictionary = _like_hand_state["manually_x_marked_cells"]
	var oldest_key: String = ""
	var oldest_time: float = INF

	var skip_reasons: Array[String] = []
	for key: String in place_times:
		var t: float = float(place_times[key])
		var p: PackedStringArray = key.split("_")
		var cat: Vector2i = Vector2i(int(p[0]), int(p[1]))
		var zone: Array = QueendokuCore.cells_excluded_by_cat(cat, sz, regions)
		if not (target in zone):
			continue
		if triggered.has(key):
			skip_reasons.append("猫(%s):已触发过" % key)
			continue
		if now - t <= missed_cross_delay:
			skip_reasons.append(
				"猫(%s):填入才 %.1fs 未过延迟(需 >%.1fs)" % [key, now - t, missed_cross_delay]
			)
			continue
		if not _zone_has_committed_x(zone, committed_x, target_key):
			skip_reasons.append("猫(%s):排除区里没有已提交的手动 X" % key)
			continue
		if t < oldest_time:
			oldest_time = t
			oldest_key = key
	if oldest_key == "":
		if not skip_reasons.is_empty():
			print("[thumb_up] X(%d,%d) NO TRIGGER,候选猫被拒原因:%s" % [r, c, " | ".join(skip_reasons)])
		return none
	print("[thumb_up] MISSED_CROSS 触发 → X(%d,%d) 补上遗漏猫(%s) 排除区里的叉" % [r, c, oldest_key])
	return {"should_play": true, "anim": LikeHandAnim.STAR_EYE_CAT, "cats": [oldest_key]}


func _mark_missed_cross_cats_triggered(cats: Array) -> void:
	var triggered: Dictionary = _like_hand_state["missed_cross_triggered_cats"]
	for key in cats:
		triggered[key] = true


func _try_play_missed_cross(r: int, c: int) -> void:
	var mc: Dictionary = _decide_missed_cross(r, c)
	if mc["should_play"]:
		_mark_missed_cross_cats_triggered(mc["cats"])
		_play_like_hand_on_cell(r, c, mc["anim"])


const _MISSED_CROSS_DEFER_MARGIN_SEC: float = 0.02


func _defer_cat_streak_break(slot: BoardTouchSlot, seq: int) -> void:
	var sec: float = _cur_window_sec() + _MISSED_CROSS_DEFER_MARGIN_SEC
	var token: int = _cat_streak_token
	get_tree().create_timer(sec).timeout.connect(
		func() -> void:
			if token != _cat_streak_token:
				return
			if slot.cat_streak_break_pending and seq == slot.cat_streak_break_seq:
				slot.cat_streak_break_pending = false
				_cat_streak = 0
	)


func _defer_missed_cross_decision(r: int, c: int) -> void:
	var token: int = _missed_cross_token
	var sec: float = _cur_window_sec() + _MISSED_CROSS_DEFER_MARGIN_SEC
	get_tree().create_timer(sec).timeout.connect(
		func() -> void:
			if token != _missed_cross_token:
				return
			if _is_complete:
				return
			if _board_view == null:
				return

			if _conflict_target_positions.has(Vector2i(r, c)):
				return

			if _board_view.get_cell_state(r, c) != CellState.MARK:
				return
			_try_play_missed_cross(r, c),
		CONNECT_ONE_SHOT
	)


func _zone_has_committed_x(zone: Array, committed_x: Dictionary, exclude_key: String = "") -> bool:
	for cell: Vector2i in zone:
		var k: String = "%d_%d" % [cell.x, cell.y]
		if k == exclude_key:
			continue
		if not committed_x.has(k):
			continue
		if _board_view.get_cell_state(cell.x, cell.y) != CellState.MARK:
			continue
		return true
	return false


func _stage_x_mark_pending(r: int, c: int) -> void:
	_active_slot.pending_x_marks.append("%d_%d" % [r, c])


func _commit_pending_x_marks(slot: BoardTouchSlot) -> void:
	if slot == null or slot.pending_x_marks.is_empty():
		return
	var committed: Dictionary = _like_hand_state["manually_x_marked_cells"]
	for key: String in slot.pending_x_marks:
		committed[key] = true
	slot.pending_x_marks.clear()


const _FEEDBACK_ARBITRATION_ORDER: Array = [
	ThumbUpConfig.Feedback.BLOW_TRUMPET,
	ThumbUpConfig.Feedback.CLAP,
	ThumbUpConfig.Feedback.LIKE,
]


func _arbitrate_feedback_for_correct_cat(r: int, c: int) -> Dictionary:
	var none: Dictionary = {"should_play": false, "anim": LikeHandAnim.LIKE, "feedback": -1}

	if _would_be_last_cat_after_place(r, c):
		return none
	for feedback: int in _FEEDBACK_ARBITRATION_ORDER:
		var decision: Dictionary = _evaluate_single_feedback(feedback, r, c)
		if decision["should_play"]:
			return {"should_play": true, "anim": decision["anim"], "feedback": feedback}
	return none


func _predict_like_hand_hw(r: int, c: int, source: int) -> float:
	if source != BoardView.ChangeSource.USER_ACTION:
		return 0.0
	var predicted: Dictionary = _arbitrate_feedback_for_correct_cat(r, c)
	if not predicted.get("should_play", false):
		return 0.0
	return _get_like_hand_margin_for_anim(int(predicted.get("anim", LikeHandAnim.LIKE)))


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
	return {"should_play": false, "anim": LikeHandAnim.LIKE}


func _on_feedback_played(feedback: int) -> void:
	match feedback:
		ThumbUpConfig.Feedback.BLOW_TRUMPET:
			_record_blow_trumpet_played()
		ThumbUpConfig.Feedback.CLAP:
			_record_clap_played()


func _validate_board() -> void:
	if _is_complete or _puzzle.is_empty() or not _puzzle.has("regions"):
		return
	var sz: int = _level_config.get("size", 4)

	if QueendokuCore.is_complete(_board_view.get_cell_state_folded_board(), sz, _puzzle["regions"]):
		_emit_full_mark_achieved_if_any()

		_win_encourage_snapshot = {
			"perfect": is_perfect_win(),
			"full_hp": is_full_hp_win(),
		}
		_on_game_win()
		return


func _refresh_score_performance(found: int, total: int, stage_immediate: bool = false) -> void:
	if _combo_feedback_view == null:
		return
	var cfg: ScorePerformanceConfig = ABTestManager.score_performance
	if not cfg.is_enabled():
		_combo_feedback_view.apply_score_stage(0, 0)
		return
	var stage: int = cfg.stage_for_progress(found, total)
	var stage_count: int = cfg.stage_count(total)

	if stage_immediate or stage <= _combo_feedback_view.get_applied_score_stage():
		_combo_feedback_view.apply_score_stage(stage, stage_count)
		return
	_combo_feedback_view.latch_score_stage(stage, stage_count)


func _update_remaining(stage_immediate: bool = false) -> void:
	var sz: int = _level_config.get("size", 4)
	var placed: int = 0
	for r in range(sz):
		for c in range(sz):
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				placed += 1
	if sz >= 10:
		_remaining_label.text = (
			"[font_size=40][color=#00B31B]%d[/color][color=#935A5A]/%d[/color][/font_size]"
			% [placed, sz]
		)
	else:
		_remaining_label.text = "[color=#00B31B]%d[/color][color=#935A5A]/%d[/color]" % [placed, sz]
	if _last_placed_count != -1 and placed != _last_placed_count:
		_anim_correct.play("CorrectPromptStatus")
	_last_placed_count = placed

	_refresh_score_performance(placed, sz, stage_immediate)

	if _cat_progress != null and _cat_progress.visible:
		var metrics: Dictionary = _cat_progress_metrics(sz)
		var is_compact: bool = ABTestManager.normal_top_ui.is_cat_progress_compact()
		if _cat_progress_total != sz:
			_cat_progress_region_order.clear()
			if is_compact:
				_setup_cat_progress_compact(sz, metrics)
			else:
				_cat_progress.setup(sz, metrics["slot"], metrics["pitch"], metrics["padding"])
			_cat_progress_total = sz

			_cat_progress.set_cat_costume(in_game_costume_id(), uses_in_game_costume())

		_layout_cat_progress_bar(metrics)
		if is_compact:
			_apply_cat_progress_compact(sz)
		elif ABTestManager.normal_top_ui.is_cat_progress_colored():
			_apply_cat_progress_colored(sz)
		else:
			_cat_progress.set_revealed_count(placed)
		_refresh_cat_progress_wrong_marks()

	_apply_target_costume_icon()


func _try_emit_rule_violation(r: int, c: int) -> void:
	var rule: int = _classify_violation_at(r, c)
	if rule != QueendokuCore.Rule.NONE:
		_on_rule_violated(rule)


func _classify_violation_at(r: int, c: int) -> int:
	if _puzzle.is_empty() or not _puzzle.has("regions"):
		return QueendokuCore.Rule.NONE
	var regions: Array = _puzzle["regions"]
	var sz: int = _level_config.get("size", 4)
	var placed: Array = []
	var board: Array = _board_view.get_board()
	for rr in range(sz):
		for cc in range(sz):
			if board[rr][cc] == CellState.CAT:
				placed.append(Vector2i(rr, cc))
	return QueendokuCore.classify_violation(r, c, placed, regions)


func _on_rule_violated(_rule: int, _additive: bool = false) -> void:
	pass


func _play_rule_highlight(rule_index: int, additive: bool = false) -> void:
	var idx: int = rule_index - 1
	if idx < 0 or idx >= _rule_highlights.size():
		return
	if not additive:
		_stop_rule_highlight()
	var highlight: TextureRect = _rule_highlights[idx]

	if not is_instance_valid(highlight):
		return
	if _rule_active_highlights.has(highlight):
		return
	var tw: Tween = create_tween().set_loops(2)
	_rule_active_highlights.append(highlight)
	_rule_tweens.append(tw)
	tw.tween_method(
		func(t: float) -> void:
			if not is_instance_valid(highlight):
				return
			var phase: float = sin(t * PI)
			highlight.modulate.a = RULE_HL_FLOOR + (1.0 - RULE_HL_FLOOR) * phase,
		0.0,
		1.0,
		RULE_HL_PERIOD
	)

	tw.finished.connect(func() -> void: _stop_one_rule_highlight(highlight, tw))


func _stop_one_rule_highlight(highlight: TextureRect, tw: Tween) -> void:
	var i: int = _rule_tweens.find(tw)
	if i >= 0:
		_rule_tweens.remove_at(i)
	var j: int = _rule_active_highlights.find(highlight)
	if j >= 0:
		_rule_active_highlights.remove_at(j)
	if is_instance_valid(highlight):
		highlight.modulate.a = 0.0


func _stop_rule_highlight() -> void:
	for tw: Tween in _rule_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_rule_tweens.clear()
	for hl: TextureRect in _rule_active_highlights:
		if is_instance_valid(hl):
			hl.modulate.a = 0.0
	_rule_active_highlights.clear()


func _on_wrong_guess(
	row: int, column: int, skip_other_cats: bool = false, from_draft_apply: bool = false
) -> void:
	_mistake_count += 1
	_wrong_guess_pending = true

	_wrong_guess_lock_token += 1
	var lock_token: int = _wrong_guess_lock_token

	_score_model.reset_combo()
	_se_count = 0

	GameState.inc_game_total_stat(_game_type(), "invalid_sign_total")
	var lost_index: int = _lives - 1

	if not _lives_inf:
		_lives = maxi(_lives - 1, 0)

		GameState.inc_elo_fish_consumed()
		_record_elo_v2_action("fish")

	if _game_type() != Tracker.GameType.DAILY:
		if LevelKind.is_insert_golden_fish(_level_kind):
			GameState.inc_insert_golden_fish_wrong_cat_num()
		else:
			GameState.inc_current_wrong_cat_num()

	var conflict_anim_played: bool = false

	if ABTestManager.misplace_reaction.is_conflict_reaction():
		var conflict: Vector2i = _find_conflict_cat(row, column)
		if conflict != Vector2i(-1, -1):
			if not ABTestManager.found_cat_animation.should_sigh_all_on_wrong():
				skip_other_cats = true

			if from_draft_apply:
				_draft_apply_conflict_shown = true

			if _lives <= 0 and not from_draft_apply:
				UIManager.block_input_briefly(
					self, MisplaceReactionConfig.CONFLICT_ANIM_DURATION_SEC + 2.0
				)

				_board_view.disable_touch_for(
					MisplaceReactionConfig.CONFLICT_ANIM_DURATION_SEC + 2.0
				)
			var completed: bool = await _play_misplace_conflict_anim(row, column, conflict)

			if not completed:
				return
			conflict_anim_played = true

	_full_mark_defer_judgement = true
	_board_view.play_error_feedback(row, column)
	_full_mark_defer_judgement = false

	if _lives <= 0:
		_seed_full_mark_fired_units_from_board("死局,登记但不播")
	elif conflict_anim_played:
		_defer_full_mark_after_conflict(Vector2i(row, column))
	else:
		_flush_full_mark_unit_clear(Vector2i(row, column))

	if from_draft_apply:
		_life_bar.animate_lost(lost_index, _display_lives())
		_play_screen_shake()
		return

	if _lives <= 0:
		_board_view.play_cat_cry_loop_all()

		UIManager.block_input_briefly(self, 2.0)

		_board_view.disable_touch_for(2.0)
	else:
		if not skip_other_cats:
			_board_view.play_cat_frustrated_all()

	_life_bar.animate_lost(lost_index, _display_lives())

	_play_screen_shake()

	get_tree().create_timer(0.4).timeout.connect(
		func() -> void:
			if not is_instance_valid(self):
				return

			_update_remaining()

			if lock_token != _wrong_guess_lock_token:
				return
			_wrong_guess_pending = false
	)

	if _lives <= 0:
		get_tree().create_timer(0.6).timeout.connect(
			func() -> void:
				if not is_instance_valid(self) or not visible:
					return

				if lock_token != _wrong_guess_lock_token:
					return
				if _is_complete:
					return
				_on_game_fail()
		)


func _on_game_fail() -> void:
	pass


## 作弊指令回调，子类覆写
func _on_cheat_command(_cmd_name: String, _args: Array[String]) -> void:
	pass


func _on_mouse_btn_pressed() -> void:
	_try_start_mouse_tool()


func _on_locate_btn_pressed() -> void:
	if _entry_anim_playing or _tool_btns_locked or _mouse_tool_busy:
		return
	Tracker.track_btn_click(Tracker.Btn.LOCATE, self)
	_reset_idle_hint()

	if _draft_mode:
		return
	if _is_complete or _wrong_guess_pending:
		return
	var consumed: bool = _consume_tool(ToolKind.LOCATE, false)
	if not consumed:
		return
	GameState.mark_current_level_dirty()
	if not _isolate_onefish_main_state():
		GameState.mark_dda_tool_or_revive_used()
		GameState.inc_today_tool_consumed()
	Tracker.inc_stat("locate_used")
	GameState.inc_game_total_stat(_game_type(), "locate_used_total")
	var sz: int = _level_config.get("size", 4)
	var sol: Array = _puzzle["solution"]
	var regions: Array = _puzzle["regions"]

	var region_remaining: Dictionary = {}
	for r in range(sz):
		for c in range(sz):
			var st: int = _board_view.get_cell_state(r, c)
			if st != CellState.MARK and st != CellState.ERROR:
				var rid: int = regions[r][c]
				region_remaining[rid] = region_remaining.get(rid, 0) + 1

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
		func(left: Dictionary, right: Dictionary) -> bool:
			return (
				left["size"] < right["size"]
				if left["size"] != right["size"]
				else (left["r"] < right["r"] if left["r"] != right["r"] else left["c"] < right["c"])
			)
	)
	var best: Dictionary = candidates[0]
	Tracker.record_solution_step(
		Tracker.StepAction.LOCATE_SIGN,
		[_step_cell(best["r"], best["c"], Tracker.StepResult.CORRECT)]
	)
	_board_view.set_cell_state(
		best["r"],
		best["c"],
		CellState.CAT,
		true,
		true,
		BoardView.ChangeSource.LOCATE,
		"",
		false,
		_found_cat_spine_anim(BoardView.ChangeSource.LOCATE)
	)

	_mark_step_dirty()
	_clear_step_dirty()
	_count_board_step("locate")

	_record_correct_cat(_decide_like_hand_for_correct_cat(LikeHandTrigger.LOCATE))
	_update_remaining()
	_validate_board()


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

	var highlight_all: bool = (
		strategy == "R2"
		or strategy == "R3"
		or strategy == "R4"
		or strategy == "R3b"
		or strategy == "R4b"
	)
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

	if strategy == "R3b" or strategy == "R4b":
		var sz_b: int = _level_config.get("size", 4)
		var regs_b: Array = _puzzle["regions"]
		var color_set_b: Dictionary = {}
		for reg in hint.get("regions", []):
			color_set_b[reg] = true
		var row_in_b: Dictionary = {}
		for row in hint.get("locked_rows", []):
			row_in_b[row] = true
		var col_in_b: Dictionary = {}
		for col in hint.get("locked_cols", []):
			col_in_b[col] = true
		var mark_idx_b: int = 0
		for r in range(sz_b):
			for c in range(sz_b):
				if not color_set_b.has(regs_b[r][c]):
					continue
				if not row_in_b.is_empty() and row_in_b.has(r):
					continue
				if not col_in_b.is_empty() and col_in_b.has(c):
					continue
				if CellState.is_blank(_board_view.get_cell_state(r, c)):
					var temp_b: CellView = _spawn_temp_cell(Vector2i(r, c), s, bpos)
					temp_b.play_r2_preview(mark_idx_b * 0.06)
					mark_idx_b += 1

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


## 在提示高亮层里造一个临时格子
func _spawn_temp_cell(cv: Vector2i, s: float, bpos: Vector2) -> CellView:
	return _spawn_temp_cell_in(_hint_highlight_layer, cv, s, bpos)


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

	temp.set_corner_radius_compensated(s, _board_view.get_puzzle_size())

	temp.set_round_corners(_board_view.corner_round_mask_for(cv.x, cv.y))

	temp.apply_cell_face_px(float(_board_view.get_grid_cell_face_px()))

	temp.apply_cross_art_variant()

	temp.set_cat_costume(in_game_costume_id())
	if src != null:
		temp.set_region_color(src.get_region_color())

		if src.get_pattern_tex() != null:
			temp.configure_pattern(src.get_pattern_tex(), src.get_pattern_color())
			temp.set_pattern_mode(src.is_pattern_on(), true)

		var raw: int = src.get_state()
		if not CellState.is_blank(raw):
			var view_state: int = CellState.CAT if raw == CellState.CAT else CellState.MARK
			temp.change_state({"state": view_state, "play_anim": false})
	return temp


## 算 R2 提示要打叉的格子（按行 / 列 / 区域四种模式）
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


func _apply_r3_r4_hint() -> void:
	var mark_cells: Array[Vector2i] = _compute_r3_r4_mark_cells(_hint_data)
	for cell: Vector2i in mark_cells:
		_mark_step_dirty()
		_board_view.set_cell_state(
			cell.x, cell.y, CellState.MARK, true, true, BoardView.ChangeSource.HINT
		)
	_validate_board()
	_update_remaining()


func _compute_r3_r4_mark_cells(hint: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var sz: int = _level_config.get("size", 4)
	var regs: Array = _puzzle["regions"]
	var reg_set: Dictionary = {}
	for reg in hint.get("regions", []):
		reg_set[reg] = true
	for row in hint.get("locked_rows", []):
		for c in range(sz):
			var row_cell: Vector2i = Vector2i(row, c)
			if (
				not reg_set.has(regs[row][c])
				and not result.has(row_cell)
				and CellState.is_blank(_board_view.get_cell_state(row, c))
			):
				result.append(row_cell)
	for col in hint.get("locked_cols", []):
		for r in range(sz):
			var col_cell: Vector2i = Vector2i(r, col)
			if (
				not reg_set.has(regs[r][col])
				and not result.has(col_cell)
				and CellState.is_blank(_board_view.get_cell_state(r, col))
			):
				result.append(col_cell)
	return result


func _apply_r3_r4b_hint() -> void:
	var mark_cells: Array[Vector2i] = _compute_r3_r4b_mark_cells(_hint_data)
	for cell: Vector2i in mark_cells:
		_mark_step_dirty()
		_board_view.set_cell_state(
			cell.x, cell.y, CellState.MARK, true, true, BoardView.ChangeSource.HINT
		)
	_validate_board()
	_update_remaining()


func _compute_r3_r4b_mark_cells(hint: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var sz: int = _level_config.get("size", 4)
	var regs: Array = _puzzle["regions"]
	var color_set: Dictionary = {}
	for reg in hint.get("regions", []):
		color_set[reg] = true
	var row_in: Dictionary = {}
	for row in hint.get("locked_rows", []):
		row_in[row] = true
	var col_in: Dictionary = {}
	for col in hint.get("locked_cols", []):
		col_in[col] = true
	for r in range(sz):
		for c in range(sz):
			if not color_set.has(regs[r][c]):
				continue
			if not row_in.is_empty() and row_in.has(r):
				continue
			if not col_in.is_empty() and col_in.has(c):
				continue
			if CellState.is_blank(_board_view.get_cell_state(r, c)):
				result.append(Vector2i(r, c))
	return result


func _should_skip_board_input() -> bool:
	return _hint_overlay != null and is_instance_valid(_hint_overlay) and _hint_overlay.visible


func _owns_board_input() -> bool:
	if Engine.is_editor_hint():
		return false

	if not is_showing():
		return false
	if _board_view == null or not is_instance_valid(_board_view):
		return false

	if not UIManager.is_top_of_stack(self):
		return false
	if _is_cheat_panel_visible():
		return false

	if _strategy_overlay != null and _strategy_overlay.visible:
		return false

	if _should_skip_board_input():
		return false

	if _entry_anim_playing:
		return false
	return true


func _can_operate_board() -> bool:
	if ABTestManager.multi_touch.is_multi_touch_enabled() and UIManager.is_any_button_held():
		return false
	return _owns_board_input() and _board_view.is_touch_enabled() and _is_app_foreground


func _input(event: InputEvent) -> void:
	if not _owns_board_input():
		_release_pointer_lock_on_release(event)
		_abandon_strokes_on_input_gate(event)
		return

	if not _board_view.is_touch_enabled() and not _press_yields_through_short_lock(event):
		_release_pointer_lock_on_release(event)

		_abandon_strokes_on_input_gate(event)
		return

	if event.device == InputEvent.DEVICE_ID_EMULATION:
		if _should_swallow_emulated_ui_press(event):
			get_viewport().set_input_as_handled()
		return

	var is_touch_press: bool = (
		event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	)
	var is_touch_release: bool = (
		event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed
	)
	var is_touch_drag: bool = event is InputEventScreenDrag
	var is_mouse_press: bool = false
	var is_mouse_release: bool = false
	var is_mouse_drag: bool = false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			is_mouse_press = mb.pressed
			is_mouse_release = not mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		is_mouse_drag = (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	var is_press: bool = is_touch_press or is_mouse_press
	var is_release: bool = is_touch_release or is_mouse_release
	var is_drag: bool = is_touch_drag or is_mouse_drag
	if not (is_press or is_release or is_drag):
		return

	var global_pos: Vector2
	if event is InputEventMouse:
		global_pos = (event as InputEventMouse).position
	elif event is InputEventScreenTouch:
		global_pos = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		global_pos = (event as InputEventScreenDrag).position
	else:
		return
	var local_pos: Vector2 = _board_view.to_local_touch_pos(global_pos)

	var slop_px: float = ABTestManager.swipe_logic.slop_pct() * float(BoardView.CELL_PX)

	_board_view.update_swipe_extra_zone_slop(slop_px)

	var pointer_index: int = _pointer_index_of(event)
	var in_board: bool = _board_view.is_pos_in_extended_hit_area(local_pos, slop_px)

	if ABTestManager.multi_touch.is_multi_touch_enabled():
		if is_press and in_board and UIManager.is_any_button_held():
			get_viewport().set_input_as_handled()
			return

		if is_press and not in_board and _has_owned_stroke():
			get_viewport().set_input_as_handled()
			return

	if not _admit_by_single_finger_lock(event, is_press, in_board):
		return

	if not is_press and not _touch_slots.has(pointer_index):
		return

	if is_press and not in_board:
		return

	var slot: BoardTouchSlot = _ensure_slot(pointer_index)
	_active_slot = slot

	if is_press:
		slot.reset_stroke_phase()

		slot.physically_down = true
		var cell: Vector2i = _board_view.pointer_to_cell(local_pos.x, local_pos.y)
		if cell.x >= 0:
			_on_board_cell_drag_start(local_pos)
		else:
			slot.pending_enter = true
			slot.last_drag_pos = local_pos
		get_viewport().set_input_as_handled()
		return

	if is_release:
		slot.physically_down = false

		var was_owned: bool = slot.is_owned()
		if slot.drag_in_progress:
			_on_board_cell_drag_end(local_pos)

		slot.reset_stroke()
		_active_slot = null

		_locked_pointer_index = _NO_POINTER_INDEX
		if was_owned:
			get_viewport().set_input_as_handled()
		return

	if is_drag:
		if slot.latched:
			get_viewport().set_input_as_handled()
			return
		if slot.pending_enter:
			var in_zone: bool = _board_view.is_pos_in_extended_hit_area(local_pos, slop_px)
			if not in_zone:
				slot.pending_enter = false
				slot.latched = true
				get_viewport().set_input_as_handled()
				return
			var cell2: Vector2i = _board_view.pointer_to_cell(local_pos.x, local_pos.y)
			if cell2.x >= 0:
				slot.pending_enter = false
				_on_board_cell_drag_start(local_pos, false)

				if not slot.drag_in_progress:
					slot.latched = true
			else:
				slot.last_drag_pos = local_pos
			get_viewport().set_input_as_handled()
			return
		if slot.drag_in_progress:
			var in_zone2: bool = _board_view.is_pos_in_extended_hit_area(local_pos, slop_px)
			if not in_zone2:
				_on_board_cell_drag_end()
				slot.latched = true
				get_viewport().set_input_as_handled()
				return
			_on_board_cell_drag_over(local_pos)
			get_viewport().set_input_as_handled()
			return

		_active_slot = null
		return


func _raw_pointer_index_of(event: InputEvent) -> int:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).index
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).index
	return _MOUSE_POINTER_INDEX


func _admit_by_single_finger_lock(event: InputEvent, is_press: bool, in_board: bool) -> bool:
	if not ABTestManager.multi_touch.should_use_single_finger_lock():
		return true
	var raw_index: int = _raw_pointer_index_of(event)
	if _locked_pointer_index != _NO_POINTER_INDEX and raw_index != _locked_pointer_index:
		return false
	if not is_press and _locked_pointer_index == _NO_POINTER_INDEX:
		return false
	if is_press and in_board:
		_locked_pointer_index = raw_index
	return true


func _release_pointer_lock_on_release(event: InputEvent) -> void:
	if _is_pointer_release(event) and _raw_pointer_index_of(event) == _locked_pointer_index:
		_locked_pointer_index = _NO_POINTER_INDEX


var _cached_cheat_panel: CheatPanel = null


func _is_cheat_panel_visible() -> bool:
	if OS.has_feature("rel"):
		return false
	if _cached_cheat_panel != null and is_instance_valid(_cached_cheat_panel):
		return _cached_cheat_panel.visible
	var root: Node = get_tree().root if get_tree() != null else null
	if root == null:
		return false
	_cached_cheat_panel = _find_cheat_panel(root)
	if _cached_cheat_panel == null:
		return false
	return _cached_cheat_panel.visible


func _find_cheat_panel(node: Node) -> CheatPanel:
	if node is CheatPanel:
		return node as CheatPanel
	for child in node.get_children():
		var found: CheatPanel = _find_cheat_panel(child)
		if found != null:
			return found
	return null


func _on_board_cell_drag_start(pos: Vector2, is_physical_press_on_cell: bool = true) -> void:
	_ensure_input_system()
	_reset_idle_hint()

	if _active_slot != null:
		_active_slot.cat_placed_this_stroke = false

	var sc: Vector2i = _board_view.pointer_to_cell(pos.x, pos.y)

	var sc_state: int = _board_view.get_cell_state(sc.y, sc.x)
	var is_terminal_x_start: bool = sc_state == CellState.ERROR
	if _is_complete or is_terminal_x_start:
		if is_terminal_x_start and not _is_complete and is_physical_press_on_cell:
			Tracker.record_solution_step(
				Tracker.StepAction.CLICK_ERROR_MARK,
				[_step_cell(sc.y, sc.x, Tracker.StepResult.NO_JUDGE)]
			)
		return

	if _wrong_guess_pending and not _may_press_during_wrong_guess(sc.y, sc.x):
		return

	if _active_slot == null:
		return
	_consume_board_actions(
		_active_slot.recognizer.on_drag_start(pos, is_physical_press_on_cell), true
	)

	_active_slot.drag_in_progress = true
	_active_slot.last_drag_pos = pos


func _on_board_cell_drag_over(pos: Vector2) -> void:
	if _is_complete:
		return

	if _wrong_guess_pending and not ABTestManager.multi_touch.is_multi_touch_enabled():
		return

	if _active_slot == null:
		return
	_active_slot.last_drag_pos = pos
	_consume_board_actions(_active_slot.recognizer.on_drag_over(pos))


func _on_board_cell_drag_end(release_pos: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _active_slot == null:
		return
	_active_slot.drag_in_progress = false

	var is_cat_click: bool = _active_slot.recognizer.finish_drag(release_pos)
	if is_cat_click:
		Tracker.inc_stat("cat_click_num")

	_commit_pending_x_marks(_active_slot)
	_flush_gesture_solution_step(_active_slot, is_cat_click, release_pos)

	if _active_slot.consume_lock_pending():
		_board_view.disable_touch_for(ABTestManager.doubletap_protect.high_freq_lock_cd_sec(), true)

	var had_change: bool = _active_slot != null and _active_slot.step_dirty
	_clear_stroke_step_dirty()
	if had_change:
		_count_board_step("gesture", _active_slot)

	_arm_dead_board_hint()


func _ensure_input_system() -> void:
	if _normal_scheme == null:
		_normal_scheme = BoardInputScheme.create_normal(_board_view)
	if _draft_scheme == null:
		_draft_scheme = BoardInputScheme.create_draft(_board_view)
	if _current_scheme == null:
		_current_scheme = _normal_scheme


func _switch_input_scheme(scheme: BoardInputScheme) -> void:
	_current_scheme = scheme
	var switching_slots: Array = _touch_slots.values()
	for slot: BoardTouchSlot in switching_slots:
		slot.recognizer.active_scheme = scheme
		slot.recognizer.reset_for_scheme_switch()


func _ensure_slot(pointer_index: int) -> BoardTouchSlot:
	if _touch_slots.has(pointer_index):
		return _touch_slots[pointer_index]
	_ensure_input_system()
	var slot := BoardTouchSlot.new()
	slot.recognizer = SwipeGuardRecognizer.new(_board_view)
	slot.recognizer.active_scheme = _current_scheme

	slot.recognizer.window_sec_provider = _double_tap_window_sec

	slot.recognizer.cross_pointer_double_tap_provider = _consume_cross_pointer_double_tap

	slot.recognizer.promote_to_double_tap_provider = _should_promote_to_double_tap

	slot.recognizer.autofix_target_provider = _resolve_autofix_target

	_touch_slots[pointer_index] = slot
	return slot


var _cross_dt_source_slot: BoardTouchSlot = null


func _consume_cross_pointer_double_tap(requester: BoardGestureRecognizer, r: int, c: int) -> bool:
	_cross_dt_source_slot = null
	var source: BoardTouchSlot = BoardCrossPointerDoubleTap.try_consume(
		_touch_slots.values(), requester, r, c
	)
	if source == null:
		return false
	_cross_dt_source_slot = source
	return true


func _take_cross_dt_source() -> BoardTouchSlot:
	var source: BoardTouchSlot = _cross_dt_source_slot
	_cross_dt_source_slot = null
	return source


func _cur_recognizer() -> BoardGestureRecognizer:
	return _active_slot.recognizer if _active_slot != null else null


func _cur_window_sec() -> float:
	var rec: BoardGestureRecognizer = _cur_recognizer()
	return (
		rec.get_last_window_sec() if rec != null else BoardGestureRecognizer.DEFAULT_DOUBLE_TAP_SEC
	)


func _settle_stroke_before_abort(slot: BoardTouchSlot) -> void:
	_commit_pending_x_marks(slot)
	_flush_gesture_solution_step(slot, false, Vector2(-1.0, -1.0))
	if slot.step_dirty:
		_count_board_step("gesture", slot)


func _reset_all_touch_strokes() -> void:
	var resetting_slots: Array = _touch_slots.values()
	for slot: BoardTouchSlot in resetting_slots:
		_settle_stroke_before_abort(slot)
		slot.reset_stroke()

	_active_slot = null


func _abandon_strokes_on_input_gate(event: InputEvent) -> void:
	if _is_pointer_release(event):
		var released: Variant = _touch_slots.get(_pointer_index_of(event), null)
		if released != null:
			(released as BoardTouchSlot).physically_down = false
	if _touch_slots.is_empty():
		return
	_reset_all_touch_strokes()


func _pointer_index_of(event: InputEvent) -> int:
	if not ABTestManager.multi_touch.is_multi_touch_enabled():
		return _MOUSE_POINTER_INDEX
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).index
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).index
	return _MOUSE_POINTER_INDEX


func _is_pointer_release(event: InputEvent) -> bool:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if event is InputEventScreenTouch:
		return not (event as InputEventScreenTouch).pressed
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		return button.button_index == MOUSE_BUTTON_LEFT and not button.pressed
	return false


func _release_conflict_line(node: LineCrossConnector) -> void:
	if node == null:
		return
	_active_conflict_lines.erase(node)
	if is_instance_valid(node):
		node.queue_free()


func _may_press_during_wrong_guess(r: int, c: int) -> bool:
	if not ABTestManager.multi_touch.is_multi_touch_enabled():
		return false
	if _active_slot == null or _active_slot.recognizer == null:
		return false
	if _active_slot.recognizer.has_pending_tap(r, c):
		return true

	var slots: Array = _touch_slots.values()
	return BoardCrossPointerDoubleTap.has_any(slots, _active_slot.recognizer, r, c)


func _press_yields_through_short_lock(event: InputEvent) -> bool:
	if not ABTestManager.multi_touch.is_multi_touch_enabled():
		return false
	if not _board_view.is_locked_only_by_yielding_locks():
		return false
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	var global_pos: Vector2
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		global_pos = (event as InputEventScreenTouch).position
	elif (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).pressed
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	):
		global_pos = (event as InputEventMouseButton).position
	else:
		return false
	var local_pos: Vector2 = _board_view.to_local_touch_pos(global_pos)

	var cell: Vector2i = _board_view.pointer_to_cell(local_pos.x, local_pos.y)
	if cell.x < 0:
		return false
	var row: int = cell.y
	var col: int = cell.x
	if not _is_solution_cell(row, col) or _board_view.get_cell_state(row, col) == CellState.CAT:
		return false
	var requester: BoardGestureRecognizer = null
	var own_slot: Variant = _touch_slots.get(_pointer_index_of(event), null)
	if own_slot != null:
		requester = (own_slot as BoardTouchSlot).recognizer
		if requester != null and requester.has_pending_tap(row, col):
			return true
	var slots: Array = _touch_slots.values()
	return BoardCrossPointerDoubleTap.has_any(slots, requester, row, col)


func _clear_all_touch_slots() -> void:
	_touch_slots.clear()
	_active_slot = null


func _should_swallow_emulated_ui_press(event: InputEvent) -> bool:
	if not ABTestManager.multi_touch.is_multi_touch_enabled():
		return false
	if not (event is InputEventMouseButton):
		return false
	var mouse_btn := event as InputEventMouseButton
	if not mouse_btn.pressed or mouse_btn.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not _has_owned_stroke():
		return false
	var local_pos: Vector2 = _board_view.to_local_touch_pos(mouse_btn.position)
	var slop_px: float = ABTestManager.swipe_logic.slop_pct() * float(BoardView.CELL_PX)
	return not _board_view.is_pos_in_extended_hit_area(local_pos, slop_px)


func _has_owned_stroke() -> bool:
	var owned_slots: Array = _touch_slots.values()
	for slot: BoardTouchSlot in owned_slots:
		if slot.is_owned():
			return true
	return false


func _double_tap_window_sec(r: int, c: int) -> float:
	var cfg := ABTestManager.doubletap_protect
	var truth_has_cat: bool = cfg.needs_truth() and _solution_has_cat(r, c)
	var would_conflict: bool = cfg.needs_conflict() and _would_cat_conflict(r, c)
	return cfg.window_sec(truth_has_cat, would_conflict)


func _should_promote_to_double_tap(r: int, c: int) -> bool:
	var cfg := ABTestManager.doubletap_protect
	if not cfg.is_promote_group():
		return false
	return cfg.should_promote_tap(_solution_has_cat(r, c))


func _resolve_autofix_target(r: int, c: int, touch_pos: Vector2 = Vector2.ZERO) -> Vector2i:
	var cfg := ABTestManager.doubletap_protect
	if not cfg.should_autofix():
		return Vector2i(-1, -1)

	if _solution_has_cat(r, c):
		return Vector2i(-1, -1)
	var board_size: int = _level_config.get("size", 4)
	var candidates: Array = []
	var pixel_dist_sq: Array = []
	var deltas: Array = [-1, 0, 1]
	for row_delta in deltas:
		for col_delta in deltas:
			if row_delta == 0 and col_delta == 0:
				continue
			var neighbor_row: int = r + row_delta
			var neighbor_col: int = c + col_delta
			if neighbor_row < 0 or neighbor_row >= board_size:
				continue
			if neighbor_col < 0 or neighbor_col >= board_size:
				continue
			if not _solution_has_cat(neighbor_row, neighbor_col):
				continue
			if _board_view.get_cell_state(neighbor_row, neighbor_col) == CellState.CAT:
				continue
			candidates.append(Vector2i(neighbor_row, neighbor_col))
			var cell_center: Vector2 = (
				_board_view.cell_to_local_rect(neighbor_row, neighbor_col).get_center()
			)
			pixel_dist_sq.append(touch_pos.distance_squared_to(cell_center))
	return DoubletapProtectConfig.pick_autofix_target(Vector2i(r, c), candidates, pixel_dist_sq)


func _solution_has_cat(r: int, c: int) -> bool:
	var solution: Array = _puzzle.get("solution", [])
	if r < 0 or r >= solution.size():
		return false
	var row: Array = solution[r]
	if c < 0 or c >= row.size():
		return false
	return bool(row[c])


func _would_cat_conflict(r: int, c: int) -> bool:
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return false
	var sz: int = _level_config.get("size", 4)
	var placed: Array = []
	var board: Array = _board_view.get_board()
	for rr in range(sz):
		for cc in range(sz):
			if board[rr][cc] == CellState.CAT:
				placed.append(Vector2i(rr, cc))
	return QueendokuCore.classify_violation(r, c, placed, regions) != QueendokuCore.Rule.NONE


func _consume_board_actions(actions: Array[CellAction], is_tap_start: bool = false) -> void:
	var cross_source: BoardTouchSlot = _take_cross_dt_source()
	if actions.is_empty():
		return

	mark_continue_clock_started()

	_note_wrong_zone_activity()

	if is_tap_start and _active_slot != null:
		var opens_dt_window: bool = true
		for a: CellAction in actions:
			if a.kind == CellAction.Kind.DOUBLE_TAP:
				opens_dt_window = false
				break
		if opens_dt_window:
			_active_slot.cat_streak_break_seq += 1
			_active_slot.cat_streak_break_pending = true
			_defer_cat_streak_break(_active_slot, _active_slot.cat_streak_break_seq)
	var applied: bool = false
	for a: CellAction in actions:
		if a.kind == CellAction.Kind.DOUBLE_TAP:
			_consume_double_tap(a.row, a.col, not _dt_promoted_this_gesture(), cross_source)
			applied = true
			continue

		if a.kind == CellAction.Kind.SET_DRAFT:
			_mark_stroke_step_dirty()
			_set_cell_draft(a.row, a.col, a.state)

			if a.state == CellState.DRAFT_CAT and not _dt_promoted_this_gesture():
				_clear_stroke_step_dirty()

			if (
				a.state != CellState.EMPTY
				and ABTestManager.full_mark_feedback.has_full_mark_feedback()
			):
				_full_mark_last_cell = Vector2i(a.row, a.col)

			if a.state == CellState.EMPTY:
				SoundManager.play(SoundManager.Kind.UNMARK_X)
			else:
				SoundManager.play(SoundManager.Kind.MARK_X)
			continue

		if _board_view.get_cell_state(a.row, a.col) == CellState.DRAFT_CAT:
			continue

		if _conflict_target_positions.has(Vector2i(a.row, a.col)):
			continue
		if a.record:
			_mark_stroke_step_dirty()

		var defer_full_mark: bool = (
			is_tap_start and a.state == CellState.MARK and CellState.is_blank(a.before)
		)
		_full_mark_defer_judgement = defer_full_mark
		_board_view.set_cell_state(a.row, a.col, a.state, a.play_anim, a.show_cat_visual, a.source)
		_full_mark_defer_judgement = false
		_collect_gesture_step_cell(a)
		if a.before == CellState.MARK and a.state == CellState.EMPTY:
			Tracker.inc_stat("erase_count")

		if a.state == CellState.MARK and CellState.is_blank(a.before):
			if is_tap_start:
				if (
					ABTestManager.doubletap_protect.should_lock_after_mark_or_error()
					and not _is_solution_cell(a.row, a.col)
					and _active_slot != null
				):
					_active_slot.lock_pending = true
			else:
				if _active_slot != null:
					_active_slot.lock_pending = false
			if is_tap_start:
				_defer_missed_cross_decision(a.row, a.col)

				_defer_full_mark_unit_clear(a.row, a.col)
			else:
				_try_play_missed_cross(a.row, a.col)

			_stage_x_mark_pending(a.row, a.col)
		if a.vibrate >= 0:
			VibrateManager.play_vibrate(a.vibrate)
		applied = true
	if applied:
		_validate_board()
		_update_remaining()


func _dt_promoted_this_gesture() -> bool:
	var rec: BoardGestureRecognizer = _cur_recognizer()
	return rec != null and rec.last_double_tap_promoted


func _consume_double_tap(
	r: int, c: int, first_tap_counted: bool = true, cross_source: BoardTouchSlot = null
) -> void:
	var cur: int = _board_view.get_cell_state(r, c)
	if cur == CellState.CAT:
		return
	var dt_cfg := ABTestManager.doubletap_protect

	var should_lock_on_mistake: bool = dt_cfg.should_lock_after_mark_or_error()

	_se_step_pending_this_place = not first_tap_counted
	_dt_cross_landing_this_place = cross_source != null

	if cross_source != null:
		cross_source.cat_streak_break_pending = false

	var is_correct: bool = _is_solution_cell(r, c)
	_record_double_tap_solution_step(r, c, is_correct, first_tap_counted)
	if is_correct:
		do_place_cat(r, c)
	else:
		do_wrong_guess_mark(r, c)
		if should_lock_on_mistake:
			_board_view.disable_touch_for(dt_cfg.high_freq_lock_cd_sec(), true)

	dt_cfg.notify_double_tap(is_correct)

	if first_tap_counted:
		_clear_stroke_step_dirty()
	_se_step_pending_this_place = false
	_dt_cross_landing_this_place = false


func do_place_cat(row: int, col: int) -> void:
	_mark_stroke_step_dirty()
	_board_view.set_cell_state(
		row,
		col,
		CellState.CAT,
		true,
		true,
		BoardView.ChangeSource.USER_ACTION,
		"",
		false,
		_found_cat_spine_anim(BoardView.ChangeSource.USER_ACTION)
	)

	if not _dt_cross_landing_this_place:
		_active_slot.cat_streak_break_pending = false
	_cat_streak += 1

	_active_slot.cat_placed_this_stroke = true

	if _cross_at_first_cat < 0:
		_cross_at_first_cat = _count_board_crosses()

	var fb_result: Dictionary = _arbitrate_feedback_for_correct_cat(row, col)
	if fb_result["should_play"]:
		_on_feedback_played(fb_result["feedback"])
		_play_like_hand_on_cell(row, col, fb_result["anim"])

	var like_played: bool = (
		fb_result["should_play"] and fb_result["feedback"] == ThumbUpConfig.Feedback.LIKE
	)
	_record_correct_cat(
		{"should_play": like_played, "anim": fb_result.get("anim", LikeHandAnim.LIKE)}
	)
	_record_game_barrage_action()


func prewarm_board(size: int) -> void:
	if _board_view == null:
		return
	var board_intro := get_node_or_null("Root") as BoardContainerCell_01
	if board_intro != null:
		board_intro.set_auto_trigger(false)
	await _board_view.prewarm_cells(size)
	if board_intro != null:
		board_intro.set_auto_trigger(true)

	await _board_view.prewarm_cat_spines(size)


func _apply_cat_found_grid_dim(animated: bool = false) -> void:
	if _board_view == null:
		return

	if LevelKind.is_color_challenge(_level_kind):
		_board_view.set_region_dim_enabled(false, animated)
		return
	_board_view.set_region_dim_enabled(ABTestManager.cat_found_grid.is_dim_enabled(), animated)


func _on_cell_changed_for_hint_cross(_r: int, _c: int, state: int, source: int) -> void:
	if source == BoardView.ChangeSource.HINT and CellState.is_cross(state):
		Tracker.inc_stat("hint_cross_count")
		print(
			(
				"[BaseGamePage] hint_cross +1 at (%d,%d), total=%d"
				% [_r, _c, Tracker.get_stat("hint_cross_count")]
			)
		)


func do_wrong_guess_mark(r: int, c: int, from_draft_apply: bool = false) -> void:
	_cat_streak = 0

	if not from_draft_apply and _active_slot != null:
		_active_slot.cat_streak_break_pending = false

	if not from_draft_apply:
		_mark_stroke_step_dirty()

	_full_mark_defer_judgement = true
	_board_view.set_cell_state(r, c, CellState.MARK)
	_full_mark_defer_judgement = false
	VibrateManager.play_at(VibrateManager.Pos.CELL_ERROR)

	if from_draft_apply:
		var rule: int = _classify_violation_at(r, c)
		if rule != QueendokuCore.Rule.NONE and not _draft_apply_violated_rules.has(rule):
			_draft_apply_violated_rules.append(rule)
	else:
		_try_emit_rule_violation(r, c)
	_on_wrong_guess(r, c, false, from_draft_apply)


func _get_conflict_rule_cells(r: int, c: int, conflict_pos: Vector2i) -> Array[Vector2i]:
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return []
	var sz: int = _level_config.get("size", 4)
	var rule: int = QueendokuCore.classify_violation(r, c, [conflict_pos], regions)
	var result: Array[Vector2i] = []
	match rule:
		QueendokuCore.Rule.SAME_COLOR:
			var region_id: int = int(regions[conflict_pos.x][conflict_pos.y])
			for rr in range(sz):
				for cc in range(sz):
					if Vector2i(rr, cc) == conflict_pos:
						continue
					if int(regions[rr][cc]) == region_id:
						result.append(Vector2i(rr, cc))
		QueendokuCore.Rule.SAME_LINE:
			if conflict_pos.x == r:
				var c_min: int = mini(c, conflict_pos.y)
				var c_max: int = maxi(c, conflict_pos.y)
				for cc in range(c_min + 1, c_max):
					result.append(Vector2i(r, cc))
			else:
				var r_min: int = mini(r, conflict_pos.x)
				var r_max: int = maxi(r, conflict_pos.x)
				for rr in range(r_min + 1, r_max):
					result.append(Vector2i(rr, c))
		QueendokuCore.Rule.NO_TOUCH:
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					if dr == 0 and dc == 0:
						continue
					var nr: int = conflict_pos.x + dr
					var nc: int = conflict_pos.y + dc
					if nr >= 0 and nr < sz and nc >= 0 and nc < sz:
						result.append(Vector2i(nr, nc))
	return result


func _find_conflict_cat(r: int, c: int) -> Vector2i:
	var regions: Array = _puzzle.get("regions", [])
	if regions.is_empty():
		return Vector2i(-1, -1)
	var sz: int = _level_config.get("size", 4)
	var placed: Array[Vector2i] = []
	var board: Array = _board_view.get_board()
	for rr in range(sz):
		for cc in range(sz):
			if rr == r and cc == c:
				continue
			if board[rr][cc] == CellState.CAT:
				placed.append(Vector2i(rr, cc))
	return QueendokuCore.find_priority_conflict_cat(r, c, placed, regions)


func _play_misplace_conflict_anim(r: int, c: int, conflict_pos: Vector2i) -> bool:
	_wrong_guess_pending = true
	var token: int = _conflict_anim_token

	if not _conflict_target_positions.has(Vector2i(r, c)):
		_conflict_target_positions.append(Vector2i(r, c))

	_save_endgame_for_pending_wrong_guess(r, c)
	var target_cell: CellView = _board_view.get_cell_view(r, c)
	var conflict_cell: CellView = _board_view.get_cell_view(conflict_pos.x, conflict_pos.y)

	if target_cell != null:
		target_cell.play_wrong_pos_reaction(MisplaceReactionConfig.TARGET_REACTION_ANIM_NAME)
		target_cell.play_grid_glow()
	if conflict_cell != null:
		conflict_cell.play_named_anim(MisplaceReactionConfig.CONFLICT_REACTION_ANIM_NAME)
		conflict_cell.play_grid_glow()

	var rule_cells: Array[Vector2i] = _get_conflict_rule_cells(r, c, conflict_pos)
	for pos in rule_cells:
		var cell: CellView = _board_view.get_cell_view(pos.x, pos.y)
		if cell != null:
			cell.play_grid_glow()

	var own_line: Dictionary = {"node": null}
	get_tree().create_timer(MisplaceReactionConfig.CONFLICT_LINE_DELAY_SEC).timeout.connect(
		func() -> void:
			if token != _conflict_anim_token:
				return
			var line := _CONFLICT_LINE_SCENE.instantiate() as LineCrossConnector
			add_child(line)
			var inv := get_global_transform().affine_inverse()
			line.setup_points(
				inv * _board_view.get_cell_global_center(r, c),
				inv * _board_view.get_cell_global_center(conflict_pos.x, conflict_pos.y)
			)
			line.play_effect()
			own_line.node = line
			_active_conflict_lines.append(line)
	)

	await get_tree().create_timer(MisplaceReactionConfig.CONFLICT_ANIM_DURATION_SEC).timeout

	if token != _conflict_anim_token:
		_conflict_target_positions.erase(Vector2i(r, c))
		return false

	_conflict_target_positions.erase(Vector2i(r, c))

	_release_conflict_line(own_line.node)
	if target_cell != null:
		target_cell.stop_named_anim()
		target_cell.stop_grid_glow()
	if conflict_cell != null:
		conflict_cell.stop_grid_glow()
	for pos in rule_cells:
		var cell: CellView = _board_view.get_cell_view(pos.x, pos.y)
		if cell != null:
			cell.stop_grid_glow()

	return true


func _cancel_misplace_conflict(reason: String = "?") -> void:
	if (
		not ABTestManager.misplace_reaction.is_conflict_reaction()
		and _conflict_target_positions.is_empty()
		and _active_conflict_lines.is_empty()
	):
		return
	_conflict_anim_token += 1

	var lines: Array[LineCrossConnector] = _active_conflict_lines.duplicate()
	for line: LineCrossConnector in lines:
		_release_conflict_line(line)
	_active_conflict_lines.clear()

	var was_deferred: bool = _full_mark_defer_judgement
	_full_mark_defer_judgement = true
	for pos: Vector2i in _conflict_target_positions:
		var cell_view: CellView = (
			_board_view.get_cell_view(pos.x, pos.y) if _board_view != null else null
		)
		if cell_view != null:
			cell_view.reset_wrong_pos_reaction()
			if reason == "on_hide":
				_board_view.mark_cell_error(pos.x, pos.y)
	_full_mark_defer_judgement = was_deferred
	_conflict_target_positions.clear()

	_wrong_guess_pending = false


func _snapshot_cell_overrides(explicit_cells: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	for pos: Vector2i in _conflict_target_positions:
		cells[pos] = CellState.ERROR
	cells.merge(explicit_cells, true)
	return cells


func _save_endgame_for_pending_wrong_guess(_row: int, _column: int) -> void:
	pass


func _mark_step_dirty() -> void:
	_step_dirty = true


func _clear_step_dirty() -> void:
	_step_dirty = false


func _mark_stroke_step_dirty() -> void:
	if _active_slot == null:
		_step_dirty = true
		return
	_active_slot.step_dirty = true


func _clear_stroke_step_dirty() -> void:
	if _active_slot == null:
		_step_dirty = false
		return
	_active_slot.step_dirty = false


func _count_board_step(source: String = "gesture", stroke_slot: BoardTouchSlot = null) -> void:
	if source == "gesture":
		var slot: BoardTouchSlot = stroke_slot if stroke_slot != null else _active_slot
		if _gesture_step_breaks_cat_streak(slot):
			_cat_streak = 0
	else:
		_break_cat_streak_from_non_gesture()

	Tracker.inc_stat("step_used")
	GameState.inc_game_total_stat(_game_type(), "step_total")
	print(
		(
			"[BaseGamePage] step +1 (%s), step_used=%d step_total=%d"
			% [
				source,
				Tracker.get_stat("step_used"),
				GameState.get_game_total_stat(_game_type(), "step_total")
			]
		)
	)


func _init_session_state() -> void:
	_clear_step_dirty()

	_clear_all_touch_slots()

	_locked_pointer_index = _NO_POINTER_INDEX

	ABTestManager.doubletap_protect.reset_high_freq_state()

	_se_amortized_step = -1

	_exit_draft_mode_and_clear()
	_clear_draft_rollback_state()

	_draft_busy = false

	_draft_used_this_level = false

	_full_mark_tracker.reset()
	_full_mark_last_cell = Vector2i(-1, -1)

	_is_app_foreground = true

	_kill_full_mark_tween()

	if _board_outer_glow != null:
		_board_outer_glow.reset_glow_color()
	if _apply_btn != null:
		_apply_btn.visible = false

	_today_mark_cells.clear()
	_today_mark_withdrawn_cell = Vector2i(-1, -1)

	reset_last_cat_stats()

	if not OS.has_feature("rel"):
		_today_log_base_cat = GameState.get_today_cat_found()
		_today_log_base_mark = GameState.get_today_mark_placed()

	_layout_bottom_tools()
	_sync_tools_from_state()

	_refresh_ad_unavailable_badge()

	_arm_network_poll()


var _today_mark_cells: Dictionary = {}

var _today_mark_withdrawn_cell: Vector2i = Vector2i(-1, -1)

var _cat_streak: int = 0

var _cross_at_first_cat: int = -1

var _cat_streak_token: int = 0


func _on_cell_changed_for_today_marks(r: int, c: int, state: int, source: int = 0) -> void:
	var cell_key: Vector2i = Vector2i(r, c)
	if state == CellState.MARK:
		if source == BoardView.ChangeSource.PREFILL:
			return
		_today_mark_cells[cell_key] = true
		return

	if state == CellState.ERROR:
		_today_mark_cells.erase(cell_key)
		return

	if state == CellState.CAT:
		if _today_mark_cells.erase(cell_key):
			_today_mark_withdrawn_cell = cell_key
		return

	if source == BoardView.ChangeSource.UNDO:
		_today_mark_cells.erase(cell_key)


func today_mark_cell_count() -> int:
	return _today_mark_cells.size()


func _count_board_crosses() -> int:
	var board_n: int = int(_level_config.get("size", 0))
	if board_n <= 0 or _board_view == null:
		return 0
	var total: int = 0
	for r in board_n:
		for c in board_n:
			var state: int = _board_view.get_cell_state(r, c)
			if state == CellState.MARK or state == CellState.ERROR:
				total += 1
	return total


func reset_last_cat_stats() -> void:
	_cat_streak = 0
	_cross_at_first_cat = -1

	_cat_streak_token += 1
	_clear_cat_streak_stroke_flags()


func _gesture_step_breaks_cat_streak(slot: BoardTouchSlot) -> bool:
	if slot == null:
		return true
	return not slot.cat_placed_this_stroke and not slot.cat_streak_break_pending


func _clear_cat_streak_stroke_flags() -> void:
	var slots: Array = _touch_slots.values()
	for slot: BoardTouchSlot in slots:
		slot.cat_placed_this_stroke = false
		slot.cat_streak_break_pending = false


func _break_cat_streak_from_non_gesture() -> void:
	_clear_cat_streak_stroke_flags()
	_cat_streak = 0


func _last_cat_at_last_flag() -> int:
	var board_n: int = int(_level_config.get("size", 0))
	return 1 if LastCatJudge.is_hit(_cat_streak, _cross_at_first_cat, board_n) else 0


const _TODAY_LOG_PLAYER_SOURCES: Array[int] = [
	BoardView.ChangeSource.USER_ACTION,
	BoardView.ChangeSource.LOCATE,
	BoardView.ChangeSource.HINT,
	BoardView.ChangeSource.MOUSE,
	BoardView.ChangeSource.DRAFT_APPLY,
	BoardView.ChangeSource.UNDO,
	BoardView.ChangeSource.FULL_MARK_AUTO_CROSS,
]

var _today_log_base_cat: int = 0
var _today_log_base_mark: int = 0


func _on_cell_changed_for_today_stats_log(r: int, c: int, state: int, source: int = 0) -> void:
	if not _TODAY_LOG_PLAYER_SOURCES.has(source):
		return
	var what: String = ""
	var note: String = ""
	if state == CellState.CAT:
		what = "放猫"

		if _today_mark_withdrawn_cell == Vector2i(r, c):
			note = " 覆盖了白叉,叉数已撤回"
	elif state == CellState.MARK:
		what = "标叉"
	elif state == CellState.ERROR:
		what = "红叉"
		note = " 不记录,叉数已撤回"
	elif source == BoardView.ChangeSource.UNDO:
		what = "撤销"
	else:
		return

	var board_n: int = int(_level_config.get("size", 0))
	print(
		(
			"[今日战绩] %s(%d,%d)%s | 本局 猫=%d 叉=%d | 今日(本关开始时) 猫=%d 叉=%d,通关后才累加 | streak=%d cross@1st=%d 现叉=%d/阈%d flag=%d"
			% [
				what,
				r,
				c,
				note,
				_board_view.count_cat_cells(),
				today_mark_cell_count(),
				_today_log_base_cat,
				_today_log_base_mark,
				_cat_streak,
				_cross_at_first_cat,
				_count_board_crosses(),
				LastCatJudge.cross_threshold(board_n),
				_last_cat_at_last_flag()
			]
		)
	)


func _accumulate_today_win_stats() -> void:
	var cat_delta: int = _board_view.count_cat_cells()
	var mark_delta: int = today_mark_cell_count()
	var delta: Dictionary = GameState.add_today_win_stats(
		cat_delta, mark_delta, int(ABTestManager.pass_text.value())
	)
	_level_config["today_cat_before"] = delta["cat_before"]
	_level_config["today_cat_after"] = delta["cat_after"]
	_level_config["today_mark_before"] = delta["mark_before"]
	_level_config["today_mark_after"] = delta["mark_after"]

	print(
		(
			"[今日战绩] %s 本局 猫+%d 叉+%d | 猫 %d→%d | 叉 %d→%d | pass_text组=%d"
			% [
				_game_type(),
				cat_delta,
				mark_delta,
				delta["cat_before"],
				delta["cat_after"],
				delta["mark_before"],
				delta["mark_after"],
				int(ABTestManager.pass_text.value())
			]
		)
	)


enum ToolLayout { NORMAL, DRAFT_ON }

const _DRAFT_ON_BT_INSET: float = 385.0


func _layout_bottom_tools(mode: int = ToolLayout.NORMAL) -> void:
	var draft_on: bool = mode == ToolLayout.DRAFT_ON

	_bt.set_hint_first(ABTestManager.prop_position.is_hint_first())

	_bt.set_kind_enabled(ToolKind.LOCATE, not draft_on)
	_bt.set_kind_enabled(ToolKind.HINT, not draft_on)
	_bt.set_kind_enabled(ToolKind.MOUSE, (not draft_on) and _is_mouse_tool_enabled())
	_bt.set_kind_locked(ToolKind.MOUSE, not _is_mouse_tool_unlocked(), MOUSE_UNLOCK_LEVEL)

	_bt.set_kind_enabled(ToolKind.DRAFT, _is_draft_unlocked())

	_bt.offset_right = -_DRAFT_ON_BT_INSET if draft_on else 0.0


func _step_cell(r: int, c: int, result: int) -> Dictionary:
	return Tracker.build_step_cell(r, c, _region_of_cell(r, c), result)


func _region_of_cell(r: int, c: int) -> int:
	var regions: Array = _puzzle.get("regions", [])
	if r < 0 or r >= regions.size():
		return -1
	var row: Array = regions[r] as Array
	if c < 0 or c >= row.size():
		return -1
	return int(row[c])


func _mark_step_result(r: int, c: int) -> int:
	return Tracker.StepResult.WRONG if _is_solution_cell(r, c) else Tracker.StepResult.CORRECT


func _sign_step_result(r: int, c: int) -> int:
	return Tracker.StepResult.CORRECT if _is_solution_cell(r, c) else Tracker.StepResult.WRONG


func _collect_gesture_step_cell(action: CellAction) -> void:
	if _active_slot == null or action.before == action.state:
		return
	if _board_view.get_cell_state(action.row, action.col) != action.state:
		return
	_active_slot.step_cells.append({"r": action.row, "c": action.col, "state": action.state})


func _flush_gesture_solution_step(
	slot: BoardTouchSlot, is_cat_click: bool, release_pos: Vector2
) -> void:
	if slot.step_cells.is_empty():
		if is_cat_click:
			var click_cell: Vector2i = _board_view.pointer_to_cell(release_pos.x, release_pos.y)
			Tracker.record_solution_step(
				Tracker.StepAction.CLICK_EXISTING_SIGN,
				[_step_cell(click_cell.y, click_cell.x, Tracker.StepResult.NO_JUDGE)]
			)
		return
	var is_mark: bool = int(slot.step_cells[0]["state"]) == CellState.MARK
	var cells: Array = []
	for entry: Dictionary in slot.step_cells:
		var row: int = int(entry["r"])
		var col: int = int(entry["c"])
		var result: int = _mark_step_result(row, col) if is_mark else Tracker.StepResult.NO_JUDGE
		cells.append(_step_cell(row, col, result))
	var action: String
	if cells.size() == 1:
		action = Tracker.StepAction.MARK if is_mark else Tracker.StepAction.ERASE_MARK
	else:
		action = Tracker.StepAction.SWIPE_MARK if is_mark else Tracker.StepAction.SWIPE_ERASE
	slot.step_cells.clear()
	Tracker.record_solution_step(action, cells)


func _record_double_tap_solution_step(
	r: int, c: int, is_correct: bool, first_tap_counted: bool
) -> void:
	var result: int = Tracker.StepResult.CORRECT if is_correct else Tracker.StepResult.WRONG
	var cells: Array = [_step_cell(r, c, result)]
	if first_tap_counted:
		Tracker.remove_latest_single_tap_step(r, c)
	Tracker.record_solution_step(Tracker.StepAction.SIGN, cells)


func _record_mouse_solution_step(targets: Array[Dictionary]) -> void:
	var cells: Array = []
	var has_cat: bool = false
	for target: Dictionary in targets:
		var cell: Vector2i = target.cell
		if bool(target.is_cat):
			has_cat = true
			cells.append(_step_cell(cell.x, cell.y, _sign_step_result(cell.x, cell.y)))
		else:
			cells.append(_step_cell(cell.x, cell.y, _mark_step_result(cell.x, cell.y)))
	var action: String = Tracker.StepAction.MOUSE_SIGN if has_cat else Tracker.StepAction.MOUSE_MARK
	Tracker.record_solution_step(action, cells)


func _hint_step_targets(hint: Dictionary) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var strategy: String = hint.get("strategy", "R1")
	var mark_cells: Array[Vector2i] = []
	if strategy == "R1_mark":
		for cell_v in hint.get("unit_cells", []) as Array:
			var unit_cell: Vector2i = cell_v as Vector2i
			if CellState.is_blank(_board_view.get_cell_state(unit_cell.x, unit_cell.y)):
				mark_cells.append(unit_cell)
	elif strategy == "R3" or strategy == "R4":
		mark_cells = _compute_r3_r4_mark_cells(hint)
	elif strategy == "R3b" or strategy == "R4b":
		mark_cells = _compute_r3_r4b_mark_cells(hint)
	elif strategy == "R2":
		mark_cells = _compute_r2_mark_cells(hint)
	elif strategy == "R4_chain" or strategy == "R5_chain":
		var chain_cell: Vector2i = hint.get("cell", Vector2i(-1, -1))
		if chain_cell.x >= 0:
			mark_cells.append(chain_cell)
	else:
		var key_cell: Vector2i = hint.get("cell", Vector2i(-1, -1))
		if key_cell.x >= 0:
			var effect: String = (
				Tracker.StepEffect.ERASE
				if hint.get("wrong_mark", false)
				else Tracker.StepEffect.SIGN
			)
			targets.append({"cell": key_cell, "effect": effect})
		return targets
	for mark_cell: Vector2i in mark_cells:
		targets.append({"cell": mark_cell, "effect": Tracker.StepEffect.MARK})
	return targets


func _record_hint_show_solution_step(hint: Dictionary) -> void:
	var cells: Array = []
	var targets: Array[Dictionary] = _hint_step_targets(hint)
	for target: Dictionary in targets:
		var cell: Vector2i = target["cell"]
		cells.append(
			Tracker.build_hint_show_cell(
				cell.x, cell.y, _region_of_cell(cell.x, cell.y), target["effect"]
			)
		)
	Tracker.record_solution_step(Tracker.StepAction.HINT_SHOW, cells)


func _record_hint_apply_solution_step(hint: Dictionary) -> void:
	var cells: Array = []
	var action: String = Tracker.StepAction.HINT_APPLY_MARK
	var targets: Array[Dictionary] = _hint_step_targets(hint)
	for target: Dictionary in targets:
		var cell: Vector2i = target["cell"]
		match target["effect"]:
			Tracker.StepEffect.SIGN:
				action = Tracker.StepAction.HINT_APPLY_SIGN
				cells.append(_step_cell(cell.x, cell.y, _sign_step_result(cell.x, cell.y)))
			Tracker.StepEffect.ERASE:
				action = Tracker.StepAction.HINT_APPLY_ERASE
				cells.append(_step_cell(cell.x, cell.y, _sign_step_result(cell.x, cell.y)))
			_:
				cells.append(_step_cell(cell.x, cell.y, _mark_step_result(cell.x, cell.y)))
	Tracker.record_solution_step(action, cells)


## 该格是否答案格（越界返回 false）
func _is_solution_cell(r: int, c: int) -> bool:
	var sol: Array = _puzzle.get("solution", [])
	if r < 0 or r >= sol.size():
		return false
	var row: Array = sol[r] as Array
	if c < 0 or c >= row.size():
		return false
	return bool(row[c])


func _puzzle_sol_1d() -> Array:
	var sol_2d: Array = _puzzle.get("solution", [])
	var result: Array = []
	for r: int in range(sol_2d.size()):
		var row: Array = sol_2d[r] as Array
		var found: int = -1
		for c: int in range(row.size()):
			if bool(row[c]):
				found = c
				break
		result.append(found)
	return result


func _on_appear_animation_finished() -> void:
	_entry_anim_playing = false
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP


# ================= 自动完成（AB: auto_complete） =================
## 自动完成时每条对角线之间的间隔（秒）
const AUTO_MARK_DIAG_INTERVAL_SEC: float = 0.06
## 打叉完到开始放猫的间隔（秒）
const AUTO_MARK_TO_CAT_GAP_SEC: float = 0.2
## 逐只放猫的间隔（秒）
const AUTO_CAT_STEP_SEC: float = 0.12
## 自动完成进行中，屏蔽输入
var _auto_completing: bool = false

## 自动完成令牌，自增即可中断进行中的流程
var _auto_complete_token: int = 0


func _run_auto_complete(token: int) -> void:
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return
	var sol: Array = _puzzle["solution"]

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

	_update_remaining()
	_validate_board()


const _FOUND_BLINK_SOURCES: Array[int] = [
	BoardView.ChangeSource.USER_ACTION,
	BoardView.ChangeSource.LOCATE,
	BoardView.ChangeSource.HINT,
	BoardView.ChangeSource.DRAFT_APPLY,
]


func _on_cell_changed_for_found_blink_all(r: int, c: int, state: int, source: int = 0) -> void:
	if state != CellState.CAT:
		return
	if not (source in _FOUND_BLINK_SOURCES):
		return

	if _applying_draft_commit:
		return

	_broadcast_found_blink_all(Vector2i(r, c))


func _broadcast_found_blink_all(exclude: Vector2i = Vector2i(-1, -1)) -> void:
	if not ABTestManager.found_cat_animation.should_blink_all_found():
		return
	if _board_view == null or not is_instance_valid(_board_view):
		return

	if Engine.is_editor_hint():
		return

	if _is_complete:
		return

	var sz: int = _level_config.get("size", 4)
	if _count_placed_cats(sz) >= sz:
		return

	if _is_pre_cat_fx_playing():
		return

	_board_view.play_found_blink_all("", exclude)


func _is_pre_cat_fx_playing() -> bool:
	return false


func _found_cat_spine_anim(source: int) -> String:
	if not (source in _FOUND_BLINK_SOURCES):
		return ""
	return ABTestManager.found_cat_animation.single_found_anim_name()


func _connect_combo_signal() -> void:
	if not _board_view.cell_state_changed.is_connected(_on_board_cell_state_changed_for_combo):
		_board_view.cell_state_changed.connect(_on_board_cell_state_changed_for_combo)

	if not _board_view.cell_state_changed.is_connected(_on_board_cell_state_changed_for_se):
		_board_view.cell_state_changed.connect(_on_board_cell_state_changed_for_se)


func _disconnect_combo_signal() -> void:
	if _board_view.cell_state_changed.is_connected(_on_board_cell_state_changed_for_combo):
		_board_view.cell_state_changed.disconnect(_on_board_cell_state_changed_for_combo)
	if _board_view.cell_state_changed.is_connected(_on_board_cell_state_changed_for_se):
		_board_view.cell_state_changed.disconnect(_on_board_cell_state_changed_for_se)


signal full_mark_units_cleared(units: Array)

signal full_mark_achieved(cells_to_cross: Array, dominant_region: int)

var _full_mark_tracker: FullMarkTracker = FullMarkTracker.new()

var _full_mark_last_cell: Vector2i = Vector2i(-1, -1)

var _full_mark_defer_judgement: bool = false

var _full_mark_defer_token: int = 0

const _FULL_MARK_AFTER_CONFLICT_SEC: float = 2.183

var _full_mark_tween: Tween = null

var _unit_clear_tweens: Array[Tween] = []

const _FULL_MARK_WAVE_DELAY: float = 0.4667
const _FULL_MARK_WAVE_STEP: float = 0.0333

const _UNIT_CLEAR_WAVE_DELAY: float = 0.0667
const _UNIT_CLEAR_WAVE_STEP: float = 0.0333


func _full_mark_geometry() -> Dictionary:
	if _board_view == null or _puzzle.is_empty() or not _puzzle.has("regions"):
		return {}
	var size: int = _level_config.get("size", 0)
	if size <= 0:
		return {}

	return {
		"board": _board_view.get_cell_state_folded_board(),
		"size": size,
		"regions": _puzzle["regions"],
		"solution": _puzzle.get("solution", []),
	}


func _on_cell_changed_for_full_mark(r: int, c: int, state: int, source: int = 0) -> void:
	if not ABTestManager.full_mark_feedback.has_full_mark_feedback():
		return

	if source == BoardView.ChangeSource.FULL_MARK_AUTO_CROSS:
		return

	if source == BoardView.ChangeSource.PREFILL or source == BoardView.ChangeSource.RESTORE:
		return

	if _applying_draft_commit:
		return

	_full_mark_last_cell = Vector2i(r, c)

	if _full_mark_defer_judgement:
		return
	if not ABTestManager.full_mark_feedback.has_unit_clear_feedback():
		return

	if _full_mark_tracker.is_full_mark_consumed():
		return
	var geometry: Dictionary = _full_mark_geometry()
	if geometry.is_empty():
		return

	var perf_takes_text: bool = state == CellState.CAT and _will_full_mark_take_over(geometry)
	var fresh: Array[Dictionary] = _full_mark_tracker.collect_new_units(
		geometry["board"], geometry["size"], geometry["regions"], geometry["solution"]
	)
	if not fresh.is_empty():
		full_mark_units_cleared.emit(fresh)

		_play_unit_clear_feedback(fresh, Vector2i(r, c), not perf_takes_text)


func _will_full_mark_take_over(geometry: Dictionary) -> bool:
	var board: Array = geometry["board"]
	var size: int = geometry["size"]
	if not FullMarkDetector.is_full_mark(board, size):
		return false
	return QueendokuCore.is_complete(board, size, geometry["regions"])


func _emit_full_mark_achieved_if_any() -> void:
	if not ABTestManager.full_mark_feedback.has_full_mark_feedback():
		return
	var geometry: Dictionary = _full_mark_geometry()
	if geometry.is_empty():
		return

	var result: Dictionary = _full_mark_tracker.consume_full_mark(
		geometry["board"], geometry["size"], geometry["regions"]
	)
	if bool(result["hit"]):
		full_mark_achieved.emit(result["cells_to_cross"], int(result["dominant_region"]))
		_play_full_mark_feedback(
			result["cells_to_cross"], int(result["dominant_region"]), int(geometry["size"])
		)


func _play_full_mark_feedback(cells_to_cross: Array, dominant_region: int, size: int) -> void:
	if _board_view == null or size <= 0:
		return

	for cell: Vector2i in cells_to_cross:
		_board_view.set_cell_state(
			cell.x,
			cell.y,
			CellState.MARK,
			true,
			true,
			BoardView.ChangeSource.FULL_MARK_AUTO_CROSS,
			"AutoXFillMode2",
			false
		)

	if dominant_region >= 0 and _board_outer_glow != null:
		_board_outer_glow.set_glow_color(_board_view.get_region_color(dominant_region))
	if _anim_board_glow != null and _anim_board_glow.has_animation("BoardGlow"):
		_anim_board_glow.stop()
		_anim_board_glow.play("BoardGlow")

	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)

	if ABTestManager.full_mark_feedback.has_full_mark_text():
		_show_full_mark_text(true, _full_mark_last_cell)

	var cross_cells: Array[Vector2i] = []
	for r in size:
		for c in size:
			if CellState.is_cross(_board_view.get_cell_state(r, c)):
				cross_cells.append(Vector2i(r, c))
	if _full_mark_tween != null and _full_mark_tween.is_valid():
		_full_mark_tween.kill()
	_full_mark_tween = _build_grid_glow_wave(
		FullMarkDetector.group_by_diagonal(cross_cells, size),
		_FULL_MARK_WAVE_DELAY,
		_FULL_MARK_WAVE_STEP
	)


func _play_unit_clear_feedback(units: Array, anchor: Vector2i, show_text: bool = true) -> void:
	if _board_view == null or anchor.x < 0 or units.is_empty():
		return

	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)

	if show_text and ABTestManager.full_mark_feedback.has_unit_clear_text():
		_show_full_mark_text(false, anchor)

	_unit_clear_tweens = _unit_clear_tweens.filter(
		func(tween: Tween) -> bool: return tween != null and tween.is_valid()
	)
	var wave: Tween = _build_grid_glow_wave(
		FullMarkDetector.group_by_ring(_dedup_unit_cells(units), anchor),
		_UNIT_CLEAR_WAVE_DELAY,
		_UNIT_CLEAR_WAVE_STEP
	)
	if wave != null:
		_unit_clear_tweens.append(wave)


func _dedup_unit_cells(units: Array) -> Array[Vector2i]:
	var seen: Dictionary = {}
	var cells: Array[Vector2i] = []
	for unit: Dictionary in units:
		var unit_cells: Array = unit["cells"]
		for cell: Vector2i in unit_cells:
			if seen.has(cell):
				continue
			seen[cell] = true
			cells.append(cell)
	return cells


func _build_grid_glow_wave(groups: Dictionary, first_delay: float, step: float) -> Tween:
	if groups.is_empty():
		return null
	var keys: Array = groups.keys()
	keys.sort()
	var wave: Tween = create_tween()
	wave.tween_interval(first_delay)
	for i in keys.size():
		wave.tween_callback(_play_grid_glow_on_cells.bind(groups[keys[i]]))
		if i < keys.size() - 1:
			wave.tween_interval(step)
	return wave


func _play_grid_glow_on_cells(cells: Array) -> void:
	if _board_view == null:
		return
	for cell: Vector2i in cells:
		var view: CellView = _board_view.get_cell_view(cell.x, cell.y)
		if view != null:
			view.play_grid_glow_2()


func _flush_full_mark_after_draft_apply() -> void:
	if not ABTestManager.full_mark_feedback.has_unit_clear_feedback():
		return
	if _full_mark_tracker.is_full_mark_consumed():
		return
	var geometry: Dictionary = _full_mark_geometry()
	if geometry.is_empty():
		return

	if _will_full_mark_take_over(geometry):
		return
	var fresh: Array[Dictionary] = _full_mark_tracker.collect_new_units(
		geometry["board"], geometry["size"], geometry["regions"], geometry["solution"]
	)
	if fresh.is_empty():
		return
	full_mark_units_cleared.emit(fresh)
	VibrateManager.play_vibrate(VibrateManager.Level.LEVEL2)

	if ABTestManager.full_mark_feedback.has_unit_clear_text():
		_show_full_mark_text(false, _full_mark_last_cell)

	_unit_clear_tweens = _unit_clear_tweens.filter(
		func(tween: Tween) -> bool: return tween != null and tween.is_valid()
	)
	var wave: Tween = _build_grid_glow_wave(
		FullMarkDetector.group_by_diagonal(_dedup_unit_cells(fresh), int(geometry["size"])),
		_FULL_MARK_WAVE_DELAY,
		_FULL_MARK_WAVE_STEP
	)
	if wave != null:
		_unit_clear_tweens.append(wave)


func _flush_full_mark_unit_clear(anchor: Vector2i) -> void:
	if not ABTestManager.full_mark_feedback.has_unit_clear_feedback():
		return
	if _full_mark_tracker.is_full_mark_consumed():
		return
	var geometry: Dictionary = _full_mark_geometry()
	if geometry.is_empty():
		return
	var fresh: Array[Dictionary] = _full_mark_tracker.collect_new_units(
		geometry["board"], geometry["size"], geometry["regions"], geometry["solution"]
	)
	if fresh.is_empty():
		return
	full_mark_units_cleared.emit(fresh)
	_play_unit_clear_feedback(fresh, anchor)


func _defer_full_mark_after_conflict(anchor: Vector2i) -> void:
	if not ABTestManager.full_mark_feedback.has_unit_clear_feedback():
		return
	var remaining: float = (
		_FULL_MARK_AFTER_CONFLICT_SEC - MisplaceReactionConfig.CONFLICT_ANIM_DURATION_SEC
	)
	if remaining <= 0.0:
		_flush_full_mark_unit_clear(anchor)
		return
	var token: int = _full_mark_defer_token
	get_tree().create_timer(remaining).timeout.connect(
		func() -> void:
			if token != _full_mark_defer_token:
				return
			if _board_view == null:
				return
			if _is_complete:
				return
			_flush_full_mark_unit_clear(anchor),
		CONNECT_ONE_SHOT
	)


func _seed_full_mark_fired_units_from_board(reason: String = "开局棋面") -> void:
	if not ABTestManager.full_mark_feedback.has_unit_clear_feedback():
		return
	var geometry: Dictionary = _full_mark_geometry()
	if geometry.is_empty():
		return
	var primed: int = _full_mark_tracker.prime_fired_units(
		geometry["board"], geometry["size"], geometry["regions"], geometry["solution"]
	)
	if primed > 0 and not OS.has_feature("rel"):
		print("[full_mark] seed(%s):已满 %d 个单元,登记为已反馈(不播、不补播)" % [reason, primed])


func _defer_full_mark_unit_clear(r: int, c: int) -> void:
	if not ABTestManager.full_mark_feedback.has_unit_clear_feedback():
		return
	var token: int = _full_mark_defer_token
	var sec: float = _cur_window_sec() + _MISSED_CROSS_DEFER_MARGIN_SEC
	get_tree().create_timer(sec).timeout.connect(
		func() -> void:
			if token != _full_mark_defer_token:
				return
			if _board_view == null:
				return
			if _is_complete:
				return

			if _conflict_target_positions.has(Vector2i(r, c)):
				return

			_flush_full_mark_unit_clear(Vector2i(r, c)),
		CONNECT_ONE_SHOT
	)


func _show_full_mark_text(is_perfect: bool, anchor: Vector2i) -> void:
	if _combo_feedback_view == null or _board_view == null:
		return
	if anchor.x < 0:
		return
	if not _combo_feedback_view.has_method("show_full_mark_text"):
		return
	var cell_global: Vector2 = _board_view.get_cell_global_center(anchor.x, anchor.y)
	_combo_feedback_view.show_full_mark_text(cell_global, is_perfect)


func _kill_full_mark_tween() -> void:
	if _full_mark_tween != null and _full_mark_tween.is_valid():
		_full_mark_tween.kill()
	_full_mark_tween = null
	for tween: Tween in _unit_clear_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_unit_clear_tweens.clear()


const _OPERABLE_DELTA_CAP_SEC: float = 0.1

var _operable_sec: float = 0.0

var _is_app_foreground: bool = true

var _cat_toast_tracker: CatToastTracker = CatToastTracker.new()


func _on_cell_changed_for_cat_toast(r: int, c: int, state: int, source: int = 0) -> void:
	if state != CellState.CAT:
		return
	if source != BoardView.ChangeSource.USER_ACTION:
		return
	var cfg := ABTestManager.cat_toast

	_cat_toast_tracker.sync_level(_cat_toast_level_key())

	var board_size: int = _level_config.get("size", 0)
	var consumed_step: int = _consumed_step_for_placed_cat(source)
	var scene: int = _cat_toast_tracker.on_player_cat_placed(
		int(cfg.value()), board_size, _operable_sec, consumed_step
	)

	if not OS.has_feature("rel"):
		_log_cat_toast_decision(r, c, board_size, scene)
	if scene == CatToastJudge.SCENE_NONE:
		return

	if _combo_feedback_view != null and _combo_feedback_view.has_method("show_cat_toast_text"):
		_combo_feedback_view.show_cat_toast_text(
			_board_view.get_cell_global_center(r, c), int(cfg.value()), scene
		)


func _log_cat_toast_decision(r: int, c: int, board_size: int, scene: int) -> void:
	var cat_no: int = _cat_toast_tracker.player_cat_count()
	var delta_sec: float = _cat_toast_tracker.last_delta_sec()
	var delta_step: int = _cat_toast_tracker.last_delta_step()
	var result: String = CatToastJudge.scene_name(scene)
	if cat_no <= 1:
		print(
			(
				"[cat_toast] 第1只猫 (%d,%d) sz=%d | 当前 %.2fs / %d步 | %s"
				% [r, c, board_size, delta_sec, delta_step, result]
			)
		)
		return
	print(
		(
			"[cat_toast] 第%d只猫 (%d,%d) sz=%d | 距上一只 %.2fs / %d步 | 累计可操作 %.2fs | %s"
			% [cat_no, r, c, board_size, delta_sec, delta_step, _operable_sec, result]
		)
	)


func _cat_toast_level_key() -> String:
	var pid: String = str(_level_config.get("_puzzle_id", ""))
	if not pid.is_empty():
		return pid
	return "%s:%d" % [_game_type(), GameState.get_current_level()]


var _near_death_fired: bool = false

var _near_death_blocked: bool = false

var _near_death_level_key: String = ""


func _on_cell_changed_for_near_death(r: int, c: int, state: int, source: int = 0) -> void:
	if state != CellState.CAT or source != BoardView.ChangeSource.USER_ACTION:
		return
	_sync_near_death_level()
	if _near_death_blocked or _near_death_fired or _lives_inf or _lives != 1 or _life_cap <= 1:
		return
	if not _allows_near_death_feedback():
		return
	_near_death_fired = true

	ABTestManager.dye_at_one_fish_cat()
	var cfg := ABTestManager.near_death_fdb
	if not OS.has_feature("rel"):
		print("[near_death] 触发 (%d,%d) group=%d" % [r, c, int(cfg.value())])
	if cfg.should_show_safe_text():
		if _combo_feedback_view != null and _combo_feedback_view.has_method("show_near_death_text"):
			_combo_feedback_view.show_near_death_text(_board_view.get_cell_global_center(r, c))
	elif cfg.should_play_bounce_glow():
		_board_view.play_near_death_appear(r, c)

		_life_bar.play_highlight_glow_at(_lives - 1)


func _allows_near_death_feedback() -> bool:
	return true


func _block_near_death_for_current_level() -> void:
	_near_death_blocked = true


func _sync_near_death_level() -> void:
	var level_key: String = _cat_toast_level_key()
	if _near_death_level_key.is_empty():
		_near_death_level_key = level_key
		return
	if level_key != _near_death_level_key:
		_near_death_level_key = level_key
		_near_death_fired = false


var _wrong_zone_tracker: WrongZoneTracker = WrongZoneTracker.new()


func _on_cell_changed_for_wrong_zone(r: int, c: int, state: int, source: int = 0) -> void:
	var regions: Array = _board_view.get_regions()
	if r < 0 or r >= regions.size():
		return
	var region_row: Array = regions[r]
	if c < 0 or c >= region_row.size():
		return
	var region_id: int = int(region_row[c])
	var fully_crossed: bool = WrongZoneTracker.is_region_fully_crossed(
		_board_view.get_board(), regions, region_id
	)
	var is_replay: bool = source == BoardView.ChangeSource.RESTORE
	var first_full: bool = _wrong_zone_tracker.update_region(
		region_id, fully_crossed, is_replay, Vector2i(r, c), state == CellState.CAT
	)
	if first_full and not is_replay and not OS.has_feature("rel"):
		print(
			(
				"[wrong_zone] 色区%d 全叉 (%d,%d) source=%s group=%d"
				% [
					region_id,
					r,
					c,
					BoardView.source_name(source),
					int(ABTestManager.wrong_zone_fdb.value())
				]
			)
		)

	if not is_replay:
		_refresh_cat_progress_wrong_marks()
	if state == CellState.CAT:
		if _board_view.highlighted_region() == region_id:
			_stop_wrong_zone_highlight()
		if source == BoardView.ChangeSource.USER_ACTION:
			_try_show_good_eye(r, c, region_id)


func _try_show_good_eye(r: int, c: int, region_id: int) -> void:
	var cfg := ABTestManager.wrong_zone_fdb
	if not cfg.should_show_good_eye() or not _allows_wrong_zone_feedback():
		return
	var requires_hint: bool = cfg.should_highlight_zone()
	if not _wrong_zone_tracker.try_reward_good_eye(region_id, requires_hint):
		return
	if not OS.has_feature("rel"):
		print("[wrong_zone] Good Eye! 色区%d (%d,%d) group=%d" % [region_id, r, c, int(cfg.value())])
	if _combo_feedback_view != null and _combo_feedback_view.has_method("show_good_eye_text"):
		_combo_feedback_view.show_good_eye_text(_board_view.get_cell_global_center(r, c))


func _allows_wrong_zone_feedback() -> bool:
	return true


func _on_wrong_zone_state_changed() -> void:
	return


func _refresh_cat_progress_wrong_marks() -> void:
	if _cat_progress == null or not _cat_progress.has_method("set_wrong_marks"):
		return
	var flags: Array = []
	if (
		_cat_progress.visible
		and ABTestManager.wrong_zone_fdb.should_mark_progress_slot()
		and _allows_wrong_zone_feedback()
	):
		flags = _cat_progress_wrong_mark_flags(_board_view.get_puzzle_size())
	_cat_progress.set_wrong_marks(flags)


func _cat_progress_wrong_mark_flags(sz: int) -> Array:
	var flags: Array = []
	var marked_regions: Array[int] = []
	var with_cat: Dictionary = _collect_regions_with_cat(sz)
	var full_regions: Array[int] = _wrong_zone_tracker.full_regions()
	for region_id: int in full_regions:
		if not with_cat.has(region_id):
			marked_regions.append(region_id)
	if marked_regions.is_empty():
		return flags
	var by_region: bool = (
		ABTestManager.normal_top_ui.is_cat_progress_colored()
		or ABTestManager.normal_top_ui.is_cat_progress_compact()
	)
	if by_region:
		if _cat_progress_region_order.size() != sz:
			return flags
		for i in sz:
			flags.append(marked_regions.has(_cat_progress_region_order[i]))
		return flags
	var first_marked: int = maxi(sz - marked_regions.size(), with_cat.size())
	for i in sz:
		flags.append(i >= first_marked)
	return flags


const _WRONG_ZONE_IDLE_SEC: float = 10.0

var _wrong_zone_idle_sec: float = 0.0


func _note_wrong_zone_activity() -> void:
	_wrong_zone_idle_sec = 0.0
	_stop_wrong_zone_highlight()


func _stop_wrong_zone_highlight() -> void:
	if _board_view != null and is_instance_valid(_board_view):
		_board_view.stop_region_highlight()


func _tick_wrong_zone_idle(delta: float) -> void:
	if not ABTestManager.wrong_zone_fdb.should_highlight_zone():
		return
	if _draft_mode or _is_complete or _board_view == null:
		return
	if _board_view.highlighted_region() >= 0:
		return
	var idle_before: float = _wrong_zone_idle_sec
	_wrong_zone_idle_sec += delta
	if idle_before < _WRONG_ZONE_IDLE_SEC and _wrong_zone_idle_sec >= _WRONG_ZONE_IDLE_SEC:
		_try_show_wrong_zone_highlight()


func _try_show_wrong_zone_highlight() -> void:
	if not _allows_wrong_zone_feedback():
		return
	var board_size: int = _board_view.get_puzzle_size()
	if not WrongZoneTracker.meets_cross_ratio(_board_view.get_board(), board_size):
		return
	var region_id: int = _wrong_zone_tracker.pick_highlight_target()
	if region_id < 0:
		return
	_wrong_zone_tracker.mark_hinted(region_id)
	_board_view.show_region_highlight(region_id)

	_on_wrong_zone_state_changed()
	if not OS.has_feature("rel"):
		print(
			(
				"[wrong_zone] 高亮色区%d 叉率=%.2f group=%d"
				% [
					region_id,
					WrongZoneTracker.cross_ratio(_board_view.get_board(), board_size),
					int(ABTestManager.wrong_zone_fdb.value())
				]
			)
		)


func _se_reserved_steps_on_other_fingers() -> int:
	if _active_slot == null:
		return 0
	if not ABTestManager.multi_touch.is_multi_touch_enabled():
		return 0
	var reserved: int = 0
	var slots: Array = _touch_slots.values()
	for slot: BoardTouchSlot in slots:
		if slot.recognizer == null:
			continue
		var is_own_slot: bool = slot == _active_slot

		if is_own_slot and not _dt_cross_landing_this_place:
			continue

		if (
			not is_own_slot
			and slot.is_owned()
			and slot.recognizer.is_window_from_latest_drag_start()
		):
			continue
		var pending: Vector2i = slot.recognizer.get_pending_tap_cell()
		if pending.x < 0:
			continue
		if not _se_window_may_become_cat(pending.x, pending.y):
			continue
		reserved += 1
	return reserved


func _se_window_may_become_cat(row: int, col: int) -> bool:
	if not _solution_has_cat(row, col):
		return false
	if _board_view != null and _board_view.get_cell_state(row, col) == CellState.CAT:
		return false
	return true


func _consumed_step_for_placed_cat(source: int) -> int:
	var is_pending_step_source: bool = (
		_se_step_pending_this_place
		or source == BoardView.ChangeSource.LOCATE
		or source == BoardView.ChangeSource.HINT
	)
	return (
		Tracker.get_stat("step_used")
		+ (1 if is_pending_step_source else 0)
		- _se_reserved_steps_on_other_fingers()
	)


func _on_board_cell_state_changed_for_se(r: int, c: int, state: int, source: int = 0) -> void:
	if state != CellState.CAT:
		return
	if source == BoardView.ChangeSource.PREFILL or source == BoardView.ChangeSource.RESTORE:
		return
	_se_count += 1

	var consumed_step: int = _consumed_step_for_placed_cat(source)
	var se_step_delta: int = (
		_se_amortized_step if _se_amortized_step >= 0 else consumed_step - _se_last_step
	)

	if _se_last_step < 0:
		se_step_delta = 0
	_se_last_step = consumed_step
	if _combo_feedback_view != null:
		_combo_feedback_view.refresh_display_visibility()

	var gain: int = ABTestManager.score_encourage.calc_gain(_se_count)

	var tier_bonus: int = ABTestManager.score_encourage.calc_step_tier_bonus(
		_level_config.get("size", 0), se_step_delta
	)
	var total_gain: int = gain + tier_bonus
	if ABTestManager.score_encourage.is_step_tier_group():
		print(
			(
				"[SE_TIER] cat(%d,%d) sz=%d step=%d tier=%s bonus=%d base=%d combo=%d gain=%d total=%d"
				% [
					r,
					c,
					int(_level_config.get("size", 0)),
					se_step_delta,
					ScoreEncourageConfig.tier_name(
						ScoreEncourageConfig.tier_of(_level_config.get("size", 0), se_step_delta)
					),
					tier_bonus,
					gain,
					_se_count,
					total_gain,
					_score_model.score + total_gain
				]
			)
		)

	_score_model.add_score(total_gain)

	var cell_global_pos: Vector2 = _board_view.get_cell_global_center(r, c)
	if _combo_feedback_view != null:
		var params: Dictionary = {
			"gain": total_gain,
			"like_hand_hw": _predict_like_hand_hw(r, c, source),
		}
		var _score_bubble: Control = _combo_feedback_view.show_se_bubble(cell_global_pos, params)

		var fly_delay: float = _combo_feedback_view.get_se_fly_delay()

		_se_last_fly_launch_ms = Time.get_ticks_msec() + int(maxf(0.0, fly_delay) * 1000.0)
		if fly_delay > 0.0:
			var _fly_gain: int = total_gain
			var _fly_score: int = _score_model.score
			var _fly_token: int = _se_fly_token

			var _from_pos: Vector2 = (
				_score_bubble.global_position + _score_bubble.size * 0.5
				if is_instance_valid(_score_bubble)
				else cell_global_pos
			)
			get_tree().create_timer(fly_delay).timeout.connect(
				func() -> void:
					if _fly_token != _se_fly_token:
						return
					if is_instance_valid(_combo_feedback_view):
						_combo_feedback_view.play_se_fly_effect(_from_pos, _fly_gain, _fly_score),
				CONNECT_ONE_SHOT
			)
		else:
			_combo_feedback_view.play_se_fly_effect(cell_global_pos, total_gain, _score_model.score)


func await_se_fly_settled() -> void:
	if _se_last_fly_launch_ms <= 0:
		return
	var remaining_ms: int = _se_last_fly_launch_ms - Time.get_ticks_msec()
	_se_last_fly_launch_ms = 0
	if remaining_ms > 0:
		await get_tree().create_timer(float(remaining_ms) / 1000.0).timeout


const AUTO_CROSS_SCORE_GAIN: int = 10

const AUTO_CROSS_BANNER_BONUS: int = 100

const AUTO_CROSS_BONUS_ROLL_SEC: float = 0.3

const AUTO_CROSS_DIAG_INTERVAL_SEC: float = AUTO_MARK_DIAG_INTERVAL_SEC * 0.5

var _auto_x_banner_shown: bool = false

var _win_encourage_snapshot: Dictionary = {}


func _play_auto_cross_bonus_sequence() -> void:
	_auto_x_banner_shown = false

	var by_win_encourage: bool
	if _win_encourage_snapshot.is_empty():
		by_win_encourage = ABTestManager.win_encourage.should_show_win_encourage(
			is_perfect_win(), is_full_hp_win()
		)
	else:
		by_win_encourage = ABTestManager.win_encourage.should_show_win_encourage(
			bool(_win_encourage_snapshot["perfect"]), bool(_win_encourage_snapshot["full_hp"])
		)
		_win_encourage_snapshot = {}
	var by_auto_x_fill: bool = ABTestManager.auto_x_fill_mode.is_enabled()
	if not by_win_encourage and not by_auto_x_fill:
		return

	if _draft_used_this_level and not by_win_encourage:
		return
	if _combo_feedback_view == null:
		return
	var sz: int = _level_config.get("size", 0)
	if sz <= 0:
		return

	await get_tree().create_timer(0.95).timeout

	var ring := func(v: Vector2i) -> int: return v.y + (sz - 1 - v.x)
	var mark_cells: Array[Vector2i] = []
	var player_cross_count: int = 0
	for r in range(sz):
		for c in range(sz):
			var st: int = _board_view.get_cell_state(r, c)
			if CellState.is_blank(st):
				mark_cells.append(Vector2i(r, c))
			elif CellState.is_cross(st):
				player_cross_count += 1

	if mark_cells.is_empty() and not by_win_encourage:
		return
	mark_cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return ring.call(a) < ring.call(b)
	)

	var diag_ring_count: int = 1
	for k in range(1, mark_cells.size()):
		if ring.call(mark_cells[k]) != ring.call(mark_cells[k - 1]):
			diag_ring_count += 1
	var roll_duration: float = float(diag_ring_count) * AUTO_CROSS_DIAG_INTERVAL_SEC
	var base_gain: int = mark_cells.size() * AUTO_CROSS_SCORE_GAIN

	_auto_complete_token += 1
	var token: int = _auto_complete_token

	if by_win_encourage or player_cross_count == 0:
		_auto_x_banner_shown = true
		var title_key: String = "WIN_PERFECT_WIN" if by_win_encourage else "WIN_X_FREE_BONUS"
		await _settle_auto_cross_no_mark(
			mark_cells, ring, base_gain, roll_duration, token, title_key
		)
	else:
		_combo_feedback_view.show_encourage_for_combo(_score_model.combo + 1)
		await _settle_auto_cross_with_mark(mark_cells, ring, base_gain, roll_duration, token)


func _settle_auto_cross_no_mark(
	mark_cells: Array[Vector2i],
	ring: Callable,
	base_gain: int,
	roll_duration: float,
	token: int,
	title_key: String = "WIN_X_FREE_BONUS"
) -> void:
	_combo_feedback_view.prepare_auto_x_banner(title_key)
	var bubble: LevelFlowScore = _combo_feedback_view.spawn_auto_x_total_bubble(
		base_gain, roll_duration
	)
	if not await _run_auto_cross_marking(mark_cells, ring, roll_duration, token):
		return

	await _combo_feedback_view.play_auto_x_banner_appear(
		ComboFeedbackView.AUTO_X_BANNER_HOLD_AT_SEC
	)
	if token != _auto_complete_token:
		return

	var total_gain: int = base_gain + AUTO_CROSS_BANNER_BONUS
	await _combo_feedback_view.roll_auto_x_total_bubble(
		bubble, base_gain, total_gain, AUTO_CROSS_BONUS_ROLL_SEC
	)
	if token != _auto_complete_token:
		return

	_combo_feedback_view.resume_auto_x_banner_appear()
	await _combo_feedback_view.fly_auto_x_total_score(
		bubble, _make_auto_cross_on_arrive(total_gain), 0.0
	)


func _settle_auto_cross_with_mark(
	mark_cells: Array[Vector2i], ring: Callable, base_gain: int, roll_duration: float, token: int
) -> void:
	var bubble: LevelFlowScore = _combo_feedback_view.spawn_auto_x_total_bubble(
		base_gain, roll_duration
	)
	if not await _run_auto_cross_marking(mark_cells, ring, roll_duration, token):
		return
	await _combo_feedback_view.fly_auto_x_total_score(
		bubble, _make_auto_cross_on_arrive(base_gain), 0.2
	)


func _run_auto_cross_marking(
	mark_cells: Array[Vector2i], ring: Callable, roll_duration: float, token: int
) -> bool:
	var mark_one := func(cell: Vector2i) -> void:
		_board_view.set_cell_state(
			cell.x,
			cell.y,
			CellState.MARK,
			true,
			true,
			BoardView.ChangeSource.AUTO_COMPLETE,
			"AutoXFillMode"
		)

	SoundManager.play(SoundManager.Kind.AUTO_X_MARK)
	SoundManager.set_silent(true)
	if ABTestManager.auto_x_fill_mode.is_instant():
		for cell: Vector2i in mark_cells:
			mark_one.call(cell)
		await get_tree().create_timer(roll_duration).timeout
		if token != _auto_complete_token:
			SoundManager.set_silent(false)
			return false
	else:
		var cell_index: int = 0
		while cell_index < mark_cells.size():
			var cur_ring: int = ring.call(mark_cells[cell_index])
			while cell_index < mark_cells.size() and ring.call(mark_cells[cell_index]) == cur_ring:
				mark_one.call(mark_cells[cell_index])
				cell_index += 1
			await get_tree().create_timer(AUTO_CROSS_DIAG_INTERVAL_SEC).timeout
			if token != _auto_complete_token:
				SoundManager.set_silent(false)
				return false
	SoundManager.set_silent(false)
	return true


func _make_auto_cross_on_arrive(total_gain: int) -> Callable:
	return func() -> void:
		_score_model.add_score(total_gain)
		_combo_feedback_view.update_se_score(_score_model.score)


## 回收动画与提示、断开局内信号并取消输入；令牌失效使未结束的异步演出不能再更新旧界面。
func on_hide() -> void:
	_reset_tool_reward_ad_opportunities()

	if _board_view != null and is_instance_valid(_board_view):
		_board_view.release_cats_to_pool()
	_reset_game_barrages()
	_disconnect_combo_signal()
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_idle_time = 0.0
	_stop_wrong_zone_highlight()
	_wrong_zone_idle_sec = 0.0
	_cancel_mouse_tool_flow()

	_auto_complete_token += 1
	_auto_completing = false

	_missed_cross_token += 1

	_full_mark_defer_token += 1

	_cancel_misplace_conflict("on_hide")
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


func _mount_progress_bar() -> void:
	var cat_bar: bool = ABTestManager.normal_top_ui.is_cat_progress_bar()

	_cat_progress = get_node_or_null(_cat_progress_path()) as Control
	_hide_idle_progress_bars()

	if _board_outer_glow != null:
		if _cat_progress_uses_adjacent_bar() and _cat_progress != null:
			_board_outer_glow.set_top_tab(
				_cat_progress,
				CatProgressBar.ADJACENT_BG_SIDE_INSET,
				CatProgressBar.ADJACENT_BG_TOP_CORNER_RADIUS,
				CatProgressBar.ADJACENT_BG_FILLET_RADIUS,
				CatProgressBar.ADJACENT_BG_FILLET_BASELINE_Y
			)
		else:
			_board_outer_glow.set_top_tab(null)
	_apply_function_area_min_for_progress()
	if _progress_target != null:
		_progress_target.visible = not cat_bar
	_align_glow_to_progress(cat_bar)
	_apply_heart_bg_position_for_progress(cat_bar)

	_set_cat_progress_row_visible(cat_bar and not _cat_progress_uses_adjacent_bar())

	_cat_progress_region_order.clear()
	_cat_progress_rotate_start = -1
	if _cat_progress != null:
		_cat_progress.visible = cat_bar

		_cat_progress_total = -1
		if cat_bar:
			_cat_progress.set_colored_mode(ABTestManager.normal_top_ui.is_cat_progress_colored())

			_cat_progress.set_done_dot_mode(
				ABTestManager.normal_top_ui.is_cat_progress_show_done_color()
			)


func _cat_progress_path() -> String:
	if _cat_progress_uses_adjacent_bar():
		return _cat_progress_adjacent_path()
	return _cat_progress_default_path()


func _cat_progress_default_path() -> String:
	return "Root/VBoxContainer/CatHeartRow/CatProgressBar"


func _cat_progress_adjacent_path() -> String:
	return ""


func _cat_progress_adjacent_holder_path() -> String:
	return ""


func _cat_progress_uses_adjacent_bar() -> bool:
	return (
		ABTestManager.normal_top_ui.is_cat_progress_adjacent_board()
		and not _cat_progress_adjacent_path().is_empty()
	)


func _hide_idle_progress_bars() -> void:
	var adjacent_on: bool = _cat_progress_uses_adjacent_bar()

	if adjacent_on:
		var default_bar: Control = (
			get_node_or_null(NodePath(_cat_progress_default_path())) as Control
		)
		if default_bar != null:
			default_bar.visible = false

	var holder_path: String = _cat_progress_adjacent_holder_path()
	if not holder_path.is_empty():
		var holder: Control = get_node_or_null(NodePath(holder_path)) as Control
		if holder != null:
			holder.visible = adjacent_on

	if not adjacent_on:
		var adjacent_path: String = _cat_progress_adjacent_path()
		if not adjacent_path.is_empty():
			var adjacent_bar: Control = get_node_or_null(NodePath(adjacent_path)) as Control
			if adjacent_bar != null:
				adjacent_bar.visible = false


const _FUNCTION_AREA_MIN_H_ADJACENT: float = 0.0


func _apply_function_area_min_for_progress() -> void:
	var target: float = _function_area_min_h_for_adjacent_bar()
	if target < 0.0:
		return
	var area: Control = get_node_or_null("Root/VBoxContainer/FunctionArea") as Control
	if area == null:
		return
	if not area.has_meta("_fa_base_min_h"):
		area.set_meta("_fa_base_min_h", area.custom_minimum_size.y)
	area.custom_minimum_size.y = (
		target if _cat_progress_uses_adjacent_bar() else float(area.get_meta("_fa_base_min_h"))
	)


func _function_area_min_h_for_adjacent_bar() -> float:
	return _FUNCTION_AREA_MIN_H_ADJACENT


func _set_cat_progress_row_visible(_on: bool) -> void:
	pass


func _cat_progress_metrics(total: int) -> Dictionary:
	if _cat_progress_uses_adjacent_bar():
		return {
			"slot": Vector2(CatProgressBar.ADJACENT_SLOT, CatProgressBar.ADJACENT_SLOT),
			"pitch": CatProgressBar.ADJACENT_PITCH,
			"padding": CatProgressBar.ADJACENT_PADDING,
			"align": "anchor_center",
		}
	return _cat_progress_default_metrics(total)


func _cat_progress_default_metrics(total: int) -> Dictionary:
	var metrics: Dictionary = CatProgressBar.solve_metrics(
		total, CatProgressBar.DESIGN_MAX_BAR_WIDTH_MAIN
	)
	metrics["align"] = "group_center"
	return metrics


const CAT_PROGRESS_GROUP_GAP: float = 30.0


func _layout_cat_progress_bar(metrics: Dictionary) -> void:
	if _cat_progress == null:
		return

	if String(metrics.get("align", "center")) == "anchor_center":
		var half_width: float = _cat_progress.size.x * 0.5
		_cat_progress.offset_left = -half_width
		_cat_progress.offset_right = half_width
		return
	var bar_width: float = _cat_progress.size.x
	var parent: Control = _cat_progress.get_parent() as Control
	var row_width: float = parent.size.x if parent != null else 1080.0
	if String(metrics.get("align", "center")) == "group_center":
		var bars: Array[Control] = _life_bar_nodes()
		var fish_width: float = 0.0
		for bar: Control in bars:
			if bar.has_meta("_cp_base_l"):
				fish_width = float(bar.get_meta("_cp_base_r")) - float(bar.get_meta("_cp_base_l"))
				break
		var group_width: float = bar_width + CAT_PROGRESS_GROUP_GAP + fish_width
		var bar_left: float = (row_width - group_width) * 0.5
		_cat_progress.offset_left = bar_left
		_cat_progress.offset_right = bar_left + bar_width
		if fish_width > 0.0:
			var fish_left: float = bar_left + bar_width + CAT_PROGRESS_GROUP_GAP
			for bar: Control in bars:
				bar.offset_left = fish_left - row_width
				bar.offset_right = fish_left + fish_width - row_width
		return
	_cat_progress.offset_left = (row_width - bar_width) * 0.5
	_cat_progress.offset_right = _cat_progress.offset_left + bar_width


func _apply_cat_progress_colored(sz: int) -> void:
	if _cat_progress == null:
		return
	var snap: Dictionary = _build_cat_progress_snapshot(sz, true)

	if int(snap["total"]) != sz:
		return
	_cat_progress.set_tints(snap["tints"])
	_cat_progress.set_revealed(snap["revealed"])


func build_cat_progress_snapshot() -> Dictionary:
	var sz: int = int(_level_config.get("size", 0))
	var snap: Dictionary = _build_cat_progress_snapshot(
		sz, ABTestManager.normal_top_ui.is_cat_progress_colored()
	)

	if int(_puzzle.get("regions", []).size()) < sz:
		snap = _degraded_cat_progress_snapshot()
	if (
		int(snap["total"]) == sz
		and ABTestManager.normal_top_ui.is_cat_progress_compact()
		and _cat_progress != null
		and _cat_progress._compact
	):
		snap["compact_order"] = _cat_progress.compact_found_order()
	if int(snap["total"]) != sz:
		push_warning("build_cat_progress_snapshot: 棋盘数据异常(size=%d),失败页进度条降级为不展示" % sz)
	return snap


func _degraded_cat_progress_snapshot() -> Dictionary:
	var empty_flags: Array[bool] = []
	return {"total": 0, "tints": PackedColorArray(), "revealed": empty_flags}


func _build_cat_progress_snapshot(sz: int, with_tints: bool) -> Dictionary:
	var degraded: Dictionary = _degraded_cat_progress_snapshot()
	if _board_view == null or sz <= 0:
		return degraded
	if _cat_progress_region_order.size() != sz:
		_rebuild_cat_progress_region_order(sz)

	if _cat_progress_region_order.size() != sz:
		return degraded
	return CatProgressBar.build_snapshot(
		_cat_progress_region_order,
		_collect_regions_with_cat(sz),
		_board_view.get_region_color,
		with_tints
	)


func _setup_cat_progress_compact(sz: int, metrics: Dictionary) -> void:
	if _cat_progress == null or _board_view == null:
		return
	if _cat_progress_region_order.size() != sz:
		_rebuild_cat_progress_region_order(sz)
	if _cat_progress_region_order.size() != sz:
		return
	var tints: PackedColorArray = PackedColorArray()
	for i in sz:
		var region_tint: Color = _board_view.get_region_color(_cat_progress_region_order[i])
		region_tint.a = CatProgressSlot.COLORED_SILHOUETTE_ALPHA
		tints.append(region_tint)
	_cat_progress.setup_compact(sz, metrics["slot"], metrics["pitch"], metrics["padding"], tints)


func _apply_cat_progress_compact(sz: int) -> void:
	if _cat_progress == null or _board_view == null:
		return
	if _cat_progress_region_order.size() != sz:
		return
	var with_cat: Dictionary = _collect_regions_with_cat(sz)
	var flags: Array = []
	for i in sz:
		flags.append(with_cat.has(_cat_progress_region_order[i]))
	_cat_progress.update_compact(flags)


func _rebuild_cat_progress_region_order(sz: int) -> void:
	_cat_progress_region_order.clear()
	if _board_view == null or sz <= 0:
		return
	var idx: Array[int] = []
	for i in sz:
		idx.append(i)
	var bv: Node = _board_view
	idx.sort_custom(
		func(left: int, right: int) -> bool:
			return bv.get_region_color(left).h < bv.get_region_color(right).h
	)

	var rotate_start: int = (
		(_cat_progress_rotate_override % sz)
		if _cat_progress_rotate_override >= 0
		else (randi() % sz)
	)

	_cat_progress_rotate_start = rotate_start
	for i in sz:
		_cat_progress_region_order.append(idx[(i + rotate_start) % sz])


func _collect_regions_with_cat(sz: int) -> Dictionary:
	var out: Dictionary = {}
	var regions: Array = _puzzle.get("regions", [])

	if regions.size() < sz:
		return out
	for r in sz:
		var row: Array = regions[r]
		if row.size() < sz:
			continue
		for c in sz:
			if _board_view.get_cell_state(r, c) == CellState.CAT:
				out[int(row[c])] = true
	return out


const LEVEL_CONFIG_COSTUME_ID_KEY: String = "costume_id"


func in_game_costume_id() -> int:
	if not uses_in_game_costume():
		return CostumeCatalog.DEFAULT_COSTUME_ID
	var snapshot: int = int(_level_config.get(LEVEL_CONFIG_COSTUME_ID_KEY, 0))
	if CostumeCatalog.is_valid(snapshot):
		return snapshot
	return _entry_costume_id()


func uses_in_game_costume() -> bool:
	return ABTestManager.dc_costume.has_costume() or _companion_costume_override != 0


var _companion_costume_override: int = 0
const _COMPANION_SERVICE: GDScript = preload("res://scripts/module/home/home_companion_service.gd")


func _companion_game_end_fields(include_this_win: bool) -> Dictionary:
	var won_game_id: String = GameState.get_persisted_game_id("normal") if include_this_win else ""
	return _COMPANION_SERVICE.new().game_end_fields(won_game_id, _level_kind)


func refresh_companion_costume_override() -> void:
	_companion_costume_override = _COMPANION_SERVICE.new().in_game_costume_override()
	if _companion_costume_override != 0:
		return

	var equipped: int = ProfileService.get_costume_id()
	if CostumeCatalog.is_event(equipped):
		_companion_costume_override = equipped


func _entry_costume_id() -> int:
	if _companion_costume_override != 0:
		return _companion_costume_override
	if not ABTestManager.dc_costume.has_costume():
		return CostumeCatalog.DEFAULT_COSTUME_ID
	return ProfileService.get_costume_id()


func _apply_in_game_costume() -> void:
	var costume_id: int = _entry_costume_id()
	_level_config[LEVEL_CONFIG_COSTUME_ID_KEY] = costume_id
	if _board_view != null:
		_board_view.set_cat_costume(costume_id)


func _apply_target_costume_icon() -> void:
	if _target_costume_cat == null:
		return
	var use_costume: bool = uses_in_game_costume()
	if _target_cat_face_icon != null:
		_target_cat_face_icon.visible = not use_costume
	_target_costume_cat.visible = use_costume
	if not use_costume:
		return
	_layout_target_costume_cat()
	if _target_costume_cat.skeleton_data_res != CostumeSkin.SKELETON_RES:
		_target_costume_cat.skeleton_data_res = CostumeSkin.SKELETON_RES
		_target_costume_applied_id = -1
	var costume_id: int = in_game_costume_id()
	if _target_costume_applied_id == costume_id:
		return

	if _target_costume_cat.get_skeleton() == null:
		return
	CostumeSkin.apply(_target_costume_cat, costume_id)
	_freeze_target_costume_cat_idle()
	_target_costume_applied_id = costume_id


func _layout_target_costume_cat() -> void:
	if _target_cat_face_icon == null:
		return
	var icon_size: Vector2 = _target_cat_face_icon.size
	if icon_size.x <= 0.0 or icon_size.y <= 0.0:
		return
	var icon_center: Vector2 = _target_cat_face_icon.position + icon_size * 0.5
	_target_costume_cat.position = Vector2(
		icon_center.x,
		_target_cat_face_icon.position.y + icon_size.y * CatProgressSlot.COSTUME_CAT_ORIGIN_Y_RATIO
	)
	var spine_scale: float = (
		icon_size.x / CatProgressSlot.COSTUME_CAT_REF_BOX_PX * CatProgressSlot.COSTUME_CAT_REF_SCALE
	)
	_target_costume_cat.scale = Vector2.ONE * spine_scale


func _freeze_target_costume_cat_idle() -> void:
	var data: SpineSkeletonDataResource = _target_costume_cat.get_skeleton_data_res()
	if data == null or data.find_animation("idle") == null:
		return
	var state: SpineAnimationState = _target_costume_cat.get_animation_state()
	if state == null:
		return
	state.set_animation("idle", false, 0)
	state.set_time_scale(0.0)


func _life_bar_nodes() -> Array[Control]:
	var out: Array[Control] = []
	if _life_bar_progress != null:
		out.append(_life_bar_progress)
	return out


func _apply_heart_bg_position_for_progress(cat_bar: bool = false) -> void:
	is_force_pass_scroll_events()

	var adjacent_board: bool = ABTestManager.normal_top_ui.is_cat_progress_adjacent_board()
	var defer_to_layout: bool = cat_bar and not adjacent_board
	var bars: Array[Control] = _life_bar_nodes()
	for hb: Control in bars:
		if not hb.has_meta("_cp_base_l"):
			hb.set_meta("_cp_base_l", hb.offset_left)
			hb.set_meta("_cp_base_r", hb.offset_right)
		if defer_to_layout:
			continue
		var base_l: float = float(hb.get_meta("_cp_base_l"))
		var base_r: float = float(hb.get_meta("_cp_base_r"))
		if adjacent_board:
			var row_w: float = _cat_heart_row_width()
			var own_w: float = base_r - base_l
			hb.offset_left = -(row_w + own_w) * 0.5
			hb.offset_right = hb.offset_left + own_w
			continue
		hb.offset_left = base_l
		hb.offset_right = base_r


func _cat_heart_row_width() -> float:
	var row: Control = get_node_or_null("Root/VBoxContainer/CatHeartRow") as Control
	if row == null or row.size.x <= 0.0:
		return 1080.0
	return row.size.x


func _align_glow_to_progress(cat_bar: bool = false) -> void:
	var glow_control: Control = (
		get_node_or_null("Root/VBoxContainer/CatHeartRow/Control") as Control
	)
	if glow_control == null:
		return

	glow_control.visible = not cat_bar
	if cat_bar:
		return
	var glow_rect: NinePatchRect = glow_control.get_node_or_null("NinePatchRect") as NinePatchRect
	if glow_rect == null:
		return
	var ref: Control = _progress_target
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


## 进度条模式下的生命背景位置微调
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


## 断开自己接在广告激励 / 关闭信号上的回调，避免页面隐藏后仍被回调
func _disconnect_self_reward_callbacks() -> void:
	for c: Dictionary in UniKitManager.ad_rewarded.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_rewarded.disconnect(cb)
	for c: Dictionary in UniKitManager.ad_closed.get_connections():
		var cb: Callable = c.callable
		if cb.get_object() == self:
			UniKitManager.ad_closed.disconnect(cb)


func _resolve_region_color_names() -> Array[String]:
	if ABTestManager.region_color.is_new_cell_only_palette():
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


func _resolve_region_color_hex_codes() -> Array[String]:
	if ABTestManager.region_color.is_new_cell_only_palette():
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


func _color_name_bbcode(region_idx: int) -> String:
	var cell_color: Color = _board_view.get_region_color(region_idx)
	var hex: String
	var name: String
	var override_name: String = _hint_color_name_override(cell_color)
	if not override_name.is_empty():
		var darkened: Color = cell_color.darkened(0.28)
		hex = (
			"#%02x%02x%02x" % [int(darkened.r * 255), int(darkened.g * 255), int(darkened.b * 255)]
		)
		name = override_name
	elif ABTestManager.region_color.value() == RegionColorConfig.VALUE_CONTROL:
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


func _hint_color_name_override(_color: Color) -> String:
	return ""


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
		[Color("#d3d551"), tr("COLOR_OLIVE_YELLOW")],
		[Color("#d86c90"), tr("COLOR_ROSE")],
		[Color("#767ae4"), tr("COLOR_PURPLE")],
		[Color("#e57ee0"), tr("COLOR_MAGENTA")],
		[Color("#e76f58"), tr("COLOR_ORANGE")],
		[Color("#dccf95"), tr("COLOR_YELLOW")],
		[Color("#7284b3"), tr("COLOR_DARK_BLUE")],
		[Color("#c0d1dc"), tr("COLOR_LIGHT_BLUE")],
		[Color("#399295"), tr("COLOR_TEAL")],
		[Color("#459a5e"), tr("COLOR_DARK_GREEN")],
		[Color("#99dbb1"), tr("COLOR_GREEN")],
		[Color("#a67b63"), tr("COLOR_BROWN")],
		[Color("#dc9e7c"), tr("COLOR_TAN")],
		[Color("#9d9041"), tr("COLOR_OLIVE_YELLOW")],
		[Color("#97cf7e"), tr("COLOR_GREEN")],
		[Color("#618f74"), tr("COLOR_DARK_GREEN")],
		[Color("#60d8d3"), tr("COLOR_TEAL")],
		[Color("#76a9cc"), tr("COLOR_SKY_BLUE")],
		[Color("#6881d0"), tr("COLOR_DARK_BLUE")],
		[Color("#aa68e5"), tr("COLOR_PURPLE")],
		[Color("#d899e4"), tr("COLOR_VIOLET")],
		[Color("#e55ca6"), tr("COLOR_MAGENTA")],
		[Color("#bb7e93"), tr("COLOR_ROSE")],
		[Color("#dc5b6a"), tr("COLOR_RED")],
	]

	if ABTestManager.region_color.is_palette_v13():
		(
			known
			. append_array(
				[
					[Color("#aed994"), tr("COLOR_LIGHT_GREEN")],
					[Color("#fab4d0"), tr("COLOR_LIGHT_PINK")],
					[Color("#e4bb49"), tr("COLOR_LIGHT_YELLOW")],
					[Color("#a7bfd7"), tr("COLOR_TEAL")],
					[Color("#6bbce7"), tr("COLOR_BLUE")],
					[Color("#d57374"), tr("COLOR_RED")],
					[Color("#ad6f48"), tr("COLOR_BROWN")],
					[Color("#5b75b2"), tr("COLOR_DARK_BLUE")],
					[Color("#9778d6"), tr("COLOR_PURPLE")],
					[Color("#48b5b2"), tr("COLOR_TURQUOISE")],
					[Color("#ffaa6d"), tr("COLOR_ORANGE")],
					[Color("#eb85b7"), tr("COLOR_PINK")],
				]
			)
		)
	elif ABTestManager.region_color.is_palette_v14():
		(
			known
			. append_array(
				[
					[Color("#f9d96a"), tr("COLOR_LIGHT_YELLOW")],
					[Color("#faaf5c"), tr("COLOR_ORANGE")],
					[Color("#d47363"), tr("COLOR_RED")],
					[Color("#ee92a7"), tr("COLOR_PINK")],
					[Color("#f9b0f7"), tr("COLOR_LIGHT_PINK")],
					[Color("#80db8c"), tr("COLOR_GREEN")],
					[Color("#c7c94a"), tr("COLOR_LIGHT_GREEN")],
					[Color("#46b4a9"), tr("COLOR_TURQUOISE")],
					[Color("#81d8e9"), tr("COLOR_SKY_BLUE")],
					[Color("#77afde"), tr("COLOR_BLUE")],
					[Color("#a590dd"), tr("COLOR_PURPLE")],
					[Color("#6862a8"), tr("COLOR_DARK_PURPLE")],
				]
			)
		)
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
			if str(hint.get("description", "")) == "":
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
## 在连锁详情层上画一个带序号的圆点标记
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


## 玩家点「查看详情」：把连锁的反证单元写进说明并展开详情层
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
		all_steps.append({"cell": cc, "label": "x", "color": Color("#dc2626")})

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
					or not is_instance_valid(detail_layer)
					or not detail_layer.is_inside_tree()
				):
					return
				var temp: CellView = _spawn_temp_cell_in(detail_layer, cv, s, bpos)
				if lbl == "x":
					temp.play_r2_preview()
				else:
					temp.play_prompt_cat()
		)
		step_delay += 0.05


func _isolate_onefish_main_state() -> bool:
	return (
		LevelKind.is_golden_fish(_level_kind) and ABTestManager.normal_level.is_onefish_state_fix()
	)


func _cmd_lives(args: Array[String]) -> void:
	var val: int = int(args[0]) if args.size() > 0 else _life_cap
	_lives = clampi(val, 0, _life_cap)
	_life_bar.refresh(_lives)
	if _lives <= 0:
		_on_game_fail()


func _compute_next_hint() -> Dictionary:
	var sz: int = _level_config.get("size", 4)
	var board: Array = _board_view.get_cell_state_folded_board()
	var regs: Array = _puzzle["regions"]

	var hint: Dictionary = HintEngine.find_mark_hint(
		board, sz, regs, ABTestManager.hint_func.has_color_exclude()
	)
	if not hint["found"]:
		var sol: Array = _puzzle.get("solution", [])
		for r in range(sz):
			for c in range(sz):
				if (sol[r] as Array)[c] and _board_view.get_cell_state(r, c) == CellState.MARK:
					var wrong_mark_cells: Array[Vector2i] = [Vector2i(r, c)]
					hint = {
						"found": true,
						"strategy": "",
						"cell": Vector2i(r, c),
						"unit_cells": wrong_mark_cells,
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
		hint = HintEngine.find_r3_r4_hint(
			board, sz, regs, ABTestManager.hint_func.has_reverse_set_locking()
		)
	if not hint["found"]:
		hint = HintEngine.find_chain_hint(board, sz, regs)
	return hint


func _hint_targets_marked_cell(hint: Dictionary) -> bool:
	var hint_cell: Vector2i = hint.get("cell", Vector2i(-1, -1))
	if hint_cell.x < 0:
		return false
	var hint_strategy: String = hint.get("strategy", "")
	if hint_strategy in ["R1_mark", "R2", "R3", "R4", "R3b", "R4b"]:
		return false
	return _board_view.get_cell_state(hint_cell.x, hint_cell.y) == CellState.MARK


func _on_hint_btn_pressed() -> void:
	if _entry_anim_playing or _tool_btns_locked or _hint_cooldown or _mouse_tool_busy:
		return
	ABTestManager.dye_at_hint_use()
	Tracker.track_btn_click(Tracker.Btn.HINT, self)
	_reset_idle_hint()

	if _draft_mode:
		return
	if _is_complete or _wrong_guess_pending:
		return

	if not _is_free_kind(ToolKind.HINT) and GameState.get_tool_count("hint") <= 0:
		_request_reward_for_tool(ToolKind.HINT)
		return
	Tracker.inc_stat("hint_used")
	GameState.inc_game_total_stat(_game_type(), "hint_used_total")
	var sz: int = _level_config.get("size", 4)
	var hint: Dictionary = _compute_next_hint()
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
	var consumed: bool = _consume_tool(ToolKind.HINT)
	SoundManager.play(SoundManager.Kind.USE_HINT)
	GameState.mark_current_level_dirty()
	if consumed and not _isolate_onefish_main_state():
		GameState.mark_dda_tool_or_revive_used()
		GameState.inc_today_tool_consumed()

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

	if _hint_targets_marked_cell(hint):
		hint["description"] = tr("HINT_WRONG_MARK")
		hint["wrong_mark"] = true
	_hint_data = hint
	_record_hint_show_solution_step(hint)

	_destroy_banner()
	_hint_overlay.show_hint(hint)
	_build_hint_highlights(hint)


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
					_mark_step_dirty()
					_board_view.set_cell_state(
						row, c, CellState.MARK, true, true, BoardView.ChangeSource.HINT
					)
		"r2a_col":
			for r in range(sz):
				if regs[r][col] != reg and CellState.is_blank(_board_view.get_cell_state(r, col)):
					_mark_step_dirty()
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
						_mark_step_dirty()
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
						_mark_step_dirty()
						_board_view.set_cell_state(
							r, c, CellState.MARK, true, true, BoardView.ChangeSource.HINT
						)
	_validate_board()
	_update_remaining()


func _on_hint_applied() -> void:
	Tracker.track_btn_click(Tracker.Btn.HINT_APPLY, self)
	Tracker.inc_stat("hint_apply_used")
	_record_hint_apply_solution_step(_hint_data)
	var strategy: String = _hint_data.get("strategy", "R1")
	if strategy == "R1_mark":
		for cell_v in _hint_data.get("unit_cells", []) as Array:
			var cell: Vector2i = cell_v as Vector2i
			if CellState.is_blank(_board_view.get_cell_state(cell.x, cell.y)):
				_mark_step_dirty()
				_board_view.set_cell_state(
					cell.x, cell.y, CellState.MARK, true, true, BoardView.ChangeSource.HINT
				)
		_validate_board()
		_update_remaining()
	elif strategy == "R3" or strategy == "R4":
		_apply_r3_r4_hint()
	elif strategy == "R3b" or strategy == "R4b":
		_apply_r3_r4b_hint()
	elif strategy == "R2":
		_apply_r2_hint()
	elif strategy == "R4_chain" or strategy == "R5_chain":
		var cell: Vector2i = _hint_data.get("cell", Vector2i(-1, -1))
		if cell.x >= 0:
			_mark_step_dirty()
			_board_view.set_cell_state(
				cell.x, cell.y, CellState.MARK, true, true, BoardView.ChangeSource.HINT
			)
			_validate_board()
			_update_remaining()
	else:
		var cell: Vector2i = _hint_data.get("cell", Vector2i(-1, -1))
		if cell.x >= 0:
			if _hint_data.get("wrong_mark", false):
				_mark_step_dirty()
				_board_view.set_cell_state(
					cell.x, cell.y, CellState.EMPTY, true, true, BoardView.ChangeSource.HINT
				)
				VibrateManager.play_at(VibrateManager.Pos.HINT_CLEAR)
			else:
				_mark_step_dirty()
				_board_view.set_cell_state(
					cell.x,
					cell.y,
					CellState.CAT,
					true,
					true,
					BoardView.ChangeSource.HINT,
					"",
					false,
					_found_cat_spine_anim(BoardView.ChangeSource.HINT)
				)
				_record_correct_cat(
					_decide_like_hand_for_correct_cat(LikeHandTrigger.HINT_R1_APPLY)
				)
			_update_remaining()
			_validate_board()
	_clear_step_dirty()
	_count_board_step("hint_apply")
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
## 拼埋点用的题目 ID：尺寸_题库_策略_序号_变换
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


func _get_diffi() -> int:
	if LevelKind.is_color_challenge(_level_kind):
		return 0
	var lv: int = GameState.get_current_level()
	if LevelSelector.is_super_hard_level(lv):
		return 2
	return 1 if LevelSelector.is_hard_level(lv) else 0


func _count_correct_crosses() -> int:
	var sol: Array = _puzzle.get("solution", [])
	if sol.is_empty():
		return 0
	var sz: int = _level_config.get("size", 0)
	var n: int = 0
	for r in range(sz):
		for c in range(sz):
			if CellState.is_cross(_board_view.get_cell_state(r, c)) and not bool(sol[r][c]):
				n += 1
	return n


func _count_false_crosses() -> int:
	var sol: Array = _puzzle.get("solution", [])
	if sol.is_empty():
		return 0
	var sz: int = _level_config.get("size", 0)
	var n: int = 0
	for r in range(sz):
		for c in range(sz):
			if CellState.is_cross(_board_view.get_cell_state(r, c)) and bool(sol[r][c]):
				n += 1
	return n


## 策略面板的 5 行静态配置：徽标、名称 key、描述 key、配色
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


## 取中文翻译；取不到就退回 tr()
func _tr_zh(key: String) -> String:
	var t: Translation = TranslationServer.get_translation_object("zh_CN")
	if t != null:
		var msg: String = t.get_message(key)
		if msg != "":
			return msg
	return tr(key)


## 懒构建策略分析浮层（标题 + 关闭按钮 + 行容器）
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


## 打开策略分析浮层并填充内容
func _on_strategy_btn_pressed() -> void:
	if _strategy_overlay == null:
		return
	_populate_strategy_vbox()
	if _strategy_bg != null:
		_strategy_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_strategy_overlay.visible = true


## 关闭策略分析浮层
func _on_strategy_close() -> void:
	if _strategy_bg != null:
		_strategy_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strategy_overlay.visible = false


func _populate_strategy_vbox() -> void:
	var children: Array[Node] = _strategy_vbox.get_children()
	for child in children:
		child.queue_free()
	var regions: Array = _puzzle.get("regions", [])
	var solution: Array = _puzzle.get("solution", [])
	var analysis: Dictionary = HintEngine.compute_puzzle_difficulty(
		regions.size(), regions, solution
	)
	var analysis_ok: bool = bool(analysis.get("ok", false))
	var difficulty_label := Label.new()
	difficulty_label.text = "整题难度 R%d" % int(analysis["r"]) if analysis_ok else "整题难度：无法完成推理"
	difficulty_label.add_theme_font_size_override("font_size", 30)
	difficulty_label.add_theme_color_override("font_color", Color("#333333"))
	difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strategy_vbox.add_child(difficulty_label)
	if analysis_ok:
		for info: Dictionary in _RANK_STRATEGY_INFO:
			var steps: int = int(analysis.get("r%d" % int(info["rank"]), 0))
			_strategy_vbox.add_child(_make_strategy_row(info, steps))

	var bank_source: String = _level_config.get("bank_source", "")
	if not bank_source.is_empty():
		var cur_strategy: int = GameState.get_current_strategy()
		var cur_rank: int = LevelData.strategy_to_rank(cur_strategy)
		var cur_tier: String = LevelData.strategy_to_tier(cur_strategy)
		var tier_str: String = "H" if cur_tier == "H" else "N"
		var strategy_lbl := Label.new()
		strategy_lbl.text = "玩家档位  strategy=%d  R%d%s" % [cur_strategy, cur_rank, tier_str]
		strategy_lbl.add_theme_font_size_override("font_size", 28)
		strategy_lbl.add_theme_color_override("font_color", Color("#888888"))
		strategy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_strategy_vbox.add_child(strategy_lbl)

	if not bank_source.is_empty():
		var src: String = _level_config.get("bank_source", "")
		var idx: int = _level_config.get("bank_idx", 0)
		var board_size: int = regions.size()
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
		src_lbl.text = "%s  %dx%d  #%d" % [src_text, board_size, board_size, idx]
		src_lbl.add_theme_font_size_override("font_size", 28)
		src_lbl.add_theme_color_override("font_color", Color("#888888"))
		src_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_strategy_vbox.add_child(src_lbl)


## 造一行策略：徽标、名称、说明与该策略用到的步数
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
## 返回所有答案猫的屏幕坐标，供调试 HTTP 接口截图定位
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
