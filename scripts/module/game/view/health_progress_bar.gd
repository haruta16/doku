## 进度式生命栏：布局生命槽并处理单槽居中、损失和类型切换。
class_name HealthProgressBar
extends HealthBarBase

@onready var _slot1: Control = $LifeSlot
@onready var _slot2: Control = $LifeSlot2
@onready var _slot3: Control = $LifeSlot3

var _life_slot_home_x: float = 0.0
var _life_slot_home_x_valid: bool = false

var _life_slot_single_active: bool = false


func slots() -> Array[Control]:
	return [_slot1, _slot2, _slot3]


func refresh(lives: int) -> void:
	var all_slots: Array[Control] = slots()
	for i in all_slots.size():
		var slot := all_slots[i] as LifeSlot
		if slot == null:
			continue
		if i < lives:
			slot.show_alive()
		else:
			slot.show_lost(false)


func animate_lost(index: int, _lives_after: int = -1) -> void:
	var slot := slot_at(index) as LifeSlot
	if slot != null:
		slot.show_lost(true)


func apply_kind(is_golden: bool) -> void:
	var all_slots: Array[Control] = slots()
	for slot: Control in all_slots:
		if slot != null and slot.has_method("set_golden"):
			slot.set_golden(is_golden)
	_apply_single_center(is_golden)


func _apply_single_center(single: bool) -> void:
	if single and not _life_slot_single_active and _slot1 != null:
		_life_slot_home_x = _slot1.position.x
		_life_slot_home_x_valid = true
	_life_slot_single_active = single

	if _slot1 != null:
		_slot1.visible = true
	if _slot2 != null:
		_slot2.visible = not single
	if _slot3 != null:
		_slot3.visible = not single
	if _slot1 == null:
		return
	if single:
		if _slot2 != null:
			_slot1.position.x = _slot2.position.x
	elif _life_slot_home_x_valid:
		_slot1.position.x = _life_slot_home_x
