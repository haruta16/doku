## 色彩挑战的配色算法；选择色相组合，并根据区域邻接关系把棋盘划为连通的两组颜色。

class_name ColorChallengePalette
extends RefCounted

enum Hue { RED_YELLOW = 0, BLUE_GREEN = 1, PURPLE_PINK = 2 }

const HUE_CYCLE: Array[int] = [Hue.RED_YELLOW, Hue.BLUE_GREEN, Hue.PURPLE_PINK]

const HUE_COUNT: int = 3

const _HUE_RAMPS: Dictionary = {
	Hue.RED_YELLOW:
	[
		Color("fae76e"),
		Color("f5cf48"),
		Color("d19c36"),
		Color("b67b51"),
		Color("edc893"),
		Color("905631"),
		Color("ffb562"),
		Color("f59139"),
		Color("db7b62"),
		Color("a55645"),
	],
	Hue.BLUE_GREEN:
	[
		Color("afdf89"),
		Color("88af5c"),
		Color("58ac54"),
		Color("3e774c"),
		Color("c9dd5a"),
		Color("aebf3f"),
		Color("72d374"),
		Color("679238"),
		Color("83debb"),
		Color("4fbaa6"),
	],
	Hue.PURPLE_PINK:
	[
		Color("bbdaf7"),
		Color("92e2e1"),
		Color("8ed4f8"),
		Color("78b9ef"),
		Color("6686b9"),
		Color("9ab3f5"),
		Color("7082d4"),
		Color("b692da"),
		Color("8975bc"),
		Color("565a97"),
	],
}

const _HUE_NAME_KEYS: Dictionary = {
	Hue.RED_YELLOW:
	[
		&"COLOR_CHALLENGE_LIGHT_YELLOW",
		&"COLOR_CHALLENGE_BRIGHT_YELLOW",
		&"COLOR_CHALLENGE_OCHRE",
		&"COLOR_CHALLENGE_LIGHT_BROWN",
		&"COLOR_CHALLENGE_BEIGE",
		&"COLOR_CHALLENGE_DARK_BROWN",
		&"COLOR_CHALLENGE_ORANGE_YELLOW",
		&"COLOR_CHALLENGE_TANGERINE_YELLOW",
		&"COLOR_CHALLENGE_ORANGE_RED",
		&"COLOR_CHALLENGE_BRICK_RED",
	],
	Hue.BLUE_GREEN:
	[
		&"COLOR_CHALLENGE_PALE_GREEN",
		&"COLOR_CHALLENGE_TEA_GREEN",
		&"COLOR_CHALLENGE_EMERALD_GREEN",
		&"COLOR_CHALLENGE_INK_GREEN",
		&"COLOR_CHALLENGE_LIGHT_GREEN",
		&"COLOR_CHALLENGE_GRASS_GREEN",
		&"COLOR_CHALLENGE_CYAN_GREEN",
		&"COLOR_CHALLENGE_PINE_GREEN",
		&"COLOR_CHALLENGE_AZURE",
		&"COLOR_CHALLENGE_CYAN_BLUE",
	],
	Hue.PURPLE_PINK:
	[
		&"COLOR_CHALLENGE_ICE_BLUE",
		&"COLOR_CHALLENGE_AZURE",
		&"COLOR_CHALLENGE_LAKE_BLUE",
		&"COLOR_CHALLENGE_SKY_BLUE",
		&"COLOR_CHALLENGE_BLUE_GRAY",
		&"COLOR_CHALLENGE_LIGHT_BLUE",
		&"COLOR_INDIGO",
		&"COLOR_CHALLENGE_LIGHT_PURPLE",
		&"COLOR_CHALLENGE_DARK_PURPLE",
		&"COLOR_CHALLENGE_DARK_BLUE",
	],
}

const _FORBIDDEN_PAIRS: Array = [
	[Hue.RED_YELLOW, Hue.BLUE_GREEN],
]


static func single_hue(delivery_index: int) -> int:
	if delivery_index < 0:
		return HUE_CYCLE[0]
	return HUE_CYCLE[delivery_index % HUE_CYCLE.size()]


static func dual_hues(delivery_index: int) -> Array[int]:
	var combos: Array = _legal_dual_combos()
	if combos.is_empty():
		var fallback: int = single_hue(delivery_index)
		return [fallback, fallback] as Array[int]
	var idx: int = (maxi(delivery_index, 0)) % combos.size()
	return combos[idx] as Array[int]


static func _legal_dual_combos() -> Array:
	var result: Array = []
	for i: int in HUE_CYCLE.size():
		for j: int in range(i + 1, HUE_CYCLE.size()):
			var pair: Array[int] = [HUE_CYCLE[i], HUE_CYCLE[j]] as Array[int]
			if not is_forbidden_pair(pair[0], pair[1]):
				result.append(pair)
	return result


static func is_forbidden_pair(hue_a: int, hue_b: int) -> bool:
	for pair: Array in _FORBIDDEN_PAIRS:
		if (pair[0] == hue_a and pair[1] == hue_b) or (pair[0] == hue_b and pair[1] == hue_a):
			return true
	return false


static func hue_ramp(hue: int) -> Array:
	if not _HUE_RAMPS.has(hue):
		return (_HUE_RAMPS[HUE_CYCLE[0]] as Array).duplicate()
	return (_HUE_RAMPS[hue] as Array).duplicate()


static func hue_name_keys(hue: int) -> Array[StringName]:
	var source: Array = _HUE_NAME_KEYS.get(hue, _HUE_NAME_KEYS[HUE_CYCLE[0]])
	var result: Array[StringName] = []
	for key: StringName in source:
		result.append(key)
	return result


static func nearest_color_name_key(color: Color, hues: Array = []) -> StringName:
	var candidates: Array = hues if not hues.is_empty() else HUE_CYCLE
	var best_key: StringName = &"HINT_SOME_COLOR"
	var best_dist: float = INF
	for raw_hue: Variant in candidates:
		var hue: int = int(raw_hue)
		if not _HUE_RAMPS.has(hue) or not _HUE_NAME_KEYS.has(hue):
			continue
		var ramp: Array = _HUE_RAMPS[hue]
		var keys: Array = _HUE_NAME_KEYS[hue]
		for index: int in mini(ramp.size(), keys.size()):
			var candidate: Color = ramp[index] as Color
			var dr: float = color.r - candidate.r
			var dg: float = color.g - candidate.g
			var db: float = color.b - candidate.b
			var distance: float = dr * dr + dg * dg + db * db
			if distance < best_dist:
				best_dist = distance
				best_key = keys[index] as StringName
	return best_key


## 根据区域邻接图寻找两组连通区域，避免双色挑战出现孤立的配色碎片。
static func split_regions_into_two(region_map: Array, size: int) -> Array[int]:
	var cell_counts: Array[int] = _count_cells_per_region(region_map, size)
	var region_count: int = cell_counts.size()
	var result: Array[int] = []
	result.resize(region_count)
	result.fill(0)
	if region_count < 2:
		return result
	var adjacency: Array = _build_region_adjacency(region_map, size, region_count)
	var total_cells: int = 0
	for count: int in cell_counts:
		total_cells += count
	var best_mask: int = -1
	var best_diff: int = total_cells + 1

	var combos: int = 1 << (region_count - 1)
	var full_mask: int = (1 << region_count) - 1
	for sub: int in range(combos):
		var group_a: int = (sub << 1) | 1
		var group_b: int = full_mask & ~group_a
		if group_b == 0:
			continue
		var cells_a: int = 0
		for region: int in region_count:
			if (group_a & (1 << region)) != 0:
				cells_a += cell_counts[region]
		var diff: int = absi(total_cells - cells_a - cells_a)
		if diff >= best_diff:
			continue
		if not _is_subset_connected(group_a, adjacency, region_count):
			continue
		if not _is_subset_connected(group_b, adjacency, region_count):
			continue
		best_diff = diff
		best_mask = group_a
		if diff <= 1:
			break
	if best_mask < 0:
		for region: int in region_count:
			result[region] = region % 2
		return result
	for region: int in region_count:
		result[region] = 0 if (best_mask & (1 << region)) != 0 else 1
	return result


static func _count_cells_per_region(region_map: Array, size: int) -> Array[int]:
	var counts: Dictionary = {}
	var max_region: int = -1
	for row: Variant in region_map:
		for cell: Variant in row as Array:
			var region: int = int(cell)
			counts[region] = int(counts.get(region, 0)) + 1
			max_region = maxi(max_region, region)
	var result: Array[int] = []
	if max_region < 0:
		return result
	result.resize(max_region + 1)
	for region: int in result.size():
		result[region] = int(counts.get(region, 0))
	return result


static func _build_region_adjacency(region_map: Array, size: int, region_count: int) -> Array:
	var seen: Array = []
	for _i: int in region_count:
		seen.append({})
	for row: int in size:
		for col: int in size:
			var here: int = int((region_map[row] as Array)[col])
			if col + 1 < size:
				var right: int = int((region_map[row] as Array)[col + 1])
				if right != here:
					(seen[here] as Dictionary)[right] = true
					(seen[right] as Dictionary)[here] = true
			if row + 1 < size:
				var down: int = int((region_map[row + 1] as Array)[col])
				if down != here:
					(seen[here] as Dictionary)[down] = true
					(seen[down] as Dictionary)[here] = true
	var result: Array = []
	for region: int in region_count:
		result.append((seen[region] as Dictionary).keys())
	return result


static func _is_subset_connected(mask: int, adjacency: Array, region_count: int) -> bool:
	var start: int = -1
	var expect: int = 0
	for region: int in region_count:
		if (mask & (1 << region)) != 0:
			expect += 1
			if start < 0:
				start = region
	if start < 0:
		return false
	var visited: Dictionary = {start: true}
	var queue: Array[int] = [start]
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for neighbor: Variant in adjacency[current] as Array:
			var next_region: int = int(neighbor)
			if (mask & (1 << next_region)) == 0:
				continue
			if visited.has(next_region):
				continue
			visited[next_region] = true
			queue.append(next_region)
	return visited.size() == expect


static func build_first_level_gradient(region_map: Array, size: int, hues: Array) -> Dictionary:
	var cell_counts: Array[int] = _count_cells_per_region(region_map, size)
	var region_count: int = cell_counts.size()
	if region_count <= 0 or size <= 1:
		return {}

	var sum_x: Array[float] = []
	var sum_y: Array[float] = []
	sum_x.resize(region_count)
	sum_y.resize(region_count)
	sum_x.fill(0.0)
	sum_y.fill(0.0)
	for row: int in size:
		for col: int in size:
			var region: int = int((region_map[row] as Array)[col])
			if region < 0 or region >= region_count:
				continue
			sum_x[region] += float(col)
			sum_y[region] += float(row)

	var projections: Array[float] = []
	projections.resize(region_count)
	for region: int in region_count:
		var count: int = cell_counts[region]
		if count <= 0:
			projections[region] = 0.0
			continue
		var center_x: float = sum_x[region] / float(count)
		var center_y: float = sum_y[region] / float(count)
		projections[region] = center_x + (float(size - 1) - center_y)

	var order: Array[int] = []
	for region: int in region_count:
		order.append(region)
	order.sort_custom(
		func(left: int, right: int) -> bool:
			if is_equal_approx(projections[left], projections[right]):
				return left < right
			return projections[left] < projections[right]
	)

	var ends_by_side: Array = []
	for hue: Variant in hues:
		ends_by_side.append(_ramp_extremes(int(hue)))
	if ends_by_side.is_empty():
		return {}

	var side: Array[int] = []
	if ends_by_side.size() >= 2:
		side = split_regions_into_two(region_map, size)
	if side.size() != region_count:
		side = []
		side.resize(region_count)
		side.fill(0)
	var color_map: Array[int] = []
	var colors: PackedColorArray = PackedColorArray()
	color_map.resize(region_count)
	colors.resize(region_count)
	var last_index: float = maxf(float(region_count - 1), 1.0)
	for rank: int in order.size():
		var region: int = order[rank]

		var ends: Array = ends_by_side[side[region] % ends_by_side.size()]
		color_map[region] = region

		colors[region] = (ends[0] as Color).lerp(ends[1] as Color, float(rank) / last_index)
	return {"color_map": color_map, "colors": colors}


static func _ramp_extremes(hue: int) -> Array[Color]:
	var ramp: Array = hue_ramp(hue)
	var darkest: Color = ramp[0] as Color
	var lightest: Color = ramp[0] as Color
	for entry: Variant in ramp:
		var color: Color = entry as Color
		if color.get_luminance() < darkest.get_luminance():
			darkest = color
		if color.get_luminance() > lightest.get_luminance():
			lightest = color
	return [darkest, lightest] as Array[Color]


## 将选定色相与区域分组转换成各格使用的颜色，供棋盘表现层直接读取。
static func build_slot_colors(
	color_map: Array, group_of_region: Array, hues: Array
) -> PackedColorArray:
	var slot_count: int = 0
	for slot: Variant in color_map:
		slot_count = maxi(slot_count, int(slot) + 1)
	var result: PackedColorArray = PackedColorArray()
	if slot_count <= 0 or hues.is_empty():
		return result
	result.resize(slot_count)

	var slot_hue: Array[int] = []
	slot_hue.resize(slot_count)
	slot_hue.fill(int(hues[0]))
	if hues.size() > 1 and not group_of_region.is_empty():
		var slot_taken: Dictionary = {}
		for region: int in color_map.size():
			var slot: int = int(color_map[region])
			if slot < 0 or slot >= slot_count or slot_taken.has(slot):
				continue
			slot_taken[slot] = true
			var group: int = 0
			if region < group_of_region.size():
				group = int(group_of_region[region])
			slot_hue[slot] = int(hues[clampi(group, 0, hues.size() - 1)])

	var used_slots: Dictionary = {}
	for region: int in color_map.size():
		var slot: int = int(color_map[region])
		if slot >= 0 and slot < slot_count:
			used_slots[slot] = true
	var rank_per_hue: Dictionary = {}
	for slot: int in slot_count:
		var hue: int = slot_hue[slot]
		var ramp: Array = hue_ramp(hue)
		if not used_slots.has(slot):
			result[slot] = ramp[0]
			continue
		var rank: int = int(rank_per_hue.get(hue, 0))
		rank_per_hue[hue] = rank + 1
		result[slot] = ramp[rank % ramp.size()]
	return result
