## 普通关卡策略 normal_level_12001：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12001Strategy
extends NL11900Strategy

const SP_TT_SCAN_LIMIT: int = 300

var _returnee_delivery: bool = false
var _baseline_entry: Dictionary = {}
var _delivery_level: int = 0
var _returnee_pending: Dictionary = {}


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12001"


func select(request: LevelSelectRequest) -> Dictionary:
	_returnee_delivery = false
	_baseline_entry = {}
	_returnee_pending = {}
	var level: int = request.level_num
	_delivery_level = level
	var baseline: Dictionary = super.select(request)
	if GameState.get_returnee_remaining(12001) <= 0 or not baseline.has("entry"):
		return baseline
	var original: Dictionary = baseline["entry"]
	var source: String = str(original.get("_bank_source_main", original.get("_bank_source", "")))
	if source in ["sp", "lk", "lk_mod"]:
		return baseline
	var baseline_size: int = int(original.get("size", 0))
	var baseline_rank: int = int(original.get("_delivery_rank", 0))
	if baseline_size <= 0 or baseline_rank <= 0:
		return baseline
	var found_duplicate: Dictionary = {}
	var duplicate_pending: Dictionary = {}
	var pool: Array = BankData.get_sp_tt_levels()
	var candidate_buckets: Dictionary = {}
	var ordinal_by_bucket: Dictionary = {}
	for entry: Dictionary in pool:
		if not matches_baseline(entry, original):
			continue
		var entry_category: int = int(entry.get("shapeCategory", 0))
		var entry_size: int = int(entry.get("size", 0))
		var bucket_key: String = "%d_%d" % [entry_category, entry_size]
		var ordinal: int = int(ordinal_by_bucket.get(bucket_key, 0)) + 1
		ordinal_by_bucket[bucket_key] = ordinal
		if not candidate_buckets.has(entry_category):
			candidate_buckets[entry_category] = []
		var bucket: Array = candidate_buckets[entry_category]
		bucket.append({"entry": entry, "ordinal": ordinal})
	var start_cat: int = GameState.get_sp_tt_category_cursor()
	var scanned: int = 0
	for cat_offset: int in range(SpTtProvider.CATEGORY_COUNT):
		var category: int = (start_cat - 1 + cat_offset) % SpTtProvider.CATEGORY_COUNT + 1
		var candidates: Array = candidate_buckets.get(category, [])
		for candidate: Dictionary in candidates:
			var entry: Dictionary = candidate["entry"]
			var entry_size: int = int(entry.get("size", 0))
			if scanned >= SP_TT_SCAN_LIMIT:
				return baseline
			scanned += 1
			if not eligible_special(entry, baseline_size, baseline_rank):
				continue
			var ordinal: int = int(candidate["ordinal"])
			var progress: Dictionary = GameState.get_sp_tt_progress(
				category, entry_size, baseline_rank
			)
			if int(progress.get("t_pos", 0)) > 0:
				continue
			if ordinal <= int(progress.get("idx", 0)):
				continue
			var picked: Dictionary = entry.duplicate(true)
			picked["_bank_source"] = "sp_tt%d" % category
			picked["_bank_source_main"] = "sp_tt"
			picked["_bank_idx"] = ordinal
			picked["_bank_transform"] = 0
			picked["_bank_rank"] = baseline_rank
			picked["_bank_tier"] = ""
			var validation: Dictionary = FinalLevelValidator.validate(picked, level)
			if not bool(validation.valid):
				continue
			picked = validation.entry
			var dedup: Dictionary = PuzzleDeduplicator.inspect(picked, level)
			var pending: Dictionary = {
				"category": category, "size": entry_size, "rank": baseline_rank, "idx": ordinal
			}
			if bool(dedup.duplicate):
				found_duplicate = _delivered(picked, str(dedup.puzzle_id), &"duplicate_fallback")
				duplicate_pending = pending
				continue
			_returnee_delivery = true
			_baseline_entry = original
			_returnee_pending = pending
			return _delivered(picked, str(dedup.puzzle_id), &"selected")
	if not found_duplicate.is_empty():
		_returnee_delivery = true
		_baseline_entry = original
		_returnee_pending = duplicate_pending
		return found_duplicate
	return baseline


static func matches_baseline(entry: Dictionary, baseline: Dictionary) -> bool:
	return (
		int(entry.get("size", 0)) == int(baseline.get("size", -1))
		and int(entry.get("r", 0)) == int(baseline.get("_delivery_rank", -1))
	)


static func eligible_special(entry: Dictionary, size: int, rank: int) -> bool:
	var entry_size: int = int(entry.get("size", 0))
	if (size > 0 and entry_size != size) or int(entry.get("r", 0)) != rank:
		return false
	var regions: Array = BankData.get_region_map(entry)
	return (
		regions.size() == entry_size
		and NL11900Strategy._count_single_regions(regions, entry_size) <= 1
	)


func on_delivery(entry: Dictionary) -> void:
	if _returnee_delivery:
		super.on_delivery(_baseline_entry)
		var category: int = int(_returnee_pending["category"])
		GameState.commit_returnee_sp_tt_delivery(
			category,
			int(_returnee_pending["size"]),
			int(_returnee_pending["rank"]),
			{"idx": int(_returnee_pending["idx"]), "t_pos": 0},
			category % SpTtProvider.CATEGORY_COUNT + 1
		)
		GameState.mark_returnee_delivery(12001, _delivery_level, false)
		return
	super.on_delivery(entry)
	if GameState.get_returnee_remaining(12001) > 0:
		var source: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
		GameState.mark_returnee_delivery(12001, _delivery_level, source in ["sp", "lk", "lk_mod"])
