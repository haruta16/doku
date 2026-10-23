## 断签恢复选择页：展示断签信息和恢复按钮，以展示序号区分每次异步查询。
extends UIFrameWindow

signal restore_requested

signal give_up_requested

@export var info_text_key: String = ""

@onready var _info: RichTextLabel = %InfoText

const _ICON_BASE_HEIGHT: float = 191.0
const _ICON_CENTER := Vector2(95.5, 95.5)

const _UNLIT_ALPHA: float = 0.2

@onready var _sun_from_num: Label = %SunFromNum
@onready var _sun_to_num: Label = %SunToNum
@onready var _restore_btn: Control = %RestoreBtn
@onready var _give_up_btn: Control = %GiveUpBtn
@onready var _anim: AnimationPlayer = $AnimationPlayer

@onready var _icon_from: StreakDayIcon = $Content/SunGroup/Sun2/SunImg
@onready var _icon_to: StreakDayIcon = $Content/SunGroup/Sun1/SunImg

var _show_seq_id: int = 0

var _restore_query_pending: bool = false


func on_create() -> void:
	_restore_btn.tag_pressed.connect(_on_restore_pressed)
	_give_up_btn.tag_pressed.connect(_on_give_up_pressed)


func on_show(params: Dictionary = {}) -> void:
	_show_seq_id += 1
	_restore_query_pending = false

	_icon_from.refresh_group(true)
	_icon_to.refresh_group(false)

	_icon_to.modulate.a = (
		1.0
		if ABTestManager.dailystreak_icon.has_unchecked_art(
			StreakManager.get_effective_icon_group()
		)
		else _UNLIT_ALPHA
	)

	_icon_from.fit_uniform_height(_ICON_BASE_HEIGHT, _ICON_CENTER)
	_icon_to.fit_uniform_height(_ICON_BASE_HEIGHT, _ICON_CENTER)
	_refresh_info(int(params.get("info_days", 0)))
	if params.has("from_streak"):
		_sun_from_num.text = str(params["from_streak"])
	if params.has("to_streak"):
		_sun_to_num.text = str(params["to_streak"])


func _refresh_info(streak_days: int) -> void:
	if info_text_key != "" and _info != null:
		_info.text = tr(info_text_key) % streak_days


func on_hide() -> void:
	_show_seq_id += 1
	_restore_query_pending = false
	if _anim != null and _anim.has_animation(&"GenericPopup"):
		_anim.play_section_with_markers("GenericPopup", &"Mark", &"")
		await _anim.animation_finished


func get_show_sequence() -> int:
	return _show_seq_id


func set_restore_query_pending(pending: bool, seq: int) -> void:
	if seq == _show_seq_id:
		_restore_query_pending = pending


func _on_restore_pressed() -> void:
	if _restore_query_pending or not is_showing():
		return
	restore_requested.emit()


func _on_give_up_pressed() -> void:
	if not is_showing():
		return
	give_up_requested.emit()


func _on_close_btn_pressed() -> void:
	if not is_showing():
		return
	give_up_requested.emit()
