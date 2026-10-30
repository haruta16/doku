## 关卡数据总表：难度曲线（关卡号 → 边长/策略/rank/tier）、题源选择、题库轮询取题、题目查重 ID
class_name LevelData
extends RefCounted

const MainRules = preload("res://products/meowdoku/gameplay/domain/doku_main_selection_rules.gd")
const Result = preload("res://scripts/framework/operation_result.gd")
const SelectionState = preload("res://products/meowdoku/gameplay/application/doku_selection_state.gd")


## 无业务写入的选题入口：所有游标/降档变化暂存在私有副本，seed 固定本次随机决策。
## 题库缓存读取可以发生，但不会保存玩家数据，也不会推进全局随机数生成器。
static func resolve_level_entry(level_num: int, override_sz: int = 0, seed_value: int = 0) -> Dictionary:
	if level_num < 1 or not GameState.is_storage_ready():
		return Result.failure("invalid_selection_context")
	var expected: Dictionary = _capture_selection_state()
	var working: SelectionState = SelectionState.new(expected)
	var policy: Dictionary = _capture_selection_policy()
	var generation: int = ContentContext.generation()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var entry: Dictionary = get_level_entry(level_num, override_sz, working, policy, rng)
	var size: int = int(entry.get("size", 0))
	if size <= 0:
		size = (entry.get("regionMap", []) as Array).size()
	if not _selection_entry_valid(entry, size):
		return Result.failure("no_valid_level")
	var puzzle_id: String = compute_puzzle_id(size, entry.regionMap)
	var previous: Dictionary = _find_previous_puzzle(working.profile.get("recent_puzzles", []), puzzle_id)
	# 只换一次候选，沿用本次已决定的难度与首局降档。特殊关的固定题不重抽。
	if not previous.is_empty() and int(previous.get("level", -1)) != level_num and str(entry.get("_bank_source", "")) not in ["sp", "lk", "catalog"]:
		var rank: int = int(entry.get("_bank_rank", 1))
		var tier: String = str(entry.get("_bank_tier", ""))
		var hard: bool = is_hard_level_group_j(level_num) if int(policy.rule_normal_rank) == 10 else is_hard_level(level_num)
		entry = _get_next_entry_with_filter(size, rank, tier, level_num, hard, -1, working, policy)
		if not _selection_entry_valid(entry, size):
			return Result.failure("no_valid_level")
		puzzle_id = compute_puzzle_id(size, entry.regionMap)
		previous = _find_previous_puzzle(working.profile.get("recent_puzzles", []), puzzle_id)
	# 第一次开局即消耗当日机会；只有实际降低过策略的分支才标记“降档局”。
	if working.is_daily_first_easy_available():
		working.consume_daily_first_easy()
	var recent: Array = working.profile.get("recent_puzzles", []).duplicate(true)
	recent.append({
		"puzzle_id": puzzle_id, "level": level_num,
		"v": UniKitManager.get_version_name(),
		"src": entry.get("_bank_source_main", entry.get("_bank_source", "")),
		"ts": int(Time.get_unix_time_from_system()),
		"bank_progress": working.profile.get("bank_progress", {}).duplicate(true),
		"main_bank_progress": working.profile.get("main_bank_progress", {}).duplicate(true),
		"lkmod_progress": working.profile.get("lkmod_progress", {}).duplicate(true),
	})
	while recent.size() > 100:
		recent.pop_front()
	working.profile["recent_puzzles"] = recent
	var identity: String = JSON.stringify({"level": level_num, "seed": seed_value, "expected": expected, "policy": policy, "puzzle_id": puzzle_id, "generation": generation})
	return {
		"ok": true, "entry": entry.duplicate(true), "size": size, "level": level_num,
		"puzzle_id": puzzle_id, "seed": seed_value, "selection_id": identity.sha256_text(),
		"expected_selection": expected, "next_selection": working.snapshot(),
		"previous": previous, "content_generation": generation,
	}


## 题面、预置格及残局都准备成功后调用；一次提交游标、降档、查重、重试题面与残局。
## 只比较选题字段，普通统计/广告到账不使计划失效；重试同 selection_id 不重复推进。
static func commit_selected(plan: Dictionary, checkpoint: Dictionary = {}, retry_params: Dictionary = {}, auto_mark_variant: int = -1, consume_daily_first: bool = false, new_game_id: String = "") -> Dictionary:
	if not plan.get("ok", false) or str(plan.get("selection_id", "")).is_empty():
		return Result.failure("invalid_selection_plan")
	if not GameState.is_storage_ready():
		return Result.failure("store_not_open")
	var candidate: Dictionary = GameState.get_core_candidate()
	var features: Dictionary = candidate.get("features", {})
	var committed: Dictionary = features.get("doku_selection", {})
	if committed.get("selection_id", "") == plan.selection_id:
		return {"ok": true, "duplicate": true, "selection_id": plan.selection_id}
	if int(plan.get("content_generation", -1)) != ContentContext.generation():
		return Result.failure("selection_content_changed")
	if int(candidate.profile.get("current_level", 1)) != int(plan.get("level", 0)):
		return Result.failure("selection_level_mismatch")
	if _capture_selection_state() != plan.get("expected_selection", {}):
		return Result.failure("selection_conflict")
	var next: Dictionary = plan.get("next_selection", {})
	if not next.get("profile") is Dictionary or not next.get("runtime") is Dictionary:
		return Result.failure("invalid_selection_plan")
	for field: String in SelectionState.PROFILE_FIELDS:
		if next.profile.has(field):
			candidate.profile[field] = next.profile[field]
	for field: String in SelectionState.RUNTIME_FIELDS:
		if next.runtime.has(field):
			candidate.round_runtime[field] = next.runtime[field]
	candidate.round_runtime["current_level_dirty"] = false
	if not retry_params.is_empty():
		candidate.profile["retry_puzzle_level"] = int(plan.level)
		candidate.profile["retry_puzzle_params"] = retry_params.duplicate(true)
	# 新题替换旧检查点；本局关闭残局保存时也不能留下上一题的快照。
	candidate.endgame["snapshot"] = checkpoint.duplicate(true)
	_stage_entry_metadata(candidate, auto_mark_variant, consume_daily_first, new_game_id)
	features["doku_selection"] = {"selection_id": plan.selection_id, "level": plan.level, "puzzle_id": plan.puzzle_id}
	candidate["features"] = features
	var result: Dictionary = GameState.commit_core_candidate(candidate, GameState.get_core_store().revision())
	if not result.get("ok", false):
		return Result.wrap_failure("selection_commit_failed", result)
	return {"ok": true, "duplicate": false, "selection_id": plan.selection_id}


## 恢复/重试不推进题库游标；搭盘成功后才提交当天资格及本局设置。
static func commit_existing_entry(auto_mark_variant: int, consume_daily_first: bool, clear_dirty: bool = false, new_game_id: String = "") -> Dictionary:
	if not GameState.is_storage_ready():
		return Result.failure("store_not_open")
	var candidate: Dictionary = GameState.get_core_candidate()
	var before: Dictionary = candidate.duplicate(true)
	_stage_entry_metadata(candidate, auto_mark_variant, consume_daily_first, new_game_id)
	if clear_dirty:
		candidate.round_runtime["current_level_dirty"] = false
	if candidate == before:
		return Result.success()
	var result: Dictionary = GameState.commit_core_candidate(candidate, GameState.get_core_store().revision())
	return result if result.get("ok", false) else Result.wrap_failure("entry_commit_failed", result)


static func _stage_entry_metadata(candidate: Dictionary, auto_mark_variant: int, consume_daily_first: bool, new_game_id: String) -> void:
	if auto_mark_variant >= 0:
		candidate.profile["saved_game_auto_mark"] = auto_mark_variant
	if consume_daily_first:
		candidate.profile["daily_first_easy_date"] = Time.get_date_string_from_system()
	if not new_game_id.is_empty():
		candidate.endgame.stats["main_total"] = {}
		candidate.endgame.stats["main_round"] = {}
		candidate.endgame.stats["main_id"] = new_game_id


static func _capture_selection_state() -> Dictionary:
	var candidate: Dictionary = GameState.get_core_candidate()
	var profile: Dictionary = {}
	for field: String in SelectionState.PROFILE_FIELDS:
		if candidate.profile.has(field):
			profile[field] = candidate.profile[field]
	var runtime: Dictionary = {}
	for field: String in SelectionState.RUNTIME_FIELDS:
		runtime[field] = bool(candidate.get("round_runtime", {}).get(field, false))
	var today: String = Time.get_date_string_from_system()
	return {
		"profile": profile.duplicate(true), "runtime": runtime,
		"daily_available": GameState.is_daily_first_easy_available() and str(profile.get("daily_first_easy_date", "")) < today,
		"today": today,
	}


static func _capture_selection_policy() -> Dictionary:
	return {
		"rule_normal_rank": ABTestManager.rule_normal_rank.value(),
		"single_region": ABTestManager.single_region_num.value(),
		"level10_sp57": ABTestManager.normal_level_10.is_sp57_at_level10(),
	}


static func _single_region_policy(policy: Dictionary) -> int:
	return int(policy.single_region) if policy.has("single_region") else ABTestManager.single_region_num.value()


static func _selection_entry_valid(entry: Dictionary, size: int) -> bool:
	if entry.is_empty() or size < 1 or size > 32:
		return false
	var regions: Variant = entry.get("regionMap")
	var solution: Variant = entry.get("solution")
	if not regions is Array or not solution is Array or regions.size() != size or solution.size() != size:
		return false
	for row: Variant in regions:
		if not row is Array or row.size() != size:
			return false
		for region: Variant in row:
			if typeof(region) not in [TYPE_INT, TYPE_FLOAT] or float(region) != floor(float(region)) or int(region) < 0 or int(region) >= size:
				return false
	for column: Variant in solution:
		if typeof(column) not in [TYPE_INT, TYPE_FLOAT] or float(column) != floor(float(column)) or int(column) < 0 or int(column) >= size:
			return false
	return QueendokuCore.validate_solution_entry(entry, size)


static func _find_previous_puzzle(recent: Array, puzzle_id: String) -> Dictionary:
	for index in range(recent.size() - 1, -1, -1):
		if recent[index].get("puzzle_id", "") == puzzle_id:
			return recent[index].duplicate(true)
	return {}

# ================= 难度曲线：内容策略与纯选择规则 =================
## 关卡号 → 棋盘边长：前 100 关查表，之后按 10 关一循环；关卡号非法返回 0
static func get_size(level_num: int) -> int:
	return DokuPolicy.cycle_size(-1, level_num)


## 同上，但用于规则组 J：分段边界是 21 / 51 / 101
static func get_size_group_j(level_num: int) -> int:
	return DokuPolicy.cycle_size(-2, level_num)


## 是否难关（Boss 关）：21 关起每逢 10 的倍数，即 30 / 40 / 50…（第 20 关不算）
static func is_hard_level(level_num: int) -> bool:
	return MainRules.is_hard(level_num, 0)


## 组 J 的难关：29 关起每逢 9 结尾，即 29 / 39 / 49…
static func is_hard_level_group_j(level_num: int) -> bool:
	return MainRules.is_hard(level_num, 10)


## 是否里程碑特殊关：由当前 DokuPolicy 特殊关配置决定，不走题库轮询
static func is_special_level(level_num: int) -> bool:
	return DokuPolicy.special_levels().has(level_num)


## 策略号 → 题库 rank：5→4、6→5、7→5，其余原样（策略号是 rank 与 H 档的组合编码）
static func strategy_to_rank(strategy: int) -> int:
	return MainRules.rank_for(strategy)


## 策略号 → 题库 tier：5 和 7 属于 H 档，其余是 N 档
static func strategy_to_tier(strategy: int) -> String:
	return MainRules.tier_for(strategy)


## 取当前难度策略：前 5 关固定 1；51 关起保底 2。仅显式传入选择状态时暂存提升。
static func get_strategy(level_num: int, selection_state: Variant = null) -> int:
	var source: Variant = selection_state if selection_state != null else GameState
	var current: int = source.get_current_strategy()
	var strategy: int = MainRules.normal_strategy(level_num, current)
	if level_num >= 51 and strategy != current and selection_state != null:
		source.set_current_strategy(strategy)
	return strategy


# ================= 题库进度推进（都会写存档） =================
## 取完一题后推进游标：lk_mod 走自己的计数器，其他来源走主进度 idx / since_lk
static func advance_for_entry(entry: Dictionary, sz: int, selection_state: Variant = null) -> void:
	var source: Variant = selection_state if selection_state != null else GameState
	var rank: int = int(entry.get("_bank_rank", 1)) # 题目里带的题库元信息，由 get_next_entry / get_next_entry_main 写入
	var tier: String = entry.get("_bank_tier", "")
	var src_main: String = entry.get("_bank_source_main", "")
	if src_main == "": # 老题库路径：只推进 bank_index
		source.advance_bank_index(sz, rank, tier)
		return
	if src_main == "lk_mod": # LK 改造题：推进它自己的游标，并把主进度的「距上次 LK」清零
		var lkprog: Dictionary = source.get_lkmod_progress(sz, rank)
		lkprog["idx"] = lkprog.get("idx", 0) + 1
		source.set_lkmod_progress(sz, rank, lkprog)
		var prog: Dictionary = source.get_main_progress(sz, rank, tier)
		prog["since_lk"] = 0
		source.set_main_progress(sz, rank, tier, prog)
	else:
		var prog: Dictionary = source.get_main_progress(sz, rank, tier) # 其他来源：主进度 idx+1，并累计 since_lk（满 4 就插一道 LK 改造题）
		prog["idx"] = prog.get("idx", 0) + 1
		prog["since_lk"] = prog.get("since_lk", 0) + 1
		source.set_main_progress(sz, rank, tier, prog)


# ================= 取题：老入口（50 关及以前） =================
## 把 regular / lkstyle / gc 三段拼成一个池，按存档序号取模轮询；tier 为空表示不限档
## 返回题目字典（带 _bank_source/_bank_idx/_bank_tier/_bank_rank），池子空时返回 {}
static func get_next_entry(
	sz: int, rank: int, tier: String = "", remaining_attempts: int = -1,
	selection_state: Variant = null, selection_policy: Dictionary = {}
) -> Dictionary:
	var source_state: Variant = selection_state if selection_state != null else GameState
	var pools: Dictionary = MainRules.cycling_pools(sz, rank, tier, false,
		BankData.get_levels(sz, rank), BankData.get_lk_style_levels(sz, rank),
		BankData.get_gc_levels(sz, rank) if (sz == 10 and rank == 1) or sz == 11 else [])
	var regular: Array = pools.regular
	var lkstyle: Array = pools.lkstyle
	var gc: Array = pools.gc
	var total_regular: int = regular.size() # 三段加起来就是轮询用的总池
	var total_lkstyle: int = lkstyle.size()
	var total_gc: int = gc.size()
	var total: int = total_regular + total_lkstyle + total_gc
	if total == 0: # 一题都没有，交给调用方处理
		return {}

	# 同一调用只构建一次题池；失败重取用循环，调用栈不随题库规模增长。
	remaining_attempts = maxi(1, total if remaining_attempts < 0 else remaining_attempts)
	while remaining_attempts > 0:
		var idx: int = source_state.get_bank_index(sz, rank, tier) # 存档里的池内序号，取模实现循环轮询
		var real_idx: int = idx % total
		var entry: Dictionary
		var source: String
		var source_idx: int
		if real_idx < total_regular: # 按 real_idx 落在哪一段决定题源，并算出段内 1-based 序号
			entry = regular[real_idx].duplicate()
			source = "regular"
			source_idx = real_idx + 1
		elif real_idx < total_regular + total_lkstyle:
			entry = lkstyle[real_idx - total_regular].duplicate()
			source = "lkstyle"
			source_idx = real_idx - total_regular + 1
		else:
			entry = gc[real_idx - total_regular - total_lkstyle].duplicate()
			source = "gc"
			source_idx = real_idx - total_regular - total_lkstyle + 1
		entry["_bank_source"] = source # 来源信息写回 entry，供难度统计、查重和推进游标使用
		entry["_bank_idx"] = source_idx
		entry["_bank_tier"] = tier
		entry["_bank_rank"] = rank

		if not QueendokuCore.validate_solution_entry(entry, sz):
			if remaining_attempts == 1:
				push_warning("LevelData.get_next_entry: 题池没有合法答案，返回最后候选供入口拒绝")
				return entry
			source_state.advance_bank_index(sz, rank, tier)
			remaining_attempts -= 1
			continue

		if _single_region_policy(selection_policy) in [1, 2] and _exceeds_single_region_limit(entry.regionMap):
			if remaining_attempts > 1:
				source_state.advance_bank_index(sz, rank, tier)
				remaining_attempts -= 1
				continue
			# 保留已有降级策略：没有符合 AB 偏好的题时仍可玩这张合法题。
			push_warning("LevelData.get_next_entry: 单格区域筛选耗尽，沿用最后合法候选")

		advance_for_entry(entry, sz, source_state)
		return entry
	return {}


## 调用前已验证题面；这里只统计单格区域，两个选题入口共用同一 AB 条件。
static func _exceeds_single_region_limit(region_map: Array) -> bool:
	var counts: Dictionary = {}
	for row: Array in region_map:
		for region: Variant in row:
			var id: int = int(region)
			counts[id] = int(counts.get(id, 0)) + 1
	var singles: int = 0
	for count: int in counts.values():
		if count == 1:
			singles += 1
	return singles > 2


# ================= 开局送格（仅前 10 关） =================
## 1~6 关送「所在区域不止一格」的答案格，7~10 关改送「独占一个小区域」的答案格
## 返回 [行, 列]；不适用或找不到时返回 []（调用方按「不给提示」处理）
static func compute_prefill(level_num: int, region_map: Array, solution: Array, sz: int) -> Array:
	if level_num < 1 or level_num > 10: # 只对第 1~10 关生效
		return []
	var want_size_one: bool = level_num >= 7 # 7 关起改送独占区域的猫

	var region_area: Dictionary = {} # 统计每个区域占几格
	for r: int in range(sz):
		for c: int in range(sz):
			var rid: int = region_map[r][c]
			region_area[rid] = region_area.get(rid, 0) + 1

	for r: int in range(sz): # 按行序扫答案，取第一只符合条件的猫
		var c: int = solution[r]
		var rid: int = region_map[r][c]
		var area: int = region_area.get(rid, 0)
		if want_size_one and area == 1:
			return [r, c]
		elif not want_size_one and area > 1:
			return [r, c]

	if sz > 0 and solution.size() > 0: # 兜底：直接送第 0 行的那只猫；连答案都没有就返回空数组
		return [0, solution[0]]
	return []


# ================= 题目的对称变换与查重 ID =================
## LK 改造题库里预留给特殊关的下标（1-based），常规轮询会跳过这几题
const LK_MOD_RESERVED: Array[int] = [20, 30, 53, 71, 72, 75, 114, 141, 164]

const TRANSFORM_COUNT: int = 8 # 一道题的对称变换总数：4 种旋转 × 是否左右镜像


## 对题目做第 t 种对称变换，返回 [region_map, solution]；solution 是「每行猫所在列号」的一维数组
## 题库轮换只用 t ∈ 0~7；cheat 面板允许 0~11，多出的 8~11 才会同时用上左右与上下镜像
static func apply_transform(region_map: Array, solution: Array, sz: int, t: int) -> Array:
	var rm: Array = region_map
	var sol: Array = solution
	@warning_ignore("integer_division") # t/4 决定镜像：0 不镜像、1 左右镜像、2 上下镜像
	var mirror: int = t / 4
	var rot: int = t % 4 # t%4 是顺时针旋转 90° 的次数
	if mirror == 1: # 左右镜像：区域图每行反转，答案列号也跟着翻
		var new_rm: Array = []
		for r: int in range(sz):
			var row: Array = []
			for c: int in range(sz):
				row.append(rm[r][sz - 1 - c])
			new_rm.append(row)
		var new_sol: Array = []
		for r: int in range(sz):
			new_sol.append(sz - 1 - sol[r])
		rm = new_rm
		sol = new_sol
	elif mirror == 2: # 上下镜像：行序倒过来，答案数组 reverse
		var new_rm: Array = []
		for r: int in range(sz):
			new_rm.append(rm[sz - 1 - r].duplicate())
		var new_sol: Array = sol.duplicate()
		new_sol.reverse()
		rm = new_rm
		sol = new_sol
	for _i: int in range(rot): # 逐次顺时针旋转：新 [r][c] 取原 [size-1-c][r]，答案按同一映射重排
		var new_rm: Array = []
		for r2: int in range(sz):
			var row: Array = []
			for c2: int in range(sz):
				row.append(rm[sz - 1 - c2][r2])
			new_rm.append(row)
		var new_sol: Array = []
		new_sol.resize(sz)
		for r2: int in range(sz):
			new_sol[sol[r2]] = sz - 1 - r2
		rm = new_rm
		sol = new_sol
	return [rm, sol] # 返回值固定是 [区域图, 答案列号数组] 两元组


## 变换序号 → 题号后缀（第 0 种是规范形，不写后缀）
const _SUFFIX_NAMES: Array[String] = [
	"",
	"r90",
	"r180",
	"r270",
	"h",
	"hr90",
	"hr180",
	"hr270",
]


## 题目的稳定查重 ID：8 种对称变换里字典序最小的形态当规范形，取规范形的 sha256 前 16 位
## 返回 "边长_哈希"；当前朝向不是规范形时再补后缀（r90/h/hr270…）
## 调用方拿它调 GameState.record_puzzle 判重，近期出现过的题会被换掉
static func compute_puzzle_id(sz: int, region_map: Array) -> String:
	var input_norm_str: String = _serialize_region_map(_normalize_region_map(region_map, sz)) # 输入先归一化（重编区域号）再序列化，作为比较基准

	var transformed_pre: Array = [] # 8 种变换各算一份归一化串，选最小的当规范形
	var transformed_str: Array = []
	for t: int in range(TRANSFORM_COUNT):
		var rm_t: Array = _apply_region_transform(region_map, sz, t)
		transformed_pre.append(rm_t)
		transformed_str.append(_serialize_region_map(_normalize_region_map(rm_t, sz)))

	var canonical_str: String = transformed_str.min() # 规范形本身（下面要用它反推当前朝向）
	var t_input_to_canonical: int = transformed_str.find(canonical_str)
	var canonical_pre: Array = transformed_pre[t_input_to_canonical]

	var suffix_t: int = 0 # 找出「规范形做第 t 种变换能得到当前输入」的那个 t
	for t: int in range(TRANSFORM_COUNT):
		var maybe_input: Array = _apply_region_transform(canonical_pre, sz, t)
		if _serialize_region_map(_normalize_region_map(maybe_input, sz)) == input_norm_str:
			suffix_t = t
			break

	var hash16: String = canonical_str.sha256_text().substr(0, 16) # 哈希只吃规范形的内容，所以同一题的任何朝向都得到同一个哈希
	if suffix_t == 0: # 朝向正好是规范形
		return "%d_%s" % [sz, hash16]
	return "%d_%s_%s" % [sz, hash16, _SUFFIX_NAMES[suffix_t]]


## 只变换区域图、不动 solution 的版本，compute_puzzle_id 算规范形时用
static func _apply_region_transform(region_map: Array, sz: int, t: int) -> Array:
	var rm: Array = region_map
	@warning_ignore("integer_division")
	var mirror: int = t / 4
	var rot: int = t % 4
	if mirror == 1:
		var new_rm: Array = []
		for r: int in range(sz):
			var row: Array = []
			for c: int in range(sz):
				row.append(rm[r][sz - 1 - c])
			new_rm.append(row)
		rm = new_rm
	elif mirror == 2:
		var new_rm: Array = []
		for r: int in range(sz):
			new_rm.append(rm[sz - 1 - r].duplicate())
		rm = new_rm
	for _i: int in range(rot):
		var new_rm: Array = []
		for r2: int in range(sz):
			var row: Array = []
			for c2: int in range(sz):
				row.append(rm[sz - 1 - c2][r2])
			new_rm.append(row)
		rm = new_rm
	return rm


## 按行优先首次出现的顺序把区域号重编成 0,1,2…，消除编号命名差异，便于两份区域图比较
static func _normalize_region_map(region_map: Array, sz: int) -> Array:
	var remap: Dictionary = {}
	var next_id: int = 0
	var result: Array = []
	for r: int in range(sz):
		var row: Array = []
		for c: int in range(sz):
			var v: int = int(region_map[r][c])
			if not remap.has(v):
				remap[v] = next_id
				next_id += 1
			row.append(remap[v])
		result.append(row)
	return result


## 把二维区域图拍成逗号分隔字符串，用于比较与取哈希
static func _serialize_region_map(region_map: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for row in region_map:
		for v in row:
			parts.append(str(int(v)))
	return ",".join(parts)


# ================= 取题：主线入口（51 关及以后） =================
## 四段题源轮询：lk_mod 改造题 + regular + lkstyle + gc；每连取 4 道常规题插一道 LK 改造题
## 一整池取完就换下一种对称变换重来；进度来自存档里的 idx / since_lk / transform
static func get_next_entry_main(
	sz: int, rank: int, tier: String, remaining_attempts: int = -1, strict_rank: bool = false,
	selection_state: Variant = null, selection_policy: Dictionary = {}
) -> Dictionary:
	var source_state: Variant = selection_state if selection_state != null else GameState
	var lk_mod: Array = _lk_modified_pool(sz, rank, strict_rank)

	var pools: Dictionary = MainRules.cycling_pools(sz, rank, tier, true,
		BankData.get_levels(sz, rank), BankData.get_lk_style_levels(sz, rank),
		BankData.get_gc_levels(sz, rank) if (sz == 10 and rank == 1) or sz == 11 else [])
	var regular: Array = pools.regular
	var lkstyle: Array = pools.lkstyle
	var gc: Array = pools.gc
	var total_lk_mod: int = lk_mod.size() # 四段池子各自的大小与总大小
	var total_regular: int = regular.size()
	var total_lkstyle: int = lkstyle.size()
	var total_gc: int = gc.size()
	var regular_pool_size: int = total_regular + total_lkstyle + total_gc
	var total: int = total_lk_mod + regular_pool_size
	if total == 0:
		return {}

	remaining_attempts = maxi(1, total * TRANSFORM_COUNT if remaining_attempts < 0 else remaining_attempts)
	while remaining_attempts > 0:
		var prog: Dictionary = source_state.get_main_progress(sz, rank, tier) # 主进度：池内序号 idx、距上次 LK 改造题的题数 since_lk、对称变换 transform
		var transform: int = prog.get("transform", 0)

		var idx: int = prog.get("idx", -1)
		var since_lk: int = prog.get("since_lk", 0)

		if idx < 0: # idx < 0 说明是没写过主进度的旧存档：从老的 bank_index 折算起点再写回
			var legacy_idx: int = source_state.get_bank_index(sz, rank, tier)
			var denom: int = total_regular + total_lkstyle
			idx = legacy_idx % denom if (legacy_idx > 0 and denom > 0) else 0
			since_lk = 0
			prog["idx"] = idx
			prog["since_lk"] = since_lk
			source_state.set_main_progress(sz, rank, tier, prog)

		var lkprog: Dictionary = source_state.get_lkmod_progress(sz, rank) # LK 改造题有独立游标，与主进度分开记
		var lk_idx: int = lkprog.get("idx", 0)
		if regular_pool_size == 0 and lk_idx >= total_lk_mod:
			return {} # 只有一次性 LK 题源且已用尽，交给调用方报告没有可用题。

		if regular_pool_size > 0 and idx >= regular_pool_size: # idx 超出池子 = 这一轮取完：换下一种对称变换、从头开始
			transform = (transform + 1) % TRANSFORM_COUNT
			idx = 0
			since_lk = 0
			prog = {"idx": 0, "since_lk": 0, "transform": transform}
			source_state.set_main_progress(sz, rank, tier, prog)

		var entry: Dictionary
		var source: String
		var source_idx: int

		if (since_lk >= 4 or regular_pool_size == 0) and lk_idx < total_lk_mod: # 无常规题时直接使用剩余 LK，否则每 4 道插一道
			entry = lk_mod[lk_idx].duplicate()
			source = "lk_mod"
			source_idx = lk_idx + 1
		elif idx < total_regular: # 否则按 idx 落在 regular / lkstyle / gc 哪一段取题
			entry = regular[idx].duplicate()
			source = "regular"
			source_idx = idx + 1
		elif idx < total_regular + total_lkstyle:
			var li: int = idx - total_regular
			entry = lkstyle[li].duplicate()
			source = "lkstyle"
			source_idx = li + 1
		elif idx < total_regular + total_lkstyle + total_gc:
			var gi: int = idx - total_regular - total_lkstyle
			entry = gc[gi].duplicate()
			source = "gc"
			source_idx = gi + 1
		else:
			# 逻辑上到不了这里，兜底取第一道常规题并记错误日志
			push_error(
				(
					"LevelData.get_next_entry_main: unexpected else branch sz=%d rank=%d tier=%s idx=%d"
					% [sz, rank, tier, idx]
				)
			)
			entry = regular[0].duplicate() if not regular.is_empty() else {}
			source = "regular"
			source_idx = 1

		entry["_bank_source"] = source # 写回题库元信息，供难度统计、查重和推进游标使用
		entry["_bank_source_main"] = source
		entry["_bank_idx"] = source_idx
		entry["_bank_tier"] = tier
		entry["_bank_rank"] = rank
		entry["_bank_transform"] = transform

		# 原始答案先校验，非法答案不能进入假定每行每列唯一的旋转算法。
		if not QueendokuCore.validate_solution_entry(entry, sz):
			if remaining_attempts == 1:
				push_warning("LevelData.get_next_entry_main: 题池没有合法答案，返回最后候选供入口拒绝")
				return entry
			if source == "lk_mod":
				lkprog["idx"] = lk_idx + 1
				source_state.set_lkmod_progress(sz, rank, lkprog)
			else:
				prog["idx"] = idx + 1
				source_state.set_main_progress(sz, rank, tier, prog)
			# 沿用旧非法题回退：后续 LK 改造题允许按 maxR 匹配。
			if strict_rank:
				strict_rank = false
				lk_mod = _lk_modified_pool(sz, rank, false)
				total_lk_mod = lk_mod.size()
			remaining_attempts -= 1
			continue

		if transform > 0 and source != "lk_mod": # 非 LK 改造题按 transform 做对称变形：同一题换朝向，玩家看到的是新题
			var rm: Array = []
			for row in entry.get("regionMap", []):
				var int_row: Array = []
				for v in row:
					int_row.append(int(v))
				rm.append(int_row)
			var sol: Array = []
			for v in entry.get("solution", []):
				sol.append(int(v))
			var result: Array = apply_transform(rm, sol, sz, transform)
			entry["regionMap"] = result[0]
			entry["solution"] = result[1]

		if _single_region_policy(selection_policy) in [1, 2] and source not in ["lk_mod", "sp", "lk"] and _exceeds_single_region_limit(entry.regionMap):
			if remaining_attempts > 1:
				prog["idx"] = idx + 1
				source_state.set_main_progress(sz, rank, tier, prog)
				remaining_attempts -= 1
				continue
			push_warning("LevelData.get_next_entry_main: 单格区域筛选耗尽，沿用最后合法候选")

		advance_for_entry(entry, sz, source_state)
		return entry
	return {}


static func _lk_modified_pool(sz: int, rank: int, strict_rank: bool) -> Array:
	var all: Array = BankData.get_lk_modified_levels()
	var selected: Array = []
	for index: int in range(all.size()):
		if (index + 1) in LK_MOD_RESERVED:
			continue
		var entry: Dictionary = all[index]
		if entry.regionMap.size() != sz:
			continue
		var entry_rank: int = int(entry.get("r", 1)) if strict_rank else int(entry.get("maxR", entry.get("r", 1)))
		if entry_rank == rank:
			selected.append(entry)
	return selected


# ================= 特殊关表与取题总入口 =================
## 关卡号 → 关卡数据 entry 的总入口：先查特殊关，再按 AB 规则算边长 / rank / tier，最后交给取题函数
## override_sz > 0 时强制使用该边长；命中特殊关失败则继续走常规曲线
static func get_level_entry(
	level_num: int, override_sz: int = 0, selection_state: Variant = null,
	selection_policy: Dictionary = {}, rng: RandomNumberGenerator = null
) -> Dictionary:
	var fixed: Dictionary = DokuLevelCatalog.resolve(level_num)
	if not fixed.get("ok", false):
		return {}
	if fixed.get("found", false):
		return fixed.entry
	var source: Variant = selection_state if selection_state != null else GameState
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var rnr: int = int(selection_policy.get("rule_normal_rank", ABTestManager.rule_normal_rank.value())) # AB 实验里的难度规则编号（1~11），决定曲线怎么裁剪

	var special_levels: Dictionary = DokuPolicy.special_levels() # 当前内容版本的特殊关表，返回独立副本
	if level_num == 10 and bool(selection_policy.get("level10_sp57", ABTestManager.normal_level_10.is_sp57_at_level10())):
		special_levels[10] = {"source": "sp", "index": 57}

	if special_levels.has(level_num): # 命中特殊关：直接从 sp / lk 题库取写死的那一题
		var spec: Dictionary = special_levels[level_num]
		var idx: int = spec["index"] - 1 # 表里的下标是 1-based
		if spec["source"] == "sp":
			var sp_levels: Array = BankData.get_sp_levels()
			if idx >= 0 and idx < sp_levels.size():
				var e: Dictionary = sp_levels[idx].duplicate()
				e["_bank_source"] = "sp"
				e["_bank_idx"] = idx + 1
				e["_bank_tier"] = ""
				e["_bank_rank"] = e.get("r", 1) # sp 题的难度看 r 字段
				return e
		elif spec["source"] == "lk":
			var lk_levels: Array = BankData.get_lk_levels()
			if idx >= 0 and idx < lk_levels.size():
				var e: Dictionary = lk_levels[idx].duplicate()
				e["_bank_source"] = "lk"
				e["_bank_idx"] = idx + 1
				e["_bank_tier"] = ""
				e["_bank_rank"] = e.get("maxR", 1) # lk 题的难度看 maxR
				return e

	var sz: int # 边长：override 优先；规则组 J 用另一张表
	if override_sz > 0:
		sz = override_sz
	elif rnr == 10:
		sz = get_size_group_j(level_num)
	else:
		sz = get_size(level_num)
	if sz == 0: # 边长 0 = 关卡号非法
		return {}

	var is_hard: bool = MainRules.is_hard(level_num, rnr)
	var strategy: int = source.get_current_strategy() if is_hard else get_strategy(level_num, source)
	var choice: Dictionary = MainRules.select(level_num, rnr, strategy,
		source.is_daily_first_easy_available(), source.is_rnr_g_prev_was_max(), rng)
	if choice.next_previous_was_max != null:
		source.set_rnr_g_prev_was_max(choice.next_previous_was_max)
	if choice.consume_daily:
		source.consume_daily_first_easy_and_mark()
	var rank: int = choice.rank
	var tier: String = choice.tier
	if not is_hard:
		tier = MainRules.normal_tier(tier, BankData.get_levels(sz, rank), BankData.get_lk_style_levels(sz, rank))
	if choice.mod1:
		source.mark_rnr_mod1_exempt()
		return get_next_entry_main(sz, rank, tier, -1, false, source, selection_policy)
	return _get_next_entry_with_filter(sz, rank, tier, level_num, is_hard, -1, source, selection_policy)



## 取题收口：51 关起走四段轮询（get_next_entry_main），前 50 关走老的三段轮询，再叠一层 AB 严格过滤
static func _get_next_entry_with_filter(
	sz: int, rank: int, tier: String, level_num: int, is_hard: bool, remaining: int = -1,
	selection_state: Variant = null, selection_policy: Dictionary = {}
) -> Dictionary:
	var source: Variant = selection_state if selection_state != null else GameState
	var entry: Dictionary # 51 关是分界线：之后才用带对称变换的题库
	if level_num >= 51:
		entry = get_next_entry_main(sz, rank, tier, -1, is_hard, source, selection_policy)
	else:
		entry = get_next_entry(sz, rank, tier, -1, source, selection_policy)

	if (_single_region_policy(selection_policy) == 2 and level_num >= 21) and not entry.is_empty(): # AB 严格档：单格区域最多 1 个，lk_mod / sp / lk 来源豁免
		var _src: String = entry.get("_bank_source_main", entry.get("_bank_source", ""))
		if _src != "lk_mod" and _src != "sp" and _src != "lk":
			var _rm: Array = entry.get("regionMap", [])
			if _rm.size() == sz:
				var _cnt: Dictionary = {}
				for _r: int in range(sz):
					for _c: int in range(sz):
						var _rid: int = int((_rm[_r] as Array)[_c])
						_cnt[_rid] = _cnt.get(_rid, 0) + 1
				var _single: int = 0
				for _v: int in _cnt.values():
					if _v == 1:
						_single += 1
				if _single > 1:
					if remaining < 0: # 重试上限 = 棋盘格数 × 12
						remaining = (sz * sz) * 12
					if remaining <= 1: # 到上限仍不合格就容错返回，避免死循环
						push_error(
							(
								"LevelData: single_region_num=2 过滤后无合格题,容错返回 sz=%d rank=%d lv=%d"
								% [sz, rank, level_num]
							)
						)
					else:
						return _get_next_entry_with_filter(
							sz, rank, tier, level_num, is_hard, remaining - 1, source, selection_policy
						)
	return entry
