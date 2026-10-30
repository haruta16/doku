## 候选发布必须保留真实每日消费者的题池；元数据错误带字段位置，显式回调不丢目录/媒体校验。
extends SceneTree

var checks: int = 0
var failures: int = 0
var _fixture: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	_test_daily_pools()
	_test_main_pools()
	_test_main_periods()
	_test_experiment_contract()
	_test_metadata()
	_test_config_diagnostics()
	_test_real_main_consumer()
	_test_explicit_callbacks()
	print("CONTENT CONSUMER CONTRACT TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_daily_pools() -> void:
	_check(_catalog({}).validate_all(DokuContentValidator.validation()).ok, "builtin fallback satisfies all supported daily pools")
	for requirement: Dictionary in DokuContentValidator.DAILY_POOLS:
		var id: String = "doku/levels/" + str(requirement.bank)
		var builtin: Dictionary = LevelBankIO.builtin_by_id(id).value
		if str(requirement.bank).begins_with("bankdatagc"):
			# 历史内置池允许消费者跳过坏题；候选反例仅保留各档一题已验证的题目。
			var usable: Array = []
			for rank: int in [1, 2, 3, 4, 5]:
				for entry: Dictionary in builtin.levels:
					if int(entry.get("r", 0)) == rank and DokuContentValidator.validate(id, {"levels": [entry]}):
						usable.append(entry)
						break
			builtin = {"levels": usable}
		for rank: int in requirement.ranks:
			var value: Dictionary = builtin.duplicate(true)
			if str(requirement.bank).begins_with("bankdatagc"):
				value.levels = value.levels.filter(func(entry: Dictionary) -> bool: return int(entry.get("r", 0)) != rank)
			else:
				value.erase(str(rank))
			_check(DokuContentValidator.validate(id, value), "remaining individual puzzles are valid: " + id + "/" + str(rank))
			var rejected := _catalog({id: value}).validate_all(DokuContentValidator.validation())
			_check(not rejected.ok and rejected.error == "daily_pool_missing" and rejected.logical_id == id and rejected.rank == rank,
				"whole candidate rejects missing required pool: " + id + "/" + str(rank))
		if requirement.has("tier"):
			var value: Dictionary = builtin.duplicate(true)
			value["4"] = value["4"].filter(func(entry: Dictionary) -> bool: return entry.get("tier", "") != "N")
			var rejected := _catalog({id: value}).validate_all(DokuContentValidator.validation())
			_check(not rejected.ok and rejected.error == "daily_pool_missing" and rejected.tier == "N", "valid H tier cannot replace required N tier")
	# 非每日题库没有无意义的全难度要求。
	var small: Dictionary = LevelBankIO.builtin_by_id("doku/levels/bankdata4x4").value
	_check(_catalog({"doku/levels/bankdata4x4": {"1": [small["1"][0]]}}).validate_all(DokuContentValidator.validation()).ok,
		"unrelated bank may contain only the ranks actually published")


func _test_main_pools() -> void:
	var small: Dictionary = LevelBankIO.builtin_by_id("doku/levels/bankdata4x4").value
	var missing: Dictionary = {"doku/levels/bankdata4x4": {"2": [small["2"][0]]}}
	var result := _catalog(missing).validate_all(DokuContentValidator.validation())
	_check(not result.ok and result.error == "main_pool_missing" and result.level == 1 and result.size == 4 and result.rank == 1,
		"valid rank 2 bank cannot remove the first main level's rank 1")
	var combined: Dictionary = missing.duplicate(true)
	combined["doku/levels/bankdatalkstyle4x4"] = {"1": [small["1"][0]]}
	_check(_catalog(combined).validate_all(DokuContentValidator.validation()).ok, "another eligible source may supply the missing rank")
	combined["doku/levels/bankdatalkstyle4x4"]["1"][0]["tier"] = "H"
	_check(_catalog(combined).validate_all(DokuContentValidator.validation()).ok, "normal N tier may fall back to another tier of the same rank")
	var covered: Dictionary = missing.duplicate(true)
	covered["doku/level_catalog"] = {"schema": 1, "levels": {}}
	for level: String in ["1", "2"]:
		covered["doku/level_catalog"].levels[level] = {"puzzle": {"bank": "doku/levels/bankdata5x5", "rank": 1, "index": 1}}
	_check(_catalog(covered).validate_all(DokuContentValidator.validation()).ok, "fixed levels can replace every reachable use of an otherwise missing pool")
	covered["doku/level_catalog"].levels.erase("2")
	result = _catalog(covered).validate_all(DokuContentValidator.validation())
	_check(not result.ok and result.error == "main_pool_missing" and result.level == 2, "covering the first level cannot hide the next reachable missing pool")
	var late: Dictionary = {"schema": 1, "size_cycles": {"base": [{"from": 1, "sizes": [7]}, {"from": 1000001, "sizes": [4]}]}}
	var candidate: Dictionary = {"doku/policy": late, "doku/levels/bankdata4x4": {"1": [small["1"][0]]}}
	result = _catalog(candidate).validate_all(DokuContentValidator.validation())
	_check(not result.ok and result.error == "main_pool_missing" and result.level >= 1000001 and result.rank > 1,
		"late policy segments are checked beyond any fixed simulation horizon")
	for size_group: String in ["2", "3", "4", "5", "6", "7", "8"]:
		var size_override: Dictionary = {"schema": 1, "size_cycles": {size_group: [{"from": 1, "sizes": [7]}, {"from": 1000001, "sizes": [4]}]}}
		result = _catalog({"doku/policy": size_override, "doku/levels/bankdata4x4": {"1": [small["1"][0]]}}).validate_all(DokuContentValidator.validation())
		_check(not result.ok and result.error == "main_pool_missing" and result.path == "$.size_cycles." + size_group,
			"GamePage size override is covered for AB group " + size_group)
	# 51 关后 regular 10/rank3 被排除；LK 改造题即使存在也可能已被玩家耗尽。
	var style: Dictionary = LevelBankIO.builtin_by_id("doku/levels/bankdatalkstyle10x10").value.duplicate(true)
	style.erase("3")
	result = _catalog({"doku/levels/bankdatalkstyle10x10": style}).validate_all(DokuContentValidator.validation())
	_check(not result.ok and result.error == "main_pool_missing" and result.size == 10 and result.rank == 3 and result.level >= 51,
		"ineligible regular and finite LK sources cannot mask an exhausted cycling pool")
	var gc := {"doku/levels/bankdatagc4x4": {"levels": [small["1"][0]]}}
	gc["doku/levels/bankdatagc4x4"].levels[0]["r"] = 1
	gc.merge(missing)
	result = _catalog(gc).validate_all(DokuContentValidator.validation())
	_check(not result.ok and result.error == "main_pool_missing", "GC in an unsupported size cannot satisfy main selection")


func _test_main_periods() -> void:
	# 与逐关枚举对照一个有限策略区间，尺寸周期 7 与尾数周期 10 不整除。
	var policy: Dictionary = DokuPolicy.merge_builtin({"size_cycles": {"base": [
		{"from": 1, "sizes": [4, 5, 6, 7, 8, 9, 10]}, {"from": 410, "sizes": [8]}]}})
	var fixed: Dictionary = {}
	for level: int in range(201, 279):
		fixed[str(level)] = {}
	var actual: Dictionary = {}
	for sample: Dictionary in DokuContentValidator._main_representatives(policy, fixed):
		if sample.group == "base" and sample.level >= 201 and sample.level < 410:
			actual["%d/%d" % [sample.size, sample.level % 10]] = true
	var expected: Dictionary = {}
	for level: int in range(201, 410):
		if fixed.has(str(level)) or policy.special_levels.has(str(level)):
			continue
		expected["%d/%d" % [policy.size_cycles.base[0].sizes[(level - 1) % 7], level % 10]] = true
	_check(actual == expected, "period representatives cover exactly the reachable size and tail combinations after fixed overrides")
	var rules = DokuMainSelectionRules
	var normal := rules.possibilities(201, 7)
	_check(normal.any(func(choice: Dictionary) -> bool: return choice.rank == 1) and normal.any(func(choice: Dictionary) -> bool: return choice.rank == 3),
		"mod1 choices include random difficulty and daily first-round easing")
	var hard := rules.possibilities(210, 11)
	_check(hard.any(func(choice: Dictionary) -> bool: return choice.tier == "N") and hard.any(func(choice: Dictionary) -> bool: return choice.tier == "H"),
		"K hard levels include both coin outcomes")


func _test_experiment_contract() -> void:
	# 从真实实验规则采集分档边界与完整日期周期，防止校验表和消费者实验漂移。
	var actual: Dictionary = {"bankdata10x10/3/": true, "bankdata10x10/4/": true, "bankdatalkstyle12x12/4/N": true}
	var config: RefCounted = load("res://products/meowdoku/app/features/abtest/config/dc_level_config.gd").new()
	for group: int in [1, 2, 3, 4]:
		config.set_debug_override(group)
		for level: int in [1, 50, 51, 100, 101, 200, 201]:
			for day: int in range(20):
				var size: int = config.get_pool_size(level, day)
				var rank: int = config.get_pool_rank(level, day)
				var bank: String = "bankdata" + ("gc" if config.use_gc_bank(size, day) else "") + "%dx%d" % [size, size]
				actual["%s/%d/" % [bank, rank]] = true
	var declared: Dictionary = {}
	for requirement: Dictionary in DokuContentValidator.DAILY_POOLS:
		for rank: int in requirement.ranks:
			declared["%s/%d/%s" % [requirement.bank, rank, requirement.get("tier", "")]] = true
	_check(actual == declared, "required pools equal the existing control and experimental consumer union")


func _test_metadata() -> void:
	var id: String = "doku/levels/bankdatalk"
	var source: Array = LevelBankIO.builtin_by_id(id).value
	for field: String in ["date", "label"]:
		for invalid: Variant in [{"bad": 1}, ["bad"], 7, null]:
			var value: Array = source.duplicate(true)
			value[0][field] = invalid
			var result := _catalog({id: value}).validate_all(DokuContentValidator.validation())
			_check(not result.ok and result.error == "content_schema:" + id and result.path == "$[0]." + field and not result.detail.is_empty(),
				"consumed metadata rejects wrong type with exact field: " + field)
	var value: Array = source.duplicate(true)
	value[0].erase("date")
	value[0].erase("label")
	_check(_catalog({id: value}).validate_all(DokuContentValidator.validation()).ok, "optional display metadata may be absent")
	value[0].date = "2026-10-27"
	value[0].label = "R3"
	_check(_catalog({id: value}).validate_all(DokuContentValidator.validation()).ok, "valid display strings remain accepted")


func _test_config_diagnostics() -> void:
	var cases: Array = [
		["doku/policy", {"schema": 1, "size_cycles": {"base": [{"from": 1, "sizes": [4, 13]}]}}, '$.size_cycles["base"][0].sizes[1]'],
		["doku/policy", {"schema": 1, "special_levels": {"2": {"source": "sp", "index": 0}}}, '$.special_levels["2"].index'],
		["doku/level_catalog", {"schema": 1, "levels": {"12": {"puzzle": {"bank": "doku/levels/bankdata4x4", "index": 0}}}}, '$.levels["12"].puzzle.index'],
		["doku/level_catalog", {"schema": 1, "levels": {"12": {"puzzle": {"bank": "doku/levels/bankdata4x4", "index": 1}, "reward": {"hint": -1}}}}, '$.levels["12"].reward["hint"]'],
		["media", {"textures": {"game/mark": "../unsafe.png"}}, '$["textures"]["game/mark"]'],
	]
	for test: Array in cases:
		var result := DokuContentValidator.inspect(test[0], test[1])
		_check(not result.ok and result.path == test[2] and not result.detail.is_empty(), "configuration diagnostic points to consumed field: " + str(test[2]))


func _test_real_main_consumer() -> void:
	var levels: Script = load("res://products/meowdoku/gameplay/application/level_data.gd")
	var state: Node = root.get_node("GameState")
	var ab: Node = root.get_node("ABTestManager")
	var page: Node = load("res://products/meowdoku/gameplay/presentation/main/view/game_page.gd").new()
	var initial: Dictionary = state.get_core_candidate()
	initial.profile.current_level = 1
	initial.profile.current_strategy = 1
	initial.profile.bank_progress = {}
	initial.profile.main_bank_progress = {}
	initial.profile.lkmod_progress = {}
	initial.profile.recent_puzzles = []
	_check(state.commit_core_candidate(initial, state.get_core_store().revision()).ok, "isolated real selection fixture commits")
	state.set("_daily_first_easy_available", false)
	ab.rule_normal_rank.set_debug_override(2)
	ab.single_region_num.set_debug_override(0)
	page.set("_size_cycle", 2)
	ContentContext.publish(null)
	var plan: Dictionary = levels.resolve_level_entry(1, page.call("_get_ab_size", 1), 17)
	_check(plan.get("ok", false) and plan.get("size") == 4, "builtin content resolves the actual first-level size override")
	var small: Dictionary = LevelBankIO.builtin_by_id("doku/levels/bankdata4x4").value
	var values: Dictionary = {"doku/levels/bankdata4x4": {"2": [small["2"][0]]}}
	var candidate := _catalog(values)
	_check(candidate.validate_all(DokuContentValidator.validation()).error == "main_pool_missing", "publication refuses the reproduced first-level missing pool")
	# 故意绕过发布门禁安装反例，证明这确实是实际消费者无法开局的内容。
	ContentContext.publish(candidate)
	plan = levels.resolve_level_entry(1, page.call("_get_ab_size", 1), 17)
	_check(plan.get("error") == "no_valid_level", "rejected first-level candidate reproduces the real selection failure")
	values["doku/levels/bankdatalkstyle4x4"] = {"1": [small["1"][0]]}
	candidate = _catalog(values)
	_check(candidate.validate_all(DokuContentValidator.validation()).ok, "eligible supplementary source passes publication")
	ContentContext.publish(candidate)
	plan = levels.resolve_level_entry(1, page.call("_get_ab_size", 1), 17)
	_check(plan.get("ok", false) and plan.entry.get("_bank_source") == "lkstyle", "accepted union pool resolves from the actual supplementary source")
	initial.profile.current_level = 6
	initial.profile.current_strategy = 2
	_check(state.commit_core_candidate(initial, state.get_core_store().revision()).ok, "AB size consumer fixture commits")
	page.set("_size_cycle", 8)
	values = {"doku/policy": {"schema": 1, "size_cycles": {"8": [{"from": 1, "sizes": [4]}]}},
		"doku/levels/bankdata4x4": {"1": [small["1"][0]]}}
	candidate = _catalog(values)
	_check(candidate.validate_all(DokuContentValidator.validation()).error == "main_pool_missing", "publication refuses an AB size override's missing rank")
	ContentContext.publish(candidate)
	plan = levels.resolve_level_entry(6, page.call("_get_ab_size", 6), 17)
	_check(plan.get("error") == "no_valid_level", "AB override reproduces missing pool at the actual selection entry")
	values.erase("doku/levels/bankdata4x4")
	candidate = _catalog(values)
	_check(candidate.validate_all(DokuContentValidator.validation()).ok, "AB size override may use the complete builtin bank")
	ContentContext.publish(candidate)
	plan = levels.resolve_level_entry(6, page.call("_get_ab_size", 6), 17)
	_check(plan.get("ok", false) and plan.get("size") == 4 and plan.entry.get("_bank_rank") == 2, "accepted AB override resolves the correct size and rank")
	ContentContext.publish(null)
	page.free()


func _test_explicit_callbacks() -> void:
	var calls: Dictionary = {"file": 0, "catalog": 0, "media": 0}
	var wrapped := ContentValidation.new(
		func(id: String, value: Variant) -> Dictionary:
			calls.file += 1
			return DokuContentValidator.inspect(id, value),
		func(catalog: RefCounted) -> Dictionary:
			calls.catalog += 1
			return DokuContentValidator.validate_catalog(catalog),
		func(_catalog_value: RefCounted) -> Dictionary:
			calls.media += 1
			return {"ok": false, "error": "observed_media_contract"}
	)
	var source: Dictionary = LevelBankIO.builtin_by_id("doku/levels/bankdata10x10").value
	var bad := _catalog({"doku/levels/bankdata10x10": {"1": [source["1"][0]]}})
	_check(bad.validate_all(wrapped).error == "daily_pool_missing" and calls.file == 1 and calls.catalog == 1,
		"wrapping file callback cannot silently remove explicitly supplied catalog callback")
	_check(bad._json.is_empty(), "failed directory verification restores the pre-validation cache")
	var good := _catalog({"doku/policy": {"schema": 1}})
	_check(good.validate_all(wrapped).ok, "wrapped product checks accept valid candidate")
	_check(good.validate_registered_media().error == "observed_media_contract" and calls.media == 1,
		"media callback remains attached to the validated catalog")
	var malformed := ContentValidation.new(func(_id: String, _value: Variant) -> bool: return true)
	_check(good.validate_all(malformed).error == "file_validator_result", "invalid callback result is rejected instead of truthy-coerced")
	_check(good._json.is_empty(), "failed file verification restores the pre-validation cache")


func _catalog(values: Dictionary) -> ContentCatalog:
	_fixture += 1
	var directory: String = "user://content-consumer-contracts/%d" % _fixture
	DirAccess.make_dir_recursive_absolute(directory)
	var files: Array = []
	for id: String in values:
		var relative: String = id.replace("/", "_") + ".json"
		var path := directory.path_join(relative)
		var bytes := JSON.stringify(values[id]).to_utf8_buffer()
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		files.append({"id": id, "path": relative, "kind": "json", "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)})
	return ContentCatalog.new(directory, {"release": "consumer-contract-%d" % _fixture, "files": files})


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + message)
