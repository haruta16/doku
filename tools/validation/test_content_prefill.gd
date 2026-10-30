## 发布校验和真实 SP 页面消费必须遵守相同的预填坐标约定。
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
	root.get_node("GameState").set_sound_on(false)
	var special: Array = bank.get_sp_levels().map(func(entry: Dictionary) -> Dictionary: return bank.materialize_entry(entry, true))
	for entry: Dictionary in special:
		for field: String in entry.keys():
			if field.begins_with("_"):
				entry.erase(field)
	var first: Dictionary = special[0]
	var size: int = first.regionMap.size()
	var answer: int = int(first.solution[0])
	_check(validator.validate("doku/levels/bankdatasp", {"levels": [first]}), "source fixture satisfies the publication schema before mutation")
	for invalid: Variant in ["bad", {}, null, [[0]], [[0, answer, 1]], [[true, answer]], [[0.5, answer]], [[0, float(answer) + 0.5]], [[-1, answer]], [[size, answer]], [[0, size]], [[0, (answer + 1) % size]], [[0, answer], [0, answer]]]:
		var candidate: Dictionary = first.duplicate(true)
		candidate["prefill_positions"] = invalid
		_check(not validator.validate("doku/levels/bankdatasp", {"levels": [candidate]}), "malformed or inconsistent prefill is rejected: " + JSON.stringify(invalid))
	first["prefill_positions"] = []
	_check(validator.validate("doku/levels/bankdatasp", {"levels": [first]}), "empty prefill is valid")
	first["prefill_positions"] = [[0.0, float(answer)], [1, int(first.solution[1])]]
	var catalog: ContentCatalog = _catalog(special)
	_check(catalog.validate_all(validator.validation()).ok, "JSON integral coordinates pass catalog validation")
	ContentContext.publish(catalog)
	var loaded: Dictionary = bank.materialize_entry(bank.get_sp_levels()[0], true)
	var params: Dictionary = _params(loaded)
	var page: Variant = ui.show_ui("game", params)
	await create_timer(0.15).timeout
	_check(page._entry_error.is_empty() and not page._entry_preparing, "valid updated SP reaches a completed real game entry")
	_check(page._board_view.count_cat_cells() == 2, "actual board consumes both published prefills")
	ui.hide_ui("game")
	await create_timer(0.4).timeout

	# 模拟旧版本已接受的内存缓存；消费端仍应拒绝它，不留下半初始化棋盘。
	bank._sp_levels[0].prefill_positions = "bad"
	page = ui.show_ui("game", params)
	await create_timer(0.1).timeout
	_check(page._entry_error.get("error") == "invalid_sp_entry", "actual SP page rejects malformed cached metadata before typed Array consumption")
	_check(page._entry_preparing and page._puzzle.is_empty(), "invalid metadata cannot complete game start or retain a playable puzzle")
	ui.hide_ui("game")
	await create_timer(0.4).timeout

	bank._sp_levels[0].prefill_positions = []
	var stale: Dictionary = params.duplicate(true)
	stale.prebuilt_solution = [0, 0, 0, 0]
	page = ui.show_ui("game", stale)
	await create_timer(0.1).timeout
	_check(page._entry_error.get("error") == "sp_entry_content_changed" and page._puzzle.is_empty(), "stale page parameters cannot mix one puzzle with another release's SP metadata")
	ui.hide_ui("game")
	await create_timer(0.4).timeout
	var invalid_index: Dictionary = params.duplicate(true)
	invalid_index.bank_index = 0
	page = ui.show_ui("game", invalid_index)
	await create_timer(0.1).timeout
	_check(page._entry_error.get("error") == "invalid_sp_entry", "SP index zero is rejected before an array lookup")
	ui.hide_ui("game")
	await create_timer(0.4).timeout
	ContentContext.publish(null)
	print("CONTENT_PREFILL_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _params(entry: Dictionary) -> Dictionary:
	return {"bank_mode": true, "bank_sp": true, "bank_size": entry.regionMap.size(), "bank_rank": int(entry.get("r", 1)), "bank_index": 1, "bank_total": 1, "prebuilt_regions": entry.regionMap.duplicate(true), "prebuilt_solution": entry.solution.duplicate(true), "prebuilt_color_map": entry.get("colorMap", []).duplicate()}


func _catalog(levels: Array) -> ContentCatalog:
	var directory: String = "user://prefill-content/valid"
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("special.json")
	var bytes := JSON.stringify({"levels": levels}).to_utf8_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return ContentCatalog.new(directory, {"release": "valid-prefill", "files": [{"id": "doku/levels/bankdatasp", "path": "special.json", "kind": "json", "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)}]})


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
