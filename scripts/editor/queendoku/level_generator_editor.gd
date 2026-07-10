class_name LevelGeneratorEditor
extends RefCounted

const _ORTHOGONAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(0, -1),
	Vector2i(0, 1),
]


static func generate_puzzle(config: Dictionary) -> Dictionary:
	return generate_solvable_puzzle(config)


static func generate_solvable_puzzle(config: Dictionary) -> Dictionary:
	var size := clampi(int(config.get("size", 8)), 4, 12)
	var max_attempts := maxi(1, int(config.get("max_attempts", 300)))
	var rng := RandomNumberGenerator.new()
	var requested_seed := int(config.get("seed", 0))
	rng.seed = requested_seed if requested_seed != 0 else Time.get_ticks_usec()

	for _attempt in max_attempts:
		var solution_columns := _generate_solution_columns(size, rng)
		if solution_columns.is_empty():
			continue
		var regions := _grow_regions(size, solution_columns, config, rng)
		if regions.is_empty():
			continue
		var solution_grid := _to_solution_grid(size, solution_columns)
		return {
			"regions": regions,
			"regionMap": regions,
			"solution": solution_grid,
			"solution_columns": solution_columns,
			"colorMap": LevelGenerator.compute_color_map_with_seed(size, regions, requested_seed),
		}

	return {}


static func _generate_solution_columns(size: int, rng: RandomNumberGenerator) -> Array[int]:
	var columns: Array[int] = []
	for column in size:
		columns.append(column)

	for _shuffle_attempt in 256:
		for index in range(size - 1, 0, -1):
			var other := rng.randi_range(0, index)
			var temporary := columns[index]
			columns[index] = columns[other]
			columns[other] = temporary
		if _is_non_touching(columns):
			return columns.duplicate()

	return []


static func _is_non_touching(columns: Array[int]) -> bool:
	for row in range(columns.size() - 1):
		if absi(columns[row] - columns[row + 1]) <= 1:
			return false
	return true


static func _grow_regions(
		size: int,
		solution_columns: Array[int],
		config: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var regions: Array = []
	for _row_index in size:
		var row: Array = []
		row.resize(size)
		row.fill(-1)
		regions.append(row)

	var region_sizes: Array[int] = []
	region_sizes.resize(size)
	region_sizes.fill(1)
	for row in size:
		regions[row][solution_columns[row]] = row

	var preferred_minimum := clampi(int(config.get("min_region_size", 0)), 1, size)
	var remaining := size * size - size
	while remaining > 0:
		var candidates: Array = []
		var preferred_candidates: Array = []
		for row in size:
			for column in size:
				if int(regions[row][column]) >= 0:
					continue
				var neighboring_regions: Dictionary = {}
				for direction in _ORTHOGONAL_DIRECTIONS:
					var neighbor_row := row + direction.x
					var neighbor_column := column + direction.y
					if neighbor_row < 0 or neighbor_row >= size or neighbor_column < 0 or neighbor_column >= size:
						continue
					var region_id := int(regions[neighbor_row][neighbor_column])
					if region_id < 0 or neighboring_regions.has(region_id):
						continue
					neighboring_regions[region_id] = true
					var candidate := [row, column, region_id]
					candidates.append(candidate)
					if region_sizes[region_id] < preferred_minimum:
						preferred_candidates.append(candidate)

		if candidates.is_empty():
			return []
		var pool := preferred_candidates if not preferred_candidates.is_empty() else candidates
		var choice: Array = pool[rng.randi_range(0, pool.size() - 1)]
		var selected_row := int(choice[0])
		var selected_column := int(choice[1])
		var selected_region := int(choice[2])
		if int(regions[selected_row][selected_column]) >= 0:
			continue
		regions[selected_row][selected_column] = selected_region
		region_sizes[selected_region] += 1
		remaining -= 1

	return regions


static func _to_solution_grid(size: int, solution_columns: Array[int]) -> Array:
	var grid: Array = []
	for row in size:
		var values: Array = []
		values.resize(size)
		values.fill(false)
		values[solution_columns[row]] = true
		grid.append(values)
	return grid
