## 普通关卡策略 normal_level_12005：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12005Strategy
extends NL11900Strategy

var _hard_delivery: bool = false


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12005"


func _alternate_hard() -> bool:
	return false


func select(request: LevelSelectRequest) -> Dictionary:
	_hard_delivery = false
	var level: int = request.level_num
	if (
		request.rank_override == 0
		and level >= 110
		and is_hard_level(level)
		and not SpecialProvider.SPECIAL_LEVELS.has(level)
	):
		return _select_rating_hard(level)
	return super.select(request)


func _select_rating_hard(level: int) -> Dictionary:
	_ctx = LevelSelectContext.new()
	_ctx.level_num = level
	_ctx.sz = SizeModifier.get_size(level)
	_ctx.is_hard = true
	_ctx.rank = HardRatingSelector.rank_at(level, _alternate_hard())
	_ctx.tier = "N"
	if _ctx.sz == 0:
		return {"failed_reason": "no_size"}
	var pools: Dictionary
	if _ctx.rank == 4:
		pools = {
			"regular": HardRatingSelector.filter_pool(BankData.get_hard_r4_levels(), 4),
			"lkstyle": [],
			"gc": [],
			"lk_mod": [],
		}
	else:
		pools = LevelData.build_pools(_ctx.sz, _ctx.rank, "N", true, true)
		pools["regular"] = _filter_v113(pools["regular"])
		for source: String in ["regular", "lkstyle", "gc", "lk_mod"]:
			pools[source] = HardRatingSelector.filter_pool(pools[source], _ctx.rank)
	var cursor: BankCursor = DeliveryPacedCursor.new(_ctx.sz, _ctx.rank, "N", level, pools)
	var budget: int = cursor.budget()
	if budget <= 0:
		return {"failed_reason": "no_rating_hard_pool"}
	for attempt: int in range(budget):
		var entry: Dictionary = LevelData.pick_at(pools, cursor.pos(), _ctx.rank, "N")
		if entry.is_empty():
			break
		cursor.advance(entry)
		var validation: Dictionary = FinalLevelValidator.validate(entry, level)
		if not bool(validation.valid):
			continue
		entry = validation.entry
		var dedup: Dictionary = PuzzleDeduplicator.inspect(entry, level)
		if bool(dedup.duplicate) and attempt + 1 < budget:
			continue
		_hard_delivery = true
		return _delivered(
			entry,
			str(dedup.puzzle_id),
			&"duplicate_fallback" if bool(dedup.duplicate) else &"selected"
		)
	return {"failed_reason": "no_valid_rating_hard"}


func on_delivery(entry: Dictionary) -> void:
	if _hard_delivery:
		DeliveryPacedCursor.count_delivery(_ctx.level_num, _ctx.sz, _ctx.rank, "N", entry)
		return
	super.on_delivery(entry)
