# 下载内容的玩法校验：不访问页面、玩家状态或 AB，也不修改原始题目。
class_name DokuContentValidator
extends RefCounted

const Validation = preload("res://scripts/framework/content/content_validation.gd")

const MainRules = preload("res://products/meowdoku/gameplay/domain/doku_main_selection_rules.gd")
const Core = preload("res://products/meowdoku/gameplay/domain/queendoku_core.gd")


## 单题/工具沿用 bool 入口；发布链使用 inspect 的字段诊断及完整校验合同。
static func validate(logical_id: String, value: Variant) -> bool:
	return bool(inspect(logical_id, value).ok)


static func validation() -> Validation:
	return Validation.new(inspect, validate_catalog, validate_media)


static func inspect(logical_id: String, value: Variant) -> Dictionary:
	if logical_id == "media":
		return _inspection_result(logical_id, ContentMediaMap.inspect(value))
	if logical_id == "doku/policy":
		return _inspection_result(logical_id, _inspect_policy(value))
	if logical_id == DokuLevelCatalog.ID:
		return _inspection_result(logical_id, DokuLevelCatalog.inspect(value))
	if not logical_id.begins_with("doku/levels/"):
		return _invalid(logical_id, "$", "unsupported logical content id")
	var filename := logical_id.trim_prefix("doku/levels/")
	if filename.ends_with(".pace"):
		return _inspect_pace(logical_id, value)
	var expected_size := 0
	var dimensions := RegEx.new()
	dimensions.compile("^bankdata(?:gc|lkstyle|onefish)?([0-9]+)x([0-9]+)$")
	var matched := dimensions.search(filename)
	if matched != null:
		if matched.get_string(1) != matched.get_string(2):
			return _invalid(logical_id, "$", "bank dimensions must be square")
		expected_size = int(matched.get_string(1))
	var groups: Array = []
	var is_gc: bool = matched != null and filename.begins_with("bankdatagc")
	if filename == "bankdatalk" and value is Array:
		groups.append({"path": "$", "entries": value})
	elif (is_gc or filename.begins_with("bankdataonefish") or filename in ["bankdatalkmodified", "bankdatasp", "bankdatadigitssp", "bankdatahardr4", "bankdatasuperhard", "bankdatasuperhardr4", "bankdatasp_tt", "bankdatasingleregion", "bankdataclimaxfilters", "bankdatacolorchallenge"]) and value is Dictionary:
		if not value.get("levels") is Array or (value.size() != 1 and filename != "bankdataclimaxfilters"):
			return _invalid(logical_id, "$.levels", "expected a levels array and no other root fields")
		groups.append({"path": "$.levels", "entries": value.levels})
	elif matched != null and value is Dictionary:
		for key: Variant in value:
			var path: String = "$[" + JSON.stringify(key) + "]"
			if str(key) not in ["1", "2", "3", "4", "5"]:
				return _invalid(logical_id, path, "unsupported difficulty rank")
			if not value[key] is Array:
				return _invalid(logical_id, path, "expected a puzzle array")
			groups.append({"path": path, "entries": value[key]})
	else:
		return _invalid(logical_id, "$", "invalid bank shape or logical id")
	var count: int = 0
	for group: Dictionary in groups:
		var entries: Array = group.entries
		for index: int in entries.size():
			var entry: Variant = BankData.materialize_entry(entries[index], true) if entries[index] is Dictionary else entries[index]
			var path: String = str(group.path) + "[%d]" % index
			if not entry is Dictionary or not entry.get("regionMap") is Array:
				return _invalid(logical_id, path + ".regionMap", "expected a puzzle with a regionMap array")
			if is_gc and (not _integer(entry.get("r")) or int(entry.r) not in [1, 2, 3, 4, 5]):
				return _invalid(logical_id, path + ".r", "GC difficulty must be an integer from 1 to 5")
			var size: int = entry.regionMap.size()
			if size < 4 or size > 12 or (expected_size != 0 and size != expected_size):
				return _invalid(logical_id, path + ".regionMap", "board size does not match the supported bank dimensions")
			if not entry.get("solution") is Array or entry.solution.size() != size:
				return _invalid(logical_id, path + ".solution", "expected one answer column per row")
			var metadata: Dictionary = _entry_metadata_error(entry, size)
			if not metadata.is_empty():
				return _invalid(logical_id, path + str(metadata.path), str(metadata.detail))
			for row_index: int in size:
				var row: Variant = entry.regionMap[row_index]
				if not row is Array or row.size() != size:
					return _invalid(logical_id, path + ".regionMap[%d]" % row_index, "expected a square board row")
				for col_index: int in size:
					var region: Variant = row[col_index]
					if not _integer(region) or region < 0 or region >= size:
						return _invalid(logical_id, path + ".regionMap[%d][%d]" % [row_index, col_index], "region must be an integer within board bounds")
			for index_in_solution: int in size:
				var col: Variant = entry.solution[index_in_solution]
				if not _integer(col) or col < 0 or col >= size:
					return _invalid(logical_id, path + ".solution[%d]" % index_in_solution, "answer column must be an integer within board bounds")
			if not Core.validate_solution_entry(entry, size):
				return _invalid(logical_id, path + ".solution", "answer violates Doku rules or region coverage")
			count += 1
	return _schema_result(logical_id, count > 0, "$", "bank must contain at least one puzzle")


static func _inspection_result(logical_id: String, checked: Dictionary) -> Dictionary:
	return checked if checked.ok else _invalid(logical_id, checked.path, checked.detail)


static func _schema_result(logical_id: String, valid: bool, path: String, detail: String) -> Dictionary:
	return {"ok": true, "error": ""} if valid else _invalid(logical_id, path, detail)


static func _invalid(logical_id: String, path: String, detail: String) -> Dictionary:
	return {"ok": false, "error": "content_schema:" + logical_id, "logical_id": logical_id, "path": path, "detail": detail}


## 候选目录与内置数据组合验证，绝不读取当前活动版本来补齐另一候选的引用。
static func validate_catalog(catalog: RefCounted) -> Dictionary:
	# 同一轮校验只解析一次内置依赖，避免大型表的每个引用都重新读盘。
	var banks: Dictionary = {}
	var provider := func(logical_id: String) -> Dictionary:
		if not banks.has(logical_id):
			var loaded: Dictionary = catalog.read_json(logical_id)
			if not loaded.get("ok", false) and loaded.get("error") == "unknown_content":
				loaded = LevelBankIO.builtin_by_id(logical_id)
			banks[logical_id] = loaded
		return banks[logical_id]
	for file: Dictionary in catalog.manifest_snapshot().get("files", []):
		var logical_id: String = str(file.get("id", ""))
		if not logical_id.begins_with("doku/levels/") or not logical_id.ends_with(".pace"):
			continue
		var pace: Dictionary = provider.call(logical_id)
		var main: Dictionary = provider.call(logical_id.trim_suffix(".pace"))
		if not pace.get("ok", false) or not main.get("ok", false) or not main.get("value") is Dictionary:
			return _invalid(logical_id, "$", "pace requires an available main bank")
		for partition: Variant in main.value:
			if not main.value[partition] is Array:
				continue
			if not pace.value.get(partition) is Array or pace.value[partition].size() != main.value[partition].size():
				return _invalid(logical_id, "$", "pace index count differs from main bank")
	var media: Dictionary = {}
	var media_result: Dictionary = catalog.read_json("media")
	if media_result.get("ok", false):
		media = media_result.value
	var definitions: Dictionary = catalog.read_json(DokuLevelCatalog.ID)
	var fixed_levels: Dictionary = definitions.value.get("levels", {}) if definitions.get("ok", false) else {}
	if definitions.get("ok", false):
		var checked: Dictionary = DokuLevelCatalog.validate_references(definitions.value, provider, media)
		if not checked.get("ok", false):
			return checked
	elif definitions.get("error") != "unknown_content":
		return definitions
	var policy: Dictionary = catalog.read_json("doku/policy")
	if not policy.get("ok", false) and policy.get("error") != "unknown_content":
		return policy
	# 即使只更新题库或策略的一部分，未覆盖的特殊关仍来自内置策略。
	var effective_policy: Dictionary = DokuPolicy.merge_builtin(policy.value if policy.get("ok", false) else {})
	for level: String in effective_policy.get("special_levels", {}):
		if fixed_levels.has(level):
			continue
		var target: Dictionary = effective_policy.special_levels[level]
		var definition: Dictionary = {"puzzle": {"bank": "doku/levels/bankdata" + str(target.source), "index": int(target.index)}}
		var checked: Dictionary = DokuLevelCatalog.resolve_definition(definition, provider)
		if not checked.get("ok", false):
			return {"ok": false, "error": "special_level_" + level + ":" + str(checked.error)}
	# 既有第10关 AB 可以选择 SP 第57题；候选不能破坏客户端仍支持的这条入口。
	if not fixed_levels.has("10"):
		var ab_reference: Dictionary = DokuLevelCatalog.resolve_definition({"puzzle": {"bank": "doku/levels/bankdatasp", "index": 57}}, provider)
		if not ab_reference.get("ok", false):
			return {"ok": false, "error": "level10_sp57:" + str(ab_reference.error)}
	var daily: Dictionary = _validate_daily_pools(provider)
	if not daily.get("ok", false):
		return daily
	return _validate_main_pools(provider, effective_policy, fixed_levels)


## 与 DailyGamePage / DcLevelConfig 的现有控制组及实验组消费者一致。
## 只约束确实会使用的池；其他尺寸/难度仍可按产品需要省略。
const DAILY_POOLS: Array = [
	{"bank": "bankdata10x10", "ranks": [3, 4]},
	{"bank": "bankdata12x12", "ranks": [3, 4, 5]},
	{"bank": "bankdatagc10x10", "ranks": [3, 4, 5]},
	{"bank": "bankdatagc12x12", "ranks": [3, 4, 5]},
	{"bank": "bankdatalkstyle12x12", "ranks": [4], "tier": "N"},
]


static func _validate_daily_pools(provider: Callable) -> Dictionary:
	for requirement: Dictionary in DAILY_POOLS:
		var logical_id: String = "doku/levels/" + str(requirement.bank)
		var loaded: Dictionary = provider.call(logical_id)
		if not loaded.get("ok", false):
			return loaded
		var value: Dictionary = loaded.value
		for rank: int in requirement.ranks:
			var tier: String = str(requirement.get("tier", ""))
			var gc: bool = str(requirement.bank).begins_with("bankdatagc")
			var entries: Array = value.get("levels", []) if gc else value.get(str(rank), [])
			var found: bool = false
			for entry: Dictionary in entries:
				if gc and int(entry.get("r", 0)) != rank:
					continue
				if not tier.is_empty() and entry.get("tier", "") != tier:
					continue
				found = true
				break
			if not found:
				return {"ok": false, "error": "daily_pool_missing", "logical_id": logical_id,
					"path": "$.levels[r=%d]" % rank if gc else "$[%s]" % JSON.stringify(str(rank)),
					"rank": rank, "tier": tier, "detail": "daily challenge requires a nonempty pool"}
	return {"ok": true, "error": ""}


## 分段内难度仅依赖尾数，尺寸循环周期为 sizes.size()。
## 枚举二者最小公倍数内的代表，且跨越有限的固定/特殊关覆盖；不截断到任意前 N 关。
static func _main_representatives(policy: Dictionary, fixed: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var covered: Dictionary = policy.get("special_levels", {}).duplicate()
	covered.merge(fixed, true)
	for group: String in MainRules.SIZE_GROUPS:
		var segments: Array = policy.size_cycles[group]
		for segment_index: int in segments.size():
			var segment: Dictionary = segments[segment_index]
			var start: int = int(segment.from)
			var end: int = int(segments[segment_index + 1].from) - 1 if segment_index + 1 < segments.size() else 9223372036854775807
			var length: int = segment.sizes.size()
			var period: int = length * 10 / _gcd(length, 10)
			for stage_index: int in MainRules.STAGE_STARTS.size():
				var lower: int = maxi(start, MainRules.STAGE_STARTS[stage_index])
				var upper: int = mini(end, MainRules.STAGE_STARTS[stage_index + 1] - 1) if stage_index + 1 < MainRules.STAGE_STARTS.size() else end
				if lower > upper:
					continue
				var seen: Dictionary = {}
				for phase: int in mini(period, upper - lower + 1):
					var level: int = lower + phase
					var size: int = int(segment.sizes[(level - start) % length])
					var key: String = "%d/%d" % [size, level % 10]
					if seen.has(key):
						continue
					while covered.has(str(level)):
						if upper - level < period:
							level = 0
							break
						level += period
					if level == 0:
						continue
					seen[key] = true
					result.append({"level": level, "size": size, "group": group})
	return result


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var next: int = a % b
		a = b
		b = next
	return a


static func _bank_rank(provider: Callable, prefix: String, size: int, rank: int) -> Array:
	var loaded: Dictionary = provider.call("doku/levels/bankdata%s%dx%d" % [prefix, size, size])
	if not loaded.get("ok", false):
		return []
	var value: Dictionary = loaded.value
	if prefix == "gc":
		return value.get("levels", []).filter(func(entry: Dictionary) -> bool: return int(entry.get("r", 0)) == rank)
	return value.get(str(rank), [])


static func _validate_main_pools(provider: Callable, policy: Dictionary, fixed: Dictionary) -> Dictionary:
	var verified: Dictionary = {}
	for sample: Dictionary in _main_representatives(policy, fixed):
		for group: int in MainRules.RULE_GROUPS:
			if (sample.group == "base" and group == 10) or (sample.group == "j" and group != 10):
				continue
			for choice: Dictionary in MainRules.possibilities(sample.level, group):
				var size: int = sample.size
				var rank: int = choice.rank
				var key: String = "%d/%d/%s/%s/%s" % [size, rank, choice.tier, sample.level >= 51, choice.hard]
				if verified.has(key):
					continue
				var regular: Array = _bank_rank(provider, "", size, rank)
				var style: Array = _bank_rank(provider, "lkstyle", size, rank)
				var gc: Array = _bank_rank(provider, "gc", size, rank) if (size == 10 and rank == 1) or size == 11 else []
				var tier: String = choice.tier if choice.hard else MainRules.normal_tier(choice.tier, regular, style)
				var pools: Dictionary = MainRules.cycling_pools(size, rank, tier, sample.level >= 51, regular, style, gc)
				var usable: bool = false
				for entries: Array in pools.values():
					for entry: Dictionary in entries:
						if Core.validate_solution_entry(BankData.materialize_entry(entry), size):
							usable = true
							break
					if usable:
						break
				if not usable:
					return {"ok": false, "error": "main_pool_missing", "logical_id": "doku/policy",
						"path": "$.size_cycles." + str(sample.group), "level": sample.level, "rule_group": group,
						"size": size, "rank": rank, "tier": tier, "detail": "reachable main selection requires a valid cycling pool; finite LK supplements may already be exhausted"}
				verified[key] = true
	return {"ok": true, "error": ""}


## 此检查必须在挂包后执行；失败由试启动协议要求重启并回退。
static func validate_media(catalog: RefCounted) -> Dictionary:
	var checked: Dictionary = ContentSceneBindings.validate_media(catalog)
	if not checked.get("ok", false):
		return checked
	var definitions: Dictionary = catalog.read_json(DokuLevelCatalog.ID)
	if definitions.get("ok", false):
		for definition: Dictionary in definitions.value.get("levels", {}).values():
			checked = ContentSceneBindings.validate_media(catalog, definition.get("media", {}))
			if not checked.get("ok", false):
				return checked
	return {"ok": true}


static func _inspect_policy(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _policy_error("$", "expected a policy object")
	if not _integer(value.get("schema")) or int(value.schema) != 1:
		return _policy_error("$.schema", "expected schema 1")
	for key: Variant in value:
		if not key is String or key not in ["schema", "size_cycles", "special_levels", "draft_unlock_level"]:
			return _policy_error("$[" + JSON.stringify(key) + "]", "unsupported policy field")
	if value.has("draft_unlock_level"):
		var threshold: Variant = value.draft_unlock_level
		if not _integer(threshold) or threshold < 1 or threshold > 10000:
			return _policy_error("$.draft_unlock_level", "expected an integer from 1 to 10000")
	if value.has("special_levels"):
		if not value.special_levels is Dictionary:
			return _policy_error("$.special_levels", "expected a level-to-reference object")
		for level: Variant in value.special_levels:
			var path: String = "$.special_levels[" + JSON.stringify(level) + "]"
			var item: Variant = value.special_levels[level]
			if not level is String or not level.is_valid_int() or int(level) < 1 or str(int(level)) != level:
				return _policy_error(path, "expected a positive canonical level number")
			if not item is Dictionary or item.size() != 2:
				return _policy_error(path, "expected source and index")
			if item.get("source") not in ["sp", "lk"]:
				return _policy_error(path + ".source", "expected sp or lk")
			if not _integer(item.get("index")) or item.index < 1:
				return _policy_error(path + ".index", "expected a positive one-based index")
	if value.has("size_cycles"):
		if not value.size_cycles is Dictionary:
			return _policy_error("$.size_cycles", "expected a group-to-segments object")
		for group: Variant in value.size_cycles:
			var path: String = "$.size_cycles[" + JSON.stringify(group) + "]"
			if str(group) not in ["base", "j", "2", "3", "4", "5", "6", "7", "8"]:
				return _policy_error(path, "unsupported size group")
			var segments: Variant = value.size_cycles[group]
			if not segments is Array or segments.is_empty():
				return _policy_error(path, "expected a nonempty segment array")
			var previous: int = 0
			for index: int in segments.size():
				var segment: Variant = segments[index]
				var segment_path: String = path + "[%d]" % index
				if not segment is Dictionary or segment.size() != 2:
					return _policy_error(segment_path, "expected from and sizes")
				if not _integer(segment.get("from")) or int(segment.from) <= previous or (previous == 0 and int(segment.from) != 1):
					return _policy_error(segment_path + ".from", "segments must start at 1 and increase strictly")
				previous = int(segment.from)
				var sizes: Variant = segment.get("sizes")
				if not sizes is Array or sizes.is_empty() or sizes.size() > 10000:
					return _policy_error(segment_path + ".sizes", "expected 1 to 10000 board sizes")
				for size_index: int in sizes.size():
					if not _integer(sizes[size_index]) or int(sizes[size_index]) < 4 or int(sizes[size_index]) > 12:
						return _policy_error(segment_path + ".sizes[%d]" % size_index, "expected an integer board size from 4 to 12")
	return {"ok": true, "error": ""}


static func _policy_error(path: String, detail: String) -> Dictionary:
	return {"ok": false, "path": path, "detail": detail}


## 棋盘之外的这些字段也会被页面直接读取，不能只验证题面而放过类型错误。
static func _entry_metadata_error(entry: Dictionary, size: int) -> Dictionary:
	# 来源注记会由读取口重写；选题/关卡业务字段只允许客户端自己组装。
	for field: Variant in entry:
		if not field is String or (field.begins_with("_") and field not in ["_content_provenance", "_pid_h", "_pid_s", "_source_file"]):
			return {"path": "[" + JSON.stringify(field) + "]", "detail": "reserved or invalid metadata key"}
	if entry.has("_pid_h") and (not entry._pid_h is String or entry._pid_h.length() != 16 or not entry._pid_h.is_valid_hex_number(false)):
		return {"path": "._pid_h", "detail": "expected a 16 character canonical hash"}
	if entry.has("_pid_s"):
		if not entry._pid_s is Array or entry._pid_s.size() != 8:
			return {"path": "._pid_s", "detail": "expected eight transform suffixes"}
		for suffix: Variant in entry._pid_s:
			if not _integer(suffix) or int(suffix) < 0 or int(suffix) > 7:
				return {"path": "._pid_s", "detail": "invalid transform suffix"}
	if entry.has("_source_file") and not entry._source_file is String:
		return {"path": "._source_file", "detail": "expected source label"}
	for field: String in ["rating", "ratingV2", "eloRating", "maxRegionFrac"]:
		if entry.has(field) and (typeof(entry[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(entry[field]))):
			return {"path": "." + field, "detail": "expected a finite rating"}
	if entry.has("size") and (not _integer(entry.size) or int(entry.size) != size):
		return {"path": ".size", "detail": "size must match regionMap dimensions"}
	for field: String in ["seed", "id", "steps", "r1", "r2", "r3", "r4", "r5", "leadR1", "shapeCategory", "singleCount", "transform"]:
		if entry.has(field) and not _integer(entry[field]):
			return {"path": "." + field, "detail": "expected an integer"}
	for field: String in ["r", "maxR", "rank"]:
		if entry.has(field) and (not _integer(entry[field]) or int(entry[field]) not in [1, 2, 3, 4, 5]):
			return {"path": "." + field, "detail": "expected an integer rank from 1 to 5"}
	for field: String in ["tier", "pattern", "date", "label", "filter"]:
		if entry.has(field) and not entry[field] is String:
			return {"path": "." + field, "detail": "expected a string"}
	for field: String in ["isChainedStrategy", "isHiddenSingleL1"]:
		if entry.has(field) and typeof(entry[field]) != TYPE_BOOL:
			return {"path": "." + field, "detail": "expected a boolean"}
	for field: String in ["stepHist", "stepOrderZ"]:
		if not entry.has(field):
			continue
		if not entry[field] is Array or (field == "stepHist" and entry[field].size() != 5):
			return {"path": "." + field, "detail": "invalid style vector shape"}
		for number: Variant in entry[field]:
			if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)) or (field == "stepHist" and (not _integer(number) or number < 0)):
				return {"path": "." + field, "detail": "invalid style vector value"}
	if entry.has("prefill_positions") and not validate_prefill(entry.prefill_positions, entry.get("solution"), size):
		return {"path": ".prefill_positions", "detail": "expected unique in-bounds answer positions"}
	for field: String in ["colorMap", "patternRegions", "spRegion"]:
		if not entry.has(field):
			continue
		if not entry[field] is Array:
			return {"path": "." + field, "detail": "expected an array"}
		if field == "colorMap" and not entry[field].is_empty() and entry[field].size() != size:
			return {"path": ".colorMap", "detail": "color map must match board size"}
		for index: int in entry[field].size():
			var value: Variant = entry[field][index]
			if not _integer(value) or int(value) < 0 or (field in ["patternRegions", "spRegion"] and int(value) >= size):
				return {"path": ".%s[%d]" % [field, index], "detail": "invalid region or color index"}
	return {}


## 预填直接放猫：每项必须是唯一、界内且与本题答案一致的整数坐标。
static func validate_prefill(value: Variant, solution: Variant, size: int) -> bool:
	if not value is Array or value.size() > size or not solution is Array or solution.size() != size:
		return false
	var seen: Dictionary = {}
	for position: Variant in value:
		if not position is Array or position.size() != 2 or not _integer(position[0]) or not _integer(position[1]):
			return false
		var row: int = int(position[0])
		var column: int = int(position[1])
		if row < 0 or row >= size or column < 0 or column >= size or not _integer(solution[row]) or int(solution[row]) != column:
			return false
		var cell := Vector2i(row, column)
		if seen.has(cell):
			return false
		seen[cell] = true
	return true


static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value)


## 节奏旁表按主题库的分区与索引对齐；不把旁表误当成普通题目。
static func _inspect_pace(logical_id: String, value: Variant) -> Dictionary:
	if not value is Dictionary or value.is_empty():
		return _invalid(logical_id, "$", "expected pace partitions")
	for partition: Variant in value:
		if str(partition) not in ["levels", "1", "2", "3", "4", "5"] or not value[partition] is Array:
			return _invalid(logical_id, "$", "invalid pace partition")
		for row: Variant in value[partition]:
			if not row is Dictionary:
				return _invalid(logical_id, "$", "invalid pace row")
			for key: String in ["g1", "g2", "g3", "g4"]:
				if typeof(row.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(row[key])):
					return _invalid(logical_id, "$", "invalid pace scalar " + key)
			for key: String in ["hint_click_seq", "r_seq"]:
				if not row.get(key) is Array:
					return _invalid(logical_id, "$", "invalid pace vector " + key)
				for number: Variant in row[key]:
					if not _integer(number) or int(number) < 0 or int(number) > 5:
						return _invalid(logical_id, "$", "invalid pace strategy")
	return {"ok": true, "error": ""}
