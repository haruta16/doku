## 必须通过 tools/run_validation.py 的隔离工程执行：验证旧页面入口与独立说明页格子。
extends SceneTree

var _checks: int = 0

var _failures: int = 0
var _notifications: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + message)


func _run() -> void:
	# --script 的主脚本先于自动加载编译；延后加载依赖 SoundManager/GameState 的视图。
	var board_script: GDScript = load("res://products/meowdoku/gameplay/presentation/board/board_view.gd")
	var board: Variant = board_script.new()
	var cell_scene: PackedScene = load("res://products/meowdoku/assets/prefab/cell.tscn")
	root.add_child(board)
	var regions: Array = [[0, 1], [1, 0]]
	var colors: Array[int] = [0, 1]
	_check(board.setup(2, regions, colors), "valid setup reports complete board construction")
	var model: DokuBoardState = board.get_board_state()
	var before_invalid: Array = board.get_board()
	for bad_regions: Array in [[], [[0]], [[0, 1], [1]], [[0, -1], [1, 0]], [[0, 2], [1, 0]], [[0, "bad"], [1, 0]]]:
		_check(not board.setup(2, bad_regions, colors), "invalid shape or region refuses board setup")
		_check(board.get_board_state() == model and board.get_board() == before_invalid, "rejected setup preserves the active board")
	board.cell_state_changed.connect(
		func(row: int, col: int, state: int, source: int) -> void:
			_notifications.append([row, col, state, source])
	)
	board.set_cell_state(0, 0, CellState.MARK, false)
	_check(model.get_cell_state(0, 0) == CellState.MARK, "legacy BoardView write reaches model")
	_check(_notifications.size() == 1, "legacy change broadcasts once")
	board.set_cell_state(0, 0, CellState.MARK, false)
	_check(_notifications.size() == 1, "identical legacy write does not broadcast")
	var cell: Variant = board.get_cell_view(0, 1)
	cell.change_state({"state": CellState.DRAFT_CROSS, "play_anim": false})
	_check(model.get_cell_state(0, 1) == CellState.DRAFT_CROSS, "direct draft write reaches shared model")
	cell.play_draft_cross_apply()
	_check(model.get_cell_state(0, 1) == CellState.MARK, "hidden draft commit write reaches shared model")
	_check(model.has_ever_marked_x(0, 1), "draft commit history belongs to model")
	_check(_notifications.size() == 1, "direct CellView path retains legacy notification behavior")
	cell.change_state({"state": CellState.DRAFT_CROSS, "play_anim": false})
	cell.play_draft_cross_disappear()
	_check(model.get_cell_state(0, 1) == CellState.EMPTY, "hidden draft clear write reaches shared model")
	board.preset_auto_cross(1, 0)
	_check(model.get_cell_state(1, 0) == CellState.MARK, "auto cross preset commits before animation")
	var preset_revision: int = model.get_revision()
	board.play_pending_auto_cross_appear(1, 0)
	_check(model.get_revision() == preset_revision, "auto cross appearance does not recommit")
	board.lock_mark(1, 0, "", false)
	board.get_cell_view(1, 0).change_state({"state": CellState.EMPTY, "play_anim": false})
	_check(model.get_cell_state(1, 0) == CellState.LOCKED_MARK, "direct view writes still obey locked mark")
	board.set_cell_state(1, 1, CellState.CAT, false)
	board.set_cell_state(1, 1, CellState.EMPTY, false)
	_check(model.get_cell_state(1, 1) == CellState.CAT, "BoardView still protects a placed cat")
	board.get_cell_view(1, 1).demo_clear()
	_check(model.get_cell_state(1, 1) == CellState.EMPTY, "legacy demo bypass still reaches shared model")
	board.set_cell_input_locked(0, 0, true)
	_check(model.is_input_locked(0, 0) and board.get_cell_view(0, 0).is_auto_mark_locked(), "lock has one source")
	board.get_cell_view(0, 0).set_auto_mark_locked(false)
	_check(not board.is_cell_input_locked(0, 0), "direct CellView unlock reaches shared model")
	model.transition_cell(1, 1, CellState.CAT, 100)
	var revision: int = model.get_revision()
	var notifications: int = _notifications.size()
	board.present_cell_transition(1, 1, CellState.EMPTY, {"play_anim": false})
	model.set_input_locked(0, 0, true)
	_check(board.refresh_from_model(), "static redraw accepts matching size")
	_check(model.get_revision() == revision, "presentation and redraw do not change board")
	_check(_notifications.size() == notifications, "presentation and redraw do not duplicate business notifications")
	_check(model.is_input_locked(0, 0) and model.has_ever_marked_x(0, 0), "redraw preserves logic metadata")
	_check(board.get_cell_view(1, 1).get_state() == CellState.CAT, "views read headless model commit")
	var snapshot: Array = board.get_board()
	snapshot[0][0] = CellState.EMPTY
	_check(board.get_cell_state(0, 0) == CellState.MARK, "legacy exported board is a detached snapshot")
	board.setup(2, regions, colors, [], false)
	_check(board.get_board_state() == model, "setup preserves model identity for use cases")
	_check(board.get_cell_state(1, 1) == CellState.CAT, "non-recycling setup preserves existing values")
	_check(not model.is_input_locked(0, 0) and not model.has_ever_marked_x(0, 0), "setup resets temporary metadata as before")
	board.setup(2, regions, colors, [], true)
	_check(model.count_blank() == 4, "recycling setup clears every old value")
	_check(board.get_cell_view(1, 1).get_state() == CellState.EMPTY, "reused cells read reset model")
	var demo: Variant = cell_scene.instantiate()
	root.add_child(demo)
	demo.change_state({"state": CellState.MARK, "play_anim": false})
	_check(demo.get_state() == CellState.MARK, "standalone cell owns working local model")
	demo.demo_cat(false)
	_check(demo.get_state() == CellState.CAT, "standalone cat demonstration works")
	demo.demo_clear()
	_check(demo.get_state() == CellState.EMPTY and model.count_blank() == 4, "standalone demo never changes game board")
	demo.queue_free()
	board.queue_free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("PASS: BoardView/CellView unique model, legacy behavior, redraw and demos checks=%d failures=0" % _checks)
	quit(0 if _failures == 0 else 1)
