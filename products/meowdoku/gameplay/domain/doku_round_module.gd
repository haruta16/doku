## Doku 对局模块：数据快照、基本棋盘动作、按次收费的提示凭证与结算判断。
## 不处理演出或产品层 DDA；旧页面过渡期间通过 sync_runtime 捕获唯一活模型。
class_name DokuRoundModule
extends RefCounted

const Actions = preload("res://products/meowdoku/gameplay/domain/doku_action_rules.gd")
const BoardState = preload("res://products/meowdoku/gameplay/domain/doku_board_state.gd")
const ToolService = preload("res://products/meowdoku/gameplay/domain/doku_tool_service.gd")
const HintService = preload("res://products/meowdoku/gameplay/domain/doku_hint_service.gd")
const Rules = preload("res://products/meowdoku/gameplay/domain/queendoku_core.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")


func create_snapshot(context: Dictionary) -> Dictionary:
	for field: String in ["board", "regions", "solution", "history"]:
		if not context.get(field, []) is Array:
			return _failure("invalid_context", "invalid " + field)
	for field: String in ["reward", "content"]:
		if not context.get(field, {}) is Dictionary:
			return _failure("invalid_context", "invalid " + field)
	var snapshot: Dictionary = {
		"schema": 1, "board": context.get("board", []).duplicate(true),
		"regions": context.get("regions", []).duplicate(true),
		"solution": context.get("solution", []).duplicate(true),
		"lives": context.get("lives", 3), "life_plus_used": context.get("life_plus_used", false), "board_revision": 0,
		"hint_cost": context.get("hint_cost", 1), "hint_item": context.get("hint_item", "hint"),
		"reward": context.get("reward", {}).duplicate(true),
		"content": context.get("content", {}).duplicate(true), "pending_hint": {},
		"history": context.get("history", []).duplicate(true), "highlight_cursor": -1,
		"attempt_sequence": context.get("attempt_sequence", 0),
	}
	var error: String = validate_snapshot(snapshot)
	return {"ok": true, "snapshot": snapshot} if error.is_empty() else _failure("invalid_context", error)


func validate_snapshot(snapshot: Dictionary) -> String:
	if typeof(snapshot.get("schema")) != TYPE_INT or snapshot.schema != 1:
		return "unsupported doku snapshot schema"
	for field: String in ["board", "regions", "solution"]:
		if not snapshot.get(field) is Array:
			return "doku snapshot requires " + field
	var board: Array = snapshot.board
	var size: int = board.size()
	if size < 1 or size > 32:
		return "invalid doku board size"
	var model: BoardState = BoardState.new()
	if not model.restore_board(board):
		return "invalid doku cell values"
	var regions: Array = snapshot.regions
	var solution: Array = snapshot.solution
	if regions.size() != size or solution.size() != size:
		return "puzzle dimensions do not match board"
	var solution_board: Array = []
	for row in range(size):
		if not regions[row] is Array or not solution[row] is Array:
			return "puzzle row is not an array"
		if regions[row].size() != size or solution[row].size() != size:
			return "puzzle is not square"
		var solution_row: Array = []
		for col in range(size):
			var region: Variant = regions[row][col]
			if typeof(region) != TYPE_INT or region < 0 or region >= size:
				return "invalid region id"
			var answer: Variant = solution[row][col]
			if typeof(answer) != TYPE_BOOL and not (typeof(answer) == TYPE_INT and answer in [0, 1]):
				return "invalid solution cell"
			solution_row.append(States.CAT if bool(answer) else States.EMPTY)
		solution_board.append(solution_row)
	if not Rules.is_complete(solution_board, size, regions):
		return "solution violates doku rules"
	if typeof(snapshot.get("life_plus_used", false)) != TYPE_BOOL:
		return "invalid life plus state"
	if typeof(snapshot.get("lives")) != TYPE_INT or snapshot.lives < 0 or snapshot.lives > 3:
		return "invalid lives"
	if typeof(snapshot.get("board_revision")) != TYPE_INT or snapshot.board_revision < 0:
		return "invalid board revision"
	if typeof(snapshot.get("hint_cost")) != TYPE_INT or snapshot.hint_cost not in [0, 1]:
		return "invalid hint cost"
	if typeof(snapshot.get("hint_item")) != TYPE_STRING or snapshot.hint_item.is_empty():
		return "invalid hint item"
	for field: String in ["reward", "content", "pending_hint"]:
		if not snapshot.get(field) is Dictionary:
			return "invalid " + field
	for item: Variant in snapshot.reward:
		if typeof(item) != TYPE_STRING or typeof(snapshot.reward[item]) != TYPE_INT or snapshot.reward[item] < 0:
			return "invalid reward"
	if not snapshot.get("history", []) is Array or not ToolService.validate_history(snapshot.get("history", []), size).is_empty():
		return "invalid history"
	if typeof(snapshot.get("highlight_cursor", -1)) != TYPE_INT:
		return "invalid highlight cursor"
	if typeof(snapshot.get("attempt_sequence", 0)) != TYPE_INT or int(snapshot.get("attempt_sequence", 0)) < 0:
		return "invalid attempt sequence"
	var pending: Dictionary = snapshot.pending_hint
	if not pending.is_empty():
		if typeof(pending.get("token")) != TYPE_STRING or not pending.get("hint") is Dictionary:
			return "invalid hint receipt"
		if typeof(pending.get("board_revision")) != TYPE_INT or typeof(pending.get("applied")) != TYPE_BOOL:
			return "invalid hint receipt state"
	return ""


func sync_runtime(snapshot: Dictionary, runtime: Dictionary) -> Dictionary:
	var next: Dictionary = snapshot.duplicate(true)
	if runtime.has("board"):
		if not runtime.board is Array or runtime.board.size() != snapshot.board.size():
			return _failure("invalid_runtime_board")
		if runtime.board != snapshot.board:
			next["board"] = runtime.board.duplicate(true)
			next["board_revision"] = int(snapshot.board_revision) + 1
	if runtime.has("history"):
		if not runtime.history is Array:
			return _failure("invalid_history")
		next["history"] = runtime.history.duplicate(true)
	if runtime.has("highlight_cursor"):
		next["highlight_cursor"] = runtime.highlight_cursor
	if runtime.has("lives"):
		next["lives"] = runtime.lives
	if runtime.has("life_plus_used"):
		next["life_plus_used"] = runtime.life_plus_used
	var error: String = validate_snapshot(next)
	return {"ok": true, "snapshot": next} if error.is_empty() else _failure("invalid_runtime", error)


func apply_action(snapshot: Dictionary, kind: String, payload: Dictionary, call_context: Dictionary) -> Dictionary:
	var next: Dictionary = snapshot.duplicate(true)
	if kind == "revive":
		return _revive(next, call_context)
	if kind == "life_plus":
		return _life_plus(next, payload, call_context.get("policy", {}))
	if kind == "sync":
		return _success(next)
	if kind == "request_hint":
		return _request_hint(next, call_context)
	if kind in ["locate", "undo"]:
		return _use_tool(next, kind, call_context)
	if kind == "apply_hint":
		return _apply_hint(next, str(payload.get("hint_token", "")))
	if kind in ["set_mark", "place_cat"]:
		return _apply_basic_move(next, kind, payload)
	if kind in ["draft_mark", "draft_commit", "draft_clear", "auto_complete", "axis_mark", "auto_mark", "lock_marks"]:
		return _apply_planned_action(next, kind, payload, call_context.get("policy", {}))
	return _failure("unknown_action")


func _request_hint(next: Dictionary, call_context: Dictionary) -> Dictionary:
	if int(next.lives) <= 0 or _complete(next):
		return _failure("round_not_playable")
	# 原版按每次成功打开提示收费；新请求替换旧凭证，同一请求重试由宿主去重。
	var hint: Dictionary = HintService.find_hint(next.board, next.regions, next.solution)
	if not hint.get("found", false):
		return _failure("no_hint")
	var policy: Dictionary = call_context.get("policy", {})
	var cost_value: Variant = policy.get("hint_cost", next.hint_cost)
	if typeof(cost_value) != TYPE_INT or cost_value not in [0, 1]:
		return _failure("invalid_hint_price")
	var cost: int = cost_value
	var token: String = "%s/hint#%d" % [call_context.get("round_id", ""), int(call_context.get("sequence", 0))]
	next["pending_hint"] = {
		"token": token, "hint": hint.duplicate(true), "board_revision": next.board_revision,
		"cost": cost, "applied": false,
	}
	var result: Dictionary = _success(next, [], {
		"hint": hint, "hint_token": token, "board_revision": next.board_revision, "cost": cost,
	})
	result["inventory_delta"] = {str(next.hint_item): -cost}
	return result


func _apply_hint(next: Dictionary, token: String) -> Dictionary:
	var pending: Dictionary = next.pending_hint
	if token.is_empty() or pending.get("token", "") != token:
		return _failure("unknown_hint")
	if pending.get("applied", false):
		return _success(next, [], {"applied": true, "already_applied": true, "complete": _complete(next)})
	if pending.get("board_revision") != next.board_revision:
		return _failure("stale_hint")
	if int(next.lives) <= 0:
		return _failure("round_not_playable")
	var applied: Dictionary = HintService.apply_hint(next.board, next.regions, pending.hint)
	if not applied.get("ok", false):
		return applied
	next["board"] = applied.board
	if not applied.changes.is_empty():
		next["board_revision"] = int(next.board_revision) + 1
	_append_history(next, applied.changes, bool(applied.is_cat_step))
	pending["applied"] = true
	next["pending_hint"] = pending
	return _success(next, applied.changes, {
		"hint": pending.hint.duplicate(true), "applied": true,
		"is_cat_step": applied.is_cat_step, "complete": _complete(next),
	})


## 普通无界面动作复用输入和页面的纯规则；同一次提交带上历史和生命。
func _apply_basic_move(next: Dictionary, kind: String, payload: Dictionary) -> Dictionary:
	if int(next.lives) <= 0 or _complete(next):
		return _failure("round_not_playable")
	if typeof(payload.get("row")) != TYPE_INT or typeof(payload.get("col")) != TYPE_INT:
		return _failure("invalid_cell")
	var row: int = payload.row
	var col: int = payload.col
	var model: BoardState = BoardState.new()
	model.restore_board(next.board)
	if not model.contains(row, col):
		return _failure("invalid_cell")
	var before: int = model.get_cell_state(row, col)
	if before in [States.CAT, States.ERROR, States.LOCKED_MARK]:
		return _failure("cell_not_editable")
	var target: int
	if kind == "set_mark":
		if typeof(payload.get("marked")) != TYPE_BOOL:
			return _failure("invalid_mark")
		target = States.MARK if payload.marked else States.EMPTY
	else:
		var decision: Dictionary = Actions.guess(next.board, next.solution, row, col, int(next.lives))
		if not decision.get("ok", false):
			return decision
		target = int(decision.final_state)
		next["lives"] = int(decision.lives)
	var changes: Array = []
	if model.set_cell_state(row, col, target):
		changes.append({"row": row, "col": col, "before": before, "after": target})
		next["board_revision"] = int(next.board_revision) + 1
	next["board"] = model.get_board()
	_append_history(next, changes, target == States.CAT, target == States.ERROR)
	return _success(next, changes, {"complete": _complete(next), "lives": next.lives})


func settle_snapshot(snapshot: Dictionary, _payload: Dictionary) -> Dictionary:
	var won: bool = _complete(snapshot)
	if not won and int(snapshot.lives) > 0:
		return _failure("round_not_finished")
	var result: Dictionary = _success(snapshot.duplicate(true), [], {"outcome": "won" if won else "failed"})
	result["inventory_delta"] = snapshot.reward.duplicate(true) if won else {}
	return result


static func _complete(snapshot: Dictionary) -> bool:
	return Rules.is_complete(snapshot.board, snapshot.board.size(), snapshot.regions)


static func _success(snapshot: Dictionary, changes: Array = [], result: Dictionary = {}) -> Dictionary:
	return {"ok": true, "snapshot": snapshot, "changes": changes, "result": result, "inventory_delta": {}}


static func _failure(error: String, detail: String = "") -> Dictionary:
	return {"ok": false, "error": error, "detail": detail}


func _use_tool(next: Dictionary, kind: String, call_context: Dictionary) -> Dictionary:
	# 定位按次使用收费；活动局即使已无候选也受理，终局/离页由宿主和页面拒绝。
	if int(next.lives) <= 0 or (kind != "locate" and _complete(next)):
		return _failure("round_not_playable")
	var policy: Dictionary = call_context.get("policy", {})
	var price: Variant = policy.get(kind + "_cost", 1)
	if typeof(price) != TYPE_INT or price not in [0, 1]:
		return _failure("invalid_tool_price")
	var planned: Dictionary
	if kind == "locate":
		planned = ToolService.locate(next.board, next.regions, next.solution)
	else:
		planned = ToolService.undo(next.board, next.get("history", []), str(policy.get("undo_mode", "revert")), int(next.get("highlight_cursor", -1)))
	if not planned.get("ok", false):
		if kind != "locate" or planned.get("error") != "no_locate_target":
			return planned
		# 空定位也是一次有效使用，和扣费一起提交；不能把存储失败伪装成这种结果。
		planned = {"ok": true, "changes": [], "no_effect": "no_locate_target"}
	if planned.has("board"):
		next["board"] = planned.board
	if not planned.changes.is_empty():
		next["board_revision"] = int(next.board_revision) + 1
	if kind == "locate":
		_append_history(next, planned.changes, true)
	if planned.has("history"):
		next["history"] = planned.history
	if planned.has("highlight_cursor"):
		next["highlight_cursor"] = planned.highlight_cursor
	var receipt: Dictionary = planned.duplicate(true)
	receipt.erase("board")
	receipt.erase("changes")
	receipt["cost"] = int(price)
	receipt["complete"] = _complete(next)
	var response: Dictionary = _success(next, planned.changes, receipt)
	response["inventory_delta"] = {kind: -int(price)}
	return response


func _revive(next: Dictionary, call_context: Dictionary) -> Dictionary:
	if int(next.lives) > 0:
		return _failure("round_not_failed")
	var policy: Dictionary = call_context.get("policy", {})
	var consume_once: Variant = policy.get("consume_free_once", false)
	if typeof(consume_once) != TYPE_BOOL:
		return _failure("invalid_revive_policy")
	var amount: Variant = policy.get("revive_lives", 0)
	if typeof(amount) != TYPE_INT or amount < 1 or amount > 3:
		return _failure("invalid_revive_lives")
	var previous: int = int(next.get("attempt_sequence", 0))
	if previous >= 9223372036854775806:
		return _failure("attempt_overflow")
	next["lives"] = amount
	next["attempt_sequence"] = previous + 1
	return _success(next, [], {"lives": amount, "attempt_sequence": previous + 1, "consume_free_once": consume_once})


static func _append_history(snapshot: Dictionary, changes: Array, is_cat: bool, is_wrong: bool = false) -> void:
	if changes.is_empty():
		return
	var cells: Array = []
	for change: Dictionary in changes:
		cells.append([change.row, change.col, change.get("history_before", change.before), change.after])
	var history: Array = snapshot.get("history", []).duplicate(true)
	history.append({"cells": cells, "cat": is_cat, "wrong": is_wrong})
	snapshot["history"] = history
	# 新的一步从最新历史开始回顾；页面直接使用提交快照，不再另行修正游标。
	snapshot["highlight_cursor"] = -1


## 无界面宿主也能运行草稿与自动动作。产品授权通过 policy，玩家只传动作参数。
func _apply_planned_action(next: Dictionary, kind: String, payload: Dictionary, policy: Dictionary) -> Dictionary:
	if int(next.lives) <= 0 or _complete(next):
		return _failure("round_not_playable")
	for field: String in ["auto_complete_enabled", "auto_complete_marks", "dot_toggle", "auto_mark_enabled", "include_region", "lock_marks"]:
		if policy.has(field) and typeof(policy[field]) != TYPE_BOOL:
			return _failure("invalid_action_policy")
	var board: Array = next.board
	var planned: Dictionary = {}
	var changes: Array = []
	if kind == "draft_commit":
		planned = Actions.commit_draft(board, next.solution, int(next.lives))
		next["lives"] = planned.lives
		changes = planned.changes
		_append_history(next, changes, planned.has_cat, not planned.wrong_positions.is_empty())
	elif kind == "draft_clear":
		planned = Actions.clear_draft(board)
		changes = planned.changes
	elif kind == "auto_complete":
		if not Actions.can_offer_auto_complete(board, bool(policy.get("auto_complete_enabled", false)), Actions.has_wrong_guess(board, next.get("history", []))):
			return _failure("auto_complete_unavailable")
		planned = Actions.auto_complete(board, next.solution, bool(policy.get("auto_complete_marks", false)))
		changes = _board_changes(board, planned.board)
	elif kind == "draft_mark":
		if typeof(payload.get("row")) != TYPE_INT or typeof(payload.get("col")) != TYPE_INT or typeof(payload.get("state")) != TYPE_INT:
			return _failure("invalid_cell")
		var row: int = payload.row
		var col: int = payload.col
		if row < 0 or col < 0 or row >= board.size() or col >= board.size() or not States.is_blank(int(board[row][col])):
			return _failure("cell_not_editable")
		if payload.state not in [States.EMPTY, States.DRAFT_CROSS, States.DRAFT_CAT]:
			return _failure("invalid_draft_state")
		var draft: Array = board.duplicate(true)
		draft[row][col] = payload.state
		planned = {"ok": true, "board": draft}
		changes = _board_changes(board, draft)
	else:
		var cells: Array[Vector2i] = []
		var target: int = States.MARK
		if kind == "axis_mark":
			if not bool(policy.get("dot_toggle", false)):
				return _failure("axis_mark_unavailable")
			if typeof(payload.get("axis")) != TYPE_INT or typeof(payload.get("index")) != TYPE_INT or typeof(payload.get("erase")) != TYPE_BOOL:
				return _failure("invalid_axis")
			if payload.axis not in [0, 1] or payload.index < 0 or payload.index >= board.size():
				return _failure("invalid_axis")
			cells = Actions.axis_targets(board, payload.axis, payload.index, payload.erase)
			target = States.EMPTY if payload.erase else States.MARK
		elif kind == "auto_mark":
			if not bool(policy.get("auto_mark_enabled", false)):
				return _failure("auto_mark_unavailable")
			if typeof(payload.get("row")) != TYPE_INT or typeof(payload.get("col")) != TYPE_INT:
				return _failure("invalid_cell")
			var cat := Vector2i(payload.row, payload.col)
			if cat.x < 0 or cat.y < 0 or cat.x >= board.size() or cat.y >= board.size() or board[cat.x][cat.y] != States.CAT:
				return _failure("invalid_cat")
			cells = Actions.auto_marks(board, next.regions, cat, bool(policy.get("include_region", true)))
		else:
			if not bool(policy.get("lock_marks", false)):
				return _failure("lock_marks_unavailable")
			for group: Dictionary in Actions.lock_sets(board, next.regions):
				for cell: Vector2i in group.marks:
					if not cells.has(cell):
						cells.append(cell)
			target = States.LOCKED_MARK
		var transformed: Array = board.duplicate(true)
		for cell: Vector2i in cells:
			transformed[cell.x][cell.y] = target
		planned = {"ok": true, "board": transformed}
		changes = _board_changes(board, transformed)
	next["board"] = planned.board
	if not changes.is_empty():
		next["board_revision"] = int(next.board_revision) + 1
	return _success(next, changes, {"complete": _complete(next), "lives": next.lives,
		"draft_contradiction": Actions.draft_contradiction(next.board, next.regions),
		"draft_all_correct": Actions.draft_all_correct(next.board, next.solution)})


static func _board_changes(before: Array, after: Array) -> Array:
	var changes: Array = []
	for row in range(before.size()):
		for col in range(before.size()):
			if before[row][col] != after[row][col]:
				changes.append({"row": row, "col": col, "before": before[row][col], "after": after[row][col]})
	return changes


func _life_plus(next: Dictionary, payload: Dictionary, policy: Dictionary) -> Dictionary:
	for key: String in ["enabled", "daily", "first_use"]:
		if typeof(policy.get(key)) != TYPE_BOOL:
			return _failure("invalid_life_plus_policy")
	for key: String in ["elapsed_sec", "minimum_sec", "random_value"]:
		if typeof(policy.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(policy[key])) or float(policy[key]) < 0.0:
			return _failure("invalid_life_plus_policy")
	if float(policy.random_value) > 1.0 or typeof(payload.get("row")) != TYPE_INT or typeof(payload.get("col")) != TYPE_INT:
		return _failure("invalid_life_plus_policy")
	if not Actions.life_plus_eligible(next.board, next.regions, payload.row, payload.col, int(next.lives), policy.enabled,
		bool(next.get("life_plus_used", false)), policy.daily, float(policy.elapsed_sec), float(policy.minimum_sec), policy.first_use, float(policy.random_value)):
		return _failure("life_plus_unavailable")
	next["lives"] = mini(int(next.lives) + 1, 3)
	next["life_plus_used"] = true
	return _success(next, [], {"lives": next.lives, "life_plus_used": true, "first_done": policy.first_use})
