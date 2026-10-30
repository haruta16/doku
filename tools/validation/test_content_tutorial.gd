## 真正打开并完成教学：SP 内容可替换，但固定步骤与题面必须保持同一客户端版本。
extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var bank: Script = load("res://products/meowdoku/gameplay/content/bank_data.gd")
	var validator: Script = load("res://products/meowdoku/gameplay/content/doku_content_validator.gd")
	var ui: Node = root.get_node("UIManager")
	var expected: Dictionary = {}
	var special: Array = bank.get_sp_levels().map(func(entry: Dictionary) -> Dictionary: return bank.materialize_entry(entry, true))
	for entry: Dictionary in special:
		if entry.get("pattern") == "guide":
			expected = entry.duplicate(true)
		entry.pattern = "ordinary"
		for field: String in entry.keys():
			if field.begins_with("_"):
				entry.erase(field)
	_check(not expected.is_empty(), "original tutorial fixture is available for comparison")
	var catalog := _catalog("without-guide", special)
	_check(catalog.validate_all(validator.validation()).ok, "SP without guide remains a valid ordinary content replacement")
	ContentContext.publish(catalog)
	_check(bank.get_sp_levels()[0]._content_provenance.release == "without-guide", "ordinary SP consumer reads replacement")
	var page: Variant = ui.show_ui("tutorial")
	_check(page.is_board_ready(), "actual tutorial entry initializes without remote guide")
	_check(_same_json(page._guide_regions, expected.regionMap), "tutorial retains the authored board for fixed steps")
	_check(page._board_view.count_empty_cells() == 16, "actual tutorial board creates sixteen empty cells")
	ui.hide_ui("tutorial")
	await create_timer(0.4).timeout

	# 即使远端保留 guide 标签并改成另一张合法 6×6 题，也不能影响固定 4×4 教学。
	var changed: Dictionary = bank.materialize_entry(bank.get_gc_levels(6, 1)[0], true)
	for field: String in changed.keys():
		if field.begins_with("_"):
			changed.erase(field)
	changed.pattern = "guide"
	special[0] = changed
	catalog = _catalog("different-guide", special)
	_check(catalog.validate_all(validator.validation()).ok, "a valid six by six SP entry is allowed regardless of its pattern label")
	ContentContext.publish(catalog)
	_check(bank.get_region_map(bank.get_sp_levels()[0]).size() == 6, "normal SP reader sees the six by six replacement")
	page = ui.show_ui("tutorial")
	_check(page.is_board_ready() and page._board_view.get_board().size() == 4, "actual tutorial remains four by four")
	_check(_same_json(page._guide_regions, expected.regionMap) and _same_json(page._guide_color_map, expected.colorMap), "fixed tutorial preserves authored regions and colors")

	# 通过真实棋盘信号与确认按钮完成七步，而不是仅检查静态常量。
	await _wait_mode(page, page.StepMode.PLACE_CAT)
	_tap(page, 0, 2)
	_tap(page, 0, 2)
	await _wait_mode(page, page.StepMode.CONFIRM)
	page._confirm_btn.tag_pressed.emit()
	await _wait_mode(page, page.StepMode.MARK_CELLS)
	for cell: Vector2i in page._allowed_cells.duplicate():
		_tap(page, cell.x, cell.y)
	await _wait_mode(page, page.StepMode.PLACE_CAT)
	_tap(page, 3, 1)
	_tap(page, 3, 1)
	await _wait_mode(page, page.StepMode.MARK_CELLS)
	for cell: Vector2i in page._allowed_cells.duplicate():
		_tap(page, cell.x, cell.y)
	await _wait_mode(page, page.StepMode.PLACE_CAT)
	_tap(page, 1, 0)
	_tap(page, 1, 0)
	await _wait_mode(page, page.StepMode.FREE_PLAY)
	_tap(page, 2, 3)
	_tap(page, 2, 3)
	await _wait_mode(page, page.StepMode.CONFIRM)
	_check(page._board_view.count_cat_cells() == 4, "all scripted placements reach a complete tutorial board")
	page._confirm_btn.tag_pressed.emit()
	await create_timer(0.6).timeout
	var game: Node = root.get_node("GameState")
	_check(game.is_tutorial_done(), "actual tutorial completion persists player progress")
	var game_page: Variant = ui.get_ui("game")
	_check(game_page != null and game_page.visible and game_page._entry_error.is_empty(), "completion enters the actual first game successfully")
	ContentContext.publish(null)
	ui.hide_all()
	await create_timer(2.0).timeout
	print("CONTENT_TUTORIAL_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _tap(page: Variant, row: int, column: int) -> void:
	var cell: Control = page._board_view.get_cell_view(row, column)
	var position: Vector2 = cell.position + cell.size * 0.5
	page._board_view.cell_drag_start.emit(position)
	page._board_view.cell_drag_end.emit(position)


func _wait_mode(page: Variant, mode: int) -> void:
	var deadline: int = Time.get_ticks_msec() + 3000
	while page._current_mode != mode and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._current_mode == mode, "script reaches expected interaction mode: " + str(mode))


func _catalog(release: String, levels: Array) -> ContentCatalog:
	var directory: String = "user://tutorial-content".path_join(release)
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("special.json")
	var bytes := JSON.stringify({"levels": levels}).to_utf8_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return ContentCatalog.new(directory, {"release": release, "files": [{"id": "doku/levels/bankdatasp", "path": "special.json", "kind": "json", "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)}]})


func _same_json(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
