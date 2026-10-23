## 普通关页面：连接 GameState 的题目与进度，处理开局、难度显示、排行反馈和通关流转。
class_name GamePage
extends BaseGamePage

enum EntryMode { NORMAL, BANK, BANK_SP, DEBUG_CONFIG, DEBUG_PREBUILT } # 入口模式：普通关卡 / 题库 / SP 题库 / 调试配置 / 调试预置
var _elo_v2_formal_main: bool = false

signal bubble_tutorial_finished

# ================= 成员变量 =================
# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _level_label: Label = $Root/VBoxContainer/Header/LevelLabel # 顶部关卡标题

var _level_value_num: int = -1
@onready var _coin_label: Label = $Root/VBoxContainer/Header/CoinLabel # 顶部金币数字（本页只显示，不结算）
@onready var _prev_btn: Button = $Root/VBoxContainer/Header/PrevBtn # 题库内上一题（题量 > 1 才显示）
@onready var _next_btn: Button = $Root/VBoxContainer/Header/NextBtn # 题库内下一题

@onready var _return_bank_btn: Button = $Root/ReturnBankBtn
@onready var _normal_toast: GameNormalToast = $Root/NormalToast # 普通难度开场提示条
@onready var _hard_toast: GameHardToast = $Root/HardToast # 困难难度开场提示条

@onready var _golden_fish_toast: GoldenFishToast = $Root/GoldenFishToast

@onready var _golden_fish_tutorial_card: GoldenFishTutorialCard = $Root/GoldenFishTutorialCard

@onready var _golden_fish_fly: Control = $Root/GlodenFishFly

const _GF_FLY_ANIM: StringName = &"GlodenFishFly"

const _GF_FLY_TOTAL_SEC: float = 0.4
const _GF_FLY_BUMP_SEC: float = 0.1
const _GF_FLY_BUMP_X: float = 45.0

var _gf_home_pos: Vector2 = Vector2.ZERO
var _gf_home_cached: bool = false
var _gf_fly_tw_x: Tween = null
var _gf_fly_tw_y: Tween = null

# ---- 开场提示条与入口按钮锁 ----
var _active_toast: BaseGameToast = null # 当前挂着的提示条，没有则为 null

@onready var _back_setting_header: BackAndSettingHeader = $Root/VBoxContainer/Header

var _entry_btn_lock_seq: int = 0 # 入口按钮锁序号：解锁回调靠它判断自己是否已过期

# ---- 子节点引用：生命预警与挂机引导 ----
@onready var _anim_tips: AnimationPlayer = $AnimTips # 生命预警动画播放器
@onready var _warn_tips: Control = $Root/VBoxContainer/CatHeartRow/Tips # 预警气泡根节点
@onready var _warn_bubble: Control = $Root/VBoxContainer/CatHeartRow/Tips/Bubble # 预警气泡
@onready var _warn_tail: Sprite2D = $Root/VBoxContainer/CatHeartRow/Tips/Bubble/Tail # 指向红心的小尾巴

@onready var _warn_label: Label = $Root/VBoxContainer/CatHeartRow/Tips/Bubble/Label
@onready var _warn_overlay: ColorRect = $Root/Overlay # 预警期间的全屏遮罩

@onready var _warn_mask: Sprite2D = $Root/VBoxContainer/CatHeartRow/HeartBg/EtMask007 # 被预警红心的遮罩贴图

@onready var _life_bar_mul: HealthBarBase = $Root/VBoxContainer/CatHeartRow/HeartBgMul

const RANK_COLLECTOR_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/rank_collector_cell.tscn"
)
@onready var _rank_collector_anchor: Control = $Root/VBoxContainer/BoardContainer/RankCollectorAnchor
var _rank_collector: RankCollectorCell = null

@onready var _board_adapt_holder: Control = $Root/VBoxContainer/BoardAdaptHolder

@onready var _rank_collector_anchor_base_top: float = _rank_collector_anchor.offset_top
@onready var _rank_collector_anchor_base_bottom: float = _rank_collector_anchor.offset_bottom

const _RANK_COLLECTOR_MIN_BOARD_GAP: float = 0.0

const _RANK_FLIGHT_TRAIL_SCENE: PackedScene = preload("res://assets/prefab/effect_score_trail.tscn")

const _RANK_FLIGHT_TRAIL_Z: int = 2
const _CENTER_RELAY_FISH_FLY_COLLECTOR_Z: int = 4

const _GF_FLIGHT_TRAIL_Z: int = 4
const _RANK_COLLECTOR_ICON_Z: int = 5

var _rank_flight_trails: Array = []

var _rank_win_presentation_active: bool = false


func _finish_rank_win_presentation(aborted: bool = false) -> void:
	if aborted and _rank_collector != null and is_instance_valid(_rank_collector):
		_rank_collector.cancel_deferred_win_reveal()
	if not _rank_win_presentation_active:
		return
	_rank_win_presentation_active = false
	RankActivityManager.end_rank_win_presentation(aborted)


@export_group("排行榜局内飞入")

@export var rank_fly_start: float = 1.25

@export var rank_fly_interval: float = 0.05

@export var rank_fly_dur: float = 0.5

@export var rank_fly_trail_fade: float = 0.3

@export var rank_fish_fly_start: float = 1.1

@export var rank_fish_fly_interval: float = 0.083

@export var rank_fish_fly_dur: float = 0.4

@export var golden_fish_split_collect_at: float = 1.35

const _GF_SPLIT_FADE_START: Array[float] = [
	1.3666667,
	1.7,
	1.4,
	1.6333336,
	1.5333333,
]

@export var rank_fish_collect_lead: float = 0.2

const _RANK_FISH_BEZIER_X: Vector4 = Vector4(0.125, 0.0, 0.875, 1.0)
const _RANK_FISH_BEZIER_Y: Vector4 = Vector4(0.0, 0.141343, 0.7, 1.0)

const _RANK_FISH_DIP_BEZIER_Y: Vector4 = Vector4(0.25, -0.3, 1.0, 1.0)

const _FISH_FLY_SCENE: PackedScene = preload("res://assets/prefab/fish_fly.tscn")

const _CC_PATTERN_BTN_SCENE: PackedScene = preload(
	"res://scripts/module/color_challenge/ui/pattern_toggle_btn.tscn"
)

const _CC_TOAST_SCENE_PATH: String = "res://scripts/module/color_challenge/ui/color_challenge_toast.tscn"

@export var rank_center_relay_to_center_dur: float = 0.4

@export var rank_center_relay_bump_x: float = 45.0
@export var rank_center_relay_bump_sec: float = 0.1

@export var rank_center_relay_hold: float = 0.5

@export var rank_center_relay_spacing: float = 150.0

@export var rank_center_relay_triangle_radius: float = 75.0

var _center_relay_fish_nodes: Array = []

var _center_relay_fish_count: int = 0

# ---- 运行时状态 ----
var _nav_index: int = 0 # 题库内当前题号（从 1 开始）
var _nav_total: int = 0 # 题库总题数，0 表示不可翻页
var _is_hard_level: bool = false # 当前关是否 Hard

var _is_super_hard_level: bool = false
var _revive_count: int = 0 # 本局复活次数
var _restart_count: int = 0 # 本局重开次数

var _pre_type: String = PreCatDecider.PRE_TYPE_NONE

var _pre_cat_positions_at_start: String = "[]"

var _pre_cat_position: Vector2i = Vector2i(-1, -1)

var _pre_cat_pend_snapshot: Dictionary = {}

var _golden_fish_pre_cat: GoldenFishPreCat = GoldenFishPreCat.new()

var _pre_cat_fx: PreCatFxDirector = null

static var debug_force_pre_cat: bool = false
var _coins: int = 40 # 顶部显示的金币数（本文件内不增减）

var _toast_first_try_hint: bool = false # 开场提示条是否按「首次挑战」文案

var _entry_handlers: Dictionary = {} # 入口模式 → 初始化函数 的派发表

# ---- 残局快照落盘（防抖） ----
var _endgame_persist_timer: Timer = null # 残局快照防抖定时器
const ENDGAME_PERSIST_DEBOUNCE_SEC: float = 0.5 # 防抖窗口：0.5 秒内的多次改动合并成一次写档

var _is_endgame_restore_session: bool = false # 本次 on_show 是否来自残局快照复原

var _is_direct_open_session: bool = false

var _is_from_tutorial: bool = false

# ---- 入口动画与插屏广告等待 ----
var _entry_anim_pending_state: Variant = null # 等插屏广告时的占位状态，null 表示没有在等
var _entry_anim_ad_error_cb: Callable = Callable() # 广告失败回调（留着用于断开）
var _entry_anim_ad_closed_cb: Callable = Callable() # 广告关闭回调（留着用于断开）
var _entry_anim_schedule_ts: int = 0 # 排定入口动画时的毫秒时间戳

const ENTRY_AD_SHOW_CONFIRM_SEC: float = 2.0
var _entry_anim_ad_impression_cb: Callable = Callable()
var _entry_anim_show_confirm_timer: Timer = null

const LATE_AD_LOCK_TIMEOUT_SEC: float = 3.0
var _late_ad_impression_cb: Callable = Callable()
var _late_ad_closed_cb: Callable = Callable()
var _late_ad_lock_active: bool = false
var _late_ad_lock_timer: Timer = null
const _BOARD_PATTERN_SWEEP_OVERLAY_SCRIPT: Script = preload(
	"res://scripts/module/game/view/board_pattern_sweep_overlay.gd"
)

var _pattern_sweep_overlay = null
var _pattern_sweep_prepared: bool = false

var _entry_sp_region_ids: Array = []

var _entry_anim_await_stack_top: bool = false

var _entry_anim_waiting_ad: bool = false

var _entry_ad_resume: Callable = Callable()

var _inter_timing_tail_state: Dictionary = {}

var _entry_anim_skipped: bool = false

const _INTER_DELAY_AFTER_BOARD_SEC: float = 0.4

# ---- 生命预警动画状态 ----
var _warn_phase: int = 0 # 预警阶段：0 未触发 / 1 展示中（等点击）/ 2 收尾
var _warn_click_allowed: bool = false # 是否已过保护时间、允许点击关闭

var _gf_guide_start_ms: int = 0

var _last_fail_end_params: Dictionary = {}


func _set_level_text(text: String, level_num: int = -1) -> void:
	_level_label.text = text
	_level_value_num = level_num


func _apply_difficulty_level_text(lv: int) -> void:
	_is_super_hard_level = LevelSelector.is_super_hard_level(lv)
	_is_hard_level = LevelSelector.is_hard_level(lv)
	if _is_super_hard_level:
		_set_level_text(tr("GAME_LEVEL_SUPER_HARD") % lv, lv)
	elif _is_hard_level:
		_set_level_text(tr("GAME_LEVEL_HARD") % lv, lv)
	else:
		_set_level_text(tr("GAME_LEVEL_TITLE") % lv, lv)
	_set_hard_fire_visible(_is_hard_level)


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


func _ready() -> void:
	super._ready()
	_entry_handlers = {
		EntryMode.NORMAL: _setup_entry_normal,
		EntryMode.BANK: _setup_entry_bank,
		EntryMode.BANK_SP: _setup_entry_bank_sp,
		EntryMode.DEBUG_CONFIG: _setup_entry_debug_config,
		EntryMode.DEBUG_PREBUILT: _setup_entry_debug_prebuilt,
	}
	_refresh_life_bar_display()

	_hint_overlay.hint_detail_requested.connect(_on_chain_detail_requested)
	_hint_overlay.layer = 10

	_anim_tips.animation_finished.connect(_on_warn_anim_finished)
	_build_strategy_overlay()

	_pre_cat_fx = PreCatFxDirector.new(self, _board_view)

	claim_button_sound($Root/VBoxContainer/Header/SettingsBtn)
	_endgame_persist_timer = Timer.new()
	_endgame_persist_timer.one_shot = true
	_endgame_persist_timer.wait_time = ENDGAME_PERSIST_DEBOUNCE_SEC
	_endgame_persist_timer.timeout.connect(_flush_endgame_snapshot)
	add_child(_endgame_persist_timer)

	_board_adapt_holder.resized.connect(_align_rank_collector_y)

	var cat_heart_row: Control = get_node_or_null("Root/VBoxContainer/CatHeartRow") as Control
	if cat_heart_row != null:
		cat_heart_row.resized.connect(_on_cat_heart_row_resized)


func _on_cat_heart_row_resized() -> void:
	_apply_heart_bg_position_for_progress(ABTestManager.normal_top_ui.is_cat_progress_bar())


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


func _resolve_entry_level(params: Dictionary) -> int:
	var entry_mode: EntryMode = _resolve_entry_mode(params)
	match entry_mode:
		EntryMode.NORMAL:
			return maxi(1, int(params.get("level_index", 1)))
		EntryMode.BANK, EntryMode.BANK_SP:
			return int(params.get("retry_level", 0))
		EntryMode.DEBUG_CONFIG:
			var config: Dictionary = params["debug_config"]
			return int(config.get("level", 0))
		_:
			return 0


func _dye_game_start_normal(level_num: int) -> void:
	ABTestManager.dye_at_game_start_normal()
	if level_num >= 10:
		ABTestManager.dye_at_game_start_normal_10()
	if level_num >= 11:
		ABTestManager.dye_at_game_start_normal_11()
	if level_num >= 21:
		ABTestManager.dye_at_game_start_normal_21()
	if level_num >= 34:
		ABTestManager.dye_at_game_start_normal_34()


func _dye_game_win_end() -> void:
	ABTestManager.dye_at_game_win_end()
	if _level_config.get("level", 0) >= 20:
		ABTestManager.dye_at_game_end_normal_20()
	if _level_config.get("level", 0) >= 11:
		ABTestManager.dye_at_game_end_normal_11()
	if _level_config.get("level", 0) >= 10:
		ABTestManager.dye_at_game_end_normal_10()
	if _level_config.get("level", 0) >= 1:
		ABTestManager.dye_at_game_end_normal_1()


func _is_game_barrage_supported_entry(entry_mode: EntryMode) -> bool:
	return (
		entry_mode == EntryMode.NORMAL
		or (entry_mode == EntryMode.BANK and int(_level_config.get("level", 0)) > 0)
	)


func _is_settle_page_flight_active() -> bool:
	if LevelKind.is_golden_fish(_level_kind):
		return false
	return ABTestManager.leaderboard_collection_levelwin.is_settle_page_flight()


func _is_center_relay_flight_active() -> bool:
	if LevelKind.is_golden_fish(_level_kind):
		return false
	return ABTestManager.leaderboard_collection_levelwin.is_center_relay_flight()


func _should_keep_life_fish_active() -> bool:
	if LevelKind.is_golden_fish(_level_kind):
		return false
	return ABTestManager.leaderboard_collection_levelwin.should_keep_life_fish()


func _should_play_collect_before_trail_active() -> bool:
	if LevelKind.is_golden_fish(_level_kind):
		return false
	return ABTestManager.leaderboard_collection_levelwin.should_play_collect_before_trail()


func _update_rank_collector() -> void:
	if _rank_collector_anchor == null:
		return
	_align_rank_collector_y()
	var is_gf: bool = LevelKind.is_golden_fish(_level_kind)

	if _rank_collector != null and is_instance_valid(_rank_collector):
		_rank_collector.set_golden_fish(is_gf)

	if _is_settle_page_flight_active():
		if _rank_collector != null and is_instance_valid(_rank_collector):
			_rank_collector.hide_and_reset()
		return

	if not (RankActivityManager.is_running() and RankActivityManager.is_joined()):
		if _rank_collector != null and is_instance_valid(_rank_collector):
			_rank_collector.hide_and_reset()
		return

	if _rank_collector == null or not is_instance_valid(_rank_collector):
		_rank_collector = create_child(RANK_COLLECTOR_SCENE) as RankCollectorCell
		var prev: Node = _rank_collector.get_parent()
		if prev != null:
			prev.remove_child(_rank_collector)

		var board_intro := $Root as BoardContainerCell_01
		if board_intro != null:
			board_intro.set_auto_trigger(false)
		_rank_collector_anchor.add_child(_rank_collector)
		if board_intro != null:
			board_intro.set_auto_trigger(true)
		_rank_collector.position = Vector2.ZERO

		_rank_collector.set_collect_icon_above_z(_RANK_COLLECTOR_ICON_Z)

		_rank_collector.set_golden_fish(is_gf)

	_rank_collector.hide_and_reset()

	_reset_flight_trails()


func _align_rank_collector_y() -> void:
	if _rank_collector_anchor == null or _board_adapt_holder == null or _board_view == null:
		return

	var rule_bar := get_node_or_null("Root/VBoxContainer/RuleBar") as Control
	var vbox := _board_adapt_holder.get_parent() as Control
	if rule_bar == null or vbox == null:
		return
	var pill_h: float = _rank_collector_anchor_base_bottom - _rank_collector_anchor_base_top

	var separation: float = float(vbox.get_theme_constant("separation"))

	var rule_bottom: float = rule_bar.position.y + rule_bar.size.y
	var rule_inner := rule_bar.get_node_or_null("Control") as Control
	var rules_bg := rule_bar.get_node_or_null("Control/RulesBg") as Control
	if rule_inner != null and rules_bg != null:
		rule_bottom = (
			rule_bar.position.y + rule_inner.position.y + rules_bg.position.y + rules_bg.size.y
		)
	var board_container_top: float = (
		_board_adapt_holder.position.y + _board_adapt_holder.size.y + separation
	)

	var board_inset: float = _board_view.position.y
	var gap_h: float = board_container_top - rule_bottom
	var centered_top: float = (board_inset - gap_h - pill_h) * 0.5

	var lowest_top: float = board_inset - _RANK_COLLECTOR_MIN_BOARD_GAP - pill_h

	var top: float = minf(centered_top, lowest_top)
	_rank_collector_anchor.offset_top = top
	_rank_collector_anchor.offset_bottom = top + pill_h


func _on_board_container_resized() -> void:
	super()
	_align_rank_collector_y.call_deferred()


func _play_rank_collect_flight() -> bool:
	if _is_settle_page_flight_active():
		return false

	if not RankActivityManager.is_joined():
		return false
	var st: int = RankActivityManager.get_state()
	if st != RankActivityData.State.OPEN_JOINED and st != RankActivityData.State.SETTLING:
		return false
	if not RankActivityManager.did_last_win_score():
		return false
	if _rank_collector == null or not is_instance_valid(_rank_collector):
		return false
	return await _play_rank_flight_fish()


func _play_rank_flight_fish() -> bool:
	if LevelKind.is_golden_fish(_level_kind):
		return await _play_golden_fish_split_flight()
	var slots: Array = _life_bar.slots()
	var fish: Array = []
	for i in range(mini(_lives, slots.size())):
		var slot: Control = slots[i] as Control
		if slot != null and is_instance_valid(slot):
			fish.append({"slot": slot, "from": slot.get_global_rect().get_center()})
	if fish.is_empty():
		return false
	_center_relay_fish_count = fish.size()
	for k in fish.size():
		var launch_at: float = rank_fish_fly_start + rank_fish_fly_interval * k

		if _should_play_collect_before_trail_active():
			get_tree().create_timer(maxf(0.0, launch_at - rank_fish_collect_lead)).timeout.connect(
				_on_fish_collect_anim.bind(fish[k]["slot"])
			)
		get_tree().create_timer(launch_at).timeout.connect(
			_on_fish_flight_launch.bind(fish[k]["slot"], fish[k]["from"], k)
		)

	var per_fish_dur: float = rank_fish_fly_dur
	if _is_center_relay_flight_active():
		per_fish_dur = rank_center_relay_to_center_dur + rank_center_relay_hold + rank_fish_fly_dur
	var total: float = (
		rank_fish_fly_start + rank_fish_fly_interval * maxi(0, fish.size() - 1) + per_fish_dur
	)
	await get_tree().create_timer(total).timeout

	if _rank_collector != null and is_instance_valid(_rank_collector):
		_rank_collector.settle_count_to_actual()
	return true


func _play_golden_fish_split_flight() -> bool:
	if _golden_fish_fly == null or not is_instance_valid(_golden_fish_fly):
		return false
	var anim: AnimationPlayer = (
		_golden_fish_fly.get_node_or_null("AnimationPlayer") as AnimationPlayer
	)
	if anim == null or not anim.has_animation(_GF_FLY_ANIM):
		push_error("GamePage: GoldenFish_Fly 缺动画 '%s'" % _GF_FLY_ANIM)
		return false

	await get_tree().create_timer(rank_fish_fly_start).timeout
	if not is_showing():
		return false

	_life_bar.mark_slot_lost_for_flight(_life_bar.slot_at(0), true)
	_golden_fish_fly.visible = true
	_start_golden_fish_fly_move()
	anim.play(_GF_FLY_ANIM)
	await get_tree().create_timer(golden_fish_split_collect_at).timeout

	if not is_showing() or _rank_collector == null or not is_instance_valid(_rank_collector):
		_reset_golden_fish_fly()
		return false

	var plans: Array = []
	for i in RankActivityConfig.GOLDEN_FISH_COLLECT_RATIO:
		var f: Control = _golden_fish_fly.get_node_or_null("Fish%d" % (i + 1)) as Control
		if f == null or not is_instance_valid(f):
			continue
		var delay: float = (
			maxf(0.0, _GF_SPLIT_FADE_START[i] - golden_fish_split_collect_at)
			if i < _GF_SPLIT_FADE_START.size()
			else 0.0
		)

		var bez_y: Vector4 = _RANK_FISH_DIP_BEZIER_Y if (i == 0 or i == 4) else _RANK_FISH_BEZIER_Y
		plans.append(
			{"from": f.get_global_transform() * (f.size * 0.5), "delay": delay, "bez_y": bez_y}
		)
	plans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["delay"] < b["delay"])
	for order in plans.size():
		var p: Dictionary = plans[order]

		get_tree().create_timer(p["delay"]).timeout.connect(
			_on_fish_flight_launch.bind(null, p["from"], order, p["bez_y"])
		)
	var launched: int = plans.size()
	var last_delay: float = plans[plans.size() - 1]["delay"] if not plans.is_empty() else 0.0
	if launched == 0:
		push_error(
			(
				"GamePage: GoldenFish_Fly 找不到 Fish1~%d 节点"
				% RankActivityConfig.GOLDEN_FISH_COLLECT_RATIO
			)
		)
		_reset_golden_fish_fly()
		return false

	var fly_done: float = last_delay + rank_fish_fly_dur
	var anim_left: float = maxf(
		0.0, anim.get_animation(_GF_FLY_ANIM).length - golden_fish_split_collect_at
	)
	await get_tree().create_timer(maxf(fly_done, anim_left)).timeout
	_reset_golden_fish_fly()
	return true


func _start_golden_fish_fly_move() -> void:
	var img: Control = _golden_fish_fly.get_node_or_null("Root/GlodenFishImg") as Control
	var holder: CanvasItem = _golden_fish_fly.get_parent() as CanvasItem
	var heart_slot: Control = _life_bar.slot_at(0)
	if img == null or holder == null or heart_slot == null or not is_instance_valid(heart_slot):
		return
	if not _gf_home_cached:
		_gf_home_pos = _golden_fish_fly.position
		_gf_home_cached = true
	_golden_fish_fly.position = _gf_home_pos

	var to_holder: Transform2D = holder.get_global_transform().affine_inverse()
	var rest: Vector2 = to_holder * (img.get_global_transform() * (img.size * 0.5))
	var start: Vector2 = to_holder * (heart_slot.get_global_transform() * (heart_slot.size * 0.5))
	var end: Vector2 = to_holder * (get_global_transform() * (size * 0.5))
	var start_pos: Vector2 = _gf_home_pos + (start - rest)
	var end_pos: Vector2 = _gf_home_pos + (end - rest)
	_golden_fish_fly.position = start_pos

	var trail: Node = _golden_fish_fly.get_node_or_null("Root/ScoreTrail")
	if trail != null and trail.has_method(&"clear_trail"):
		trail.call(&"clear_trail")
	_kill_golden_fish_fly_tweens()

	_gf_fly_tw_x = create_tween()
	(
		_gf_fly_tw_x
		. tween_property(
			_golden_fish_fly, "position:x", start_pos.x + _GF_FLY_BUMP_X, _GF_FLY_BUMP_SEC
		)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		_gf_fly_tw_x
		. tween_property(
			_golden_fish_fly, "position:x", end_pos.x, _GF_FLY_TOTAL_SEC - _GF_FLY_BUMP_SEC
		)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)

	_gf_fly_tw_y = create_tween()
	(
		_gf_fly_tw_y
		. tween_property(_golden_fish_fly, "position:y", end_pos.y, _GF_FLY_TOTAL_SEC)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)


func _kill_golden_fish_fly_tweens() -> void:
	for tw: Tween in [_gf_fly_tw_x, _gf_fly_tw_y]:
		if tw != null and tw.is_valid():
			tw.kill()
	_gf_fly_tw_x = null
	_gf_fly_tw_y = null


func _reset_golden_fish_fly() -> void:
	if _golden_fish_fly == null or not is_instance_valid(_golden_fish_fly):
		return
	var anim: AnimationPlayer = (
		_golden_fish_fly.get_node_or_null("AnimationPlayer") as AnimationPlayer
	)
	_kill_golden_fish_fly_tweens()
	if _gf_home_cached:
		_golden_fish_fly.position = _gf_home_pos

	var trail: Node = _golden_fish_fly.get_node_or_null("Root/ScoreTrail")
	if trail != null and trail.has_method(&"clear_trail"):
		trail.call(&"clear_trail")
	if anim != null:
		anim.stop()

		if anim.has_animation(&"RESET"):
			anim.play(&"RESET")
			anim.advance(0.0)
	_golden_fish_fly.visible = false


func _on_fish_collect_anim(slot: Control) -> void:
	if not is_showing():
		return
	if is_instance_valid(slot) and slot is LifeSlot:
		(slot as LifeSlot).play_collect()


func _on_fish_flight_launch(
	slot: Control, from: Vector2, order: int = 0, bez_y: Vector4 = _RANK_FISH_BEZIER_Y
) -> void:
	if not is_showing() or _rank_collector == null or not is_instance_valid(_rank_collector):
		return
	var fish_kinds: Array = [
		SoundManager.Kind.RANK_FISH_COLLECT_1,
		SoundManager.Kind.RANK_FISH_COLLECT_2,
		SoundManager.Kind.RANK_FISH_COLLECT_3,
	]
	SoundManager.play(fish_kinds[clampi(order, 0, fish_kinds.size() - 1)])

	if not _should_keep_life_fish_active():
		_life_bar.mark_slot_lost_for_flight(slot, true)

	if _is_center_relay_flight_active():
		_play_center_relay(from, order)
	else:
		_spawn_flight_trail(
			from,
			_rank_collector.get_collect_target_global(),
			rank_fish_fly_dur,
			_RANK_FISH_BEZIER_X,
			bez_y
		)


func _play_center_relay(from: Vector2, index: int) -> void:
	if _rank_collector == null or not is_instance_valid(_rank_collector):
		return

	var n: int = maxi(1, _center_relay_fish_count)
	var screen_center: Vector2 = get_viewport_rect().get_center()
	var target: Vector2
	if n == 3:
		var r: float = rank_center_relay_triangle_radius
		var tri: Array[Vector2] = [
			Vector2(-0.8660254 * r, 0.5 * r),
			Vector2(0.0, -r),
			Vector2(0.8660254 * r + 15.0, 0.5 * r),
		]
		target = screen_center + tri[clampi(index, 0, 2)]
	else:
		target = (
			screen_center
			+ Vector2((float(index) - float(n - 1) / 2.0) * rank_center_relay_spacing, 0.0)
		)
	var fx: Node = _FISH_FLY_SCENE.instantiate()
	add_child(fx)
	(fx as CanvasItem).z_index = 45
	_center_relay_fish_nodes.append(fx)
	var root: Control = fx.get_node_or_null("Root") as Control
	if root == null:
		_center_relay_fish_nodes.erase(fx)
		fx.queue_free()
		_spawn_flight_trail(
			from,
			_rank_collector.get_collect_target_global(),
			rank_fish_fly_dur,
			_RANK_FISH_BEZIER_X,
			_RANK_FISH_BEZIER_Y
		)
		return
	root.global_position = from
	var anim: AnimationPlayer = fx.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_animation("FishFly"):
		anim.play("FishFly")
	var collector_target: Vector2 = _rank_collector.get_collect_target_global()

	var tw: Tween = fx.create_tween()

	var bump_x: float = from.x + rank_center_relay_bump_x
	var seg2_dur: float = rank_center_relay_to_center_dur - rank_center_relay_bump_sec
	var to_center := func(elapsed: float) -> void:
		if not is_instance_valid(root):
			return
		var px: float
		if elapsed <= rank_center_relay_bump_sec:
			px = Tween.interpolate_value(
				from.x,
				rank_center_relay_bump_x,
				elapsed,
				rank_center_relay_bump_sec,
				Tween.TRANS_CUBIC,
				Tween.EASE_IN_OUT
			)
		else:
			px = Tween.interpolate_value(
				bump_x,
				target.x - bump_x,
				elapsed - rank_center_relay_bump_sec,
				seg2_dur,
				Tween.TRANS_CUBIC,
				Tween.EASE_IN_OUT
			)
		var py: float = Tween.interpolate_value(
			from.y,
			target.y - from.y,
			elapsed,
			rank_center_relay_to_center_dur,
			Tween.TRANS_CUBIC,
			Tween.EASE_IN_OUT
		)
		root.global_position = Vector2(px, py)
	tw.tween_method(
		to_center, 0.0, rank_center_relay_to_center_dur, rank_center_relay_to_center_dur
	)
	tw.tween_interval(rank_center_relay_hold)

	tw.tween_callback(
		func() -> void:
			if (
				is_instance_valid(fx)
				and _rank_collector != null
				and is_instance_valid(_rank_collector)
				and fx.get_parent() != _rank_collector
			):
				fx.get_parent().remove_child(fx)
				_rank_collector.add_child(fx)
				(fx as CanvasItem).z_index = _CENTER_RELAY_FISH_FLY_COLLECTOR_Z
				if is_instance_valid(root):
					root.global_position = target
	)

	var bez_y: Vector4 = _RANK_FISH_BEZIER_Y
	if n == 3:
		if index == 0:
			bez_y = _RANK_FISH_DIP_BEZIER_Y
		elif index == 2:
			bez_y = _RANK_FISH_BEZIER_X
	elif n == 2:
		if index == 0:
			bez_y = _RANK_FISH_DIP_BEZIER_Y
	elif index == 0 or index == n - 1:
		bez_y = _RANK_FISH_DIP_BEZIER_Y
	var mover := func(t: float) -> void:
		if not is_instance_valid(root):
			return
		var ex: float = ComboFeedbackView._cubic_bezier_ease(
			t,
			_RANK_FISH_BEZIER_X.x,
			_RANK_FISH_BEZIER_X.y,
			_RANK_FISH_BEZIER_X.z,
			_RANK_FISH_BEZIER_X.w
		)
		var ey: float = ComboFeedbackView._cubic_bezier_ease(t, bez_y.x, bez_y.y, bez_y.z, bez_y.w)
		root.global_position = Vector2(
			lerpf(target.x, collector_target.x, ex), lerpf(target.y, collector_target.y, ey)
		)
	tw.tween_method(mover, 0.0, 1.0, rank_fish_fly_dur)

	tw.tween_callback(
		func() -> void:
			if is_showing() and _rank_collector != null and is_instance_valid(_rank_collector):
				_rank_collector.on_item_collected()
	)
	tw.tween_interval(rank_fly_trail_fade)
	tw.tween_callback(
		func() -> void:
			_center_relay_fish_nodes.erase(fx)
			if is_instance_valid(fx):
				fx.queue_free()
	)


func _spawn_flight_trail(
	from: Vector2, to: Vector2, dur: float, bez_x: Vector4, bez_y: Vector4
) -> void:
	if _rank_collector == null or not is_instance_valid(_rank_collector):
		return
	var trail: Node = _RANK_FLIGHT_TRAIL_SCENE.instantiate()
	_rank_collector.add_child(trail)

	(trail as CanvasItem).z_index = (
		_GF_FLIGHT_TRAIL_Z if LevelKind.is_golden_fish(_level_kind) else _RANK_FLIGHT_TRAIL_Z
	)
	var sprite: Node2D = trail.get_node_or_null("ScoreTrail")
	if sprite == null:
		trail.queue_free()
		return
	sprite.global_position = from

	var fly_target := Node2D.new()
	fly_target.name = "FlyTarget"
	fly_target.global_position = from
	trail.add_child(fly_target)
	sprite.target_path = sprite.get_path_to(fly_target)
	sprite.use_self_when_no_target = false
	for child: Node in sprite.get_children():
		if child is CPUParticles2D:
			var p := child as CPUParticles2D
			sprite.remove_child(p)
			fly_target.add_child(p)
			p.visible = true
			p.emitting = true
	_rank_flight_trails.append(trail)

	var tw: Tween = trail.create_tween()

	var mover := func(t: float) -> void:
		if not (is_instance_valid(fly_target) and is_instance_valid(sprite)):
			return
		var ex: float = ComboFeedbackView._cubic_bezier_ease(t, bez_x.x, bez_x.y, bez_x.z, bez_x.w)
		var ey: float = ComboFeedbackView._cubic_bezier_ease(t, bez_y.x, bez_y.y, bez_y.z, bez_y.w)
		fly_target.global_position = Vector2(lerpf(from.x, to.x, ex), lerpf(from.y, to.y, ey))
		sprite.notify_target_moved()
	tw.tween_method(mover, 0.0, 1.0, dur)
	tw.tween_callback(_on_flight_arrived.bind(trail))


func _on_flight_arrived(trail: Node) -> void:
	if _rank_collector != null and is_instance_valid(_rank_collector):
		_rank_collector.on_item_collected()
	if not is_instance_valid(trail):
		return
	_set_trail_emitting(trail, false)

	var linger: Tween = trail.create_tween()
	linger.tween_interval(rank_fly_trail_fade)
	linger.tween_callback(_free_flight_trail.bind(trail))


func _free_flight_trail(trail: Node) -> void:
	_rank_flight_trails.erase(trail)
	if is_instance_valid(trail):
		trail.queue_free()


func _set_trail_emitting(trail: Node, on: bool) -> void:
	for p: Node in trail.find_children("*", "CPUParticles2D", true, false):
		var particle := p as CPUParticles2D
		if particle != null:
			particle.emitting = on


func _reset_flight_trails() -> void:
	for trail: Variant in _rank_flight_trails:
		if is_instance_valid(trail):
			(trail as Node).queue_free()
	_rank_flight_trails.clear()

	for fx: Variant in _center_relay_fish_nodes:
		if is_instance_valid(fx):
			(fx as Node).queue_free()
	_center_relay_fish_nodes.clear()


## 整理普通关及活动关入口参数，区分残局恢复、直接开局和教程，初始化本局反馈与模式。
func on_show(params: Dictionary = {}) -> void:
	_elo_v2_formal_main = false
	_finish_rank_win_presentation(true)
	_reset_game_barrages()

	Tracker.set_active_game_type(Tracker.GameType.NORMAL)

	_life_bar.restore_hidden_slots()
	_life_bar_mul.restore_hidden_slots()

	ABTestManager.dye_at_game_start()

	super.on_show(params)

	_start_cc_pattern_btn_entry_fade()

	_return_bank_btn.visible = params.get("from_bank_browser", false)

	if _active_toast != null:
		_active_toast.hide_toast()

	_is_endgame_restore_session = params.get("endgame_restore", false)

	_cat_progress_rotate_override = int(params.get("restore_cat_progress_rotate", -1))

	_level_value_num = -1

	_is_direct_open_session = params.get("from_direct_open", false)

	_is_from_tutorial = params.get("from_tutorial", false)

	_dye_game_start_normal(_resolve_entry_level(params))
	_golden_fish_pre_cat = GoldenFishPreCat.new(ABTestManager.golden_fish_precat)

	if ColorChallengeGate.is_unlocked(GameState.get_golden_fish_career_count()):
		ABTestManager.dye_at_game_start_pass4_goldenfish()
	_try_begin_returnee_event(params)

	var kind_level: int = int(params.get("level_index", params.get("retry_level", 0)))
	_level_kind = GoldenFishGate.resolve_kind(
		kind_level,
		GameState.get_available_golden_fish_pending(),
		ABTestManager.golden_fish_func.is_enabled(),
		ABTestManager.golden_fish_timing.unlock_min_level()
	)

	if _level_kind == LevelKind.MAIN:
		_level_kind = ColorChallengeGate.resolve_kind(
			kind_level,
			GameState.get_color_challenge_pending(),
			ABTestManager.color_challenge_func.group_value()
		)

	if not OS.has_feature("rel"):
		print(
			(
				"[GoldenFish] game_page kind: 关号=%d pending=%s enabled=%s → 算出=%d%s"
				% [
					kind_level,
					str(GameState.get_golden_fish_pending()),
					str(ABTestManager.golden_fish_func.is_enabled()),
					_level_kind,
					(
						(", 残局覆盖为 kind=%d" % int(params["restore_kind"]))
						if params.has("restore_kind")
						else ""
					)
				]
			)
		)

	if params.has("restore_kind"):
		_level_kind = int(params["restore_kind"])
	_discard_level_on_digit_group_switch(params)
	_golden_fish_pre_cat.prepare_entry(_resolve_entry_level(params), _level_kind)

	if LevelKind.is_insert_golden_fish(_level_kind):
		ABTestManager.dye_at_game_start_onefish()

		if not OS.has_feature("rel"):
			print(
				(
					"[GoldenFish] 已染色(GAME_START_ONEFISH,取题之前) → 取题策略组=%d"
					% ABTestManager.golden_fish_func.current_group()
				)
			)

	if LevelKind.is_color_challenge(_level_kind):
		GameState.begin_color_challenge_pattern_mode()
		_apply_pattern_mode()

	var _skip_dfld: bool = (
		params.get("_stale_new_easier", false)
		or params.get("_returnee_fresh", false)
		or _will_discard_stale_endgame_snapshot(params)
		or LevelKind.is_golden_fish(_level_kind)
		or LevelKind.is_color_challenge(_level_kind)
	)

	if not _skip_dfld:
		GameState.evaluate_daily_first_easy()

	elif ABTestManager.normal_level.is_onefish_dfld_fix() and LevelKind.is_golden_fish(_level_kind):
		GameState.evaluate_daily_first_easy()
		if GameState.is_daily_first_easy_available():
			GameState.consume_daily_first_easy()
			print("[DailyFirstEasy] 一命关消耗当日机会 (onefish_dfld_fix)")

	elif LevelKind.is_color_challenge(_level_kind):
		GameState.evaluate_daily_first_easy()
		if GameState.is_daily_first_easy_available():
			GameState.consume_daily_first_easy()
			print("[DailyFirstEasy] 颜色挑战消耗当日机会")

	var _dfe_lv: int = params.get("level_index", 0)
	var _dfe_is_normal_entry: bool = (
		_dfe_lv > 0
		and not params.get("bank_mode", false)
		and not params.has("debug_config")
		and not params.has("debug_prebuilt")
	)
	if not _skip_dfld and _dfe_is_normal_entry and GameState.is_daily_first_easy_available():
		var _dfe_is_hard: bool = LevelSelector.is_hard_level(_dfe_lv)
		if _dfe_is_hard or LevelData.is_special_level(_dfe_lv):
			GameState.consume_daily_first_easy()
			print("[DailyFirstEasy] 特殊/Hard关 level=%d, 不降档, 机会消耗" % _dfe_lv)
		elif _has_user_progress_in_endgame_snapshot(_dfe_lv):
			GameState.consume_daily_first_easy()
			print("[DailyFirstEasy] 有操作残局,残局复原优先,机会消耗 (level=%d)" % _dfe_lv)
		elif _is_locked_puzzle_hard_neighbor_eased(_dfe_lv):
			GameState.consume_daily_first_easy()
			print("[DailyFirstEasy] 本关已由难关邻居规则降档,不再降档,机会消耗 (level=%d)" % _dfe_lv)
		else:
			GameState.clear_endgame_snapshot()
			if not GameState.get_retry_puzzle(_dfe_lv).is_empty():
				GameState.clear_retry_puzzle()
			print("[DailyFirstEasy] 清除缓存,准备取降档新题 (level=%d)" % _dfe_lv)

	if not _skip_dfld and not GameState.is_daily_first_easy_available():
		GameState.advance_daily_first_easy_date()

	if _try_consume_endgame_snapshot(params):
		return

	var _entry_lv_for_cached: int = params.get("level_index", 0)
	if (
		_entry_lv_for_cached > 0
		and not params.get("bank_mode", false)
		and not params.has("debug_config")
		and not params.has("debug_prebuilt")
	):
		var _cached: Dictionary = GameState.get_retry_puzzle(_entry_lv_for_cached)
		if not _cached.is_empty() and _retry_cache_matches_kind(_cached):
			GameState.clear_current_level_dirty()

			var _cached_params: Dictionary = _cached.duplicate(true)
			_cached_params["_tracker_status"] = Tracker.GameStatus.CONTINUE

			_cached_params["from_direct_open"] = _is_direct_open_session

			_cached_params["from_tutorial"] = _is_from_tutorial
			on_show(_cached_params)
			return

	var _entry_lv_idx: int = params.get("level_index", 0)
	_toast_first_try_hint = (
		_entry_lv_idx > 0
		and not params.get("bank_mode", false)
		and not params.has("debug_config")
		and not params.has("debug_prebuilt")
		and GameState.get_retry_puzzle(_entry_lv_idx).is_empty()
	)

	_board_view.visible = false

	_stat_status = params.get("_tracker_status", Tracker.GameStatus.NEW)
	if _stat_status == Tracker.GameStatus.NEW:
		Tracker.new_game_id(Tracker.GameType.NORMAL)
	_stat_start_ms = Time.get_ticks_msec()

	if not CheatBus.command_issued.is_connected(_on_cheat_command):
		CheatBus.command_issued.connect(_on_cheat_command)

	_pre_cat_pend_snapshot = {}

	var _entry_mode: EntryMode = _resolve_entry_mode(params)
	var _entry_setup_result: Variant = _entry_handlers[_entry_mode].call(params)
	if _entry_mode == EntryMode.NORMAL and _entry_setup_result != true:
		UIManager.show_ui(UiName.HOME)
		UIManager.hide_ui(UiName.GAME)
		return
	_begin_elo_v2_attempt_for_entry(_is_game_barrage_supported_entry(_entry_mode))

	_resolve_pre_cat()

	if _pre_cat_fx != null:
		var fx_cell: Vector2i = _pre_cat_position
		if fx_cell.x < 0 and _entry_mode == EntryMode.NORMAL:
			fx_cell = _self_prefill_cell()
		_pre_cat_fx.prepare(
			_level_config.get("level", 0),
			fx_cell,
			_is_endgame_restore_session,
			_golden_fish_pre_cat.fx_kind(_level_kind)
		)

	_log_cat_rank()

	if not LevelKind.is_golden_fish(_level_kind) and GameState.is_daily_first_easy_available():
		GameState.consume_daily_first_easy()
		print("[DailyFirstEasy] 兜底消耗 (strategy<=1 或其他路径未消耗)")

	_strategy_btn.visible = not OS.has_feature("rel")

	var _nav_enabled := _nav_total > 1
	_prev_btn.visible = _nav_enabled
	_next_btn.visible = _nav_enabled
	if _nav_enabled:
		_prev_btn.text = "‹"
		_next_btn.text = "›"

	var life_rule: Dictionary = {"lives": 3, "inf": false}
	if not LevelKind.is_golden_fish(_level_kind):
		life_rule = ABTestManager.health_points_rule.lives_for_level(
			int(_level_config.get("level", 0)), int(_level_config.get("size", 0))
		)
	_lives_inf = (not LevelKind.is_golden_fish(_level_kind)) and life_rule.inf
	var life_cap: int = 1 if LevelKind.is_golden_fish(_level_kind) else int(life_rule.lives)
	_life_cap = life_cap

	_level_config["life_cap"] = life_cap
	_lives = life_cap

	var use_mul_bar: bool = (
		(not LevelKind.is_golden_fish(_level_kind)) and (life_cap > 3 or _lives_inf)
	)
	_life_bar_progress.visible = not use_mul_bar
	_life_bar_mul.visible = use_mul_bar
	_life_bar = _life_bar_mul if use_mul_bar else _life_bar_progress
	_refresh_life_bar_display()

	_life_bar.apply_kind(LevelKind.is_golden_fish(_level_kind))

	if params.has("restore_lives"):
		_lives = clampi(int(params["restore_lives"]), 0, life_cap)
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
	_last_placed_count = -1

	_like_hand_state = {
		"in_game_sec": 0.0,
		"last_cat_sec": 0.0,
		"triggered_count": int(params.get("restore_like_hand_triggered_count", 0)),
		"clock_paused": false,
		"has_seen_first_cat": false,
		"cat_place_times": {},
		"missed_cross_triggered_cats": {},
		"latest_cat_key": "",
		"manually_x_marked_cells": {},
		"hint_marked_x_cells": {},
	}

	var _restore_in_game_sec: float = float(params.get("restore_in_game_sec", 0.0))
	if _restore_in_game_sec > 0.0:
		_like_hand_state["in_game_sec"] = _restore_in_game_sec
		_like_hand_state["last_cat_sec"] = _restore_in_game_sec
		print("[Endgame] restore in_game_sec=%.1fs (Time 指标续接杀端前时长)" % _restore_in_game_sec)

	_continue_play_sec = float(params.get("restore_continue_play_sec", 0.0))
	_continue_clock_started = bool(params.get("restore_continue_clock_started", false))

	for _mc_key in params.get("restore_missed_cross_triggered_cats", []):
		_like_hand_state["missed_cross_triggered_cats"][_mc_key] = true

	for _xm_key in params.get("restore_manually_x_marked_cells", []):
		_like_hand_state["manually_x_marked_cells"][_xm_key] = true
	_start_gameplay_timing(_is_game_barrage_supported_entry(_entry_mode))
	get_tree().create_timer(0.1).timeout.connect(
		func() -> void:
			UIManager.hide_ui(UiName.FAIL)
			UIManager.hide_ui(UiName.WIN)
	)
	_hint_overlay.visible = false
	if _strategy_overlay != null:
		_strategy_overlay.visible = false

	_reset_life_warning()

	_golden_fish_tutorial_card.reset_card()

	_reset_golden_fish_fly()

	_coin_label.text = str(_coins)
	_refresh_life_bar_display()
	_sync_tools_from_state()

	await get_tree().process_frame

	_relayout_board()

	_apply_top_gap_for_short_screen()

	var sz: int = _level_config["size"]
	_board_view.mouse_filter = Control.MOUSE_FILTER_STOP

	_disconnect_combo_signal()

	var _pat_regions: Array = _level_config.get("patternRegions", [])
	var _sp_regions: Array = _level_config.get("spRegion", [])
	var _board_intro_setup := $Root as BoardContainerCell_01
	_entry_sp_region_ids = []
	if _board_intro_setup != null:
		_board_intro_setup.set_auto_trigger(false)
	var color_map_for_setup: Array[int] = _compute_color_map_for_current(sz)

	if params.has("restore_cc_delivery_index"):
		_level_config["_cc_delivery_index"] = int(params["restore_cc_delivery_index"])

	refresh_companion_costume_override()
	_level_config["companion_costume_override"] = _companion_costume_override
	_apply_in_game_costume()

	_apply_color_challenge_palette(sz, color_map_for_setup)
	_board_view.setup(sz, _puzzle["regions"], color_map_for_setup, _pat_regions, true)

	_refresh_color_challenge_pattern_btn()
	_board_view.set_solution(_puzzle_sol_1d())

	if _pre_cat_fx != null and _pre_cat_fx.is_pending():
		_board_view.set_region_dim_enabled(false)
	else:
		_apply_cat_found_grid_dim()
	if _board_intro_setup != null:
		var use_special_intro: bool = not _sp_regions.is_empty()
		if use_special_intro and ABTestManager.normal_level.is_lk_mod_freq_boost_active():
			var _bank_src: String = str(
				_level_config.get("bank_source_main", _level_config.get("bank_source", ""))
			)
			if _bank_src == "lk_mod":
				use_special_intro = false
		_entry_sp_region_ids = _sp_regions.duplicate() if use_special_intro else []
		(
			_board_intro_setup
			. configure_special_regions(
				_puzzle["regions"],
				_entry_sp_region_ids,
			)
		)
		_board_intro_setup.set_auto_trigger(true)

	_prefill_hints()

	_restore_partial_board()

	_seed_like_hand_first_cat_from_board()

	_seed_full_mark_fired_units_from_board()

	_setup_endgame_persist_for_normal_entry(params)
	if _combo_feedback_view == null:
		_combo_feedback_view = get_node_or_null("Root/VBoxContainer/ComboFeedback")
	if _combo_feedback_view != null:
		_combo_feedback_view.reset(_score_model.score)

		_combo_feedback_view.set_inserted_level(not LevelKind.occupies_level_number(_level_kind))
		_combo_feedback_view.set_level_value(_level_value_num)

		_combo_feedback_view.set_super_hard(_is_super_hard_level)
		_combo_feedback_view.set_hard(_is_hard_level)
	_connect_combo_signal()

	_update_remaining(true)

	RankActivityManager.notify_level_start()

	_update_rank_collector()

	_cancel_pattern_sweep_effect()
	_entry_anim_playing = true
	_board_view.visible = false
	_board_view.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_lock_entry_buttons()

	var board_intro := $Root as BoardContainerCell_01
	_disconnect_entry_animation_callbacks(board_intro)
	if _anim_player.is_playing():
		_anim_player.stop()

	_reset_idle_hint()

	_idle_hint_round_count = 0

	var main_level: int = int(_level_config.get("level", 0))
	(
		NormalLevelGroupTag
		. update_at_level_start(
			main_level,
			_entry_mode == EntryMode.NORMAL,
			_level_kind,
		)
	)

	(
		Tracker
		. track_game_start(
			_build_qid(),
			Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)),
			_stat_status,
			_tracker_game_type(),
			_get_diffi(),
			_level_config.get("level", 0),
			_level_config.get("rank", 0),
			_level_config.get("size", 0),
			1 if (RankActivityManager.is_running() and RankActivityManager.is_joined()) else 0,
			_pre_type,
			0,
			0.0,
			_level_config.get("rating", 0.0),
			_build_rec_extra().merged(_build_elo_start_extra()),
		)
	)

	var ad_pos: String = Tracker.AdPos.NORMAL_START
	if _stat_status == Tracker.GameStatus.RESTART:
		ad_pos = Tracker.AdPos.NORMAL_RESTART
	elif _stat_status == Tracker.GameStatus.CONTINUE:
		ad_pos = Tracker.AdPos.NORMAL_CONTINUE

	var delay_start_interstitial: bool = (
		ABTestManager.inter_timing.should_delay_start_interstitial()
	)
	var inter_elig: Dictionary = {}
	_entry_anim_skipped = false
	if not delay_start_interstitial:
		inter_elig = await _eval_start_interstitial(params, ad_pos)

	var board_intro_pre := $Root as BoardContainerCell_01
	if board_intro_pre != null:
		board_intro_pre.set_process(false)
	($Root/VBoxContainer as Container).queue_sort()
	await get_tree().process_frame
	_prepare_start_interstitial_flow()
	if delay_start_interstitial:
		_show_deferred_start_interstitial(params, ad_pos)
	else:
		_show_immediate_start_interstitial(ad_pos, inter_elig)

	_show_banner_if_eligible("game")

	if is_instance_valid(_elo_debug_overlay):
		_refresh_elo_debug_panel()


func _setup_entry_bank(params: Dictionary) -> void:
	var bank_sz: int = params["bank_size"]
	var rank: int = params["bank_rank"]
	var idx: int = params["bank_index"]
	var is_elo_delivery: bool = bool(params.get("is_elo_delivery", false))
	if ABTestManager.normal_level.is_elo_v2_active():
		is_elo_delivery = is_elo_delivery and _has_valid_elo_v2_rating(params)

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
		"_cc_delivery_index": params.get("_cc_delivery_index", -1),
		"rating": params.get("rating", 0.0),
		"is_elo_delivery": is_elo_delivery,
		"eloRating": params.get("eloRating", -1.0) if is_elo_delivery else -1.0,
		"_elo_e": params.get("_elo_e", -1.0) if is_elo_delivery else -1.0,
		"_elo_k": params.get("_elo_k", -1.0) if is_elo_delivery else -1.0,
		"_elo_player_rating": params.get("_elo_player_rating", -1.0) if is_elo_delivery else -1.0,
		"_puzzle_id": params.get("_puzzle_id", ""),
		"style_vector": params.get("style_vector", {}),
		"restore_state": params.get("restore_state", {}),
		"patternRegions":
		params.get("patternRegions", params.get("bank_params", {}).get("patternRegions", [])),
		"spRegion": _resolve_sp_regions(params),
		"kind": _level_kind,
	}

	if int(params.get("_cc_delivery_index", -1)) >= 0:
		_level_config["_cc_delivery_index"] = int(params["_cc_delivery_index"])

	_level_config["pace_group"] = params.get("_bank_pace_group", 0)
	_level_config["pace_score"] = params.get("_bank_pace_score", 0.0)

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
	if retry_lv > 0:
		_apply_difficulty_level_text(retry_lv)
	else:
		_is_hard_level = false
		_is_super_hard_level = false
		_set_level_text("%d×%d  R%d  #%d" % [bank_sz, bank_sz, rank, idx])
		_set_hard_fire_visible(false)
	_strategy_steps = [
		params.get("r1_steps", 0),
		params.get("r2_steps", 0),
		params.get("r3_steps", 0),
		params.get("r4_steps", 0),
		params.get("r5_steps", 0),
	]
	_nav_index = params.get("bank_index", 1)
	_nav_total = params.get("bank_total", 1)


func _setup_entry_bank_sp(params: Dictionary) -> void:
	var bank_sz: int = params["bank_size"]
	var rank: int = params["bank_rank"]
	var idx: int = params["bank_index"]

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
		"_cc_delivery_index": params.get("_cc_delivery_index", -1),
		"rating": params.get("rating", 0.0),
		"patternRegions":
		params.get("patternRegions", params.get("bank_params", {}).get("patternRegions", [])),
		"spRegion": _resolve_sp_regions(params),
		"kind": _level_kind,
	}

	_level_config["pace_group"] = params.get("_bank_pace_group", 0)
	_level_config["pace_score"] = params.get("_bank_pace_score", 0.0)
	if not OS.has_feature("rel"):
		var _seq: Dictionary = PaceLogSeqLookup.lookup(
			_level_config["bank_source"], bank_sz, rank, idx
		)
		print(
			(
				"[Level] lv=%d route=BANK_SP src=%s idx=%d sz=%d rank=%d pace_group=%d pace_score=%.4f r_seq=%s hint_click_seq=%s(len=%d)"
				% [
					retry_lv,
					_level_config["bank_source"],
					idx,
					bank_sz,
					rank,
					_level_config["pace_group"],
					_level_config["pace_score"],
					str(_seq["r_seq"]),
					str(_seq["hint_click_seq"]),
					(_seq["hint_click_seq"] as Array).size(),
				]
			)
		)

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

	var sp_all: Array = BankData.get_sp_levels()
	var pattern: String = "SP"
	if idx - 1 < sp_all.size():
		var sp_entry: Dictionary = sp_all[idx - 1]
		pattern = sp_entry.get("pattern", "SP")
		var raw_prefill: Array = sp_entry.get("prefill_positions", [])
		var int_prefill: Array = []
		for pos in raw_prefill:
			int_prefill.append([int(pos[0]), int(pos[1])])
		_level_config["prefill_positions"] = int_prefill
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


func _resolve_sp_regions(params: Dictionary) -> Array:
	var direct: Array = params.get("spRegion", params.get("bank_params", {}).get("spRegion", []))
	if not direct.is_empty():
		return direct

	var levels: Array = []
	match params.get("bank_source", ""):
		"sp":
			levels = BankData.get_sp_levels()
		"lk":
			levels = BankData.get_lk_levels()
		_:
			return []
	var index: int = int(params.get("bank_index", 0)) - 1
	if index < 0 or index >= levels.size():
		return []
	return (levels[index] as Dictionary).get("spRegion", [])


func _setup_entry_debug_config(params: Dictionary) -> void:
	var dc: Dictionary = params["debug_config"]
	_level_config = dc.duplicate()
	if not _level_config.has("prefill_count"):
		_level_config["prefill_count"] = 0
	if not _level_config.has("prefill_positions"):
		_level_config["prefill_positions"] = []

	_level_config["kind"] = LevelKind.MAIN
	const _PUZZLE_GENERATOR_PATH := "res://scripts/module/gameplay/core/puzzle_generator.gd"
	var generator_script: GDScript = (
		load(_PUZZLE_GENERATOR_PATH) if ResourceLoader.exists(_PUZZLE_GENERATOR_PATH) else null
	)
	if generator_script == null:
		push_error("[GamePage] debug_config 入口不可用：PuzzleGenerator 不在当前包内")
		return
	_puzzle = generator_script.generate_puzzle(_level_config)
	_set_level_text(dc.get("label", "Debug"))
	_strategy_steps = [0, 0, 0, 0, 0]
	_nav_index = 0
	_nav_total = 0


func _setup_entry_debug_prebuilt(params: Dictionary) -> void:
	var dp: Dictionary = params["debug_prebuilt"]
	var dp_sz: int = dp["size"]
	_level_config = {
		"level": 0,
		"size": dp_sz,
		"seed": 0,
		"prefill_count": 0,
		"prefill_positions": [],
		"kind": _level_kind,
	}
	_puzzle = {"regions": dp["regions"], "solution": dp["solution"]}
	_set_level_text(dp.get("label", "Debug"))
	_strategy_steps = [0, 0, 0, 0, 0]
	_nav_index = 0
	_nav_total = 0


func _select_entry_for_level(
	level_index: int,
	rank_override: int,
	pre_cat_pend: Dictionary = {},
	ignore_special: bool = false,
	cc_stale: Dictionary = {}
) -> Dictionary:
	var group: int = ABTestManager.normal_level.value()
	var use_returnee: bool = GameState.get_returnee_remaining(group) > 0 or ignore_special
	if use_returnee:
		var selection_pending: Dictionary = _golden_fish_pre_cat.selector_pending(
			_level_kind, pre_cat_pend
		)
		var entry: Dictionary = LevelSelector.select(
			level_index, rank_override, selection_pending, ignore_special
		)
		if not entry.is_empty() and LevelKind.is_color_challenge(_level_kind):
			var delivery_index: int = GameState.get_color_challenge_delivered()
			entry["_cc_delivery_index"] = delivery_index
			var retry: Dictionary = GameState.get_retry_puzzle(level_index).duplicate(true)
			retry["_cc_delivery_index"] = delivery_index
			retry["_returnee_color_override"] = true
			GameState.set_retry_puzzle(level_index, retry)
			GameState.commit_color_challenge_override_delivery()
		return entry

	if LevelKind.is_color_challenge(_level_kind):
		var cc_entry: Dictionary = ColorChallengeSelector.select(
			level_index, int(cc_stale.get("rank", 0)), int(cc_stale.get("size", 0))
		)
		if not cc_entry.is_empty():
			return cc_entry
		push_error("[ColorChallenge] level unavailable, fallback to main level=%d" % level_index)
		_level_kind = LevelKind.MAIN
		GameState.on_color_challenge_settled()
		return LevelSelector.select(level_index, rank_override, pre_cat_pend)
	if not LevelKind.is_insert_golden_fish(_level_kind):
		return LevelSelector.select(level_index, rank_override, pre_cat_pend)
	var gf_entry: Dictionary = GoldenFishSelector.select(level_index)
	if not gf_entry.is_empty():
		return gf_entry
	push_error("[GoldenFish] insert level unavailable, fallback to main level=%d" % level_index)
	_level_kind = LevelKind.MAIN

	GameState.on_golden_fish_settled(false)

	_pre_cat_pend_snapshot = _golden_fish_pre_cat.fallback_pending(level_index, pre_cat_pend)
	return LevelSelector.select(level_index, rank_override, _pre_cat_pend_snapshot)


func _setup_entry_normal(params: Dictionary) -> bool:
	var level_index: int = params.get("level_index", 1)
	level_index = max(1, level_index)

	var rank_override: int = int(params.get("rank_override", 0))

	_pre_cat_pend_snapshot = _golden_fish_pre_cat.consume_pending(level_index, _level_kind)
	var lv_entry: Dictionary = _select_entry_for_level(
		level_index,
		rank_override,
		_pre_cat_pend_snapshot,
		bool(params.get("_returnee_ignore_special", false)),
		params.get("_cc_stale", {})
	)
	if lv_entry.is_empty():
		push_error("GamePage: LevelSelector failed to deliver entry, level=%d" % level_index)
		return false

	var lv_sz: int = int(lv_entry.get("size", 0))
	if lv_sz == 0:
		lv_sz = SizeModifier.get_size(level_index)
	var lv_rank: int = int(lv_entry.get("_delivery_rank", lv_entry.get("_bank_rank", 1)))
	var lv_sol_1d: Array = lv_entry.get("solution", [])
	var lv_sol_2d: Array = []
	for r: int in range(lv_sz):
		var row: Array = []
		row.resize(lv_sz)
		row.fill(false)
		if r < lv_sol_1d.size():
			row[int(lv_sol_1d[r])] = true
		lv_sol_2d.append(row)
	var lv_raw_regions: Array = lv_entry.get("regionMap", [])
	var lv_int_regions: Array = []
	for row_arr: Array in lv_raw_regions:
		var int_row: Array = []
		for v in row_arr:
			int_row.append(int(v))
		lv_int_regions.append(int_row)

	var lv_prefill_positions: Array = lv_entry.get("_prefill_positions", [])

	var is_elo_delivery: bool = bool(lv_entry.get("is_elo_delivery", false))
	if ABTestManager.normal_level.is_elo_v2_active():
		is_elo_delivery = is_elo_delivery and _has_valid_elo_v2_rating(lv_entry)
	_level_config = {
		"level": level_index,
		"size": lv_sz,
		"rank": lv_rank,
		"seed": lv_entry.get("seed", 0),
		"prefill_count": 1 if not lv_prefill_positions.is_empty() else 0,
		"prefill_positions": lv_prefill_positions.duplicate(true),
		"bank_source": lv_entry.get("_bank_source", "regular"),
		"bank_source_main": lv_entry.get("_bank_source_main", ""),
		"bank_idx": lv_entry.get("_bank_idx", 0),
		"bank_tier": lv_entry.get("_bank_tier", ""),
		"bank_transform": lv_entry.get("_bank_transform", 0),
		"rating": lv_entry.get("rating", 0.0),
		"is_elo_delivery": is_elo_delivery,
		"eloRating": lv_entry.get("eloRating", -1.0) if is_elo_delivery else -1.0,
		"_elo_e": lv_entry.get("_elo_e", -1.0) if is_elo_delivery else -1.0,
		"_elo_k": lv_entry.get("_elo_k", -1.0) if is_elo_delivery else -1.0,
		"_elo_player_rating": lv_entry.get("_elo_player_rating", -1.0) if is_elo_delivery else -1.0,
		"_puzzle_id": lv_entry.get("_puzzle_id", ""),
		"style_vector":
		lv_entry.get(
			"elo_v2_style_vector",
			{"stepHist": lv_entry.get("stepHist", {}), "stepOrderZ": lv_entry.get("stepOrderZ", [])}
		),
		"custom_color_map": lv_entry.get("colorMap", []),
		"patternRegions": lv_entry.get("patternRegions", []),
		"spRegion": lv_entry.get("spRegion", []),
		"kind": _level_kind,
		"_rec_qid": lv_entry.get("_rec_qid", ""),
		"_rec_decision_id": lv_entry.get("_rec_decision_id", ""),
		"_rec_slot_index": lv_entry.get("_rec_slot_index", -1),
		"_rec_rhythm_state": lv_entry.get("_rec_rhythm_state", ""),
		"_rec_selection_status": lv_entry.get("_rec_selection_status", ""),
		"_rec_fallback_reason": lv_entry.get("_rec_fallback_reason", ""),
		"_cc_delivery_index": lv_entry.get("_cc_delivery_index", -1),
		"_rec_intended_optimal_qid": lv_entry.get("_rec_intended_optimal_qid", ""),
		"_rec_is_explore": lv_entry.get("_rec_is_explore", false),
	}

	_level_config["pace_group"] = lv_entry.get("_bank_pace_group", 0)
	_level_config["pace_score"] = lv_entry.get("_bank_pace_score", 0.0)

	_level_config["pre_cat_swap_type"] = lv_entry.get(
		"_pre_cat_swap_type", PreCatDecider.PRE_TYPE_NONE
	)

	var _gs_strategy: int = GameState.get_current_strategy()
	var _gs_rank: int = LevelData.strategy_to_rank(_gs_strategy)
	var _qid: String = (
		"%s_%d" % [lv_entry.get("_bank_source", "regular"), lv_entry.get("_bank_idx", 0)]
	)
	var _daily_v2_group: int = ABTestManager.normal_level.value()
	if (
		_daily_v2_group
		in [
			NormalLevelConfig.VALUE_DAILY_FIRST_CEILING_MINUS_ONE,
			NormalLevelConfig.VALUE_DAILY_FIRST_R4,
			NormalLevelConfig.VALUE_DAILY_FIRST_COMBINED
		]
	):
		print(
			(
				"[DailyFirstEasyV2] group=%d level=%d current=R%d delivered=R%d qid=%s settlement_exempt=%s"
				% [
					_daily_v2_group,
					level_index,
					_gs_rank,
					lv_rank,
					_qid,
					str(GameState.is_current_level_daily_first_easy())
				]
			)
		)
	elif GameState.is_current_level_daily_first_easy():
		print(
			(
				"[DailyFirstEasy] level=%d 当前难度R%d, 触发首局降档: 实际难度R%d, qid=%s"
				% [level_index, _gs_rank, lv_rank, _qid]
			)
		)
	else:
		print("[DailyFirstEasy] level=%d 当前难度R%d, qid=%s" % [level_index, lv_rank, _qid])

	var strategy_steps: Array = lv_entry.get("_strategy_steps", [0, 0, 0, 0, 0])
	for i in range(5):
		_strategy_steps[i] = int(strategy_steps[i])
	_puzzle = {"regions": lv_int_regions, "solution": lv_sol_2d}

	var puzzle_id: String = str(lv_entry.get("_puzzle_id", ""))
	if puzzle_id.is_empty():
		push_error(
			"GamePage: LevelSelector returned entry without _puzzle_id, level=%d" % level_index
		)
		return false
	PuzzleSessionTracker.record(puzzle_id, level_index)
	RecentLevelDebugTracker.record(
		level_index,
		lv_sz,
		lv_rank,
		lv_entry.get("regionMap", []),
		_level_config["bank_source"],
		str(lv_entry.get("_iso_check", ""))
	)
	_apply_difficulty_level_text(level_index)

	GameState.clear_current_level_dirty()
	_nav_index = level_index
	_nav_total = 0
	return true


func _nl1170x_debug_tail(lv_entry: Dictionary, sz: int, _level_index: int) -> String:
	var nl: int = ABTestManager.normal_level.value()
	var hf: int = ABTestManager.hint_func.value()
	var r: int = int(lv_entry.get("r", 0))
	var steps: int = int(lv_entry.get("steps", 0))
	var baked: String = str(int(lv_entry["leadR1"])) if lv_entry.has("leadR1") else "-"

	var sol_grid: Array = _solution_to_bool_grid(lv_entry.get("solution", []), sz)
	if sol_grid.is_empty():
		return (
			" | dbg nl=%d hf=%d hint_steps=<no solution> leadR1_baked=%s r=%d r4/steps=%d/%d"
			% [nl, hf, baked, r, int(lv_entry.get("r4", 0)), steps]
		)

	var regions: Array = []
	for row in lv_entry.get("regionMap", []):
		var int_row: Array = []
		for v in row:
			int_row.append(int(v))
		regions.append(int_row)

	var kinds: Array[String] = HintEngine.replay_hint_steps(sz, regions, sol_grid, false)
	var lead: int = 0
	for k in kinds:
		if k == "M" or k == "1":
			lead += 1
		else:
			break
	return (
		" | dbg nl=%d hf=%d hint_steps=%s(n=%d) lead_M1=%d/sz%d leadR1_baked=%s r=%d r4/steps=%d/%d"
		% [
			nl,
			hf,
			",".join(kinds),
			kinds.size(),
			lead,
			sz,
			baked,
			r,
			int(lv_entry.get("r4", 0)),
			steps,
		]
	)


func _solution_to_bool_grid(sol: Array, sz: int) -> Array:
	if sz <= 0 or sol.size() != sz:
		return []
	var grid: Array = []
	for r in range(sz):
		var row: Array = []
		row.resize(sz)
		row.fill(false)
		grid.append(row)
	if sol[0] is Array:
		for r in range(sz):
			for c in range(sz):
				grid[r][c] = bool((sol[r] as Array)[c])
	else:
		for r in range(sz):
			var col: int = int(sol[r])
			if col < 0 or col >= sz:
				return []
			grid[r][col] = true
	return grid


func on_hide() -> void:
	_finish_rank_win_presentation(true)
	super.on_hide()

	_reset_flight_trails()

	_stop_cc_pattern_btn_entry_fade()

	_cancel_pending_entry_animation_wait()

	_cancel_late_ad_watch()

	var board_intro := $Root as BoardContainerCell_01
	_disconnect_entry_animation_callbacks(board_intro)
	_cancel_pattern_sweep_effect()

	if _pre_cat_fx != null:
		_pre_cat_fx.cancel()
	if _anim_player.is_playing():
		_anim_player.stop()
	if _active_toast != null:
		_active_toast.hide_toast()

	if _endgame_persist_timer != null:
		_endgame_persist_timer.stop()
	if _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		_flush_endgame_snapshot()
		_board_view.cell_state_changed.disconnect(_persist_endgame_snapshot)

	_reset_life_warning()

	_golden_fish_tutorial_card.reset_card()

	_reset_golden_fish_fly()


func _discard_level_on_digit_group_switch(params: Dictionary) -> void:
	var level_num: int = int(params.get("level_index", 0))
	if (
		level_num <= 0
		or params.get("bank_mode", false)
		or params.has("debug_config")
		or params.has("debug_prebuilt")
		or _level_kind != LevelKind.MAIN
	):
		return
	var current_group: int = ABTestManager.normal_level.value()
	var previous_group: int = GameState.get_latest_selected_normal_level_group(level_num)
	if (
		previous_group < 0
		or previous_group == current_group
		or (previous_group != 12004 and current_group != 12004)
	):
		return
	var snapshot: Dictionary = GameState.get_endgame_snapshot()
	var has_snapshot: bool = int(snapshot.get("level", -1)) == level_num
	var has_retry: bool = not GameState.get_retry_puzzle(level_num).is_empty()
	if not has_snapshot and not has_retry:
		return
	if has_snapshot and _validate_endgame_snapshot(snapshot):
		var snapshot_size: int = int(snapshot.get("size", 0))
		if (
			snapshot_size > 0
			and QueendokuCore.is_complete(
				_reconstruct_board_for_check(snapshot, snapshot_size),
				snapshot_size,
				snapshot.get("regionMap", [])
			)
		):
			return
	if has_snapshot:
		GameState.clear_endgame_snapshot()
	if has_retry:
		GameState.clear_retry_puzzle()
	GameState.clear_current_level_dirty()
	params["_tracker_status"] = Tracker.GameStatus.NEW


func _try_begin_returnee_event(params: Dictionary) -> void:
	var level_num: int = int(params.get("level_index", 0))
	if (
		level_num <= 30
		or params.get("bank_mode", false)
		or params.has("debug_config")
		or params.has("debug_prebuilt")
	):
		return
	var group: int = ABTestManager.normal_level.value()
	if not GameState.should_begin_returnee_event(group):
		return
	var snapshot: Dictionary = GameState.get_endgame_snapshot()
	if (
		ABTestManager.normal_endgame_save.is_enabled()
		and not snapshot.is_empty()
		and int(snapshot.get("level", -1)) == level_num
		and _validate_endgame_snapshot(snapshot)
	):
		var size: int = int(snapshot.get("size", 0))
		if (
			size > 0
			and QueendokuCore.is_complete(
				_reconstruct_board_for_check(snapshot, size), size, snapshot.get("regionMap", [])
			)
		):
			return
	var lower: int = LevelData.level_min_rank(level_num)
	var upper: int = LevelData.resolve_strategy(level_num, GameState.get_current_strategy(), 5)
	upper = mini(upper, 4 if level_num >= 51 else (3 if level_num >= 21 else 2))
	GameState.begin_returnee_event(group, lower, upper)
	GameState.mark_stale_endgame_discarded()
	GameState.clear_endgame_snapshot()
	GameState.clear_retry_puzzle()
	GameState.clear_current_level_dirty()
	params["_tracker_status"] = Tracker.GameStatus.NEW
	if SpecialProvider.SPECIAL_LEVELS.has(level_num):
		params["_returnee_ignore_special"] = true


func _will_discard_stale_endgame_snapshot(params: Dictionary) -> bool:
	if not StaleEndgameGate.is_pending_stale_discard():
		return false
	var lv: int = params.get("level_index", 0)
	if (
		lv <= 0
		or params.get("bank_mode", false)
		or params.has("debug_config")
		or params.has("debug_prebuilt")
	):
		return false
	var snap: Dictionary = GameState.get_endgame_snapshot()
	return (
		not snap.is_empty()
		and int(snap.get("level", -1)) == lv
		and not _is_unplayed_color_challenge_snapshot(snap)
	)


func _is_unplayed_color_challenge_snapshot(snapshot: Dictionary) -> bool:
	if not LevelKind.is_color_challenge(_level_kind):
		return false
	if not LevelKind.is_color_challenge(int(snapshot.get("kind", LevelKind.default_kind()))):
		return false

	return not bool(snapshot.get("continue_clock_started", true))


func _try_consume_endgame_snapshot(params: Dictionary) -> bool:
	var lv_idx: int = params.get("level_index", 0)
	if (
		lv_idx <= 0
		or params.get("bank_mode", false)
		or params.has("debug_config")
		or params.has("debug_prebuilt")
	):
		return false

	if not ABTestManager.normal_endgame_save.is_enabled():
		if not GameState.get_endgame_snapshot().is_empty():
			GameState.clear_endgame_snapshot()
		return false
	var snapshot: Dictionary = GameState.get_endgame_snapshot()
	if snapshot.is_empty():
		return false
	if not _validate_endgame_snapshot(snapshot):
		GameState.clear_endgame_snapshot()
		return false
	var snap_level: int = int(snapshot["level"])
	if snap_level != GameState.get_current_level() or snap_level != lv_idx:
		var snap_app_version: Variant = snapshot.get("app_version", null)
		if (
			OS.has_feature("rel")
			and snap_app_version != null
			and _version_at_least(str(snap_app_version), "1.12.0")
		):
			push_error(
				(
					"[Endgame] snapshot level=%d mismatch (current_level=%d, entry=%d), clearing"
					% [snap_level, GameState.get_current_level(), lv_idx]
				)
			)
		GameState.clear_endgame_snapshot()
		return false
	var lives_left: int = int(snapshot["lives"])
	var sz: int = int(snapshot["size"])
	if lives_left <= 0:
		print("[Endgame] lives==0, clear snapshot and fall through to retry/fresh")
		Tracker.reset_round_stats()
		GameState.clear_endgame_snapshot()
		return false

	var data_err: String = _validate_snapshot_data(snapshot, sz, snap_level)
	if not data_err.is_empty():
		push_error("[Endgame] snapshot data integrity error: " + data_err)
		GameState.clear_endgame_snapshot()
		return false
	var board: Array = _reconstruct_board_for_check(snapshot, sz)
	if QueendokuCore.is_complete(board, sz, snapshot["regionMap"]):
		print("[Endgame] snapshot is_complete, advancing level=%d and re-entering" % snap_level)

		var snap_kind: int = int(snapshot.get("kind", LevelKind.default_kind()))

		var restore_rank: int = int(snapshot.get("r", 0))
		var restore_diffi: int = int(
			snapshot.get("diffi", 1 if LevelSelector.is_hard_level(snap_level) else 0)
		)
		_capture_elo_v2_completed_snapshot_facts(snapshot)

		if LevelKind.is_golden_fish(snap_kind) or LevelKind.is_color_challenge(snap_kind):
			GameState.consume_comeback_main_win()

		GameState.on_level_won(
			snap_level,
			snap_kind,
			restore_rank,
			restore_diffi,
			lives_left == _life_cap,
			str(snapshot.get("last_action_local_date", ""))
		)

		if LevelKind.is_golden_fish(snap_kind):
			GameState.on_golden_fish_settled(true)

		elif LevelKind.is_color_challenge(snap_kind):
			GameState.on_color_challenge_settled()
		GameState.clear_endgame_snapshot()
		var new_params: Dictionary = params.duplicate()
		new_params["level_index"] = GameState.get_current_level()
		new_params["_tracker_status"] = Tracker.GameStatus.NEW
		on_show(new_params)
		return true

	var _nes: NormalEndgameSaveConfig = ABTestManager.normal_endgame_save
	var _pending_stale: bool = StaleEndgameGate.is_pending_stale_discard()
	if _pending_stale and _is_unplayed_color_challenge_snapshot(snapshot):
		GameState.mark_stale_endgame_discarded()
		print(
			(
				"[Endgame] stale: color challenge snapshot never played, restore as-is level=%d"
				% snap_level
			)
		)
	elif _pending_stale:
		GameState.clear_endgame_snapshot()

		GameState.mark_stale_endgame_discarded()

		if _nes.is_stale_new_easier():
			GameState.consume_daily_first_easy()
		var _snap_kind: int = int(snapshot.get("kind", LevelKind.default_kind()))
		var _snap_is_cc: bool = LevelKind.is_color_challenge(_snap_kind)
		if _nes.is_stale_restart_current():
			print(
				(
					"[Endgame] nes group2 stale-restart: discard snapshot, restart level=%d"
					% snap_level
				)
			)
			return false

		var _super_hard_rank: int = StaleEndgameGate.super_hard_stale_rank(snap_level, _snap_kind)
		if (
			_super_hard_rank <= 0
			and not _snap_is_cc
			and LevelData.is_special_level(snap_level)
			and _nes.value() != NormalEndgameSaveConfig.VALUE_STALE_NEW_EASIER_TWO_DAYS
		):
			print(
				(
					"[Endgame] nes group3 special level=%d: no downgrade, restart same as group2"
					% snap_level
				)
			)
			return false

		var _snap_rank: int = int(snapshot["r"])
		var _target_rank: int = (
			_super_hard_rank
			if _super_hard_rank > 0
			else max(LevelData.level_min_rank(snap_level), _snap_rank - 1)
		)
		if ABTestManager.normal_level.is_elo_v2_active() and not _snap_is_cc:
			GameState.abandon_elo_v2_attempt(snap_level)
		GameState.clear_retry_puzzle()
		print(
			(
				"[Endgame] nes group3 stale-new-easier: discard snapshot, new puzzle level=%d rank=%d (from r=%d)"
				% [snap_level, _target_rank, _snap_rank]
			)
		)
		var new_params3: Dictionary = params.duplicate()
		if _nes.value() == NormalEndgameSaveConfig.VALUE_STALE_NEW_EASIER_TWO_DAYS:
			GameState.begin_stale_new_easier_level(snap_level)
			new_params3["_returnee_fresh"] = true
			new_params3["_returnee_ignore_special"] = true
		if _super_hard_rank > 0:
			new_params3["_returnee_ignore_special"] = true
		new_params3["level_index"] = snap_level
		new_params3["rank_override"] = _target_rank

		if _snap_is_cc:
			new_params3["_cc_stale"] = {
				"size": sz, "rank": ColorChallengeGate.stale_easier_rank(_snap_rank)
			}
		new_params3["_stale_new_easier"] = true
		new_params3["_tracker_status"] = Tracker.GameStatus.NEW
		new_params3.erase("bank_mode")
		on_show(new_params3)
		return true
	print(
		(
			"[Endgame] restoring in-progress snapshot level=%d lives=%d cats=%d marks=%d errors=%d"
			% [
				snap_level,
				lives_left,
				(snapshot.get("placed_cats", []) as Array).size(),
				(snapshot.get("marks", []) as Array).size(),
				(snapshot.get("errors", []) as Array).size(),
			]
		)
	)
	var is_elo_delivery: bool = bool(snapshot.get("is_elo_delivery", false))
	if ABTestManager.normal_level.is_elo_v2_active():
		is_elo_delivery = is_elo_delivery and _has_valid_elo_v2_rating(snapshot)
	var restore_params: Dictionary = {
		"bank_mode": true,
		"bank_size": sz,
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
		"is_elo_delivery": is_elo_delivery,
		"eloRating": snapshot.get("eloRating", -1.0),
		"_elo_e": snapshot.get("_elo_e", -1.0),
		"_elo_k": snapshot.get("_elo_k", -1.0),
		"_elo_player_rating": snapshot.get("_elo_player_rating", -1.0),
		"_puzzle_id": snapshot.get("_puzzle_id", ""),
		"style_vector": snapshot.get("style_vector", {}),
		"spRegion": snapshot.get("spRegion", []),
		"retry_level": snap_level,
		"restore_state":
		{
			"placed_cats": snapshot.get("placed_cats", []),
			"marks": snapshot.get("marks", []),
			"errors": snapshot.get("errors", []),
			"pre_type": str(snapshot.get("pre_type", PreCatDecider.PRE_TYPE_NONE)),
		},
		"restore_lives": lives_left,
		"restore_kind": int(snapshot.get("kind", LevelKind.default_kind())),
		"restore_cc_delivery_index": int(snapshot.get("cc_delivery_index", 0)),
		"endgame_restore": true,
		"restore_score":
		int(
			snapshot.get(
				"score",
				(
					snapshot.get("se_score", 0)
					if bool(snapshot.get("se_enabled", false))
					else snapshot.get("combo_score", 0)
				)
			)
		),
		"restore_combo": int(snapshot.get("combo", snapshot.get("combo_count", 0))),
		"restore_max_combo": int(snapshot.get("max_combo", snapshot.get("combo_count", 0))),
		"restore_se_count": int(snapshot.get("se_count", 0)),
		"restore_se_last_step": int(snapshot.get("se_last_step", -1)),
		"restore_cat_streak": int(snapshot.get("cat_streak", 0)),
		"restore_cross_at_first_cat": int(snapshot.get("cross_at_first_cat", -1)),
		"restore_restart_count": int(snapshot.get("restart_count", 0)),
		"restore_revive_count": int(snapshot.get("revive_count", 0)),
		"restore_in_game_sec": float(snapshot.get("in_game_sec", 0.0)),
		"restore_continue_play_sec": float(snapshot.get("continue_play_sec", 0.0)),
		"restore_continue_clock_started": bool(snapshot.get("continue_clock_started", false)),
		"restore_operable_sec": float(snapshot.get("operable_sec", 0.0)),
		"restore_cat_toast": snapshot.get("cat_toast", {}),
		"restore_near_death_fired": bool(snapshot.get("near_death_fired", false)),
		"restore_near_death_level_key": str(snapshot.get("near_death_level_key", "")),
		"restore_near_death_blocked": bool(snapshot.get("near_death_blocked", false)),
		"restore_wrong_zone": snapshot.get("wrong_zone", {}),
		"restore_cat_progress_rotate": int(snapshot.get("cat_progress_rotate_start", -1)),
		"restore_like_hand_triggered_count": int(snapshot.get("like_hand_triggered_count", 0)),
		"restore_missed_cross_triggered_cats": snapshot.get("missed_cross_triggered_cats", []),
		"restore_manually_x_marked_cells": snapshot.get("manually_x_marked_cells", []),
		"_tracker_status": Tracker.GameStatus.CONTINUE,
		"from_direct_open": _is_direct_open_session,
		"from_tutorial": _is_from_tutorial,
	}
	GameState.clear_current_level_dirty()
	on_show(restore_params)
	return true


func _version_at_least(a: String, b: String) -> bool:
	var pa: PackedStringArray = a.split(".")
	var pb: PackedStringArray = b.split(".")
	var n: int = max(pa.size(), pb.size())
	for i in range(n):
		var va: int = int(pa[i]) if i < pa.size() else 0
		var vb: int = int(pb[i]) if i < pb.size() else 0
		if va != vb:
			return va > vb
	return true


func _is_locked_puzzle_hard_neighbor_eased(level: int) -> bool:
	var locked: Dictionary = GameState.get_retry_puzzle(level)
	return bool(locked.get(RetryPuzzleBuilder.KEY_HARD_NEIGHBOR_EASED, false))


func _has_user_progress_in_endgame_snapshot(level: int) -> bool:
	var snapshot: Dictionary = GameState.get_endgame_snapshot()
	if snapshot.is_empty():
		return false
	if int(snapshot.get("level", 0)) != level:
		return false
	if int(snapshot.get("lives", 0)) <= 0:
		return false

	var prefill_positions: Array = snapshot.get("prefill_positions", [])
	if not prefill_positions.is_empty():
		var sol_1d: Array = snapshot.get("solution", [])
		if not sol_1d.is_empty():
			var all_valid: bool = true
			for pos: Variant in prefill_positions:
				var r: int = int((pos as Array)[0])
				var c: int = int((pos as Array)[1])
				if not (r >= 0 and r < sol_1d.size() and int(sol_1d[r]) == c):
					all_valid = false
					break
			if all_valid:
				return true
	var prefill_count: int = prefill_positions.size()
	var user_cats: int = (snapshot.get("placed_cats", []) as Array).size() - prefill_count
	var user_marks: int = (snapshot.get("marks", []) as Array).size()
	var user_errors: int = (snapshot.get("errors", []) as Array).size()
	return user_cats > 0 or user_marks > 0 or user_errors > 0


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
		push_error(
			(
				"[Endgame] snapshot regionMap size mismatch: expected sz=%d got %d"
				% [sz, (rm as Array).size() if rm is Array else -1]
			)
		)
		return false
	for row in rm as Array:
		if not (row is Array) or (row as Array).size() != sz:
			push_error("[Endgame] snapshot regionMap row size mismatch: expected sz=%d" % sz)
			return false
	var sol = snapshot["solution"]
	if not (sol is Array) or (sol as Array).size() != sz:
		push_error(
			(
				"[Endgame] snapshot solution size mismatch: expected sz=%d got %d"
				% [sz, (sol as Array).size() if sol is Array else -1]
			)
		)
		return false
	return true


func _validate_snapshot_data(snapshot: Dictionary, sz: int, snap_level: int) -> String:
	var sol_arr: Array = snapshot["solution"] as Array
	for r: int in range(sz):
		var c: int = int(sol_arr[r])
		if c < 0 or c >= sz:
			return "solution col OOB: r=%d c=%d sz=%d level=%d" % [r, c, sz, snap_level]
	for pos: Variant in snapshot.get("placed_cats", []):
		var r: int = int((pos as Array)[0])
		var c: int = int((pos as Array)[1])
		if r < 0 or r >= sz or c < 0 or c >= sz or int(sol_arr[r]) != c:
			return "cat at non-solution cell (%d,%d) level=%d" % [r, c, snap_level]
	return ""


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

	if not ABTestManager.normal_endgame_save.is_enabled():
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


func _prepare_start_interstitial_flow() -> void:
	_entry_anim_schedule_ts = Time.get_ticks_msec()

	_cancel_pending_entry_animation_wait()

	_cancel_late_ad_watch()


func _show_immediate_start_interstitial(ad_position: String, elig: Dictionary) -> void:
	var effective_elig: Dictionary = elig
	if elig.get("replace_with_subscription", false):
		if _show_subscription_instead_of_interstitial(ad_position, elig):
			_pause_entry_anim_for_fullscreen()
			return
		effective_elig = elig_without_replace_flag(elig)
	if not _try_show_start_interstitial(ad_position, effective_elig):
		_start_entry_animation()
		return
	_pause_entry_anim_for_fullscreen()
	_install_entry_anim_ad_wait()


func _pause_entry_anim_for_fullscreen() -> void:
	_anim_player.play("Appear")
	_anim_player.seek(0.0, true)
	_anim_player.pause()
	_entry_anim_pending_state = {"done": false}


func _install_entry_anim_ad_wait() -> void:
	if _entry_anim_pending_state == null:
		_entry_anim_pending_state = {"done": false}

	_entry_anim_waiting_ad = true
	_entry_anim_ad_error_cb = func(pid: String, msg: String) -> void:
		if pid != AdPlacement.INTERSTITIAL:
			return
		_invoke_entry_ad_resume("ad_error")
	UniKitManager.ad_error_occurred.connect(_entry_anim_ad_error_cb)

	_entry_anim_ad_closed_cb = func(pid: String) -> void:
		if pid != AdPlacement.INTERSTITIAL:
			return
		_invoke_entry_ad_resume("ad_closed")
	UniKitManager.ad_closed.connect(_entry_anim_ad_closed_cb)
	_arm_entry_ad_show_confirm()


func _invoke_entry_ad_resume(source: String) -> void:
	if _entry_ad_resume.is_null():
		_fire_entry_anim(source)
		return
	var resume: Callable = _entry_ad_resume
	_entry_ad_resume = Callable()
	resume.call(source)


func _show_deferred_start_interstitial(params: Dictionary, ad_position: String) -> void:
	_entry_anim_pending_state = {"done": false}
	var elig: Dictionary = await _eval_start_interstitial(params, ad_position)
	if not is_showing():
		_cancel_pending_entry_animation_wait()
		return

	if elig.get("replace_with_subscription", false):
		_cancel_pending_entry_animation_wait()
		_show_immediate_start_interstitial(ad_position, elig)
		return
	if not elig.get("eligible", false):
		_cancel_pending_entry_animation_wait()
		_start_entry_animation()
		return

	_place_board_without_intro()
	_prepare_pattern_sweep_effect()

	_anim_player.play("Appear")

	await get_tree().create_timer(_INTER_DELAY_AFTER_BOARD_SEC).timeout
	if not is_showing():
		_cancel_pending_entry_animation_wait()
		return
	if not _try_show_start_interstitial(ad_position, elig):
		_cancel_pending_entry_animation_wait()
		_on_board_intro_pattern_ready()
		return
	_install_entry_anim_ad_wait()
	var state := {"done": false}
	_inter_timing_tail_state = state
	_entry_ad_resume = func(_source: String) -> void: _cancel_pending_entry_animation_wait()
	var lock_seq_at_skip: int = _entry_btn_lock_seq

	while not state.done:
		await get_tree().process_frame

	if lock_seq_at_skip != _entry_btn_lock_seq or not is_showing():
		return

	_on_board_intro_pattern_ready()


func _place_board_without_intro() -> void:
	_entry_anim_skipped = true
	_board_view.visible = true
	_board_view.on_board_entry_started(0.0)
	var board_intro := $Root as BoardContainerCell_01
	if board_intro != null:
		board_intro.set_auto_trigger(false)
		_disconnect_entry_animation_callbacks(board_intro)
		_reveal_board_container(board_intro)


func _reveal_board_container(board_intro: BoardContainerCell_01) -> void:
	if not (board_intro.board_view is CanvasItem):
		return
	var board_container: CanvasItem = board_intro.board_view as CanvasItem
	var col: Color = board_container.modulate
	col.a = 1.0
	board_container.modulate = col


func _on_interstitial_subscription_closed(
	ad_position: String, elig: Dictionary, should_play_interstitial: bool
) -> bool:
	var shown: bool = super._on_interstitial_subscription_closed(
		ad_position, elig, should_play_interstitial
	)
	if shown:
		_install_entry_anim_ad_wait()
	else:
		_entry_anim_await_stack_top = true
	return shown


func on_stack_top() -> void:
	super.on_stack_top()
	if not _entry_anim_await_stack_top:
		return
	_entry_anim_await_stack_top = false
	_invoke_entry_ad_resume("interstitial_sub_closed")


func _fire_entry_anim(source: String) -> void:
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
	_start_entry_animation()


func _on_application_focus_in() -> void:
	super._on_application_focus_in()
	if _entry_anim_pending_state == null:
		if _late_ad_lock_active:
			_release_late_ad_lock("focus_in")
		return

	if not _entry_anim_waiting_ad:
		print("[Game] focus_in 忽略：本次入场动画不在等广告（组2 订阅页那条链由 on_stack_top 收尾）")
		return
	_invoke_entry_ad_resume("focus_in")


func _on_application_focus_out() -> void:
	super._on_application_focus_out()

	if _board_view == null:
		return
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		return
	if _endgame_persist_timer != null:
		_endgame_persist_timer.stop()
	_flush_endgame_snapshot()
	print(
		(
			"[Endgame] focus_out flush snapshot, in_game_sec=%.1fs (切后台落盘,防杀端丢时长)"
			% float(_like_hand_state.get("in_game_sec", 0.0))
		)
	)


func _cancel_pending_entry_animation_wait() -> void:
	_entry_anim_await_stack_top = false
	_entry_anim_waiting_ad = false
	_entry_ad_resume = Callable()

	if not _inter_timing_tail_state.is_empty():
		_inter_timing_tail_state["done"] = true
		_inter_timing_tail_state = {}

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
	_disarm_entry_ad_show_confirm()


func _arm_entry_ad_show_confirm() -> void:
	if not UniKitManager.is_ad_impression_signal_available():
		return
	_disarm_entry_ad_show_confirm()
	_entry_anim_ad_impression_cb = func(data: Dictionary) -> void:
		if String(data.get("placement_id", "")) != AdPlacement.INTERSTITIAL:
			return

		_disarm_entry_ad_show_confirm()
	UniKitManager.ad_impression_received.connect(_entry_anim_ad_impression_cb)
	_entry_anim_show_confirm_timer = create_countdown(
		ENTRY_AD_SHOW_CONFIRM_SEC, _on_entry_ad_show_confirm_timeout
	)


func _on_entry_ad_show_confirm_timeout() -> void:
	_entry_anim_show_confirm_timer = null
	if _entry_anim_pending_state == null or _entry_anim_pending_state.get("done", false):
		return
	print("[Inter] %.1fs 内未收到 ad impression → 判定插屏未上屏,主动恢复进关流程(防卡死)" % ENTRY_AD_SHOW_CONFIRM_SEC)
	_invoke_entry_ad_resume("no_ad_impression")

	_arm_late_ad_watch()


func _disarm_entry_ad_show_confirm() -> void:
	if not _entry_anim_ad_impression_cb.is_null():
		if UniKitManager.ad_impression_received.is_connected(_entry_anim_ad_impression_cb):
			UniKitManager.ad_impression_received.disconnect(_entry_anim_ad_impression_cb)
		_entry_anim_ad_impression_cb = Callable()
	if _entry_anim_show_confirm_timer != null:
		remove_timer(_entry_anim_show_confirm_timer)
		_entry_anim_show_confirm_timer = null


func _arm_late_ad_watch() -> void:
	if not UniKitManager.is_ad_impression_signal_available():
		return
	_cancel_late_ad_watch()
	_late_ad_impression_cb = func(data: Dictionary) -> void:
		if String(data.get("placement_id", "")) != AdPlacement.INTERSTITIAL:
			return
		_on_late_ad_impression()
	UniKitManager.ad_impression_received.connect(_late_ad_impression_cb)


func _on_late_ad_impression() -> void:
	if _late_ad_lock_active:
		return
	_late_ad_lock_active = true
	print("[Inter] 迟到的 ad impression 到达(超时判定后广告仍上屏)→ 重新锁交互,等广告关闭")
	_set_late_ad_interaction_locked(true)
	_late_ad_closed_cb = func(pid: String) -> void:
		if pid != AdPlacement.INTERSTITIAL:
			return
		_release_late_ad_lock("ad_closed")
	UniKitManager.ad_closed.connect(_late_ad_closed_cb)
	_late_ad_lock_timer = create_countdown(LATE_AD_LOCK_TIMEOUT_SEC, _on_late_ad_lock_timeout)


func _on_late_ad_lock_timeout() -> void:
	_late_ad_lock_timer = null
	_release_late_ad_lock("timeout")


func _release_late_ad_lock(source: String) -> void:
	if not _late_ad_lock_active:
		return
	_late_ad_lock_active = false
	print("[Inter] 迟到锁解除(source=%s)" % source)
	_set_late_ad_interaction_locked(false)
	_cancel_late_ad_watch()


func _cancel_late_ad_watch() -> void:
	if _late_ad_lock_active:
		_late_ad_lock_active = false
		_set_late_ad_interaction_locked(false)
	if not _late_ad_impression_cb.is_null():
		if UniKitManager.ad_impression_received.is_connected(_late_ad_impression_cb):
			UniKitManager.ad_impression_received.disconnect(_late_ad_impression_cb)
		_late_ad_impression_cb = Callable()
	if not _late_ad_closed_cb.is_null():
		if UniKitManager.ad_closed.is_connected(_late_ad_closed_cb):
			UniKitManager.ad_closed.disconnect(_late_ad_closed_cb)
		_late_ad_closed_cb = Callable()
	if _late_ad_lock_timer != null:
		remove_timer(_late_ad_lock_timer)
		_late_ad_lock_timer = null


func _set_late_ad_interaction_locked(locked: bool) -> void:
	if _entry_anim_playing:
		return
	if _board_view != null:
		_board_view.set_touch_enabled(not locked)
	if locked:
		_lock_entry_buttons()
	else:
		_unlock_entry_buttons()


func _prepare_pattern_sweep_effect() -> void:
	_pattern_sweep_prepared = false
	if not ABTestManager.board_intro.is_pattern_sweep():
		return
	if _entry_sp_region_ids.is_empty() or _puzzle.get("regions", []).is_empty():
		return
	if _pattern_sweep_overlay == null:
		_pattern_sweep_overlay = _BOARD_PATTERN_SWEEP_OVERLAY_SCRIPT.new()
		_pattern_sweep_overlay.name = "BoardPatternSweepOverlay"
		add_child(_pattern_sweep_overlay)
	_pattern_sweep_prepared = _pattern_sweep_overlay.configure(
		_board_view, _puzzle["regions"], _entry_sp_region_ids
	)


func _on_board_intro_pattern_ready() -> void:
	if not _pattern_sweep_prepared or _pattern_sweep_overlay == null:
		_on_appear_animation_finished()
		return
	if not _pattern_sweep_overlay.effect_finished.is_connected(_on_appear_animation_finished):
		_pattern_sweep_overlay.effect_finished.connect(
			_on_appear_animation_finished, CONNECT_ONE_SHOT
		)
	_pattern_sweep_overlay.play()


func _disconnect_entry_animation_callbacks(board_intro: BoardContainerCell_01) -> void:
	if board_intro != null:
		if board_intro.animation_finished.is_connected(_on_appear_animation_finished):
			board_intro.animation_finished.disconnect(_on_appear_animation_finished)
		if board_intro.animation_finished.is_connected(_on_board_intro_pattern_ready):
			board_intro.animation_finished.disconnect(_on_board_intro_pattern_ready)
	if (
		_pattern_sweep_overlay != null
		and _pattern_sweep_overlay.effect_finished.is_connected(_on_appear_animation_finished)
	):
		_pattern_sweep_overlay.effect_finished.disconnect(_on_appear_animation_finished)


func _cancel_pattern_sweep_effect() -> void:
	_pattern_sweep_prepared = false
	if _pattern_sweep_overlay == null:
		return
	if _pattern_sweep_overlay.effect_finished.is_connected(_on_appear_animation_finished):
		_pattern_sweep_overlay.effect_finished.disconnect(_on_appear_animation_finished)
	_pattern_sweep_overlay.cancel()


func _start_entry_animation() -> void:
	var board_intro := $Root as BoardContainerCell_01
	if board_intro != null:
		_apply_grid_ui_entry_anim(board_intro)
		_prepare_pattern_sweep_effect()
		board_intro.play()
	_play_entry_animation()


func _play_entry_animation() -> void:
	_board_view.visible = true
	var board_intro := $Root as BoardContainerCell_01
	_board_view.on_board_entry_started(_grid_intro_sync_total(board_intro))
	_anim_player.play("Appear")
	SoundManager.play(SoundManager.Kind.BOARD_ENTER)
	if board_intro != null:
		if _pattern_sweep_prepared:
			if not board_intro.animation_finished.is_connected(_on_board_intro_pattern_ready):
				board_intro.animation_finished.connect(
					_on_board_intro_pattern_ready, CONNECT_ONE_SHOT
				)
		elif not board_intro.animation_finished.is_connected(_on_appear_animation_finished):
			board_intro.animation_finished.connect(_on_appear_animation_finished, CONNECT_ONE_SHOT)


func _on_appear_animation_finished() -> void:
	super._on_appear_animation_finished()

	if not _entry_anim_skipped:
		VibrateManager.play_at(VibrateManager.Pos.BOARD_INTRO)

	var lock_seq: int = _entry_btn_lock_seq

	if _try_show_golden_fish_life_tutorial():
		await bubble_tutorial_finished

		if lock_seq != _entry_btn_lock_seq or not is_showing():
			return

		_golden_fish_tutorial_card.show_card()
		await _golden_fish_tutorial_card.dismissed
		if lock_seq != _entry_btn_lock_seq or not is_showing():
			return

		Tracker.track_golden_fish_guide_end(
			int(_level_config.get("level", 0)),
			float(Time.get_ticks_msec() - _gf_guide_start_ms) / 1000.0
		)

	_try_show_start_toast()

	if _pre_cat_fx != null and _pre_cat_fx.is_pending():
		await _wait_start_toast_hidden_if_any()

		if lock_seq != _entry_btn_lock_seq or not is_showing():
			return
		await _pre_cat_fx.run()
		if lock_seq != _entry_btn_lock_seq or not is_showing():
			return

		_apply_cat_found_grid_dim(true)

	_unlock_entry_buttons_after_toast(lock_seq)

	if _late_ad_lock_active:
		_set_late_ad_interaction_locked(true)


func _is_board_all_empty() -> bool:
	var sz: int = _board_view.get_puzzle_size()
	return sz > 0 and _board_view.count_empty_cells() == sz * sz


func _is_hard_style_level(lv: int) -> bool:
	return LevelSelector.is_hard_level(lv) or LevelSelector.is_super_hard_level(lv)


func _try_show_start_toast() -> void:
	var level_num: int = _level_config.get("level", 0)
	if level_num <= 0 or bool(_level_config.get("is_daily", false)):
		return

	if _is_from_tutorial:
		_show_start_toast_exclusive(_normal_toast, {"text_key": "GAME_TOAST_TUTORIAL_PASSED"})
		return

	var daily_first_config: DailyFirstWinEncourageConfig = ABTestManager.daily_first_win_encourage
	var main_win_today: bool = GameState.has_main_win_today()
	var entry_seen_today: bool = GameState.has_daily_first_win_entry_seen_today()
	var is_first_entry: bool = daily_first_config.is_first_eligible_entry(
		level_num, _level_kind, main_win_today, entry_seen_today
	)
	var show_goal: bool = daily_first_config.has_goal_toast()
	if not OS.has_feature("rel"):
		print(
			(
				"[DailyFirstWin] entry lv=%d kind=%d group=%d won_today=%s seen_today=%s eligible=%s goal=%s"
				% [
					level_num,
					_level_kind,
					int(daily_first_config.value()),
					str(main_win_today),
					str(entry_seen_today),
					str(is_first_entry),
					str(show_goal)
				]
			)
		)
	if level_num > 1 and not main_win_today and not entry_seen_today:
		GameState.mark_daily_first_win_entry_seen_today()

	var is_comeback_entry: bool = false
	if LevelKind.is_golden_fish(_level_kind) or LevelKind.is_color_challenge(_level_kind):
		GameState.consume_comeback_main_win()
	else:
		is_comeback_entry = GameState.claim_comeback_start_level(level_num)
	var board_all_empty: bool = _is_board_all_empty()
	if not _is_direct_open_session and (not board_all_empty or level_num < 11):
		return

	if level_num >= 11 and board_all_empty:
		if LevelKind.is_golden_fish(_level_kind):
			_show_start_toast_exclusive(_golden_fish_toast, {})
			return
		if LevelKind.is_color_challenge(_level_kind):
			var special_toast: BaseGameToast = _ensure_color_challenge_toast() as BaseGameToast
			if special_toast != null:
				_show_start_toast_exclusive(special_toast, {})
			return
	if is_comeback_entry:
		var comeback_key: StringName = ABTestManager.comeback_func.get_start_text_key()
		if not comeback_key.is_empty():
			_show_start_toast_exclusive(
				_hard_toast if _is_hard_style_level(level_num) else _normal_toast,
				{
					"text_key": comeback_key,
					"fallback_text": "Ready for a comeback? You've got this!",
				}
			)
			return
	if is_first_entry and show_goal:
		var goal_text_key: StringName = daily_first_config.pick_goal_text_key()
		_show_start_toast_exclusive(
			_hard_toast if _is_hard_style_level(level_num) else _normal_toast,
			{"text_key": goal_text_key}
		)
		if not OS.has_feature("rel"):
			print("[DailyFirstWin] goal shown key=%s" % goal_text_key)
		return

	if _is_direct_open_session:
		_show_start_toast_exclusive(
			_hard_toast if _is_hard_style_level(level_num) else _normal_toast,
			{"text_key": "GAME_TOAST_CONTINUE_UNFINISHED"}
		)
		return
	var is_hard: bool = _is_hard_style_level(level_num)
	var is_first_try: bool = _toast_first_try_hint
	var last_clean: bool = GameState.was_last_level_clean_win()

	var is_special_trigger: bool = (not is_hard) and last_clean and is_first_try
	var group: int = NormalStartToastTextConfig.VALUE_G2_SOCIAL_PROOF
	var kind: String
	if is_special_trigger:
		kind = "special"
	elif is_first_try:
		kind = "first"
	else:
		kind = "retry"
	var pick: Dictionary = StartToastTextPool.resolve(group, kind, is_hard, level_num)
	_show_start_toast_exclusive(
		_hard_toast if is_hard else _normal_toast,
		{
			"text_key": pick.text_key,
			"pct_str": pick.pct_str,
		}
	)


func _show_start_toast_exclusive(target: BaseGameToast, params: Dictionary) -> void:
	if target == null:
		return

	if target == _hard_toast:
		params = params.duplicate()
		params["super_hard"] = LevelSelector.is_super_hard_level(_level_config.get("level", 0))
	for t: BaseGameToast in [_normal_toast, _hard_toast, _golden_fish_toast]:
		if t != target and t != null and t.visible:
			t.hide_toast()
	_active_toast = target
	_active_toast.show_toast(params)


func _on_return_bank_btn_pressed() -> void:
	_reset_game_barrages()
	UIManager.show_ui(UiName.BANK)
	UIManager.hide_ui(UiName.GAME)


func _on_gear_btn_pressed() -> void:
	if _is_complete:
		return
	_reset_game_barrages()
	Tracker.track_btn_click(Tracker.Btn.BACK, self)
	_clock_timer.stop()

	_exit_draft_mode_and_clear()
	_clear_draft_rollback_state()

	var lv: int = _level_config.get("level", 0)
	if lv > 0:
		GameState.mark_current_level_dirty()

	RankActivityManager.notify_level_exit()
	UIManager.hide_all_except([UiName.HOME])
	UIManager.show_ui(UiName.HOME)


func _on_restart_requested() -> void:
	_reset_game_barrages()
	_score_model.reset_all()
	_se_count = 0

	RankActivityManager.notify_level_restart()

	_destroy_banner()

	if _endgame_persist_timer != null and _endgame_persist_timer.time_left > 0.0:
		_endgame_persist_timer.stop()

	var lv: int = _level_config.get("level", 0)
	LevelOps.confirm_level_failed_main(
		_build_game_end_params(Tracker.GameResult.QUIT), lv, _level_kind
	)
	LevelOps.on_restart_click()
	if lv > 0:
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
				"prefill_positions": _prefill_positions_without_pre_cat(),
				"custom_color_map": _level_config.get("custom_color_map", []),
				"patternRegions": _level_config.get("patternRegions", []),
				"spRegion": _level_config.get("spRegion", []),
				"retry_level": lv,
				"bank_source": _level_config.get("bank_source", ""),
				"bank_source_main": _level_config.get("bank_source_main", ""),
				"bank_tier": _level_config.get("bank_tier", ""),
				"is_elo_delivery": bool(_level_config.get("is_elo_delivery", false)),
				"eloRating": _level_config.get("eloRating", -1.0),
				"_elo_e": _level_config.get("_elo_e", -1.0),
				"_elo_k": _level_config.get("_elo_k", -1.0),
				"_elo_player_rating": _level_config.get("_elo_player_rating", -1.0),
				"_puzzle_id": _level_config.get("_puzzle_id", ""),
				"style_vector": _level_config.get("style_vector", {}),
				"_cc_delivery_index": int(_level_config.get("_cc_delivery_index", -1)),
				"r1_steps": _strategy_steps[0],
				"r2_steps": _strategy_steps[1],
				"r3_steps": _strategy_steps[2],
				"r4_steps": _strategy_steps[3],
				"r5_steps": _strategy_steps[4],
				"_tracker_status": Tracker.GameStatus.RESTART,
			}
		)
	else:
		var bp: Dictionary = _level_config.get("bank_params", {})
		if not bp.is_empty():
			bp["_tracker_status"] = Tracker.GameStatus.RESTART
			on_show(bp)
		else:
			on_show({"_tracker_status": Tracker.GameStatus.RESTART})


const _WARN_LIFE_TEXT_KEY: String = "WARN_LIFE_LAST_CHANCE"

const _GF_TUT_LIFE_KEY: String = "GOLDEN_FISH_TUTORIAL_LIFE"

const _GF_TUT_LIFE_FALLBACK: String = "Only Golden Fish - Be careful!"


func _on_wrong_guess(
	r: int, c: int, skip_other_cats: bool = false, from_draft_apply: bool = false
) -> void:
	super._on_wrong_guess(r, c, skip_other_cats, from_draft_apply)

	if from_draft_apply:
		return

	_try_show_last_chance_warning()


func _try_show_last_chance_warning() -> void:
	if _lives != 1 or GameState.has_shown_warn_life():
		return

	_board_view.disable_touch_for(1.2)
	get_tree().create_timer(1.2).timeout.connect(_maybe_show_life_warning)


func _on_draft_apply_wrong_batch_done() -> void:
	_try_show_last_chance_warning()


func _maybe_show_life_warning() -> void:
	if GameState.has_shown_warn_life():
		return

	GameState.mark_warn_life_shown()
	_show_life_warning()


func _show_life_warning() -> void:
	_show_bubble_tutorial(_WARN_LIFE_TEXT_KEY)


func _show_bubble_tutorial(text_key: String) -> void:
	if _anim_tips == null:
		return
	if not _hint_mutex.try_acquire("warn_life"):
		return
	if _warn_label != null:
		_warn_label.text = text_key
	_warn_phase = 1
	_warn_click_allowed = false

	if _warn_overlay != null:
		_warn_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	_warn_tips.visible = true

	_align_warn_tail_to_heart()
	_anim_tips.play_section_with_markers("GenericPopup", "", "Mark")

	get_tree().create_timer(0.5).timeout.connect(func() -> void: _warn_click_allowed = true)


func _try_show_golden_fish_life_tutorial() -> bool:
	if not LevelKind.is_golden_fish(_level_kind):
		return false
	if GameState.has_golden_fish_tutorial_shown():
		return false

	GameState.mark_golden_fish_tutorial_shown()
	_gf_guide_start_ms = Time.get_ticks_msec()
	Tracker.track_golden_fish_guide_show(int(_level_config.get("level", 0)))
	_show_bubble_tutorial(_gf_tutorial_life_text())
	return true


func _gf_tutorial_life_text() -> String:
	var t: String = TranslationServer.translate(_GF_TUT_LIFE_KEY)
	return _GF_TUT_LIFE_FALLBACK if t == _GF_TUT_LIFE_KEY else t


func _align_warn_tail_to_heart() -> void:
	var heart_slot: Control = _life_bar.slot_at(0)
	if _warn_tail == null or heart_slot == null:
		return
	if not is_instance_valid(_warn_tail) or not is_instance_valid(heart_slot):
		return
	var bubble: Control = _warn_tail.get_parent() as Control
	if bubble == null:
		return
	var bubble_parent: Control = bubble.get_parent() as Control
	if bubble_parent == null:
		return

	var heart_center_x: float = heart_slot.get_global_rect().get_center().x
	var settled_origin_x: float = bubble_parent.global_position.x + bubble.position.x
	_warn_tail.position.x = heart_center_x - settled_origin_x


func _on_warn_anim_finished(anim_name: StringName) -> void:
	if anim_name != "GenericPopup" or _warn_phase != 2:
		return
	_warn_phase = 0
	_hint_mutex.release("warn_life")
	if _warn_overlay != null:
		_warn_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	bubble_tutorial_finished.emit()


func _is_pre_cat_fx_playing() -> bool:
	return _pre_cat_fx != null and _pre_cat_fx.is_playing()


func _should_skip_board_input() -> bool:
	if super._should_skip_board_input():
		return true

	if _pre_cat_fx != null and _pre_cat_fx.is_playing():
		return true

	if (
		_warn_overlay != null
		and is_instance_valid(_warn_overlay)
		and not is_zero_approx(_warn_overlay.color.a)
	):
		return true

	if (
		_golden_fish_tutorial_card != null
		and is_instance_valid(_golden_fish_tutorial_card)
		and _golden_fish_tutorial_card.visible
	):
		return true
	return false


func _input(event: InputEvent) -> void:
	if _warn_phase == 1:
		var is_press: bool = (
			(event is InputEventScreenTouch and event.pressed)
			or (event is InputEventMouseButton and event.pressed)
		)
		if is_press:
			if not _warn_click_allowed:
				get_viewport().set_input_as_handled()
				return
			_warn_phase = 2
			_anim_tips.play_section_with_markers("GenericPopup", "Mark", "")
			get_viewport().set_input_as_handled()
			return

	super._input(event)


func _reset_life_warning() -> void:
	var was_active: bool = _warn_phase != 0
	_hint_mutex.release("warn_life")
	_warn_phase = 0

	if _board_view != null and is_instance_valid(_board_view):
		_board_view.set_touch_enabled(true)
	if _anim_tips != null and _anim_tips.is_playing():
		_anim_tips.stop()
	if _warn_overlay != null:
		_warn_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
		_warn_overlay.color.a = 0.0
	if _warn_bubble != null:
		_warn_bubble.modulate.a = 0.0
	if _warn_mask != null:
		_warn_mask.modulate.a = 0.0
	if was_active:
		bubble_tutorial_finished.emit()


func _on_game_fail() -> void:
	if not _is_complete:
		_record_elo_v2_action("death")
		GameState.on_game_finished()
	_is_complete = true

	_reset_game_barrage_session_state()

	_exit_draft_mode_and_clear()
	_clock_timer.stop()

	pause_like_hand_clock()
	_stop_idle_tool_hint()
	_destroy_banner()
	Tracker.inc_stat("gamedie_count")

	RankActivityManager.notify_level_failed()

	ABTestManager.dye_at_game_fail_end()

	var _fail_end_params: Dictionary = _build_game_end_params(Tracker.GameResult.FAIL)
	Tracker.track_game_end(_fail_end_params)

	_last_fail_end_params = _fail_end_params

	_board_view.play_cat_cry_loop_all()
	VibrateManager.play_at(VibrateManager.Pos.GAME_FAIL)
	var lv: int = _level_config.get("level", 0)
	if lv > 0:
		GameState.on_level_failed(lv, _level_kind)

	var retry_params: Dictionary = {}
	if lv > 0:
		retry_params = GameState.get_retry_puzzle(lv).duplicate(true)
	else:
		var bp: Dictionary = _level_config.get("bank_params", {})
		if not bp.is_empty():
			retry_params = bp.duplicate()
		else:
			retry_params = {"level_index": 1}

	var _sz: int = _level_config.get("size", 4)
	var _placed: int = 0

	for _r in range(_sz):
		for _c in range(_sz):
			if _board_view.get_cell_state(_r, _c) == CellState.CAT:
				_placed += 1
	var remaining_cats: int = _sz - _placed
	var fail := (
		UIManager
		. show_ui(
			UiName.FAIL,
			{
				"level_config": _level_config,
				"retry_params": retry_params,
				"remaining_cats": remaining_cats,
				"cat_progress": build_cat_progress_snapshot(),
			}
		)
	)
	if fail != null and not fail.revive_requested.is_connected(_on_revive_requested):
		fail.revive_requested.connect(_on_revive_requested)
	if fail != null and not fail.revive_ad_started.is_connected(_on_revive_ad_started):
		fail.revive_ad_started.connect(_on_revive_ad_started)
	if fail != null and not fail.golden_fish_skipped.is_connected(_on_golden_fish_skipped):
		fail.golden_fish_skipped.connect(_on_golden_fish_skipped)


## 复活广告开始播放：先把猫恢复成待机动作
func _on_revive_ad_started() -> void:
	_board_view.revive_all_cat_to_idle()


func _on_revive_requested() -> void:
	UIManager.hide_ui(UiName.FAIL)

	RankActivityManager.notify_level_revived()

	_board_view.set_touch_enabled(true)
	_is_complete = false
	_revive_count += 1

	_block_near_death_for_current_level()

	if not _isolate_onefish_main_state():
		GameState.mark_dda_tool_or_revive_used()
		GameState.mark_dda_revive_used()
		GameState.inc_today_revive_count()
	_golden_fish_pre_cat.mark_revived(
		int(_level_config.get("level", 0)), _level_kind, _isolate_onefish_main_state()
	)
	GameState.inc_game_total_stat(Tracker.GameType.NORMAL, "revive_count")
	GameState.inc_game_total_stat(Tracker.GameType.NORMAL, "rv_count")

	if LevelKind.is_golden_fish(_level_kind):
		_lives = 1
	else:
		if not _lives_inf:
			_lives = _life_cap
	_refresh_life_bar_display()

	if not LevelKind.is_golden_fish(_level_kind):
		_life_bar.revive_all()

	_flush_endgame_snapshot()

	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"]

	resume_like_hand_clock()

	_board_view.revive_all_cat_to_idle()

	_rollback_draft_lethal_cells()

	_show_banner_if_eligible("game")
	_restart_game_barrages_after_continue()


func _refresh_life_bar_display() -> void:
	_life_bar.refresh(_display_lives())


func _allows_near_death_feedback() -> bool:
	return _level_kind == LevelKind.MAIN


func _allows_wrong_zone_feedback() -> bool:
	return _level_kind != LevelKind.COLOR_CHALLENGE


func _on_wrong_zone_state_changed() -> void:
	if (
		_board_view != null
		and _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot)
	):
		_flush_endgame_snapshot()


func _life_bar_nodes() -> Array[Control]:
	var out: Array[Control] = super._life_bar_nodes()
	if _life_bar_mul != null:
		out.append(_life_bar_mul)
	return out


func _cat_progress_adjacent_path() -> String:
	return "Root/VBoxContainer/BoardContainer/CatProgressBar"


func _cat_progress_adjacent_holder_path() -> String:
	return "Root/VBoxContainer/AdjacentBoardBarHolder"


func _record_normal_pass_time(time_total: int) -> void:
	if _level_kind != LevelKind.MAIN:
		return
	var lv: int = int(_level_config.get("level", 0))
	if lv <= 0 or LevelSelector.is_hard_level(lv) or LevelSelector.is_super_hard_level(lv):
		return
	var source: String = str(_level_config.get("bank_source_main", ""))
	if source.is_empty():
		source = str(_level_config.get("bank_source", ""))
	if not PassTimeDda.is_normal_level_source(source):
		return
	GameState.record_normal_pass_time(
		lv, int(_level_config.get("size", 0)), int(_level_config.get("rank", 0)), time_total
	)


func _on_game_win() -> void:
	PowerSaver.wake(_WIN_REPLAY_FULL_FPS_SEC)
	_reset_game_barrage_session_state()

	if _is_complete:
		push_error(
			"[COMPLETE-REENTRY] _on_game_win 重入 level=%d" % int(_level_config.get("level", -1))
		)
	if not _is_complete:
		GameState.on_game_finished()

		_accumulate_today_win_stats()
	_is_complete = true

	_exit_draft_mode_and_clear()
	_clock_timer.stop()
	_stop_idle_tool_hint()
	_destroy_banner()

	_dye_game_win_end()

	var _win_end_params: Dictionary = _build_game_end_params(Tracker.GameResult.WIN)
	_capture_elo_v2_win_facts()
	Tracker.track_game_end(_win_end_params)
	_record_normal_pass_time(int(_win_end_params.get("time_total", 0)))

	if LevelKind.is_golden_fish(_level_kind):
		_record_rec_history(_win_end_params, LevelOps.RecProgress.FINISH)
	else:
		_record_rec_history(_win_end_params)
	var lv: int = _level_config.get("level", 0)
	var this_session_rank: int = int(_level_config.get("rank", 0))
	var this_session_diffi: int = _get_diffi()
	var mouse_win_persisted_early: bool = false
	var rank_win_committed_early: bool = false

	if _mouse_completion_pending:
		if _rank_collector != null and is_instance_valid(_rank_collector):
			_rank_collector.set_win_reveal_deferred(true)
		_commit_rank_win()
		rank_win_committed_early = true
		if lv > 0:
			_persist_win_progress(lv, this_session_rank, this_session_diffi)
			mouse_win_persisted_early = true
	if not await _await_mouse_completion_anim_if_needed():
		return

	SoundManager.stop(SoundManager.Kind.MARK_CAT)

	PowerSaver.wake(_WIN_REPLAY_FULL_FPS_SEC)
	_board_view.replay_all_cat_appear(ABTestManager.found_cat_animation.win_replay_anim_name())

	if not rank_win_committed_early:
		_commit_rank_win()
	elif _rank_collector != null and is_instance_valid(_rank_collector):
		_rank_collector.set_win_reveal_deferred(false)
	VibrateManager.play_at(VibrateManager.Pos.GAME_WIN)
	_cleanup_hint()
	await get_tree().process_frame

	if _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		_board_view.cell_state_changed.disconnect(_persist_endgame_snapshot)
	if _endgame_persist_timer != null:
		_endgame_persist_timer.stop()

	if not mouse_win_persisted_early and lv > 0:
		_persist_win_progress(lv, this_session_rank, this_session_diffi)

	await _play_auto_cross_bonus_sequence()

	await await_se_fly_settled()
	if not is_showing():
		return

	var flight_shown: bool = await _play_rank_collect_flight()
	if not is_showing():
		return

	if flight_shown:
		await get_tree().create_timer(0.0667).timeout
		if not is_showing():
			return

	_level_config["restart_count"] = _restart_count
	_level_config["revive_count"] = _revive_count
	_level_config["mistake_count"] = _mistake_count
	_level_config["final_score"] = _score_model.score
	_level_config["max_combo"] = _score_model.max_combo

	_level_config["elapsed_sec"] = _like_hand_state.get("in_game_sec", 0.0)

	var _pp_size: int = int(_level_config.get("size", 0))
	var _pp_total: int = maxi(_pp_size * _pp_size, 1)
	var _pp_empty: int = _board_view.count_empty_cells() if _board_view != null else 0
	_level_config["completion_rate"] = int(
		round((1.0 - float(_pp_empty) / float(_pp_total)) * 100.0)
	)
	_level_config["tools_used"] = (
		int(Tracker.get_stat("hint_used")) + int(Tracker.get_stat("locate_used"))
	)

	StreakManager.settle_win(&"main")

	var toast_was_shown: bool = await _play_win_toast_and_wait()
	_level_config["toast_was_shown"] = toast_was_shown

	var rank_flow_shown: bool = await _try_run_rank_flow_after_win(toast_was_shown or flight_shown)

	_finish_rank_win_presentation(true)

	var streak_consumed_appear_delay: bool = false
	if not ABTestManager.daily_streak.is_settle_reorder():
		streak_consumed_appear_delay = await _try_run_streak_flow_after_win(
			&"main", toast_was_shown or rank_flow_shown or flight_shown
		)
	_level_config["skip_appear_delay"] = (
		streak_consumed_appear_delay or rank_flow_shown or flight_shown
	)
	if (
		not toast_was_shown
		and not streak_consumed_appear_delay
		and not rank_flow_shown
		and not flight_shown
	):
		await get_tree().create_timer(GameWinPage.APPEAR_DELAY).timeout
		if not is_showing():
			return

	_level_config["lives"] = _lives

	_level_config["diffi"] = this_session_diffi if lv > 0 else 0
	UIManager.show_ui(_win_ui_name(), {"level_config": _level_config, "board_view": _board_view})


func _commit_rank_win() -> void:
	if RankActivityManager.is_joined():
		_rank_win_presentation_active = true
		RankActivityManager.begin_rank_win_presentation()

	RankActivityManager.set_level_collect(
		RankActivityConfig.map_collect(
			_level_config.get("size", 0), _lives, LevelKind.is_golden_fish(_level_kind), _lives_inf
		)
	)
	RankActivityManager.notify_level_win()


func _persist_win_progress(level_num: int, session_rank: int, session_diffi: int) -> void:
	_capture_daily_first_main_win(level_num)
	GameState.on_level_won(level_num, _level_kind, session_rank, session_diffi, is_full_hp_win())

	if LevelKind.is_golden_fish(_level_kind):
		GameState.on_golden_fish_settled(true)
	elif LevelKind.is_color_challenge(_level_kind):
		GameState.on_color_challenge_settled()
	GameState.clear_endgame_snapshot()


func _capture_daily_first_main_win(level_num: int) -> void:
	var is_main_win: bool = level_num > 0 and not bool(_level_config.get("is_daily", false))

	if not _level_config.has("companion_before_win"):
		_level_config["companion_before_win"] = GameState.get_home_companion_data()
	if not _level_config.has("is_comeback_main_win"):
		var is_comeback_win: bool = is_main_win and GameState.consume_comeback_main_win()
		_level_config["is_comeback_main_win"] = is_comeback_win and _level_kind == LevelKind.MAIN
	if _level_config.has("is_daily_first_main_win"):
		return
	_level_config["is_daily_first_main_win"] = (
		is_main_win and level_num > 1 and not GameState.has_main_win_today()
	)
	if not OS.has_feature("rel"):
		print(
			(
				"[DailyFirstWin] settle lv=%d kind=%d won_today=%s first=%s"
				% [
					level_num,
					_level_kind,
					str(GameState.has_main_win_today()),
					str(_level_config["is_daily_first_main_win"])
				]
			)
		)


## 胜利界面名（普通对局固定 WIN）
func _win_ui_name() -> StringName:
	return UiName.WIN


func _is_no_mistake_level() -> bool:
	if LevelKind.is_insert_golden_fish(_level_kind):
		return not GameState.has_insert_golden_fish_wrong_cat()
	return not GameState.has_wrong_cat_current_level()


func _try_run_streak_flow_after_win(_source: StringName, skip_cat_appear: bool = false) -> bool:
	var has_revive: bool = StreakManager.has_pending_revive_decision()
	if not has_revive and not StreakManager.has_pending_show():
		return false

	if not skip_cat_appear:
		await get_tree().create_timer(GameWinPage.APPEAR_DELAY).timeout
	if has_revive:
		await StreakReviveFlow.run(self)
	if StreakManager.has_pending_show():
		await StreakPage.open_after_win()
	return true


func _try_run_rank_flow_after_win(skip_cat_appear: bool) -> bool:
	if not RankActivityManager.is_joined():
		return false

	if not UniKitManager.is_online():
		return false

	var st: int = RankActivityManager.get_state()
	if st != RankActivityData.State.OPEN_JOINED and st != RankActivityData.State.SETTLING:
		return false
	var will_change: bool = RankActivityManager.did_last_win_score()
	var settling: bool = st == RankActivityData.State.SETTLING

	var podium: bool = _is_rank_podium_eligible()
	if not will_change and not settling and not podium:
		return false
	if podium:
		UIManager.warm_pool_async(UiName.RANK_ACTIVITY_PODIUM)

	if will_change and ABTestManager.podium_per_game.is_list_podium_style():
		UIManager.warm_pool_async(UiName.RANK_ACTIVITY_CHANGE_V2)
	if not skip_cat_appear:
		await get_tree().create_timer(GameWinPage.APPEAR_DELAY).timeout
		if not is_showing():
			return false

	if will_change:
		var advance: int = RankActivityManager.get_last_win_advance()

		var change_ui: StringName = (
			UiName.RANK_ACTIVITY_CHANGE_V2
			if ABTestManager.podium_per_game.is_list_podium_style()
			else UiName.RANK_ACTIVITY_CHANGE
		)

		var rank_like_result: Dictionary = {}
		if ABTestManager.rank_like_func.is_like_enabled():
			rank_like_result = RankActivityManager.prepare_rank_like_settlement(
				ABTestManager.rank_like_func.has_barrage()
			)

		(
			UIManager
			. show_ui(
				change_ui,
				{
					"advance_places": advance,
					"lives": _lives,
					"is_golden_fish": LevelKind.is_golden_fish(_level_kind),
					"rank_like_result": rank_like_result,
				}
			)
		)
		await UIManager.await_hidden(change_ui)

	if podium and RankActivityManager.get_state() == RankActivityData.State.OPEN_JOINED:
		await _try_run_rank_podium_after_win()

	_finish_rank_win_presentation()

	if RankActivityManager.get_state() == RankActivityData.State.SETTLING:
		if not RankActivityManager.get_pending_reward().is_empty():
			RankActivityManager.claim_reward(false)
			await get_tree().process_frame
			await UIManager.await_hidden(UiName.AWARD)
		else:
			var solo_shown: bool = await _try_run_end_solo_podium()
			if not solo_shown:
				RankActivityManager.notify_settlement_done()
	return true


func _try_run_end_solo_podium() -> bool:
	var pending: Dictionary = RankActivityManager.get_pending_end_solo_podium()
	if pending.is_empty():
		return false
	if not ABTestManager.podium_per_leaderboard.has_end_solo_podium():
		return false
	if not RankActivityManager.begin_end_solo_podium():
		return false
	UIManager.show_ui(UiName.RANK_ACTIVITY_SOLO_PODIUM, {"rank": int(pending.get("rank", 4))})
	await UIManager.await_hidden(UiName.RANK_ACTIVITY_SOLO_PODIUM)
	RankActivityManager.complete_end_solo_podium(false)
	return true


func _is_rank_podium_eligible() -> bool:
	var _pg: PodiumPerGameConfig = ABTestManager.podium_per_game
	var _d_limit: int = _pg.podium_rank_limit()
	var _d_win: int = RankActivityManager.get_last_win_advance()
	var _d_online: int = RankActivityManager.get_last_online_advance()
	var _d_rank: int = RankActivityManager.get_player_rank()
	var _d_why: String = "PASS(会登台)"
	if not _pg.has_per_game_podium():
		_d_why = "拦:AB未命中登台组(需 podium_per_game=1)"
	elif _d_limit <= 0:
		_d_why = "拦:limit<=0"
	elif _d_win <= 0 and _d_online <= 0:
		_d_why = "拦:两个 advance 都为 0(名次未上升,且离线补偿也为 0)"
	elif _d_rank < 1 or _d_rank > _d_limit:
		_d_why = "拦:名次 %d 超出前 %d" % [_d_rank, _d_limit]
	print(
		(
			"[PodiumDiag] eligible? %s | pg=%d ab_loaded=%s limit=%d win_adv=%d online_adv=%d rank=%d"
			% [
				_d_why,
				int(_pg.value()),
				str(_pg.is_value_loaded()),
				_d_limit,
				_d_win,
				_d_online,
				_d_rank
			]
		)
	)

	if not ABTestManager.podium_per_game.has_per_game_podium():
		return false
	var limit: int = ABTestManager.podium_per_game.podium_rank_limit()
	if limit <= 0:
		return false
	if (
		RankActivityManager.get_last_win_advance() <= 0
		and RankActivityManager.get_last_online_advance() <= 0
	):
		return false
	var rank: int = RankActivityManager.get_player_rank()
	return rank >= 1 and rank <= limit


func _try_run_rank_podium_after_win() -> void:
	var rank: int = RankActivityManager.get_player_rank()
	var top3: Array = []
	var rank_infos: Array = RankActivityManager.get_rank_infos().slice(0, 3)
	for info in rank_infos:
		if info != null:
			top3.append(info.player_info)
	(
		UIManager
		. show_ui(
			UiName.RANK_ACTIVITY_PODIUM,
			{
				"rank": rank,
				"top3_infos": top3,
			}
		)
	)
	await UIManager.await_hidden(UiName.RANK_ACTIVITY_PODIUM)


func _on_rule_violated(rule: int, additive: bool = false) -> void:
	_play_rule_highlight(rule, additive)


func _retry_cache_matches_kind(cached: Dictionary) -> bool:
	var source: String = str(cached.get("bank_source", ""))
	var level: int = int(cached.get("retry_level", 0))
	if (
		ABTestManager.normal_level.value() == 11900
		and (source == "digit_sp" or (source == "sp" and level in [44, 104]))
	):
		return false
	var is_cc_lock: bool = (
		str(cached.get("bank_source", "")) == ColorChallengeGate.BANK_SOURCE
		or bool(cached.get("_returnee_color_override", false))
	)
	var is_cc_level: bool = LevelKind.is_color_challenge(_level_kind)
	if is_cc_lock != is_cc_level:
		print(
			(
				"[ColorChallenge] 锁题与本局类型不匹配,忽略该锁 (lock_is_cc=%s level_is_cc=%s)"
				% [str(is_cc_lock), str(is_cc_level)]
			)
		)
		return false
	return true


func _resolve_pre_cat() -> void:
	_pre_type = PreCatDecider.PRE_TYPE_NONE
	_pre_cat_position = Vector2i(-1, -1)

	if LevelKind.is_golden_fish(_level_kind):
		if LevelKind.is_insert_golden_fish(_level_kind):
			var decision: Dictionary = _golden_fish_pre_cat.resolve_insert(_level_config, _puzzle)
			_pre_type = str(decision.get("pre_type", PreCatDecider.PRE_TYPE_NONE))
			if not (_level_config.get("restore_state", {}) as Dictionary).is_empty():
				_pre_cat_position = decision.get("position", Vector2i(-1, -1))
			else:
				_append_pre_cat_prefill(decision.get("position", Vector2i(-1, -1)))
		return

	if LevelKind.is_color_challenge(_level_kind):
		print("[pre_cat] color challenge level, skip (pending 保留给下一个主线关)")
		return
	var lv: int = _level_config.get("level", 0)
	print(
		(
			"[pre_cat] resolve lv=%d rank=%d size=%d"
			% [lv, _level_config.get("rank", 0), _level_config.get("size", 0)]
		)
	)
	if lv <= 0:
		return

	if GameState.is_g4_pressure_level(lv):
		print("[pre_cat] g4 pressure level lv=%d, skip (pending 保留给下一个主线关)" % lv)
		return

	var restore_state: Dictionary = _level_config.get("restore_state", {})
	if not restore_state.is_empty():
		_pre_type = str(restore_state.get("pre_type", PreCatDecider.PRE_TYPE_NONE))

		var restored_prefills: Array = _level_config.get("prefill_positions", [])
		if (
			lv >= 21
			and _pre_type != PreCatDecider.PRE_TYPE_NONE
			and not restored_prefills.is_empty()
		):
			_pre_cat_position = Vector2i(int(restored_prefills[0][0]), int(restored_prefills[0][1]))
		print("[pre_cat] restore branch pre_type=%s" % _pre_type)
		return

	var pend: Dictionary = _golden_fish_pre_cat.main_pending(lv, _pre_cat_pend_snapshot)
	print("[pre_cat] pend=%s fail_count=%d" % [str(pend), GameState.get_pre_cat_fail_count(lv)])

	if debug_force_pre_cat:
		var forced_size: int = _level_config.get("size", 0)
		var forced_solution: Array = _puzzle.get("solution", [])
		var forced_pos: Vector2i = PreCatDecider.pick_prefill_cell(
			forced_size, _puzzle.get("regions", []), forced_solution
		)
		if forced_pos.x < 0:
			forced_pos = _pick_any_solution_cell(forced_size, forced_solution)
			if forced_pos.x < 0:
				print("[pre_cat] cheat 强制预放失败:本题连一个真解格都读不到(solution 为空?)")
				return
			print("[pre_cat] cheat 无 rank>=R3 解格,降级随机挑真解格")
		var forced_scenes: Array[int] = [PreCatDecider.SCENE_CONSECUTIVE_FAIL]
		_pre_type = PreCatDecider.scenes_to_pre_type(forced_scenes)
		_append_pre_cat_prefill(forced_pos)
		GameState.set_pre_cat_lock(lv, _pre_type, forced_pos, pend)
		print(
			(
				"[pre_cat] cheat 强制预放 pos=%s pre_type=%s(借用场景2 的值,仅为让埋点字段合法)"
				% [str(forced_pos), _pre_type]
			)
		)
		return
	if ABTestManager.normal_level.is_server_rec_active():
		print(
			(
				"[pre_cat] normal_level=%s(服务端推荐组) skip, pre_type=0"
				% str(ABTestManager.normal_level.value())
			)
		)
		return

	if lv <= 20:
		print("[pre_cat] lv<=20 skip, pre_type=0")
		return

	var high_rank_mode: bool = ABTestManager.normal_level.is_pre_cat_high_rank_active()

	var lock: Dictionary = GameState.get_pre_cat_lock(lv, pend)
	print("[pre_cat] lock=%s" % str(lock))
	if bool(lock.get("locked", false)):
		_pre_type = str(lock.get("pre_type", PreCatDecider.PRE_TYPE_NONE))
		var locked_pos: Vector2i = lock.get("position", Vector2i(-1, -1))

		if locked_pos.x >= 0:
			var sol: Array = _puzzle.get("solution", [])
			var is_valid: bool = (
				locked_pos.x < sol.size()
				and locked_pos.y < (sol[locked_pos.x] as Array).size()
				and bool((sol[locked_pos.x] as Array)[locked_pos.y])
			)
			if not is_valid:
				var sz: int = _level_config.get("size", 0)
				var regions: Array = _puzzle.get("regions", [])
				var new_pos: Vector2i = (
					PreCatDecider.pick_prefill_cell_highest_rank(sz, regions, sol)
					if high_rank_mode
					else PreCatDecider.pick_prefill_cell(sz, regions, sol)
				)
				print(
					(
						"[pre_cat] lock pos %s invalid for current puzzle → re-pick %s"
						% [str(locked_pos), str(new_pos)]
					)
				)
				if new_pos.x >= 0:
					var restats: Dictionary = PreCatDecider.rank_stats(sz, regions, sol, new_pos)
					var r_sel: int = int(restats["selected_rank"])
					var r_max: int = int(restats["max_rank"])

					var verdict: String = (
						(" %s" % ("✅一致" if r_sel == r_max else "⚠️不一致")) if high_rank_mode else ""
					)
					print(
						(
							"[pre_cat] 难度校验(re-pick) 高难模式=%s 选中格rank=%d 全盘最高rank=%d%s"
							% [str(high_rank_mode), r_sel, r_max, verdict]
						)
					)
				locked_pos = new_pos
				GameState.set_pre_cat_lock(lv, _pre_type, locked_pos, pend)
		_append_pre_cat_prefill(locked_pos)
		print("[pre_cat] sustain lock pre_type=%s pos=%s" % [_pre_type, str(_pre_cat_position)])
		return

	if ABTestManager.normal_level.is_pre_cat_level_swap_active():
		var swap_type: String = str(
			_level_config.get("pre_cat_swap_type", PreCatDecider.PRE_TYPE_NONE)
		)
		if swap_type != PreCatDecider.PRE_TYPE_NONE:
			_pre_type = swap_type
			GameState.set_pre_cat_lock(lv, _pre_type, Vector2i(-1, -1), pend)
			print("[pre_cat] level_swap decided pre_type=%s" % _pre_type)
			return
		print("[pre_cat] level_swap miss, fallback to control-style decide()+prefill")

	var scenes: Array[int] = PreCatDecider.hit_scenarios(
		bool(pend.get("hard", false)),
		_level_config.get("rank", 0),
		bool(pend.get("struggle", false)),
		bool(pend.get("demote", false))
	)
	print("[pre_cat] scenes=%s" % str(scenes))
	if scenes.is_empty():
		if GameState.has_golden_fish_pre_cat_followup(lv):
			GameState.set_pre_cat_lock(lv, _pre_type, Vector2i(-1, -1), pend)
		return
	var res: Dictionary = PreCatDecider.decide(
		scenes,
		_level_config.get("size", 0),
		_puzzle.get("regions", []),
		_puzzle.get("solution", []),
		high_rank_mode
	)
	print(
		(
			"[pre_cat] decide res=%s regions_empty=%s solution_empty=%s"
			% [
				str(res),
				str((_puzzle.get("regions", []) as Array).is_empty()),
				str((_puzzle.get("solution", []) as Array).is_empty())
			]
		)
	)
	if res.has("selected_rank"):
		var r_sel: int = int(res["selected_rank"])
		var r_max: int = int(res["max_rank"])

		var verdict: String = (
			(" %s" % ("✅一致" if r_sel == r_max else "⚠️不一致")) if high_rank_mode else ""
		)
		print(
			(
				"[pre_cat] 难度校验 高难模式=%s 选中格rank=%d 全盘最高rank=%d%s"
				% [str(high_rank_mode), r_sel, r_max, verdict]
			)
		)
	_pre_type = str(res.get("pre_type", PreCatDecider.PRE_TYPE_NONE))
	var pos: Vector2i = res.get("position", Vector2i(-1, -1))
	_append_pre_cat_prefill(pos)

	GameState.set_pre_cat_lock(lv, _pre_type, pos, pend)
	print("[pre_cat] decided pre_type=%s pos=%s" % [_pre_type, str(pos)])


func _pick_any_solution_cell(size: int, solution_2d: Array) -> Vector2i:
	var cells: Array[Vector2i] = []
	for r: int in range(size):
		if r >= solution_2d.size():
			break
		var row: Array = solution_2d[r]
		for c: int in range(size):
			if c < row.size() and bool(row[c]):
				cells.append(Vector2i(r, c))
	if cells.is_empty():
		return Vector2i(-1, -1)
	return cells[randi() % cells.size()]


func _append_pre_cat_prefill(pos: Vector2i) -> void:
	if pos.x < 0:
		return
	_pre_cat_position = pos
	var pp: Array = _level_config.get("prefill_positions", [])
	pp.append([pos.x, pos.y])
	_level_config["prefill_positions"] = pp


func _prefill_positions_without_pre_cat() -> Array:
	var src: Array = _level_config.get("prefill_positions", [])
	if _pre_cat_position.x < 0:
		return src.duplicate()
	var out: Array = []
	for p in src:
		if int(p[0]) == _pre_cat_position.x and int(p[1]) == _pre_cat_position.y:
			continue
		out.append(p)
	return out


func _self_prefill_cell() -> Vector2i:
	var arr: Array = _level_config.get("prefill_positions", [])
	if arr.is_empty():
		return Vector2i(-1, -1)
	var p: Variant = arr[0]
	if p is Array and (p as Array).size() >= 2:
		return Vector2i(int((p as Array)[0]), int((p as Array)[1]))
	return Vector2i(-1, -1)


func _prefill_hints() -> void:
	var positions: Array = _level_config.get("prefill_positions", [])
	var pre_cat_positions: Array = []

	var hide_cell: Vector2i = Vector2i(-1, -1)
	if _pre_cat_fx != null and _pre_cat_fx.wants_cat_hidden():
		hide_cell = _pre_cat_fx.cat_cell()
	for position: Array in positions:
		var row: int = int(position[0])
		var column: int = int(position[1])
		var show_cat: bool = not (row == hide_cell.x and column == hide_cell.y)

		_board_view.set_cell_state(
			row, column, CellState.CAT, false, show_cat, BoardView.ChangeSource.PREFILL
		)
		pre_cat_positions.append([row, column])

	_pre_cat_positions_at_start = JSON.stringify(pre_cat_positions)
	_record_prefill_solution_step(positions)


func _record_prefill_solution_step(positions: Array) -> void:
	if positions.is_empty() or _stat_status == Tracker.GameStatus.CONTINUE:
		return
	var cells: Array = []
	for pos in positions:
		cells.append(_step_cell(int(pos[0]), int(pos[1]), Tracker.StepResult.CORRECT))
	Tracker.record_solution_step(Tracker.StepAction.PREFILL_SIGN, cells)


# ================= 盘面复原与草稿回滚 =================
## 从 _level_config 的 restore_state 复原棋盘
func _restore_partial_board() -> void:
	_restore_partial_board_from(_level_config.get("restore_state", {}))


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

	for pos in data.get("errors", []):
		var r: int = int(pos[0])
		var c: int = int(pos[1])
		_board_view.set_cell_state(
			r, c, CellState.MARK, false, true, BoardView.ChangeSource.RESTORE
		)
		_board_view.mark_cell_error(r, c, BoardView.ChangeSource.RESTORE)


var _cc_pattern_btn: Button = null

var _cc_toast: CanvasLayer = null


func _ensure_color_challenge_toast() -> CanvasLayer:
	if _cc_toast != null and is_instance_valid(_cc_toast):
		return _cc_toast
	var scene: PackedScene = load(_CC_TOAST_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[ColorChallenge] 横幅场景加载失败: %s" % _CC_TOAST_SCENE_PATH)
		return null
	var toast: CanvasLayer = scene.instantiate() as CanvasLayer
	if toast == null:
		push_error("[ColorChallenge] 横幅根节点不是 CanvasLayer")
		return null
	var host: Node = get_node_or_null("Root")
	if host == null:
		push_error("[ColorChallenge] Root 未找到,横幅无法挂载")
		return null
	host.add_child(toast)
	_cc_toast = toast
	return _cc_toast


func _refresh_color_challenge_pattern_btn() -> void:
	var want: bool = LevelKind.is_color_challenge(_level_kind)
	if not want:
		_stop_cc_pattern_btn_entry_fade()
		if _cc_pattern_btn != null and is_instance_valid(_cc_pattern_btn):
			_cc_pattern_btn.queue_free()
		_cc_pattern_btn = null
		return
	if _cc_pattern_btn == null or not is_instance_valid(_cc_pattern_btn):
		var host: Node = find_node_by_name("FunctionArea")
		if host == null:
			push_error("[ColorChallenge] FunctionArea 未找到,色盲快捷开关无法挂载")
			return
		var btn: Button = _CC_PATTERN_BTN_SCENE.instantiate() as Button
		if btn == null:
			return
		btn.name = "ColorChallengePatternBtn"
		btn.toggled.connect(_on_cc_pattern_btn_toggled)

		btn.modulate.a = 0.0
		host.add_child(btn)
		bind_press_release_scale(btn)

		_attach_button_press_guard(btn)
		_cc_pattern_btn = btn

	_cc_pattern_btn.set_pressed_no_signal(GameState.is_pattern_mode_on())
	_align_cc_pattern_btn_to_board()
	_start_cc_pattern_btn_entry_fade()


func _start_cc_pattern_btn_entry_fade() -> void:
	if _cc_pattern_btn == null or not is_instance_valid(_cc_pattern_btn):
		return

	_cc_pattern_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if not RenderingServer.frame_pre_draw.is_connected(_sync_cc_pattern_btn_alpha):
		RenderingServer.frame_pre_draw.connect(_sync_cc_pattern_btn_alpha)


func _sync_cc_pattern_btn_alpha() -> void:
	if _cc_pattern_btn == null or not is_instance_valid(_cc_pattern_btn):
		_stop_cc_pattern_btn_entry_fade()
		return
	var ref: CanvasItem = get_node_or_null(_CC_PATTERN_BTN_FADE_REF) as CanvasItem
	if ref == null:
		_stop_cc_pattern_btn_entry_fade()
		return
	_cc_pattern_btn.modulate.a = ref.modulate.a
	if ref.modulate.a >= 1.0 and not _entry_anim_playing:
		_stop_cc_pattern_btn_entry_fade()


func _stop_cc_pattern_btn_entry_fade() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_cc_pattern_btn_alpha):
		RenderingServer.frame_pre_draw.disconnect(_sync_cc_pattern_btn_alpha)
	if _cc_pattern_btn != null and is_instance_valid(_cc_pattern_btn):
		_cc_pattern_btn.modulate.a = 1.0
		_cc_pattern_btn.mouse_filter = Control.MOUSE_FILTER_STOP


const _CC_PATTERN_BTN_FADE_REF: NodePath = ^"Root/VBoxContainer/ToolsRow/BottomTools/HintCtrl/HintBtn"


func _apply_pattern_mode() -> void:
	super._apply_pattern_mode()
	if _cc_pattern_btn != null and is_instance_valid(_cc_pattern_btn):
		_cc_pattern_btn.set_pressed_no_signal(GameState.is_pattern_mode_on())


func _align_cc_pattern_btn_to_board() -> void:
	if _cc_pattern_btn == null or not is_instance_valid(_cc_pattern_btn):
		return
	if _board_view == null:
		return
	var visible_w: float = (
		BoardView.intrinsic_size_for(int(_level_config.get("size", 0))).x * _board_view.scale.x
	)
	var board_right: float = _board_view.position.x + visible_w
	_cc_pattern_btn.position.x = board_right - _cc_pattern_btn.size.x


func _on_cc_pattern_btn_toggled(new_value: bool) -> void:
	GameState.set_pattern_mode_on(new_value)
	_apply_pattern_mode()
	VibrateManager.play_at(VibrateManager.Pos.BLIND_MOD_BTN)

	Tracker.track_btn_click(
		Tracker.Btn.PATTERN_MODE_ON if new_value else Tracker.Btn.PATTERN_MODE_OFF, self
	)
	print("[ColorChallenge] 局内色盲开关 → %s" % ("开" if new_value else "关"))


func _current_color_challenge_hues() -> Array:
	var delivery_index: int = _resolve_cc_delivery_index()
	var group: int = ABTestManager.color_challenge_func.group_value()
	if ColorChallengeGate.is_dual_color(group):
		return ColorChallengePalette.dual_hues(delivery_index)
	return [ColorChallengePalette.single_hue(delivery_index)]


func _hint_color_name_override(color: Color) -> String:
	if not LevelKind.is_color_challenge(_level_kind):
		return ""
	var key: StringName = ColorChallengePalette.nearest_color_name_key(
		color, _current_color_challenge_hues()
	)
	return tr(key)


func _resolve_cc_delivery_index() -> int:
	var raw: int = int(_level_config.get("_cc_delivery_index", -1))
	if raw >= 0:
		return raw
	push_error(
		(
			"[ColorChallenge] _cc_delivery_index 缺失(kind=%d lv=%s) —— entry → _level_config 的透传断了,配色会退化成恒红"
			% [_level_kind, str(_level_config.get("level", "?"))]
		)
	)
	return 0


func _apply_color_challenge_palette(sz: int, color_map: Array[int]) -> void:
	if not LevelKind.is_color_challenge(_level_kind):
		_board_view.clear_palette_override()
		return
	var group: int = ABTestManager.color_challenge_func.group_value()
	var hues: Array = _current_color_challenge_hues()
	var delivery_index: int = _resolve_cc_delivery_index()
	var groups_of_region: Array = []
	var slot_colors: PackedColorArray = PackedColorArray()
	var gradient_used: bool = false
	if delivery_index <= 0:
		var gradient: Dictionary = ColorChallengePalette.build_first_level_gradient(
			_puzzle["regions"], sz, hues
		)
		if not gradient.is_empty():
			color_map.assign(gradient["color_map"])
			slot_colors = gradient["colors"]
			gradient_used = true
	if not gradient_used:
		if ColorChallengeGate.is_dual_color(group):
			groups_of_region = ColorChallengePalette.split_regions_into_two(_puzzle["regions"], sz)
		slot_colors = ColorChallengePalette.build_slot_colors(color_map, groups_of_region, hues)
	if slot_colors.is_empty():
		push_error(
			"[ColorChallenge] palette empty, fallback to default (sz=%d group=%d)" % [sz, group]
		)
		_board_view.clear_palette_override()
		return
	_board_view.set_palette_override(slot_colors)
	if not OS.has_feature("rel"):
		print(
			(
				"[ColorChallenge] 配色: 交付序号=%d 分组=%d 色系=%s 槽位数=%d%s%s"
				% [
					delivery_index,
					group,
					str(hues),
					slot_colors.size(),
					" 首关对角渐变(左下→右上,深→浅)" if gradient_used else "",
					(" 双色二分=%s" % str(groups_of_region)) if not groups_of_region.is_empty() else ""
				]
			)
		)


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


const _ELO_DEBUG_RANKS: Array = [3, 4, 5]
const _ELO_DEBUG_TOOLS_ROW_HEIGHT: float = 200.0
const _ELO_DEBUG_PANEL_HEIGHT: float = 120.0
const _ELO_DEBUG_PANEL_WIDTH: float = 220.0
const _ELO_DEBUG_FONT_SIZE: int = 26
const _ELO_DEBUG_ROLL_SEC: float = 0.5
const _ELO_DEBUG_DELTA_HOLD_SEC: float = 1.2
const _ELO_DEBUG_COLOR_ACTIVE: Color = Color(0.95, 0.25, 0.2, 1.0)
const _ELO_DEBUG_COLOR_IDLE: Color = Color(0.5, 0.5, 0.5, 1.0)
const _ELO_DEBUG_COLOR_DELTA: Color = Color(1.0, 0.85, 0.2, 1.0)
var _elo_debug_overlay: CanvasLayer = null
var _elo_debug_labels: Dictionary = {}
var _elo_debug_delta_labels: Dictionary = {}
var _elo_debug_shown_values: Dictionary = {}


func _on_cheat_command(cmd_name: String, args: Array[String]) -> void:
	match cmd_name:
		"win":
			_cmd_win(args)
		"gf_fx":
			_cmd_gf_fx(args)
		"level":
			_cmd_level(args)
		"lives":
			_cmd_lives(args)
		"elo_debug":
			_cmd_elo_debug(args)
		"dumpjson":
			_cmd_dumpjson(args)
		"score":
			_cmd_score(args)
		"time":
			_cmd_time(args)
		"thumb_reset":
			_cmd_thumb_reset()
		"thumb_r4":
			_cmd_thumb_r4()
		"draft":
			_cmd_draft()
		"draft_win":
			_cmd_draft_win()
		"test_err_page":
			_cmd_test_err_page()


func _cmd_test_err_page() -> void:
	push_error("[fold-test] error B from game_page.gd")


func _cmd_elo_debug(args: Array[String]) -> void:
	var on: bool = (int(args[0]) if args.size() > 0 else 1) != 0
	if not on:
		if is_instance_valid(_elo_debug_overlay):
			_elo_debug_overlay.visible = false
		return
	_ensure_elo_debug_panel()
	_elo_debug_overlay.visible = true
	_refresh_elo_debug_panel()


func _ensure_elo_debug_panel() -> void:
	if is_instance_valid(_elo_debug_overlay):
		return
	_elo_debug_overlay = CanvasLayer.new()
	_elo_debug_overlay.layer = 15
	_elo_debug_overlay.visible = false
	get_tree().current_scene.add_child(_elo_debug_overlay)

	var panel := VBoxContainer.new()
	panel.name = "EloDebugPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.alignment = BoxContainer.ALIGNMENT_CENTER

	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_right = 16.0 + _ELO_DEBUG_PANEL_WIDTH
	panel.offset_top = -(_ELO_DEBUG_TOOLS_ROW_HEIGHT + _ELO_DEBUG_PANEL_HEIGHT)
	panel.offset_bottom = -_ELO_DEBUG_TOOLS_ROW_HEIGHT
	_elo_debug_overlay.add_child(panel)

	var font: FontVariation = load("res://assets/fonts/Roboto-bold.tres")
	for r: int in _ELO_DEBUG_RANKS:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var rating_label := Label.new()
		rating_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rating_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rating_label.add_theme_font_override("font", font)
		rating_label.add_theme_font_size_override("font_size", _ELO_DEBUG_FONT_SIZE)
		rating_label.add_theme_color_override("font_color", _ELO_DEBUG_COLOR_IDLE)
		row.add_child(rating_label)
		_elo_debug_labels[r] = rating_label

		var delta_label := Label.new()
		delta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		delta_label.add_theme_font_override("font", font)
		delta_label.add_theme_font_size_override("font_size", _ELO_DEBUG_FONT_SIZE)
		delta_label.add_theme_color_override("font_color", _ELO_DEBUG_COLOR_DELTA)
		delta_label.visible = false
		row.add_child(delta_label)
		_elo_debug_delta_labels[r] = delta_label

		panel.add_child(row)
	if not GameState.elo_rating_committed.is_connected(_on_elo_debug_rating_committed):
		GameState.elo_rating_committed.connect(_on_elo_debug_rating_committed)


func _refresh_elo_debug_panel() -> void:
	var active_rank: int = GameState.get_elo_active_rank()
	for r: int in _ELO_DEBUG_RANKS:
		var label: Label = _elo_debug_labels.get(r)
		if label == null:
			continue
		var value: float = GameState.get_elo_rating(r)
		_elo_debug_shown_values[r] = value
		label.text = "R%d ELO: %.1f" % [r, value]
		label.add_theme_color_override(
			"font_color", _ELO_DEBUG_COLOR_ACTIVE if r == active_rank else _ELO_DEBUG_COLOR_IDLE
		)
		var delta_label: Label = _elo_debug_delta_labels.get(r)
		if delta_label != null:
			delta_label.visible = false


func _on_elo_debug_rating_committed(rank: int, new_value: float) -> void:
	if not is_instance_valid(_elo_debug_overlay):
		return
	var rating_label: Label = _elo_debug_labels.get(rank)
	var delta_label: Label = _elo_debug_delta_labels.get(rank)
	if rating_label == null or delta_label == null:
		return
	var old_value: float = _elo_debug_shown_values.get(rank, new_value)
	var delta: float = new_value - old_value
	delta_label.text = "%+.1f" % delta
	delta_label.visible = true
	var tw: Tween = _tween_elo_rating_label(rating_label, old_value, new_value, rank)
	_elo_debug_shown_values[rank] = new_value
	if tw != null:
		tw.finished.connect(
			func() -> void:
				if is_instance_valid(delta_label):
					delta_label.visible = false
		)
	else:
		get_tree().create_timer(_ELO_DEBUG_DELTA_HOLD_SEC).timeout.connect(
			func() -> void:
				if is_instance_valid(delta_label):
					delta_label.visible = false
		)


const _ELO_DEBUG_TWEEN_META: StringName = &"_elo_debug_tween"


func _tween_elo_rating_label(label: Label, from_value: float, to_value: float, rank: int) -> Tween:
	if label.has_meta(_ELO_DEBUG_TWEEN_META):
		var old_tw: Tween = label.get_meta(_ELO_DEBUG_TWEEN_META) as Tween
		if old_tw != null and old_tw.is_valid():
			old_tw.kill()
		label.remove_meta(_ELO_DEBUG_TWEEN_META)
	if is_equal_approx(from_value, to_value):
		label.text = "R%d ELO: %.1f" % [rank, to_value]
		return null
	label.text = "R%d ELO: %.1f" % [rank, from_value]
	var tw: Tween = label.create_tween()
	(
		tw
		. tween_method(
			func(v: float) -> void: label.text = "R%d ELO: %.1f" % [rank, v],
			from_value,
			to_value,
			_ELO_DEBUG_ROLL_SEC
		)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	label.set_meta(_ELO_DEBUG_TWEEN_META, tw)
	tw.finished.connect(
		func() -> void:
			if is_instance_valid(label) and label.get_meta(_ELO_DEBUG_TWEEN_META, null) == tw:
				label.remove_meta(_ELO_DEBUG_TWEEN_META)
	)
	return tw


func _log_cat_rank() -> void:
	var msg: String = _build_cat_rank_text()
	if msg.is_empty():
		return
	print("[rank_cat]\n" + msg + "\n————————————————————————————————————————")


func _build_cat_rank_text() -> String:
	if _puzzle.is_empty() or not _puzzle.has("solution") or not _puzzle.has("regions"):
		return ""
	var sz: int = _level_config.get("size", 0)
	var regions: Array = _puzzle.get("regions", [])
	var solution: Array = _puzzle.get("solution", [])
	if sz <= 0 or regions.is_empty() or solution.is_empty():
		return ""

	var board: Array = []
	for r: int in range(sz):
		var row: Array = []
		row.resize(sz)
		row.fill(CellState.EMPTY)
		board.append(row)

	var fallback_strategy: int = _level_config.get("rank", 1)
	var tier: String = _level_config.get("bank_tier", "N")
	if tier == "H":
		if fallback_strategy == 4:
			fallback_strategy = 5
		elif fallback_strategy == 5:
			fallback_strategy = 7
	else:
		if fallback_strategy == 5:
			fallback_strategy = 6
	var ranks: Dictionary = HintEngine.compute_cell_ranks(
		board, sz, regions, solution, fallback_strategy
	)

	var labels: Dictionary = {1: "R1", 2: "R2", 3: "R3", 4: "R4", 5: "R4H", 6: "R5", 7: "R5H"}
	var counts: Dictionary = {}
	for cell: Vector2i in ranks:
		var code: int = int(ranks[cell])
		counts[code] = counts.get(code, 0) + 1
	var lines: Array[String] = []
	lines.append(
		(
			"Lv%d (rank=%d tier=%s size=%d)"
			% [_level_config.get("level", 0), _level_config.get("rank", 0), tier, sz]
		)
	)
	lines.append("── 各 R 级猫数量 ──")
	var total: int = 0
	for code: int in [1, 2, 3, 4, 5, 6, 7]:
		if counts.has(code):
			var c: int = counts[code]
			total += c
			lines.append("%-4s : %d 只" % [labels[code], c])
	lines.append("合计 : %d 只" % total)

	lines.append("── 预填猫 ──")
	if _pre_cat_position.x >= 0 and ranks.has(_pre_cat_position):
		var pcode: int = int(ranks[_pre_cat_position])
		lines.append(
			(
				"位置(%d,%d) 难度 %s (pre_type=%s)"
				% [_pre_cat_position.x, _pre_cat_position.y, labels.get(pcode, "R?"), _pre_type]
			)
		)
	else:
		lines.append("无 (pre_type=%s)" % _pre_type)
	return "\n".join(lines)


func _cmd_thumb_reset() -> void:
	_like_hand_state["last_cat_sec"] = _like_hand_state["in_game_sec"] - 60.0
	_like_hand_state["triggered_count"] = 0
	_like_hand_state["has_seen_first_cat"] = true
	Toast.popup("LIKE 计时已重置(间隔 60s / 次数 0)", self)


func _cmd_thumb_r4() -> void:
	if _r4_plus_cells.is_empty():
		Toast.popup("当前无 R4+ 解格", self)
		return
	var coords: PackedStringArray = []
	for cell: Vector2i in _r4_plus_cells:
		coords.append("(%d,%d)" % [cell.x, cell.y])
	var msg: String = "R4+ 解格 %d 个: %s" % [coords.size(), ", ".join(coords)]
	print("[Cheat] " + msg)
	Toast.popup(msg, self)


func _cmd_score(args: Array[String]) -> void:
	var val: int = int(args[0]) if not args.is_empty() else 8888
	val = maxi(0, val)
	_score_model.score = val
	Toast.popup("当前分数已设为 %d" % val, self)


func _cmd_time(args: Array[String]) -> void:
	var sec: float = float(args[0]) if not args.is_empty() else 90.0
	sec = maxf(0.0, sec)
	_like_hand_state["in_game_sec"] = sec
	Toast.popup("当前时间已设为 %.1fs" % sec, self)


func _cmd_win(_args: Array[String]) -> void:
	if _entry_anim_playing or _is_complete or _wrong_guess_pending or _auto_completing:
		return
	if _puzzle.is_empty() or not _puzzle.has("solution"):
		return
	_auto_completing = true
	_auto_complete_token += 1
	_reset_idle_hint()
	UIMask.acquire()
	await _run_auto_complete(_auto_complete_token)
	UIMask.release()
	_auto_completing = false


func _cmd_gf_fx(_args: Array[String]) -> void:
	if (
		_entry_anim_playing
		or _is_complete
		or _wrong_guess_pending
		or _auto_completing
		or _puzzle.is_empty()
		or not _puzzle.has("solution")
	):
		print("[Cheat] gf_fx:此刻不能自动通关(入场动画中 / 本局已结束 / 正在自动完成),稍后再点")
		return
	_cmd_win([])
	await GameState.level_settled

	await get_tree().process_frame
	GameState.cheat_force_golden_fish_pending()
	var next_lv: int = GameState.get_current_level()
	var tip: String = ""
	if not ABTestManager.golden_fish_func.is_enabled():
		tip = "但 golden_fish_func=0(对照组)→ 压根不出一命关。先去「AB测」页把它切成 1"
	elif next_lv < GoldenFishGate.INSERT_MODE_MIN_LEVEL:
		tip = (
			"但第 %d 关 < %d 关下限 → 插入式不生效(通关一次还会被清掉)。先 `level %d`"
			% [next_lv, GoldenFishGate.INSERT_MODE_MIN_LEVEL, GoldenFishGate.INSERT_MODE_MIN_LEVEL]
		)
	else:
		tip = "下一关(第 %d 关)就是插入式一命关,进去看完动效再点一次本命令即可循环" % next_lv
	print("[Cheat] gf_fx:已自动通关 + 置 pending。%s" % tip)
	if not RankActivityManager.is_joined():
		print("[Cheat] gf_fx ⚠️ 排名活动未参与 —— 通关动效挂在排名飞入链上,不参与不会播。先去第 1 页点 `rank_open` 并参与")


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


func _build_endgame_snapshot(override: Dictionary = {}) -> Dictionary:
	var base: Dictionary = _build_puzzle_base()
	var sz: int = int(base["size"])
	var board: Array = _board_view.get_board()
	var cells_override: Dictionary = _snapshot_cell_overrides(override.get("cells", {}))
	var placed_cats: Array = []
	var marks: Array = []
	var errors: Array = []
	for r: int in range(sz):
		for c: int in range(sz):
			var st: int = board[r][c]

			var cell_key := Vector2i(r, c)
			if cells_override.has(cell_key):
				st = int(cells_override[cell_key])
			match st:
				CellState.CAT:
					placed_cats.append([r, c])
				CellState.MARK:
					marks.append([r, c])
				CellState.ERROR:
					errors.append([r, c])

	var snapshot: Dictionary = {"version": GameState.ENDGAME_SNAPSHOT_VERSION}
	snapshot.merge(base)

	snapshot["level"] = int(_level_config.get("level", 0))

	snapshot["last_action_local_date"] = GameState.current_local_date()
	snapshot["bank_source"] = _level_config.get("bank_source", "")
	snapshot["bank_source_main"] = _level_config.get("bank_source_main", "")
	snapshot["bank_tier"] = _level_config.get("bank_tier", "")
	snapshot["prefill_positions"] = _level_config.get("prefill_positions", [])

	var is_elo_delivery: bool = bool(_level_config.get("is_elo_delivery", false))
	snapshot["is_elo_delivery"] = is_elo_delivery
	snapshot["eloRating"] = _level_config.get("eloRating", -1.0) if is_elo_delivery else -1.0
	snapshot["_elo_e"] = _level_config.get("_elo_e", -1.0) if is_elo_delivery else -1.0
	snapshot["_elo_k"] = _level_config.get("_elo_k", -1.0) if is_elo_delivery else -1.0
	snapshot["_elo_player_rating"] = (
		_level_config.get("_elo_player_rating", -1.0) if is_elo_delivery else -1.0
	)
	snapshot["_puzzle_id"] = _level_config.get("_puzzle_id", "")
	snapshot["style_vector"] = _level_config.get("style_vector", {}).duplicate(true)

	snapshot["spRegion"] = _level_config.get("spRegion", [])

	snapshot["kind"] = _level_kind

	snapshot["cc_delivery_index"] = int(_level_config.get("_cc_delivery_index", 0))

	snapshot["diffi"] = _get_diffi()
	snapshot["pre_type"] = _pre_type

	snapshot["lives"] = int(override.get("lives", _lives))
	snapshot["placed_cats"] = placed_cats
	snapshot["marks"] = marks
	snapshot["errors"] = errors
	snapshot["score"] = int(override.get("score", _score_model.score))
	snapshot["combo"] = int(override.get("combo", _score_model.combo))
	snapshot["max_combo"] = int(override.get("max_combo", _score_model.max_combo))
	snapshot["se_count"] = int(override.get("se_count", _se_count))

	snapshot["se_last_step"] = int(override.get("se_last_step", _se_last_step))

	snapshot["se_enabled"] = true

	snapshot["cat_streak"] = _cat_streak
	snapshot["cross_at_first_cat"] = _cross_at_first_cat
	snapshot["restart_count"] = _restart_count
	snapshot["revive_count"] = _revive_count

	snapshot["in_game_sec"] = float(_like_hand_state.get("in_game_sec", 0.0))

	snapshot["continue_play_sec"] = _continue_play_sec
	snapshot["continue_clock_started"] = _continue_clock_started

	snapshot["operable_sec"] = _operable_sec
	snapshot["cat_toast"] = _cat_toast_tracker.export_state()

	snapshot["near_death_fired"] = _near_death_fired
	snapshot["near_death_level_key"] = _near_death_level_key

	snapshot["near_death_blocked"] = _near_death_blocked

	snapshot["wrong_zone"] = _wrong_zone_tracker.export_state()

	snapshot["cat_progress_rotate_start"] = _cat_progress_rotate_start

	snapshot["like_hand_triggered_count"] = int(_like_hand_state.get("triggered_count", 0))

	snapshot["missed_cross_triggered_cats"] = (
		_like_hand_state.get("missed_cross_triggered_cats", {}).keys()
	)

	snapshot["manually_x_marked_cells"] = _like_hand_state.get("manually_x_marked_cells", {}).keys()
	return snapshot


## 等到当前开场提示条自己收起
func _wait_start_toast_hidden_if_any() -> void:
	var active: BaseGameToast = _active_toast
	if active == null or not active.visible:
		return
	while active.visible:
		await active.visibility_changed


func _lock_entry_buttons() -> void:
	_entry_btn_lock_seq += 1
	_back_setting_header.lock_buttons()
	_tool_btns_locked = true


func _unlock_entry_buttons() -> void:
	_back_setting_header.unlock_buttons()
	_tool_btns_locked = false


## 提示条收起后解锁入口按钮（序号变了就不再解锁）
func _unlock_entry_buttons_after_toast(seq: int) -> void:
	await _wait_start_toast_hidden_if_any()
	if seq != _entry_btn_lock_seq:
		return
	_unlock_entry_buttons()


## 格子变更 → 残局快照：关键状态立刻写，其余延迟 0.5 秒写
func _persist_endgame_snapshot(_r: int, _c: int, state: int, _source: int = 0) -> void:
	if state == CellState.CAT or state == CellState.ERROR:
		_endgame_persist_timer.stop()

		call_deferred("_flush_endgame_snapshot")
	else:
		_endgame_persist_timer.start()


func _flush_endgame_snapshot() -> void:
	if _is_complete:
		return
	GameState.set_endgame_snapshot(_build_endgame_snapshot())


func save_endgame_snapshot(override: Dictionary = {}) -> void:
	if _is_complete:
		return
	GameState.set_endgame_snapshot(_build_endgame_snapshot(override))


func _save_endgame_for_pending_wrong_guess(r: int, c: int) -> void:
	if not _board_view.cell_state_changed.is_connected(_persist_endgame_snapshot):
		return

	var override: Dictionary = {
		"cells": {Vector2i(r, c): CellState.ERROR},
		"lives": _lives,
		"combo": 0,
		"se_count": 0,
	}

	if _endgame_persist_timer != null:
		_endgame_persist_timer.stop()
	save_endgame_snapshot(override)


func _on_prev_btn_pressed() -> void:
	_nav_to(_nav_index - 1)


func _on_next_btn_pressed() -> void:
	_nav_to(_nav_index + 1)


func _nav_to(new_index: int) -> void:
	if _nav_total <= 0:
		return
	var idx: int = ((new_index - 1) % _nav_total + _nav_total) % _nav_total + 1

	var bp: Dictionary = _level_config.get("bank_params", {})
	if bp.is_empty():
		UIManager.show_ui(UiName.GAME, {"level_index": idx})
		return

	var is_lk: bool = bp.get("bank_lk", false)
	var is_lk_style: bool = bp.get("bank_lk_style", false)
	var is_sp: bool = bp.get("bank_sp", false)
	var sz: int = bp.get("bank_size", 7)
	var rank: int = bp.get("bank_rank", 1)

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

	if levels.is_empty() or idx - 1 >= levels.size():
		return

	var entry: Dictionary = levels[idx - 1]
	var new_params: Dictionary = bp.duplicate()
	new_params["bank_index"] = idx
	new_params["prebuilt_regions"] = BankData.get_region_map(entry)
	new_params["prebuilt_solution"] = BankData.get_solution(entry)

	if is_sp:
		new_params["bank_size"] = entry.get("size", 9)
		new_params["bank_rank"] = entry.get("r", 1)
		new_params["level_seed"] = entry.get("id", 0)
		new_params["custom_color_map"] = entry.get("colorMap", [])
		new_params["r1_steps"] = entry.get("r1", 0)
		new_params["r2_steps"] = entry.get("r2", 0)
		new_params["r3_steps"] = entry.get("r3", 0)
		new_params["r4_steps"] = entry.get("r4", 0)
		new_params["r5_steps"] = entry.get("r5", 0)
	elif is_lk:
		new_params["bank_size"] = entry.get("size", 8)
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


func get_scr_name() -> String:
	if LevelKind.is_golden_fish(_level_kind):
		return Tracker.Scr.GOLDEN_FISH_GAME
	if LevelKind.is_color_challenge(_level_kind):
		return Tracker.Scr.COLOR_CHALLENGE_GAME
	return Tracker.Scr.NORMAL_GAME


func _tracker_game_type() -> String:
	if LevelKind.is_golden_fish(_level_kind):
		return Tracker.GameType.GOLDEN_FISH
	if LevelKind.is_color_challenge(_level_kind):
		return Tracker.GameType.COLOR_CHALLENGE
	return Tracker.GameType.NORMAL


func _build_game_end_params(result: String) -> Dictionary:
	var time_sec: int = _current_round_time_sec()

	GameState.inc_game_total_stat(Tracker.GameType.NORMAL, "time_total", time_sec)
	var sz: int = _level_config.get("size", 0)
	var cat_n: int = _board_view.count_cat_cells()
	var params: Dictionary = {
		"qid": _build_qid(),
		"qrotate": Tracker.transform_to_qrotate(_level_config.get("bank_transform", 0)),
		"result": result,
		"game_type": _tracker_game_type(),
		"diffi": _get_diffi(),
		"level": _level_config.get("level", 0),
		"strategy_layer": _level_config.get("rank", 0),
		"scale": sz,
		"pre_type": _pre_type,
		"pre_cat_positions": _pre_cat_positions_at_start,
		"rating": _level_config.get("rating", 0.0),
		"hint": GameState.get_tool_count("hint"),
		"locate": GameState.get_tool_count("locate"),
		"hint_used": Tracker.get_stat("hint_used"),
		"locate_used": Tracker.get_stat("locate_used"),
		"hint_used_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "hint_used_total"),
		"locate_used_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "locate_used_total"),
		"mouse": GameState.get_tool_count(ToolKind.MOUSE),
		"mouse_used": Tracker.get_stat("mouse_used"),
		"mouse_used_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "mouse_used_total"),
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
		"draft_apply_used_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_apply_used_total"),
		"draft_stop_used_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "draft_stop_used_total"),
		"coord_count": Tracker.get_stat("coord_count"),
		"step_used": Tracker.get_stat("step_used"),
		"step_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "step_total"),
		"cat_click_num": Tracker.get_stat("cat_click_num"),
		"gamedie_count": Tracker.get_stat("gamedie_count"),
		"restart_count": Tracker.get_stat("restart_count"),
		"time": time_sec,
		"time_total": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "time_total"),
		"cross_count": _board_view.count_mark_cells(),
		"correct_cross_count": _count_correct_crosses(),
		"false_cross_count": _count_false_crosses(),
		"hint_cross_count": Tracker.get_stat("hint_cross_count"),
		"invalid_sign": _board_view.count_error_cells(),
		"invalid_sign_total":
		GameState.get_game_total_stat(Tracker.GameType.NORMAL, "invalid_sign_total"),
		"fail_sign": sz - cat_n,
		"erase_count": Tracker.get_stat("erase_count"),
		"revive_count": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "revive_count"),
		"rv_count": GameState.get_game_total_stat(Tracker.GameType.NORMAL, "rv_count"),
		"hp_count": _lives,
		"se_score": _score_model.score,
		"is_tap_cat_at_last": _last_cat_at_last_flag(),
	}
	print(
		(
			"[GamePage] game_end cross: correct=%d false=%d hint=%d | cross_count=%d invalid_sign=%d"
			% [
				params["correct_cross_count"],
				params["false_cross_count"],
				params["hint_cross_count"],
				params["cross_count"],
				params["invalid_sign"]
			]
		)
	)
	print(
		(
			"[GamePage] game_end step: step_used=%d step_total=%d | locate_used=%d hint_apply_used=%d"
			% [
				params["step_used"],
				params["step_total"],
				params["locate_used"],
				params["hint_apply_used"]
			]
		)
	)
	print(
		(
			"[GamePage] game_end last_cat: is_tap_cat_at_last=%d | streak=%d/%d cross@1st=%d/阈%d"
			% [
				params["is_tap_cat_at_last"],
				_cat_streak,
				sz,
				_cross_at_first_cat,
				LastCatJudge.cross_threshold(sz)
			]
		)
	)
	params.merge(_build_rec_extra())
	params.merge(_build_elo_end_extra(result))
	params.merge(_companion_game_end_fields(result == Tracker.GameResult.WIN))
	return params


func _build_elo_start_extra() -> Dictionary:
	if not bool(_level_config.get("is_elo_delivery", false)):
		return {"eloRating": -1.0, "eValue": -1.0, "kValue": -1.0, "playerRating": -1.0}
	return {
		"eloRating": float(_level_config.get("eloRating", -1.0)),
		"eValue": float(_level_config.get("_elo_e", -1.0)),
		"kValue": float(_level_config.get("_elo_k", -1.0)),
		"playerRating": float(_level_config.get("_elo_player_rating", -1.0)),
	}


func _build_elo_end_extra(result: String) -> Dictionary:
	var extra: Dictionary = _build_elo_start_extra()
	if not bool(_level_config.get("is_elo_delivery", false)) or result != Tracker.GameResult.WIN:
		extra["sValue"] = -1.0
		extra["playerRatingNew"] = -1.0
		return extra
	var rank: int = int(_level_config.get("rank", 0))
	var puzzle_rating: float = float(_level_config.get("eloRating", 0.0))
	var player_rating: float = GameState.get_elo_rating(rank)
	var k_factor: float = float(
		_level_config.get("_elo_k", EloRatingMath.k_for_games(GameState.get_elo_games(rank)))
	)
	var expected_score: float = EloRatingMath.e_from_ratings(puzzle_rating, player_rating)
	var performance_score: float = EloRatingMath.s_from_fish(
		GameState.get_elo_fish_consumed(), GameState.is_dda_tool_or_revive_used()
	)
	if ABTestManager.normal_level.is_elo_v2_active():
		_capture_elo_v2_win_facts()
		var facts: Dictionary = GameState.get_elo_v2_attempt()
		performance_score = (
			LevelSelector.elo_v2_performance_score(facts) if _has_current_elo_v2_attempt() else -1.0
		)
		if performance_score < 0.0:
			extra["sValue"] = -1.0
			extra["playerRatingNew"] = -1.0
			return extra
		k_factor = EloV2Performance.k_for_games(GameState.get_elo_games(rank))
	extra["sValue"] = performance_score
	extra["playerRatingNew"] = EloRatingMath.new_player_rating(
		player_rating, k_factor, performance_score, expected_score
	)
	return extra


func _has_valid_elo_v2_rating(data: Dictionary) -> bool:
	var rating_value: Variant = data.get("eloRating", null)
	return (rating_value is float or rating_value is int) and is_finite(float(rating_value))


func _begin_elo_v2_attempt_for_entry(formal_entry: bool) -> void:
	_elo_v2_formal_main = (
		formal_entry and _level_kind == LevelKind.MAIN and int(_level_config.get("level", 0)) > 0
	)
	if not _elo_v2_formal_main or not ABTestManager.normal_level.is_elo_v2_active():
		return
	var size: int = int(_level_config.get("size", 0))
	var puzzle_id: String = str(_level_config.get("_puzzle_id", ""))
	if puzzle_id.is_empty():
		var regions: Array = _puzzle.get("regions", [])
		if regions.is_empty() or size <= 0:
			return
		puzzle_id = LevelData.compute_puzzle_id(size, regions)
		_level_config["_puzzle_id"] = puzzle_id
	var vector: Dictionary = _level_config.get("style_vector", {}).duplicate(true)
	vector["style_size"] = size
	_level_config["style_vector"] = vector
	var level: int = int(_level_config.get("level", 0))
	var rank: int = int(_level_config.get("rank", 0))
	var rating_value: Variant = _level_config.get("eloRating", null)
	var has_rating: bool = rating_value is float or rating_value is int
	var puzzle_rating: float = float(rating_value) if has_rating else -1.0
	has_rating = has_rating and is_finite(puzzle_rating)
	if not has_rating:
		puzzle_rating = -1.0
	var eligible: bool = (
		level >= 21
		and rank in [3, 4, 5]
		and not _is_super_hard_level
		and bool(_level_config.get("is_elo_delivery", false))
		and has_rating
	)
	var previous: Dictionary = GameState.get_elo_v2_attempt()
	GameState.begin_elo_v2_attempt(level, puzzle_id, rank, puzzle_rating, vector, eligible)
	if eligible:
		var player_rating: float = GameState.get_elo_rating(rank)
		_level_config["_elo_player_rating"] = player_rating
		_level_config["_elo_e"] = EloRatingMath.e_from_ratings(puzzle_rating, player_rating)
		_level_config["_elo_k"] = EloV2Performance.k_for_games(GameState.get_elo_games(rank))
		if previous.is_empty() and _stat_status != Tracker.GameStatus.NEW:
			var round_stats: Dictionary = GameState.get_game_round_stats(Tracker.GameType.NORMAL)
			var restarts: int = int(round_stats.get("restart_count", 0))
			if _stat_status == Tracker.GameStatus.RESTART:
				restarts = maxi(0, restarts - 1)
			GameState.merge_elo_v2_resume_facts(
				restarts,
				GameState.is_dda_tool_or_revive_used(),
				GameState.get_elo_fish_consumed(),
				int(round_stats.get("gamedie_count", 0))
			)
	if _stat_status == Tracker.GameStatus.RESTART:
		_record_elo_v2_action("restart")


func _has_current_elo_v2_attempt() -> bool:
	if not _elo_v2_formal_main or not ABTestManager.normal_level.is_elo_v2_active():
		return false
	if _level_kind != LevelKind.MAIN:
		return false
	var facts: Dictionary = GameState.get_elo_v2_attempt()
	return (
		int(facts.get("level", 0)) == int(_level_config.get("level", 0))
		and str(facts.get("puzzle_id", "")) == str(_level_config.get("_puzzle_id", ""))
	)


func _record_elo_v2_action(action: String) -> void:
	if _has_current_elo_v2_attempt():
		GameState.record_elo_v2_action(action)


func _capture_elo_v2_win_facts() -> void:
	if _has_current_elo_v2_attempt():
		GameState.set_elo_v2_win_facts(
			GameState.get_game_total_stat(Tracker.GameType.NORMAL, "time_total"), is_full_hp_win()
		)


func _capture_elo_v2_completed_snapshot_facts(snapshot: Dictionary) -> void:
	if (
		not ABTestManager.normal_level.is_elo_v2_active()
		or int(snapshot.get("kind", LevelKind.default_kind())) != LevelKind.MAIN
	):
		return
	var level: int = int(snapshot.get("level", 0))
	var size: int = int(snapshot.get("size", 0))
	var rank: int = int(snapshot.get("r", 0))
	var vector: Dictionary = snapshot.get("style_vector", {}).duplicate(true)
	vector["style_size"] = size
	var puzzle_id: String = str(snapshot.get("_puzzle_id", ""))
	if puzzle_id.is_empty():
		puzzle_id = LevelData.compute_puzzle_id(size, snapshot["regionMap"])
	var previous: Dictionary = GameState.get_elo_v2_attempt()
	var rating_value: Variant = snapshot.get("eloRating", null)
	var has_rating: bool = rating_value is float or rating_value is int
	var puzzle_rating: float = float(rating_value) if has_rating else -1.0
	has_rating = has_rating and is_finite(puzzle_rating)
	if not has_rating:
		puzzle_rating = -1.0
	var eligible: bool = (
		level >= 21
		and rank in [3, 4, 5]
		and int(snapshot.get("diffi", 0)) != 2
		and bool(snapshot.get("is_elo_delivery", false))
		and has_rating
	)
	GameState.begin_elo_v2_attempt(level, puzzle_id, rank, puzzle_rating, vector, eligible)
	if eligible:
		if previous.is_empty():
			var round_stats: Dictionary = GameState.get_game_round_stats(Tracker.GameType.NORMAL)
			GameState.merge_elo_v2_resume_facts(
				int(round_stats.get("restart_count", 0)),
				GameState.is_dda_tool_or_revive_used(),
				GameState.get_elo_fish_consumed(),
				int(round_stats.get("gamedie_count", 0))
			)
	GameState.set_elo_v2_win_facts(-1, int(snapshot.get("lives", 0)) == _life_cap)


func _record_rec_history(end_params: Dictionary, progress_state: String = "") -> void:
	var pre_cat_positions: Array = _level_config.get("prefill_positions", [])
	var record: Dictionary = LevelOps._extract_rec_history(
		end_params, progress_state, pre_cat_positions
	)
	if record.is_empty():
		return
	LevelRecManager.record_level_history(record)


func _on_golden_fish_skipped() -> void:
	RankActivityManager.notify_level_fail_abandon()
	if _last_fail_end_params.is_empty():
		return
	_record_rec_history(_last_fail_end_params, LevelOps.RecProgress.SKIP)


func _build_rec_extra() -> Dictionary:
	var d: Dictionary = {}
	var rec_qid: String = str(_level_config.get("_rec_qid", ""))
	if rec_qid.is_empty():
		return d
	d["decision_id"] = str(_level_config.get("_rec_decision_id", ""))
	d["user_id"] = RecApi._user_id()

	d["ts"] = int(Time.get_unix_time_from_system())
	d["slot_index"] = int(_level_config.get("_rec_slot_index", -1))
	d["served_qid"] = rec_qid
	d["rhythm_state"] = str(_level_config.get("_rec_rhythm_state", ""))
	d["selection_status"] = str(_level_config.get("_rec_selection_status", ""))
	d["fallback_reason"] = str(_level_config.get("_rec_fallback_reason", ""))
	d["intended_optimal_qid"] = str(_level_config.get("_rec_intended_optimal_qid", ""))

	d["is_explore"] = 1 if bool(_level_config.get("_rec_is_explore", false)) else 0
	return d


const _TOP_GAP_FLOOR: float = 0.0

const _AD_GAP_SQUEEZED: float = 13.0


func _apply_top_gap_for_short_screen() -> void:
	var vbox: Control = get_node_or_null(^"Root/VBoxContainer") as Control
	if vbox == null:
		return
	var cat_holder: Control = vbox.get_node_or_null(^"CatAdaptHolder") as Control
	var ad_holder: Control = vbox.get_node_or_null(^"AdAdaptHolder") as Control
	if cat_holder == null or ad_holder == null:
		return

	var base_min_h: float = vbox.get_combined_minimum_size().y
	var raised_min_h: float = (
		base_min_h + maxf(0.0, _TOP_GAP_FLOOR - cat_holder.custom_minimum_size.y)
	)
	cat_holder.custom_minimum_size.y = maxf(cat_holder.custom_minimum_size.y, _TOP_GAP_FLOOR)
	var parent: Control = vbox.get_parent() as Control
	if parent == null:
		return

	var avail_h: float = (
		parent.size.y * (vbox.anchor_bottom - vbox.anchor_top)
		+ vbox.offset_bottom
		- vbox.offset_top
	)

	if avail_h <= 0.0:
		avail_h = get_viewport_rect().size.y
	if raised_min_h <= avail_h:
		return
	ad_holder.custom_minimum_size.y = minf(ad_holder.custom_minimum_size.y, _AD_GAP_SQUEEZED)
