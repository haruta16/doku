## 重试锁题参数构建：把已校验题目映射为游戏页参数，保留预填、配色、策略步骤与 Elo 信息。
class_name RetryPuzzleBuilder
extends RefCounted

const ENTRY_KEY_HARD_NEIGHBOR_EASED: String = "_hard_neighbor_eased"

const KEY_HARD_NEIGHBOR_EASED: String = "hard_neighbor_eased"


## 根据交付题目生成可重进同题的参数字典；步骤全缺时按最高层级补回退统计。
static func build(level_num: int, entry: Dictionary) -> Dictionary:
	var size: int = int(entry.get("_delivery_size", entry.get("size", 0)))
	var rank: int = int(entry.get("_delivery_rank", 1))
	var regions: Array = entry.get("regionMap", [])
	var solution: Array = entry.get("solution", [])
	var prefill_pos: Array = LevelData.compute_prefill(level_num, regions, solution, size)

	var strategy_steps: Array[int] = [
		int(entry.get("r1", 0)),
		int(entry.get("r2", 0)),
		int(entry.get("r3", 0)),
		int(entry.get("r4", 0)),
		int(entry.get("r5", 0)),
	]

	if strategy_steps.all(func(value: int) -> bool: return value == 0):
		var fallback_r: int = int(entry.get("r", entry.get("maxR", 0)))
		if fallback_r >= 1 and fallback_r <= 5:
			strategy_steps[fallback_r - 1] = int(entry.get("steps", 1))

	var is_elo_delivery: bool = bool(entry.get("is_elo_delivery", false))

	var result: Dictionary = {
		"bank_mode": true,
		"bank_size": size,
		"bank_rank": rank,
		"bank_index": entry.get("_bank_idx", 0),
		"prebuilt_regions": regions,
		"prebuilt_solution": solution,
		"level_seed": entry.get("seed", 0),
		"prefill_positions": [prefill_pos] if not prefill_pos.is_empty() else [],
		"custom_color_map": entry.get("colorMap", []),
		"spRegion": entry.get("spRegion", []),
		"retry_level": level_num,
		"bank_source": entry.get("_bank_source", "regular"),
		"bank_source_main": entry.get("_bank_source_main", ""),
		"bank_tier": entry.get("_bank_tier", ""),
		"rating": entry.get("rating", 0.0),
		"is_elo_delivery": is_elo_delivery,
		"eloRating": entry.get("eloRating", -1.0) if is_elo_delivery else -1.0,
		"_elo_e": entry.get("_elo_e", -1.0) if is_elo_delivery else -1.0,
		"_elo_k": entry.get("_elo_k", -1.0) if is_elo_delivery else -1.0,
		"_elo_player_rating": entry.get("_elo_player_rating", -1.0) if is_elo_delivery else -1.0,
		"r1_steps": strategy_steps[0],
		"r2_steps": strategy_steps[1],
		"r3_steps": strategy_steps[2],
		"r4_steps": strategy_steps[3],
		"r5_steps": strategy_steps[4],
		KEY_HARD_NEIGHBOR_EASED: bool(entry.get(ENTRY_KEY_HARD_NEIGHBOR_EASED, false)),
	}
	if entry.has("elo_v2_style_vector"):
		result["_puzzle_id"] = str(entry.get("_puzzle_id", ""))
		var style: Dictionary = entry.get("elo_v2_style_vector", {})
		result["style_vector"] = style.duplicate(true)
	return result
