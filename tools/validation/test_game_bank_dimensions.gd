## 合法省略 size 的混合尺寸题库：真实列表按钮、双向翻题和通关下一题必须消费同一题面尺寸。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node


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
	_check(game.reset_all(), "isolated player resets")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(0)
	ab.game_auto_mark.set_debug_override(0)
	var values: Dictionary = {}
	for source: String in ["sp", "lk", "lkmodified"]:
		var id: String = "doku/levels/bankdata" + source
		var value: Variant = LevelBankIO.builtin_by_id(id).value
		var entries: Array = value.levels if value is Dictionary else value
		for entry: Dictionary in entries:
			entry.erase("size")
		values[id] = value
	var catalog: ContentCatalog = _catalog(values)
	_check(catalog.validate_all(DokuContentValidator.validation()).ok, "all three banks without size form a valid release")
	ContentContext.publish(catalog)
	for source: String in ["sp", "lk", "lkmodified"]:
		var value: Variant = values["doku/levels/bankdata" + source]
		var entries: Array = value.levels if value is Dictionary else value
		var old_default: int = 9 if source == "sp" else 8
		# 各取一题大于旧默认尺寸、一题小于旧默认尺寸，覆盖两种错配方向。
		for larger: bool in [true, false]:
			var selected: int = -1
			for index: int in range(1, entries.size() - 1):
				var size: int = entries[index].regionMap.size()
				if (size > old_default if larger else size < old_default):
					selected = index
					break
			_check(selected >= 0, source + " has the required non-default size fixture")
			if selected >= 0:
				await _exercise_routes(source, entries, selected)
	ui.hide_all()
	ContentContext.publish(null)
	# 真实通关页的出现等待已被隐藏作废；让挂起的等待返回后再结束测试进程。
	await create_timer(1.4).timeout # 通关页 APPEAR_DELAY 为 1.2 秒。
	print("GAME BANK DIMENSION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _exercise_routes(source: String, entries: Array, index: int) -> void:
	var bank: Variant = ui.show_ui(UiName.BANK)
	match source:
		"sp": bank._show_sp_panel()
		"lk": bank._show_lk_panel()
		"lkmodified": bank._show_lk_modified_panel()
	await process_frame # 排除上一轮列表已 queue_free 的按钮。
	var list: Control = bank._level_list if source == "sp" else bank._lk_list
	var buttons: Array = list.get_children().filter(func(node: Node) -> bool: return node is Button)
	_check(buttons.size() == entries.size(), source + " real bank list contains every entry")
	if index >= buttons.size():
		return
	var size: int = entries[index].regionMap.size()
	_check(_has_label(buttons[index], "%d×%d" % [size, size]), source + " bank row reports the actual size")
	buttons[index].pressed.emit()
	await _wait_for_entry()
	var page: Variant = ui.get_ui(UiName.GAME)
	if not _check_entry(page, entries[index], index, source + " list button"):
		ui.hide_all()
		await create_timer(0.4).timeout
		return
	page._on_prev_btn_pressed()
	await _wait_for_entry()
	_check_entry(page, entries[index - 1], index - 1, source + " previous puzzle")
	page._on_next_btn_pressed()
	await _wait_for_entry()
	_check_entry(page, entries[index], index, source + " next into omitted non-default size")
	page._on_next_btn_pressed()
	await _wait_for_entry()
	_check_entry(page, entries[index + 1], index + 1, source + " next puzzle")
	page._on_prev_btn_pressed()
	await _wait_for_entry()
	_check_entry(page, entries[index], index, source + " previous into omitted non-default size")
	page._on_prev_btn_pressed()
	await _wait_for_entry()
	var win: Variant = ui.show_ui(UiName.WIN, {"level_config": page._level_config.duplicate(true), "board_view": page._board_view})
	_check(win != null, source + " opens the actual win page")
	if win == null:
		ui.hide_all()
		return
	_check(win._next_btn.btn_text.contains("%d×%d" % [size, size]), source + " actual win button reports the upcoming size")
	win._next_btn.tag_pressed.emit()
	await _wait_for_entry()
	_check_entry(page, entries[index], index, source + " win next button")
	_check(not entries[index].has("size"), source + " consumer does not mutate optional metadata")
	ui.hide_all()
	await create_timer(0.5).timeout


func _wait_for_entry() -> void:
	# 首次场景加载可能耗掉本帧的计时预算；按入场状态等待，不能用短计时器抢在搭盘前断言。
	for frame: int in 120:
		await process_frame
		var page: Variant = ui.get_ui(UiName.GAME)
		if page != null and (page._entry_ready or not page._entry_error.is_empty()):
			return


func _check_entry(page: Variant, entry: Dictionary, index: int, label: String) -> bool:
	var ready: bool = page != null and page._entry_ready and page._entry_error.is_empty()
	_check(ready, label + " enters successfully")
	if not ready:
		return false
	var size: int = entry.regionMap.size()
	_check(page._level_config.get("size") == size and page._level_config.bank_params.bank_size == size, label + " propagates the actual size")
	_check(page._nav_index == index + 1, label + " retains the selected puzzle identity")
	var board: Array = page._board_view.get_board()
	_check(board.size() == size and board.all(func(row: Array) -> bool: return row.size() == size), label + " builds a complete square board")
	var solution_matches: bool = true
	for row: int in size:
		for col: int in size:
			solution_matches = solution_matches and page._puzzle.solution[row][col] == (col == int(entry.solution[row]))
	_check(solution_matches, label + " preserves the original puzzle solution")
	_check(page._ensure_business_round().get("ok", false), label + " supports the real gameplay session")
	return true


func _has_label(node: Node, text: String) -> bool:
	if node is Label and node.text.contains(text):
		return true
	for child: Node in node.get_children():
		if _has_label(child, text):
			return true
	return false


func _catalog(values: Dictionary) -> ContentCatalog:
	var directory: String = "user://bank-dimensions"
	DirAccess.make_dir_recursive_absolute(directory)
	var files: Array = []
	for id: String in values:
		var filename: String = id.get_file() + ".json"
		var path: String = directory.path_join(filename)
		var bytes: PackedByteArray = JSON.stringify(values[id]).to_utf8_buffer()
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		files.append({"id": id, "path": filename, "kind": "json", "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)})
	return ContentCatalog.new(directory, {"release": "bank-dimensions", "files": files})


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEST_FAILED: " + message)
