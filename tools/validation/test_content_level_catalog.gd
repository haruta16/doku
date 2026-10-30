## 精确关卡表必须在候选发布中自洽，且实际入口不能被旧随机选题/查重替换。
extends SceneTree

var checks: int = 0
var failures: int = 0


class CountingCatalog extends RefCounted:
	var value: Dictionary
	var reads: int = 0
	var release: String = "counted-a"

	func _init(table: Dictionary) -> void:
		value = table

	func read_json(id: String) -> Dictionary:
		if id != DokuLevelCatalog.ID:
			return {"ok": false, "error": "unknown_content"}
		reads += 1
		return {"ok": true, "value": value.duplicate(true), "release": release}

	func release_id() -> String:
		return release


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var levels: Script = load("res://products/meowdoku/gameplay/application/level_data.gd")
	var validator: Script = load("res://products/meowdoku/gameplay/content/doku_content_validator.gd")
	var missing := func(_id: String) -> Dictionary: return {"ok": false, "error": "unknown_content"}
	var definition: Dictionary = {"puzzle": {"bank": "doku/levels/bankdata4x4", "rank": 1, "index": 1}, "rules": {"initial_lives": 2, "draft_unlock_level": 5}, "reward": {"hint": 2}}
	var resolved: Dictionary = DokuLevelCatalog.resolve_definition(definition, missing)
	_check(resolved.ok and resolved.entry.size == 4 and resolved.entry._bank_source == "catalog", "fixed catalog resolves exact builtin reference")
	if not resolved.ok:
		quit(1)
		return
	definition["prefill"] = [[0, int(resolved.entry.solution[0])]]
	# Godot JSON 数字解码为 float，期望值走相同边界，避免拿内存 int 类型比较。
	definition = JSON.parse_string(JSON.stringify(definition))
	var table: Dictionary = {"schema": 1, "levels": {"21": definition}}
	_check(DokuLevelCatalog.validate_references(table, missing).ok, "valid prefill and builtin dependency")
	for malformed: Variant in [null, [], {"schema": true, "levels": {}}, {"schema": {}, "levels": {}}, {"schema": 1, "levels": {"01": definition}}]:
		_check(not DokuLevelCatalog.validate(malformed), "malformed schema rejected without runtime error")
	for malformed: Variant in [{}, {"puzzle": []}, {"puzzle": {"bank": "doku/levels/bankdata4x4", "index": true}}, {"puzzle": definition.puzzle, "extra": 1}, {"puzzle": definition.puzzle, "rules": {"initial_lives": 0}}, {"puzzle": definition.puzzle, "reward": {"gems": 1}}, {"puzzle": definition.puzzle, "prefill": [[0, 0], [0, 0]]}]:
		_check(not DokuLevelCatalog.validate_definition(malformed), "bad field cannot silently have no effect")
	var bad: Dictionary = definition.duplicate(true)
	bad.puzzle.index = 999999
	_check(not DokuLevelCatalog.resolve_definition(bad, missing).ok, "missing exact reference rejects instead of reroll")
	bad = definition.duplicate(true)
	bad.prefill = [[0, (int(resolved.entry.solution[0]) + 1) % 4]]
	_check(not DokuLevelCatalog.resolve_definition(bad, missing).ok, "wrong prefilled cat rejected")
	var malformed_bank := func(_id: String) -> Dictionary: return {"ok": true, "value": {"1": [{"regionMap": "bad"}]}}
	_check(not DokuLevelCatalog.resolve_definition(definition, malformed_bank).ok, "malformed provider rejected safely")
	for malformed_entry: Dictionary in [{"regionMap": [[], [], [], []], "solution": "bad"}, {"regionMap": ["bad", [], [], []], "solution": [0, 1, 2, 3]}, {"regionMap": resolved.entry.regionMap, "solution": [true, 1, 2, 3]}]:
		var provider := func(_id: String) -> Dictionary: return {"ok": true, "value": {"1": [malformed_entry]}}
		_check(not DokuLevelCatalog.resolve_definition(definition, provider).ok, "invalid referenced rows and solution rejected safely")
	bad = definition.duplicate(true)
	bad.media = {"game/mark": "season/mark"}
	var media_table: Dictionary = {"schema": 1, "levels": {"21": bad}}
	_check(not DokuLevelCatalog.validate_references(media_table, missing).ok, "media alias must exist in candidate release")
	_check(not DokuLevelCatalog.validate_references(media_table, missing, {"audio": {"season/mark": "mark.wav"}}).ok, "media alias kind must match scene slot")
	_check(DokuLevelCatalog.validate_references(media_table, missing, {"textures": {"season/mark": "mark.png"}}).ok, "same-kind alias accepted")
	for slot: String in ["ui/home/logo", "ui/home/daily_record", "ui/home/daily_base", "ui/home/logo_spine"]:
		bad = definition.duplicate(true)
		bad.media = {slot: "season/home"}
		_check(not DokuLevelCatalog.validate_definition(bad), "global scene slot cannot be published as an ineffective per-level alias: " + slot)
	for slot: String in DokuLevelCatalog.BOARD_MEDIA_SLOTS:
		bad = definition.duplicate(true)
		bad.media = {slot: "season/board"}
		_check(DokuLevelCatalog.validate_definition(bad), "actual board slot remains configurable: " + slot)
	var directory: String = "user://level-catalog-test"
	DirAccess.make_dir_recursive_absolute(directory)
	var candidate_entry: Dictionary = resolved.entry.duplicate(true)
	for field: String in candidate_entry.keys():
		if field.begins_with("_"):
			candidate_entry.erase(field)
	candidate_entry.seed = 8675309
	var catalog: ContentCatalog = _catalog(directory, "fixed-levels", {"doku/level_catalog": table, "doku/levels/bankdata4x4": {"1": [candidate_entry]}})
	_check(catalog.validate_all(validator.validation()).ok, "candidate cross-table validation uses candidate bank")
	var shortened_special: ContentCatalog = _catalog(directory, "short-special", {"doku/levels/bankdatasp": {"levels": [candidate_entry]}})
	_check(not shortened_special.validate_all(validator.validation()).ok, "bank-only release cannot break inherited builtin special-level references")
	var partial_policy: ContentCatalog = _catalog(directory, "partial-special", {"doku/policy": {"schema": 1, "draft_unlock_level": 35}, "doku/levels/bankdatasp": {"levels": [candidate_entry]}})
	_check(not partial_policy.validate_all(validator.validation()).ok, "partial policy still validates inherited special-level references")
	var ab_special: ContentCatalog = _catalog(directory, "ab-special", {"doku/policy": {"schema": 1, "special_levels": {}}, "doku/levels/bankdatasp": {"levels": [candidate_entry]}})
	_check(str(ab_special.validate_all(validator.validation()).get("error", "")).begins_with("level10_sp57:"), "bank update preserves existing experimental SP57 consumer")
	var fixed_special: ContentCatalog = _catalog(directory, "fixed-special", {"doku/policy": {"schema": 1, "special_levels": {"10": {"source": "sp", "index": 999}}}, "doku/level_catalog": {"schema": 1, "levels": {"10": definition}}, "doku/levels/bankdatasp": {"levels": [candidate_entry]}})
	_check(fixed_special.validate_all(validator.validation()).ok, "fixed definition takes precedence over unused special and AB references just as at runtime")
	ContentContext.publish(catalog)
	var actual: Dictionary = DokuLevelCatalog.resolve(21)
	_check(actual.ok and actual.found and int(actual.entry.seed) == 8675309, "runtime reads the validated candidate bank")
	_check(actual.entry._definition_provenance.release == "fixed-levels", "definition provenance separate from bank provenance")
	_check(not DokuLevelCatalog.resolve(22).found, "undeclared level keeps existing selection")
	var game: Node = root.get_node("GameState")
	game.set_current_level(21)
	var before: Dictionary = game.get_core_candidate()
	var plan: Dictionary = levels.resolve_level_entry(21, 9, 17)
	_check(plan.ok and plan.size == 4 and plan.entry.regionMap == resolved.entry.regionMap, "fixed definition overrides random size selection")
	_check(plan.next_selection.profile.get("bank_progress", {}) == before.profile.get("bank_progress", {}), "fixed level does not consume ordinary bank cursor")
	_check(game.get_core_store().snapshot().profile.get("bank_progress", {}) == before.profile.get("bank_progress", {}), "resolution is read-only")
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var ui: Node = root.get_node("UIManager")
	var page: Variant = ui.show_ui("game", {"level_index": 21})
	await create_timer(0.5).timeout
	_check(page._entry_error.is_empty() and page._level_config.size == 4, "actual game entry accepts fixed level")
	_check(page._lives == 2 and page._round_policy.draft_unlock_level == 5, "configured initial lives and draft threshold reach actual consumers")
	_check(page._board_view.get_board()[0][int(resolved.entry.solution[0])] == CellState.CAT, "configured prefill reaches actual board")
	_check(JSON.stringify(page._level_config.level_definition) == JSON.stringify(definition), "reward/media/rule definition remains in round context")
	_check(JSON.stringify(page._build_endgame_snapshot().level_definition) == JSON.stringify(definition), "checkpoint carries exact original definition")
	ui.hide_ui("game")
	await create_timer(0.3).timeout
	ContentContext.publish(null)
	page = ui.show_ui("game", {"level_index": 21})
	await create_timer(0.5).timeout
	_check(_same_json(page._puzzle.regions, resolved.entry.regionMap) and _same_json(page._level_config.level_definition, definition), "restore survives active catalog removal without reselecting or dropping rewards")
	ui.hide_ui("game")
	await create_timer(0.3).timeout
	_check_generation_cache(definition)
	_check_large_catalog(directory, definition)
	ContentContext.publish(null)
	print("LEVEL CATALOG TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_generation_cache(definition: Dictionary) -> void:
	var provider := CountingCatalog.new({"schema": 1, "levels": {"21": definition.duplicate(true)}})
	ContentContext.publish(provider)
	var selected: Dictionary = DokuLevelCatalog.resolve(21)
	_check(selected.ok and selected.found, "cache resolves selected definition")
	selected.entry._level_definition.reward.hint = 99
	selected.entry.regionMap[0][0] = 99
	var next: Dictionary = DokuLevelCatalog.resolve(21)
	_check(next.entry._level_definition.reward.hint == 2 and next.entry.regionMap[0][0] != 99, "returned puzzle and definition cannot mutate the private catalog")
	for level: int in range(100, 110):
		_check(not DokuLevelCatalog.resolve(level).found, "cache preserves undeclared-level fallback")
	_check(provider.reads == 1, "one generation reads and copies the whole catalog only once")
	provider.value.levels["21"].reward.hint = 3
	provider.release = "counted-b"
	ContentContext.publish(provider)
	selected = DokuLevelCatalog.resolve(21)
	_check(selected.entry._level_definition.reward.hint == 3 and selected.entry._definition_provenance.release == "counted-b", "republishing the same provider refreshes definitions and provenance")
	_check(provider.reads == 2, "new generation reads the catalog exactly once again")
	provider.value.schema = 2
	ContentContext.publish(provider)
	var rejected: Dictionary = DokuLevelCatalog.resolve(21)
	_check(not rejected.ok and rejected.error == "level_catalog_schema", "invalid catalog cannot reuse an earlier valid generation")
	rejected.ok = true
	rejected.error = "caller mutation"
	var again: Dictionary = DokuLevelCatalog.resolve(999)
	_check(not again.ok and again.error == "level_catalog_schema" and provider.reads == 3, "cached rejection is stable and cannot be overwritten by callers")
	_check(ContentContext.content_error().get("logical_id") == DokuLevelCatalog.ID, "invalid cached generation retains content failure diagnostics")
	ContentContext.publish(null)
	_check(not DokuLevelCatalog.resolve(21).found and ContentContext.content_error().is_empty(), "removing a catalog clears both old definitions and old diagnostics")


func _check_large_catalog(directory: String, definition: Dictionary) -> void:
	var table: Dictionary = {"schema": 1, "levels": {}}
	for level: int in range(1, 10001):
		table.levels[str(level)] = definition.duplicate(true)
	var provider: ContentCatalog = _catalog(directory, "large-catalog", {DokuLevelCatalog.ID: table})
	ContentContext.publish(provider)
	var start: int = Time.get_ticks_usec()
	var first: Dictionary = DokuLevelCatalog.resolve(10001)
	var first_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	var times: Array[float] = []
	for _index: int in range(21):
		start = Time.get_ticks_usec()
		var result: Dictionary = DokuLevelCatalog.resolve(10001)
		times.append(float(Time.get_ticks_usec() - start) / 1000.0)
		_check(result.ok and not result.found, "large catalog repeated lookup preserves fallback")
	times.sort()
	_check(first.ok and not first.found and DokuLevelCatalog.resolve(10000).found, "maximum-size catalog remains usable")
	var external: Dictionary = ContentContext.read_json(DokuLevelCatalog.ID)
	external.value.levels.clear()
	_check(DokuLevelCatalog.resolve(10000).found and ContentContext.read_json(DokuLevelCatalog.ID).value.levels.size() == 10000, "ordinary content reads still return independent copies")
	print("PERFORMANCE_RESULT=level_catalog entries=10000 cold_ms=%.3f cached_missing_p50_ms=%.3f" % [first_ms, times[times.size() / 2]])


func _catalog(directory: String, release: String, values: Dictionary) -> ContentCatalog:
	directory = directory.path_join(release)
	DirAccess.make_dir_recursive_absolute(directory)
	var entries: Array = []
	for id: String in values:
		var filename: String = id.replace("/", "_") + ".json"
		var path: String = directory.path_join(filename)
		var file := FileAccess.open(path, FileAccess.WRITE)
		var bytes: PackedByteArray = JSON.stringify(values[id]).to_utf8_buffer()
		file.store_buffer(bytes)
		file.close()
		entries.append({"id": id, "path": filename, "kind": "json", "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)})
	return ContentCatalog.new(directory, {"release": release, "files": entries})


func _same_json(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
