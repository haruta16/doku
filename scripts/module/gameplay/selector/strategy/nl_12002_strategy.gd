## 普通关卡策略 normal_level_12002：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12002Strategy
extends NL11900Strategy

var _returnee_delivery: bool = false
var _fixed_sp_delivery: bool = false
var _delivery_level: int = 0
var _supp_pending: Dictionary = {}
var _lk_skip: int = 0


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12002"


func select(request: LevelSelectRequest) -> Dictionary:
	_returnee_delivery = false
	_supp_pending = {}
	_lk_skip = 0
	_delivery_level = request.level_num
	_fixed_sp_delivery = (
		GameState.get_returnee_remaining(12002) > 0
		and SpecialProvider.SPECIAL_LEVELS.has(request.level_num)
		and not request.ignore_special
	)
	if (
		GameState.get_returnee_remaining(12002) <= 0
		or (SpecialProvider.SPECIAL_LEVELS.has(request.level_num) and not request.ignore_special)
	):
		return _select_baseline(request)
	var range_limits: Vector2i = GameState.get_returnee_easy_range()
	var chosen_rank: int = draw_easy_rank(range_limits.x, range_limits.y)
	var ranks: Array[int] = [chosen_rank]
	for rank: int in range(range_limits.x, range_limits.y + 1):
		if rank != chosen_rank:
			ranks.append(rank)
	for rank: int in ranks:
		var outcome: Dictionary = _select_easy_rank(request, rank)
		if outcome.has("entry"):
			_returnee_delivery = true
			return outcome
	return {"failed_reason": "returnee_single_region_pool_empty"}


func _select_easy_rank(request: LevelSelectRequest, chosen_rank: int) -> Dictionary:
	_supp_pending = {}
	_lk_skip = 0
	_ctx = LevelSelectContext.new()
	_ctx.level_num = request.level_num
	_ctx.sz = SizeModifier.get_size(request.level_num)
	_ctx.rank = chosen_rank
	_ctx.tier = ""
	if _ctx.sz <= 0:
		return {"failed_reason": "no_size"}
	_is_main_path = request.level_num >= 51
	_pools = LevelData.build_pools(_ctx.sz, chosen_rank, "", false, _is_main_path)
	_pools["regular"] = _filter_v113(_pools["regular"])
	_cursor = _create_cursor(request.level_num)
	for attempt: int in range(mini(48, _cursor.budget())):
		var position: Dictionary = _cursor.pos()
		var candidate: Dictionary = LevelData.pick_at(_pools, position, chosen_rank, "")
		if candidate.is_empty():
			break
		_cursor.advance(candidate)
		var outcome: Dictionary = _check_easy_candidate(candidate, request.level_num)
		if outcome.has("entry"):
			return outcome
		if str(candidate.get("_bank_source_main", "")) == "lk_mod":
			for skip: int in range(1, (_pools["lk_mod"] as Array).size() - int(position["lk_idx"])):
				position["lk_idx"] = int(_cursor.pos()["lk_idx"]) + skip
				var next_lk: Dictionary = LevelData.pick_at(_pools, position, chosen_rank, "")
				outcome = _check_easy_candidate(next_lk, request.level_num)
				if outcome.has("entry"):
					_lk_skip = skip
					return outcome
			break
	for skip: int in range(16):
		var supp: Dictionary = SingleRegionSuppProvider.next_entry(_ctx.sz, chosen_rank, 1, skip)
		if supp.is_empty():
			break
		var outcome: Dictionary = _check_easy_candidate(supp["entry"], request.level_num)
		if outcome.has("entry"):
			_supp_pending = supp
			return outcome
	return {}


func _check_easy_candidate(candidate: Dictionary, level: int) -> Dictionary:
	var regions: Array = candidate.get("regionMap", [])
	if regions.size() != _ctx.sz or _count_single_regions(regions, _ctx.sz) != 1:
		return {}
	var validation: Dictionary = FinalLevelValidator.validate(candidate, level)
	if not bool(validation.valid):
		return {}
	var entry: Dictionary = validation.entry
	var dedup: Dictionary = PuzzleDeduplicator.inspect(entry, level)
	if bool(dedup.duplicate):
		return {}
	return _delivered(entry, str(dedup.puzzle_id), &"selected")


static func draw_easy_rank(lower: int, upper: int) -> int:
	if upper <= lower:
		return lower
	if upper == 3 and lower <= 2:
		return 2 + LevelSelectionRandom.pick_weighted(NL11502Strategy.WEIGHTS_R3)
	if upper == 4 and lower <= 2:
		return 2 + LevelSelectionRandom.pick_weighted(NL11502Strategy.WEIGHTS_R4)
	return LevelSelectionRandom.pick_in_range(lower, upper)


func _select_baseline(request: LevelSelectRequest) -> Dictionary:
	return super.select(request)


func on_delivery(entry: Dictionary) -> void:
	if _fixed_sp_delivery:
		GameState.mark_returnee_delivery(12002, _delivery_level, true)
		return
	if _returnee_delivery:
		if _lk_skip > 0:
			var lk_progress: Dictionary = GameState.get_lkmod_progress(_ctx.sz, _ctx.rank)
			lk_progress["idx"] = int(lk_progress.get("idx", 0)) + _lk_skip
			GameState.set_lkmod_progress(_ctx.sz, _ctx.rank, lk_progress, false)
		if not _supp_pending.is_empty():
			SingleRegionSuppProvider.commit(_supp_pending)
			DeliveryPacedCursor.count_delivery(
				_delivery_level, _ctx.sz, _ctx.rank, "", {"_bank_source": "regular"}
			)
		else:
			super.on_delivery(entry)
		GameState.mark_returnee_delivery(12002, _delivery_level, false)
		return
	super.on_delivery(entry)
