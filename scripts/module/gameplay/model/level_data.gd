# 关卡数据总表：难度曲线（关卡号 → 边长/策略/rank/tier）、题源选择、题库轮询取题、题目查重 ID
class_name LevelData
extends RefCounted

# ================= 难度曲线：边长表与难度判定 =================
const LEVEL_COUNT: int = 0 # 未被任何地方使用的占位常量（值恒为 0）
# 第 1~100 关的棋盘边长表，共 100 项，下标 = 关卡号 - 1
const SIZES: Array[int] = [
	4,
	4,
	5,
	5,
	6,
	5,
	5,
	6,
	6,
	7,
	6,
	6,
	6,
	6,
	7,
	6,
	7,
	6,
	7,
	8,
	6,
	7,
	6,
	7,
	8,
	6,
	7,
	8,
	7,
	8,
	6,
	7,
	6,
	7,
	8,
	6,
	7,
	8,
	7,
	8,
	6,
	7,
	6,
	7,
	8,
	6,
	7,
	8,
	7,
	8,
	6,
	7,
	8,
	7,
	9,
	6,
	7,
	8,
	9,
	10,
	6,
	7,
	8,
	7,
	9,
	6,
	7,
	8,
	9,
	10,
	6,
	7,
	8,
	7,
	9,
	6,
	7,
	8,
	9,
	10,
	6,
	7,
	8,
	7,
	9,
	6,
	7,
	8,
	9,
	10,
	6,
	7,
	8,
	7,
	9,
	6,
	7,
	8,
	9,
	10,
]

const _SIZES_101_PLUS: Array[int] = [7, 8, 7, 9, 10, 7, 8, 9, 8, 10] # 第 101 关起的边长表，按 (关卡号 - 101) % 10 循环

const _SIZES_GROUP_J_21_50: Array[int] = [6, 7, 6, 7, 8, 6, 7, 8, 8, 7] # 规则组 J（rule_normal_rank == 10）专用的边长表，分段边界与主表不同

const _SIZES_GROUP_J_51_100: Array[int] = [6, 7, 8, 7, 9, 6, 7, 8, 10, 9] # 51~100 段

const _SIZES_GROUP_J_101_PLUS: Array[int] = [7, 8, 7, 9, 10, 7, 8, 9, 10, 8] # 101 关以后，同样 10 关一循环


# 关卡号 → 棋盘边长：前 100 关查表，之后按 10 关一循环；关卡号非法返回 0
static func get_size(level_num: int) -> int:
	if level_num < 1: # 关卡号小于 1 视为无效
		return 0
	if level_num <= 100: # 前 100 关直接查表
		return SIZES[level_num - 1]
	return _SIZES_101_PLUS[(level_num - 101) % 10] # 101 关起每 10 关重复一轮


# 同上，但用于规则组 J：分段边界是 21 / 51 / 101
static func get_size_group_j(level_num: int) -> int:
	if level_num < 1:
		return 0
	if level_num < 21:
		return SIZES[level_num - 1] # 前 20 关沿用主表
	if level_num <= 50:
		return _SIZES_GROUP_J_21_50[(level_num - 21) % 10] # 21~50 段
	if level_num <= 100:
		return _SIZES_GROUP_J_51_100[(level_num - 51) % 10] # 51~100 段
	return _SIZES_GROUP_J_101_PLUS[(level_num - 101) % 10] # 101 关以后


# 是否难关（Boss 关）：21 关起每逢 10 的倍数，即 30 / 40 / 50…（第 20 关不算）
static func is_hard_level(level_num: int) -> bool:
	return level_num >= 21 and level_num % 10 == 0


# 组 J 的难关：29 关起每逢 9 结尾，即 29 / 39 / 49…
static func is_hard_level_group_j(level_num: int) -> bool:
	return level_num >= 29 and level_num % 10 == 9


# 是否里程碑特殊关：题目写死在 _SPECIAL_LEVELS 里，不走题库轮询
static func is_special_level(level_num: int) -> bool:
	return _SPECIAL_LEVELS.has(level_num)


# 策略号 → 题库 rank：5→4、6→5、7→5，其余原样（策略号是 rank 与 H 档的组合编码）
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


# 策略号 → 题库 tier：5 和 7 属于 H 档，其余是 N 档
static func strategy_to_tier(strategy: int) -> String:
	match strategy:
		5:
			return "H"
		7:
			return "H"
		_:
			return "N"


# 取当前难度策略：前 5 关固定 1；51 关起保底 2，并把提升结果写回存档
static func get_strategy(level_num: int) -> int:
	if level_num <= 5:
		return 1
	var strategy: int = GameState.get_current_strategy() # 玩家当前策略号，随连胜等成长
	if level_num >= 51 and strategy < 2:
		GameState.set_current_strategy(2) # 副作用：立即写存档
		strategy = 2
	return strategy


# ================= 题库进度推进（都会写存档） =================
# 取完一题后推进游标：lk_mod 走自己的计数器，其他来源走主进度 idx / since_lk
static func advance_for_entry(entry: Dictionary, sz: int) -> void:
	var rank: int = int(entry.get("_bank_rank", 1)) # 题目里带的题库元信息，由 get_next_entry / get_next_entry_main 写入
	var tier: String = entry.get("_bank_tier", "")
	var src_main: String = entry.get("_bank_source_main", "")
	if src_main == "": # 老题库路径：只推进 bank_index
		GameState.advance_bank_index(sz, rank, tier)
		return
	if src_main == "lk_mod": # LK 改造题：推进它自己的游标，并把主进度的「距上次 LK」清零
		var lkprog: Dictionary = GameState.get_lkmod_progress(sz, rank)
		lkprog["idx"] = lkprog.get("idx", 0) + 1
		GameState.set_lkmod_progress(sz, rank, lkprog)
		var prog: Dictionary = GameState.get_main_progress(sz, rank, tier)
		prog["since_lk"] = 0
		GameState.set_main_progress(sz, rank, tier, prog)
	else:
		var prog: Dictionary = GameState.get_main_progress(sz, rank, tier) # 其他来源：主进度 idx+1，并累计 since_lk（满 4 就插一道 LK 改造题）
		prog["idx"] = prog.get("idx", 0) + 1
		prog["since_lk"] = prog.get("since_lk", 0) + 1
		GameState.set_main_progress(sz, rank, tier, prog)


# ================= 取题：老入口（50 关及以前） =================
# 把 regular / lkstyle / gc 三段拼成一个池，按存档序号取模轮询；tier 为空表示不限档
# 返回题目字典（带 _bank_source/_bank_idx/_bank_tier/_bank_rank），池子空时返回 {}
static func get_next_entry(
	sz: int, rank: int, tier: String = "", remaining_attempts: int = -1
) -> Dictionary:
	# 三段题源：常规题 / LK 风格题 / GC 题，由 BankData 按 size+rank 索引
	var regular: Array = (
		BankData.get_levels_by_tier(sz, rank, tier) if tier != "" else BankData.get_levels(sz, rank)
	)
	var lkstyle: Array = (
		BankData.get_lk_style_levels_by_tier(sz, rank, tier)
		if tier != ""
		else BankData.get_lk_style_levels(sz, rank)
	)

	if tier != "" and regular.is_empty() and lkstyle.is_empty(): # tier 过滤后两段都空了，就退回该 rank 的全量题
		regular = BankData.get_levels(sz, rank)
		lkstyle = BankData.get_lk_style_levels(sz, rank)

	var gc: Array = []
	if (sz == 10 and rank == 1) or sz == 11: # GC 题只在 10x10 的 rank1 和 11x11 参与
		gc = (
			BankData.get_gc_levels_by_tier(sz, rank, tier)
			if tier != ""
			else BankData.get_gc_levels(sz, rank)
		)
		if tier != "" and gc.is_empty():
			gc = BankData.get_gc_levels(sz, rank)
	var total_regular: int = regular.size() # 三段加起来就是轮询用的总池
	var total_lkstyle: int = lkstyle.size()
	var total_gc: int = gc.size()
	var total: int = total_regular + total_lkstyle + total_gc
	if total == 0: # 一题都没有，交给调用方处理
		return {}

	if remaining_attempts < 0: # 负数表示首次进入，容错次数按池子大小给
		remaining_attempts = total
	var idx: int = GameState.get_bank_index(sz, rank, tier) # 存档里的池内序号，取模实现循环轮询
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

	# AB 实验过滤：单格区域超过 2 个就换下一题
	if (
		ABTestManager.single_region_num.is_single_region_limited()
		or ABTestManager.single_region_num.value() == SingleRegionNumConfig.VALUE_STRICT
	):
		var _rm: Array = entry.get("regionMap", []) # 数一数每个区域占几格，统计一格大小的区域个数
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
			if _single > 2: # 不合格
				if remaining_attempts <= 1: # 重取次数用尽：报错后容错返回，避免卡死
					push_error(
						(
							"LevelData.get_next_entry: single_region_num 过滤后连续 %d 次无合格题,容错返回 sz=%d rank=%d tier=%s"
							% [total, sz, rank, tier]
						)
					)
				else:
					GameState.advance_bank_index(sz, rank, tier) # 否则推进游标换下一题再来一轮
					return get_next_entry(sz, rank, tier, remaining_attempts - 1)

	if not QueendokuCore.validate_solution_entry(entry, sz): # 答案自检：区域图尺寸、列号合法，且摆出来确实能通关
		push_error(
			(
				"LevelData.get_next_entry: invalid solution sz=%d rank=%d tier=%s source=%s idx=%d, advancing"
				% [sz, rank, tier, source, source_idx]
			)
		)
		if remaining_attempts <= 1: # 池子里连续多题都不合法：报错后容错返回最后一题
			push_error(
				(
					"LevelData.get_next_entry: 题库内连续 %d 题都不合法,容错返回最后 entry sz=%d rank=%d tier=%s"
					% [total, sz, rank, tier]
				)
			)
			return entry
		GameState.advance_bank_index(sz, rank, tier) # 不合法就推进游标重取
		return get_next_entry(sz, rank, tier, remaining_attempts - 1)

	advance_for_entry(entry, sz) # 通过校验才推进游标（写存档）
	return entry


# ================= 开局送格（仅前 10 关） =================
# 1~6 关送「所在区域不止一格」的答案格，7~10 关改送「独占一个小区域」的答案格
# 返回 [行, 列]；不适用或找不到时返回 []（调用方按「不给提示」处理）
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
# LK 改造题库里预留给特殊关的下标（1-based），常规轮询会跳过这几题
const LK_MOD_RESERVED: Array[int] = [20, 30, 53, 71, 72, 75, 114, 141, 164]

const TRANSFORM_COUNT: int = 8 # 一道题的对称变换总数：4 种旋转 × 是否左右镜像


# 对题目做第 t 种对称变换，返回 [region_map, solution]；solution 是「每行猫所在列号」的一维数组
# 题库轮换只用 t ∈ 0~7；cheat 面板允许 0~11，多出的 8~11 才会同时用上左右与上下镜像
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


# 变换序号 → 题号后缀（第 0 种是规范形，不写后缀）
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


# 题目的稳定查重 ID：8 种对称变换里字典序最小的形态当规范形，取规范形的 sha256 前 16 位
# 返回 "边长_哈希"；当前朝向不是规范形时再补后缀（r90/h/hr270…）
# 调用方拿它调 GameState.record_puzzle 判重，近期出现过的题会被换掉
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


# 只变换区域图、不动 solution 的版本，compute_puzzle_id 算规范形时用
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


# 按行优先首次出现的顺序把区域号重编成 0,1,2…，消除编号命名差异，便于两份区域图比较
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


# 把二维区域图拍成逗号分隔字符串，用于比较与取哈希
static func _serialize_region_map(region_map: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for row in region_map:
		for v in row:
			parts.append(str(int(v)))
	return ",".join(parts)


# ================= 取题：主线入口（51 关及以后） =================
# 四段题源轮询：lk_mod 改造题 + regular + lkstyle + gc；每连取 4 道常规题插一道 LK 改造题
# 一整池取完就换下一种对称变换重来；进度来自存档里的 idx / since_lk / transform
static func get_next_entry_main(
	sz: int, rank: int, tier: String, remaining_attempts: int = -1, strict_rank: bool = false
) -> Dictionary:
	var lk_mod_all: Array = BankData.get_lk_modified_levels() # LK 改造题全量，下面再按边长和 rank 过滤

	var lk_mod: Array = []
	for i: int in range(lk_mod_all.size()):
		if (i + 1) in LK_MOD_RESERVED: # 预留给特殊关的题不参与常规轮询
			continue
		var e: Dictionary = lk_mod_all[i]
		if int(e.get("size", 0)) != sz:
			continue
		var e_rank: int = int(e.get("r", 1)) if strict_rank else int(e.get("maxR", e.get("r", 1))) # strict_rank 时只看 r，否则退一步看 maxR（宽松匹配）
		if e_rank != rank:
			continue
		lk_mod.append(e)

	# 三段常规题源，取法与 get_next_entry 相同
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

	if sz == 10 and rank in [3, 4]: # 10x10 的 rank3/4 不用常规题库
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

	var total_lk_mod: int = lk_mod.size() # 四段池子各自的大小与总大小
	var total_regular: int = regular.size()
	var total_lkstyle: int = lkstyle.size()
	var total_gc: int = gc.size()
	var total: int = total_lk_mod + total_regular + total_lkstyle + total_gc
	if total == 0:
		return {}

	var prog: Dictionary = GameState.get_main_progress(sz, rank, tier) # 主进度：池内序号 idx、距上次 LK 改造题的题数 since_lk、对称变换 transform
	var transform: int = prog.get("transform", 0)

	var idx: int = prog.get("idx", -1)
	var since_lk: int = prog.get("since_lk", 0)

	if idx < 0: # idx < 0 说明是没写过主进度的旧存档：从老的 bank_index 折算起点再写回
		var legacy_idx: int = GameState.get_bank_index(sz, rank, tier)
		var denom: int = total_regular + total_lkstyle
		idx = legacy_idx % denom if (legacy_idx > 0 and denom > 0) else 0
		since_lk = 0
		prog["idx"] = idx
		prog["since_lk"] = since_lk
		GameState.set_main_progress(sz, rank, tier, prog)

	var lkprog: Dictionary = GameState.get_lkmod_progress(sz, rank) # LK 改造题有独立游标，与主进度分开记
	var lk_idx: int = lkprog.get("idx", 0)

	if idx >= total_regular + total_lkstyle + total_gc: # idx 超出池子 = 这一轮取完：换下一种对称变换、从头开始
		transform = (transform + 1) % TRANSFORM_COUNT
		idx = 0
		since_lk = 0
		prog = {"idx": 0, "since_lk": 0, "transform": transform}
		GameState.set_main_progress(sz, rank, tier, prog)

	var entry: Dictionary
	var source: String
	var source_idx: int

	if since_lk >= 4 and lk_idx < total_lk_mod: # 每连取 4 道常规题就插一道 LK 改造题（还有剩余的话）
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

	entry["_bank_source"] = source # 写回题库元信息，供难度统计、查重和推进游标使用
	entry["_bank_source_main"] = source
	entry["_bank_idx"] = source_idx
	entry["_bank_tier"] = tier
	entry["_bank_rank"] = rank
	entry["_bank_transform"] = transform

	# AB 实验过滤：限制单格区域数量，lk_mod / sp / lk 来源豁免
	if (
		(
			ABTestManager.single_region_num.is_single_region_limited()
			or ABTestManager.single_region_num.value() == SingleRegionNumConfig.VALUE_STRICT
		)
		and source != "lk_mod"
		and source != "sp"
		and source != "lk"
	):
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
			if _single > 2:
				if remaining_attempts < 0: # 容错次数上限 = 池子大小 × 变换数
					remaining_attempts = total * TRANSFORM_COUNT
				if remaining_attempts <= 1: # 用尽了：报错后容错返回当前这题
					push_error(
						(
							"LevelData.get_next_entry_main: single_region_num 过滤后连续 %d 次无合格题,容错返回 sz=%d rank=%d tier=%s"
							% [total * TRANSFORM_COUNT, sz, rank, tier]
						)
					)
				else:
					if source == "lk_mod": # 换下一题：推进对应来源的游标（写存档）
						var lkprog_s: Dictionary = GameState.get_lkmod_progress(sz, rank)
						lkprog_s["idx"] = lkprog_s.get("idx", 0) + 1
						GameState.set_lkmod_progress(sz, rank, lkprog_s)
					else:
						var prog_s: Dictionary = GameState.get_main_progress(sz, rank, tier)
						prog_s["idx"] = prog_s.get("idx", 0) + 1
						GameState.set_main_progress(sz, rank, tier, prog_s)
					return get_next_entry_main(sz, rank, tier, remaining_attempts - 1, strict_rank)

	if remaining_attempts < 0: # 若前面 AB 过滤没触发过，这里补上默认容错次数
		remaining_attempts = total * TRANSFORM_COUNT
	if not QueendokuCore.validate_solution_entry(entry, sz): # 答案自检，不合法就推进游标重取
		push_error(
			(
				"LevelData.get_next_entry_main: invalid solution sz=%d rank=%d tier=%s source=%s idx=%d transform=%d, advancing"
				% [sz, rank, tier, source, source_idx, transform]
			)
		)
		if remaining_attempts <= 1: # 全部重取完仍不合法：报错后容错返回
			push_error(
				(
					"LevelData.get_next_entry_main: 三合一题库连续 %d 次取题都不合法,容错返回最后 entry sz=%d rank=%d tier=%s"
					% [total * TRANSFORM_COUNT, sz, rank, tier]
				)
			)
			return entry
		if source == "lk_mod": # 不合法时同样要推进游标，否则会反复取到同一题
			var lkprog2: Dictionary = GameState.get_lkmod_progress(sz, rank)
			lkprog2["idx"] = lkprog2.get("idx", 0) + 1
			GameState.set_lkmod_progress(sz, rank, lkprog2)
		else:
			prog["idx"] = prog.get("idx", 0) + 1
			GameState.set_main_progress(sz, rank, tier, prog)
		return get_next_entry_main(sz, rank, tier, remaining_attempts - 1)

	advance_for_entry(entry, sz) # 通过校验才推进游标
	return entry


# ================= 特殊关表与取题总入口 =================
# 里程碑关的固定题目：关号 → {题源 "sp"/"lk", 1-based 下标}；sp = bankDataSP，lk = bankDataLK
# 这些关不参与题库轮询
const _SPECIAL_LEVELS: Dictionary = {
	10: {"source": "sp", "index": 44},
	20: {"source": "sp", "index": 45},
	30: {"source": "sp", "index": 36},
	40: {"source": "sp", "index": 9},
	50: {"source": "sp", "index": 37},
	55: {"source": "sp", "index": 7},
	60: {"source": "sp", "index": 34},
	62: {"source": "sp", "index": 8},
	70: {"source": "sp", "index": 32},
	75: {"source": "sp", "index": 6},
	80: {"source": "sp", "index": 43},
	90: {"source": "sp", "index": 33},
	100: {"source": "sp", "index": 5},
	123: {"source": "sp", "index": 1},
	200: {"source": "lk", "index": 30},
	250: {"source": "lk", "index": 75},
	314: {"source": "lk", "index": 141},
	456: {"source": "sp", "index": 2},
}


# 关卡号 → 关卡数据 entry 的总入口：先查特殊关，再按 AB 规则算边长 / rank / tier，最后交给取题函数
# override_sz > 0 时强制使用该边长；命中特殊关失败则继续走常规曲线
static func get_level_entry(level_num: int, override_sz: int = 0) -> Dictionary:
	var rnr: int = ABTestManager.rule_normal_rank.value() # AB 实验里的难度规则编号（1~11），决定曲线怎么裁剪

	var special_levels: Dictionary = _SPECIAL_LEVELS.duplicate() # 复制一份特殊关表，便于按 AB 开关替换其中一条
	if level_num == 10 and ABTestManager.normal_level_10.is_sp57_at_level10():
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

	var strategy: int # 下面按 rnr 与关卡号决定策略号，再映射成 rank + tier
	var rank: int
	var tier: String

	var is_hard: bool = is_hard_level_group_j(level_num) if rnr == 10 else is_hard_level(level_num) # 难关（每 10 关一个）不走随机，直接给最难的档位

	if is_hard: # 难关分支：不同 rnr 给的档位不同
		strategy = GameState.get_current_strategy()
		if rnr == 4 or rnr == 5:
			rank = 5
			tier = "N"
		elif rnr == 8:
			rank = 5
			tier = "N"
		elif rnr == 9:
			rank = 4
			tier = "N"
		elif rnr == 10:
			if level_num >= 201:
				if strategy >= 6:
					rank = 5
					tier = "H"
				else:
					rank = 5
					tier = "N"
			elif level_num >= 101:
				rank = 5
				tier = "N"
			elif level_num >= 51:
				if strategy >= 4:
					rank = 5
					tier = "N"
				else:
					rank = 4
					tier = "N"
			else:
				rank = 4
				tier = "N"
		elif level_num >= 201:
			if strategy >= 6:
				if rnr == 11 and randi() % 2 == 0:
					rank = 5
					tier = "N"
				else:
					rank = 5
					tier = "H"
			else:
				rank = 5
				tier = "N"
		else:
			rank = 5
			tier = "N"
	else: # 普通关分支：先取当前策略，按关卡段位封顶，再按 rnr 随机化
		strategy = get_strategy(level_num)

		# rnr 6/7 的 mod1 豁免：51 关起每逢 x1 关降难度，并按需消耗每日首局降档
		var is_mod1_exempt: bool = (
			(rnr == 6 or rnr == 7) and level_num >= 51 and level_num % 10 == 1
		)
		if is_mod1_exempt: # 豁免分支：算完 rank/tier 就直接取题返回
			if level_num >= 101:
				strategy = randi_range(2, 3)
			else:
				strategy = 2

			if GameState.is_daily_first_easy_available() and strategy > 1: # 每日首局降一档，消耗掉当天的机会（写存档）
				strategy -= 1
				GameState.consume_daily_first_easy_and_mark()
			rank = strategy_to_rank(strategy)
			tier = strategy_to_tier(strategy)
			if tier == "N": # N 档查不到题就退回不带 tier 的全量题
				var sample: Array = BankData.get_levels_by_tier(sz, rank, "N")
				if sample.is_empty():
					sample = BankData.get_lk_style_levels_by_tier(sz, rank, "N")
				if sample.is_empty():
					tier = ""

			GameState.mark_rnr_mod1_exempt() # 记录本次豁免，供其他系统查询
			return get_next_entry_main(sz, rank, tier, -1, false)

		if rnr == 1: # 按 rnr 给出各关卡段的策略上限（越靠后的段允许越难）
			if level_num >= 51:
				strategy = min(strategy, 4)
			elif level_num >= 21:
				strategy = min(strategy, 3)
			else:
				strategy = min(strategy, 2)
		elif rnr == 4 or rnr == 5:
			if level_num >= 101:
				strategy = min(strategy, 5)
			elif level_num >= 51:
				strategy = min(strategy, 4)
			elif level_num >= 21:
				strategy = min(strategy, 3)
			else:
				strategy = min(strategy, 2)
		elif rnr == 8:
			if level_num >= 51:
				strategy = min(strategy, 4)
			elif level_num >= 21:
				strategy = min(strategy, 3)
			else:
				strategy = min(strategy, 2)
		elif rnr == 9:
			if level_num >= 21:
				strategy = min(strategy, 3)
			else:
				strategy = min(strategy, 2)
		elif rnr == 10:
			if level_num >= 201:
				strategy = min(strategy, 6)
			elif level_num >= 101:
				strategy = min(strategy, 5)
			elif level_num >= 51:
				strategy = min(strategy, 4)
			elif level_num >= 21:
				strategy = min(strategy, 3)
			else:
				strategy = min(strategy, 2)
		else:
			if level_num >= 201:
				strategy = min(strategy, 6)
			elif level_num >= 101:
				strategy = min(strategy, 5)
			elif level_num >= 51:
				strategy = min(strategy, 4)
			elif level_num >= 21:
				strategy = min(strategy, 3)
			else:
				strategy = min(strategy, 2)

		if rnr == 2 and strategy >= 3: # 按 rnr 在 [下限, 上限] 之间随机抽一个策略
			strategy = randi_range(2, strategy)
		elif rnr == 3 and strategy >= 3:
			strategy = randi_range(max(2, strategy - 1), strategy)
		elif rnr == 4: # rnr 4 的下限：51 关起从 2 开始，之前允许 1
			var lower: int = 2 if level_num >= 51 else 1
			strategy = randi_range(lower, strategy)
		elif rnr == 5 and level_num >= 101:
			strategy = randi_range(2, strategy)
		elif rnr == 6 and strategy >= 3:
			strategy = randi_range(2, strategy)
		elif rnr == 7 and strategy >= 3:
			var seg_max: int = strategy # rnr 7 额外约束：上一题已经顶到上限的话，这题不再连顶

			if level_num > 50 and GameState.is_rnr_g_prev_was_max():
				strategy = max(2, strategy - 1)
			strategy = randi_range(2, strategy)

			GameState.set_rnr_g_prev_was_max(strategy == seg_max)
		elif rnr == 8 and strategy >= 3:
			strategy = randi_range(2, strategy)
		elif rnr == 9 and strategy >= 3:
			strategy = randi_range(2, strategy)
		elif rnr == 10 and strategy >= 3:
			strategy = randi_range(2, strategy)
		elif rnr == 11 and strategy >= 3:
			strategy = randi_range(2, strategy)

		if GameState.is_daily_first_easy_available() and strategy > 1: # 每日首局降一档（与上面的豁免分支只会触发一处）
			strategy -= 1
			GameState.consume_daily_first_easy_and_mark()
		rank = strategy_to_rank(strategy) # 策略号映射成题库的 rank + tier
		tier = strategy_to_tier(strategy)

		if tier == "N": # N 档查不到题就退回不带 tier 的全量题
			var sample: Array = BankData.get_levels_by_tier(sz, rank, "N")
			if sample.is_empty():
				sample = BankData.get_lk_style_levels_by_tier(sz, rank, "N")
			if sample.is_empty():
				tier = ""

	return _get_next_entry_with_filter(sz, rank, tier, level_num, is_hard) # 交给统一的过滤 + 取题函数


# 取题收口：51 关起走四段轮询（get_next_entry_main），前 50 关走老的三段轮询，再叠一层 AB 严格过滤
static func _get_next_entry_with_filter(
	sz: int, rank: int, tier: String, level_num: int, is_hard: bool, remaining: int = -1
) -> Dictionary:
	var entry: Dictionary # 51 关是分界线：之后才用带对称变换的题库
	if level_num >= 51:
		entry = get_next_entry_main(sz, rank, tier, -1, is_hard)
	else:
		entry = get_next_entry(sz, rank, tier)

	if ABTestManager.single_region_num.is_strict_limited_at(level_num) and not entry.is_empty(): # AB 严格档：单格区域最多 1 个，lk_mod / sp / lk 来源豁免
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
							sz, rank, tier, level_num, is_hard, remaining - 1
						)
	return entry
