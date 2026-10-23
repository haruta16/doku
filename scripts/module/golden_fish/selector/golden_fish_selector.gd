## 金鱼关选题器；依据投放次数决定尺寸和难度，从 OneFish 关卡库取题并执行缺库回退。

class_name GoldenFishSelector
extends RefCounted


## 读取实验选题策略与金鱼投放次数，从 OneFish 库取得候选并建立关卡交付信息。
static func select(level_num: int) -> Dictionary:
	var gf: GoldenFishFuncConfig = ABTestManager.golden_fish_func
	var shuffled: bool = gf.uses_shuffled_pick()

	GameState.note_onefish_pick_group(gf.current_group())

	var delivered: int = GameState.get_golden_fish_insert_delivered()
	var rank: int = _resolve_insert_rank(gf, delivered)
	var sz: int = GoldenFishGate.insert_size(
		delivered, GameState.get_onefish_pick_switch_anchor(), gf.uses_upsized_size_cycle()
	)
	var picked: Dictionary = _pick_with_fallback(sz, rank, shuffled)
	if picked.is_empty():
		push_error("[GoldenFish] onefish bank unavailable, sz=%d rank=%d" % [sz, rank])
		return {}
	var entry: Dictionary = picked["entry"]
	var final_sz: int = picked["size"]
	var final_rank: int = picked["rank"]

	entry["_bank_source"] = GoldenFishGate.INSERT_BANK_SOURCE
	entry["_bank_source_main"] = ""
	entry["_bank_tier"] = ""
	entry["_bank_idx"] = int(picked["bank_idx"])
	entry["_bank_transform"] = int(picked["transform"])
	entry["size"] = final_sz
	entry["_delivery_size"] = final_sz
	entry["_delivery_rank"] = final_rank
	entry["_bank_rank"] = final_rank

	var region_map: Array = entry.get("regionMap", [])
	var puzzle_id: String = PuzzleDeduplicator.resolve_puzzle_id(entry, final_sz, region_map)

	var retry_params: Dictionary = RetryPuzzleBuilder.build(level_num, entry)
	entry["_puzzle_id"] = puzzle_id
	entry["_prefill_positions"] = retry_params.get("prefill_positions", [])
	entry["_strategy_steps"] = [
		int(retry_params.get("r1_steps", 0)),
		int(retry_params.get("r2_steps", 0)),
		int(retry_params.get("r3_steps", 0)),
		int(retry_params.get("r4_steps", 0)),
		int(retry_params.get("r5_steps", 0)),
	]

	var used_idx: int = int(picked["bank_idx"]) - 1
	var used_count: int = int(picked["count"])
	if shuffled:
		GameState.commit_onefish_shuffle_delivery(final_sz, final_rank, used_idx, used_count, false)
	else:
		GameState.commit_onefish_delivery(final_sz, final_rank, used_idx, used_count, false)

	(
		GameState
		. finalize_selected_puzzle(
			level_num,
			{
				"puzzle_id": puzzle_id,
				"v": UniKitManager.get_version_name(),
				"nl": ABTestManager.normal_level.value(),
				"src": GoldenFishGate.INSERT_BANK_SOURCE,
			},
			retry_params
		)
	)
	print(
		(
			"[GoldenFish] deliver insert level: sz=%d rank=%d idx=%d t=%d pid=%s (career #%d)"
			% [
				final_sz,
				final_rank,
				entry["_bank_idx"],
				entry["_bank_transform"],
				puzzle_id,
				GameState.get_golden_fish_insert_delivered()
			]
		)
	)
	return entry


## 在目标尺寸/难度没有可用题时查找备用分档，集中处理关卡库缺口。
static func _pick_with_fallback(sz: int, rank: int, shuffled: bool) -> Dictionary:
	var picked: Dictionary = _pick(sz, rank, shuffled)
	if not picked.is_empty():
		return picked

	push_error("[GoldenFish] onefish 池取不到题: sz=%d rank=%d —— 即将换档兜底,该组难度分布会偏斜" % [sz, rank])
	var other_rank: int = (
		GoldenFishGate.INSERT_RANK_MAX
		if rank == GoldenFishGate.INSERT_RANK_MIN
		else GoldenFishGate.INSERT_RANK_MIN
	)
	picked = _pick(sz, other_rank, shuffled)
	if not picked.is_empty():
		return picked
	var alt_sizes: Array = BankData.get_onefish_sizes()
	for alt_sz: int in alt_sizes:
		if alt_sz == sz:
			continue
		var alt_ranks: Array = BankData.get_onefish_ranks(alt_sz)
		for alt_rank: int in alt_ranks:
			picked = _pick(alt_sz, alt_rank, shuffled)
			if not picked.is_empty():
				return picked
	return {}


static func _resolve_insert_rank(gf: GoldenFishFuncConfig, delivered: int) -> int:
	if delivered == 0 and gf.uses_random_first_rank():
		return _pick_uniform([GoldenFishGate.INSERT_RANK_MIN, GoldenFishGate.INSERT_RANK_MAX])
	if gf.uses_alternating_rank():
		return GoldenFishGate.insert_rank_alternating(
			delivered, GameState.get_onefish_pick_switch_anchor()
		)
	if gf.uses_diff_ext_rank():
		return _pick_uniform(
			GoldenFishGate.diff_ext_rank_candidates(GameState.get_current_strategy())
		)
	return GoldenFishGate.insert_rank(GameState.get_current_strategy())


static func _pick_uniform(candidates: Array[int]) -> int:
	if candidates.size() == 1:
		return candidates[0]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _pick(sz: int, rank: int, shuffled: bool) -> Dictionary:
	var levels: Array = BankData.get_onefish_levels(sz, rank)
	var count: int = levels.size()
	if count <= 0:
		return {}
	var idx: int = 0

	var transform: int = GameState.get_onefish_cycle_round(sz, rank) % LevelData.TRANSFORM_COUNT
	if shuffled:
		var draw: Dictionary = GameState.next_onefish_shuffle_draw(sz, rank, count)
		if draw.is_empty():
			return {}
		idx = int(draw["idx"])
	else:
		idx = GameState.next_onefish_sequential_draw(sz, rank, count)
		if idx < 0:
			return {}
	var entry: Dictionary = BankData.materialize_entry(levels[idx] as Dictionary, true)

	var region_map: Array = []
	for row: Variant in entry.get("regionMap", []):
		var int_row: Array = []
		for v: Variant in row as Array:
			int_row.append(int(v))
		region_map.append(int_row)
	var solution: Array = []
	for v: Variant in entry.get("solution", []):
		solution.append(int(v))
	if transform > 0 and region_map.size() > 0:
		var result: Array = LevelData.apply_transform(
			region_map, solution, region_map.size(), transform
		)
		region_map = result[0]
		solution = result[1]
	entry["regionMap"] = region_map
	entry["solution"] = solution
	return {
		"entry": entry,
		"size": sz,
		"rank": rank,
		"bank_idx": idx + 1,
		"transform": transform,
		"count": count,
	}
