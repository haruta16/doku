## 纯棋盘回归：可在只复制模型与 CellState 的空项目中执行，不需要自动加载或节点场景。
extends SceneTree

var _checks: int = 0

const BoardState = preload("res://products/meowdoku/gameplay/domain/doku_board_state.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")

var _failures: int = 0


func _initialize() -> void:
	_test_snapshot_and_counts()
	_test_transition_history()
	_test_restore_is_atomic()
	_test_locks_and_revisions()
	if _failures == 0:
		print("PASS: DokuBoardState snapshots, transitions, restore and locks checks=%d failures=0" % _checks)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _test_snapshot_and_counts() -> void:
	var board: BoardState = BoardState.new(3)
	_check(board.get_size() == 3 and board.count_blank() == 9, "new board is empty")
	_check(board.set_cell_state(0, 0, States.CAT), "write cat")
	_check(board.set_cell_state(0, 1, States.ERROR), "write error")
	_check(board.set_cell_state(0, 2, States.LOCKED_MARK), "write locked mark")
	_check(board.set_cell_state(1, 0, States.DRAFT_CAT), "write draft cat")
	_check(board.set_cell_state(1, 1, States.DRAFT_CROSS), "write draft cross")
	var snapshot: Array = board.get_board()
	snapshot[0][0] = States.EMPTY
	_check(board.get_cell_state(0, 0) == States.CAT, "snapshot cannot mutate live cells")
	var folded: Array = board.get_folded_board()
	_check(folded[0] == [States.CAT, States.MARK, States.MARK], "error and locked mark fold to marks")
	_check(folded[1] == [States.EMPTY, States.EMPTY, States.EMPTY], "draft folds to empty")
	_check(board.count_blank() == 6, "draft is included in blank count")
	_check(board.count_state(States.CAT) == 1, "cat count")
	_check(not board.set_cell_state(-1, 0, States.CAT), "negative coordinates rejected")
	_check(not board.set_cell_state(3, 0, States.CAT), "out of range rejected")
	_check(not board.set_cell_state(0, 0, 999), "unknown state rejected")
	_check(board.get_cell_state(-1, 0) == States.EMPTY, "out of range read matches legacy API")
	var separate: BoardState = BoardState.new(3)
	_check(separate.count_state(States.CAT) == 0, "models never share live cell arrays")


func _test_transition_history() -> void:
	var board: BoardState = BoardState.new(2)
	_check(board.transition_cell(0, 0, States.MARK, 100), "first mark")
	_check(board.has_ever_marked_x(0, 0), "mark recorded")
	_check(board.transition_cell(0, 0, States.CAT, 1099), "quick mark to cat")
	_check(not board.has_ever_marked_x(0, 0), "quick mark to cat restores prior history")
	board.transition_cell(0, 1, States.MARK, 100)
	board.transition_cell(0, 1, States.CAT, 1100)
	_check(board.has_ever_marked_x(0, 1), "exact grace boundary retains mark history")
	board.transition_cell(1, 0, States.MARK, 100)
	board.transition_cell(1, 0, States.EMPTY, 200)
	board.transition_cell(1, 0, States.MARK, 300)
	board.transition_cell(1, 0, States.CAT, 350)
	_check(board.has_ever_marked_x(1, 0), "quick second mark does not erase older mark history")
	board.transition_cell(1, 1, States.DRAFT_CAT, 0)
	board.transition_cell(1, 1, States.DRAFT_CROSS, 1)
	_check(not board.has_ever_marked_x(1, 1), "draft does not count as a formal mark")
	_check(board.apply_draft_cross(1, 1, 10), "draft cross commits")
	_check(board.has_ever_marked_x(1, 1), "draft commit tracks formal mark")
	board.transition_cell(1, 1, States.ERROR, 20)
	_check(board.has_ever_errored(1, 1), "error tracked")
	board.reset_cell_tracking(1, 1)
	_check(not board.has_ever_errored(1, 1), "tracking reset independent of cell value")
	_check(board.get_cell_state(1, 1) == States.ERROR, "tracking reset does not erase cell")
	board.set_cell_state(0, 0, States.LOCKED_MARK)
	_check(not board.transition_cell(0, 0, States.EMPTY, 1200), "ordinary transitions cannot unlock locked mark")
	_check(board.set_cell_state(0, 0, States.EMPTY), "raw restore can clear terminal state")


func _test_restore_is_atomic() -> void:
	var board: BoardState = BoardState.new(2)
	board.transition_cell(0, 0, States.ERROR, 10)
	board.set_input_locked(1, 1, true)
	var previous: Array = board.get_board()
	var revision: int = board.get_revision()
	var invalid_boards: Array = [
		[[States.EMPTY, States.CAT], [States.EMPTY]],
		[[States.EMPTY, States.CAT], [States.EMPTY, 99]],
		[[States.EMPTY, States.CAT], [States.EMPTY, true]],
		[[States.EMPTY, States.CAT], [States.EMPTY, 1.5]],
		[[States.EMPTY, States.CAT], [States.EMPTY, INF]],
		[[States.EMPTY, States.CAT], [States.EMPTY, NAN]],
		[[States.EMPTY, States.CAT], "invalid row"],
	]
	for invalid: Array in invalid_boards:
		_check(not board.restore_board(invalid), "invalid snapshot rejected")
		_check(board.get_board() == previous, "failed restore leaves every cell intact")
		_check(board.get_revision() == revision, "failed restore preserves revision")
		_check(board.is_input_locked(1, 1) and board.has_ever_errored(0, 0), "failed restore preserves metadata")
	_check(board.restore_board([[1.0, 2.0], [4.0, 6.0]]), "integer JSON numbers restore")
	_check(board.get_board() == [[1, 2], [4, 6]], "restore values")
	_check(not board.is_input_locked(1, 1) and not board.has_ever_errored(0, 0), "restore clears ephemeral metadata")
	_check(board.restore_board([]) and board.get_size() == 0, "empty snapshot supported")


func _test_locks_and_revisions() -> void:
	var board: BoardState = BoardState.new(1)
	var revision: int = board.get_revision()
	board.set_input_locked(0, 0, true)
	_check(board.is_input_locked(0, 0), "input lock lives in model")
	_check(board.get_revision() == revision, "visual lock does not invalidate board-based hint")
	board.transition_cell(0, 0, States.MARK, 0)
	_check(board.get_revision() == revision + 1, "transition advances board revision once")
	board.transition_cell(0, 0, States.MARK, 1)
	_check(board.get_revision() == revision + 1, "identical state is idempotent")
	_check(not board.reset(-1) and board.get_size() == 1, "invalid reset preserves model")
	board.reset(2)
	_check(board.count_blank() == 4 and not board.is_input_locked(0, 0), "reset clears locks and values")
