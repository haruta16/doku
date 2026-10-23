## 首页协调器：刷新活动入口和续玩状态，按优先队列串起登录、奖励、引导与活动弹窗。
class_name HomePage
extends UIFrameWindow

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _start_btn: Control = $Root/StartBtn # 开始按钮（BtnWithTag 场景，用 Control 类型以便设置 show_difficult）
@onready var _anim: AnimationPlayer = $AnimationPlayer # 首页主界面动画 MainInterface

@onready var _companion: Control = $Root/HomeCompanionPanel
var _home_companion_strategy: HomeCompanionCatStrategy
var _companion_entry_generation: int = 0
var _companion_entry_pending: bool = false

@onready var _daily_btn: Button = $Root/DailyBtn # 每日挑战按钮外层，只用于绑按压缩放
@onready var _daily_bg: Button = $Root/DailyBtn/Bg # 每日按钮可换肤的背景
@onready var _daily_shadow: NinePatchRect = $Root/DailyBtn/Shadow # 按钮投影，锁定态隐藏
@onready var _daily_lock_icon: HBoxContainer = $Root/DailyBtn/LockIcon # 锁定态：锁图标 + 文案
@onready var _daily_lock_label: Label = $Root/DailyBtn/LockIcon/LockLabel # 锁定态文案
@onready var _daily_unlock_box: HBoxContainer = $Root/DailyBtn/UnlockBox # 可玩 / 已完成态：猫爪 + 文案
@onready var _daily_unlock_label: Label = $Root/DailyBtn/UnlockBox/UnlockLabel # 可玩 / 已完成态文案
@onready var _daily_done_tag: Panel = $Root/DailyBtn/DoneTag # 已完成角标（用时）
@onready var _daily_done_time: Label = $Root/DailyBtn/DoneTag/DoneHBox/DoneTimeLabel # 已完成用时文案
@onready var _daily_top_tag: Control = $Root/DailyBtn/TopTag # 已完成右上角名次标签
@onready var _daily_top_label: Label = $Root/DailyBtn/TopTag/TopLabel # 名次文案
@onready var _countdown_tag: Panel = $Root/DailyBtn/CountdownTag # 倒计时角标（可玩态显示）
@onready var _daily_paw: TextureRect = $Root/DailyBtn/UnlockBox/Paw # 猫爪图标（按 A/B 换亮 / 暗贴图）
# ---- 倒计时与动画 ----
@onready var _countdown_label: Label = $Root/DailyBtn/CountdownTag/HBox/CountdownLabel # 倒计时文案 HH:MM:SS
@onready var _countdown_hbox: HBoxContainer = $Root/DailyBtn/CountdownTag/HBox
@onready var _countdown_icon: TextureRect = $Root/DailyBtn/CountdownTag/HBox/TimerIcon
@onready var _daily_done_hbox: HBoxContainer = $Root/DailyBtn/DoneTag/DoneHBox
@onready var _daily_done_icon: TextureRect = $Root/DailyBtn/DoneTag/DoneHBox/DoneTimeIcon

@onready var _daily_players_row: DcPlayersJoinedRow = $Root/DailyBtn/PlayersJoinedRow

@onready var _daily_cat_wrap: Control = $Root/DailyBtn/UnlockBox/CatWrap

@onready var _daily_cat_icon: TextureRect = $Root/DailyBtn/UnlockBox/CatWrap/CatSlot/CatIcon

@onready var _daily_cat_shadow: TextureRect = $Root/DailyBtn/UnlockBox/CatWrap/CatShadow

@onready var _daily_cat_anchor: Node2D = $Root/DailyBtn/UnlockBox/CatWrap/CatSlot/CatAnchor

var _daily_cat_spine: SpineSprite = null

# ---- 可调参数（Inspector 可改） ----
@export var _daily_paw_tex_lit: Texture2D # 猫爪亮色贴图（已完成态）
@export var _daily_paw_tex_dim: Texture2D # 猫爪暗色贴图（未完成态）

@export var _logo_skin: String = "logo"
@export var _halloween_logo_skin: String = "halloween"

# ---- 每日按钮的原始样式缓存（首次显示时记下，换肤后靠它还原） ----
var _daily_sf_normal: StyleBox # Bg 的 normal 原始样式
var _daily_sf_pressed: StyleBox # Bg 的 pressed 原始样式

# ---- 入口格子场景（daily_streak A/B 的新版首页布局用） ----
## 每日挑战入口格子，在新版布局里替代原来的 DailyBtn
const _DC_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/daily/ui/daily_challenge_entry_cell.tscn"
)
## 连续打卡入口格子
const _STREAK_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/daily_streak/ui/streak_entry_cell.tscn"
)

const _STREAK_MINI_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/daily_streak/ui/streak_mini_entry_cell.tscn"
)
const _RANK_MINI_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/rank_activity_mini_entry_cell.tscn"
)

const _RANK_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/rank_activity_entry_cell.tscn"
)

const _STREAK_TOP_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/daily_streak/ui/streak_entry_top_cell.tscn"
)

const _RANK_LEFT_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/rank_activity_entry_left_cell.tscn"
)

const _SIDE_BAR_DC_ENABLED: bool = false
const _DC_LEFT_ENTRY_CELL: PackedScene = preload(
	"res://scripts/module/daily/ui/daily_challenge_entry_left_cell.tscn"
)

const _AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")

const _PEEKABOO_CAT_CELL: PackedScene = preload(
	"res://scripts/module/peekaboo/ui/peekaboo_cat_cell.tscn"
)

@onready var _streak_layout: Control = $Root/home_page_slot
@onready var _dc_slot: Control = $Root/home_page_slot/DcEntrySlot
@onready var _streak_slot: Control = $Root/home_page_slot/StreakEntrySlot
@onready var _streak_small_slot: Control = $Root/home_page_slot/StreakSmallEntrySlot
@onready var _rank_slot: Control = $Root/home_page_slot/RankEntrySlot

@onready var _streak_icon_slot: Control = $Root/home_page_slot/StreakIconSlot

@onready var _side_bar_left: VBoxContainer = $Root/home_page_slot/SideBarLeftSlot
@onready var _side_bar_right: VBoxContainer = $Root/home_page_slot/SideBarRightSlot

@onready var _peekaboo_slot: Control = $Root/PeekabooSlot

@onready var _pos_table: Control = $Root/home_page_pos

var _pos_origin: Dictionary = {}

# ---- Logo 与坐标备份 ----
@onready var _loge: Control = $Root/Loge # 猫头 Logo 容器

@onready var _logo_spine: SpineSprite = $Root/Loge/LogoSpine
@onready
var _logo_track_player: AnimationPlayer = $"Root/Loge/LogoSpine/SpineAnimationTrack/LogoSpine Track 0"

const _LOGO_ENTRY_ANIM: String = "Appear"

@onready var _profile_entry: Control = $Root/VBoxContainer/Header/ProfileEntry
@onready var _avatar_slot: Control = $Root/VBoxContainer/Header/ProfileEntry/AvatarSlot
@onready var _avatar_btn: Button = $Root/VBoxContainer/Header/ProfileEntry/AvatarBtn
var _avatar_cell = null
var _dc_cell = null # 动态创建的每日挑战格子（懒加载）
var _streak_cell = null # 动态创建的连续打卡格子（懒加载）
var _streak_mini_cell = null
var _rank_mini_cell = null

var _rank_cell = null
var _streak_top_cell = null
var _rank_left_cell = null
var _dc_left_cell = null
var _peekaboo_cell = null

var _peekaboo_presenting: bool = false
var _rank_popup_pending: bool = false

var _rank_session_waiting_for_setting: bool = false

var _rank_open_popup_deferred: bool = false

var _rank_layout_locked: bool = false
var _popup_queue: UIPopupQueue = UIPopupQueue.new()

const HOME_RESTORE_DELAY: float = 0.4 # 漏奖补发判定前的延迟（秒）

# ---- 诊断状态 ----
static var last_restore_status: String = "尚未触发补发判定" # 上次漏奖补发判定的结果，static 供 cheat 面板读取

# ---- 运行时状态 ----
var _is_exiting: bool = false # 是否正在转场离开首页

var _tap_diag_last_ms: int = 0 # 诊断用时间戳（除初始化外没有引用）
var _pending_page: String = "" # 转场目标页名
var _pending_params: Dictionary = {} # 转场目标页参数
var _new_page_node: Node = null # 转场后打开的新页面节点
var _setting_anchor_queued: bool = false
var _bottom_layout_queued: bool = false


func _ready() -> void:
	_bind_setting_anchor_updates()

	_avatar_cell = create_child(_AVATAR_CELL, {})
	_mount_into_slot(_avatar_cell, _avatar_slot)
	_avatar_cell.set_self()
	_avatar_btn.button_down.connect(func() -> void: play_press_scale(_profile_entry))
	_avatar_btn.button_up.connect(func() -> void: play_release_scale(_profile_entry))
	bind_press_release_scale($Root/DailyBtn)
	_fit_daily_btn_font()

	_daily_btn.visibility_changed.connect(_refresh_daily_cat_head)

	RankActivityManager.state_changed.connect(_on_rank_state_changed)

	RankActivityManager.period_opened.connect(_on_rank_period_opened)

	RankActivityManager.time_ticked.connect(_on_rank_time_ticked_for_peekaboo)

	claim_button_sound($Root/VBoxContainer/Header/SettingsBtn)

	DataSyncManager.data_sync_completed.connect(_on_cloud_sync_completed)

	AccountManager.progress_select_required.connect(_on_progress_select_required)

	AccountManager.account_deleted_notice_required.connect(_on_account_deleted_notice_required)

	var grid: Sprite2D = $Background/GridFlowLoop
	var vp_w: float = get_viewport_rect().size.x
	grid.position.x = vp_w / 2.0
	if vp_w > 1080.0:
		var grid_scale: float = (vp_w / 1080.0) * 1.02
		grid.scale = Vector2(grid_scale, grid_scale)


func _bind_setting_anchor_updates() -> void:
	var sources: Array[Control] = [$Root/VBoxContainer, $Root/VBoxContainer/Header]
	for source: Control in sources:
		if not source.item_rect_changed.is_connected(_queue_setting_anchor):
			source.item_rect_changed.connect(_queue_setting_anchor)
	var spacer: Control = $Root/VBoxContainer/HeaderAdaptHolder
	if not spacer.minimum_size_changed.is_connected(_queue_setting_anchor):
		spacer.minimum_size_changed.connect(_queue_setting_anchor)
	_queue_setting_anchor()


func _queue_setting_anchor() -> void:
	if _setting_anchor_queued:
		return
	_setting_anchor_queued = true
	_write_setting_anchor.call_deferred()


func _write_setting_anchor() -> void:
	_setting_anchor_queued = false
	var settings_button: Control = $Root/VBoxContainer/Header/SettingsBtn
	var header: Control = $Root/VBoxContainer/Header
	var container: VBoxContainer = $Root/VBoxContainer
	var header_top: float = 0.0
	var preceding_visible: bool = false
	var children: Array[Node] = container.get_children()
	for child: Node in children:
		var row: Control = child as Control
		if row == null or not row.visible:
			continue
		if preceding_visible:
			header_top += container.get_theme_constant("separation")
		if row == header:
			break
		header_top += row.get_combined_minimum_size().y
		preceding_visible = true
	var target_origin: Vector2 = container.get_global_transform() * Vector2(0.0, header_top)
	var center: float = (
		settings_button.get_global_rect().get_center().y
		+ target_origin.y
		- header.global_position.y
	)
	HomeSettingAnchor.set_settingbtn_y(center)


## 语言切换通知：刷新随语言变化的文案与字号
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()
		_fit_daily_btn_font()


func _refresh_dynamic_text() -> void:
	_start_btn.btn_text = tr("GAME_LEVEL_TITLE") % GameState.get_current_level()
	_apply_start_btn_golden_style()
	_apply_start_btn_continue_style()


func _apply_start_btn_golden_style() -> void:
	var is_golden: bool = _is_start_btn_golden()
	GoldenFishBtnStyle.apply(_start_btn, is_golden)

	ColorChallengeBtnStyle.apply(_start_btn, (not is_golden) and _is_start_btn_color_challenge())


func _is_start_btn_golden() -> bool:
	return GoldenFishGate.should_show_golden_style(
		GameState.get_current_level(),
		GameState.get_available_golden_fish_pending(),
		ABTestManager.golden_fish_func.is_enabled(),
		ABTestManager.golden_fish_timing.unlock_min_level()
	)


func _is_start_btn_color_challenge() -> bool:
	return ColorChallengeGate.should_show_style(
		GameState.get_current_level(),
		GameState.get_color_challenge_pending(),
		ABTestManager.color_challenge_func.group_value()
	)


func _apply_start_btn_difficulty(lv: int) -> void:
	var is_super_hard: bool = LevelSelector.is_super_hard_level(lv)
	_start_btn.super_hard = is_super_hard
	_start_btn.show_difficult = is_super_hard or LevelSelector.is_hard_level(lv)
	_start_btn.hard_effect_variant = ABTestManager.hard_button.effect_variant()


func _apply_start_btn_continue_style() -> void:
	_start_btn.sub_text = ""

	if _is_start_btn_golden():
		return
	if StaleEndgameGate.is_pending_stale_discard():
		return
	var lv: int = GameState.get_current_level()
	var snap: Dictionary = GameState.get_endgame_snapshot()
	if not ContinueEntryStats.has_player_progress(snap, lv):
		return
	if ContinueEntryStats.is_legacy_snapshot(snap):
		return
	var cfg: LevelBtnContinueConfig = ABTestManager.level_btn_continue
	if not cfg.is_enabled():
		return

	_start_btn.btn_text = tr("WIN_CONTINUE")
	if cfg.shows_progress():
		var pct: float = ContinueEntryStats.progress_percent(snap)
		_start_btn.sub_text = tr("HOME_CONTINUE_COMPLETED") % ContinueEntryStats.format_percent(pct)
	elif cfg.shows_time():
		var play_sec: float = float(snap.get(ContinueEntryStats.SNAP_KEY_PLAY_SEC, 0.0))
		_start_btn.sub_text = (
			tr("HOME_CONTINUE_STARTED") % ContinueEntryStats.format_play_time(play_sec)
		)
	elif cfg.shows_level_with_continue():
		_start_btn.sub_text = tr("GAME_LEVEL_TITLE") % lv


func _start_btn_name() -> String:
	if _is_start_btn_golden():
		return Tracker.Btn.GOLDEN_FISH_PLAY
	if _is_start_btn_color_challenge():
		return Tracker.Btn.COLOR_CHALLENGE_PLAY
	return Tracker.Btn.NORMAL_PLAY


func _on_cloud_sync_completed(changed: bool) -> void:
	if not changed or not visible:
		return
	_refresh_progress_display()


func _refresh_progress_display() -> void:
	var lv: int = GameState.get_current_level()
	_refresh_dynamic_text()
	_apply_start_btn_difficulty(lv)
	_apply_start_btn_golden_style()

	_apply_start_btn_continue_style()
	_refresh_daily_btn_state()

	_relayout_rank_entries(true, false, false)


## 每日按钮字号下限（像素）
const _DAILY_BTN_MIN_FONT_SIZE: int = 44


## 每日按钮文案自适应：锁定态与可玩态的可用宽度不同，各自从上限逐步缩小到放得下
func _fit_daily_btn_font() -> void:
	# 两种形态显示的是同一个文案 key
	var display_text: String = tr("HOME_DAILY_CHALLENGE")
	# 按钮实际宽度 = 左右 offset 之差
	var btn_w: float = _daily_btn.offset_right - _daily_btn.offset_left
	# 锁定态可用宽度：扣掉锁图标 56 与右侧留白 40
	var lock_avail: float = btn_w - 56.0 - 40.0
	var lock_font: Font = _daily_lock_label.get_theme_font("font")
	var lock_fs: int = 80
	# 从 80 号字起每轮 -2，直到放得下或触到下限
	while lock_fs > _DAILY_BTN_MIN_FONT_SIZE:
		if (
			lock_font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lock_fs).x
			<= lock_avail
		):
			break
		lock_fs -= 2
	_daily_lock_label.add_theme_font_size_override("font_size", lock_fs)

	# 可玩态可用宽度：扣掉猫爪 100、间距 20、右侧留白 60
	var unlock_avail: float = btn_w - 100.0 - 20.0 - 60.0
	var unlock_font: Font = _daily_unlock_label.get_theme_font("font")
	# 从 66 号字起同样逐步缩小
	var unlock_fs: int = 66
	while unlock_fs > _DAILY_BTN_MIN_FONT_SIZE:
		if (
			unlock_font.get_string_size(display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, unlock_fs).x
			<= unlock_avail
		):
			break
		unlock_fs -= 2
	_daily_unlock_label.add_theme_font_size_override("font_size", unlock_fs)


## 刷新入口与陪伴策略，建立活动弹窗队列，再按推送或残局直开条件决定后续入口。
func on_show(_params: Dictionary = {}) -> void:
	UniKitManager.destroy_ad(AdPlacement.BANNER)

	_fire_home_10s_dye()

	SoundManager.start_bgm()

	HelpshiftManager.request_unread()
	_is_exiting = false
	_new_page_node = null
	_home_companion_strategy = HomeCompanionCatStrategy.create()
	_companion_entry_generation += 1
	_companion_entry_pending = false
	_companion.prepare_entry(_home_companion_strategy)
	connect_managed(get_viewport().size_changed, _queue_bottom_layout)
	connect_managed($Root/VBoxContainer.item_rect_changed, _queue_bottom_layout)
	_sync_companion_sound()
	connect_managed(_popup_queue.drained, _on_popup_queue_drained)
	connect_managed(UIManager.events.window_shown, _on_companion_cover_shown)
	connect_managed(UIManager.events.window_hidden, _on_companion_cover_hidden)
	_apply_halloween_logo()

	connect_managed(ProfileService.avatar_frame_changed, _on_profile_display_changed)

	connect_managed(ProfileService.costume_changed, _on_profile_display_changed)
	_on_profile_display_changed()
	$Root/VBoxContainer/Header/SettingsBtn.modulate.a = 0.0

	_queue_setting_anchor()
	$Root/StartBtn.modulate.a = 0.0
	$Root/DailyBtn.modulate.a = 0.0
	_anim.stop()

	_anim.play(&"RESET")
	_anim.advance(0.0)
	_anim.play_section_with_markers(&"MainInterface", &"", &"disappear")
	_anim.advance(0.0)
	if _daily_sf_normal == null:
		_daily_sf_normal = _daily_bg.get_theme_stylebox("normal")
		_daily_sf_pressed = _daily_sf_normal
	var lv: int = GameState.get_current_level()
	_refresh_dynamic_text()
	_apply_start_btn_difficulty(lv)
	_apply_start_btn_golden_style()

	_apply_start_btn_continue_style()

	DailyEntryState.ensure_max_daily_advanced()

	connect_managed(ClockTicker.second_tick, _update_countdown)

	_update_countdown()

	connect_managed(ProfileService.costume_changed, _refresh_daily_cat_head)
	_fit_daily_btn_font()

	RankActivityManager.set_first_frame_tiered(ABTestManager.rank_1st_frame.is_enabled())

	RankActivityManager.set_streak_rule(
		ABTestManager.rank_win.streak_table(),
		ABTestManager.rank_win.boost_spec(),
		ABTestManager.rank_win.x_base_rule()
	)
	RankActivityManager.on_home_shown(_is_end_solo_podium_enabled())

	connect_managed(RankActivityManager.settle_ready, _on_rank_settle_ready)

	_apply_home_layout()

	_apply_entry_shape_pos()

	_align_daily_btn_under_start()

	_apply_entry_shape_cells()

	_roll_dc_players_avatars()

	if _peekaboo_presenting:
		push_warning("[HomePage] 躲猫猫表现被打断(on_show 时仍在表现中)→ 强制释放闸门、布局锁与 blocker")
		_peekaboo_presenting = false
		set_rank_layout_locked(false)
		RankActivityManager.end_external_presentation()

		var stale_blocker: Node = find_child(PeekabooFlow.BLOCKER_NAME, false, false)
		if stale_blocker != null and not stale_blocker.is_queued_for_deletion():
			stale_blocker.queue_free()

	PeekabooManager.evaluate_on_cold_start()

	StreakManager.notify_group_dyed()
	_build_popup_queue()

	if _try_trigger_streak_push_open():
		return

	if _try_trigger_direct_open():
		return

	refresh_peekaboo_cat()
	_companion_entry_pending = true
	_popup_queue.flush()


func _on_popup_queue_drained() -> void:
	if _companion_entry_pending:
		_try_begin_companion_entry.bind(_companion_entry_generation).call_deferred()


func _on_companion_cover_hidden(_ui_name: String, _window: UIFrameWindow) -> void:
	_sync_companion_sound.call_deferred()
	_on_popup_queue_drained()


func _on_companion_cover_shown(_ui_name: String, _window: UIFrameWindow) -> void:
	_sync_companion_sound()


func _sync_companion_sound() -> void:
	_companion.cat.set_sound_enabled(
		is_showing() and not _is_exiting and UIManager.get_top_window() == self
	)


func _try_begin_companion_entry(generation: int) -> void:
	if generation != _companion_entry_generation or not _companion_entry_pending:
		return
	if not is_showing() or _is_exiting or UIManager.get_top_window() != self:
		return
	if _popup_queue.is_running() or not _popup_queue.is_empty():
		return
	_companion_entry_pending = false
	_sync_companion_sound()
	_companion.begin_entry()
	_enqueue_companion_guide(true)
	_popup_queue.flush()


func _enqueue_companion_guide(tutorial: bool) -> void:
	if not is_showing() or _is_exiting or not _companion.has_companion():
		return
	if tutorial and not _companion.tutorial_needed():
		return
	var priority: int = 0
	var configs: Array = _load_json_config(_POPUP_CONFIG_PATH)
	for config: Variant in configs:
		if config is Dictionary and str(config.get("OpenScene", "")) == "home":
			priority = maxi(priority, int(config.get("Priority", 0)))
	var entry: UIPopupEntry = UIPopupEntry.new()
	entry.key = "home_companion_guide"
	entry.priority = priority + 1
	entry.callable = _show_companion_guide.bind(tutorial)
	_popup_queue.cancel(entry.key)
	_popup_queue.enqueue(entry)


func _show_companion_guide(tutorial: bool) -> void:
	if not is_showing() or _is_exiting or not _companion.has_companion():
		return
	if tutorial and not _companion.tutorial_needed():
		return
	_companion.set_interaction_enabled(false)
	if tutorial:
		_companion.begin_tutorial()
	var generation: int = _companion_entry_generation
	var page: UIFrameWindow = UIManager.show_ui(
		UiName.HOME_COMPANION_GUIDE, _companion.guide_parameters(tutorial)
	)
	connect_managed(page.main_level_requested, _on_companion_main_level_requested)
	await UIManager.await_hidden(UiName.HOME_COMPANION_GUIDE)
	disconnect_managed(page.main_level_requested, _on_companion_main_level_requested)
	if generation != _companion_entry_generation:
		return
	if tutorial and page.was_completed():
		_companion.complete_tutorial()
	if is_showing() and not _is_exiting:
		if page.should_enter_main_level():
			enter_main_level()
			return
		_sync_companion_sound()
		if tutorial:
			_companion.resume_after_tutorial()
		_companion.set_interaction_enabled(true)


func _on_companion_main_level_requested() -> void:
	_companion_entry_pending = false
	_companion.stop_presentation()


func _on_companion_explanation_requested() -> void:
	_enqueue_companion_guide(false)
	if not _popup_queue.is_running():
		_popup_queue.flush()


## 把待演出的陪伴奖励合成一个队列项，先取消同键旧项以避免重复排队。
func _enqueue_companion_rewards() -> void:
	var pending: Array[int] = _companion.pending_reward_presentations()
	if pending.is_empty():
		return
	var entry: UIPopupEntry = UIPopupEntry.new()
	entry.key = "home_companion_reward"
	entry.priority = _find_popup_priority("vip_daily_gift")
	entry.callable = _show_companion_rewards
	_popup_queue.cancel(entry.key)
	_popup_queue.enqueue(entry)


func _enqueue_companion_end_popup() -> void:
	_popup_queue.cancel("home_companion_end")
	_consume_companion_switch_before_event_end()
	if not _should_show_companion_end_popup():
		return
	var entry: UIPopupEntry = UIPopupEntry.new()
	entry.key = "home_companion_end"
	entry.priority = _find_popup_priority("ab_switch_popup")
	entry.callable = _show_companion_end_popup
	_popup_queue.enqueue(entry)


func _consume_companion_switch_before_event_end() -> void:
	if (
		not ABTestManager.is_app_start_dyed()
		or _companion.event_ended()
		or _should_show_ab_switch_popup()
	):
		return
	var config: HomeCompanionCatConfig = ABTestManager.home_companion_cat
	var previous: int = config.get_prev_saved_group()
	if previous >= 0 and previous != config.peek_group():
		config.consume_switch()


func _should_show_companion_end_popup() -> bool:
	if not ABTestManager.is_app_start_dyed():
		return false
	var config: HomeCompanionCatConfig = ABTestManager.home_companion_cat
	var previous: int = config.get_prev_saved_group()
	var current: int = config.peek_group()
	if previous < 0 or previous == current:
		return false
	return _companion.closed_notice_needed(
		HomeCompanionCatStrategy.for_group(previous), HomeCompanionCatStrategy.for_group(current)
	)


func _show_companion_end_popup() -> void:
	if not is_showing() or _is_exiting or not _should_show_companion_end_popup():
		return
	var page: UIFrameWindow = (
		UIManager
		. show_ui(
			UiName.AB_SWITCH_POPUP,
			{
				"title": tr("HOME_COMPANION_END_TITLE"),
				"body": tr("HOME_COMPANION_END_BODY"),
				"btn_text": tr("HOME_COMPANION_END_CONFIRM"),
				"feedback": "1",
				"reward": {},
			}
		)
	)
	if page == null:
		return

	ABTestManager.home_companion_cat.consume_switch()
	await UIManager.await_hidden(UiName.AB_SWITCH_POPUP)


func _show_companion_rewards() -> void:
	var pending: Array[int] = _companion.pending_reward_presentations()
	var generation: int = _companion_entry_generation
	for tier: int in pending:
		if generation != _companion_entry_generation or not is_showing() or _is_exiting:
			return
		var current_pending: Array[int] = _companion.pending_reward_presentations()
		if not current_pending.has(tier):
			continue
		_companion.set_interaction_enabled(false)
		var page: UIFrameWindow = UIManager.show_ui(
			UiName.HOME_COMPANION_REWARD,
			{"reward_tier": tier, "chest_from": _companion.chest_global_center()}
		)
		await UIManager.await_hidden(UiName.HOME_COMPANION_REWARD)
		if generation != _companion_entry_generation:
			return
		if page.was_collected():
			_companion.complete_reward_presentation(tier)
		else:
			break
	if is_showing() and not _is_exiting:
		_companion.set_interaction_enabled(true)


func _fire_home_10s_dye() -> void:
	await get_tree().create_timer(10.0).timeout
	ABTestManager.dye_at_home_page_10s()


func on_stack_top() -> void:
	_sync_companion_sound()
	_on_popup_queue_drained()

	_apply_halloween_logo()
	_repair_logo_entry_pose()

	_relayout_rank_entries()
	if _rank_open_popup_deferred:
		_enqueue_deferred_rank_open_popup.call_deferred()


func on_stack_bottom() -> void:
	_companion.cat.set_sound_enabled(false)


func try_open_rank_for_new_session() -> void:
	if not is_showing() or _is_exiting:
		return
	if not RankActivityManager.maybe_open(true):
		return
	var setting: UIFrameWindow = UIManager.get_ui(UiName.SETTING)
	_rank_session_waiting_for_setting = (
		setting != null and setting.get_window_state() != UIBaseWindow.WindowState.HIDDEN
	)
	if _rank_session_waiting_for_setting:
		connect_managed(UIManager.events.window_hidden, _on_rank_session_cover_hidden)


func _on_rank_session_cover_hidden(ui_name: String, _window: UIFrameWindow) -> void:
	if ui_name != UiName.SETTING:
		return
	_rank_session_waiting_for_setting = false
	disconnect_managed(UIManager.events.window_hidden, _on_rank_session_cover_hidden)
	_enqueue_deferred_rank_open_popup.call_deferred()


func _apply_halloween_logo() -> void:
	var data: SpineSkeletonDataResource = _logo_spine.get_skeleton_data_res()
	var skeleton: SpineSkeleton = _logo_spine.get_skeleton()
	if data == null or skeleton == null:
		return
	var skin_name: String = (
		_halloween_logo_skin if _companion.halloween_dress_active() else _logo_skin
	)
	var skin: SpineSkin = data.find_skin(skin_name)
	var current_skin: SpineSkin = skeleton.get_skin()
	if current_skin != null and current_skin.get_name() == skin_name:
		return
	if skin == null:
		push_warning("HomePage: logo 骨架缺皮肤 %s，回落 default" % skin_name)
		if current_skin == null:
			return
	skeleton.set_skin(skin)
	skeleton.set_slots_to_setup_pose()
	_logo_spine.update_skeleton(0.0)


func _repair_logo_entry_pose() -> void:
	if _logo_track_player.is_playing():
		return
	var state: SpineAnimationState = _logo_spine.get_animation_state()
	if state == null:
		return
	var current: SpineTrackEntry = state.get_current(0)
	if current != null and current.get_animation().get_name() == _LOGO_ENTRY_ANIM:
		return
	var entry: SpineTrackEntry = state.set_animation(_LOGO_ENTRY_ANIM, false, 0)
	entry.set_track_time(entry.get_animation_end())


const _POPUP_CONFIG_PATH: String = "res://assets/cfg/dialog_priority_strategy.json"


## 从配置读取首页弹窗及优先级，过滤条件后追加奖励、账号和云进度冲突提示。
func _build_popup_queue() -> void:
	if _popup_queue.is_running():
		return
	_popup_queue.clear()
	var configs: Array = _load_json_config(_POPUP_CONFIG_PATH)
	for cfg in configs:
		if not cfg is Dictionary:
			continue
		if str(cfg.get("OpenScene", "")) != "home":
			continue
		var key: String = str(cfg.get("Key", ""))
		var priority: int = int(cfg.get("Priority", 0))
		var method_name: String = "_show_%s" % key
		if not has_method(method_name):
			push_warning("UIPopupQueue: no method '%s' on HomePage, skipping" % method_name)
			continue

		var should_method: String = "_should_show_%s" % key
		if has_method(should_method) and not call(should_method):
			continue
		var entry := UIPopupEntry.new()
		entry.key = key
		entry.priority = priority
		entry.callable = Callable(self, method_name)
		_popup_queue.enqueue(entry)
	_enqueue_companion_rewards()
	_enqueue_companion_end_popup()

	_enqueue_login_result_popup()

	_enqueue_progress_select_popup()

	_enqueue_account_deleted_popup()


## 先消费本次直开门禁，再检查关卡、有效残局、实验和弹窗队列，满足才安排直接续玩。
func _try_trigger_direct_open() -> bool:
	var lv: int = GameState.get_current_level()
	var ab_val: int = ABTestManager.unfinished_game_open.value()
	var today_ses: int = GameState.get_today_session_count()

	if not GameState.try_consume_direct_open_gate():
		print(
			(
				"[UnfinishedOpen] SKIP reason=gate_consumed (level=%d ab=%d today_ses=%d)"
				% [lv, ab_val, today_ses]
			)
		)
		return false
	if lv < 50:
		print("[UnfinishedOpen] SKIP reason=level<50 (level=%d ab=%d)" % [lv, ab_val])
		return false
	if not _has_valid_endgame_snapshot():
		var snap: Dictionary = GameState.get_endgame_snapshot()
		var placed_n: int = (
			(snap.get("placed_cats", []) as Array).size() if not snap.is_empty() else 0
		)
		var prefill_n: int = (
			(snap.get("prefill_positions", []) as Array).size() if not snap.is_empty() else 0
		)
		var marks_n: int = (snap.get("marks", []) as Array).size() if not snap.is_empty() else 0
		var errors_n: int = (snap.get("errors", []) as Array).size() if not snap.is_empty() else 0
		print(
			(
				"[UnfinishedOpen] SKIP reason=invalid_endgame (empty=%s snap_level=%d cur_level=%d lives=%d placed=%d prefill=%d marks=%d errors=%d)"
				% [
					snap.is_empty(),
					int(snap.get("level", -1)),
					lv,
					int(snap.get("lives", -1)),
					placed_n,
					prefill_n,
					marks_n,
					errors_n
				]
			)
		)
		return false
	var cfg := ABTestManager.unfinished_game_open
	if not cfg.is_enabled():
		print("[UnfinishedOpen] SKIP reason=ab_control (ab=%d level=%d)" % [ab_val, lv])
		return false
	if cfg.requires_non_first_session() and today_ses <= 1:
		print(
			"[UnfinishedOpen] SKIP reason=first_session (ab=%d today_ses=%d)" % [ab_val, today_ses]
		)
		return false
	if not _popup_queue.is_empty():
		print("[UnfinishedOpen] SKIP reason=popup_queue_not_empty (ab=%d level=%d)" % [ab_val, lv])
		return false
	print(
		(
			"[UnfinishedOpen] TRIGGER (level=%d ab=%d today_ses=%d) → waiting entry anim"
			% [lv, ab_val, today_ses]
		)
	)
	_trigger_direct_open()
	return true


func _has_valid_endgame_snapshot() -> bool:
	return ContinueEntryStats.has_player_progress(
		GameState.get_endgame_snapshot(), GameState.get_current_level()
	)


func cheat_force_direct_open() -> void:
	if _is_exiting or not is_showing():
		print(
			(
				"[UnfinishedOpen] cheat direct_open aborted (home not showing, exiting=%s showing=%s)"
				% [_is_exiting, is_showing()]
			)
		)
		return
	print("[UnfinishedOpen] cheat direct_open: bypassing all gates → exit_to_page(game)")
	_exit_to_page(
		"game",
		{
			"level_index": GameState.get_current_level(),
			"endgame_restore": true,
			"from_direct_open": true,
		}
	)


enum StreakPushPending {
	NONE,
	COLD_START_CLICK,
}

static var pending_push_click: StreakPushPending = StreakPushPending.NONE


func _try_trigger_streak_push_open() -> bool:
	var click_src: StreakPushPending = pending_push_click
	pending_push_click = StreakPushPending.NONE
	if click_src != StreakPushPending.COLD_START_CLICK:
		return false
	if not _has_valid_endgame_snapshot():
		print("[StreakPush] direct open skip: no valid endgame, stay on home")
		return false
	var blockers: Dictionary = _collect_streak_push_blockers()
	if not blockers.is_empty() and not _only_rank_open_blockers(blockers):
		print(
			"[StreakPush] direct open skip: popups pending(%s), stay on home" % str(blockers.keys())
		)
		return false
	print(
		"[StreakPush] direct open TRIGGER (blockers=%s) → waiting entry anim" % str(blockers.keys())
	)
	_trigger_direct_open()
	return true


func _collect_streak_push_blockers() -> Dictionary:
	var blockers: Dictionary = {}
	for pending_key: String in _popup_queue.pending_keys():
		blockers[pending_key] = true
	return blockers


func _only_rank_open_blockers(blockers: Dictionary) -> bool:
	var rank_open_like: Dictionary = {}
	for blocker_key: String in blockers:
		if blocker_key == "rank_open_popup":
			rank_open_like[blocker_key] = true
			continue
		if blocker_key == "rank_reward_and_tryopen_popup":
			var has_reward_semantics: bool = (
				not RankActivityManager.get_pending_reward().is_empty()
				or (
					not RankActivityManager.get_pending_end_solo_podium().is_empty()
					and _is_end_solo_podium_enabled()
				)
			)
			if not has_reward_semantics:
				rank_open_like[blocker_key] = true
	return rank_open_like.size() == blockers.size()


func _trigger_direct_open() -> void:
	connect_managed(_anim.animation_finished, _on_direct_open_anim_finished)


func _on_direct_open_anim_finished(anim_name: StringName) -> void:
	if anim_name != &"MainInterface":
		return

	disconnect_managed(_anim.animation_finished, _on_direct_open_anim_finished)

	if _is_exiting or not is_showing():
		print(
			(
				"[UnfinishedOpen] anim finished but home not eligible (exiting=%s showing=%s), abort"
				% [_is_exiting, is_showing()]
			)
		)
		return
	print(
		"[UnfinishedOpen] entry anim finished → exit_to_page(game, endgame_restore + from_direct_open)"
	)
	_exit_to_page(
		"game",
		{
			"level_index": GameState.get_current_level(),
			"endgame_restore": true,
			"from_direct_open": true,
		}
	)


func _enqueue_login_result_popup() -> void:
	var pending: AccountFlowResult = AccountManager.take_pending_result()
	if pending == null:
		return
	var entry := UIPopupEntry.new()
	entry.key = "login_result"

	entry.priority = 19999
	entry.callable = func() -> void:
		await get_tree().process_frame
		if _is_exiting or not visible:
			return
		(
			UIManager
			. show_ui(
				UiName.ACCOUNT_RESULT,
				{
					"type": pending.type,
					"channel": pending.channel,
				}
			)
		)

		await UIManager.await_hidden(UiName.ACCOUNT_RESULT)
	_popup_queue.insert_next(entry)


func _enqueue_progress_select_popup() -> void:
	var conflict: ProgressConflict = AccountManager.refresh_progress_conflict()
	if conflict == null:
		return
	_popup_queue.cancel("progress_select")
	var entry := UIPopupEntry.new()
	entry.key = "progress_select"

	entry.priority = 20000
	entry.callable = func() -> void:
		await get_tree().process_frame
		if _is_exiting or not visible:
			return
		UIManager.show_ui(UiName.PROGRESS_SELECT, {"conflict": conflict})
		await UIManager.await_hidden(UiName.PROGRESS_SELECT)
	_popup_queue.insert_next(entry)


func _on_progress_select_required() -> void:
	if _is_exiting or not visible:
		print("[HomePage] 收到进度选择请求但 home 未显示，等 on_show 取")
		return
	_enqueue_progress_select_popup()
	if not _popup_queue.is_running():
		_popup_queue.flush()


func _enqueue_account_deleted_popup() -> void:
	if not AccountManager.has_pending_account_deleted():
		return
	_popup_queue.cancel("account_deleted")
	var entry := UIPopupEntry.new()
	entry.key = "account_deleted"

	entry.priority = 20001
	entry.callable = func() -> void:
		await get_tree().process_frame
		if _is_exiting or not visible:
			return

		UIManager.show_ui(UiName.ACCOUNT_DELETED)
		await UIManager.await_hidden(UiName.ACCOUNT_DELETED)
	_popup_queue.insert_next(entry)


func _on_account_deleted_notice_required() -> void:
	if _is_exiting or not visible:
		print("[HomePage] 收到账号已销毁告知但 home 未显示，等 on_show 取")
		return
	_enqueue_account_deleted_popup()
	if not _popup_queue.is_running():
		_popup_queue.flush()


func _load_json_config(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Array else []


func _find_popup_priority(key: String) -> int:
	for cfg in _load_json_config(_POPUP_CONFIG_PATH):
		if cfg is Dictionary and str(cfg.get("Key", "")) == key:
			return int(cfg.get("Priority", 0))
	return 0


const _AB_SWITCH_POPUP_CONFIG_PATH: String = "res://assets/cfg/ab_switch_popup_strategy.json"


## 解析逗号分隔的键值条件，花括号内的逗号属于整数集合而不是外层分隔符。
static func _parse_trigger_dsl(s: String) -> Dictionary:
	var result: Dictionary = {}
	var parts: PackedStringArray = []
	var buf: String = ""
	var depth: int = 0
	for c in s:
		if c == "{":
			depth += 1
			buf += c
		elif c == "}":
			depth -= 1
			buf += c
		elif c == "," and depth == 0:
			parts.append(buf.strip_edges())
			buf = ""
		else:
			buf += c
	if not buf.strip_edges().is_empty():
		parts.append(buf.strip_edges())
	for part in parts:
		var eq: int = part.find("=")
		if eq < 0:
			continue
		var k: String = part.substr(0, eq).strip_edges()
		var v: String = part.substr(eq + 1).strip_edges()
		if v.begins_with("{") and v.ends_with("}"):
			var inner: String = v.substr(1, v.length() - 2)
			var nums: Array[int] = []
			for item in inner.split(","):
				var t: String = item.strip_edges()
				if t.is_valid_int():
					nums.append(t.to_int())
			result[k] = nums
		else:
			result[k] = v
	return result


func _check_abtest_switch_trigger(trigger: Dictionary) -> bool:
	var key: String = str(trigger.get("key", ""))
	var bf: Array = trigger.get("bf", [])
	var af: Array = trigger.get("af", [])

	if not ABTestManager.is_app_start_dyed():
		return false
	match key:
		_:
			var cfg: AbConfigBase = ABTestManager.find_config(key)
			if cfg == null:
				return false
			var prev: int = cfg.get_prev_saved_group()
			if prev == -1:
				return false

			var current: int = int(cfg.peek_value())
			if prev == current:
				return false
			if not (prev in bf and current in af):
				return false
			return not _is_switch_notice_suppressed(key)


func _is_switch_notice_suppressed(key: String) -> bool:
	match key:
		"dc_costume":
			return GameState.get_current_level() < DailyEntryState.UNLOCK_LEVEL
		_:
			return false


func _should_show_ab_switch_popup() -> bool:
	var entries: Array = _load_json_config(_AB_SWITCH_POPUP_CONFIG_PATH)
	var streak_page: int = StreakManager.get_pending_switch_page()
	var daily_streak_idx: int = 0
	for entry in entries:
		if not entry is Dictionary:
			continue
		var trigger_str: String = str(entry.get("Trigger", ""))
		var trigger: Dictionary = _parse_trigger_dsl(trigger_str)
		if str(trigger.get("trigger", "")) != "abtest_switch":
			continue
		var entry_key: String = str(trigger.get("key", ""))
		if entry_key == "daily_streak":
			daily_streak_idx += 1
			if streak_page > 0 and daily_streak_idx == streak_page:
				return true
		else:
			if _check_abtest_switch_trigger(trigger):
				return true
	return false


func _show_ab_switch_popup() -> void:
	var entries: Array = _load_json_config(_AB_SWITCH_POPUP_CONFIG_PATH)

	var streak_page: int = StreakManager.get_pending_switch_page()
	var daily_streak_idx: int = 0

	var matched: Dictionary = {}
	var matched_key: String = ""
	for entry in entries:
		if not entry is Dictionary:
			continue
		var trigger_str: String = str(entry.get("Trigger", ""))
		var trigger: Dictionary = _parse_trigger_dsl(trigger_str)
		if str(trigger.get("trigger", "")) != "abtest_switch":
			continue
		var entry_key: String = str(trigger.get("key", ""))
		var matched_this: bool = false
		if entry_key == "daily_streak":
			daily_streak_idx += 1
			matched_this = streak_page > 0 and daily_streak_idx == streak_page
		else:
			matched_this = _check_abtest_switch_trigger(trigger)
		if matched_this:
			matched = entry
			matched_key = entry_key
			break

	if matched.is_empty():
		return

	await get_tree().create_timer(0.1).timeout
	if not visible or _is_exiting:
		return

	var params: Dictionary = AbSwitchPopup.parse_param(str(matched.get("Param", "")))

	var grant_reward: Dictionary = params.get("reward", {})

	var exchange: Dictionary = params.get("exchange_reward", {})
	var ex_from: String = str(exchange.get("from", ""))
	var ex_to: String = str(exchange.get("to", ""))
	var ex_count: int = 0
	if ToolKind.is_valid(ex_from) and ToolKind.is_valid(ex_to):
		if _is_exchange_kind_unlocked(ex_from):
			ex_count = GameState.get_tool_count(ex_from)
	elif not exchange.is_empty():
		push_error("home_page: exchange_reward 的 kind 非法, from=%s to=%s" % [ex_from, ex_to])

	if ex_count > 0:
		var show_reward: Dictionary = grant_reward.duplicate()
		show_reward[ex_to] = int(show_reward.get(ex_to, 0)) + ex_count
		params["reward"] = show_reward

	if not exchange.is_empty():
		if ex_count > 0:
			var base_body: String = str(params.get("body", ""))
			var gift_line: String = tr("HERE_A_GIFT_FOR_YOU")
			if base_body.is_empty():
				params["body"] = gift_line
			else:
				params["body"] = "%s\n%s" % [tr(base_body).strip_edges(), gift_line]
			params["btn_text"] = "AD_REWARD_RESTORED_COLLECT"
		else:
			params["btn_text"] = "HOW_TO_PLAY_GOT_IT"

	if matched_key == "rank_1st_frame":
		var comp: Dictionary = _rank_frame_switch_reward(ProfileService.get_max_unlocked_form())
		if not comp.is_empty():
			var show_reward: Dictionary = grant_reward.duplicate()
			for k: String in comp:
				show_reward[k] = int(show_reward.get(k, 0)) + int(comp[k])
			params["reward"] = show_reward

			grant_reward = show_reward
			params["body"] = "RANK_TIER_REFUND_GIFT"
			params["btn_text"] = "AD_REWARD_RESTORED_COLLECT"
		else:
			params["btn_text"] = "HOW_TO_PLAY_GOT_IT"

		ProfileService.set_frame_form(0)

	if matched_key == "dc_costume":
		if _prepare_dc_costume_switch_reward(params):
			grant_reward = params.get("reward", {})

	var win := UIManager.show_ui(UiName.AB_SWITCH_POPUP, params)
	if win == null:
		return

	_apply_all_switch_keys_to_current()
	await UIManager.await_hidden(UiName.AB_SWITCH_POPUP)

	var grant_kinds: Array = grant_reward.keys()
	for kind: String in grant_kinds:
		var count: int = int(grant_reward.get(kind, 0))
		if count > 0:
			GameState.set_tool_count(kind, GameState.get_tool_count(kind) + count)

	if ex_count > 0:
		GameState.exchange_tool_all(ex_from, ex_to)


func _rank_frame_switch_reward(form: int) -> Dictionary:
	match form:
		1:
			return {ToolKind.HINT: 1}
		2:
			return {ToolKind.HINT: 1, ToolKind.LOCATE: 1}
		3:
			return {ToolKind.HINT: 2, ToolKind.LOCATE: 1}
		4:
			return {ToolKind.HINT: 2, ToolKind.LOCATE: 2}
		_:
			return {}


const _DC_COSTUME_SWITCH_HINT: int = 1


func _prepare_dc_costume_switch_reward(params: Dictionary) -> bool:
	if not _has_unexpired_trial_costume():
		params["btn_text"] = "HOW_TO_PLAY_GOT_IT"
		return false
	var base_reward: Dictionary = params.get("reward", {})
	var show_reward: Dictionary = base_reward.duplicate()
	show_reward[ToolKind.HINT] = int(show_reward.get(ToolKind.HINT, 0)) + _DC_COSTUME_SWITCH_HINT
	params["reward"] = show_reward
	var base_body: String = str(params.get("body", ""))
	var gift_line: String = tr("HERE_A_GIFT_FOR_YOU")
	if base_body.is_empty():
		params["body"] = gift_line
	else:
		params["body"] = "%s\n%s" % [tr(base_body).strip_edges(), gift_line]
	params["btn_text"] = "AD_REWARD_RESTORED_COLLECT"
	return true


func _has_unexpired_trial_costume() -> bool:
	var costume_ids: Array[int] = CostumeCatalog.all_ids()
	for costume_id in costume_ids:
		if CostumeCatalog.is_trial(costume_id) and ProfileService.is_costume_held(costume_id):
			return true
	return false


func _is_exchange_kind_unlocked(from_kind: String) -> bool:
	if from_kind == ToolKind.MOUSE:
		return GameState.get_current_level() >= BaseGamePage.MOUSE_UNLOCK_LEVEL
	return true


func _apply_all_switch_keys_to_current() -> void:
	var seen: Dictionary = {}
	for entry in _load_json_config(_AB_SWITCH_POPUP_CONFIG_PATH):
		if not entry is Dictionary:
			continue
		var trigger: Dictionary = _parse_trigger_dsl(str(entry.get("Trigger", "")))
		if str(trigger.get("trigger", "")) != "abtest_switch":
			continue
		var key: String = str(trigger.get("key", ""))
		if key.is_empty() or seen.has(key):
			continue
		seen[key] = true
		match key:
			"daily_streak":
				StreakManager.consume_pending_switch()
			_:
				var cfg: AbConfigBase = ABTestManager.find_config(key)
				if cfg != null:
					cfg.consume_switch()


func _should_show_ad_reward_restored() -> bool:
	if not GameState.has_pending_rewards():
		return false
	var has_grantable: bool = false
	for pr in GameState.get_pending_rewards():
		var r_items: Array = UniKitManager.restore_items_for_position(str(pr.get("source", "")))
		if not r_items.is_empty():
			has_grantable = true
			break
	if not has_grantable:
		return false
	var now: int = int(Time.get_unix_time_from_system())
	if GameState.get_restore_remaining_today(now) <= 0:
		return false
	return true


func _show_ad_reward_restored() -> void:
	await get_tree().create_timer(HOME_RESTORE_DELAY).timeout
	if _is_exiting or not visible:
		last_restore_status = "延迟期间玩家已离开 home,放弃本次判定"
		return
	if not GameState.has_pending_rewards():
		last_restore_status = "无待补发奖励(漏奖队列为空)"
		return

	var grantable: Array = []
	for pr in GameState.get_pending_rewards():
		var r_items: Array = UniKitManager.restore_items_for_position(str(pr.get("source", "")))
		if r_items.is_empty():
			continue
		grantable.append({"entry": pr, "items": r_items})
	if grantable.is_empty():
		last_restore_status = "队列非空但无可补发道具(广告位非补发类)"
		GameState.pop_all_pending_rewards()
		return

	var now: int = int(Time.get_unix_time_from_system())
	var remaining: int = GameState.get_restore_remaining_today(now)
	if remaining <= 0:
		last_restore_status = "今日不补发(已达上限或防刷未过,今日已补发 %d 次)" % GameState.get_restored_today_count()
		return

	grantable.reverse()
	var to_grant: Array = grantable.slice(0, remaining)

	var by_kind: Dictionary = {}
	var granted_entries: Array = []
	for g in to_grant:
		for it in g.items:
			var gk: String = str(it.get("kind", ""))
			if gk == "":
				continue
			by_kind[gk] = int(by_kind.get(gk, 0)) + int(it.get("count", 0))
		granted_entries.append(g.entry)
	var rewards: Array = []
	for k in by_kind:
		rewards.append({"kind": k, "count": int(by_kind[k])})
	last_restore_status = (
		"本批弹出 %d 次补发/%d 种道具(今日可发 %d 次, 队列可补 %d 次)"
		% [to_grant.size(), rewards.size(), remaining, grantable.size()]
	)
	var page := UIManager.show_ui(UiName.AD_REWARD_RESTORED, {"rewards": rewards})
	if page == null:
		return

	var result := {"done": false}
	page.collected.connect(
		func(_rewards_collected: Array) -> void: result.done = true, CONNECT_ONE_SHOT
	)
	while not result.done:
		await get_tree().process_frame

	GameState.add_restored_today_count(to_grant.size())
	GameState.remove_pending_rewards(granted_entries)
	UIManager.hide_ui(UiName.AD_REWARD_RESTORED)


func _should_show_rank_reward_and_tryopen_popup() -> bool:
	if not RankActivityManager.get_pending_reward().is_empty():
		return true
	if (
		not RankActivityManager.get_pending_end_solo_podium().is_empty()
		and _is_end_solo_podium_enabled()
	):
		return true
	if RankActivityManager.is_open_not_joined():
		return true
	return false


func _show_rank_reward_and_tryopen_popup() -> void:
	var pending_reward: Dictionary = RankActivityManager.get_pending_reward()
	var reward_rank: int = int(pending_reward.get("rank", 0))
	if not pending_reward.is_empty():
		UIManager.show_ui(UiName.RANK_ACTIVITY_PAGE)
		await UIManager.await_hidden(UiName.RANK_ACTIVITY_PAGE)
	else:
		var shown: bool = await _run_end_solo_podium(true)
		if not shown:
			return

	await get_tree().process_frame
	await get_tree().process_frame

	if (
		reward_rank in [2, 3]
		and not _is_exiting
		and visible
		and _should_show_rank_frame_unlock_popup()
	):
		_popup_queue.cancel("rank_frame_unlock_popup")
		await _show_rank_frame_unlock_popup()
		if _is_exiting or not visible:
			return

	await _show_rank_open_popup()


func _is_end_solo_podium_enabled() -> bool:
	return ABTestManager.podium_per_leaderboard.has_end_solo_podium()


func _run_end_solo_podium(at_home: bool) -> bool:
	var pending: Dictionary = RankActivityManager.get_pending_end_solo_podium()
	if pending.is_empty():
		return false
	if not _is_end_solo_podium_enabled():
		return false
	if not RankActivityManager.begin_end_solo_podium():
		return false
	UIManager.show_ui(UiName.RANK_ACTIVITY_SOLO_PODIUM, {"rank": int(pending.get("rank", 4))})
	await UIManager.await_hidden(UiName.RANK_ACTIVITY_SOLO_PODIUM)
	RankActivityManager.complete_end_solo_podium(at_home)
	return true


func _on_rank_settle_ready(_result: Dictionary) -> void:
	await get_tree().process_frame
	if _is_exiting or not visible:
		return
	if RankActivityManager.get_pending_end_solo_podium().is_empty():
		return
	if not _is_end_solo_podium_enabled():
		RankActivityManager.notify_settlement_done()
		return

	_popup_queue.cancel("rank_settle")
	var entry := UIPopupEntry.new()
	entry.key = "rank_settle"
	entry.priority = _find_popup_priority("rank_reward_and_tryopen_popup")
	entry.callable = func() -> void:
		if _is_exiting or not visible:
			return

		if not await _run_end_solo_podium(true):
			return
		await _show_rank_open_popup()
	_popup_queue.enqueue(entry)
	if not _popup_queue.is_running():
		_popup_queue.flush()


func _should_show_vip_daily_gift() -> bool:
	return PurchaseManager.can_claim_vip_daily_gift()


func _show_vip_daily_gift() -> void:
	if _is_exiting or not visible:
		return
	await VipDailyGiftFlow.run()


func _should_show_rank_open_popup() -> bool:
	if not RankActivityManager.is_open_not_joined():
		return false
	if _rank_popup_pending:
		return false
	var existing: UIFrameWindow = UIManager.get_ui(UiName.RANK_ACTIVITY_OPEN_POPUP)
	if existing != null and existing.visible:
		return false
	return true


func _show_rank_open_popup() -> void:
	if not RankActivityManager.is_open_not_joined():
		return

	if _rank_popup_pending:
		return
	var existing: UIFrameWindow = UIManager.get_ui(UiName.RANK_ACTIVITY_OPEN_POPUP)
	if existing != null and existing.visible:
		return
	_rank_popup_pending = true

	await get_tree().create_timer(0.1).timeout
	for _i in range(60):
		if _is_exiting or visible:
			break
		await get_tree().process_frame
	if _is_exiting or not visible:
		_rank_popup_pending = false
		_rank_open_popup_deferred = (
			not _is_exiting and is_showing() and RankActivityManager.is_open_not_joined()
		)
		return
	_rank_open_popup_deferred = false
	var dlg: UIFrameWindow = UIManager.show_ui(UiName.RANK_ACTIVITY_OPEN_POPUP)
	if dlg == null:
		_rank_popup_pending = false
		return

	await UIManager.await_hidden(UiName.RANK_ACTIVITY_OPEN_POPUP)
	_rank_popup_pending = false

	RankActivityManager.confirm_participation()
	if _is_exiting or not visible:
		return
	var is_first: bool = RankActivityManager.get_period_count() == 1

	if not (is_first or dlg.was_started()):
		return

	if is_first and ProfileService.is_identity_default():
		var profile: UIFrameWindow = UIManager.show_ui(
			UiName.PROFILE, {"from_rank_open_guide": true}
		)
		if profile != null:
			await UIManager.await_hidden(UiName.PROFILE)
		if _avatar_cell != null:
			_avatar_cell.set_self()
		if _is_exiting or not visible:
			return

	_enter_main_level_covering()


func request_rank_open_popup() -> void:
	_show_rank_open_popup()


func _should_show_rank_frame_unlock_popup() -> bool:
	if not ABTestManager.rank_1st_frame.is_enabled():
		return false

	return ProfileService.get_pending_frame_tier_form() > 0


func _show_rank_frame_unlock_popup() -> void:
	if not _should_show_rank_frame_unlock_popup():
		return
	var page: UIFrameWindow = UIManager.show_ui(UiName.RANK_FRAME_UNLOCK)
	if page == null or not page.has_method("show_frame_tier_only"):
		push_error("HomePage: RANK_FRAME_UNLOCK page missing show_frame_tier_only")
		return
	page.show_frame_tier_only(
		ProfileService.get_pending_frame_tier_form(),
		ProfileService.get_first_place_wins(),
		"RANK_TIER_CELE"
	)
	await UIManager.await_hidden(UiName.RANK_FRAME_UNLOCK)


func _on_rank_period_opened(_count: int) -> void:
	await get_tree().process_frame
	if _is_exiting or not is_showing():
		return
	_rank_open_popup_deferred = true
	_enqueue_deferred_rank_open_popup()


func _enqueue_deferred_rank_open_popup() -> void:
	if not _rank_open_popup_deferred or _is_exiting or not is_showing():
		return
	if _rank_session_waiting_for_setting:
		return
	if not RankActivityManager.is_open_not_joined():
		_rank_open_popup_deferred = false
		return
	if not visible:
		return
	if not _should_show_rank_open_popup():
		return

	var pending_keys: Array[String] = _popup_queue.pending_keys()
	if pending_keys.has("rank_open_popup"):
		_rank_open_popup_deferred = false
		return
	var entry := UIPopupEntry.new()
	entry.key = "rank_open_popup"
	entry.priority = _find_popup_priority("rank_open_popup")
	entry.callable = _show_rank_open_popup
	_popup_queue.enqueue(entry)
	_rank_open_popup_deferred = false
	if not _popup_queue.is_running():
		_popup_queue.flush()


func on_hide() -> void:
	_companion.cat.set_sound_enabled(false)
	_companion_entry_generation += 1
	_companion_entry_pending = false
	_companion.end_entry()
	_popup_queue.clear()
	_rank_open_popup_deferred = false
	_rank_session_waiting_for_setting = false

	for cell: Variant in [_streak_cell, _streak_mini_cell, _streak_top_cell]:
		if cell != null and cell.has_method("reset_icon"):
			cell.reset_icon()


func _set_streak_cell_visible(cell: Variant, vis: bool) -> void:
	if cell == null:
		return
	var ctrl := cell as Control
	if not vis and ctrl.visible and cell.has_method("reset_icon"):
		cell.reset_icon()
	var became_visible: bool = vis and not ctrl.visible
	ctrl.visible = vis
	if became_visible and cell.has_method("on_show"):
		cell.on_show({})


func _update_countdown() -> void:
	_companion.tick()
	_apply_halloween_logo()
	DailyEntryState.ensure_max_daily_advanced()
	_refresh_daily_btn_state()
	_countdown_label.text = DailyEntryState.countdown_text()

	var previous_time_layout: int = _dc_in_btn_state
	_apply_dc_number_time_layout()
	if previous_time_layout != _dc_in_btn_state:
		_queue_bottom_layout()
	_sync_players_row_canvas_rect()
	_daily_players_row.refresh(DailyEntryState.compute_state())


func _roll_dc_players_avatars() -> void:
	_daily_players_row.roll_avatars()
	if _dc_cell != null and _dc_cell.has_method("roll_players_avatars"):
		_dc_cell.roll_players_avatars()


# ================= 输入与入口按钮 =================
## 返回键（Android 物理返回）→ 弹退出确认
func _on_back_request() -> void:
	# 已经在转场中就不再处理
	if _is_exiting:
		return
	_request_quit_confirm()


## 弹「确认退出」弹窗；设置页开着时不接管返回键
func _request_quit_confirm() -> void:
	# 设置页可见时，返回键该由它自己处理
	var setting: Node = UIManager.get_ui(UiName.SETTING)
	if setting != null and setting is CanvasItem and (setting as CanvasItem).visible:
		return
	# 确认后直接退出游戏
	UIManager.show_ui(UiName.CONFIRM, {"on_confirm": func(): get_tree().quit()})


func _on_settings_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.SETTINGS, self)
	VibrateManager.play_at(VibrateManager.Pos.SETTINGS_BTN)
	UIManager.show_ui(UiName.SETTING)


func _on_avatar_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.SELF_INFO, self)
	VibrateManager.play_at(VibrateManager.Pos.AVATAR_BTN)

	var page: UIFrameWindow = UIManager.show_ui(UiName.PROFILE)
	if page == null:
		return
	await UIManager.await_hidden(UiName.PROFILE)
	if _avatar_cell != null:
		_avatar_cell.set_self()

	_refresh_avatar_red_dot()


func _on_profile_display_changed() -> void:
	if _avatar_cell != null:
		_avatar_cell.set_self()
	_refresh_avatar_red_dot()


func _refresh_avatar_red_dot() -> void:
	if _avatar_cell != null:
		var has_skin_tab: bool = (
			ABTestManager.dc_costume.has_costume()
			or ProfileService.is_costume_held(CostumeCatalog.HALLOWEEN_COSTUME_ID)
		)
		_avatar_cell.set_red_dot(
			(
				ProfileService.has_frame_red_dot()
				or ProfileService.has_avatar_red_dot()
				or (has_skin_tab and ProfileService.has_costume_red_dot())
			)
		)


func get_profile_entry_center() -> Vector2:
	return _profile_entry.global_position + _profile_entry.size * 0.5


func play_profile_shake() -> void:
	if _avatar_cell != null:
		_avatar_cell.play_shake()


func get_rank_entry_center() -> Vector2:
	for cell in [_rank_cell, _rank_mini_cell, _rank_left_cell]:
		var c: Control = cell as Control
		if c != null and c.is_inside_tree() and c.is_visible_in_tree():
			return c.get_global_rect().get_center()
	push_warning("HomePage.get_rank_entry_center: 三种 rank 入口卡均不可见,返 Vector2.ZERO")
	return Vector2.ZERO


func get_rank_entry_cell() -> Control:
	for cell in [_rank_cell, _rank_mini_cell, _rank_left_cell]:
		var candidate: Control = cell as Control
		if candidate != null and candidate.is_inside_tree() and candidate.is_visible_in_tree():
			return candidate
	return null


func is_rank_entry_left_side() -> bool:
	var left_cell: Control = _rank_left_cell as Control
	return left_cell != null and left_cell.is_inside_tree() and left_cell.is_visible_in_tree()


func _on_start_btn_pressed() -> void:
	VibrateManager.play_at(VibrateManager.Pos.START_BTN)
	UIManager.hide_all_except([UiName.HOME, UiName.GAME])
	enter_main_level()


func enter_main_level() -> void:
	Tracker.track_btn_click(_start_btn_name(), self)
	_exit_to_page("game", {"level_index": GameState.get_current_level()})


func _enter_main_level_covering() -> void:
	Tracker.track_btn_click(_start_btn_name(), self)
	UIManager.show_ui(UiName.GAME, {"level_index": GameState.get_current_level()})
	if is_showing():
		UIManager.hide_ui(UiName.HOME)


func _on_daily_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.DAILY_PLAY, self)

	DailyEntryState.handle_click(
		self,
		_exit_to_page.bind("daily_game", {}),
		func() -> void:
			DcReplayFlow.open_confirm(
				self, _exit_to_page.bind("daily_game", DcReplayFlow.enter_params())
			)
	)


func _exit_to_page(page_name: String, params: Dictionary) -> void:
	if _is_exiting:
		return
	_is_exiting = true
	_companion.set_interaction_enabled(false)
	_pending_page = page_name
	_pending_params = params
	var anim: Animation = _anim.get_animation(&"MainInterface")
	var entry_delay: float = maxf(
		0.0, anim.get_marker_time(&"Entry") - anim.get_marker_time(&"disappear")
	)
	var anim_finish_delay: float = maxf(0.0, anim.length - anim.get_marker_time(&"disappear"))
	_anim.play_section_with_markers(&"MainInterface", &"disappear", &"")
	get_tree().create_timer(entry_delay).timeout.connect(
		func() -> void:
			_on_entry_reached()
			get_tree().create_timer(maxf(0.0, anim_finish_delay - entry_delay)).timeout.connect(
				func() -> void: _on_anim_finished(&"MainInterface")
			)
	)


func _on_entry_reached() -> void:
	if _new_page_node != null or not is_inside_tree():
		return

	_new_page_node = UIManager.show_ui(_pending_page, _pending_params)
	if _new_page_node == null:
		return

	if _new_page_node is CanvasItem:
		z_index = (_new_page_node as CanvasItem).z_index + 1

		_daily_players_row.sync_now()


func _on_anim_finished(_anim_name: StringName) -> void:
	if _new_page_node == null:
		return

	var _dest_win: UIFrameWindow = _new_page_node as UIFrameWindow
	if _dest_win != null and not _dest_win.is_showing():
		return
	UIManager.hide_ui(UiName.HOME)


const _DAILY_PAW_ENABLED: bool = false

const _DC_IN_BTN_TIME_TOP: float = 106.0
const _DC_IN_BTN_TIME_BOTTOM: float = 146.0
const _DC_IN_BTN_TITLE_CENTER_Y: float = 61.0
const _DC_IN_BTN_ICON_SIZE: Vector2 = Vector2(35, 40)
const _DC_IN_BTN_TIME_FONT_SIZE: int = 44
const _DC_IN_BTN_TIME_SEP: int = 10
const _DC_IN_BTN_PLAYERS_TOP: float = 170.0
const _DC_IN_BTN_PLAYERS_BOTTOM: float = 250.0

const _DC_IN_BTN_TIME_FONT: FontVariation = preload("res://assets/fonts/Roboto-medium.tres")

var _dc_in_btn_state: int = -1

var _dc_in_btn_baseline: Dictionary = {}


func _apply_dc_number_time_layout() -> void:
	var want: int = 1 if ABTestManager.dc_number.is_count_visible() else 0
	if want == _dc_in_btn_state:
		return
	if _dc_in_btn_baseline.is_empty():
		_dc_in_btn_baseline = {
			"unlock_top": _daily_unlock_box.offset_top,
			"unlock_bottom": _daily_unlock_box.offset_bottom,
			"cd_rect":
			Rect2(
				_countdown_tag.offset_left,
				_countdown_tag.offset_top,
				_countdown_tag.offset_right - _countdown_tag.offset_left,
				_countdown_tag.offset_bottom - _countdown_tag.offset_top
			),
			"done_rect":
			Rect2(
				_daily_done_tag.offset_left,
				_daily_done_tag.offset_top,
				_daily_done_tag.offset_right - _daily_done_tag.offset_left,
				_daily_done_tag.offset_bottom - _daily_done_tag.offset_top
			),
			"cd_panel": _countdown_tag.get_theme_stylebox(&"panel"),
			"done_panel": _daily_done_tag.get_theme_stylebox(&"panel"),
			"cd_sep": _countdown_hbox.get_theme_constant(&"separation"),
			"done_sep": _daily_done_hbox.get_theme_constant(&"separation"),
			"cd_icon": _countdown_icon.custom_minimum_size,
			"done_icon": _daily_done_icon.custom_minimum_size,
			"cd_font": _countdown_label.get_theme_font(&"font"),
			"done_font": _daily_done_time.get_theme_font(&"font"),
			"cd_fs": _countdown_label.get_theme_font_size(&"font_size"),
			"done_fs": _daily_done_time.get_theme_font_size(&"font_size"),
			"players_top": _daily_players_row.offset_top,
			"players_bottom": _daily_players_row.offset_bottom,
			"players_left": _daily_players_row.offset_left,
			"players_right": _daily_players_row.offset_right,
			"players_z": _daily_players_row.z_index,
			"players_mod": _daily_players_row.modulate,
			"players_anchors":
			[
				_daily_players_row.anchor_left,
				_daily_players_row.anchor_top,
				_daily_players_row.anchor_right,
				_daily_players_row.anchor_bottom,
			],
			"cd_z": _countdown_tag.z_index,
			"done_z": _daily_done_tag.z_index,
		}
	_dc_in_btn_state = want
	if want == 1:
		var base_center: float = (
			(
				float(_dc_in_btn_baseline["unlock_top"])
				+ _daily_btn.size.y
				+ float(_dc_in_btn_baseline["unlock_bottom"])
			)
			* 0.5
		)
		var shift: float = _DC_IN_BTN_TITLE_CENTER_Y - base_center
		_daily_unlock_box.offset_top = float(_dc_in_btn_baseline["unlock_top"]) + shift
		_daily_unlock_box.offset_bottom = float(_dc_in_btn_baseline["unlock_bottom"]) + shift

		for tag: Panel in [_countdown_tag, _daily_done_tag]:
			tag.offset_left = 0.0
			tag.offset_right = _daily_btn.size.x
			tag.offset_top = _DC_IN_BTN_TIME_TOP
			tag.offset_bottom = _DC_IN_BTN_TIME_BOTTOM

			tag.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())

			tag.z_index = 1
		for hb: HBoxContainer in [_countdown_hbox, _daily_done_hbox]:
			hb.add_theme_constant_override(&"separation", _DC_IN_BTN_TIME_SEP)
		for ic: TextureRect in [_countdown_icon, _daily_done_icon]:
			ic.custom_minimum_size = _DC_IN_BTN_ICON_SIZE
		for lb: Label in [_countdown_label, _daily_done_time]:
			lb.add_theme_font_override(&"font", _DC_IN_BTN_TIME_FONT)
			lb.add_theme_font_size_override(&"font_size", _DC_IN_BTN_TIME_FONT_SIZE)

		_daily_players_row.top_level = true
		_daily_players_row.anchor_left = 0.0
		_daily_players_row.anchor_top = 0.0
		_daily_players_row.anchor_right = 0.0
		_daily_players_row.anchor_bottom = 0.0
		_sync_players_row_canvas_rect()

		_daily_players_row.follow_host(_daily_btn)
		return
	_daily_unlock_box.offset_top = float(_dc_in_btn_baseline["unlock_top"])
	_daily_unlock_box.offset_bottom = float(_dc_in_btn_baseline["unlock_bottom"])
	var cd: Rect2 = _dc_in_btn_baseline["cd_rect"]
	var dn: Rect2 = _dc_in_btn_baseline["done_rect"]
	_countdown_tag.offset_left = cd.position.x
	_countdown_tag.offset_top = cd.position.y
	_countdown_tag.offset_right = cd.end.x
	_countdown_tag.offset_bottom = cd.end.y
	_daily_done_tag.offset_left = dn.position.x
	_daily_done_tag.offset_top = dn.position.y
	_daily_done_tag.offset_right = dn.end.x
	_daily_done_tag.offset_bottom = dn.end.y
	_countdown_tag.add_theme_stylebox_override(&"panel", _dc_in_btn_baseline["cd_panel"])
	_daily_done_tag.add_theme_stylebox_override(&"panel", _dc_in_btn_baseline["done_panel"])
	_countdown_hbox.add_theme_constant_override(&"separation", int(_dc_in_btn_baseline["cd_sep"]))
	_daily_done_hbox.add_theme_constant_override(
		&"separation", int(_dc_in_btn_baseline["done_sep"])
	)
	_countdown_icon.custom_minimum_size = _dc_in_btn_baseline["cd_icon"]
	_daily_done_icon.custom_minimum_size = _dc_in_btn_baseline["done_icon"]
	_countdown_label.add_theme_font_override(&"font", _dc_in_btn_baseline["cd_font"])
	_daily_done_time.add_theme_font_override(&"font", _dc_in_btn_baseline["done_font"])
	_countdown_label.add_theme_font_size_override(&"font_size", int(_dc_in_btn_baseline["cd_fs"]))
	_daily_done_time.add_theme_font_size_override(&"font_size", int(_dc_in_btn_baseline["done_fs"]))
	_daily_players_row.top_level = false
	var anc: Array = _dc_in_btn_baseline["players_anchors"]
	_daily_players_row.anchor_left = float(anc[0])
	_daily_players_row.anchor_top = float(anc[1])
	_daily_players_row.anchor_right = float(anc[2])
	_daily_players_row.anchor_bottom = float(anc[3])
	_daily_players_row.offset_left = float(_dc_in_btn_baseline["players_left"])
	_daily_players_row.offset_right = float(_dc_in_btn_baseline["players_right"])
	_daily_players_row.offset_top = float(_dc_in_btn_baseline["players_top"])
	_daily_players_row.offset_bottom = float(_dc_in_btn_baseline["players_bottom"])
	_countdown_tag.z_index = int(_dc_in_btn_baseline["cd_z"])
	_daily_done_tag.z_index = int(_dc_in_btn_baseline["done_z"])
	_daily_players_row.z_index = int(_dc_in_btn_baseline["players_z"])
	_daily_players_row.follow_host(null)
	_daily_players_row.modulate = _dc_in_btn_baseline["players_mod"]


func _sync_players_row_canvas_rect() -> void:
	if not _daily_players_row.top_level:
		return
	var host: CanvasItem = _daily_btn.get_parent() as CanvasItem
	if host == null:
		return
	var btn_canvas: Vector2 = host.get_global_transform() * _daily_btn.position
	_daily_players_row.offset_left = btn_canvas.x
	_daily_players_row.offset_right = btn_canvas.x + _daily_btn.size.x
	_daily_players_row.offset_top = btn_canvas.y + _DC_IN_BTN_PLAYERS_TOP
	_daily_players_row.offset_bottom = btn_canvas.y + _DC_IN_BTN_PLAYERS_BOTTOM


func _refresh_daily_btn_state() -> void:
	var s: int = DailyEntryState.compute_state()
	match s:
		DailyEntryState.State.LOCKED:
			var sf := StyleBoxFlat.new()
			sf.bg_color = Color(0.667, 0.667, 0.667, 1)
			sf.set_corner_radius_all(200)
			_daily_bg.add_theme_stylebox_override("normal", sf)
			_daily_bg.add_theme_stylebox_override("pressed", sf)
			_daily_bg.add_theme_stylebox_override("hover", sf)
			_daily_shadow.visible = false
			_daily_lock_icon.visible = true
			_daily_unlock_box.visible = false
			_daily_done_tag.visible = false
			_daily_top_tag.visible = false
			_countdown_tag.visible = false
		DailyEntryState.State.DONE, DailyEntryState.State.REPLAY:
			var sf_n := StyleBoxFlat.new()
			sf_n.bg_color = Color(0.576, 0.651, 0.945, 1)
			sf_n.set_corner_radius_all(200)
			sf_n.shadow_color = Color(0.576, 0.651, 0.945, 0.15)
			sf_n.shadow_size = 10
			sf_n.shadow_offset = Vector2(0, 4)
			var sf_p := StyleBoxFlat.new()
			sf_p.bg_color = Color(0.471, 0.537, 0.78, 1)
			sf_p.set_corner_radius_all(200)
			_daily_bg.add_theme_stylebox_override("normal", sf_n)
			_daily_bg.add_theme_stylebox_override("pressed", sf_p)
			_daily_bg.add_theme_stylebox_override("hover", sf_n)
			_daily_shadow.visible = true
			_daily_lock_icon.visible = false
			_daily_unlock_box.visible = true
			_daily_done_tag.visible = true
			_daily_top_tag.visible = true
			_countdown_tag.visible = false
			_daily_done_time.text = DailyEntryState.done_time_text()
			_daily_top_label.text = DailyEntryState.done_rank_text()
			_daily_paw.visible = _DAILY_PAW_ENABLED
			if _daily_paw.visible:
				_daily_paw.texture = _daily_paw_tex_lit
			call_deferred("_update_top_tag_layout")
		_:
			_daily_bg.add_theme_stylebox_override("normal", _daily_sf_normal)
			_daily_bg.add_theme_stylebox_override("pressed", _daily_sf_pressed)
			_daily_bg.add_theme_stylebox_override("hover", _daily_sf_normal)
			_daily_shadow.visible = true
			_daily_lock_icon.visible = false
			_daily_unlock_box.visible = true
			_daily_done_tag.visible = false
			_daily_top_tag.visible = false
			_countdown_tag.visible = true
			_daily_paw.visible = _DAILY_PAW_ENABLED
			if _daily_paw.visible:
				_daily_paw.texture = _daily_paw_tex_dim
	_refresh_daily_cat_head()


func _refresh_daily_cat_head() -> void:
	if _daily_cat_icon == null:
		return
	var state: int = DailyEntryState.compute_state()
	var has_cat: bool = (
		ABTestManager.dc_costume.has_costume() and state != DailyEntryState.State.LOCKED
	)

	_apply_daily_btn_cat_layout(has_cat)
	if not has_cat:
		_daily_cat_icon.visible = false
		_daily_cat_shadow.visible = false
		if _daily_cat_spine != null:
			_daily_cat_spine.visible = false
		return

	var costume_id: int = ProfileService.get_today_costume()
	var dimmed: bool = not ProfileService.is_costume_held(costume_id)
	var tex: Texture2D = CostumeIcon.texture_for(costume_id)

	_daily_cat_icon.visible = tex != null
	_daily_cat_icon.texture = tex
	_daily_cat_icon.modulate.a = DcEntryCatHead.DIM_ALPHA if dimmed else 1.0

	_daily_cat_shadow.visible = tex != null
	_daily_cat_shadow.texture = tex
	_daily_cat_shadow.self_modulate.a = DcEntryCatHead.DIM_ALPHA if dimmed else 1.0
	if tex != null:
		if _daily_cat_spine != null:
			_daily_cat_spine.visible = false
		return
	_ensure_daily_cat_spine()
	_daily_cat_spine.visible = true
	CostumeSkin.apply(_daily_cat_spine, costume_id)
	_daily_cat_spine.modulate.a = DcEntryCatHead.DIM_ALPHA if dimmed else 1.0


func _ensure_daily_cat_spine() -> void:
	if _daily_cat_spine != null:
		return
	_daily_cat_spine = SpineSprite.new()
	_daily_cat_spine.skeleton_data_res = CostumeSkin.SKELETON_RES
	_daily_cat_anchor.add_child(_daily_cat_spine)


const _DAILY_BTN_TEXT_KEY: String = "HOME_DAILY_CHALLENGE"


func _apply_daily_btn_cat_layout(has_cat: bool) -> void:
	if _daily_cat_wrap != null:
		_daily_cat_wrap.visible = has_cat
	if _daily_btn != null:
		_daily_btn.text = "" if has_cat else _DAILY_BTN_TEXT_KEY


## 重新摆放右上角名次标签：宽度随文字自适应并保持右边对齐
func _update_top_tag_layout() -> void:
	# 设计稿里标签的默认位置与尺寸（像素）
	const DEFAULT_TAG_X: float = 619.0
	const DEFAULT_TAG_Y: float = -31.0
	const DEFAULT_TAG_W: float = 202.0
	const DEFAULT_TAG_H: float = 70.0
	const DEFAULT_LBL_W: float = 151.0
	const LBL_OFFSET_L: float = 30.0
	const LBL_OFFSET_T: float = 0.0
	# 按当前字号量出文字的自然宽度
	var font: Font = _daily_top_label.get_theme_font("font")
	var fs: int = _daily_top_label.get_theme_font_size("font_size")
	var lbl_w_natural: float = ceilf(
		font.get_string_size(_daily_top_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	)

	# 宽度不小于设计值
	var lbl_w: float = max(lbl_w_natural, DEFAULT_LBL_W)
	# 标签宽度 = 2 × 文字宽 - 100，右边固定
	var tag_w: float = 2.0 * lbl_w - 100.0

	# 由右边固定点反推新的 X
	var tag_x: float = (DEFAULT_TAG_X + DEFAULT_TAG_W) - tag_w
	_daily_top_tag.position = Vector2(tag_x, DEFAULT_TAG_Y)
	_daily_top_tag.size = Vector2(tag_w, DEFAULT_TAG_H)
	_daily_top_label.position = Vector2(LBL_OFFSET_L, LBL_OFFSET_T)
	_daily_top_label.size = Vector2(lbl_w, DEFAULT_TAG_H)


func _apply_entry_shape_pos() -> void:
	var shape_root: Control = _shape_root()

	var solo: bool = not RankActivityManager.has_home_entry()

	_place(_streak_slot, ["StreakSoloPos", "StreakPos"] if solo else ["StreakPos"], shape_root)
	_place(_dc_slot, ["DcSoloPos", "DcPos"] if solo else ["DcPos"], shape_root)
	_place(_rank_slot, ["RankPos"], shape_root)

	_place(_side_bar_left, ["SideBarLeftPos"], shape_root)
	_place(_side_bar_right, ["SideBarRightPos"], shape_root)

	_place(_loge, ["LogoPos"], shape_root)


func _place(target: Control, names: Array, shape_root: Control) -> void:
	if target == null:
		return
	_snapshot_pos_origin(target)
	if shape_root != null:
		for nm: String in names:
			var mark: Control = shape_root.get_node_or_null(nm) as Control
			if mark != null:
				_write_offsets(
					target,
					[
						mark.anchor_left,
						mark.anchor_top,
						mark.anchor_right,
						mark.anchor_bottom,
						mark.offset_left,
						mark.offset_top,
						mark.offset_right,
						mark.offset_bottom
					]
				)
				return
	_write_offsets(target, _pos_origin[target])


func _snapshot_pos_origin(target: Control) -> void:
	if _pos_origin.has(target):
		return
	_pos_origin[target] = [
		target.anchor_left,
		target.anchor_top,
		target.anchor_right,
		target.anchor_bottom,
		target.offset_left,
		target.offset_top,
		target.offset_right,
		target.offset_bottom
	]


func _write_offsets(target: Control, v: Array) -> void:
	target.anchor_left = v[0]
	target.anchor_top = v[1]
	target.anchor_right = v[2]
	target.anchor_bottom = v[3]
	target.offset_left = v[4]
	target.offset_top = v[5]
	target.offset_right = v[6]
	target.offset_bottom = v[7]


func _apply_entry_shape_cells() -> void:
	var shape: int = ABTestManager.home_entry_shape.get_shape()
	var is_control: bool = shape == HomeEntryShapeConfig.VALUE_CURRENT_WIDGET
	var rank_on: bool = RankActivityManager.has_home_entry()
	var is_side: bool = shape == HomeEntryShapeConfig.VALUE_RANK_SIDE

	var want_dc_big: bool = not ABTestManager.home_entry_shape.has_daily_btn()
	_daily_btn.visible = not want_dc_big
	if _dc_cell != null:
		(_dc_cell as Control).visible = want_dc_big

	var streak_top: bool = (
		shape in [HomeEntryShapeConfig.VALUE_ICON_TOP, HomeEntryShapeConfig.VALUE_RANK_SIDE]
	)

	if not is_control:
		if _streak_cell != null:
			_set_streak_cell_visible(_streak_cell, not streak_top)
		if _streak_mini_cell != null:
			_set_streak_cell_visible(_streak_mini_cell, false)
		if _rank_mini_cell != null:
			(_rank_mini_cell as Control).visible = false

	if streak_top:
		if _streak_top_cell == null:
			_streak_top_cell = create_child(_STREAK_TOP_ENTRY_CELL, {})
			_mount_into_slot(_streak_top_cell, _streak_icon_slot)
		(_streak_top_cell as Control).visible = true
		_streak_top_cell.on_show({})
	elif _streak_top_cell != null:
		_set_streak_cell_visible(_streak_top_cell, false)

	if rank_on and not is_side and not is_control:
		if _rank_cell == null:
			_rank_cell = create_child(_RANK_ENTRY_CELL, {})
			_mount_into_slot(_rank_cell, _rank_slot)
		(_rank_cell as Control).visible = true
		_rank_cell.on_show({})
	elif _rank_cell != null:
		(_rank_cell as Control).visible = false

	if rank_on and is_side:
		if _rank_left_cell == null:
			_rank_left_cell = create_child(_RANK_LEFT_ENTRY_CELL, {})
			_mount_into_container(_rank_left_cell, _side_bar_left)
		(_rank_left_cell as Control).visible = true
		_rank_left_cell.on_show({})
	elif _rank_left_cell != null:
		(_rank_left_cell as Control).visible = false

	if _SIDE_BAR_DC_ENABLED and is_side:
		if _dc_left_cell == null:
			_dc_left_cell = create_child(_DC_LEFT_ENTRY_CELL, {})
			_mount_into_container(_dc_left_cell, _side_bar_right)
		(_dc_left_cell as Control).visible = true
		_dc_left_cell.on_show({})
	elif _dc_left_cell != null:
		(_dc_left_cell as Control).visible = false


const _DAILY_BTN_GAP: float = 60.0


func _align_daily_btn_under_start() -> void:
	var bg: Control = _start_btn.get_node_or_null("Root/Bg") as Control
	var reference_rect: Rect2 = bg.get_global_rect() if bg != null else _start_btn.get_global_rect()
	var daily_rect: Rect2 = _daily_btn.get_global_rect()

	var bottom_extent: float = maxf(
		_daily_btn.size.y,
		(
			maxf(_countdown_tag.get_global_rect().end.y, _daily_done_tag.get_global_rect().end.y)
			- daily_rect.position.y
		)
	)
	if ABTestManager.dc_number.is_count_visible():
		bottom_extent = maxf(bottom_extent, _DC_IN_BTN_PLAYERS_BOTTOM)
	_companion.fit_start_button(reference_rect.end.y + _DAILY_BTN_GAP + bottom_extent)
	reference_rect = bg.get_global_rect() if bg != null else _start_btn.get_global_rect()
	var horizontal_shift: float = reference_rect.get_center().x - daily_rect.get_center().x
	var vertical_shift: float = reference_rect.end.y + _DAILY_BTN_GAP - daily_rect.position.y
	_daily_btn.offset_left += horizontal_shift
	_daily_btn.offset_right += horizontal_shift
	_daily_btn.offset_top += vertical_shift
	_daily_btn.offset_bottom += vertical_shift

	_sync_players_row_canvas_rect()


func _queue_bottom_layout() -> void:
	if not is_showing() or _is_exiting or _bottom_layout_queued:
		return
	_bottom_layout_queued = true
	_refresh_bottom_layout.call_deferred()


func _refresh_bottom_layout() -> void:
	_bottom_layout_queued = false
	if not is_showing() or _is_exiting:
		return
	_align_daily_btn_under_start()
	_companion.refresh_layout()


func _shape_root() -> Control:
	return _pos_table.get_node_or_null("Shape%d" % ABTestManager.home_entry_shape.get_shape())


func _apply_home_layout() -> void:
	_streak_layout.visible = true

	if _dc_cell == null:
		_dc_cell = create_child(_DC_ENTRY_CELL, {})
		_mount_into_slot(_dc_cell, _dc_slot)
	if _streak_cell == null:
		_streak_cell = create_child(_STREAK_ENTRY_CELL, {})
		_mount_into_slot(_streak_cell, _streak_slot)
	_apply_streak_dead_layout()
	_apply_rank_entry_layout()


func _apply_streak_dead_layout() -> void:
	if _streak_cell != null:
		_streak_cell.visible = true

		_streak_cell.on_show({})
	if _dc_cell != null:
		(_dc_cell as Control).position.x = 0.0


func _apply_rank_entry_layout() -> void:
	if not _streak_layout.visible:
		return
	var rank_on: bool = RankActivityManager.has_home_entry()

	if _streak_cell != null:
		_set_streak_cell_visible(_streak_cell, not rank_on)
	if not rank_on:
		if _streak_mini_cell != null:
			_set_streak_cell_visible(_streak_mini_cell, false)
		if _rank_mini_cell != null:
			(_rank_mini_cell as Control).visible = false
		return

	if _streak_mini_cell == null:
		_streak_mini_cell = create_child(_STREAK_MINI_ENTRY_CELL, {})
		_mount_into_slot(_streak_mini_cell, _streak_small_slot)
	if _rank_mini_cell == null:
		_rank_mini_cell = create_child(_RANK_MINI_ENTRY_CELL, {})
		_mount_into_slot(_rank_mini_cell, _rank_slot)
	(_streak_mini_cell as Control).visible = true
	(_rank_mini_cell as Control).visible = true

	if _dc_cell != null:
		(_dc_cell as Control).position.x = 0.0

	_streak_mini_cell.on_show({})
	_rank_mini_cell.on_show({})


func _relayout_rank_entries(
	with_streak_dead: bool = false, with_shape_pos: bool = false, only_when_showing: bool = false
) -> void:
	if _rank_layout_locked:
		return
	if only_when_showing and not is_showing():
		return
	if with_streak_dead:
		_apply_streak_dead_layout()
	_apply_rank_entry_layout()
	if with_shape_pos:
		_companion.restore_logo_layout()
		_apply_entry_shape_pos()
		_companion.refresh_layout()

	_apply_entry_shape_cells()


func _on_rank_state_changed(_state: int) -> void:
	_relayout_rank_entries(false, true, true)


func set_rank_layout_locked(locked: bool) -> void:
	if _rank_layout_locked == locked:
		return
	_rank_layout_locked = locked
	if not locked:
		_on_rank_state_changed(RankActivityManager.get_state())


const _PEEKABOO_POS_TABLE := [
	Vector2(666.0, 230.0),
	Vector2(320.0, 71.0),
	Vector2(874.0, -777.0),
	Vector2(641.0, -356.0),
	Vector2(60.0, -587.0),
]


func refresh_peekaboo_cat() -> void:
	if _companion.has_companion():
		hide_peekaboo_cat()
		return

	_apply_peekaboo_soft_protect()
	var st: Dictionary = PeekabooManager.get_cat_state()
	if not bool(st.get("present", false)):
		hide_peekaboo_cat()
		return
	var prop_index: int = int(st.get("prop_index", 0))

	var idx: int = posmod(int(st.get("pos_index", 0)), _PEEKABOO_POS_TABLE.size())

	var t: Vector2 = _PEEKABOO_POS_TABLE[idx]
	var host: Control = _peekaboo_slot.get_parent() as Control
	var center_y: float = (host.size.y if host != null else 2400.0) * 0.5
	_peekaboo_slot.position = Vector2(t.x, center_y + t.y)
	if _peekaboo_cell == null:
		_peekaboo_cell = create_child(_PEEKABOO_CAT_CELL, {"prop_index": prop_index})
		_mount_into_slot(_peekaboo_cell, _peekaboo_slot)

		_peekaboo_cell.cat_pressed.connect(_on_peekaboo_cat_pressed)
	(_peekaboo_cell as Control).visible = true

	_peekaboo_cell.on_show({"prop_index": prop_index})


func hide_peekaboo_cat() -> void:
	if _peekaboo_cell == null:
		return
	_peekaboo_cell.disarm()
	(_peekaboo_cell as Control).visible = false


func _on_rank_time_ticked_for_peekaboo(_remaining_sec: int, _expired: bool) -> void:
	_apply_peekaboo_soft_protect()


func _apply_peekaboo_soft_protect() -> void:
	if not PeekabooRules.is_soft_protected(
		RankActivityManager.get_state(), RankActivityManager.get_remaining_sec()
	):
		return

	PeekabooManager.mark_soft_protected()
	hide_peekaboo_cat()


func get_peekaboo_cell() -> Control:
	if _peekaboo_cell == null or not is_instance_valid(_peekaboo_cell):
		return null
	return _peekaboo_cell as Control


func get_peekaboo_center() -> Vector2:
	var cell: Control = get_peekaboo_cell()
	if cell == null or not cell.is_inside_tree():
		return Vector2.ZERO
	return cell.get_global_rect().get_center()


func get_peekaboo_pos_centers() -> PackedVector2Array:
	var out := PackedVector2Array()
	var host: Control = _peekaboo_slot.get_parent() as Control
	if host == null or not host.is_inside_tree():
		return out

	var center_y: float = host.size.y * 0.5

	var half := Vector2(75.0, 75.0)
	var cell: Control = get_peekaboo_cell()
	if cell != null and cell.size != Vector2.ZERO:
		half = cell.size * 0.5
	var xf: Transform2D = host.get_global_transform()
	for t in _PEEKABOO_POS_TABLE:
		out.append(xf * (Vector2(t.x, center_y + t.y) + half))
	return out


func get_peekaboo_fly_layer() -> Control:
	return self


func enqueue_peekaboo_confirm_popup(body: Callable) -> void:
	_popup_queue.cancel("peekaboo_confirm")
	var entry := UIPopupEntry.new()
	entry.key = "peekaboo_confirm"
	entry.priority = _find_popup_priority("rank_reward_and_tryopen_popup")
	entry.callable = body
	_popup_queue.enqueue(entry)
	if not _popup_queue.is_running():
		_popup_queue.flush()


func is_peekaboo_confirm_pending() -> bool:
	return _popup_queue.is_running() or not _popup_queue.is_empty()


func _on_peekaboo_cat_pressed() -> void:
	if _peekaboo_presenting:
		return
	if _popup_queue.is_running():
		refresh_peekaboo_cat()
		return
	_peekaboo_presenting = true
	await PeekabooFlow.run(self)
	_peekaboo_presenting = false


## 把格子从原父节点摘下、挂进槽位并归零位置
func _mount_into_slot(cell: Node, slot: Control) -> void:
	var p: Node = cell.get_parent()
	if p != null:
		p.remove_child(cell)
	slot.add_child(cell)
	if cell is Control:
		(cell as Control).position = Vector2.ZERO


func _mount_into_container(cell: Node, box: Container) -> void:
	var c: Control = cell as Control
	if c != null and c.custom_minimum_size == Vector2.ZERO and c.size != Vector2.ZERO:
		c.custom_minimum_size = c.size
	var p: Node = cell.get_parent()
	if p != null:
		p.remove_child(cell)
	box.add_child(cell)


# ================= 埋点与诊断 =================
## 首页的埋点页面名
func get_scr_name() -> String:
	return Tracker.Scr.HOMEPAGE


## 诊断函数：点击被别人拦截时 push_error 报出拦截者（当前没有调用点）
func _diag_tap(pos: Vector2) -> void:
	# 取当前鼠标悬停的控件
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var hovered_path: String = str(hovered.get_path()) if hovered != null else "null"
	# 命中首页自己（可能只是正在转场），不算异常
	var in_home: bool = hovered != null and (hovered == self or is_ancestor_of(hovered))
	if in_home:
		if _is_exiting:
			push_error(
				"HomePage tap blocked by _is_exiting: hovered=%s pos=%s" % [hovered_path, str(pos)]
			)
		return

	# 落在白名单弹窗上：正常
	if _is_normal_home_overlay(hovered):
		return
	push_error(
		(
			"HomePage tap intercepted: hovered=%s pos=%s is_exiting=%s"
			% [hovered_path, str(pos), str(_is_exiting)]
		)
	)


func _is_normal_home_overlay(hovered: Control) -> bool:
	if hovered == null:
		return false

	var normal_ui: Array[StringName] = [
		UiName.SETTING,
		UiName.CONFIRM,
		UiName.DC_REPLAY_CONFIRM,
		UiName.FEEDBACK,
		UiName.AD_REWARD_RESTORED,
		UiName.AB_SWITCH_POPUP,
	]
	for ui_name in normal_ui:
		var win: UIFrameWindow = UIManager.get_ui(ui_name)
		if win != null and win.visible and (win == hovered or win.is_ancestor_of(hovered)):
			return true

	var node: Node = hovered
	while node != null:
		if node.name.to_lower().contains("cheat"):
			return true
		node = node.get_parent()
	return false
