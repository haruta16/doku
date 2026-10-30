## 第二玩法会话的提交通知、重新打开及坏终态恢复；只使用隔离工程中的真实存档。
extends SceneTree

const Session = preload("res://scripts/examples/block/block_example_session.gd")
const Module = preload("res://scripts/examples/block/domain/block_probe_module.gd")
const Files = preload("res://scripts/framework/storage/save_store.gd")

var _checks: int = 0
var _failures: int = 0
var _directory: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use the isolated validation runner")
		quit(2)
		return
	_directory = "user://block_session_boundaries"
	for operation: String in ["start", "place", "collect"]:
		_test_reentrant_new_round(operation)
	_test_reentrant_open()
	_test_failed_reopen()
	_test_terminal_contract()
	await _test_native_drag_lifecycle()
	print("BLOCK SESSION BOUNDARY TESTS: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_reentrant_new_round(operation: String) -> void:
	var directory: String = _directory.path_join(operation)
	var session := Session.new()
	_check(session.open(directory).ok, operation + ": open real session")
	if operation == "collect":
		_check(session.new_round(_definition(1)).ok and session.place(0, 0).ok, "prepare terminal round")
	var nested: Dictionary = {}
	session._core.committed.connect(func(_revision: int) -> void:
		nested.result = session.new_round(_definition(3))
	, CONNECT_ONE_SHOT)
	var result: Dictionary
	match operation:
		"start": result = session.new_round()
		"place": result = session.place(0, 3)
		"collect": result = session.collect()
	_check(result.get("ok", false) and nested.get("result", {}).get("ok", false), operation + ": outer commit and nested new round both succeed")
	_check(session.current() == nested.get("result", {}), operation + ": old receipt cannot replace the newer round")
	var moved: Dictionary = session.place(0, 0)
	_check(moved.get("ok", false) and moved.get("snapshot", {}).get("size") == 3, operation + ": next action targets the new round")
	var reopened := Session.new()
	_check(reopened.open(directory).ok and reopened.current() == session.current(), operation + ": memory and reopened state agree")
	_check(session.stars() == (1 if operation == "collect" else 0), operation + ": notification does not change settlement grants")


func _test_reentrant_open() -> void:
	var source: String = _directory.path_join("open-source")
	var target: String = _directory.path_join("open-target")
	var session := Session.new()
	_check(session.open(source).ok, "reentrant open: original session ready")
	var nested: Dictionary = {}
	session._core.committed.connect(func(_revision: int) -> void:
		nested.result = session.open(target)
	, CONNECT_ONE_SHOT)
	var placed: Dictionary = session.place(0, 3)
	_check(placed.ok and nested.get("result", {}).get("ok", false), "reentrant open: both old placement and new store opening succeed")
	_check(session.current() == nested.get("result", {}), "receipt from the previous store cannot overwrite the newly opened store")
	_check(session.place(0, 3).get("ok", false), "newly opened store accepts its own next sequence")
	var reopened := Session.new()
	_check(reopened.open(target).ok and reopened.current() == session.current(), "reentrant open: next action survives restart")


func _test_failed_reopen() -> void:
	var source: String = _directory.path_join("reopen-source")
	var target: String = _directory.path_join("reopen-future")
	var session := Session.new()
	_check(session.open(source).ok, "failed reopen: original store ready")
	var before: Dictionary = session.current()
	var files := Files.new("block-example-local", target, true, target.path_join("a.cfg"), target.path_join("b.cfg"), target.path_join("flag"))
	var cfg := ConfigFile.new()
	cfg.set_value("core", "schema_version", 99)
	cfg.set_value("core", "state", {"inventory": {"star": 0}, "round_services": {}})
	_check(files.commit_config(cfg).ok, "failed reopen: prepare future-schema store without corrupting bytes")
	_check(session.open(target).get("error") == "schema_mismatch", "failed reopen reports the unsupported schema")
	_check(session.current().is_empty() and not session.preview(0, 3).valid, "failed reopen exposes no stale view or preview")
	_check(session.place(0, 3).get("error") == "not_open" and session.collect().get("error") == "not_open" and session.new_round().get("error") == "not_open", "failed reopen cannot keep writing through the previous host")
	var original := Session.new()
	_check(original.open(source).ok and original.current() == before, "failed reopen leaves the previous store unchanged")
	_check(session.open(source).ok and session.place(0, 3).ok, "same session can explicitly reopen and continue after failure")


func _test_terminal_contract() -> void:
	var module := Module.new()
	for kind: String in ["premature", "exhausted", "blocked"]:
		var directory: String = _directory.path_join(kind)
		var session := Session.new()
		_check(session.open(directory).ok, kind + ": open a persisted round")
		var candidate: Dictionary = session._core.snapshot()
		var snapshot: Dictionary = candidate.round_services["block_probe/example"].snapshot
		match kind:
			"premature": snapshot.finished = true
			"exhausted": snapshot.piece_index = snapshot.pieces.size()
			"blocked":
				for row: Array in snapshot.occupied:
					row.fill(1)
		_check(not module.validate_snapshot(snapshot).is_empty(), kind + ": validator rejects a contradictory finished flag")
		_check(session._core.commit(candidate, session._core.revision()).ok, kind + ": persist type-correct invalid module state for recovery test")
		var reopened := Session.new()
		_check(reopened.open(directory).get("error") == "invalid_snapshot" and reopened.current().is_empty(), kind + ": recovery refuses the bad snapshot before a view indexes the queue")
	var blocked: Dictionary = _definition(2)
	blocked.board = [[1, 1], [1, 1]]
	var ended: Dictionary = module.create_snapshot(blocked)
	_check(ended.ok and ended.snapshot.finished and module.validate_snapshot(ended.snapshot).is_empty(), "legal initially blocked board derives its terminal state")
	_check(module.settle_snapshot(ended.snapshot, {}).ok, "legal initially blocked round still settles")


func _test_native_drag_lifecycle() -> void:
	var scene: PackedScene = load("res://scripts/examples/block/block_example.tscn")
	var view: Control = scene.instantiate()
	view.storage_directory = _directory.path_join("native-drag")
	root.add_child(view)
	await process_frame
	await process_frame
	var before: Dictionary = view._session.current()
	var board: Control = view._board
	var side: float = minf(board.size.x, board.size.y)
	var origin: Vector2 = (board.size - Vector2.ONE * side) * 0.5
	var point: Vector2 = board.get_global_transform_with_canvas() * (origin + Vector2(3.5, 0.5) * side / 5.0)
	await _begin_drag(view._piece)
	_pointer_motion(point, MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_check(board._preview.get("valid", false), "native drag previews the next piece on the board")
	_pointer_motion(Vector2(-20, -20), MOUSE_BUTTON_MASK_LEFT)
	_pointer_button(Vector2(-20, -20), false)
	await process_frame
	_check(not root.gui_is_dragging() and board._preview.is_empty(), "native cancelled drag clears its preview")
	_check(view._session.current() == before, "cancelled drag consumes neither a piece nor a request sequence")
	view._session._files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	await _begin_drag(view._piece)
	_pointer_motion(point, MOUSE_BUTTON_MASK_LEFT)
	_pointer_button(point, false)
	await process_frame
	_check(view._last_result.get("error") == "commit_failed" and view._session.current() == before, "native drop write failure leaves the displayed piece and board retryable")
	_check(not root.gui_is_dragging() and board._preview.is_empty(), "failed native drop still closes the drag lifecycle")
	view._session._files.set_fault_injector_for_tests(Callable())
	await _begin_drag(view._piece)
	_pointer_motion(point, MOUSE_BUTTON_MASK_LEFT)
	_pointer_button(point, false)
	await process_frame
	_check(view._last_result.get("ok", false) and view._session.current().snapshot.score == 12, "native retry places exactly one piece after storage recovers")
	await _begin_drag(view._piece)
	view._new_button.pressed.emit()
	var replacement: Dictionary = view._session.current()
	_pointer_motion(point, MOUSE_BUTTON_MASK_LEFT)
	_pointer_button(point, false)
	await process_frame
	_check(view._session.current() == replacement and board._preview.is_empty(), "native drag begun before a new round cannot place into its replacement")
	view.queue_free()
	await process_frame


func _begin_drag(piece: Control) -> void:
	var point: Vector2 = piece.get_global_transform_with_canvas() * (piece.size * 0.5)
	_pointer_motion(point)
	_pointer_button(point, true)
	await process_frame
	_pointer_motion(point + Vector2(20, -20), MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_check(root.gui_is_dragging(), "pointer input starts the real Control drag")


func _pointer_motion(point: Vector2, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.relative = root.get_final_transform().basis_xform(Vector2(20, -20))
	event.button_mask = mask
	# 原生拖拽从 Input 查询鼠标位置；只 push_input 到 Viewport 不会更新这个位置。
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pointer_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


static func _definition(size: int) -> Dictionary:
	return {"size": size, "pieces": [[[0, 0]], [[0, 0]]] if size > 1 else [[[0, 0]]], "reward": {"star": 1}}


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + description)
