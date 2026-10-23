## 生命栏接口：统一槽位访问、损失与复活动画，以及收集飞行动画所需的临时隐藏。
class_name HealthBarBase
extends Control

var _flight_hidden_slots: Array[Control] = []


func refresh(_lives: int) -> void:
	pass


func animate_lost(_index: int, _lives_after: int = -1) -> void:
	pass


func apply_kind(_is_golden: bool) -> void:
	pass


func slots() -> Array[Control]:
	return []


func slot_at(index: int) -> Control:
	var all_slots: Array[Control] = slots()
	if index < 0 or index >= all_slots.size():
		return null
	return all_slots[index]


func revive_all() -> void:
	var all_slots: Array[Control] = slots()
	for slot: Control in all_slots:
		if slot is LifeSlot:
			(slot as LifeSlot).play_revive()


func play_highlight_glow_at(index: int) -> void:
	var slot := slot_at(index) as LifeSlot
	if slot != null:
		slot.play_highlight_glow()


func stop_highlight_glow() -> void:
	var all_slots: Array[Control] = slots()
	for slot: Control in all_slots:
		if slot is LifeSlot:
			(slot as LifeSlot).stop_highlight_glow()


func mark_slot_lost_for_flight(slot: Control, silent: bool = false) -> void:
	if slot == null or not is_instance_valid(slot):
		return
	if slot is LifeSlot:
		(slot as LifeSlot).show_lost(false, silent)
	else:
		slot.visible = false
	if not _flight_hidden_slots.has(slot):
		_flight_hidden_slots.append(slot)


func restore_hidden_slots() -> void:
	for slot: Control in _flight_hidden_slots:
		if not is_instance_valid(slot):
			continue
		slot.visible = true
		if slot is LifeSlot:
			(slot as LifeSlot).show_alive()
	_flight_hidden_slots.clear()
