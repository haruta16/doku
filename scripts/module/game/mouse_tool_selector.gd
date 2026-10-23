## 老鼠道具的目标选择：按非猫格子的候选桶筛选并打乱顺序，返回本次作用位置。
class_name MouseToolSelector
extends RefCounted

const BUCKET_UNSOLVED_REGION: StringName = &"unsolved_region"
const BUCKET_SOLVED_REGION: StringName = &"solved_region"
const BUCKET_CAT_EMPTY: StringName = &"cat_empty"
const BUCKET_CAT_MARKED: StringName = &"cat_marked"


static func select_targets(
	board: Array,
	solution: Array,
	regions: Array,
	rng: RandomNumberGenerator,
	max_steps: int = 3,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if (
		max_steps <= 0
		or board.is_empty()
		or solution.size() != board.size()
		or regions.size() != board.size()
	):
		return result

	var size: int = board.size()
	var regions_with_cat: Dictionary = {}
	for r: int in range(size):
		var board_row: Array = board[r] as Array
		var region_row: Array = regions[r] as Array
		if board_row.size() != size or region_row.size() != size:
			return result
		for c: int in range(size):
			if int(board_row[c]) == CellState.CAT:
				regions_with_cat[region_row[c]] = true

	var unsolved_region: Array[Vector2i] = []
	var solved_region: Array[Vector2i] = []
	var cat_empty: Array[Vector2i] = []
	var cat_marked: Array[Vector2i] = []
	for r: int in range(size):
		var board_row: Array = board[r] as Array
		var solution_row: Array = solution[r] as Array
		var region_row: Array = regions[r] as Array
		if solution_row.size() != size:
			return result
		for c: int in range(size):
			var state: int = int(board_row[c])
			var is_cat_cell: bool = bool(solution_row[c])
			var cell := Vector2i(r, c)
			if is_cat_cell:
				if CellState.is_blank(state):
					cat_empty.append(cell)
				elif state == CellState.MARK:
					cat_marked.append(cell)
				continue
			if not CellState.is_blank(state):
				continue
			if regions_with_cat.has(region_row[c]):
				solved_region.append(cell)
			else:
				unsolved_region.append(cell)

	_shuffle_bucket(unsolved_region, rng)
	_shuffle_bucket(solved_region, rng)
	_shuffle_bucket(cat_empty, rng)
	_shuffle_bucket(cat_marked, rng)

	if _append_non_cat_bucket(result, unsolved_region, BUCKET_UNSOLVED_REGION, max_steps):
		return result
	if _append_non_cat_bucket(result, solved_region, BUCKET_SOLVED_REGION, max_steps):
		return result

	if not result.is_empty():
		return result
	if not cat_empty.is_empty():
		result.append({"cell": cat_empty[0], "is_cat": true, "bucket": BUCKET_CAT_EMPTY})
	elif not cat_marked.is_empty():
		result.append({"cell": cat_marked[0], "is_cat": true, "bucket": BUCKET_CAT_MARKED})
	return result


static func _append_non_cat_bucket(
	result: Array[Dictionary],
	bucket: Array[Vector2i],
	bucket_name: StringName,
	max_steps: int,
) -> bool:
	for cell: Vector2i in bucket:
		result.append({"cell": cell, "is_cat": false, "bucket": bucket_name})
		if result.size() >= max_steps:
			return true
	return false


static func _shuffle_bucket(bucket: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i: int in range(bucket.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = bucket[i]
		bucket[i] = bucket[j]
		bucket[j] = tmp
