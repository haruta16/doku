## 可选的精确关卡定义。未声明关卡沿用既有选题；声明后缺题即拒绝，不悄悄换题。
class_name DokuLevelCatalog
extends RefCounted

const ID: String = "doku/level_catalog"
const Definition = preload("res://products/meowdoku/gameplay/domain/doku_level_definition.gd")
const BOARD_MEDIA_SLOTS: Array[String] = Definition.BOARD_MEDIA_SLOTS
const Core = preload("res://products/meowdoku/gameplay/domain/queendoku_core.gd")
const Banks = preload("res://products/meowdoku/gameplay/content/level_bank_io.gd")

# read_json 返回的独立副本仅由本类持有；内容代次变化才重新读取并验证整表。
static var _cached_generation: int = -1
static var _cached_catalog: Dictionary = {}


static func validate(value: Variant) -> bool:
	return bool(inspect(value).ok)


static func inspect(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 2:
		return _invalid("$", "expected schema and levels")
	if not _integer(value.get("schema")) or int(value.schema) != 1:
		return _invalid("$.schema", "expected schema 1")
	if not value.get("levels") is Dictionary or value.levels.size() > 10000:
		return _invalid("$.levels", "expected at most 10000 fixed level definitions")
	for key: Variant in value.levels:
		var path: String = "$.levels[" + JSON.stringify(key) + "]"
		if not key is String or not key.is_valid_int() or int(key) < 1 or str(int(key)) != key:
			return _invalid(path, "expected a positive canonical level number")
		var checked: Dictionary = inspect_definition(value.levels[key])
		if not checked.ok:
			return _invalid(path + str(checked.path).trim_prefix("$"), checked.detail)
	return {"ok": true, "error": ""}


static func validate_definition(value: Variant) -> bool:
	return bool(inspect_definition(value).ok)


static func inspect_definition(value: Variant) -> Dictionary:
	var checked: Dictionary = Definition.inspect(value)
	if not checked.ok:
		return checked
	# 发布与开局还要求媒体槽位已接入当前客户端；冻结后的业务结算仅用纯契约。
	var known: Dictionary = slot_kinds()
	for slot: String in value.get("media", {}):
		if not known.has(slot):
			return _invalid("$.media[" + JSON.stringify(slot) + "]", "board slot is not bound by this client")
	return {"ok": true, "error": ""}


static func _invalid(path: String, detail: String) -> Dictionary:
	return {"ok": false, "path": path, "detail": detail}


static func slot_kinds() -> Dictionary:
	var result: Dictionary = {}
	for binding: Dictionary in ContentSceneBindings.registry().values():
		if binding.slot in Definition.BOARD_MEDIA_SLOTS:
			result[binding.slot] = binding.kind
	return result


## provider 只读取指定候选目录；未覆盖的文件回到客户端内置题库。
static func resolve_definition(definition: Dictionary, provider: Callable) -> Dictionary:
	if not validate_definition(definition):
		return _failure("level_definition_schema")
	var puzzle: Dictionary = definition.puzzle
	var loaded: Dictionary = provider.call(str(puzzle.bank))
	if not loaded.get("ok", false) and loaded.get("error") == "unknown_content":
		loaded = Banks.builtin_by_id(str(puzzle.bank))
	if not loaded.get("ok", false):
		return loaded
	var data: Variant = loaded.value
	var entries: Array = []
	if data is Array and not puzzle.has("rank"):
		entries = data
	elif data is Dictionary:
		if data.get("levels") is Array and not puzzle.has("rank"):
			entries = data.levels
		elif puzzle.has("rank") and data.get(str(int(puzzle.rank))) is Array:
			entries = data[str(int(puzzle.rank))]
	var index: int = int(puzzle.index) - 1
	if index < 0 or index >= entries.size() or not entries[index] is Dictionary:
		return _failure("level_reference_missing:" + str(puzzle.bank))
	var entry: Dictionary = BankData.materialize_entry(entries[index], true)
	if not entry.get("regionMap") is Array:
		return _failure("level_reference_invalid:" + str(puzzle.bank))
	var size: int = entry.regionMap.size()
	if not _valid_entry_shape(entry, size) or not Core.validate_solution_entry(entry, size):
		return _failure("level_reference_invalid:" + str(puzzle.bank))
	for cell: Array in definition.get("prefill", []):
		if int(cell[0]) >= size or int(cell[1]) >= size or int(entry.solution[int(cell[0])]) != int(cell[1]):
			return _failure("level_prefill_invalid")
	entry["size"] = size
	entry["_bank_source"] = "catalog"
	entry["_bank_idx"] = index + 1
	entry["_bank_rank"] = int(puzzle.get("rank", entry.get("r", entry.get("maxR", 1))))
	entry["_level_definition"] = definition.duplicate(true)
	entry["_content_provenance"] = {"logical_id": str(puzzle.bank), "release": str(loaded.get("release", "builtin")), "fallback_error": ""}
	return {"ok": true, "found": true, "entry": entry}


static func resolve(level: int) -> Dictionary:
	var loaded: Dictionary = _current_catalog()
	if not loaded.get("ok", false):
		if loaded.get("error") == "unknown_content":
			return {"ok": true, "found": false}
		return loaded.duplicate(true)
	var definition: Dictionary = loaded.value.levels.get(str(level), {})
	if definition.is_empty():
		return {"ok": true, "found": false}
	var result: Dictionary = resolve_definition(definition, ContentContext.read_json)
	if not result.get("ok", false):
		ContentContext.report_content_error(ID, str(result.get("error", "level_reference")))
	else:
		result.entry["_definition_provenance"] = {"logical_id": ID, "release": str(loaded.release)}
	return result


static func _current_catalog() -> Dictionary:
	var generation: int = ContentContext.generation()
	if _cached_generation != generation:
		var loaded: Dictionary = ContentContext.read_json(ID)
		if loaded.get("ok", false) and not validate(loaded.value):
			ContentContext.report_content_error(ID, "level_catalog_schema")
			loaded = _failure("level_catalog_schema")
		_cached_catalog = loaded
		_cached_generation = generation
	return _cached_catalog


static func validate_references(value: Dictionary, provider: Callable, media: Dictionary = {}) -> Dictionary:
	if not validate(value):
		return _failure("level_catalog_schema")
	var kinds: Dictionary = slot_kinds()
	for level: String in value.levels:
		var definition: Dictionary = value.levels[level]
		var resolved: Dictionary = resolve_definition(definition, provider)
		if not resolved.get("ok", false):
			return _failure("level_" + level + ":" + str(resolved.error))
		for source: String in definition.get("media", {}):
			var target: String = definition.media[source]
			if not media.get(kinds[source], {}).has(target):
				return _failure("level_media_missing:" + target)
	return {"ok": true}


static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value)


static func _valid_entry_shape(entry: Dictionary, size: int) -> bool:
	if size < 4 or size > 12 or not entry.get("solution") is Array or entry.solution.size() != size:
		return false
	for row: Variant in entry.regionMap:
		if not row is Array or row.size() != size:
			return false
		for region: Variant in row:
			if not _integer(region) or region < 0 or region >= size:
				return false
	for col: Variant in entry.solution:
		if not _integer(col) or col < 0 or col >= size:
			return false
	return true


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
