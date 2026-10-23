## 普通关卡策略 NLV6DifficultyStrategy：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NLV6DifficultyStrategy
extends NL12100Strategy

const _MAIN_POOL_SOURCES: Array[String] = ["regular", "lkstyle", "gc"]

var _v6_rating_enabled: bool = false
var _v6_single_enabled: bool = false


func _variant() -> int:
	return 0


func max_strategy_at(level_num: int) -> int:
	return maxi(
		super.max_strategy_at(level_num), DifficultyV6Rules.strategy_cap(level_num, _variant())
	)


func select(request: LevelSelectRequest) -> Dictionary:
	_v6_rating_enabled = true
	_v6_single_enabled = true
	return super.select(request)


func _apply_strategy(ctx: LevelSelectContext) -> void:
	var r4_node: int = DifficultyV6Rules.r4_node_level(_variant())
	if r4_node == DifficultyV6Rules.CONTROL_R4_NODE_LEVEL:
		super._apply_strategy(ctx)
		return
	if ctx.level_num >= r4_node and GameState.get_current_strategy() < 2:
		GameState.set_current_strategy(2)
	var strategy: int = LevelData.resolve_strategy(
		ctx.level_num, GameState.get_current_strategy(), 5
	)
	if ctx.level_num >= r4_node:
		strategy = maxi(strategy, 2)
	strategy = mini(strategy, DifficultyV6Rules.strategy_cap(ctx.level_num, _variant()))
	if strategy >= 3:
		strategy = _pick_untagged(strategy)
	ctx.strategy = strategy
	ctx.rank = LevelData.strategy_to_rank(strategy)
	ctx.tier = LevelData.strategy_to_tier(strategy)


func _v6_rating_cap() -> int:
	if not _v6_rating_enabled or _ctx.rank_override > 0 or _ctx.is_super_hard:
		return DifficultyV6Rules.NO_CAP
	if _ctx.is_hard:
		if _variant() != DifficultyV6Rules.VARIANT_HARD_RATING:
			return DifficultyV6Rules.NO_CAP
		return DifficultyV6Rules.hard_rating_cap(_ctx.level_num)
	if _ctx.rank != 4 or not DifficultyV6Rules.is_r4_constraint_level(_ctx.level_num, _variant()):
		return DifficultyV6Rules.NO_CAP
	return DifficultyV6Rules.R4_RATING_CAP


func _v6_required_single() -> int:
	if (
		not _v6_single_enabled
		or _ctx.rank_override > 0
		or _ctx.is_hard
		or _ctx.is_super_hard
		or _ctx.rank != 4
	):
		return DifficultyV6Rules.NO_SINGLE_REQUIREMENT
	return DifficultyV6Rules.required_single_count(
		_ctx.level_num, _variant(), GameState.get_nl_v6_alternate_r4_count_before(_ctx.level_num)
	)


func _v6_constraint_active() -> bool:
	return _v6_rating_cap() >= 0 or _v6_required_single() >= 0


func _v6_pool_key() -> String:
	return (
		"%s_%d_%d_%s_%d_%d"
		% [
			"h" if _ctx.is_hard else "n",
			_ctx.sz,
			_ctx.rank,
			_ctx.tier,
			_v6_rating_cap(),
			_v6_required_single()
		]
	)


func _build_pools_for_ctx() -> Dictionary:
	if not _v6_constraint_active():
		return super._build_pools_for_ctx()
	var rating_cap: int = _v6_rating_cap()
	var required_single: int = _v6_required_single()
	var pools: Dictionary = LevelData.build_pools(
		_ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, false, _is_main_path, required_single >= 0
	)
	pools["regular"] = _filter_v113(pools["regular"])
	for source: String in _MAIN_POOL_SOURCES:
		pools[source] = DifficultyV6Rules.filter_pool(
			pools.get(source, []), rating_cap, _ctx.sz, required_single
		)
	print(
		(
			"[LEVEL.difficulty_v6] %s lv=%d sz=%d rank=%d cap=%d single=%d pool=%d"
			% [
				String(get_strategy_id()),
				_ctx.level_num,
				_ctx.sz,
				_ctx.rank,
				rating_cap,
				required_single,
				V6FilteredPoolCursor._pool_total(pools)
			]
		)
	)
	return pools


func _create_cursor_for_ctx(level_num: int) -> BankCursor:
	if not _v6_constraint_active():
		return super._create_cursor_for_ctx(level_num)
	return V6FilteredPoolCursor.new(_v6_pool_key(), _pools)


## 按本组顺序放宽筛选条件或切换题库，直到取得候选或耗尽兜底阶段。
func _relax_next() -> Dictionary:
	while _v6_rating_enabled or _v6_single_enabled:
		var was_active: bool = _v6_constraint_active()
		if _v6_rating_enabled:
			_v6_rating_enabled = false
		else:
			_v6_single_enabled = false
		if not was_active:
			continue
		_pools = _build_pools_for_ctx()
		_cursor = _create_cursor_for_ctx(_ctx.level_num)
		_outer_budget = _ctx.sz * _ctx.sz * 12
		_inner_budget = _cursor.budget()
		var entry: Dictionary = _scan_current_pool()
		if not entry.is_empty():
			_cursor.advance(entry)
			return entry
	return super._relax_next()


func on_delivery(entry: Dictionary) -> void:
	if _is_alternate_delivery():
		GameState.record_nl_v6_alternate_delivery(
			_ctx.level_num, _should_count_alternate_r4(entry), false
		)
	super.on_delivery(entry)


func _is_alternate_delivery() -> bool:
	if _ctx.is_hard or _ctx.is_super_hard:
		return false
	return DifficultyV6Rules.is_alternate_level(_ctx.level_num, _variant())


func _should_count_alternate_r4(entry: Dictionary) -> bool:
	if _ctx.rank != 4:
		return false
	var source: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
	return source in _MAIN_POOL_SOURCES


func _v6_alt_constrained() -> bool:
	return not _ctx.is_hard and not _ctx.is_super_hard and _v6_rating_cap() >= 0


func _v6_alt_key(source: String) -> String:
	return "%s_%d_%d" % [source, _ctx.sz, _ctx.rank]


func _alt_skip_ids(source: String) -> Array:
	return GameState.get_nl_v6_alt_state(_v6_alt_key(source)).get("ids", [])


func _try_deliver_sp_tt(lv: int) -> Dictionary:
	if not _v6_alt_constrained():
		return super._try_deliver_sp_tt(lv)
	var candidates: Array = []
	for category: int in range(1, SpTtProvider.CATEGORY_COUNT + 1):
		var bucket: Array = SpTtProvider.bucket_entries(category, _ctx.sz, _ctx.rank)
		var progress: Dictionary = GameState.get_sp_tt_progress(category, _ctx.sz, _ctx.rank)
		var consumed: int = (
			bucket.size() if int(progress.get("t_pos", 0)) > 0 else int(progress.get("idx", 0))
		)
		for index: int in range(bucket.size()):
			candidates.append(
				{
					"entry": bucket[index],
					"category": category,
					"index": index,
					"consumed": index < consumed
				}
			)
	var state: Dictionary = GameState.get_nl_v6_alt_state(_v6_alt_key("sp_tt")).duplicate(true)
	var max_rounds: int = 1
	for candidate: Dictionary in candidates:
		var allowed: Array = SpTtProvider.allowed_transforms(int(candidate["category"]))
		max_rounds = maxi(max_rounds, allowed.size())
	var stop_round: int = int(state.get("round", 0)) + max_rounds
	var retrying: bool = false

	while true:
		var choice: Dictionary = _v6_pick_alt("sp_tt", candidates, state)
		if choice.is_empty():
			return {} if retrying else super._try_deliver_sp_tt(lv)
		if int(choice["round"]) >= stop_round:
			return {}
		var candidate: Dictionary = choice["candidate"]
		var category_id: int = int(candidate["category"])
		var allowed: Array = SpTtProvider.allowed_transforms(category_id)
		var transform: int = int(allowed[int(choice["round"]) % allowed.size()])
		var entry: Dictionary = BankData.materialize_entry(candidate["entry"] as Dictionary, true)
		if transform > 0:
			entry = SpTtProvider.apply_entry_transform(entry, transform)
		entry["_bank_source"] = "sp_tt%d" % category_id
		entry["_bank_source_main"] = "sp_tt"
		entry["_bank_idx"] = int(candidate["index"]) + 1
		entry["_bank_transform"] = transform
		entry["_bank_rank"] = _ctx.rank
		entry["_bank_tier"] = ""
		entry["_sp_tt_category"] = category_id
		var validation: Dictionary = FinalLevelValidator.validate(entry, lv)
		if not bool(validation.valid):
			return {}
		var dedup: Dictionary = PuzzleDeduplicator.inspect(validation.entry, lv)
		if bool(dedup.duplicate):
			state = choice["state"]
			retrying = true
			continue
		return _v6_deliver_alt("sp_tt", entry, choice, lv)
	return {}


func _try_deliver_lk_mod(lv: int) -> Dictionary:
	if not _v6_alt_constrained():
		return super._try_deliver_lk_mod(lv)
	var bucket: Array = LevelData.build_pools(_ctx.sz, _ctx.rank, _ctx.tier, false, true).get(
		"lk_mod", []
	)
	var consumed: int = int(GameState.get_lkmod_progress(_ctx.sz, _ctx.rank).get("idx", 0))
	var candidates: Array = []
	for index: int in range(bucket.size()):
		candidates.append({"entry": bucket[index], "index": index, "consumed": index < consumed})
	var choice: Dictionary = _v6_pick_alt("lk_mod", candidates)
	if choice.is_empty():
		return super._try_deliver_lk_mod(lv)
	var candidate: Dictionary = choice["candidate"]
	var entry: Dictionary = (candidate["entry"] as Dictionary).duplicate(true)
	entry["_bank_source"] = "lk_mod"
	entry["_bank_source_main"] = "lk_mod"
	entry["_bank_idx"] = int(candidate["index"]) + 1
	entry["_bank_transform"] = 0
	entry["_bank_rank"] = _ctx.rank
	entry["_bank_tier"] = ""
	return _v6_deliver_alt("lk_mod", entry, choice, lv)


func _v6_pick_alt(source: String, candidates: Array, state_override: Dictionary = {}) -> Dictionary:
	if candidates.is_empty():
		return {}
	var state: Dictionary = (
		GameState.get_nl_v6_alt_state(_v6_alt_key(source))
		if state_override.is_empty()
		else state_override
	)
	var used_ids: Array = state.get("ids", [])
	var round_index: int = int(state.get("round", 0))
	var picked: int = _v6_nearest_candidate(candidates, used_ids, round_index == 0)
	if picked < 0:
		round_index += 1
		used_ids = []
		picked = _v6_nearest_candidate(candidates, used_ids, false)
	if picked < 0:
		return {}
	var candidate: Dictionary = candidates[picked]
	var next_ids: Array = used_ids.duplicate()
	next_ids.append(int((candidate["entry"] as Dictionary).get("id", -1)))
	return {
		"candidate": candidate,
		"round": round_index,
		"state": {"ids": next_ids, "round": round_index}
	}


func _v6_nearest_candidate(candidates: Array, used_ids: Array, skip_consumed: bool) -> int:
	var entries: Array = []
	var blocked_ids: Array = used_ids.duplicate()
	for candidate: Dictionary in candidates:
		var entry: Dictionary = candidate["entry"]
		entries.append(entry)
		if skip_consumed and bool(candidate["consumed"]):
			blocked_ids.append(int(entry.get("id", -1)))
	return DifficultyV6Rules.pick_nearest_index(
		entries, blocked_ids, _v6_rating_cap(), _ctx.sz, _v6_required_single()
	)


func _v6_deliver_alt(source: String, entry: Dictionary, choice: Dictionary, lv: int) -> Dictionary:
	var delivered: Dictionary = _deliver_special(entry, lv)
	if delivered.is_empty():
		return {}
	_alt_pending_commit = {
		"source": source, "v6_key": _v6_alt_key(source), "v6_state": choice["state"]
	}
	print(
		(
			"[LEVEL.difficulty_v6] %s alt lv=%d src=%s sz=%d rank=%d rating=%.2f cap=%d single_req=%d round=%d"
			% [
				String(get_strategy_id()),
				lv,
				source,
				_ctx.sz,
				_ctx.rank,
				float(entry.get("rating", -1.0)),
				_v6_rating_cap(),
				_v6_required_single(),
				int(choice["round"])
			]
		)
	)
	return delivered


func _commit_alt_delivery(entry: Dictionary) -> bool:
	if not _alt_pending_commit.has("v6_state"):
		return super._commit_alt_delivery(entry)
	var source: String = str(_alt_pending_commit.get("source", ""))
	if entry.get("_bank_source_main", "") != source:
		return false
	GameState.set_nl_v6_alt_state(
		str(_alt_pending_commit["v6_key"]), _alt_pending_commit["v6_state"], false
	)
	_advance_alt_block(source)
	return true
