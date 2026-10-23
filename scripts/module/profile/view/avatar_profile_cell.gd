## 资料页中的头像或头像框选项；区分选中、锁定与门槛提示，并把点击交给资料页处理。

extends UIChildWindow

signal cell_pressed(id: int, form: int)
signal cell_locked_pressed(id: int, form: int)

signal cell_pressed_down(id: int, form: int)

const _LOCK_SHAKE_ANIM: StringName = &"Lock"

const AVATAR_CELL: PackedScene = preload("res://scripts/module/profile/ui/avatar_cell.tscn")

@onready var _check: Control = $Check
@onready var _lock: TextureRect = $Lock
@onready var _anim: AnimationPlayer = $AnimationPlayer

var _cell: Control = null
var _id: int = 0

var _form: int = 0
var _locked: bool = false


func _ready() -> void:
	super._ready()

	_cell = AVATAR_CELL.instantiate()
	$AvatarSlot.add_child(_cell)


func setup_avatar(id: int) -> void:
	_id = id
	_form = 0
	_cell.set_frame_visible(false)
	_cell.set_avatar(id)


func setup_frame(id: int, form: int = 0) -> void:
	_id = id
	_form = form
	_cell.set_avatar_visible(false)
	_cell.set_frame(id, form)


func set_selected(selected: bool) -> void:
	_check.visible = selected


func set_locked(locked: bool) -> void:
	_locked = locked
	_lock.visible = locked


func set_content_alpha(alpha: float) -> void:
	$AvatarSlot.modulate.a = alpha


func show_threshold_badge(threshold: int) -> void:
	_cell.set_count_forced(threshold)


func get_id() -> int:
	return _id


func get_form() -> int:
	return _form


func _on_click_down() -> void:
	cell_pressed_down.emit(_id, _form)


func _on_click_pressed() -> void:
	if _locked:
		_anim.play(_LOCK_SHAKE_ANIM)
		cell_locked_pressed.emit(_id, _form)
	else:
		cell_pressed.emit(_id, _form)
