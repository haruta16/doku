extends SceneTree


func _initialize() -> void:
	var failures: Array[String] = []
	var main_scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene_path.is_empty() or not ResourceLoader.load(main_scene_path) is PackedScene:
		failures.append("main scene failed to load: %s" % main_scene_path)

	var expected_sizes: Array[int] = [4, 5, 6, 7, 8, 9, 10, 12]
	if BankData.get_sizes() != expected_sizes:
		failures.append("unexpected regular level-bank sizes: %s" % [BankData.get_sizes()])

	var special_levels := BankData.get_sp_levels()
	if special_levels.size() != 57:
		failures.append("expected 57 SP levels, got %d" % special_levels.size())
	if not special_levels.any(func(entry: Dictionary) -> bool: return entry.get("pattern", "") == "guide"):
		failures.append("SP tutorial guide level is missing")

	for size in range(4, 11):
		var puzzle := LevelGeneratorEditor.generate_solvable_puzzle({
			"size": size,
			"seed": 1000 + size,
			"max_attempts": 300,
		})
		if not _validate_generated_puzzle(puzzle, size):
			failures.append("generated puzzle failed validation for size %d" % size)

	if failures.is_empty():
		print("VALIDATION_OK: main scene, level banks, tutorial data, and generators 4x4-10x10")
		quit(0)
		return

	for failure in failures:
		push_error("VALIDATION_FAILED: %s" % failure)
	quit(1)


func _validate_generated_puzzle(puzzle: Dictionary, size: int) -> bool:
	if puzzle.is_empty():
		return false
	var regions: Array = puzzle.get("regions", [])
	var solution: Array = puzzle.get("solution", [])
	if regions.size() != size or solution.size() != size:
		return false

	var used_columns: Dictionary = {}
	var used_regions: Dictionary = {}
	var previous_column := -100
	for row in size:
		if not solution[row] is Array or (solution[row] as Array).size() != size:
			return false
		var selected_column := -1
		for column in size:
			if bool(solution[row][column]):
				if selected_column >= 0:
					return false
				selected_column = column
		if selected_column < 0 or used_columns.has(selected_column):
			return false
		if row > 0 and absi(selected_column - previous_column) <= 1:
			return false
		used_columns[selected_column] = true
		previous_column = selected_column

		if not regions[row] is Array or (regions[row] as Array).size() != size:
			return false
		var region_id := int(regions[row][selected_column])
		if region_id < 0 or region_id >= size or used_regions.has(region_id):
			return false
		used_regions[region_id] = true

	return used_columns.size() == size and used_regions.size() == size
