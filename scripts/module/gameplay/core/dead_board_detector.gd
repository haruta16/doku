## 明显死局检测：识别整行整列全叉，以及高叉占比下不同区域唯一空位的同行同列冲突。
class_name DeadBoardDetector
extends RefCounted

const CROSS_RATIO_THRESHOLD: float = 0.7


## 合并两种局面检查；这是可见死局的判据，并非完整求解器。
static func is_visibly_dead(board: Array, size: int, regions: Array) -> bool:
	return has_fully_crossed_line(board, size) or has_conflicting_last_cells(board, size, regions)


## 发现任意整行或整列都是叉类状态时立即判定为死局。
static func has_fully_crossed_line(board: Array, size: int) -> bool:
	for line in range(size):
		var row_all_cross: bool = true
		var col_all_cross: bool = true
		for i in range(size):
			if not CellState.is_cross(_state_at(board, line, i)):
				row_all_cross = false
			if not CellState.is_cross(_state_at(board, i, line)):
				col_all_cross = false
		if row_all_cross or col_all_cross:
			return true
	return false


## 叉占比超过 70% 后，查未放猫区域的唯一空位是否同行或同列。
static func has_conflicting_last_cells(board: Array, size: int, regions: Array) -> bool:
	if size <= 0:
		return false
	var cross_count: int = 0

	var region_stats: Dictionary = {}
	for r in range(size):
		for c in range(size):
			var state: int = _state_at(board, r, c)
			var region_id: int = int((regions[r] as Array)[c])
			if not region_stats.has(region_id):
				region_stats[region_id] = [0, false, Vector2i(-1, -1)]
			var stat: Array = region_stats[region_id]
			if CellState.is_cross(state):
				cross_count += 1
			elif state == CellState.CAT:
				stat[1] = true
			elif CellState.is_blank(state):
				stat[0] = int(stat[0]) + 1
				stat[2] = Vector2i(r, c)
	if float(cross_count) / float(size * size) <= CROSS_RATIO_THRESHOLD:
		return false
	var last_cells: Array[Vector2i] = []
	var stats_list: Array = region_stats.values()
	for stat: Array in stats_list:
		if not bool(stat[1]) and int(stat[0]) == 1:
			last_cells.append(stat[2])
	for i in range(last_cells.size()):
		for j in range(i + 1, last_cells.size()):
			if last_cells[i].x == last_cells[j].x or last_cells[i].y == last_cells[j].y:
				return true
	return false


## 把棋盘单元转为整数状态，统一后续 CellState 判断的输入。
static func _state_at(board: Array, r: int, c: int) -> int:
	return int((board[r] as Array)[c])
