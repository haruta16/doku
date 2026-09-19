# 步骤历史：一次操作（可能跨多格）记成一条 StepRecord，供撤销回退与撤销高亮
class_name StepHistory
extends RefCounted


# 单条记录：本次改动的格子 + 两个标记位
class StepRecord:
	var cells: Array[Dictionary] = [] # 每项 {pos: Vector2i, before: int, after: int}

	var is_cat_placement: bool = false # 本次是否落了猫

	var is_wrong_guess: bool = false # 本次是否猜错


# ---- 内部栈（尾部是最新一步） ----
var _history: Array[StepRecord] = [] # 记录栈，back() 是最新一步


# ================= 栈操作 =================
# 压入一步；空步骤不入栈
func push_step(step: StepRecord) -> void:
	if step.cells.is_empty():
		return
	_history.append(step)


# 弹出最新一步；没有则返回 null
func pop_last() -> StepRecord:
	if _history.is_empty():
		return null
	return _history.pop_back()


# 看最新一步但不弹出
func peek_last() -> StepRecord:
	if _history.is_empty():
		return null
	return _history.back()


# 按索引查看某一步
func peek_at(index: int) -> StepRecord:
	if index < 0 or index >= _history.size():
		return null
	return _history[index]


# 是否还有步骤（撤销按钮的可用性判断）
func has_step() -> bool:
	return not _history.is_empty()


# 清空历史
func clear() -> void:
	_history.clear()


# 当前步数
func size() -> int:
	return _history.size()


# ================= 序列化 =================
# 序列化成一维数组，用于存档
func serialize() -> Array:
	var result: Array = []
	for step: StepRecord in _history:
		var cells_arr: Array = []
		# 每格压成 [row, col, before, after] 四元组
		for entry: Dictionary in step.cells:
			cells_arr.append([entry["pos"].x, entry["pos"].y, entry["before"], entry["after"]])
		# 一条记录 = {cells, cat, wrong}
		result.append(
			{"cells": cells_arr, "cat": step.is_cat_placement, "wrong": step.is_wrong_guess}
		)
	return result


# 从序列化数据恢复（读档）；没有格子的记录会被丢弃
func deserialize(data: Array) -> void:
	_history.clear()
	for item in data:
		# 新建一条记录
		var step := StepRecord.new()
		step.is_cat_placement = item.get("cat", false)
		step.is_wrong_guess = item.get("wrong", false)
		for cell_arr in item.get("cells", []):
			# 还原每格的四元组
			step.cells.append(
				{
					"pos": Vector2i(int(cell_arr[0]), int(cell_arr[1])),
					"before": int(cell_arr[2]),
					"after": int(cell_arr[3])
				}
			)
		# 空记录不入栈
		if not step.cells.is_empty():
			_history.append(step)
