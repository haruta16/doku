## 回流欢迎页：适配猫动画与欢迎文案，等待入场后允许关闭。
extends UIFrameWindow

const _WELCOME_KEY: String = "COMEBACK_WELCOME_TEXT"

const _WELCOME_FALLBACK: String = "Welcome home, {0}! I missed you!"

const _NICKNAME_COLOR: String = "#F19320"

const _BACK_BTN_KEY: String = "COMEBACK_WELCOME_BTN"

const _BACK_BTN_FALLBACK: String = "I'm back!"

const _APPEAR_ANIM: String = "Appear"

const _LOOP_ANIM: String = "Loop"

const _ENDING_ANIM: StringName = &"ShowEnding"

const _ART_CANVAS_SIZE: Vector2 = Vector2(1080, 2400)

@onready var _anim: AnimationPlayer = $Root/AnimationPlayer
@onready var _cat_anchor: Control = $Root/Show/CatAnchor
@onready var _cat: SpineSprite = $Root/Show/CatAnchor/Cat
@onready var _ending: Control = $Root/Ending
@onready var _welcome_label: RichTextLabel = $Root/Ending/WelcomeTxt
@onready var _back_btn: Control = $Root/Ending/BackBtn

var _show_seq_id: int = 0

var _can_leave: bool = false


func on_create() -> void:
	resized.connect(_fit_cat_to_screen)


func on_show(params: Dictionary = {}) -> void:
	if not bool(params.get("preview", false)):
		GameState.mark_comeback_welcome_shown()
	_show_seq_id += 1
	var seq: int = _show_seq_id
	_can_leave = false
	_ending.visible = false
	_welcome_label.text = _welcome_text()
	_back_btn.set("btn_text", _tr_or(_BACK_BTN_KEY, _BACK_BTN_FALLBACK))
	print("[Comeback] 欢迎表演开播 gap=%d" % GameState.get_login_gap_days())
	_fit_cat_to_screen()
	_play_cat()
	if not await _await_appear_finished(seq):
		return
	_ending.visible = true
	AnimUtil.play(_anim, _ENDING_ANIM, false)
	await _anim.animation_finished
	if seq != _show_seq_id:
		return
	_can_leave = true


func on_hide() -> void:
	_show_seq_id += 1
	_can_leave = false


func _fit_cat_to_screen() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var cover_scale: float = maxf(
		1.0, maxf(size.x / _ART_CANVAS_SIZE.x, size.y / _ART_CANVAS_SIZE.y)
	)
	_cat_anchor.scale = Vector2(cover_scale, cover_scale)


func _play_cat() -> void:
	var state: SpineAnimationState = _cat.get_animation_state()
	state.set_animation(_APPEAR_ANIM, false, 0)
	state.add_animation(_LOOP_ANIM, 0.0, true, 0)
	_cat.update_skeleton(0.0)


func _await_appear_finished(seq: int) -> bool:
	while true:
		var signal_args: Array = await _cat.animation_completed
		if seq != _show_seq_id:
			return false
		var entry: SpineTrackEntry = signal_args[2]
		if entry.get_animation().get_name() == _APPEAR_ANIM:
			return true
	return false


func on_escape() -> bool:
	return true


func _on_back_btn_pressed() -> void:
	if not _can_leave:
		return
	_can_leave = false
	print("[Comeback] I'm back 按下 → 进主页")
	UIManager.hide_ui(UiName.COMEBACK_WELCOME)


func _welcome_text() -> String:
	var nickname: String = ProfileService.get_nickname().replace("[", "[lb]")
	var highlighted: String = "[color=%s]%s[/color]" % [_NICKNAME_COLOR, nickname]
	return (
		"[center]%s[/center]" % _tr_or(_WELCOME_KEY, _WELCOME_FALLBACK).replace("{0}", highlighted)
	)


func _tr_or(key: String, fallback: String) -> String:
	var translated: String = tr(key)
	return fallback if translated == key else translated
