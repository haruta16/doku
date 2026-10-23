## 从色彩挑战关卡库选题、校验区域、应用变换并生成重试参数。
## 成功投放会提交 GameState 的挑战计数与当前题目，因此 select 不是无副作用的随机查询。

class_name ColorChallengeSelector
extends RefCounted

const SINGLE_REGION_LIMIT: int = 1

const MAX_VALIDATE_RETRIES: int = 8


## 按已投放次数决定尺寸和难度，首次优先用指定题；成功后提交投放计数、题目标识和重试参数。
static func select(level_num: int, rank_override: int = 0, size_override: int = 0) -> Dictionary:
	var delivered: int = GameState.get_color_challenge_delivered()
	var rank: int = (
		rank_override
		if rank_override > 0
		else ColorChallengeGate.cc_rank(GameState.get_current_strategy(), delivered)
	)
	var sz: int = size_override if size_override > 0 else ColorChallengeGate.cc_size(delivered)

	var has_override: bool = rank_override > 0 or size_override > 0
	var picked: Dictionary = _pick_first_level() if delivered <= 0 and not has_override else {}
	if picked.is_empty():
		picked = _pick_with_fallback(sz, rank)
	if picked.is_empty():
		push_error(
			"[ColorChallenge] bank unavailable, sz=%d rank=%d delivered=%d" % [sz, rank, delivered]
		)
		return {}
	var entry: Dictionary = picked["entry"]
	var final_sz: int = picked["size"]
	var final_rank: int = picked["rank"]

	entry["_bank_source"] = ColorChallengeGate.BANK_SOURCE
	entry["_bank_source_main"] = ""
	entry["_bank_tier"] = ""
	entry["_bank_idx"] = int(picked["bank_idx"])
	entry["_bank_transform"] = int(picked["transform"])
	entry["size"] = final_sz
	entry["_delivery_size"] = final_sz
	entry["_delivery_rank"] = final_rank
	entry["_bank_rank"] = final_rank

	entry["_cc_delivery_index"] = delivered

	var region_map: Array = entry.get("regionMap", [])
	var puzzle_id: String = PuzzleDeduplicator.resolve_puzzle_id(entry, final_sz, region_map)

	var retry_params: Dictionary = RetryPuzzleBuilder.build(level_num, entry)

	retry_params["_cc_delivery_index"] = delivered
	entry["_puzzle_id"] = puzzle_id
	entry["_prefill_positions"] = retry_params.get("prefill_positions", [])
	entry["_strategy_steps"] = [
		int(retry_params.get("r1_steps", 0)),
		int(retry_params.get("r2_steps", 0)),
		int(retry_params.get("r3_steps", 0)),
		int(retry_params.get("r4_steps", 0)),
		int(retry_params.get("r5_steps", 0)),
	]

	GameState.commit_color_challenge_delivery(final_sz, final_rank)

	(
		GameState
		. finalize_selected_puzzle(
			level_num,
			{
				"puzzle_id": puzzle_id,
				"v": UniKitManager.get_version_name(),
				"src": ColorChallengeGate.BANK_SOURCE,
			},
			retry_params
		)
	)
	print(
		(
			"[ColorChallenge] deliver: sz=%d rank=%d idx=%d t=%d pid=%s (career #%d)"
			% [
				final_sz,
				final_rank,
				entry["_bank_idx"],
				entry["_bank_transform"],
				puzzle_id,
				GameState.get_color_challenge_delivered()
			]
		)
	)
	return entry


static func _pick_first_level() -> Dictionary:
	var raw: Dictionary = BankData.get_color_challenge_first_level()
	if raw.is_empty():
		return {}
	var sz: int = int(raw.get("size", ColorChallengeGate.FIRST_SIZE))
	var rank: int = int(raw.get("r", ColorChallengeGate.RANK_MIN))
	return _build_entry(raw, sz, rank, 0, 0)


## 目标分档缺题时依次尝试另一难度与备用尺寸，最终仍无题才返回空结果。
static func _pick_with_fallback(sz: int, rank: int) -> Dictionary:
	var picked: Dictionary = _pick(sz, rank)
	if not picked.is_empty():
		return picked
	var other_rank: int = (
		ColorChallengeGate.RANK_MAX
		if rank == ColorChallengeGate.RANK_MIN
		else ColorChallengeGate.RANK_MIN
	)
	picked = _pick(sz, other_rank)
	if not picked.is_empty():
		return picked
	for alt_sz: int in ColorChallengeGate.SIZE_CYCLE:
		if alt_sz == sz:
			continue
		for alt_rank: int in [ColorChallengeGate.RANK_MIN, ColorChallengeGate.RANK_MAX]:
			picked = _pick(alt_sz, alt_rank)
			if not picked.is_empty():
				return picked

	if sz != ColorChallengeGate.FIRST_SIZE:
		for alt_rank: int in [ColorChallengeGate.RANK_MIN, ColorChallengeGate.RANK_MAX]:
			picked = _pick(ColorChallengeGate.FIRST_SIZE, alt_rank)
			if not picked.is_empty():
				return picked
	return {}


## 按保存游标和变换轮次选候选，有限次尝试单格区域限制；全部不满足时保留最后候选并记录警告。
static func _pick(sz: int, rank: int) -> Dictionary:
	var levels: Array = BankData.get_color_challenge_levels(sz, rank)
	var count: int = levels.size()
	if count <= 0:
		return {}
	var cursor: int = GameState.get_color_challenge_index(sz, rank)
	var attempts: int = mini(MAX_VALIDATE_RETRIES, count)
	var last_result: Dictionary = {}
	for step: int in attempts:
		var idx: int = (cursor + step) % count
		@warning_ignore("integer_division")
		var transform: int = ((cursor + step) / count) % LevelData.TRANSFORM_COUNT
		last_result = _build_entry(levels[idx] as Dictionary, sz, rank, idx, transform)
		if _passes_single_region_limit(last_result["entry"].get("regionMap", [])):
			return last_result

	push_warning(
		"[ColorChallenge] no candidate within single-region limit, sz=%d rank=%d" % [sz, rank]
	)
	return last_result


## 把紧凑库记录展开成可玩棋盘并应用几何变换，输出题目和来源元信息。
static func _build_entry(
	raw: Dictionary, sz: int, rank: int, idx: int, transform: int
) -> Dictionary:
	var entry: Dictionary = BankData.materialize_entry(raw, true)

	var region_map: Array = []
	for row: Variant in entry.get("regionMap", []):
		var int_row: Array = []
		for cell: Variant in row as Array:
			int_row.append(int(cell))
		region_map.append(int_row)
	var solution: Array = []
	for col: Variant in entry.get("solution", []):
		solution.append(int(col))
	if transform > 0 and region_map.size() > 0:
		var transformed: Array = LevelData.apply_transform(
			region_map, solution, region_map.size(), transform
		)
		region_map = transformed[0]
		solution = transformed[1]
	entry["regionMap"] = region_map
	entry["solution"] = solution
	return {
		"entry": entry,
		"size": sz,
		"rank": rank,
		"bank_idx": idx + 1,
		"transform": transform,
	}


static func _passes_single_region_limit(region_map: Array) -> bool:
	return _count_single_regions(region_map) <= SINGLE_REGION_LIMIT


static func _count_single_regions(region_map: Array) -> int:
	if region_map.is_empty():
		return 0
	var counts: Dictionary = {}
	for row: Variant in region_map:
		for cell: Variant in row as Array:
			var region_id: int = int(cell)
			counts[region_id] = int(counts.get(region_id, 0)) + 1
	var single_count: int = 0
	for region_id: Variant in counts:
		if int(counts[region_id]) == 1:
			single_count += 1
	return single_count
