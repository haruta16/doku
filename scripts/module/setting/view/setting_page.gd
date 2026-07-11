class_name SettingPage
extends UIFrameWindow

var is_game_mode: bool = false

static var debug_force_show_cmp: bool = false

@onready var _toggle_grid: GridContainer = $Root/Content/PanelContainer/VBoxContainer/GridContainer
@onready
var _sound_ctrl: Control = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl
@onready
var _sound_btn: BaseButton = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl/SoundBtn
@onready
var _vibration_ctrl: Control = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl
@onready
var _vibration_btn: BaseButton = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl/VibrationBtn

@onready
var _people_ctrl: Control = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl
@onready
var _people_btn: BaseButton = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl/PeopleBtn

@onready
var _music_ctrl: Control = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl
@onready
var _music_btn: BaseButton = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl/MusicBtn
@onready
var _music_toggle_on: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl/MusicBtn/ToggleOn
@onready
var _music_toggle_off: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl/MusicBtn/ToggleOff
@onready
var _sound_toggle_on: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl/SoundBtn/ToggleOn
@onready
var _sound_toggle_off: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl/SoundBtn/ToggleOff
@onready
var _vibration_toggle_on: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl/VibrationBtn/ToggleOn
@onready
var _vibration_toggle_off: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl/VibrationBtn/ToggleOff
@onready
var _icon_music: TextureRect = $Root/Content/PanelContainer/VBoxContainer/GridContainer/MusicCtrl/MusicBtn/IconMusic
@onready
var _icon_sound: TextureRect = $Root/Content/PanelContainer/VBoxContainer/GridContainer/SoundCtrl/SoundBtn/IconSound
@onready
var _icon_vibration: TextureRect = $Root/Content/PanelContainer/VBoxContainer/GridContainer/VibrationCtrl/VibrationBtn/IconVibration
@onready
var _people_toggle_on: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl/PeopleBtn/ToggleOn
@onready
var _people_toggle_off: Panel = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl/PeopleBtn/ToggleOff
@onready
var _icon_people: TextureRect = $Root/Content/PanelContainer/VBoxContainer/GridContainer/PeopleCtrl/PeopleBtn/IconPeople
@onready
var _terms_btn: UnderlineLink = $Root/Content/PanelContainer/VBoxContainer/TermContainer/TermsBtn
@onready
var _privacy_btn: UnderlineLink = $Root/Content/PanelContainer/VBoxContainer/TermContainer/PrivacyBtn
@onready
var _privacy_preference_btn: UnderlineLink = $Root/Content/PanelContainer/VBoxContainer/PrivacyContainer/PrivacyPreferenceBtn
@onready
var _version_label: Label = $Root/Content/PanelContainer/VBoxContainer/HBoxContainer/VersionLabel
@onready var _panel_container: PanelContainer = $Root/Content/PanelContainer
@onready var _anim: AnimationPlayer = $Root/AnimationPlayer

@onready
var _vb_how_to_play: Button = $Root/Content/PanelContainer/VBoxContainer/BtnContainer/HowToPlayBtn
@onready
var _vb_restart: Control = $Root/Content/PanelContainer/VBoxContainer/BtnContainer/OrangeRestartBtn
@onready
var _vb_restart_bg: Button = $Root/Content/PanelContainer/VBoxContainer/BtnContainer/OrangeRestartBtn/Bg
@onready
var _vb_feedback: Button = $Root/Content/PanelContainer/VBoxContainer/BtnContainer/FeedbackBtn
@onready
var _vb_language: Button = $Root/Content/PanelContainer/VBoxContainer/BtnContainer/LanguageBtn
@onready var _vb_cmp_row: Control = $Root/Content/PanelContainer/VBoxContainer/PrivacyContainer
@onready var _vb_term_row: Control = $Root/Content/PanelContainer/VBoxContainer/TermContainer
@onready var _vb_version_row: Control = $Root/Content/PanelContainer/VBoxContainer/HBoxContainer

@onready var _vb_sp3: Control = $Root/Content/PanelContainer/VBoxContainer/Control3
@onready var _vb_sp6: Control = $Root/Content/PanelContainer/VBoxContainer/Control6

var _sp3_static_miny: float = 0.0

var _on_restart_cb: Callable = Callable()

var _on_close_cb: Callable = Callable()
var _closing: bool = false

var _restart_consumed: bool = false

var _skip_next_close_anim: bool = false
var _suppress_next_close_cb: bool = false


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
	bind_press_release_scale(_vb_how_to_play)
	bind_press_release_scale(_vb_feedback)
	bind_press_release_scale(_vb_language)

	claim_button_sound(_sound_btn)

	for b in [_terms_btn, _privacy_preference_btn, _privacy_btn]:
		b.resized.connect(_queue_unify_terms_row_font_size)


func on_show(params: Dictionary = {}) -> void:
	is_game_mode = params.get("is_game_mode", false)

	HelpshiftManager.request_unread()

	if ABTestManager.bgm_test.is_enabled():
		_music_ctrl.visible = true
	else:
		_music_ctrl.visible = false

	_people_ctrl.visible = _is_people_toggle_visible()

	_apply_toggle_grid_layout()
	_update_toggle(_music_toggle_on, _music_toggle_off, _icon_music, GameState.is_music_on())
	_update_toggle(_people_toggle_on, _people_toggle_off, _icon_people, GameState.is_people_on())
	_on_restart_cb = params.get("on_restart", Callable())
	_on_close_cb = params.get("on_close", Callable())

	var show_how_to_play: bool = is_game_mode and ABTestManager.rule_text.is_setting_entry()

	var show_language: bool = (
		(not is_game_mode) and ABTestManager.settings_language.is_language_switch_enabled()
	)

	var show_cmp: bool = (
		(not is_game_mode) and (UniKitManager.check_cmp_required() or debug_force_show_cmp)
	)
	apply_vbox_layout(
		{
			"show_how_to_play": show_how_to_play,
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


func _center_panel_vertically() -> void:
	if not is_instance_valid(_panel_container):
		return

	var h: float = _panel_container.get_combined_minimum_size().y
	_panel_container.offset_top = -h / 2.0
	_panel_container.offset_bottom = h / 2.0


func on_hide() -> void:
	if _closing:
		return
	_closing = true

	var should_call_cb: bool = not _suppress_next_close_cb
	_suppress_next_close_cb = false
	if _skip_next_close_anim:
		_skip_next_close_anim = false
		visible = false
		if should_call_cb and _on_close_cb.is_valid():
			_on_close_cb.call()
		return
	_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
	await _anim.animation_finished
	visible = false

	if should_call_cb and _on_close_cb.is_valid():
		_on_close_cb.call()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()

		_queue_unify_terms_row_font_size()


var _unify_queued: bool = false


func _queue_unify_terms_row_font_size() -> void:
	if _unify_queued:
		return
	_unify_queued = true
	call_deferred("_unify_terms_row_font_size")


func _unify_terms_row_font_size() -> void:
	_unify_queued = false
	if _vb_term_row == null or not _vb_term_row.visible:
		return
	var btns: Array[UnderlineLink] = [_terms_btn, _privacy_preference_btn, _privacy_btn]
	var min_fs: int = -1
	for b in btns:
		if b == null or not b.visible:
			continue
		var fs: int = b.measure_fit_font_size()
		if min_fs < 0 or fs < min_fs:
			min_fs = fs
	if min_fs <= 0:
		return
	for b in btns:
		if b == null or not b.visible:
			continue
		b.set_font_size_cap(min_fs)


func apply_vbox_layout(config: Dictionary) -> void:
	_vb_how_to_play.visible = config.get("show_how_to_play", false)
	_vb_restart.visible = config.get("show_restart", false)
	_vb_feedback.visible = config.get("show_feedback", true)
	_vb_language.visible = config.get("show_language", false)
	_vb_cmp_row.visible = config.get("show_cmp", false)
	_vb_term_row.visible = config.get("show_terms", false)
	_vb_version_row.visible = config.get("show_version", false)


func _apply_toggle_grid_layout() -> void:
	var pairs: Array = [
		[_music_ctrl, _music_btn],
		[_sound_ctrl, _sound_btn],
		[_vibration_ctrl, _vibration_btn],
		[_people_ctrl, _people_btn],
	]
	var visible_count: int = 0
	for pair in pairs:
		if (pair[0] as Control).visible:
			visible_count += 1
	var h_sep: int = 100
	var btn_scale: float = 1.0
	if visible_count == 3:
		h_sep = 30
	elif visible_count >= 4:
		h_sep = 20

		btn_scale = 0.744
	_toggle_grid.columns = 4
	_toggle_grid.add_theme_constant_override("h_separation", h_sep)
	for pair in pairs:
		var ctrl: Control = pair[0] as Control
		if not ctrl.visible:
			continue
		var btn: Control = pair[1] as Control

		btn.pivot_offset = Vector2.ZERO
		btn.scale = Vector2(btn_scale, btn_scale)

		ctrl.custom_minimum_size = btn.custom_minimum_size * btn_scale


func _set_miny(node: Control, miny: float) -> void:
	node.custom_minimum_size.y = miny


func _refresh_dynamic_text() -> void:
	var version: String = UniKitManager.get_version_name()
	_version_label.text = tr("SETTING_VERSION") % version


func _is_link_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return event is InputEventScreenTouch and event.pressed


@export var _tex_music_off: Texture2D
@export var _tex_sound_off: Texture2D
@export var _tex_vibrate_off: Texture2D
@export var _tex_people_off: Texture2D

var _icon_on_textures: Dictionary = {}


func _update_toggle(on_panel: Panel, off_panel: Panel, icon: TextureRect, is_on: bool) -> void:
	on_panel.visible = is_on
	off_panel.visible = not is_on
	if not _icon_on_textures.has(icon):
		_icon_on_textures[icon] = icon.texture
	var off_tex: Texture2D = _get_off_texture(icon)
	if off_tex:
		icon.texture = _icon_on_textures[icon] if is_on else off_tex


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
	UIManager.hide_ui(UiName.SETTING)


func _on_music_btn_pressed() -> void:
	var new_value: bool = not GameState.is_music_on()
	GameState.set_music_on(new_value)

	SoundManager.refresh_bgm()
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
	if new_value:
		VibrateManager.play_vibrate(VibrateManager.Level.LEVEL3)
	Tracker.track_sw_click(
		Tracker.Sw.VIBRATION,
		1 if new_value else 0,
		Tracker.Dlg.OPTIONS if is_game_mode else Tracker.Dlg.SETTINGS
	)


func _on_people_btn_pressed() -> void:
	var new_value: bool = not GameState.is_people_on()
	GameState.set_people_on(new_value)
	_update_toggle(_people_toggle_on, _people_toggle_off, _icon_people, new_value)
	Toast.popup("SETTING_PEOPLE_ON" if new_value else "SETTING_PEOPLE_OFF", self)


func _on_restart_btn_pressed() -> void:
	if _restart_consumed:
		return
	_restart_consumed = true

	Tracker.track_btn_click(Tracker.Btn.RESTART, self)
	if _on_restart_cb.is_valid():
		_on_restart_cb.call()
	UIManager.hide_ui(UiName.SETTING)


func _on_terms_btn_pressed(event: InputEvent = null) -> void:
	if event != null and not _is_link_press(event):
		return
	Tracker.track_btn_click(Tracker.Btn.TERMS, self)
	var url: String = UniKitManager.get_localized_privacy_url("https://oakevergames.com/tos.html")
	OS.shell_open(url)


func _on_privacy_btn_pressed(event: InputEvent = null) -> void:
	if event != null and not _is_link_press(event):
		return
	Tracker.track_btn_click(Tracker.Btn.PRIVACY, self)
	var url: String = UniKitManager.get_localized_privacy_url("https://oakevergames.com/pp.html")
	OS.shell_open(url)


func _on_privacy_preference_btn_pressed(event: InputEvent = null) -> void:
	if event != null and not _is_link_press(event):
		return
	Tracker.track_btn_click(Tracker.Btn.PRIVACY_PREFERENCE, self)
	UniKitManager.show_cmp_ui()


func get_dlg_name() -> String:
	return Tracker.Dlg.OPTIONS if is_game_mode else Tracker.Dlg.SETTINGS


func get_dlg_extra() -> Dictionary:
	if is_game_mode:
		return {}
	if ABTestManager == null or ABTestManager.settings_language == null:
		return {}
	return {"settings_language": ABTestManager.settings_language.value()}


func _on_how_to_play_btn_pressed() -> void:
	var htp := UIManager.show_ui(UiName.HOW_TO_PLAY_PAGED)
	_skip_next_close_anim = true
	_suppress_next_close_cb = true
	UIManager.hide_ui(UiName.SETTING)
	await htp.closed
	if _on_close_cb.is_valid():
		_on_close_cb.call()


func _on_language_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.LANGUAGE, self)
	UIManager.show_ui(UiName.LANGUAGE)


func _on_feedback_btn_pressed() -> void:
	Tracker.track_btn_click(Tracker.Btn.FEEDBACK, self)

	if not UniKitManager.is_online():
		Toast.popup("NETWORK_ERROR", self)
		return

	HelpshiftManager.open_faq()


func _is_people_toggle_visible() -> bool:
	return ABTestManager.combo_voice.is_enabled()
