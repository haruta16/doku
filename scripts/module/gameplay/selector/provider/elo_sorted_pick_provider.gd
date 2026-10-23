## 按 Elo 排序并搜索候选题；结合已选题记录、校验回调和可选的近邻回退控制重复与难度范围。
class_name EloSortedPickProvider
extends RefCounted

static var _order_cache: Dictionary = {}


## 按请求的题源、尺寸与策略范围构造缓存排序；普通题源额外限制单格区域数量。
static func get_sorted_order(
	pools: Dictionary,
	sz: int,
	rank: int,
	tier: String,
	strict_rank: bool,
	is_main_path: bool,
	source_mode: String
) -> Array:
	var key := (
		"%d_%d_%s_%s_%s_%s_%d_%d_%d_%d"
		% [
			sz,
			rank,
			tier,
			strict_rank,
			is_main_path,
			source_mode,
			(pools.get("regular", []) as Array).size(),
			(pools.get("lkstyle", []) as Array).size(),
			(pools.get("gc", []) as Array).size(),
			(pools.get("lk_mod", []) as Array).size(),
		]
	)
	if _order_cache.has(key):
		return _order_cache[key]
	var scored: Array = []
	var source_names: Array = (
		["lk_mod"] if source_mode == "lk_mod" else ["regular", "lkstyle", "gc"]
	)

	for source_name: String in source_names:
		var source_pool: Array = pools.get(source_name, [])
		for i: int in source_pool.size():
			var entry: Dictionary = source_pool[i] as Dictionary
			if not entry.has("eloRating"):
				continue

			if source_mode != "lk_mod" and not _has_at_most_one_single_region(entry, sz):
				continue
			scored.append(
				{
					"elo": float(entry["eloRating"]),
					"pid": str(entry.get("_pid_h", "")),
					"ref": entry,
					"source": source_name,
					"idx": i
				}
			)
	scored.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if left["elo"] != right["elo"]:
				return left["elo"] < right["elo"]

			return left["pid"] < right["pid"]
	)
	var order: Array = []
	for scored_item: Dictionary in scored:
		order.append(scored_item)
	_order_cache[key] = order
	return order


## 统计区域大小并排除多个单格区域；无法识别的布局留给后续完整校验。
static func _has_at_most_one_single_region(entry: Dictionary, sz: int) -> bool:
	var region_value: Variant = entry.get("regionMap", [])
	var counts: Dictionary = {}
	if region_value is PackedByteArray:
		var packed_regions: PackedByteArray = region_value
		if packed_regions.size() != sz * sz:
			return true
		for region_id: int in packed_regions:
			counts[region_id] = int(counts.get(region_id, 0)) + 1
	else:
		var region_map: Array = region_value
		if region_map.size() != sz:
			return true
		for row_value: Variant in region_map:
			var row: Array = row_value as Array
			if row.size() != sz:
				return true
			for region_id: Variant in row:
				var key: int = int(region_id)
				counts[key] = int(counts.get(key, 0)) + 1
	var singles: int = 0
	var region_counts: Array = counts.values()
	for count: int in region_counts:
		if count == 1:
			singles += 1
			if singles > 1:
				return false
	return true


## 二分查找首个 Elo 大于或等于 target 的位置。
static func _lower_bound(order: Array, target: float) -> int:
	var low: int = 0
	var high: int = order.size()
	while low < high:
		var mid: int = (low + high) / 2
		if float(order[mid]["elo"]) < target:
			low = mid + 1
		else:
			high = mid
	return low


## 连接 GameState 的已选题查询与标记回调，再执行排序搜索。
static func pick(
	pools: Dictionary,
	sz: int,
	rank: int,
	tier: String,
	strict_rank: bool,
	is_main_path: bool,
	source_mode: String,
	elo_rating_x: float,
	bounds: Vector2,
	validate: Callable
) -> Dictionary:
	var order: Array = get_sorted_order(
		pools, sz, rank, tier, strict_rank, is_main_path, source_mode
	)
	return pick_from_order(
		order,
		rank,
		tier,
		elo_rating_x,
		bounds,
		validate,
		func(pid: String) -> bool: return GameState.is_elo_pid_selected(pid),
		func(pid: String) -> void: GameState.mark_elo_pid_selected(pid),
		false
	)


## 先跳过已选题；允许近邻回退且首轮失败时，再放宽已选题限制尝试一次。
static func pick_from_order(
	order: Array,
	rank: int,
	tier: String,
	elo_rating_x: float,
	bounds: Vector2,
	validate: Callable,
	is_selected: Callable,
	mark: Callable,
	allow_nearest: bool = false
) -> Dictionary:
	var picked: Dictionary = _pick_from_order_pass(
		order, rank, tier, elo_rating_x, bounds, validate, is_selected, mark, allow_nearest
	)
	if not picked.is_empty() or not allow_nearest:
		return picked
	return _pick_from_order_pass(
		order,
		rank,
		tier,
		elo_rating_x,
		bounds,
		validate,
		func(_pid: String) -> bool: return false,
		mark,
		true
	)


## 从目标值向上扫描带内候选；允许回退时再补低端，并按离难度带的距离向外搜索。
static func _pick_from_order_pass(
	order: Array,
	rank: int,
	tier: String,
	elo_rating_x: float,
	bounds: Vector2,
	validate: Callable,
	is_selected: Callable,
	mark: Callable,
	allow_nearest: bool
) -> Dictionary:
	var start: int = _lower_bound(order, elo_rating_x)
	for i: int in range(start, order.size()):
		var item: Dictionary = order[i]
		if float(item["elo"]) > bounds.y:
			break
		var candidate: Dictionary = _try_item(item, rank, tier, validate, is_selected, mark)
		if not candidate.is_empty():
			return candidate
	if not allow_nearest:
		return {}
	var left: int = start - 1
	while left >= 0 and float(order[left]["elo"]) >= bounds.x:
		var in_band: Dictionary = _try_item(order[left], rank, tier, validate, is_selected, mark)
		if not in_band.is_empty():
			return in_band
		left -= 1
	var right: int = _upper_bound(order, bounds.y)
	while left >= 0 or right < order.size():
		var take_left: bool = right >= order.size()
		if left >= 0 and right < order.size():
			take_left = (
				bounds.x - float(order[left]["elo"]) <= float(order[right]["elo"]) - bounds.y
			)
		var nearest_item: Dictionary = order[left] if take_left else order[right]
		if take_left:
			left -= 1
		else:
			right += 1
		var nearest: Dictionary = _try_item(nearest_item, rank, tier, validate, is_selected, mark)
		if not nearest.is_empty():
			return nearest
	return {}


## 二分查找首个 Elo 严格大于 target 的位置。
static func _upper_bound(order: Array, target: float) -> int:
	var low: int = 0
	var high: int = order.size()
	while low < high:
		var mid: int = (low + high) / 2
		if float(order[mid]["elo"]) <= target:
			low = mid + 1
		else:
			high = mid
	return low


## 展开并变换候选，附来源信息，经校验接受后才调用标记回调记录 pid。
static func _try_item(
	item: Dictionary,
	rank: int,
	tier: String,
	validate: Callable,
	is_selected: Callable,
	mark: Callable
) -> Dictionary:
	var pid: String = str(item["pid"])
	if is_selected.call(pid):
		return {}
	var candidate: Dictionary = BankData.materialize_entry(item["ref"] as Dictionary, true)
	var transform: int = int(item.get("transform", 0))
	if transform > 0:
		candidate = _apply_transform(candidate, transform)
	candidate["_bank_source"] = str(item["source"])
	candidate["_bank_source_main"] = str(item["source"])
	candidate["_bank_idx"] = int(item["idx"]) + 1
	candidate["_bank_transform"] = transform
	candidate["_bank_rank"] = rank
	candidate["_bank_tier"] = str(item.get("tier", tier))
	candidate["_elo_sorted_pick"] = true
	if not validate.call(candidate):
		return {}
	mark.call(pid)
	return candidate


## 原地同步旋转或镜像区域图与答案。
static func _apply_transform(entry: Dictionary, transform: int) -> Dictionary:
	var region_map: Array = []
	for row: Variant in entry.get("regionMap", []):
		var int_row: Array = []
		for value: Variant in row as Array:
			int_row.append(int(value))
		region_map.append(int_row)
	var solution: Array = []
	for value: Variant in entry.get("solution", []):
		solution.append(int(value))
	var size: int = region_map.size()
	if size == 0:
		return entry
	var transformed: Array = LevelData.apply_transform(region_map, solution, size, transform)
	entry["regionMap"] = transformed[0]
	entry["solution"] = transformed[1]
	return entry


## 丢弃排序缓存，使下次选题重新读取题库并排序。
static func clear_cache() -> void:
	_order_cache.clear()
