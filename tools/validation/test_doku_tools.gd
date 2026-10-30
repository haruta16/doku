## 独立行为验收：期望由旧 BaseGamePage 定位/撤销流程推导，不调用页面或 autoload。
extends SceneTree

var _checks: int = 0

const Tools = preload("res://products/meowdoku/gameplay/domain/doku_tool_service.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")

var _failures: int = 0
var _regions: Array = [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]]
var _solution: Array = [[false, true, false, false], [false, false, false, true], [true, false, false, false], [false, false, true, false]]


func _initialize() -> void:
	_test_locate()
	_test_revert()
	_test_highlight()
	_test_invalid_history()
	if _failures == 0:
		print("PASS: Doku tools locate ordering, no target, protected undo, pure highlight and invalid history checks=%d failures=0" % _checks)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + message)


func _empty_board() -> Array:
	return [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]


func _step(cells: Array, cat: bool = false, wrong: bool = false) -> Dictionary:
	return {"cells": cells, "cat": cat, "wrong": wrong}


func _target(result: Dictionary) -> Vector2i:
	if not result.get("ok", false) or result.get("changes", []).is_empty():
		return Vector2i(-1, -1)
	return Vector2i(result.changes[0].row, result.changes[0].col)


func _test_locate() -> void:
	var board: Array = _empty_board()
	board[1] = [States.MARK, States.ERROR, States.EMPTY, States.EMPTY]
	board[2] = [States.EMPTY, States.MARK, States.ERROR, States.EMPTY]
	board[3] = [States.MARK, States.MARK, States.EMPTY, States.ERROR]
	var original: Array = board.duplicate(true)
	var result: Dictionary = Tools.locate(board, _regions, _solution)
	_check(_target(result) == Vector2i(3, 2), "fewest remaining region cells beats row order")
	_check(result.board[3][2] == States.CAT and result.is_cat_step, "locate returns one correct-cat transition")
	_check(board == original, "locate does not mutate input board")
	result = Tools.locate(result.board, _regions, _solution)
	_check(_target(result) == Vector2i(1, 3), "equal region counts use row order and skip completed target")
	var same_region_solution: Array = [[true, false, true, false], [false, false, false, false], [false, false, false, false], [false, false, false, false]]
	result = Tools.locate(_empty_board(), _regions, same_region_solution)
	_check(_target(result) == Vector2i(0, 0), "equal row ties use column order")
	board = _empty_board()
	board[0][1] = States.MARK
	result = Tools.locate(board, _regions, _solution)
	_check(_target(result) == Vector2i(0, 1) and result.changes[0].before == States.MARK, "wrong-marked answer remains a valid locate target")
	board = _empty_board()
	board[0][1] = States.LOCKED_MARK
	board[1][3] = States.CAT
	board[2][0] = States.CAT
	board[3][2] = States.CAT
	result = Tools.locate(board, _regions, _solution)
	_check(result.get("error") == "no_locate_target", "locked final answer produces no board target; product module decides attempt charging")
	board[0][1] = States.CAT
	_check(Tools.locate(board, _regions, _solution).get("error") == "no_locate_target", "complete answer has no locate target")
	board = _empty_board()
	board[0][1] = States.LOCKED_MARK
	_check(_target(Tools.locate(board, _regions, _solution)) == Vector2i(1, 3), "locked answer is skipped in favor of a usable target")


func _test_revert() -> void:
	var board: Array = _empty_board()
	board[0] = [States.MARK, States.CAT, States.ERROR, States.LOCKED_MARK]
	board[1][0] = States.DRAFT_CROSS
	board[3][3] = States.MARK
	var history: Array = [
		_step([[2, 3, States.EMPTY, States.MARK]]),
		_step([
			[0, 0, States.EMPTY, States.MARK],
			[0, 1, States.EMPTY, States.CAT],
			[0, 2, States.EMPTY, States.ERROR],
			[0, 3, States.EMPTY, States.MARK],
			[1, 0, States.MARK, States.DRAFT_CROSS],
		]),
		_step([[0, 1, States.EMPTY, States.CAT]], true),
		_step([[3, 3, States.EMPTY, States.MARK]], false, true),
	]
	var original_board: Array = board.duplicate(true)
	var original_history: Array = history.duplicate(true)
	var result: Dictionary = Tools.undo(board, history, "revert", -1)
	_check(result.get("ok", false), "revert finds older usable step past wrong guess and protected cat step")
	if not result.get("ok", false):
		return
	_check(result.changes.size() == 2 and result.board[0][0] == States.EMPTY and result.board[1][0] == States.MARK, "revert restores historical values, including draft predecessor")
	_check(result.board[0][1] == States.CAT and result.board[0][2] == States.ERROR and result.board[0][3] == States.LOCKED_MARK, "revert protects cat, error and locked cells")
	_check(result.board[3][3] == States.MARK, "wrong-guess history is skipped even if its current cell would be editable")
	_check(result.history == [history[0]] and result.highlight_cursor == -1, "revert removes selected and newer skipped steps, then resets highlight cursor")
	_check(board == original_board and history == original_history, "revert never mutates input board or history")
	result.history[0].cells[0][0] = 99
	_check(history == original_history, "returned history cannot mutate caller history")
	var blocked: Array = [_step([[0, 1, States.EMPTY, States.CAT]], true), _step([[0, 3, States.EMPTY, States.MARK]])]
	_check(Tools.undo(board, blocked, "revert", -1).get("error") == "no_undo_step", "protected-only history cannot consume undo")
	_check(Tools.undo(board, [], "revert", -1).get("error") == "no_undo_step", "empty history cannot undo")
	# 原版先选可编辑步骤再收费，不以实际格子变化作为选中条件。
	var unchanged_board: Array = _empty_board()
	var selected: Array = [_step([[0, 0, States.EMPTY, States.MARK]])]
	result = Tools.undo(unchanged_board, selected, "revert", -1)
	_check(result.get("ok", false) and result.changes.is_empty(), "selected editable step remains a valid undo when already at its before value")
	_check(result.get("history", [1]).is_empty() and result.board == unchanged_board, "unchanged selected undo still removes its step without changing the board")
	_check(selected.size() == 1 and unchanged_board == _empty_board(), "unchanged selected undo does not mutate its inputs")


func _test_highlight() -> void:
	var board: Array = _empty_board()
	var history: Array = [
		_step([[0, 0, States.EMPTY, States.MARK]]),
		_step([[1, 1, States.EMPTY, States.CAT]], true),
		_step([[2, 2, States.EMPTY, States.CAT]], false, true),
	]
	var original: Array = history.duplicate(true)
	var result: Dictionary = Tools.undo(board, history, "highlight", -1)
	_check(result.get("ok", false) and result.highlight_cursor == 0, "pure-cat highlight walks back to an ordinary marking step")
	_check(result.get("highlight_cells", []) == [history[2].cells[0], history[1].cells[0], history[0].cells[0]], "highlight groups cells in newest-to-oldest presentation order")
	_check(result.get("changes", []) == [] and not result.has("board"), "highlight only returns selection data, never board writes")
	_check(result.history == history and history == original, "highlight keeps all history")
	result.highlight_cells[0][0] = 99
	result.history[0].cells[0][0] = 99
	_check(history == original, "highlight output is detached from caller history")
	_check(Tools.undo(board, history, "highlight", 0).get("error") == "no_undo_step", "highlight reaching beginning returns no step")
	_check(Tools.undo(board, history, "highlight", -2).get("error") == "no_undo_step", "exhausted highlight cursor stays unavailable")
	var mixed: Array = [history[0], _step([[1, 1, States.EMPTY, States.CAT], [1, 2, States.EMPTY, States.MARK]], true)]
	result = Tools.undo(board, mixed, "highlight", -1)
	_check(result.get("ok", false) and result.highlight_cursor == 1 and result.highlight_cells == mixed[1].cells, "cat step containing exclusions is already a complete highlight group")
	var wrong_with_error: Array = [history[0], _step([[2, 2, States.EMPTY, States.ERROR]], false, true)]
	result = Tools.undo(board, wrong_with_error, "highlight", -1)
	_check(result.get("ok", false) and result.highlight_cursor == 1 and result.highlight_cells == wrong_with_error[1].cells, "wrong guess with non-cat result remains its own visual history group")
	var only_cats: Array = [_step([[1, 1, States.EMPTY, States.CAT]], true)]
	_check(Tools.undo(board, only_cats, "highlight", -1).get("error") == "no_undo_step", "cat-only history with no prior marking group cannot highlight")


func _test_invalid_history() -> void:
	var invalid_cases: Array = [
		[null],
		[{"cells": "wrong"}],
		[_step([[0, 0, States.EMPTY]])],
		[_step([[0, 4, States.EMPTY, States.MARK]])],
		[_step([[-1, 0, States.EMPTY, States.MARK]])],
		[_step([[0, 0, -1, States.MARK]])],
		[_step([[0, 0, States.EMPTY, 7]])],
		[_step([[0, 0, States.EMPTY, 2.0]])],
		[_step([[true, 0, States.EMPTY, States.MARK]])],
	]
	for invalid: Array in invalid_cases:
		_check(Tools.undo(_empty_board(), invalid, "revert", -1).get("error") == "invalid_history", "malformed history rejects revert: " + str(invalid))
		_check(Tools.undo(_empty_board(), invalid, "highlight", -1).get("error") == "invalid_history", "malformed history rejects highlight: " + str(invalid))
	_check(Tools.undo(_empty_board(), [], "unknown", -1).get("error") == "invalid_undo_mode", "unknown undo mode rejected")
