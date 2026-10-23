## 设置页：协调音乐、音效、震动、语言、客服和账号保存入口，并适配实验布局。
class_name SettingPage
extends UIFrameWindow

var is_game_mode: bool = false # 由 on_show 的 params.is_game_mode 决定

static var debug_force_show_cmp: bool = false # 调试开关：强制显示隐私偏好入口（cheat 面板置位）

const _PREMIUM_CELL: PackedScene = preload(
	"res://scripts/module/purchase/ui/purchase_settings_cell.tscn"
)

const _PREMIUM_CELL_SIZE: Vector2 = Vector2(804, 200)

const _PREMIUM_SP_H: float = 30.0

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _toggle_grid: GridContainer = $Root/Content/PanelContainer/VBoxContainer/GridContainer # 四个开关的网格容器
@onready
var _sound_ctrl: Control = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl # 音效开关控制节点
@onready
var _sound_btn: BaseButton = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl/SoundBtn # 音效开关按钮
@onready
var _vibration_ctrl: Control = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl # 震动开关控制节点
@onready
var _vibration_btn: BaseButton = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl/VibrationBtn # 震动开关按钮

@onready
var _people_ctrl: Control = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl # 人声开关控制节点
@onready
var _people_btn: BaseButton = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl/PeopleBtn # 人声开关按钮

@onready
var _music_ctrl: Control = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl # 音乐开关控制节点
@onready
var _music_btn: BaseButton = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl/MusicBtn # 音乐开关按钮
@onready
var _music_toggle_on: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl/MusicBtn/ToggleOn # 音乐开态面板
@onready
var _music_toggle_off: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl/MusicBtn/ToggleOff # 音乐关态面板
@onready
var _sound_toggle_on: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl/SoundBtn/ToggleOn # 音效开态面板
@onready
var _sound_toggle_off: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl/SoundBtn/ToggleOff # 音效关态面板
@onready
var _vibration_toggle_on: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl/VibrationBtn/ToggleOn # 震动开态面板
@onready
var _vibration_toggle_off: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl/VibrationBtn/ToggleOff # 震动关态面板
@onready
var _icon_music: TextureRect = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl/MusicBtn/IconMusic # 音乐图标（开 / 关换贴图）
@onready
var _icon_sound: TextureRect = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl/SoundBtn/IconSound # 音效图标
@onready
var _icon_vibration: TextureRect = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl/VibrationBtn/IconVibration # 震动图标
@onready
var _people_toggle_on: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl/PeopleBtn/ToggleOn # 人声开态面板
@onready
var _people_toggle_off: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl/PeopleBtn/ToggleOff # 人声关态面板
@onready
var _icon_people: TextureRect = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl/PeopleBtn/IconPeople # 人声图标
@onready
var _terms_btn: UnderlineLink = $Root/Content/PanelContainer/VBoxContainer/TermContainer/TermsBtn # 用户协议链接（UnderlineLink，字号自适应）
@onready
var _privacy_btn: UnderlineLink = $Root/Content/PanelContainer/VBoxContainer/TermContainer/PrivacyBtn # 隐私政策链接
@onready
var _privacy_preference_btn: UnderlineLink = $Root/Content/PanelContainer/VBoxContainer/PrivacyContainer/PrivacyPreferenceBtn # 隐私偏好（CMP）链接
@onready
var _version_label: Label = $Root/Content/PanelContainer/VBoxContainer/HBoxContainer/VersionLabel # 版本号文案
@onready var _panel_container: PanelContainer = $Root/Content/PanelContainer # 居中的面板容器
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer # 弹窗动画（GenericPopup：Mark 之前为开场段，之后为关闭段）

@onready
var _vb_restart: Control = $Root/Content/PanelContainer/VBoxContainer/BtnContainer/OrangeRestartBtn # 「重新开始」整行容器
@onready
var _vb_restart_bg: Button = $Root/Content/PanelContainer/VBoxContainer/BtnContainer/OrangeRestartBtn/Bg # 重开按钮的 Bg（真正接收点击，用于按压缩放）
@onready
var _vb_feedback: Button = $Root/Content/PanelContainer/VBoxContainer/BtnContainer/FeedbackBtn # 反馈入口
@onready
var _vb_language: Button = $Root/Content/PanelContainer/VBoxContainer/BtnContainer/LanguageBtn # 语言入口
@onready var _vb_cmp_row: Control = $Root/Content/PanelContainer/VBoxContainer/PrivacyContainer # 隐私偏好整行
@onready var _vb_term_row: Control = $Root/Content/PanelContainer/VBoxContainer/TermContainer # 条款整行
@onready var _vb_version_row: Control = $Root/Content/PanelContainer/VBoxContainer/HBoxContainer # 版本号整行

# ---- 显隐受 A/B 与模式控制的整行、以及两个弹性占位 ----
@onready var _vb_sp3: Control = $Root/Content/PanelContainer/VBoxContainer/Control3 # 弹性占位行 3：游戏内模式压成 0 高
@onready var _vb_sp6: Control = $Root/Content/PanelContainer/VBoxContainer/Control6 # 弹性占位行 6：游戏内模式加高到 90 像素

@onready var _vb_premium_sp: Control = $Root/Content/PanelContainer/VBoxContainer/Control5
@onready
var _vb_premium_container: Control = $Root/Content/PanelContainer/VBoxContainer/PremiumContainer

@onready var _vb_pattern_sp: Control = $Root/Content/PanelContainer/VBoxContainer/Control4
@onready var _vb_pattern_toggle: Control = $Root/Content/PanelContainer/VBoxContainer/ToggleContainer
@onready
var _pattern_switch: Control = $Root/Content/PanelContainer/VBoxContainer/ToggleContainer/PatternModeSwitch
@onready
var _pattern_on_panel: Panel = $Root/Content/PanelContainer/VBoxContainer/ToggleContainer/PatternModeSwitch/Content/Switch/On
@onready
var _pattern_off_panel: Panel = $Root/Content/PanelContainer/VBoxContainer/ToggleContainer/PatternModeSwitch/Content/Switch/Off
@onready
var _pattern_switch_hot: Control = $Root/Content/PanelContainer/VBoxContainer/ToggleContainer/PatternModeSwitch/Content/Switch

@onready
var _save_progress_row: Control = $Root/Content/PanelContainer/VBoxContainer/ToggleContainer/SaveProgressRow

var _sp3_static_miny: float = 0.0 # _vb_sp3 在编辑器里的原始最小高度（像素）

var _premium_cell = null

# ---- 外部回调与一次性标记 ----
var _on_restart_cb: Callable = Callable() # 重开回调（游戏内由 game 页传入）

var _on_pattern_changed_cb: Callable = Callable()

var _on_close_cb: Callable = Callable() # 关闭回调
var _closing: bool = false # 关闭流程进行中

var _restart_consumed: bool = false # 重开按钮本次显示是否已消费


func _ready() -> void:
	_sp3_static_miny = _vb_sp3.custom_minimum_size.y
	_update_toggle(_music_toggle_on, _music_toggle_off, _icon_music, GameState.is_music_on())
	_update_toggle(_sound_toggle_on, _sound_toggle_off, _icon_sound, GameState.is_sound_on())
	_update_toggle(
		_vibration_toggle_on, _vibration_toggle_off, _icon_vibration, GameState.is_vibration_on()
	)
	_update_toggle(_people_toggle_on, _people_toggle_off, _icon_people, GameState.is_people_on())
	_refresh_dynamic_text()
	bind_press_release_scale($Root/Content/PanelContainer/VBoxContainer/TitleBar/CloseBtn)

	bind_press_release_scale(_vb_restart_bg)
	bind_press_release_scale(_vb_feedback)
	bind_press_release_scale(_vb_language)

	claim_button_sound(_sound_btn)

	_pattern_switch_hot.gui_input.connect(_on_pattern_switch_input)

	for b in [_terms_btn, _privacy_preference_btn, _privacy_btn]:
		b.resized.connect(_queue_unify_terms_row_font_size)
	_save_progress_row.row_pressed.connect(_on_save_progress_pressed)

	PurchaseManager.vip_status_changed.connect(_on_vip_status_changed)


func _mount_premium_cell() -> void:
	_premium_cell = create_child(_PREMIUM_CELL, {})
	if _premium_cell == null:
		return
	var p: Node = _premium_cell.get_parent()
	if p != null and p != _vb_premium_container:
		p.remove_child(_premium_cell)
		_vb_premium_container.add_child(_premium_cell)
	_premium_cell.position = Vector2.ZERO
	_premium_cell.custom_minimum_size = _PREMIUM_CELL_SIZE
	_premium_cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_premium_cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_premium_cell.card_pressed.connect(_on_premium_card_pressed)


func on_show(params: Dictionary = {}) -> void:
	ABTestManager.dye_at_open_setting()
	is_game_mode = params.get("is_game_mode", false)

	HelpshiftManager.request_unread()

	_music_ctrl.visible = (
		ABTestManager != null
		and ABTestManager.bgm_test != null
		and ABTestManager.bgm_test.has_music_switch()
	)

	_people_ctrl.visible = _is_people_toggle_visible()

	_apply_premium_entry()

	var show_language: bool = not is_game_mode

	var show_pattern: bool = is_game_mode

	var show_save: bool = (not is_game_mode) and AccountManager.is_login_feature_enabled()
	var show_toggle_container: bool = show_pattern or show_save

	_vb_pattern_sp.visible = show_toggle_container
	_set_miny(_vb_pattern_sp, 30.0 if show_toggle_container else 0.0)
	_vb_pattern_toggle.visible = show_toggle_container

	_pattern_switch.visible = show_pattern
	_save_progress_row.visible = show_save
	if show_pattern:
		_update_pattern_toggle_visual(GameState.is_pattern_mode_on())

	RedDotCenter.dismiss(DotName.MUSIC_ENTRY)

	_on_pattern_changed_cb = params.get("on_pattern_changed", Callable())

	_apply_toggle_grid_layout()
	_update_toggle(_music_toggle_on, _music_toggle_off, _icon_music, GameState.is_music_on())
	_update_toggle(_people_toggle_on, _people_toggle_off, _icon_people, GameState.is_people_on())
	_on_restart_cb = params.get("on_restart", Callable())
	_on_close_cb = params.get("on_close", Callable())

	var show_cmp: bool = (
		(not is_game_mode) and (UniKitManager.check_cmp_required() or debug_force_show_cmp)
	)
	apply_vbox_layout(
		{
			"show_restart": is_game_mode,
			"show_feedback": true,
			"show_language": show_language,
			"show_cmp": show_cmp,
			"show_terms": not is_game_mode,
			"show_version": not is_game_mode,
		}
	)

	_set_miny(_vb_sp3, 0.0 if is_game_mode else _sp3_static_miny)

	_set_miny(_vb_sp6, 90.0 if is_game_mode else 30.0)
	_closing = false
	_restart_consumed = false
	_anim.play_section_with_markers("GenericPopup", &"", &"Mark")

	_queue_unify_terms_row_font_size()

	_center_panel_vertically()


# ================= 显隐与布局 =================
## 面板垂直居中：按内容最小高度算上下 offset
func _center_panel_vertically() -> void:
	if not is_instance_valid(_panel_container):
		return

	# 用内容需要的最小高度，不受当前缩放动画影响
	var h: float = _panel_container.get_combined_minimum_size().y
	_panel_container.offset_top = -h / 2.0
	_panel_container.offset_bottom = h / 2.0


func _apply_premium_entry() -> void:
	var entry_on: bool = PurchaseManager.is_subscription_entry_enabled()
	var is_vip: bool = PurchaseManager.is_vip_active()
	var tier: int = PurchaseManager.get_vip_tier()
	var show_subscribed: bool = is_vip and tier >= 0

	var show_premium: bool = entry_on or is_vip
	_vb_premium_sp.visible = show_premium
	_set_miny(_vb_premium_sp, _PREMIUM_SP_H if show_premium else 0.0)
	_vb_premium_container.visible = show_premium

	_set_miny(_vb_premium_container, _PREMIUM_CELL_SIZE.y if show_premium else 0.0)
	if not show_premium:
		return

	if _premium_cell == null:
		_mount_premium_cell()
	if _premium_cell == null:
		return
	if show_subscribed:
		_premium_cell.show_subscribed(
			tier + 1, PurchaseDefine.is_base_edition(PurchaseManager.get_vip_plan_product_id())
		)
	else:
		_premium_cell.show_entry()


func _on_vip_status_changed(_active: bool) -> void:
	if not is_showing():
		return
	_apply_premium_entry()
	_center_panel_vertically()


func _on_premium_card_pressed() -> void:
	var user_state: String = (
		Tracker.SubscriptionUserState.SUBSCRIBED
		if PurchaseManager.is_vip_active()
		else Tracker.SubscriptionUserState.UNSUBSCRIBED
	)
	print(
		(
			"[Purchase (SettingPage)] 点击 Premium 卡 user_state=%s tier=%d → 开订阅页"
			% [user_state, PurchaseManager.get_vip_tier()]
		)
	)
	Tracker.track_sub_entry_click(Tracker.SubscriptionSource.SETTINGS_GET_PREMIUM, user_state)
	UIManager.show_ui(UiName.SUBSCRIPTION)


func on_hide() -> void:
	if _closing:
		return
	_closing = true
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished
	visible = false

	if _on_close_cb.is_valid():
		_on_close_cb.call()


## 语言切换时刷新版本号并重算链接字号
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()

		_queue_unify_terms_row_font_size()


## 同帧去重标记：为 true 表示已经排了一次重算
var _unify_queued: bool = false


## 请求一次条款字号统一（同帧去重）
func _queue_unify_terms_row_font_size() -> void:
	if _unify_queued:
		return
	_unify_queued = true
	call_deferred("_unify_terms_row_font_size")


## 取三个可见链接里「能放下的最小字号」作为统一上限，避免一行三个大小不一
func _unify_terms_row_font_size() -> void:
	_unify_queued = false
	# 整行隐藏时不用算
	if _vb_term_row == null or not _vb_term_row.visible:
		return
	# 三个链接，顺序与界面一致
	var btns: Array[UnderlineLink] = [_terms_btn, _privacy_preference_btn, _privacy_btn]
	# min_fs 为 -1 表示还没有有效值
	var min_fs: int = -1
	for b in btns:
		if b == null or not b.visible:
			continue
		# measure_fit_font_size 返回该链接按自身宽度算出的适配字号
		var fs: int = b.measure_fit_font_size()
		if min_fs < 0 or fs < min_fs:
			min_fs = fs
	# 一个都不合适就放弃
	if min_fs <= 0:
		return
	# set_font_size_cap 会立刻重排文本
	for b in btns:
		if b == null or not b.visible:
			continue
		b.set_font_size_cap(min_fs)


func apply_vbox_layout(config: Dictionary) -> void:
	_vb_restart.visible = config.get("show_restart", false)
	_vb_feedback.visible = config.get("show_feedback", true)
	_vb_language.visible = config.get("show_language", false)
	_vb_cmp_row.visible = config.get("show_cmp", false)
	_vb_term_row.visible = config.get("show_terms", false)
	_vb_version_row.visible = config.get("show_version", false)


## 按可见开关数量调整网格间距与按钮缩放
func _apply_toggle_grid_layout() -> void:
	var pairs: Array = [
		[_music_ctrl, _music_btn],
		[_sound_ctrl, _sound_btn],
		[_vibration_ctrl, _vibration_btn],
		[_people_ctrl, _people_btn],
	]
	# 统计当前可见的开关数量
	var visible_count: int = 0
	for pair in pairs:
		if (pair[0] as Control).visible:
			visible_count += 1
	# 3 个时收紧间距；4 个时再收紧并整体缩到 0.744 倍
	var h_sep: int = 100
	var btn_scale: float = 1.0
	if visible_count == 3:
		h_sep = 30
	elif visible_count >= 4:
		h_sep = 20

		btn_scale = 0.744
	# 固定 4 列（多余的列不显示）
	_toggle_grid.columns = 4
	_toggle_grid.add_theme_constant_override("h_separation", h_sep)
	# 缩放前把 pivot 归零，避免按中心缩放把位置带偏
	for pair in pairs:
		var ctrl: Control = pair[0] as Control
		if not ctrl.visible:
			continue
		var btn: Control = pair[1] as Control

		btn.pivot_offset = Vector2.ZERO
		btn.scale = Vector2(btn_scale, btn_scale)

		# 控制节点按缩放后的尺寸占位，保证网格对齐
		ctrl.custom_minimum_size = btn.custom_minimum_size * btn_scale


## 设置节点的最小高度（像素）
func _set_miny(node: Control, miny: float) -> void:
	node.custom_minimum_size.y = miny


## 刷新版本号文案（SETTING_VERSION 带 %s 占位）
func _refresh_dynamic_text() -> void:
	# 版本名优先取原生插件（带构建号），编辑器下退回 project.godot
	var version: String = UniKitManager.get_version_name()
	_version_label.text = tr("SETTING_VERSION") % version


## 链接只认「按下」：鼠标左键按下或手指按下
func _is_link_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return event is InputEventScreenTouch and event.pressed


# ================= 开关视觉 =================
# ---- 可调参数（Inspector 可改）：四个开关的「关态」图标贴图 ----
@export var _tex_music_off: Texture2D
@export var _tex_sound_off: Texture2D
@export var _tex_vibrate_off: Texture2D
@export var _tex_people_off: Texture2D

var _icon_on_textures: Dictionary = {}


## 按布尔值切换某个开关的 on / off 面板与图标贴图
func _update_toggle(on_panel: Panel, off_panel: Panel, icon: TextureRect, is_on: bool) -> void:
	# 显隐 on / off 两个面板
	on_panel.visible = is_on
	off_panel.visible = not is_on
	# 第一次见到这个图标时，把它当前的贴图记为「开态」
	if not _icon_on_textures.has(icon):
		_icon_on_textures[icon] = icon.texture
	# 没配关态贴图就不换图
	var off_tex: Texture2D = _get_off_texture(icon)
	if off_tex:
		# 按状态二选一
		icon.texture = _icon_on_textures[icon] if is_on else off_tex


## 按图标节点找对应的「关态」贴图（四选一，找不到返回 null）
func _get_off_texture(icon: TextureRect) -> Texture2D:
	if icon == _icon_music:
		return _tex_music_off
	elif icon == _icon_sound:
		return _tex_sound_off
	elif icon == _icon_vibration:
		return _tex_vibrate_off
	elif icon == _icon_people:
		return _tex_people_off
	return null


func _on_close_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	VibrateManager.play_at(VibrateManager.Pos.SETTING_CLOSE)
	UIManager.hide_ui(UiName.SETTING)


func _on_music_btn_pressed() -> void:
	var new_value: bool = not GameState.is_music_on()
	GameState.set_music_on(new_value)
	VibrateManager.play_at(VibrateManager.Pos.SETTING_TOGGLE)

	SoundManager.refresh_bgm()

	RedDotCenter.refresh(DotName.MUSIC_SWITCH)
	_update_toggle(_music_toggle_on, _music_toggle_off, _icon_music, new_value)
	Toast.popup("SETTING_MUSIC_ON" if new_value else "SETTING_MUSIC_OFF", self)
	Tracker.track_sw_click(
		Tracker.Sw.MUSIC,
		1 if new_value else 0,
		Tracker.Dlg.OPTIONS if is_game_mode else Tracker.Dlg.SETTINGS
	)


func _on_sound_btn_pressed() -> void:
	var new_value: bool = not GameState.is_sound_on()
	GameState.set_sound_on(new_value)
	VibrateManager.play_at(VibrateManager.Pos.SETTING_TOGGLE)
	_update_toggle(_sound_toggle_on, _sound_toggle_off, _icon_sound, new_value)

	if new_value:
		SoundManager.play(SoundManager.Kind.BTN_CLICK)
	Toast.popup("SETTING_SOUND_ON" if new_value else "SETTING_SOUND_OFF", self)
	Tracker.track_sw_click(
		Tracker.Sw.SOUND,
		1 if new_value else 0,
		Tracker.Dlg.OPTIONS if is_game_mode else Tracker.Dlg.SETTINGS
	)


func _on_vibration_btn_pressed() -> void:
	var new_value: bool = not GameState.is_vibration_on()
	GameState.set_vibration_on(new_value)
	_update_toggle(_vibration_toggle_on, _vibration_toggle_off, _icon_vibration, new_value)
	Toast.popup("SETTING_VIBRATION_ON" if new_value else "SETTING_VIBRATION_OFF", self)
	VibrateManager.play_at(VibrateManager.Pos.SETTING_TOGGLE)
	Tracker.track_sw_click(
		Tracker.Sw.VIBRATION,
		1 if new_value else 0,
		Tracker.Dlg.OPTIONS if is_game_mode else Tracker.Dlg.SETTINGS
	)


## 有效按压切换并保存图案模式，刷新红点和提示，再通知当前盘面应用变化。
func _on_pattern_switch_input(event: InputEvent) -> void:
	VibrateManager.play_at(VibrateManager.Pos.SETTING_TOGGLE)

	if not (event is InputEventMouseButton and event.pressed):
		return
	var new_value: bool = not GameState.is_pattern_mode_on()
	GameState.set_pattern_mode_on(new_value)
	_update_pattern_toggle_visual(new_value)

	RedDotCenter.dismiss(DotName.PATTERN_SWITCH)
	Toast.popup("SETTING_PATTERN_ON" if new_value else "SETTING_PATTERN_OFF", self)
	Tracker.track_sw_click(Tracker.Sw.PATTERN, 1 if new_value else 0, Tracker.Dlg.OPTIONS)
	if _on_pattern_changed_cb.is_valid():
		_on_pattern_changed_cb.call()


func _update_pattern_toggle_visual(is_on: bool) -> void:
	_pattern_on_panel.visible = is_on
	_pattern_off_panel.visible = not is_on


func _on_people_btn_pressed() -> void:
	var new_value: bool = not GameState.is_people_on()
	GameState.set_people_on(new_value)
	VibrateManager.play_at(VibrateManager.Pos.SETTING_TOGGLE)
	_update_toggle(_people_toggle_on, _people_toggle_off, _icon_people, new_value)
	Toast.popup("SETTING_PEOPLE_ON" if new_value else "SETTING_PEOPLE_OFF", self)


## 重新开始：本次显示内只允许点一次
func _on_restart_btn_pressed() -> void:
	# 已经点过就忽略，防止连点重开两次
	if _restart_consumed:
		return
	_restart_consumed = true

	# 埋点：点击重开
	Tracker.track_btn_click(Tracker.Btn.RESTART, self)
	# 回调由 game 页传入，负责真正重置本关
	if _on_restart_cb.is_valid():
		_on_restart_cb.call()
	# 关掉设置页
	UIManager.hide_ui(UiName.SETTING)


## 打开用户协议：地址先按语言本地化
func _on_terms_btn_pressed(event: InputEvent = null) -> void:
	# 只响应按下事件，避免悬停 / 抬起也触发
	if event != null and not _is_link_press(event):
		return
	Tracker.track_btn_click(Tracker.Btn.TERMS, self)
	var url: String = UniKitManager.get_localized_privacy_url("https://oakevergames.com/tos.html")
	# 交给系统浏览器打开
	OS.shell_open(url)


## 打开隐私政策（流程同上）
func _on_privacy_btn_pressed(event: InputEvent = null) -> void:
	if event != null and not _is_link_press(event):
		return
	Tracker.track_btn_click(Tracker.Btn.PRIVACY, self)
	var url: String = UniKitManager.get_localized_privacy_url("https://oakevergames.com/pp.html")
	OS.shell_open(url)


## 打开 CMP 隐私偏好界面（原生 SDK）
func _on_privacy_preference_btn_pressed(event: InputEvent = null) -> void:
	if event != null and not _is_link_press(event):
		return
	Tracker.track_btn_click(Tracker.Btn.PRIVACY_PREFERENCE, self)
	UniKitManager.show_cmp_ui()


# ================= 埋点信息与入口跳转 =================
## 埋点用的弹窗名：游戏内叫「选项」，首页叫「设置」
func get_dlg_name() -> String:
	return Tracker.Dlg.OPTIONS if is_game_mode else Tracker.Dlg.SETTINGS


## 埋点附加属性：带上 settings_language 的 A/B 值
func get_dlg_extra() -> Dictionary:
	if is_game_mode:
		return {}
	# 防御：ABTestManager 或其配置还没就绪时返回空
	if ABTestManager == null or ABTestManager.settings_language == null:
		return {}
	return {"settings_language": ABTestManager.settings_language.value()}


## 打开语言选择弹窗
func _on_language_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.LANGUAGE, self)
	UIManager.show_ui(UiName.LANGUAGE)


## 反馈入口：离线先提示，在线才打开 Helpshift FAQ
func _on_feedback_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.FEEDBACK, self)

	# 离线直接提示，不打开客服页
	if not UniKitManager.is_online():
		Toast.popup("NETWORK_ERROR", self)
		return

	# Helpshift 未读数会写进 RedDotCenter，反馈按钮上的红点随之刷新
	HelpshiftManager.open_faq()


func _is_people_toggle_visible() -> bool:
	return true


## 记录点击后打开登录页，并传入当前账号渠道；此处不直接上传存档。
func _on_save_progress_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.SAVE_PROGRESS, self)

	(
		UIManager
		. show_ui(
			UiName.LOGIN,
			{
				"signed_in_channel": AccountManager.get_signed_in_channel(),
			}
		)
	)
