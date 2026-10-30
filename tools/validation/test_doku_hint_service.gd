## 提示策略的独立语义样例，覆盖旧页面的所有应用分支与错叉兜底。
extends SceneTree

var _checks: int = 0

const Hints = preload("res://products/meowdoku/gameplay/domain/doku_hint_service.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")

var _failures: int = 0
var _regions: Array = [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]]
var _solution: Array = [[false, true, false, false], [false, false, false, true], [true, false, false, false], [false, false, true, false]]


func _initialize() -> void:
	_test_selection_and_basic_application()
	_test_set_rules()
	_test_chains()
	if _failures == 0:
		print("PASS: Doku hints wrong-mark fallback, R1, R1_mark, four R2 modes, R3/R4 and chains checks=%d failures=0" % _checks)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + message)


func _empty_board() -> Array:
	return [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]


func _test_selection_and_basic_application() -> void:
	var board: Array = _empty_board()
	board[0][1] = States.MARK
	var hint: Dictionary = Hints.find_hint(board, _regions, _solution)
	_check(hint.get("wrong_mark", false) and hint.cell == Vector2i(0, 1), "marked solution cell triggers wrong-mark fallback")
	var applied: Dictionary = Hints.apply_hint(board, _regions, hint)
	_check(applied.board[0][1] == States.EMPTY and not applied.is_cat_step, "wrong-mark hint erases only its target")
	board = _empty_board()
	board[0] = [States.MARK, States.EMPTY, States.MARK, States.MARK]
	hint = Hints.find_hint(board, _regions, _solution)
	_check(hint.strategy == "R1" and hint.cell == Vector2i(0, 1), "unique remaining position produces R1")
	applied = Hints.apply_hint(board, _regions, hint)
	_check(applied.board[0][1] == States.CAT and applied.is_cat_step, "R1 places a cat")
	board = _empty_board()
	board[0][1] = States.CAT
	board[0][0] = States.DRAFT_CROSS
	board[0][2] = States.ERROR
	hint = Hints.find_hint(board, _regions, _solution)
	_check(hint.strategy == "R1_mark", "existing-cat exclusions are preferred before later rules")
	applied = Hints.apply_hint(board, _regions, hint)
	_check(applied.board[0][0] == States.MARK, "draft counts as blank for R1_mark application")
	var draft_change: Dictionary = applied.changes[0]
	_check(draft_change.before == States.DRAFT_CROSS and draft_change.history_before == States.EMPTY, "real before and legacy undo before remain distinct")
	_check(applied.board[0][2] == States.ERROR and applied.board[0][1] == States.CAT, "hint leaves protected cells intact")
	_check(board[0][0] == States.DRAFT_CROSS, "pure hint application never mutates its input")


func _test_set_rules() -> void:
	var cases: Array = [
		[{"mode": "r2a_row", "region": 0, "row": 1}, [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]],
		[{"mode": "r2a_col", "region": 0, "col": 1}, [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]],
		[{"mode": "r2b_row", "region": 0, "row": 1}, [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]],
		[{"mode": "r2b_col", "region": 0, "col": 1}, [Vector2i(0, 0), Vector2i(0, 2), Vector2i(0, 3)]],
	]
	for fixture: Array in cases:
		var hint: Dictionary = fixture[0].duplicate(true)
		hint["strategy"] = "R2"
		var applied: Dictionary = Hints.apply_hint(_empty_board(), _regions, hint)
		var coordinates: Array = []
		for change: Dictionary in applied.changes:
			coordinates.append(Vector2i(change.row, change.col))
		_check(coordinates == fixture[1], "R2 application matches exclusion semantics: " + str(hint.mode))
	for strategy: String in ["R3", "R4"]:
		var board: Array = _empty_board()
		board[2][0] = States.DRAFT_CAT
		board[3][1] = States.LOCKED_MARK
		var applied: Dictionary = Hints.apply_hint(board, _regions, {
			"strategy": strategy, "regions": [0], "locked_rows": [2], "locked_cols": [1],
		})
		_check(applied.changes.size() == 5, strategy + " unions row/column exclusions without duplicates")
		_check(applied.board[0][1] == States.EMPTY, strategy + " keeps cells of included region")
		_check(applied.board[2][0] == States.MARK and applied.board[3][1] == States.LOCKED_MARK, strategy + " folds drafts but preserves locked marks")
		var coordinates: Array = []
		for change: Dictionary in applied.changes:
			coordinates.append(Vector2i(change.row, change.col))
		_check(coordinates == [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(1, 1)], strategy + " preserves legacy rows-before-columns undo presentation order")


func _test_chains() -> void:
	for strategy: String in ["R4_chain", "R5_chain"]:
		var applied: Dictionary = Hints.apply_hint(_empty_board(), _regions, {"strategy": strategy, "cell": Vector2i(2, 2)})
		_check(applied.changes.size() == 1 and applied.board[2][2] == States.MARK and not applied.is_cat_step, strategy + " applies an exclusion, never a cat")
