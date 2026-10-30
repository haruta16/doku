## 第六版难度约束：按实验组限制 R4 出现时点、题目评分和单格区域数量，并提供回退选题。
class_name DifficultyV6Rules
extends RefCounted

const VARIANT_HARD_RATING: int = 1
const VARIANT_R4_EARLY_MILD: int = 2
const VARIANT_R4_EARLY_AGGRESSIVE: int = 3

const CONTROL_R4_NODE_LEVEL: int = 51
const R3_NODE_LEVEL: int = 21
const R4_CONSTRAINT_END_LEVEL: int = 70
const R4_RATING_CAP: int = 7032
const NO_CAP: int = -1
const NO_SINGLE_REQUIREMENT: int = -1

const _HARD_RATING_SEGMENTS: Array[Dictionary] = [
	{"from": 101, "to": 200, "cap": 15133},
	{"from": 201, "to": 400, "cap": 15838},
	{"from": 401, "to": 600, "cap": 16454},
]

const _R4_NODE_LEVEL_BY_VARIANT: Dictionary = {
	VARIANT_R4_EARLY_MILD: 41,
	VARIANT_R4_EARLY_AGGRESSIVE: 31,
}

const _ALTERNATE_START_BY_VARIANT: Dictionary = {
	VARIANT_R4_EARLY_MILD: 51,
	VARIANT_R4_EARLY_AGGRESSIVE: 41,
}


## 按关号区间读取困难题评分上限，未覆盖区间返回 -1 表示不限。
static func hard_rating_cap(level_num: int) -> int:
	for segment: Dictionary in _HARD_RATING_SEGMENTS:
		if level_num >= int(segment["from"]) and level_num <= int(segment["to"]):
			return int(segment["cap"])
	return NO_CAP


## 读取实验组引入 R4 的关号，未配置时采用对照组节点。
static func r4_node_level(variant: int) -> int:
	return int(_R4_NODE_LEVEL_BY_VARIANT.get(variant, CONTROL_R4_NODE_LEVEL))


## 根据关号与实验组节点给出允许的最高解题策略层级。
static func strategy_cap(level_num: int, variant: int) -> int:
	if level_num >= r4_node_level(variant):
		return 4
	if level_num >= R3_NODE_LEVEL:
		return 3
	return 2


## 判断是否处于该实验方案的 R4 单格区域限制区间。
static func is_r4_constraint_level(level_num: int, variant: int) -> bool:
	if not _R4_NODE_LEVEL_BY_VARIANT.has(variant):
		return false
	return level_num >= r4_node_level(variant) and level_num <= R4_CONSTRAINT_END_LEVEL


## 在 R4 限制区间内，判断是否已经进入单格数量交替阶段。
static func is_alternate_level(level_num: int, variant: int) -> bool:
	if not is_r4_constraint_level(level_num, variant):
		return false
	return level_num >= int(_ALTERNATE_START_BY_VARIANT[variant])


## 返回必须具有的单格区域数；交替阶段按已交付次数奇偶切换，不适用时为 -1。
static func required_single_count(level_num: int, variant: int, delivered_alternate_r4: int) -> int:
	if not is_r4_constraint_level(level_num, variant):
		return NO_SINGLE_REQUIREMENT
	if is_alternate_level(level_num, variant):
		return delivered_alternate_r4 % 2
	return 1


## 只有评分上限有效且题目带评分时，才判断是否超过上限。
static func exceeds_rating_cap(entry: Dictionary, cap: int) -> bool:
	if cap < 0 or not entry.has("rating"):
		return false
	return float(entry["rating"]) > float(cap)


## 统计恰好只占一个格子的区域数量。
static func count_single_regions(region_map: Array, board_size: int) -> int:
	var cell_counts: Dictionary = {}
	for row: int in range(board_size):
		var cells: Array = region_map[row]
		for col: int in range(board_size):
			var region_id: int = int(cells[col])
			cell_counts[region_id] = int(cell_counts.get(region_id, 0)) + 1
	var single_total: int = 0
	var counts: Array = cell_counts.values()
	for count: int in counts:
		if count == 1:
			single_total += 1
	return single_total


## 从 BankData 展开区域矩阵后检查单格区域数；负数要求表示不限。
static func matches_single_count(entry: Dictionary, board_size: int, required: int) -> bool:
	if required < 0:
		return true
	var region_map: Array = BankData.get_region_map(entry)
	if region_map.size() != board_size:
		return false
	return count_single_regions(region_map, board_size) == required


## 保留同时满足评分上限和单格区域数量要求的题目，不改原数组。
static func filter_pool(
	entries: Array, rating_cap: int, board_size: int, required_single: int
) -> Array:
	var kept: Array = []
	for entry: Dictionary in entries:
		if exceeds_rating_cap(entry, rating_cap):
			continue
		if not matches_single_count(entry, board_size, required_single):
			continue
		kept.append(entry)
	return kept


## 计算题目评分超过上限的距离，缺少评分或未设上限时记零。
static func rating_distance(entry: Dictionary, cap: int) -> float:
	if cap < 0 or not entry.has("rating"):
		return 0.0
	return maxf(0.0, float(entry["rating"]) - float(cap))


## 跳过已使用题目，优先选超出评分上限最少的题，同距离再优先满足单格数量。
static func pick_nearest_index(
	entries: Array, used_ids: Array, rating_cap: int, board_size: int, required_single: int
) -> int:
	var best_index: int = -1
	var best_distance: float = INF
	var best_mismatch: int = 2
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		if used_ids.has(int(entry.get("id", -1))):
			continue
		var distance: float = rating_distance(entry, rating_cap)
		var mismatch: int = 0 if matches_single_count(entry, board_size, required_single) else 1
		if distance < best_distance or (distance == best_distance and mismatch < best_mismatch):
			best_index = index
			best_distance = distance
			best_mismatch = mismatch
	return best_index
