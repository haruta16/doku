## 预放猫决策：根据困难关后续、连续失败或降档场景，从高策略层级位置选一只答案猫。
extends RefCounted
class_name PreCatDecider

const SCENE_HARD_NEXT: int = 1
const SCENE_CONSECUTIVE_FAIL: int = 2
const SCENE_DEMOTE: int = 3

const PRE_TYPE_NONE: String = "0"


## 收集本次命中的预放猫来源，多个场景可以同时成立。
static func hit_scenarios(
	is_prev_hard: bool, cur_rank: int, pending_struggle: bool, pending_demote: bool
) -> Array[int]:
	var scenes: Array[int] = []
	if is_prev_hard and cur_rank >= 3:
		scenes.append(SCENE_HARD_NEXT)
	if pending_struggle:
		scenes.append(SCENE_CONSECUTIVE_FAIL)
	if pending_demote:
		scenes.append(SCENE_DEMOTE)
	return scenes


## 把场景编号连接成埋点标识，没有场景时返回字符串零。
static func scenes_to_pre_type(scenes: Array[int]) -> String:
	if scenes.is_empty():
		return PRE_TYPE_NONE
	var parts: PackedStringArray = []
	for s: int in scenes:
		parts.append(str(s))
	return "&".join(parts)


## 在空棋盘推导出的 R3 及以上答案猫中随机选点；无候选返回 (-1, -1)。
static func pick_prefill_cell(
	size: int, regions: Array, solution_2d: Array, pick_index: Callable = Callable()
) -> Vector2i:
	var ranks: Dictionary = _compute_empty_board_ranks(size, regions, solution_2d)
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in ranks:
		if int(ranks[cell]) >= 3:
			candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	var selected_index: int = (
		int(pick_index.call(candidates.size()))
		if pick_index.is_valid()
		else randi() % candidates.size()
	)
	return candidates[selected_index]


## 先找最高推导层级，再在同层级答案猫中随机选一格。
static func pick_prefill_cell_highest_rank(
	size: int, regions: Array, solution_2d: Array
) -> Vector2i:
	var ranks: Dictionary = _compute_empty_board_ranks(size, regions, solution_2d)
	var max_rank: int = 0
	for cell: Vector2i in ranks:
		var r: int = int(ranks[cell])
		if r >= 3 and r > max_rank:
			max_rank = r
	if max_rank == 0:
		return Vector2i(-1, -1)
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in ranks:
		if int(ranks[cell]) == max_rank:
			candidates.append(cell)
	return candidates[randi() % candidates.size()]


## 创建全空棋盘并调用 HintEngine，得到每只答案猫所需的策略层级。
static func _compute_empty_board_ranks(size: int, regions: Array, solution_2d: Array) -> Dictionary:
	var board: Array = []
	for r: int in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(CellState.EMPTY)
		board.append(row)
	return HintEngine.compute_cell_ranks(board, size, regions, solution_2d)


## 返回选中位置的推导层级和整盘最高层级，供预放结果记录。
static func rank_stats(size: int, regions: Array, solution_2d: Array, pos: Vector2i) -> Dictionary:
	var ranks: Dictionary = _compute_empty_board_ranks(size, regions, solution_2d)
	var max_rank: int = 0
	for r: int in ranks.values():
		max_rank = maxi(max_rank, int(r))
	return {
		"selected_rank": int(ranks.get(pos, -1)) if pos.x >= 0 else -1,
		"max_rank": max_rank,
	}


## 综合触发场景和选点方式，返回预放位置、来源及层级信息；不直接落子。
static func decide(
	scenes: Array[int],
	size: int,
	regions: Array,
	solution_2d: Array,
	high_rank_mode: bool = false,
	pick_index: Callable = Callable()
) -> Dictionary:
	var no_place: Dictionary = {"pre_type": PRE_TYPE_NONE, "position": Vector2i(-1, -1)}
	if scenes.is_empty():
		return no_place
	var pos: Vector2i = (
		pick_prefill_cell_highest_rank(size, regions, solution_2d)
		if high_rank_mode
		else pick_prefill_cell(size, regions, solution_2d, pick_index)
	)
	if pos.x < 0:
		return no_place

	var stats: Dictionary = rank_stats(size, regions, solution_2d, pos)
	return {
		"pre_type": scenes_to_pre_type(scenes),
		"position": pos,
		"selected_rank": stats["selected_rank"],
		"max_rank": stats["max_rank"],
	}
