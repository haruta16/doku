## 选题数据工具：转换策略编码、构建来源题池、执行几何变换，并生成包含方向信息的查重题号。
class_name LevelData
extends RefCounted

# ================= 难度曲线：边长表与难度判定 =================
const LEVEL_COUNT: int = 0 # 未被任何地方使用的占位常量（值恒为 0）


## 按 SpecialProvider 的固定关号表判断是否特殊关。
static func is_special_level(level_num: int) -> bool:
	return SpecialProvider.SPECIAL_LEVELS.has(level_num)


## 策略号 → 题库 rank：5→4、6→5、7→5，其余原样（策略号是 rank 与 H 档的组合编码）
static func strategy_to_rank(strategy: int) -> int:
	match strategy:
		5:
			return 4
		6:
			return 5
		7:
			return 5
		_:
			return strategy


## 策略号 → 题库 tier：5 和 7 属于 H 档，其余是 N 档
static func strategy_to_tier(strategy: int) -> String:
	match strategy:
		5:
			return "H"
		7:
			return "H"
		_:
			return "N"


## 把题库层级与普通或困难档组合为统一策略编号。
static func rank_tier_to_strategy(rank: int, tier: String) -> int:
	if rank == 4 and tier == "H":
		return 5
	if rank == 5:
		return 7 if tier == "H" else 6
	return rank


## 第 51 关起最低策略层级为二，之前为一。
static func level_min_rank(level_num: int) -> int:
	return 2 if level_num >= 51 else 1


const PREFILL_LEVEL_MAX: int = 10


## 前十关选一只答案猫预填：前六关偏好多格区域，七至十关偏好单格区域。
static func compute_prefill(level_num: int, region_map: Array, solution: Array, sz: int) -> Array:
	if level_num < 1 or level_num > PREFILL_LEVEL_MAX:
		return []
	var want_size_one: bool = level_num >= 7

	var region_area: Dictionary = {}
	for r: int in range(sz):
		for c: int in range(sz):
			var rid: int = region_map[r][c]
			region_area[rid] = region_area.get(rid, 0) + 1

	for r: int in range(sz):
		var c: int = solution[r]
		var rid: int = region_map[r][c]
		var area: int = region_area.get(rid, 0)
		if want_size_one and area == 1:
			return [r, c]
		elif not want_size_one and area > 1:
			return [r, c]

	if sz > 0 and solution.size() > 0:
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


## 对区域编号归一化后比较八种对称形态，用规范形哈希及当前方向后缀生成题号。
static func compute_puzzle_id(sz: int, region_map: Array) -> String:
	var input_norm_str: String = _serialize_region_map(_normalize_region_map(region_map, sz))

	var transformed_pre: Array = []
	var transformed_str: Array = []
	for t: int in range(TRANSFORM_COUNT):
		var rm_t: Array = _apply_region_transform(region_map, sz, t)
		transformed_pre.append(rm_t)
		transformed_str.append(_serialize_region_map(_normalize_region_map(rm_t, sz)))

	var canonical_str: String = transformed_str.min()
	var t_input_to_canonical: int = transformed_str.find(canonical_str)
	var canonical_pre: Array = transformed_pre[t_input_to_canonical]

	var suffix_t: int = 0
	for t: int in range(TRANSFORM_COUNT):
		var maybe_input: Array = _apply_region_transform(canonical_pre, sz, t)
		if _serialize_region_map(_normalize_region_map(maybe_input, sz)) == input_norm_str:
			suffix_t = t
			break

	var hash16: String = canonical_str.sha256_text().substr(0, 16)
	return compose_puzzle_id(sz, hash16, suffix_t)


## 把尺寸、规范形哈希与合法变换后缀拼成题号，规范形省略后缀。
static func compose_puzzle_id(sz: int, hash16: String, suffix_index: int) -> String:
	if suffix_index <= 0 or suffix_index >= _SUFFIX_NAMES.size():
		return "%d_%s" % [sz, hash16]
	return "%d_%s_%s" % [sz, hash16, _SUFFIX_NAMES[suffix_index]]


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


## 按首次出现顺序重编号区域，消除颜色编号不同导致的伪差异。
static func _normalize_region_map(region_map: Array, sz: int) -> Array:
	var id_map: Dictionary = {}
	var next_id: int = 0
	var result: Array = []
	for r: int in range(sz):
		var row: Array = []
		for c: int in range(sz):
			var v: int = int(region_map[r][c])
			if not id_map.has(v):
				id_map[v] = next_id
				next_id += 1
			row.append(id_map[v])
		result.append(row)
	return result


## 把二维区域图拍成逗号分隔字符串，用于比较与取哈希
static func _serialize_region_map(region_map: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for row in region_map:
		for v in row:
			parts.append(str(int(v)))
	return ",".join(parts)


## 按尺寸、层级、档位与主线路径规则组合常规、LK 风格、GC 和 LK 改题池。
static func build_pools(
	sz: int,
	rank: int,
	tier: String,
	strict_rank: bool,
	include_lk_mod: bool,
	is_main_path: bool = include_lk_mod,
	force_include_regular: bool = false
) -> Dictionary:
	var regular: Array = (
		BankData.get_levels_by_tier(sz, rank, tier) if tier != "" else BankData.get_levels(sz, rank)
	)
	var lkstyle: Array = (
		BankData.get_lk_style_levels_by_tier(sz, rank, tier)
		if tier != ""
		else BankData.get_lk_style_levels(sz, rank)
	)
	if tier != "" and regular.is_empty() and lkstyle.is_empty():
		regular = BankData.get_levels(sz, rank)
		lkstyle = BankData.get_lk_style_levels(sz, rank)

	if (
		not force_include_regular
		and (include_lk_mod or is_main_path)
		and sz == 10
		and rank in [3, 4]
	):
		regular = []
	var gc: Array = []
	if (sz == 10 and rank == 1) or sz == 11:
		gc = (
			BankData.get_gc_levels_by_tier(sz, rank, tier)
			if tier != ""
			else BankData.get_gc_levels(sz, rank)
		)
		if tier != "" and gc.is_empty():
			gc = BankData.get_gc_levels(sz, rank)
	var lk_mod: Array = []
	if include_lk_mod:
		var lk_mod_all: Array = BankData.get_lk_modified_levels()
		for i: int in range(lk_mod_all.size()):
			if (i + 1) in LK_MOD_RESERVED:
				continue
			var e: Dictionary = lk_mod_all[i]
			if int(e.get("size", 0)) != sz:
				continue
			var e_rank: int = (
				int(e.get("r", 1)) if strict_rank else int(e.get("maxR", e.get("r", 1)))
			)
			if e_rank != rank:
				continue
			lk_mod.append(e)
	return {"regular": regular, "lkstyle": lkstyle, "gc": gc, "lk_mod": lk_mod}


## 读取完整超难题库并包装成统一题池结构。
static func build_super_hard_pools() -> Dictionary:
	return build_super_hard_pools_from(BankData.get_all_super_hard_levels())


## 把传入超难题库放进 regular 槽，其余来源留空以复用通用游标。
static func build_super_hard_pools_from(bank: Array) -> Dictionary:
	return {
		"regular": bank,
		"lkstyle": [],
		"gc": [],
		"lk_mod": [],
	}


## 按游标确定来源并展开题目，必要时旋转镜像，再附来源、索引、档位与节奏信息。
static func pick_at(pools: Dictionary, pos: Dictionary, rank: int, tier: String) -> Dictionary:
	var idx: int = int(pos.get("idx", 0))
	var since_lk: int = int(pos.get("since_lk", 0))
	var transform: int = int(pos.get("transform", 0))
	var lk_idx: int = int(pos.get("lk_idx", 0))
	var is_main_path: bool = bool(pos.get("is_main_path", false))

	var regular: Array = pools.get("regular", [])
	var lkstyle: Array = pools.get("lkstyle", [])
	var gc: Array = pools.get("gc", [])
	var lk_mod: Array = pools.get("lk_mod", [])
	var total_regular: int = regular.size()
	var total_lkstyle: int = lkstyle.size()
	var total_gc: int = gc.size()

	var entry: Dictionary
	var source: String
	var source_idx: int

	if is_main_path:
		if since_lk >= 4 and lk_idx < lk_mod.size():
			entry = BankData.materialize_entry(lk_mod[lk_idx])
			source = "lk_mod"
			source_idx = lk_idx + 1
		elif idx < total_regular:
			entry = BankData.materialize_entry(regular[idx])
			source = "regular"
			source_idx = idx + 1
		elif idx < total_regular + total_lkstyle:
			var li: int = idx - total_regular
			entry = BankData.materialize_entry(lkstyle[li])
			source = "lkstyle"
			source_idx = li + 1
		elif idx < total_regular + total_lkstyle + total_gc:
			var gi: int = idx - total_regular - total_lkstyle
			entry = BankData.materialize_entry(gc[gi])
			source = "gc"
			source_idx = gi + 1
		else:
			return {}
		if transform > 0 and source != "lk_mod":
			var rm: Array = []
			for row in entry.get("regionMap", []):
				var int_row: Array = []
				for v in row:
					int_row.append(int(v))
				rm.append(int_row)
			var sol: Array = []
			for v in entry.get("solution", []):
				sol.append(int(v))
			var _sz: int = rm.size()
			if _sz > 0:
				var result: Array = apply_transform(rm, sol, _sz, transform)
				entry["regionMap"] = result[0]
				entry["solution"] = result[1]
		entry["_bank_source"] = source
		entry["_bank_source_main"] = source
		entry["_bank_idx"] = source_idx
		entry["_bank_tier"] = tier
		entry["_bank_rank"] = rank

		entry["_bank_transform"] = 0 if source == "lk_mod" else transform
	else:
		var total: int = total_regular + total_lkstyle + total_gc
		if total == 0:
			return {}
		var real_idx: int = idx % total
		if real_idx < total_regular:
			entry = BankData.materialize_entry(regular[real_idx])
			source = "regular"
			source_idx = real_idx + 1
		elif real_idx < total_regular + total_lkstyle:
			entry = BankData.materialize_entry(lkstyle[real_idx - total_regular])
			source = "lkstyle"
			source_idx = real_idx - total_regular + 1
		else:
			entry = BankData.materialize_entry(gc[real_idx - total_regular - total_lkstyle])
			source = "gc"
			source_idx = real_idx - total_regular - total_lkstyle + 1
		entry["_bank_source"] = source
		entry["_bank_idx"] = source_idx
		entry["_bank_tier"] = tier
		entry["_bank_rank"] = rank
		entry["_bank_transform"] = 0
	PaceEntryStamper.try_stamp(entry, pos)
	return entry


## 固定新手段使用 R1；第 51 关起保证至少 R2，其余保留当前策略。
static func resolve_strategy(level_num: int, current_strategy: int, fixed_r1_upper: int) -> int:
	if level_num <= fixed_r1_upper:
		return 1
	if level_num >= 51:
		return maxi(current_strategy, 2)
	return current_strategy
