## 旧诊断/内容测试入口的纯候选适配；正式关卡使用完整1.22策略。
## 保留前框架有界拒绝循环与一次性LK语义，不接入全局状态。
class_name LegacySelectionAdapter
extends RefCounted

static func get_next_entry(
	sz: int, rank: int, tier: String = "", remaining_attempts: int = -1,
	selection_state: Variant = null, selection_policy: Dictionary = {}
) -> Dictionary:
	var source_state: Variant = selection_state if selection_state != null else DokuSelectionState.new({})
	var pools: Dictionary = DokuMainSelectionRules.cycling_pools(sz, rank, tier, false,
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

		if int(selection_policy.get("single_region", 0)) in [1, 2] and _exceeds_single_region_limit(entry.regionMap):
			if remaining_attempts > 1:
				source_state.advance_bank_index(sz, rank, tier)
				remaining_attempts -= 1
				continue
			# 保留已有降级策略：没有符合 AB 偏好的题时仍可玩这张合法题。
			push_warning("LevelData.get_next_entry: 单格区域筛选耗尽，沿用最后合法候选")

		LevelData.advance_for_entry(entry, sz, source_state)
		return entry
	return {}

static func get_next_entry_main(
	sz: int, rank: int, tier: String, remaining_attempts: int = -1, strict_rank: bool = false,
	selection_state: Variant = null, selection_policy: Dictionary = {}
) -> Dictionary:
	var source_state: Variant = selection_state if selection_state != null else DokuSelectionState.new({})
	var lk_mod: Array = LevelData._lk_modified_pool(sz, rank, strict_rank)

	var pools: Dictionary = DokuMainSelectionRules.cycling_pools(sz, rank, tier, true,
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

	remaining_attempts = maxi(1, total * LevelData.TRANSFORM_COUNT if remaining_attempts < 0 else remaining_attempts)
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
			transform = (transform + 1) % LevelData.TRANSFORM_COUNT
			idx = 0
			since_lk = 0
			prog = {"idx": 0, "since_lk": 0, "transform": transform}
			source_state.set_main_progress(sz, rank, tier, prog)

		var entry: Dictionary
		var source: String
		var source_idx: int

		if (since_lk >= 4 or regular_pool_size == 0) and lk_idx < total_lk_mod: # 无常规题时直接使用剩余 LK，否则每 4 道插一道
			entry = BankData.materialize_entry(lk_mod[lk_idx])
			source = "lk_mod"
			source_idx = lk_idx + 1
		elif idx < total_regular: # 否则按 idx 落在 regular / lkstyle / gc 哪一段取题
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
			# 逻辑上到不了这里，兜底取第一道常规题并记错误日志
			push_error(
				(
					"LevelData.get_next_entry_main: unexpected else branch sz=%d rank=%d tier=%s idx=%d"
					% [sz, rank, tier, idx]
				)
			)
			entry = BankData.materialize_entry(regular[0]) if not regular.is_empty() else {}
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
				lk_mod = LevelData._lk_modified_pool(sz, rank, false)
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
			var result: Array = LevelData.apply_transform(rm, sol, sz, transform)
			entry["regionMap"] = result[0]
			entry["solution"] = result[1]

		if int(selection_policy.get("single_region", 0)) in [1, 2] and source not in ["lk_mod", "sp", "lk"] and _exceeds_single_region_limit(entry.regionMap):
			if remaining_attempts > 1:
				prog["idx"] = idx + 1
				source_state.set_main_progress(sz, rank, tier, prog)
				remaining_attempts -= 1
				continue
			push_warning("LevelData.get_next_entry_main: 单格区域筛选耗尽，沿用最后合法候选")

		LevelData.advance_for_entry(entry, sz, source_state)
		return entry
	return {}

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
