## 合法省略 size 的真实题库必须按选题计划搭盘；搭盘失败不提交入场或开放动作。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
var levels: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	game = root.get_node("GameState")
	ui = root.get_node("UIManager")
	levels = load("res://products/meowdoku/gameplay/application/level_data.gd")
	var ab: Node = root.get_node("ABTestManager")
	ab.size_cycle.set_debug_override(2)
	ab.normal_endgame_save.set_debug_override(0)
	ab.daily_first_level_difficulty.set_debug_override(0)
	var preparer: Callable = ui._scene_preparer
	var fixture: Script = load("res://tools/validation/fixtures/rejecting_board_view.gd")
	ui._scene_preparer = func(scene: Node) -> void:
		preparer.call(scene)
		var board: Node = scene.get_node_or_null("Root/VBoxContainer/BoardContainer/BoardView")
		if board != null:
			board.set_script(fixture)
	for source: String in ["sp", "lk"]:
		await _missing_size(source)
	await _rejected_setup()
	await _invalid_prepared_shape()
	await _daily_rejected_setup()
	ui._scene_preparer = preparer
	ui.hide_all()
	ContentContext.publish(null)
	await create_timer(0.4).timeout
	for name: String in ["game", "daily_game", "confirm"]:
		await ui.destroy_ui(name)
	await process_frame
	print("GAME ENTRY SHAPE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _prepare_player() -> void:
	_check(game.reset_all(), "isolated player resets")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(1)


func _missing_size(source: String) -> void:
	_prepare_player()
	var id: String = "doku/levels/bankdata" + source
	var data: Variant = LevelBankIO.builtin_by_id(id).value
	var entries: Array = data.levels if data is Dictionary else data
	var selected: int = -1
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		entry.erase("size")
		var size: int = entry.regionMap.size()
		if selected < 0 and size != 4 and QueendokuCore.validate_solution_entry(entry, size):
			selected = index
	_check(selected >= 0, source + " contains a legal special puzzle with a different ordinary AB size")
	if selected < 0:
		return
	var values: Dictionary = {id: data, "doku/policy": {"schema": 1, "special_levels": {"1": {"source": source, "index": selected + 1}}}}
	var catalog: ContentCatalog = _catalog(source, values)
	_check(catalog.validate_all(DokuContentValidator.validation()).ok, source + " omitted size remains a fully valid content release")
	ContentContext.publish(catalog)
	var expected_size: int = entries[selected].regionMap.size()
	var plan: Dictionary = levels.resolve_level_entry(1, 4, 123)
	_check(plan.ok and plan.size == expected_size and BankData.get_region_map(plan.entry).size() == expected_size, source + " plan derives the size from the optional-field puzzle")
	var page: Variant = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.3).timeout
	_check(page._entry_ready and page._entry_error.is_empty(), source + " actual main page enters successfully")
	_check(page._level_config.get("size") == expected_size and page._puzzle.get("regions", []).size() == expected_size, source + " page uses the validated plan size")
	var board: Array = page._board_view.get_board()
	_check(board.size() == expected_size and board.all(func(row: Array) -> bool: return row.size() == expected_size), source + " actual board is completely built")
	_check(page._ensure_business_round().get("ok", false), source + " accepted entry supports the real round contract")
	_check(page._execute_business_action("locate", {}, {"locate_cost": 0}).get("ok", false), source + " subsequent business action uses the same board")
	await _close()
	ContentContext.publish(null)


func _rejected_setup() -> void:
	_prepare_player()
	var page: Variant = ui.get_ui("game")
	_check(not page._board_view.get_board().is_empty(), "cached failure fixture still owns an earlier complete board")
	page._board_view.reject_setup = true
	var before: Dictionary = game.get_core_store().snapshot()
	page = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.3).timeout
	_check(page._board_view.rejected_setups == 1, "failure comes from the actual board setup boundary")
	_check(not page._entry_ready and page._entry_error.get("error") == "invalid_board", "failed setup cannot declare the old cached board ready")
	_check(page._clock_timer.is_stopped() and not page._board_view.visible, "failed setup closes interaction and presentation")
	var after: Dictionary = game.get_core_store().snapshot()
	_check(after.profile.bank_progress == before.profile.bank_progress and after.profile.retry_puzzle_params == before.profile.retry_puzzle_params, "failed setup does not commit selection or retry data")
	_check(after.endgame.stats.main_id == before.endgame.stats.main_id and after.round_services == before.round_services, "failed setup does not publish a game identity or round")
	_check(page._execute_business_action("locate", {}, {"locate_cost": 1}).get("error") == "entry_not_ready", "failed setup cannot spend a tool")
	await _close()
	page._board_view.reject_setup = false
	page = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.3).timeout
	_check(page._entry_ready and page._entry_error.is_empty(), "same cached page can retry after setup recovers")
	await _close()


func _invalid_prepared_shape() -> void:
	_prepare_player()
	var before: Dictionary = game.get_core_store().snapshot()
	var page: Variant = ui.show_ui("game", {"debug_prebuilt": {"size": 4, "regions": [[0]], "solution": [[true]]}})
	await create_timer(0.3).timeout
	_check(not page._entry_ready and page._entry_error.get("error") == "invalid_board", "incomplete prepared entry is rejected before layout and commit")
	_check(game.get_core_store().snapshot().endgame.stats.main_id == before.endgame.stats.main_id, "invalid prepared data cannot publish successful entry tracking")
	await _close()


func _daily_rejected_setup() -> void:
	_prepare_player()
	var ab: Node = root.get_node("ABTestManager")
	ab.auto_x_fill_mode.set_debug_override(0)
	ab.dc_level.set_debug_override(0)
	var page: Variant = ui._get_or_create("daily_game")
	page._board_view.reject_setup = true
	var before: Dictionary = game.get_core_store().snapshot()
	ui.show_ui("daily_game")
	await create_timer(0.3).timeout
	_check(page._board_view.rejected_setups == 1 and not page._entry_ready, "daily setup failure cannot open interaction")
	_check(page._clock_timer.is_stopped() and not page._board_view.visible, "daily setup failure stops timer and board presentation")
	var after: Dictionary = game.get_core_store().snapshot()
	_check(after.profile.daily_started_date == before.profile.daily_started_date and after.endgame.stats.daily_id == before.endgame.stats.daily_id, "daily setup failure preserves started date and tracking identity")
	_check(after.endgame.stats.daily_total == before.endgame.stats.daily_total and after.endgame.stats.daily_round == before.endgame.stats.daily_round and after.round_services == before.round_services, "daily setup failure does not publish statistics or a business round")
	_check(page._execute_business_action("locate", {}, {"locate_cost": 1}).get("error") == "entry_not_ready", "failed daily setup cannot spend a tool")
	await _close("daily_game")
	page._board_view.reject_setup = false
	ui.show_ui("daily_game")
	await create_timer(0.3).timeout
	_check(page._entry_ready and page._ensure_business_round().get("ok", false), "daily cached page can recover and establish its real round")
	await _close("daily_game")


func _catalog(release: String, values: Dictionary) -> ContentCatalog:
	var directory: String = "user://entry-shape/" + release
	DirAccess.make_dir_recursive_absolute(directory)
	var files: Array = []
	for id: String in values:
		var filename: String = id.replace("/", "_") + ".json"
		var path: String = directory.path_join(filename)
		var bytes: PackedByteArray = JSON.stringify(values[id]).to_utf8_buffer()
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		files.append({"id": id, "path": filename, "kind": "json", "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)})
	return ContentCatalog.new(directory, {"release": release, "files": files})


func _close(name: String = "game") -> void:
	ui.hide_ui(name)
	await create_timer(0.3).timeout


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEST_FAILED: " + message)
