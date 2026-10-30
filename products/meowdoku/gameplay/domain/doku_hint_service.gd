## 无界面的 Doku 提示选择与应用。复用现有 HintEngine，保留旧页面的降级顺序。
class_name DokuHintService
extends RefCounted

const BoardState = preload("res://products/meowdoku/gameplay/domain/doku_board_state.gd")
const EngineRules = preload("res://products/meowdoku/gameplay/domain/hint_engine.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")


static func find_hint(raw_board: Array, regions: Array, solution: Array) -> Dictionary:
	var model: BoardState = BoardState.new()
	if not model.restore_board(raw_board):
		return {"found": false}
	var size: int = raw_board.size()
	var board: Array = model.get_folded_board()
	var hint: Dictionary = EngineRules.find_mark_hint(board, size, regions)
	if not hint.get("found", false):
		for row in range(size):
			for col in range(size):
				if bool(solution[row][col]) and raw_board[row][col] == States.MARK:
					hint = {
						"found": true, "strategy": "", "cell": Vector2i(row, col),
						"unit_cells": [Vector2i(row, col)], "wrong_mark": true,
						"description_key": "HINT_WRONG_MARK",
					}
					break
			if hint.get("found", false):
				break
	if not hint.get("found", false):
		hint = EngineRules.find_r1_hint(board, size, regions)
	if not hint.get("found", false):
		hint = EngineRules.find_r2_hint(board, size, regions)
	if not hint.get("found", false):
		hint = EngineRules.find_r3_r4_hint(board, size, regions)
	if not hint.get("found", false):
		hint = EngineRules.find_chain_hint(board, size, regions)
	if not hint.get("found", false):
		return {"found": false}
	var strategy: String = str(hint.get("strategy", "R1"))
	hint["strategy"] = strategy
	var cell: Vector2i = hint.get("cell", Vector2i(-1, -1))
	if cell.x >= 0 and strategy not in ["R1_mark", "R2", "R3", "R4"]:
		if raw_board[cell.x][cell.y] in [States.MARK, States.DRAFT_CROSS]:
			hint["wrong_mark"] = true
			hint["description_key"] = "HINT_WRONG_MARK"
	return hint


## hint 必须来自本服务生成并保存的凭证，不能使用页面修改后的提示或玩家任意传入的坐标。
static func apply_hint(raw_board: Array, regions: Array, hint: Dictionary) -> Dictionary:
	var model: BoardState = BoardState.new()
	if not model.restore_board(raw_board):
		return {"ok": false, "error": "invalid_board"}
	var size: int = raw_board.size()
	var strategy: String = str(hint.get("strategy", "R1"))
	var changes: Array = []
	if strategy == "R1_mark":
		for position: Vector2i in hint.get("unit_cells", []):
			if model.contains(position.x, position.y) and States.is_blank(model.get_cell_state(position.x, position.y)):
				_add_change(model, changes, position.x, position.y, States.MARK, States.EMPTY)
	elif strategy == "R2":
		var work: Array = model.get_folded_board()
		EngineRules._apply_r2_marks(work, hint, size, regions)
		for row in range(size):
			for col in range(size):
				if work[row][col] == States.MARK and States.is_blank(model.get_cell_state(row, col)):
					_add_change(model, changes, row, col, States.MARK, States.EMPTY)
	elif strategy in ["R3", "R4"]:
		# 保留旧页面的先行后列顺序：同一份顺序还用于撤销回看演出。
		var included_regions: Array = hint.get("regions", [])
		for row: int in hint.get("locked_rows", []):
			for col in range(size):
				if regions[row][col] not in included_regions and States.is_blank(model.get_cell_state(row, col)):
					_add_change(model, changes, row, col, States.MARK, States.EMPTY)
		for col: int in hint.get("locked_cols", []):
			for row in range(size):
				if regions[row][col] not in included_regions and States.is_blank(model.get_cell_state(row, col)):
					_add_change(model, changes, row, col, States.MARK, States.EMPTY)
	else:
		var position: Vector2i = hint.get("cell", Vector2i(-1, -1))
		if not model.contains(position.x, position.y):
			return {"ok": false, "error": "invalid_hint_cell"}
		var target: int
		if strategy in ["R4_chain", "R5_chain"]:
			target = States.MARK
		elif hint.get("wrong_mark", false):
			target = States.EMPTY
		else:
			target = States.CAT
		var history_before: int = States.EMPTY if strategy in ["R4_chain", "R5_chain"] else (States.MARK if hint.get("wrong_mark", false) else -1)
		_add_change(model, changes, position.x, position.y, target, history_before)
	return {
		"ok": true, "board": model.get_board(), "changes": changes,
		"is_cat_step": strategy in ["", "R1"] and not hint.get("wrong_mark", false),
	}


static func _add_change(model: BoardState, changes: Array, row: int, col: int, target: int, history_before: int = -1) -> void:
	var before: int = model.get_cell_state(row, col)
	if before in [States.CAT, States.LOCKED_MARK] or before == target:
		return
	if model.set_cell_state(row, col, target):
		changes.append({
			"row": row, "col": col, "before": before, "after": target,
			"history_before": before if history_before < 0 else history_before,
		})
