## 单局全标记反馈去重：记住已触发的行列区域，并保证整盘全标记奖励只消费一次。
class_name FullMarkTracker
extends RefCounted

var _fired_units: Dictionary = {}

var _full_mark_consumed: bool = false


## 清空已触发单元和全标记消费状态，开始新一局时调用。
func reset() -> void:
	_fired_units.clear()
	_full_mark_consumed = false


## 调用检测器找完成单元，仅返回首次出现的单元，并立即把它们记为已触发。
func collect_new_units(
	board: Array, size: int, regions: Array, solution: Array
) -> Array[Dictionary]:
	var fresh: Array[Dictionary] = []
	var all_units: Array[Dictionary] = FullMarkDetector.completed_units(
		board, size, regions, solution
	)
	for unit: Dictionary in all_units:
		var unit_key: String = _unit_key(int(unit["kind"]), int(unit["index"]))
		if _fired_units.has(unit_key):
			continue
		_fired_units[unit_key] = true
		fresh.append(unit)
	return fresh


## 把当前已完成单元记入去重表，避免恢复棋盘时重播旧反馈。
func prime_fired_units(board: Array, size: int, regions: Array, solution: Array) -> int:
	var primed: int = 0
	var all_units: Array[Dictionary] = FullMarkDetector.completed_units(
		board, size, regions, solution
	)
	for unit: Dictionary in all_units:
		var unit_key: String = _unit_key(int(unit["kind"]), int(unit["index"]))
		if _fired_units.has(unit_key):
			continue
		_fired_units[unit_key] = true
		primed += 1
	return primed


## 首次满足全标记条件时消费资格，返回待补叉格子和最大区域；本函数不直接改棋盘。
func consume_full_mark(board: Array, size: int, regions: Array) -> Dictionary:
	var miss: Dictionary = {
		"hit": false,
		"cells_to_cross": [] as Array[Vector2i],
		"dominant_region": -1,
	}
	if _full_mark_consumed:
		return miss
	if not FullMarkDetector.is_full_mark(board, size):
		return miss
	_full_mark_consumed = true
	return {
		"hit": true,
		"cells_to_cross": FullMarkDetector.unmarked_cells(board, size),
		"dominant_region": FullMarkDetector.dominant_region(size, regions),
	}


## 查询本局整盘全标记资格是否已经消费。
func is_full_mark_consumed() -> bool:
	return _full_mark_consumed


## 返回本局已记录的完成单元数量。
func fired_unit_count() -> int:
	return _fired_units.size()


## 用单元种类与索引组成去重键，避免行、列和区域编号互相冲突。
static func _unit_key(kind: int, index: int) -> String:
	return "%d:%d" % [kind, index]
