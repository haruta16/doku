## 陪伴猫引导页：显示玩法说明与活动倒计时，衔接猫入场和主线入口。
extends UIFrameWindow

signal main_level_requested

const System: GDScript = preload("res://scripts/module/home/core/home_companion_system.gd")
const Service: GDScript = preload("res://scripts/module/home/home_companion_service.gd")
const Interaction: GDScript = preload(
	"res://scripts/module/home/core/home_companion_interaction.gd"
)

@export_range(0.0, 1.0) var tutorial_mask_opacity: float = 0.5

@onready var _popup_anim: AnimationPlayer = $Root/Content/AnimationPlayer
@onready var _card: Control = $Root/Content/Card
@onready var _content: Control = $Root/Content
@onready var _intro: Control = $Root/Intro
@onready var _intro_cat: Control = $Root/Intro/Cat
@onready var _speech: Control = $Root/Intro/Speech
@onready var _speech_text: Label = $Root/Intro/Speech/Text
@onready var _speech_animation: AnimationPlayer = $Root/Intro/Speech/AnimationPlayer
@onready var _default_mask_opacity: float = mask_opacity
@onready var _title: Label = $Root/Content/Card/Title
@onready var _body: RichTextLabel = $Root/Content/Card/Body
@onready var _next: Control = $Root/Content/Card/NextButton
@onready var _next_button: Button = $Root/Content/Card/NextButton/Root/Bg
@onready var _banner: Control = $Root/Content/Card/Banner
@onready var _countdown: Control = $Root/Content/Card/Banner/Countdown
@onready var _countdown_label: TabularDigitLabel = $Root/Content/Card/Banner/Countdown/CountdownLabel
@onready var _countdown_icon: TextureRect = $Root/Content/Card/Banner/Countdown/CountdownIcon
@onready var _countdown_icon_width: float = _countdown_icon.size.x
@onready var _countdown_label_width: float = _countdown_label.size.x
@onready
var _countdown_center: float = (_countdown_icon.offset_left + _countdown_label.offset_right) * 0.5

const COUNTDOWN_ICON_GAP: float = 13.0

var _kind: StringName = &""
var _tutorial: bool = false
var _completed: bool = false
var _main_level_requested: bool = false
var _clock: Callable
var _intro_active: bool = false
var _intro_step: int = 0
var _intro_source: Control
var _mask_target_opacity: float = 0.0


func on_show(params: Dictionary = {}) -> void:
	if is_instance_valid(_intro_source):
		disconnect_managed(_intro_source.item_rect_changed, _queue_intro_layout)
	_intro_source = params.get("cat_source") as Control
	_kind = StringName(params.get("kind", "halloween"))
	_tutorial = bool(params.get("tutorial", false))
	_mask_target_opacity = tutorial_mask_opacity if _tutorial else _default_mask_opacity
	_completed = false
	_main_level_requested = false
	_clock = params.get("clock", Callable())
	_next_button.disabled = false
	_intro_cat.end_home_entry()
	_sync_intro_sound()
	connect_managed(UIManager.events.window_shown, _on_intro_cover_shown)
	connect_managed(UIManager.events.window_hidden, _on_intro_cover_hidden)
	_intro_active = _tutorial and _kind in [&"halloween", &"cans", &"satiety"]
	_intro_step = 0
	UIManager.set_window_mask_opacity(self, 0.0 if _intro_active else _mask_target_opacity)
	_speech_animation.stop()
	_speech.modulate = Color.WHITE
	_speech.hide()
	_intro.visible = _intro_active
	_content.visible = not _intro_active
	_refresh()
	if _intro_active:
		connect_managed(_intro_cat.entry_speech_revealed, _on_entry_speech_revealed)
		connect_managed(_speech.resized, _queue_intro_layout)
		if is_instance_valid(_intro_source):
			connect_managed(_intro_source.item_rect_changed, _queue_intro_layout)
		_intro_cat.scale = params.get("cat_scale", Vector2.ONE * 0.65)
		_intro_cat.global_position = params.get(
			"cat_position", Vector2(size.x * 0.5 - 208.0, size.y * 0.5 - 120.0)
		)
		_speech_text.text = (
			tr("HOME_COMPANION_HALLOWEEN_GREETING")
			if _kind == &"halloween"
			else tr("HOME_COMPANION_GREETING")
		)
		_refresh_intro_layout()
		var mode: int = Interaction.Mode.CANDY
		if _kind == &"cans":
			mode = Interaction.Mode.CANS
		elif _kind == &"satiety":
			mode = Interaction.Mode.SATIETY
		_intro_cat.begin_tutorial_preview(
			mode, int(params.get("food_count", 0)), float(params.get("satiety", 60.0))
		)
	if _countdown.visible:
		_update_countdown()
		if not ClockTicker.second_tick.is_connected(_update_countdown):
			connect_managed(ClockTicker.second_tick, _update_countdown)
		if not _countdown_label.draw.is_connected(_reflow_countdown):
			connect_managed(_countdown_label.draw, _reflow_countdown)
	else:
		disconnect_managed(ClockTicker.second_tick, _update_countdown)
		disconnect_managed(_countdown_label.draw, _reflow_countdown)


func was_completed() -> bool:
	return _completed


func should_enter_main_level() -> bool:
	return _main_level_requested


func _sync_intro_sound() -> void:
	_intro_cat.set_sound_enabled(is_showing() and UIManager.get_top_window() == self)


func _on_intro_cover_shown(_ui_name: String, _window: UIFrameWindow) -> void:
	_sync_intro_sound()


func _on_intro_cover_hidden(_ui_name: String, _window: UIFrameWindow) -> void:
	_sync_intro_sound.call_deferred()


func on_stack_top() -> void:
	_sync_intro_sound()


func on_stack_bottom() -> void:
	_intro_cat.set_sound_enabled(false)


func get_dlg_name() -> String:
	return Tracker.Dlg.COMPANION_CAT_GUIDE if _kind == &"halloween" else ""


func _on_entry_speech_revealed() -> void:
	if _intro_active and is_showing():
		UIManager.set_window_mask_opacity(self, _mask_target_opacity, 0.2)
		_speech.show()
		_speech_animation.play(&"appear")
		_speech_animation.advance(0.0)


func on_escape() -> bool:
	if _kind == &"halloween" and not _intro_active:
		_completed = _tutorial
		Tracker.track_btn_click(Tracker.Btn.CLOSE, self)
	UIManager.hide_ui(get_ui_name())
	return true


func _refresh() -> void:
	_fit_popup()
	_banner.visible = true
	_countdown.visible = _kind == &"halloween"
	if _kind == &"halloween":
		_title.text = tr("HOME_COMPANION_HALLOWEEN_TITLE")
		_body.text = tr("HOME_COMPANION_HALLOWEEN_DESC")
	else:
		_title.text = tr("HOME_COMPANION_GUIDE_TITLE")
		_body.text = (
			tr("HOME_COMPANION_GUIDE_CANS_DESC") + "\n\n" + tr("HOME_COMPANION_GUIDE_CAN_RULE")
		)
		if _kind == &"satiety":
			_body.text += "\n\n" + tr("HOME_COMPANION_GUIDE_SATIETY_RULE")

	_next.btn_text = tr("RANK_OPEN_CONFIRM")


func _update_countdown() -> void:
	if not _countdown.visible:
		return
	var now: int = int(_clock.call()) if _clock.is_valid() else Service.local_now()
	_countdown_label.text = System.format_countdown(System.EVENT_END - now)
	_reflow_countdown()


func _reflow_countdown() -> void:
	var text_width: float = _countdown_label.ensure_block_width()
	if text_width <= 0.0:
		return
	var group_width: float = _countdown_icon_width + COUNTDOWN_ICON_GAP + text_width
	var group_right: float = _countdown_center + group_width * 0.5
	var icon_left: float = group_right - group_width
	if is_equal_approx(_countdown_icon.offset_left, icon_left):
		return
	_countdown_icon.offset_left = icon_left
	_countdown_icon.offset_right = icon_left + _countdown_icon_width
	_countdown_label.offset_left = group_right - _countdown_label_width
	_countdown_label.offset_right = group_right


func _fit_popup() -> void:
	var fit_scale: float = minf(1.0, minf(size.x / 1080.0, size.y / 1380.0))
	_card.scale = Vector2.ONE * fit_scale
	_card.position = (size - _card.size * fit_scale) * 0.5


func _on_resized() -> void:
	if is_node_ready():
		_fit_popup()
		if _intro_active:
			_queue_intro_layout()


func _queue_intro_layout() -> void:
	_refresh_intro_layout.call_deferred()


func _refresh_intro_layout() -> void:
	if not _intro_active:
		return
	if is_instance_valid(_intro_source):
		_intro_cat.scale = _intro_source.get_global_transform().get_scale()
		_intro_cat.global_position = _intro_source.global_position
	_intro_cat.refresh_accessory_layout(global_position.x + size.x * 0.5)
	var cat_foot: Vector2 = _intro_cat.cat_sprite.global_position
	_speech.fit_to_text(size.x - 120.0)
	_speech.global_position = Vector2(
		global_position.x + (size.x - _speech.size.x) * 0.5, cat_foot.y - 588.0 - _speech.size.y
	)


func _on_next_pressed() -> void:
	if _intro_active or _completed or _main_level_requested or not is_showing():
		return
	_next_button.disabled = true
	_completed = _tutorial
	_main_level_requested = _kind == &"halloween"
	if _kind == &"halloween":
		Tracker.track_btn_click(Tracker.Btn.GOT_IT_CAP, self)

		main_level_requested.emit()
	UIManager.hide_ui(get_ui_name())


func on_hide() -> void:
	_intro_cat.set_sound_enabled(false)
	_popup_anim.stop()
	_speech_animation.stop()
	_speech.modulate = Color.WHITE
	_intro_cat.end_home_entry()
	_intro_active = false
	_next_button.disabled = false


func _play_open_animation() -> void:
	if _intro_active:
		_popup_anim.stop()
		return
	super._play_open_animation()


func _input(event: InputEvent) -> void:
	if not _intro_active or not is_showing() or not UIManager.is_top_of_stack(self):
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		if not _intro_cat.is_entry_speech_ready():
			return
		if _kind != &"halloween":
			if _intro_step == 0:
				_intro_step = 1
				_speech_text.text = (
					tr("HOME_COMPANION_HUNGRY_SATIETY")
					if _kind == &"satiety"
					else tr("HOME_COMPANION_HUNGRY_CANS")
				)
				_refresh_intro_layout()
				_intro_cat.show_tutorial_hunger()
			else:
				_completed = true
				UIManager.hide_ui(get_ui_name())
			return
		_intro_active = false
		_intro_cat.end_home_entry()
		_intro.hide()
		_content.show()
		_play_open_animation()
