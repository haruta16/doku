## 真实 GUI 输入、手势中断与历史归属；必须经隔离 runner 执行。
extends SceneTree

var checks: int = 0
var failures: int = 0
var ui: Node
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	ui = root.get_node("UIManager")
	game = root.get_node("GameState")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(0)
	ab.game_auto_mark.set_debug_override(0)
	ab.win_toast.set_debug_override(0)
	await _test_geometry()
	for guarded: bool in [false, true]:
		await _test_normal_stroke(guarded)
	for mode: String in ["focus", "window_focus", "occluded", "modal", "disabled", "brief", "global_mask", "lost_release"]:
		await _test_interruption(mode)
	await _test_double_tap()
	for correct: bool in [true, false]:
		await _test_terminal_double_tap(correct)
	await _test_draft_and_undo()
	await _test_replacement()
	await _test_touch_emulation()
	ui.hide_all()
	await create_timer(0.9).timeout
	print("GAME INPUT LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _open(guarded: bool = false) -> Variant:
	ui.hide_all()
	await create_timer(0.9).timeout
	_check(game.reset_all(), "isolated state reset")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	var page: Variant = ui.show_ui("game", {"level_index": 50})
	await _wait_ready(page)
	page._gameplay_policy.swipe_guard = guarded
	page._gameplay_policy.swipe_guard_variant = 0
	page._gameplay_policy.tap_split = true
	page._ensure_input_system()
	return page

func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._entry_ready and not page._entry_anim_playing, "actual game entry ready")

func _center(board: Variant, row: int, col: int) -> Vector2:
	return board.cell_to_local_rect(row, col).get_center()

func _move(board: Variant, local: Vector2, mask: int = MOUSE_BUTTON_MASK_LEFT) -> void:
	var event := InputEventMouseMotion.new()
	event.position = board.get_global_transform_with_canvas() * local
	event.button_mask = mask
	root.push_input(event, true)

func _button(board: Variant, local: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = board.get_global_transform_with_canvas() * local
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	root.push_input(event, true)

func _press(board: Variant, local: Vector2) -> void:
	_move(board, local, 0)
	_button(board, local, true)

func _test_geometry() -> void:
	var board: Variant = load("res://products/meowdoku/gameplay/presentation/board/board_view.gd").new()
	root.add_child(board)
	board.position = Vector2(20000, 20000)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var guard: Variant = load("res://products/meowdoku/gameplay/presentation/input/swipe_axis_guard.gd").new()
	for size: int in range(4, 13):
		var regions: Array = []
		var colors: Array[int] = []
		for row: int in size:
			var line: Array = []
			line.resize(size)
			line.fill(row)
			regions.append(line)
			colors.append(row)
		_check(board.setup(size, regions, colors, [], true), "legal size %d builds" % size)
		guard.begin(size, board.SLOT_PX, board.BOARD_PADDING, board.CELL_PX, Vector2i(-1, -1))
		guard.configure(false, 4, 40.0)
		for cell: Vector2i in [Vector2i(0, 0), Vector2i(size - 1, 0), Vector2i(0, size - 1), Vector2i(size - 1, size - 1), Vector2i(size / 2, size / 2)]:
			var pos: Vector2 = _center(board, cell.y, cell.x)
			_check(board.pointer_to_cell(pos.x, pos.y) == cell, "plain center mapping size %d" % size)
			_check(guard.process(pos.x, pos.y) == cell, "guard center mapping size %d" % size)
		var middle: float = _center(board, 0, 0).x
		var edge: float = board.BOARD_PADDING + size * board.SLOT_PX
		for pos: Vector2 in [Vector2(-1, middle), Vector2(middle, -1), Vector2(board.BOARD_PADDING - 0.01, middle), Vector2(middle, board.BOARD_PADDING - 0.01), Vector2(edge, middle), Vector2(middle, edge)]:
			_check(board.pointer_to_cell(pos.x, pos.y) == Vector2i(-1, -1), "plain outside remains outside size %d" % size)
			_check(guard.process(pos.x, pos.y) == Vector2i(-1, -1), "guard outside remains outside size %d" % size)
		await process_frame
	board.queue_free()
	await process_frame

func _test_normal_stroke(guarded: bool) -> void:
	var page: Variant = await _open(guarded)
	var board: Variant = page._board_view
	_press(board, _center(board, 0, 0))
	_move(board, _center(board, 0, 4))
	# 仍按住时离开棋盘，再回到盘内；保留原版的跨格补插与防误滑行为。
	_move(board, Vector2(board.size.x + 100.0, _center(board, 0, 0).y))
	_move(board, _center(board, 0, 5))
	_check(board._dragging and page._gesture_recognizer._stroke.is_active(), "outside and return keeps the active stroke")
	_button(board, Vector2(board.size.x + 100.0, _center(board, 0, 0).y), false)
	for col: int in 6:
		_check(board.get_cell_state(0, col) == CellState.MARK, "normal stroke preserves interpolation")
	_check(not board._dragging and not page._gesture_recognizer._stroke.is_active(), "outside release completes capture once")
	_check(page._step_history.size() == 1 and page._current_step_cells.is_empty(), "one stroke remains one undo record")
	_check(root.get_node("Tracker").get_stat("step_used") == 1, "one stroke counts once")
	_check(not board.get_cell_view(0, 5)._press_shrunk, "release restores split-press presentation")

func _test_interruption(mode: String) -> void:
	var page: Variant = await _open()
	var board: Variant = page._board_view
	var first: Vector2 = _center(board, 0, 0)
	var second: Vector2 = _center(board, 0, 1)
	_press(board, first)
	_check(board.get_cell_state(0, 0) == CellState.MARK and board._dragging, mode + " starts real GUI stroke")
	match mode:
		"focus": root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		"window_focus": root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		"occluded": page.visible = false
		"modal": ui.show_ui("setting")
		"disabled": board.mouse_filter = Control.MOUSE_FILTER_IGNORE
		"brief": ui.block_input_briefly(page, 0.7)
		"global_mask": UIMask.acquire()
		"lost_release": _move(board, first, 0)
	await process_frame
	await process_frame
	_move(board, second)
	await process_frame
	_check(board.get_cell_state(0, 1) == CellState.EMPTY, mode + " cannot paint through lost input ownership")
	_check(not board._dragging and not page._gesture_recognizer._stroke.is_active(), mode + " clears both capture and recognizer")
	_check(page._gesture_recognizer._last_tap_cell == Vector2i(-1, -1), mode + " clears the old double-tap window")
	_check(not board.get_cell_view(0, 0)._press_shrunk, mode + " releases long-press presentation")
	_check(page._current_step_cells.is_empty() and page._step_history.size() == 1, mode + " preserves the already applied stroke as one undo record")
	_button(board, second, false)
	_check(root.get_node("Tracker").get_stat("step_used") == 1, mode + " late release cannot count twice")
	if mode == "global_mask": UIMask.release()
	if mode == "modal": ui.hide_ui("setting")
	if mode == "disabled": board.mouse_filter = Control.MOUSE_FILTER_STOP
	if mode == "occluded": page.visible = true
	if mode == "focus": root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	if mode == "window_focus": root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await create_timer(0.8).timeout
	_press(board, second)
	_button(board, second, false)
	_check(board.get_cell_state(0, 1) == CellState.MARK and page._step_history.size() == 2, mode + " next independent click remains usable")

func _test_double_tap() -> void:
	var page: Variant = await _open()
	var board: Variant = page._board_view
	var col: int = 0
	for index: int in page._level_config.size:
		if page._puzzle.solution[0][index]: col = index
	var pos: Vector2 = _center(board, 0, col)
	_press(board, pos)
	_button(board, pos, false)
	_press(board, pos)
	_button(board, pos, false)
	_check(board.get_cell_state(0, col) == CellState.CAT, "unchanged same-cell double tap places correct cat")
	_check(page._step_history.size() == 1 and page._step_history.peek_last().is_cat_placement, "double tap keeps its merged cat undo record")
	_check(page._step_history.peek_last().cells[0].before == CellState.EMPTY, "double-tap undo still targets original empty cell")
	await create_timer(0.7).timeout

func _test_terminal_double_tap(correct: bool) -> void:
	var page: Variant = await _open()
	var board: Variant = page._board_view
	var col: int = 0
	for index: int in page._level_config.size:
		if bool(page._puzzle.solution[0][index]) == correct: col = index
	if correct:
		for row: int in range(1, page._level_config.size):
			for index: int in page._level_config.size:
				if page._puzzle.solution[row][index]:
					board.get_board_state().set_cell_state(row, index, CellState.CAT)
		board.refresh_from_model()
	else:
		page._lives = 1
	var pos: Vector2 = _center(board, 0, col)
	_press(board, pos)
	_button(board, pos, false)
	_press(board, pos)
	var label: String = "last cat" if correct else "fatal wrong guess"
	_check(board.get_cell_state(0, col) == (CellState.CAT if correct else CellState.ERROR), label + " consumes the real double tap")
	_check(page._step_history.size() == 1, label + " keeps exactly one merged undo record")
	var last: Variant = page._step_history.peek_last()
	_check(last != null and last.is_cat_placement == correct and last.is_wrong_guess == not correct, label + " retains the operation flags")
	await create_timer(1.6).timeout
	_check(page._is_complete, label + " reaches terminal state")
	var history: Array = page._step_history.serialize()
	var steps: int = root.get_node("Tracker").get_stat("step_used")
	var rounds: Dictionary = game.get_core_store().snapshot().round_services
	_button(board, pos, false)
	await process_frame
	_check(page._step_history.serialize() == history, label + " late release cannot append history after settlement")
	_check(root.get_node("Tracker").get_stat("step_used") == steps and steps == 2, label + " preserves original two-tap statistics without a third count")
	_check(game.get_core_store().snapshot().round_services == rounds, label + " late release cannot rewrite settled round state")


func _test_draft_and_undo() -> void:
	var page: Variant = await _open()
	var board: Variant = page._board_view
	_press(board, _center(board, 0, 0))
	page._enter_draft_mode()
	_check(not board._dragging and page._step_history.size() == 1, "scheme switch finishes the preceding real stroke")
	_move(board, _center(board, 0, 1))
	_button(board, _center(board, 0, 1), false)
	_check(board.get_cell_state(0, 1) == CellState.EMPTY, "old normal pointer cannot continue into draft scheme")
	_press(board, _center(board, 0, 1))
	_move(board, _center(board, 0, 3))
	_button(board, _center(board, 0, 3), false)
	for col: int in range(1, 4):
		_check(board.get_cell_state(0, col) == CellState.DRAFT_CROSS, "draft stroke still interpolates draft crosses")
	_check(page._step_history.size() == 1, "draft stroke does not become a real undo step")
	page._exit_draft_mode_and_clear()
	page._gameplay_policy.undo_enabled = true
	page._gameplay_policy.undo_mode = "revert"
	_check(game.set_tool_count("undo", 3), "fund existing undo flow")
	page._on_undo_btn_pressed()
	await create_timer(0.4).timeout
	_check(board.get_cell_state(0, 0) == CellState.EMPTY and not page._step_history.has_step(), "cancelled real stroke is still undoable")
	_move(board, _center(board, 0, 4))
	_check(board.get_cell_state(0, 4) == CellState.EMPTY, "old pointer cannot repaint after undo")

func _test_replacement() -> void:
	var page: Variant = await _open()
	var board: Variant = page._board_view
	_press(board, _center(board, 0, 0))
	ui.show_ui("game", {"level_index": 50})
	await _wait_ready(page)
	var snapshot: Array = board.get_board()
	var history: Array = page._step_history.serialize()
	_move(board, _center(board, 0, 3))
	_button(board, _center(board, 0, 3), false)
	_check(board.get_board() == snapshot and page._step_history.serialize() == history, "old pointer cannot change replacement board or history")
	_check(not board._dragging and not page._gesture_recognizer._stroke.is_active(), "replacement has no old capture")

func _test_touch_emulation() -> void:
	var page: Variant = await _open()
	var board: Variant = page._board_view
	_check(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"), "existing touch-to-mouse emulation remains enabled")
	_touch(board, 0, _center(board, 0, 0), true)
	await process_frame
	_check(board.get_cell_state(0, 0) == CellState.MARK and board._dragging, "primary touch reaches existing mouse input path")
	_touch(board, 1, _center(board, 0, 4), true)
	await process_frame
	_touch(board, 1, _center(board, 0, 4), false)
	await process_frame
	_check(board.get_cell_state(0, 4) == CellState.EMPTY and board._dragging, "secondary touch does not steal or release the primary stroke")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = root.get_screen_transform() * (board.get_global_transform_with_canvas() * _center(board, 0, 2))
	Input.parse_input_event(drag)
	await process_frame
	_touch(board, 0, _center(board, 0, 2), false)
	await process_frame
	_check(board.get_cell_state(0, 2) == CellState.MARK and not board._dragging, "primary touch drag and release remain functional")
	_check(page._step_history.size() == 1, "emulated touch remains one undo stroke")

func _touch(board: Variant, index: int, local: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = root.get_screen_transform() * (board.get_global_transform_with_canvas() * local)
	event.pressed = down
	Input.parse_input_event(event)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
