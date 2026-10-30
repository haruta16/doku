## 真实 Block 场景交互；无产品单例依赖，使用临时工程内的独立夹具。
extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _directory: String
var _example: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var project: String = ProjectSettings.globalize_path("res://")
	if not project.contains("/doku-validation-") and not project.contains("/doku-block-example-"):
		printerr("TEST_FAILED: use an isolated example/validation runner")
		quit(2)
		return
	_directory = project.path_join("block_example_test")
	await _create_view()
	_check(_example._last_result.get("ok", false), "real scene opens and starts a round")
	var original: Dictionary = _example._session.current()
	var preview: Dictionary = _example._session.preview(0, 3)
	_check(preview.valid and preview.cells == [[0, 3], [0, 4]], "rule module returns placement preview")
	_check(_example._session.current() == original, "preview does not advance the round")
	_check(not _example._session.preview(0, 0).valid, "overlap preview is rejected")
	_example._board.place_requested.emit(0, 0)
	_check(_example._last_result.get("error") == "invalid_placement" and _example._session.current() == original, "bad UI placement leaves saved board intact")
	_example._session._files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_example._board.place_requested.emit(0, 3)
	_check(_example._last_result.get("error") == "commit_failed", "page reports a failed placement save")
	_check(_example._session.current() == original, "write failure changes neither board nor sequence")
	_example._session._files.set_fault_injector_for_tests(Callable())
	var board: Control = _example._board
	var side: float = minf(board.size.x, board.size.y)
	var origin := (board.size - Vector2.ONE * side) * 0.5
	var point := origin + Vector2(3.5, 0.5) * side / 5.0
	var drag: Dictionary = {"kind": "block_piece", "round_id": original.round_id, "sequence": original.next_sequence}
	_check(board._can_drop_data(point, drag), "actual drag target accepts valid piece")
	board._drop_data(point, drag)
	var placed: Dictionary = _example._session.current()
	_check(placed.snapshot.score == 12 and placed.snapshot.occupied[0] == [0, 0, 0, 0, 0], "real drop clears row and saves score")
	_check(placed.next_sequence == original.next_sequence + 1, "placement advances one durable request")
	_check(not board._can_drop_data(point, drag), "old drag cannot place the next piece after a committed action")
	var identity: String = placed.round_id
	_example.queue_free()
	await process_frame
	await _create_view()
	_check(_example._session.current().round_id == identity and _example._session.current().snapshot == placed.snapshot, "destroy and recreate view restores exact round")
	_example._reload_button.pressed.emit()
	_check(_example._session.current().snapshot == placed.snapshot, "reload button preserves committed state")
	var short_round: Dictionary = _example._session.new_round({"size": 2, "board": [[1, 0], [0, 0]], "pieces": [[[0, 0]]], "reward": {"star": 1}})
	_check(short_round.ok, "prepare finite completion through same product port")
	_example._refresh()
	_example._board.place_requested.emit(0, 1)
	_check(_example._collect_button.visible and not _example._collect_button.disabled, "finish exposes reward button")
	_example._session._files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_example._collect_button.pressed.emit()
	_check(_example._session.stars() == 0 and not _example._collect_button.disabled, "failed settlement remains retryable without reward")
	_example._session._files.set_fault_injector_for_tests(Callable())
	_example._collect_button.pressed.emit()
	_check(_example._session.stars() == 1 and _example._collect_button.disabled, "successful settlement grants once and disables button")
	_example._collect_button.pressed.emit()
	_check(_example._session.stars() == 1 and _example._last_result.duplicate, "repeated callback cannot duplicate reward")
	_example._reload_button.pressed.emit()
	_check(_example._session.stars() == 1 and _example._collect_button.disabled, "reload preserves terminal receipt")
	_example._new_button.pressed.emit()
	_check(_example._session.current().round_id != identity and _example._session.current().snapshot.score == 0, "new-round button creates a fresh identity")
	_check(_example._session.stars() == 1, "new round preserves shared inventory")
	await process_frame
	await process_frame
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot="):
			var path: String = argument.trim_prefix("--screenshot=")
			await RenderingServer.frame_post_draw
			var captured: Image = root.get_texture().get_image()
			_check(not captured.is_empty() and captured.save_png(path) == OK, "rendered scene screenshot is saved")
			print("BLOCK_EXAMPLE_SCREENSHOT=" + path)
	_example.queue_free()
	await process_frame
	print("BLOCK EXAMPLE TESTS: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _create_view() -> void:
	var scene: PackedScene = load("res://scripts/examples/block/block_example.tscn")
	_example = scene.instantiate()
	_example.storage_directory = _directory
	root.add_child(_example)
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + description)
