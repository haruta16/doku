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
	ab.auto_x_fill_mode.set_debug_override(0)
	ab.win_toast.set_debug_override(0)
	ab.multi_touch.set_debug_override(0)
	ab.doubletap_protect.set_debug_override(0)
	ab.prop_mouse.set_debug_override(1)
	ab.draft_mode.set_debug_override(5)
	await _test_geometry()
	for guarded: bool in [false, true]:
		await _test_normal_stroke(guarded)
	for mode: String in ["focus", "window_focus", "occluded", "modal", "disabled", "brief", "global_mask", "lost_release"]:
		await _test_interruption(mode)
	await _test_double_tap()
	for correct: bool in [true, false]:
		await _test_terminal_double_tap(correct)
	await _test_draft_and_mouse()
	await _test_replacement()
	for multi: bool in [false, true]:
		await _test_touch_emulation(multi)
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
	while (not page._entry_ready or page._entry_anim_playing or page._tool_btns_locked) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._entry_ready and not page._entry_anim_playing and not page._tool_btns_locked, "actual game entry ready")

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
	_check(_slot(page).latched and not _slot(page).recognizer._stroke.is_active(), "1.22 outside slop latches the completed stroke until release")
	_button(board, Vector2(board.size.x + 100.0, _center(board, 0, 0).y), false)
	for col: int in 5:
		_check(board.get_cell_state(0, col) == CellState.MARK, "normal stroke preserves interpolation")
	_check(not _slot(page).is_owned() and not _slot(page).recognizer._stroke.is_active(), "outside release completes capture once")
	_check(root.get_node("Tracker").get_solution_steps().size() == 1 and _slot(page).step_cells.is_empty(), "one stroke remains one solution step")
	_check(root.get_node("Tracker").get_stat("step_used") == 1, "one stroke counts once")
	_check(board.get_cell_state(0, 5) == CellState.EMPTY, "leaving extended hit area requires a new press before repainting")

func _test_interruption(mode: String) -> void:
	var page: Variant = await _open()
	var board: Variant = page._board_view
	var first: Vector2 = _center(board, 0, 0)
	var second: Vector2 = _center(board, 0, 1)
	_press(board, first)
	_check(board.get_cell_state(0, 0) == CellState.MARK and _slot(page).is_owned(), mode + " starts real GUI stroke")
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
	_check(not _slot(page).is_owned() and not _slot(page).recognizer._stroke.is_active(), mode + " clears both capture and recognizer")
	_check(_slot(page).recognizer._last_tap_cell == Vector2i(-1, -1), mode + " clears the old double-tap window")
	_check(not _slot(page).physically_down, mode + " releases physical pointer ownership")
	_check(_slot(page).step_cells.is_empty() and root.get_node("Tracker").get_solution_steps().size() == 1, mode + " preserves the already applied stroke as one solution step")
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
	_check(board.get_cell_state(0, 1) == CellState.MARK and root.get_node("Tracker").get_solution_steps().size() == 2, mode + " next independent click remains usable")

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
	_check(root.get_node("Tracker").get_solution_steps().size() == 1 and page._business_history.back().cat, "double tap replaces its preliminary mark with a single sign solution step")
	_check(root.get_node("Tracker").get_stat("step_used") == 1, "1.22 double tap merges its preliminary mark into one counted step")
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
	_check(root.get_node("Tracker").get_solution_steps().size() == 1, label + " keeps exactly one sign solution step")
	var last: Variant = page._business_history.back()
	_check(last != null and last.cat == correct and last.wrong == not correct, label + " retains the operation flags")
	await create_timer(1.6).timeout
	_check(page._is_complete, label + " reaches terminal state")
	var history: Array = page._business_history.duplicate(true)
	var steps: int = root.get_node("Tracker").get_stat("step_used")
	var rounds: Dictionary = game.get_core_store().snapshot().round_services
	_button(board, pos, false)
	await process_frame
	_check(page._business_history.duplicate(true) == history, label + " late release cannot append history after settlement")
	_check(root.get_node("Tracker").get_stat("step_used") == steps and steps == 1, label + " preserves the merged double-tap statistic without another count")
	_check(game.get_core_store().snapshot().round_services == rounds, label + " late release cannot rewrite settled round state")


func _test_draft_and_mouse() -> void:
	var page: Variant = await _open()
	var board: Variant = page._board_view
	game.set_tool_count("draft", 3)
	game.set_tool_count("mouse", 3)
	_press(board, _center(board, 0, 0))
	page._on_draft_btn_pressed()
	_check(page._draft_mode and not _slot(page).is_owned(), "paid draft switch finishes preceding real stroke")
	_check(root.get_node("Tracker").get_solution_steps().size() == 1, "switch keeps previous normal solution step")
	_move(board, _center(board, 0, 1))
	_button(board, _center(board, 0, 1), false)
	_check(board.get_cell_state(0, 1) == CellState.EMPTY, "old normal pointer cannot continue into draft scheme")
	_press(board, _center(board, 0, 1))
	_move(board, _center(board, 0, 3))
	_button(board, _center(board, 0, 3), false)
	for col: int in range(1, 4):
		_check(board.get_cell_state(0, col) == CellState.DRAFT_CROSS, "draft stroke still interpolates draft crosses")
	page._exit_draft_mode_and_clear()
	_check(not page._draft_mode and board.get_cell_state(0, 0) == CellState.MARK, "transactional draft cancel preserves preceding real mark")
	for col: int in range(1, 4):
		_check(board.get_cell_state(0, col) == CellState.EMPTY, "draft cancel removes only draft cells")
	page._try_start_mouse_tool()
	_check(game.get_tool_count("mouse") == 2 and page._mouse_tool_busy, "replacement 1.22 mouse tool starts one paid flow")
	var committed: Array = board.get_board().duplicate(true)
	_move(board, _center(board, 0, 4))
	_button(board, _center(board, 0, 4), false)
	_check(board.get_board() == committed, "old pointer cannot repaint during mouse animation")
	await create_timer(1.5).timeout


func _test_replacement() -> void:
	var page: Variant = await _open()
	var board: Variant = page._board_view
	_press(board, _center(board, 0, 0))
	ui.show_ui("game", {"level_index": 50})
	await _wait_ready(page)
	var snapshot: Array = board.get_board()
	var history: Array = page._business_history.duplicate(true)
	_move(board, _center(board, 0, 3))
	_button(board, _center(board, 0, 3), false)
	_check(board.get_board() == snapshot and page._business_history.duplicate(true) == history, "old pointer cannot change replacement board or history")
	_check(not _slot(page).is_owned() and not _slot(page).recognizer._stroke.is_active(), "replacement has no old capture")

func _test_touch_emulation(multi: bool) -> void:
	root.get_node("ABTestManager").multi_touch.set_debug_override(1 if multi else 0)
	var page: Variant = await _open()
	var board: Variant = page._board_view
	# Live experiment changes cannot transfer pointer ownership mid-round.
	root.get_node("ABTestManager").multi_touch.set_debug_override(0 if multi else 1)
	root.get_node("ABTestManager").doubletap_protect.set_debug_override(4)
	root.get_node("ABTestManager").swipe_logic.set_debug_override(1)
	_check(page._round_multi_touch().is_multi_touch_enabled() == multi and page._round_doubletap_protect().value() == 0 and page._round_swipe_logic().value() == 0, "input interpreters retain frozen entry values after live AB changes")
	_check(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"), "touch emulation compatibility remains enabled")
	_touch(board, 0, _center(board, 0, 0), true)
	await process_frame
	var primary: Variant = page._touch_slots.get(0 if multi else -2)
	_check(board.get_cell_state(0, 0) == CellState.MARK and primary.is_owned(), "real primary touch reaches 1.22 slot input once")
	_touch(board, 1, _center(board, 0, 4), true)
	await process_frame
	_touch(board, 1, _center(board, 0, 4), false)
	await process_frame
	_check(board.get_cell_state(0, 4) == (CellState.MARK if multi else CellState.EMPTY), "secondary touch follows frozen single versus multi mode")
	_check(primary.is_owned() and primary.physically_down, "secondary release cannot release primary stroke")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = root.get_screen_transform() * (board.get_global_transform_with_canvas() * _center(board, 0, 2))
	Input.parse_input_event(drag)
	await process_frame
	_touch(board, 0, _center(board, 0, 2), false)
	await process_frame
	_check(board.get_cell_state(0, 2) == CellState.MARK and not primary.is_owned(), "primary touch drag and release remain functional")
	_check(root.get_node("Tracker").get_solution_steps().size() == (2 if multi else 1), "emulated mouse never duplicates real touch solution steps")
	root.get_node("ABTestManager").multi_touch.set_debug_override(0)
	root.get_node("ABTestManager").doubletap_protect.set_debug_override(0)
	root.get_node("ABTestManager").swipe_logic.set_debug_override(0)

func _slot(page: Variant) -> Variant:
	return page._ensure_slot(-2)


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
