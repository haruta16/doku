## size 为可选元数据：发布合法的省略版本后，题源/游标、统计及真实预览入口保持一致。
extends SceneTree

const BANK_ID: String = "doku/levels/bankdatalkmodified"

var checks: int = 0
var failures: int = 0
var levels: Script
var simulator: Script
var commands_script: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var game: Node = root.get_node("GameState")
	var ui: Node = root.get_node("UIManager")
	levels = load("res://products/meowdoku/gameplay/application/level_data.gd")
	simulator = load("res://products/meowdoku/app/diagnostics/view/playtest_simulator_page.gd")
	commands_script = load("res://products/meowdoku/app/diagnostics/cheat_commands.gd")
	_check(game.reset_all(), "isolated player resets")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	root.get_node("ABTestManager").normal_endgame_save.set_debug_override(0)
	var expected: Dictionary = _pool_snapshot()
	var expected_counts: Dictionary = simulator._compute_pool_sizes()
	var expected_selection: Dictionary = _selection_snapshot()
	var data: Variant = LevelBankIO.builtin_by_id(BANK_ID).value
	var entries: Array = data.levels if data is Dictionary else data
	for entry: Dictionary in entries:
		entry.erase("size")
	var directory: String = "user://optional-dimensions"
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("lkmodified.json")
	var bytes: PackedByteArray = JSON.stringify(data).to_utf8_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var catalog := ContentCatalog.new(directory, {"release": "optional-dimensions", "files": [
		{"id": BANK_ID, "path": "lkmodified.json", "kind": "json", "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)}]})
	_check(catalog.validate_all(DokuContentValidator.validation()).ok, "omitted size passes complete candidate release validation")
	ContentContext.publish(catalog)
	var actual: Dictionary = _pool_snapshot()
	for key: String in expected:
		_check(actual[key] == expected[key], key + " keeps eligible puzzle identities and order for optional size")
	_check(simulator._compute_pool_sizes() == expected_counts, "simulator reports the same pool sizes for the legal update")
	_check(_selection_snapshot() == expected_selection, "real main selector preserves source, puzzle and progress across the metadata-only update")
	_check(levels._lk_modified_pool(8, 4, false).size() > 0, "reported 8x8 rank4 pool remains available")
	var commands: Node = commands_script.new()
	var preview_args: Array[String] = ["1", "0", "lkm_8_4"]
	commands._cmd_bank_preview(preview_args)
	var page: Variant = null
	for frame: int in 120:
		await process_frame
		page = ui.get_ui(UiName.GAME)
		if page != null and (page._entry_ready or not page._entry_error.is_empty()):
			break
	_check(page != null and page._entry_ready and page._entry_error.is_empty(), "actual bank_preview command opens the omitted-size LK modified puzzle")
	if page != null and page._entry_ready:
		_check(page._level_config.size == 8 and page._board_view.get_board().size() == 8, "preview builds the requested complete 8x8 board")
		var first: Dictionary = entries.filter(func(entry: Dictionary) -> bool: return entry.regionMap.size() == 8 and int(entry.get("maxR", entry.get("r", 0))) == 4)[0]
		var same: bool = true
		for row: int in 8:
			for col: int in 8:
				same = same and page._puzzle.solution[row][col] == (col == int(first.solution[row]))
		_check(same, "preview retains the requested first puzzle identity")
	_check(entries.all(func(entry: Dictionary) -> bool: return not entry.has("size")), "consumers do not mutate omitted metadata in the shared content")
	commands.free()
	ui.hide_all()
	ContentContext.publish(null)
	await create_timer(0.6).timeout
	print("CONTENT OPTIONAL DIMENSION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _pool_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for size: int in range(4, 13):
		for rank: int in range(1, 6):
			for strict: bool in [false, true]:
				var pool: Array = levels._lk_modified_pool(size, rank, strict).duplicate(true)
				for entry: Dictionary in pool:
					entry.erase("size")
					entry.erase("_content_provenance") # 发布来源已改变，题面本身必须不变。
				result["%d/%d/%s" % [size, rank, strict]] = pool
	return result


func _selection_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for strict: bool in [false, true]:
		for since_lk: int in [0, 4]:
			var working := DokuSelectionState.new({})
			working.set_main_progress(8, 4, "N", {"idx": 0, "since_lk": since_lk, "transform": 0})
			var chosen: Dictionary = levels.get_next_entry_main(8, 4, "N", -1, strict, working, {"single_region": 0})
			chosen.erase("size")
			chosen.erase("_content_provenance")
			var key: String = "%s/%d" % [strict, since_lk]
			result[key] = {"entry": chosen, "progress": working.snapshot()}
	return result


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEST_FAILED: " + message)
