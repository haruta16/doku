## 按题库 rating 排序搜索；使用外部接受回调完成策略过滤，不在此处标记题目已选。
class_name RatingSortedPickProvider
extends RefCounted

const SOURCES: Array[String] = ["regular", "lkstyle", "gc"]

static var _order_cache: Dictionary = {}


## 按尺寸、策略和来源筛选题库，缓存 rating 升序、pid 作为同分顺序的候选序列。
static func get_sorted_order(
	pools: Dictionary, sz: int, rank: int, tier: String, strict_rank: bool, is_main_path: bool
) -> Array:
	var key := (
		"%d_%d_%s_%s_%s_%d_%d_%d"
		% [
			sz,
			rank,
			tier,
			strict_rank,
			is_main_path,
			(pools.get("regular", []) as Array).size(),
			(pools.get("lkstyle", []) as Array).size(),
			(pools.get("gc", []) as Array).size(),
		]
	)
	if _order_cache.has(key):
		return _order_cache[key]
	var scored: Array = []
	for source_name: String in SOURCES:
		var source_pool: Array = pools.get(source_name, [])
		for i: int in source_pool.size():
			var entry: Dictionary = source_pool[i] as Dictionary
			if not entry.has("rating"):
				continue
			(
				scored
				. append(
					{
						"rating": float(entry["rating"]),
						"pid": str(entry.get("_pid_h", "")),
						"ref": entry,
						"source": source_name,
						"idx": i,
					}
				)
			)
	scored.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if left["rating"] != right["rating"]:
				return left["rating"] < right["rating"]
			return left["pid"] < right["pid"]
	)
	_order_cache[key] = scored
	return scored


## 二分定位难度带范围，再从低到高返回首个通过接受回调的未选题。
static func pick_from_order(
	order: Array,
	band: Vector2,
	rank: int,
	tier: String,
	is_main_path: bool,
	is_selected: Callable,
	accept: Callable
) -> Dictionary:
	if not RatingBandTable.is_valid_band(band):
		return {}
	return _scan(
		order, lower_bound(order, band.x), band.y, rank, tier, is_main_path, is_selected, accept
	)


## 从严格高于难度带上界的位置开始向上寻找可接受候选。
static func pick_above_band(
	order: Array,
	band: Vector2,
	rank: int,
	tier: String,
	is_main_path: bool,
	is_selected: Callable,
	accept: Callable
) -> Dictionary:
	if not RatingBandTable.is_valid_band(band):
		return {}
	return _scan(
		order, upper_bound(order, band.y), INF, rank, tier, is_main_path, is_selected, accept
	)


## 跳过已经选过的 pid，展开候选后交给 accept 回调决定是否返回。
static func _scan(
	order: Array,
	start: int,
	max_rating: float,
	rank: int,
	tier: String,
	is_main_path: bool,
	is_selected: Callable,
	accept: Callable
) -> Dictionary:
	for i: int in range(start, order.size()):
		var item: Dictionary = order[i]
		if float(item["rating"]) > max_rating:
			break
		if is_selected.call(str(item["pid"])):
			continue
		var candidate: Dictionary = build_candidate(item, rank, tier, is_main_path)
		if accept.call(candidate):
			return candidate
	return {}


## 返回首个 rating 严格大于目标值的位置。
static func upper_bound(order: Array, target: float) -> int:
	var low: int = 0
	var high: int = order.size()
	while low < high:
		var mid: int = (low + high) / 2
		if float(order[mid]["rating"]) <= target:
			low = mid + 1
		else:
			high = mid
	return low


## 返回首个 rating 大于或等于目标值的位置。
static func lower_bound(order: Array, target: float) -> int:
	var low: int = 0
	var high: int = order.size()
	while low < high:
		var mid: int = (low + high) / 2
		if float(order[mid]["rating"]) < target:
			low = mid + 1
		else:
			high = mid
	return low


## 展开原始题目并附上题库来源、策略等级及模式等交付字段。
static func build_candidate(
	item: Dictionary, rank: int, tier: String, is_main_path: bool
) -> Dictionary:
	var candidate: Dictionary = BankData.materialize_entry(item["ref"] as Dictionary, true)
	var source_name: String = str(item["source"])
	candidate["_bank_source"] = source_name
	if is_main_path:
		candidate["_bank_source_main"] = source_name
	candidate["_bank_idx"] = int(item["idx"]) + 1
	candidate["_bank_transform"] = 0
	candidate["_bank_rank"] = rank
	candidate["_bank_tier"] = tier
	candidate["_rating_sorted_pick"] = true
	return candidate


## 清空排序缓存，下次请求重新建立候选顺序。
static func clear_cache() -> void:
	_order_cache.clear()
