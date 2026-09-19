# 关卡生成器（开发/调试用）：先掷一个「相邻行的解不相贴」的解，再把棋盘向外长成大小不一的颜色区域
# 全是 static 的纯工具类，不属于 @tool / EditorPlugin；正式包里可能整个文件被剔除（见 game_page 的 debug_config 入口）
class_name LevelGeneratorEditor
extends RefCounted

# 四邻域方向，按 (行增量, 列增量) 使用：区域生长只看上下左右，不含斜角
const _ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
]


# ================= 对外入口 =================
# 生成入口：直接转发给 generate_solvable_puzzle（debug_config 等调用点走这里）
static func generate_puzzle(config: Dictionary) -> Dictionary:
	return generate_solvable_puzzle(config)


# 掷出一整道可解题：最多重试 max_attempts 轮，全失败返回空字典 {}
# config 只认 size / seed / min_region_size / max_attempts（debug 页传的 strip_count 本函数不读）
static func generate_solvable_puzzle(config: Dictionary) -> Dictionary:
	# 棋盘边长，夹到 4~12，默认 8
	var size := clampi(int(config.get("size", 8)), 4, 12)
	# 最多重试轮数，至少 1（默认 300）
	var max_attempts := maxi(1, int(config.get("max_attempts", 300)))
	# 种子决定可复现性：seed 传 0 表示用当前微秒时间当种子
	var rng := RandomNumberGenerator.new()
	var requested_seed := int(config.get("seed", 0))
	rng.seed = requested_seed if requested_seed != 0 else Time.get_ticks_usec()

	# 每轮重掷「解 + 区域」；区域长不出来就换下一轮
	for _attempt in max_attempts:
		# 先掷解：一个相邻两行列号差都 >1 的排列
		var solution_columns := _generate_solution_columns(size, rng)
		if solution_columns.is_empty():
			continue
		# 再长区域：每个解格是各自区域的种子
		var regions := _grow_regions(size, solution_columns, config, rng)
		if regions.is_empty():
			continue
		# 把「每行一个列号」的解展开成 bool 网格
		var solution_grid := _to_solution_grid(size, solution_columns)
		return {
			"regions": regions,
			"regionMap": regions,
			"solution": solution_grid,
			"solution_columns": solution_columns,
			"colorMap": LevelGenerator.compute_color_map_with_seed(size, regions, requested_seed),
		}

	# 全部轮次都失败：空字典就是失败信号
	return {}


# ================= 内部实现 =================
# 掷解：洗牌 0..size-1 的列号，直到相邻两行的列号差都 >1，即猫与猫不竖贴也不斜贴
static func _generate_solution_columns(size: int, rng: RandomNumberGenerator) -> Array[int]:
	var columns: Array[int] = []
	for column in size:
		columns.append(column)

	# 最多洗 256 次；洗不出合法排列说明这个 size 太苛刻，返回空数组
	for _shuffle_attempt in 256:
		# Fisher–Yates 洗牌：从尾部往前逐个与随机位置交换
		for index in range(size - 1, 0, -1):
			var other := rng.randi_range(0, index)
			var temporary := columns[index]
			columns[index] = columns[other]
			columns[other] = temporary
		# 合格就返回副本，免得调用方改到本地数组
		if _is_non_touching(columns):
			return columns.duplicate()

	return []


# 校验某个排列是否合规：相邻两行的列号差 <=1 就算相贴
static func _is_non_touching(columns: Array[int]) -> bool:
	for row in range(columns.size() - 1):
		if absi(columns[row] - columns[row + 1]) <= 1:
			return false
	return true


# 区域生长：每个解格先自成一区，再反复随机把空格并入相邻区域，优先把没达到 min_region_size 的区域补大
# 中途长不下去（空格找不到任何相邻区域）就返回空数组，交给上层重掷
static func _grow_regions(
		size: int,
		solution_columns: Array[int],
		config: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var regions: Array = []
	# 先铺一张 size×size 的 -1 网格：-1 表示这一格还没归属任何区域
	for _row_index in size:
		var row: Array = []
		row.resize(size)
		row.fill(-1)
		regions.append(row)

	# 每个区域当前的格数，用于判断谁还「不够大」
	var region_sizes: Array[int] = []
	region_sizes.resize(size)
	region_sizes.fill(1)
	# 每行的解格单独成区：区域 id 直接就用行号 row
	for row in size:
		regions[row][solution_columns[row]] = row

	# 想把区域补到的下限（config.min_region_size，默认 0 表示不设偏好）
	var preferred_minimum := clampi(int(config.get("min_region_size", 0)), 1, size)
	# 还剩多少格没分配：解格已经占掉 size 格
	var remaining := size * size - size
	# 一次只填一格，直到全盘填满
	while remaining > 0:
		# 本轮全部候选，分普通池和优先池两档
		var candidates: Array = []
		var preferred_candidates: Array = []
		for row in size:
			for column in size:
				# 已经有归属的格子跳过
				if int(regions[row][column]) >= 0:
					continue
				# 去重：一个空格可能同时挨着多个区域，但每个区域只收一条候选
				var neighboring_regions: Dictionary = {}
				# 只看上下左右四个方向
				for direction in _ORTHOGONAL_DIRECTIONS:
					var neighbor_row := row + direction.x
					var neighbor_column := column + direction.y
					# 越界的邻居不算
					if neighbor_row < 0 or neighbor_row >= size or neighbor_column < 0 or neighbor_column >= size:
						continue
					var region_id := int(regions[neighbor_row][neighbor_column])
					if region_id < 0 or neighboring_regions.has(region_id):
						continue
					neighboring_regions[region_id] = true
					# 候选记成 [行, 列, 要并入的区域 id]
					var candidate := [row, column, region_id]
					candidates.append(candidate)
					# 这个区域还没达到下限，进优先池
					if region_sizes[region_id] < preferred_minimum:
						preferred_candidates.append(candidate)

		# 空格却找不到任何相邻区域：这一轮的区域长不成完整棋盘
		if candidates.is_empty():
			return []
		# 优先池非空就只从中挑，保证小区域先长大
		var pool := preferred_candidates if not preferred_candidates.is_empty() else candidates
		# 从池里随机挑一个候选
		var choice: Array = pool[rng.randi_range(0, pool.size() - 1)]
		var selected_row := int(choice[0])
		var selected_column := int(choice[1])
		var selected_region := int(choice[2])
		# 双保险：万一这格在本轮之外已被填上，换下一轮
		if int(regions[selected_row][selected_column]) >= 0:
			continue
		# 落子：并入区域、更新面积、剩余格数减一
		regions[selected_row][selected_column] = selected_region
		region_sizes[selected_region] += 1
		remaining -= 1

	return regions


# 把解展开成 size×size 的 bool 网格：每行只有解列那格是 true
static func _to_solution_grid(size: int, solution_columns: Array[int]) -> Array:
	var grid: Array = []
	# 每行先铺 size 个 false，再把解列置 true
	for row in size:
		var values: Array = []
		values.resize(size)
		values.fill(false)
		values[solution_columns[row]] = true
		grid.append(values)
	return grid
