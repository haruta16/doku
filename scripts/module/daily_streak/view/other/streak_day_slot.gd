@tool
extends Control

const COLOR_CHECKED := Color(0.94509804, 0.5764706, 0.1254902, 1)
const COLOR_INACTIVE := Color(0.5769231, 0.3522559, 0.3522559, 1)

@export var weekday: String = "WEEKDAY_WED":
	set = set_weekday
@export var checked: bool = false:
	set = set_checked
@export var is_chest: bool = false:
	set = set_chest

@onready var _label: Label = $WeekLabel
@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _unchecked: Control = $UncheckedDot
@onready var _checked: Control = $CheckedDot
@onready var _chest: Control = $Chest
@onready var _gift_cell: Control = $Chest/StreakGiftCell
@onready var _click_area: Button = $Chest/ClickArea

var _applying: bool = false


func _ready() -> void:
	_show_static()

	if _click_area and not _click_area.pressed.is_connected(_on_chest_pressed):
		_click_area.pressed.connect(_on_chest_pressed)


func _gift_anim() -> AnimationPlayer:
	if _gift_cell == null:
		return null
	return _gift_cell.get_node_or_null("AnimationPlayer") as AnimationPlayer


func _play_chest_loop() -> void:
	var ap := _gift_anim()
	if ap == null or not ap.has_animation(&"Loop"):
		return
	ap.get_animation(&"Loop").loop_mode = Animation.LOOP_LINEAR
	ap.play(&"Loop")


func _on_chest_pressed() -> void:
	var ap := _gift_anim()
	if ap == null or not ap.has_animation(&"Click"):
		return
	ap.play(&"Click")
	await ap.animation_finished
	if is_instance_valid(ap):
		_play_chest_loop()


func set_weekday(v: String) -> void:
	weekday = v
	if is_inside_tree():
		_refresh_label()


func set_checked(v: bool) -> void:
	checked = v
	if is_inside_tree() and not _applying:
		_show_static()


func set_chest(v: bool) -> void:
	is_chest = v
	if is_inside_tree() and not _applying:
		_show_static()


func apply_static(is_checked: bool, is_chest_slot: bool) -> void:
	_applying = true
	checked = is_checked
	is_chest = is_chest_slot
	_applying = false
	_show_static()


func play_checkin(chest: bool) -> float:
	_applying = true
	is_chest = chest
	checked = true
	_applying = false
	_refresh_label()
	if _anim == null:
		return 0.0
	if chest:
		_set_dots(false, false, true)
		_anim.play(&"Reward")
	else:
		_set_dots(true, true, false)

		if _anim.has_animation(&"RESET"):
			_anim.play(&"RESET")
			_anim.seek(0.0, true)
		_anim.play(&"CheckIn")

		if not Engine.is_editor_hint():
			SoundManager.play(SoundManager.Kind.USE_HINT)
	return _anim.current_animation_length


func show_unchecked_dot() -> void:
	_set_dots(true, false, false)


func _show_static() -> void:
	_refresh_label()
	if checked:
		_set_dots(false, true, false)
	elif is_chest:
		_set_dots(false, false, true)
	else:
		_set_dots(true, false, false)
	if _anim == null:
		return
	_anim.play(&"Idle" if checked else &"RESET")
	_anim.seek(_anim.current_animation_length, true)


func hide_chest() -> void:
	if _chest:
		_chest.visible = false


func _set_dots(unchecked: bool, checked_dot: bool, chest: bool) -> void:
	if _unchecked:
		_unchecked.visible = unchecked
	if _checked:
		_checked.visible = checked_dot
	if _chest:
		_chest.visible = chest
	if chest:
		_play_chest_loop()


func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = tr(weekday)
	_label.add_theme_color_override("font_color", COLOR_CHECKED if checked else COLOR_INACTIVE)
