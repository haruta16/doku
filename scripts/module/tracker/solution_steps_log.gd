## 解题步骤日志：记录和撤销可表示的单格动作，支持本轮及累计状态序列化。
class_name SolutionStepsLog
extends RefCounted

const MAX_CHARS: int = 150000

const KEY_ROUND: String = "round"
const KEY_TOTAL: String = "total"

var round_steps: Array = []
var total_steps: Array = []
var _round_chars: int = 0
var _total_chars: int = 0


func append(step: Dictionary) -> void:
	var step_chars: int = _step_chars(step)
	if _round_chars + step_chars <= MAX_CHARS:
		round_steps.append(step)
		_round_chars += step_chars
	if _total_chars + step_chars <= MAX_CHARS:
		total_steps.append(step.duplicate(true))
		_total_chars += step_chars


func remove_latest_single_cell_step(row: int, col: int, actions: Array) -> bool:
	var round_index: int = _latest_single_cell_step_index(round_steps, row, col, actions)
	if round_index >= 0:
		_round_chars -= _step_chars(round_steps[round_index])
		round_steps.remove_at(round_index)
	var total_index: int = _latest_single_cell_step_index(total_steps, row, col, actions)
	if total_index >= 0:
		_total_chars -= _step_chars(total_steps[total_index])
		total_steps.remove_at(total_index)
	return round_index >= 0


func reset_round() -> void:
	round_steps.clear()
	_round_chars = 0


func reset_all() -> void:
	reset_round()
	total_steps.clear()
	_total_chars = 0


func is_empty() -> bool:
	return round_steps.is_empty() and total_steps.is_empty()


func to_dict() -> Dictionary:
	return {KEY_ROUND: round_steps.duplicate(true), KEY_TOTAL: total_steps.duplicate(true)}


func load_dict(data: Dictionary) -> void:
	reset_all()
	var saved_round: Variant = data.get(KEY_ROUND, [])
	var saved_total: Variant = data.get(KEY_TOTAL, [])
	if saved_round is Array:
		round_steps = (saved_round as Array).duplicate(true)
	if saved_total is Array:
		total_steps = (saved_total as Array).duplicate(true)
	_round_chars = _steps_chars(round_steps)
	_total_chars = _steps_chars(total_steps)


static func _latest_single_cell_step_index(steps: Array, row: int, col: int, actions: Array) -> int:
	for i: int in range(steps.size() - 1, -1, -1):
		var step: Variant = steps[i]
		if not (step is Dictionary):
			continue
		var cells: Variant = (step as Dictionary).get("cells", [])
		if not (cells is Array) or not _cells_touch(cells as Array, row, col):
			continue
		if (cells as Array).size() == 1 and actions.has((step as Dictionary).get("action", "")):
			return i
		return -1
	return -1


static func _cells_touch(cells: Array, row: int, col: int) -> bool:
	for cell: Variant in cells:
		if (
			cell is Dictionary
			and int((cell as Dictionary).get("r", -1)) == row
			and int((cell as Dictionary).get("c", -1)) == col
		):
			return true
	return false


static func _step_chars(step: Dictionary) -> int:
	return JSON.stringify(step).length() + 1


static func _steps_chars(steps: Array) -> int:
	var chars: int = 0
	for step in steps:
		if step is Dictionary:
			chars += _step_chars(step)
	return chars
