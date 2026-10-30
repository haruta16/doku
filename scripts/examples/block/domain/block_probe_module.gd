## 跨玩法契约验证：固定方块队列的拖放消行。无 Doku 类型，也不要求通用棋盘父类。
## 固定队列让恢复和复用验证可重现；独立交互入口在 scripts/examples/block/。
class_name BlockProbeModule
extends RefCounted


func create_snapshot(context: Dictionary) -> Dictionary:
	var size_value: Variant = context.get("size", 4)
	if typeof(size_value) != TYPE_INT or size_value < 1 or size_value > 12:
		return _failure("invalid_block_size")
	var size: int = size_value
	var board: Array = []
	if context.has("board"):
		if not context.board is Array:
			return _failure("invalid_block_board")
		board = context.board.duplicate(true)
	else:
		for row in range(size):
			var line: Array = []
			line.resize(size)
			line.fill(0)
			board.append(line)
	if not context.get("pieces", []) is Array or not context.get("reward", {}) is Dictionary:
		return _failure("invalid_block_context")
	var snapshot: Dictionary = {
		"schema": 1, "size": size, "occupied": board,
		"pieces": context.get("pieces", []).duplicate(true), "piece_index": 0,
		"score": 0, "finished": false, "reward": context.get("reward", {}).duplicate(true),
	}
	var invalid: String = _validate_snapshot_fields(snapshot)
	if not invalid.is_empty():
		return _failure("invalid_block_context", invalid)
	snapshot["finished"] = _is_finished(snapshot)
	return {"ok": true, "snapshot": snapshot}


func validate_snapshot(snapshot: Dictionary) -> String:
	var invalid: String = _validate_snapshot_fields(snapshot)
	if not invalid.is_empty():
		return invalid
	if snapshot.finished != _is_finished(snapshot):
		return "terminal state does not match the board and piece queue"
	return ""


func _validate_snapshot_fields(snapshot: Dictionary) -> String:
	if typeof(snapshot.get("schema")) != TYPE_INT or snapshot.schema != 1 or typeof(snapshot.get("size")) != TYPE_INT:
		return "invalid block schema or size"
	var size: int = snapshot.size
	if size < 1 or size > 12 or not snapshot.get("occupied") is Array or snapshot.occupied.size() != size:
		return "invalid block dimensions"
	for row: Variant in snapshot.occupied:
		if not row is Array or row.size() != size:
			return "invalid block row"
		for cell: Variant in row:
			if typeof(cell) != TYPE_INT or cell not in [0, 1]:
				return "invalid occupied cell"
	if not snapshot.get("pieces") is Array or snapshot.pieces.is_empty():
		return "missing block pieces"
	for shape: Variant in snapshot.pieces:
		if not shape is Array or shape.is_empty():
			return "empty shape"
		var seen: Dictionary = {}
		for offset: Variant in shape:
			if not offset is Array or offset.size() != 2:
				return "invalid shape coordinate"
			if typeof(offset[0]) != TYPE_INT or typeof(offset[1]) != TYPE_INT:
				return "shape coordinates must be integers"
			if offset[0] < 0 or offset[1] < 0 or offset[0] >= size or offset[1] >= size:
				return "shape coordinate out of bounds"
			var key: String = "%d,%d" % [offset[0], offset[1]]
			if seen.has(key):
				return "duplicate shape coordinate"
			seen[key] = true
	if typeof(snapshot.get("piece_index")) != TYPE_INT or snapshot.piece_index < 0 or snapshot.piece_index > snapshot.pieces.size():
		return "invalid piece index"
	if typeof(snapshot.get("score")) != TYPE_INT or snapshot.score < 0 or typeof(snapshot.get("finished")) != TYPE_BOOL:
		return "invalid score or terminal state"
	if not snapshot.get("reward") is Dictionary:
		return "invalid reward"
	for item: Variant in snapshot.reward:
		if typeof(item) != TYPE_STRING or typeof(snapshot.reward[item]) != TYPE_INT or snapshot.reward[item] < 0:
			return "invalid reward item"
	return ""


func sync_runtime(_snapshot: Dictionary, _runtime: Dictionary) -> Dictionary:
	return _failure("block_runtime_override_unsupported")


## 只读预览与实际放置共用 _fits；页面不复制越界/碰撞规则。
func preview_placement(snapshot: Dictionary, row: int, col: int) -> Dictionary:
	if not validate_snapshot(snapshot).is_empty() or snapshot.finished:
		return {"valid": false, "cells": []}
	var shape: Array = snapshot.pieces[snapshot.piece_index]
	var cells: Array = []
	for offset: Array in shape:
		cells.append([row + int(offset[0]), col + int(offset[1])])
	return {"valid": _fits(snapshot.occupied, shape, row, col), "cells": cells}


func apply_action(snapshot: Dictionary, kind: String, payload: Dictionary, _call_context: Dictionary) -> Dictionary:
	if kind != "place":
		return _failure("unknown_action")
	if _is_finished(snapshot):
		return _failure("round_not_playable")
	if typeof(payload.get("row")) != TYPE_INT or typeof(payload.get("col")) != TYPE_INT:
		return _failure("invalid_placement")
	var row: int = payload.row
	var col: int = payload.col
	var shape: Array = snapshot.pieces[snapshot.piece_index]
	if not _fits(snapshot.occupied, shape, row, col):
		return _failure("invalid_placement")
	var next: Dictionary = snapshot.duplicate(true)
	var placed: Array = []
	for offset: Array in shape:
		var r: int = row + int(offset[0])
		var c: int = col + int(offset[1])
		next.occupied[r][c] = 1
		placed.append([r, c])
	var rows: Array = []
	var cols: Array = []
	for index in range(int(next.size)):
		var row_full: bool = true
		var col_full: bool = true
		for other in range(int(next.size)):
			row_full = row_full and next.occupied[index][other] == 1
			col_full = col_full and next.occupied[other][index] == 1
		if row_full:
			rows.append(index)
		if col_full:
			cols.append(index)
	for full_row: int in rows:
		for column in range(int(next.size)):
			next.occupied[full_row][column] = 0
	for full_col: int in cols:
		for line in range(int(next.size)):
			next.occupied[line][full_col] = 0
	next["piece_index"] = int(next.piece_index) + 1
	next["score"] = int(next.score) + placed.size() + (rows.size() + cols.size()) * 10
	next["finished"] = _is_finished(next)
	var changes: Array = [{"kind": "place", "cells": placed}]
	if not rows.is_empty() or not cols.is_empty():
		changes.append({"kind": "clear_lines", "rows": rows, "cols": cols})
	return {
		"ok": true, "snapshot": next, "changes": changes, "inventory_delta": {},
		"result": {"score": next.score, "finished": next.finished, "cleared_rows": rows, "cleared_cols": cols},
	}


func settle_snapshot(snapshot: Dictionary, _payload: Dictionary) -> Dictionary:
	if not _is_finished(snapshot):
		return _failure("round_not_finished")
	return {
		"ok": true, "snapshot": snapshot.duplicate(true), "changes": [],
		"inventory_delta": snapshot.reward.duplicate(true),
		"result": {"outcome": "finished", "score": snapshot.score},
	}


static func _is_finished(snapshot: Dictionary) -> bool:
	if int(snapshot.piece_index) >= snapshot.pieces.size():
		return true
	var shape: Array = snapshot.pieces[snapshot.piece_index]
	for row in range(int(snapshot.size)):
		for col in range(int(snapshot.size)):
			if _fits(snapshot.occupied, shape, row, col):
				return false
	return true


static func _fits(board: Array, shape: Array, row: int, col: int) -> bool:
	for offset: Array in shape:
		var r: int = row + int(offset[0])
		var c: int = col + int(offset[1])
		if r < 0 or c < 0 or r >= board.size() or c >= board.size() or board[r][c] != 0:
			return false
	return true


static func _failure(error: String, detail: String = "") -> Dictionary:
	return {"ok": false, "error": error, "detail": detail}
