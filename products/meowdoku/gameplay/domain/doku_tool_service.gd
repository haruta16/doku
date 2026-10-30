## 定位与撤销的数据规则。输入/输出都是副本，不依赖按钮、节点或存档。
class_name DokuToolService
extends RefCounted

const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")
const Board = preload("res://products/meowdoku/gameplay/domain/doku_board_state.gd")


static func locate(board: Array, regions: Array, solution: Array) -> Dictionary:
	var remaining: Dictionary = {}
	for row in board.size():
		for col in board.size():
			if board[row][col] not in [States.MARK, States.ERROR]:
				var region: int = regions[row][col]
				remaining[region] = int(remaining.get(region, 0)) + 1
	var best := Vector2i(-1, -1)
	var smallest: int = 2147483647
	for row in board.size():
		for col in board.size():
			if not bool(solution[row][col]) or board[row][col] in [States.CAT, States.LOCKED_MARK]:
				continue
			var count: int = remaining.get(regions[row][col], board.size() * board.size())
			if count < smallest:
				smallest = count
				best = Vector2i(row, col)
	if best.x < 0:
		return {"ok": false, "error": "no_locate_target"}
	var next: Array = board.duplicate(true)
	next[best.x][best.y] = States.CAT
	return {"ok": true, "board": next, "changes": [{"row": best.x, "col": best.y, "before": board[best.x][best.y], "after": States.CAT}], "is_cat_step": true}


static func undo(board: Array, history: Array, mode: String, cursor: int) -> Dictionary:
	var invalid: String = validate_history(history, board.size())
	if not invalid.is_empty():
		return {"ok": false, "error": invalid}
	if mode == "highlight":
		return _highlight(history, cursor)
	if mode != "revert":
		return {"ok": false, "error": "invalid_undo_mode"}
	var model: RefCounted = Board.new()
	model.restore_board(board)
	for index in range(history.size() - 1, -1, -1):
		var step: Dictionary = history[index]
		if bool(step.get("wrong", false)):
			continue
		var changes: Array = []
		var has_revertible: bool = false
		for cell: Array in step.cells:
			var row: int = cell[0]
			var col: int = cell[1]
			var current: int = model.get_cell_state(row, col)
			if current in [States.CAT, States.ERROR, States.LOCKED_MARK]:
				continue
			has_revertible = true
			if model.set_cell_state(row, col, int(cell[2])):
				changes.append({"row": row, "col": col, "before": current, "after": int(cell[2])})
		# 原版选中可撤销步骤后即消费并移除历史，不要求格值一定发生变化。
		if has_revertible:
			return {"ok": true, "board": model.get_board(), "changes": changes, "history": history.slice(0, index).duplicate(true), "highlight_cursor": -1}
	return {"ok": false, "error": "no_undo_step"}


static func _highlight(history: Array, cursor: int) -> Dictionary:
	if cursor == -2 or history.is_empty():
		return {"ok": false, "error": "no_undo_step"}
	var next: int = history.size() - 1 if cursor == -1 else cursor - 1
	if next < 0 or next >= history.size():
		return {"ok": false, "error": "no_undo_step"}
	var step: Dictionary = history[next]
	var cells: Array = step.cells.duplicate(true)
	if bool(step.get("cat", false)) or bool(step.get("wrong", false)):
		var has_non_cat: bool = cells.any(func(cell: Array) -> bool: return int(cell[3]) != States.CAT)
		if not has_non_cat:
			var found: bool = false
			for index in range(next - 1, -1, -1):
				var previous: Dictionary = history[index]
				cells.append_array(previous.cells.duplicate(true))
				if not previous.get("cat", false) and not previous.get("wrong", false):
					next = index
					found = true
					break
			if not found:
				return {"ok": false, "error": "no_undo_step"}
	return {"ok": true, "changes": [], "history": history.duplicate(true), "highlight_cursor": next, "highlight_cells": cells}


static func validate_history(history: Array, size: int) -> String:
	for step: Variant in history:
		if not step is Dictionary or not step.get("cells") is Array:
			return "invalid_history"
		for cell: Variant in step.cells:
			if not cell is Array or cell.size() != 4:
				return "invalid_history"
			for value: Variant in cell:
				if typeof(value) != TYPE_INT:
					return "invalid_history"
			if cell[0] < 0 or cell[0] >= size or cell[1] < 0 or cell[1] >= size or cell[2] < 0 or cell[2] > States.LOCKED_MARK or cell[3] < 0 or cell[3] > States.LOCKED_MARK:
				return "invalid_history"
	return ""
