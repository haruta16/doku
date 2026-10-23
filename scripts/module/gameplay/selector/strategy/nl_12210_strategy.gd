## 普通关卡策略 normal_level_12210：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12210Strategy
extends LevelSelectionStrategy

const COARSE_SINGLE_LIMIT: int = 2
const MAX_RANK_PROBE: int = 7
const RELAX_PHASE_COUNT: int = 9

const ELO_RANKS: Array = [3, 4, 5]
const ELO_POLICY_VALUE: int = 11920
const FIRST_TARGET_LEVEL: int = 11
const COOLDOWN_LEVELS: int = 3
const BLOCK_SIZE: int = 6
const ELO_INITIAL_NEW_PLAYER: float = -1.0
const ELO_INITIAL_OLD_PLAYER: float = 750.0

const STYLE_WINDOW_LEVELS: int = 14
const STYLE_MAX_GROUPS: int = 2
const STYLE_SELECTION_BUDGET_USEC: int = 400000
const STYLE_SELECTION_MAX_COMPARISONS: int = 100

var _ctx: LevelSelectContext
var _pools: Dictionary
var _cursor: BankCursor
var _strict_rank: bool
var _is_main_path: bool
var _outer_budget: int
var _inner_budget: int
var _coarse_single_limit: int
var _dispersion_enabled: bool
var _ab_filter_enabled: bool
var _elo_filter_enabled: bool
var _elo_bounds: Vector2
var _elo_target: float

var _style_filter_enabled: bool

var _style_window: Array

var _style_reject_count: int
var _style_budget: Dictionary
var _dedup_retries: int
var _relax_phase: int
var _original_rank: int
var _use_super_hard_pool: bool = false
var _sh_anchor: int = 0
var _alt_pending_commit: Dictionary = {}
var _elo_target_band: Vector2 = Vector2.ZERO


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12210"


## 声明策略实现版本，和实验组标识一起描述当前选题规则。
func get_strategy_version() -> int:
	return 1


func select(request: LevelSelectRequest) -> Dictionary:
	_reset_run_state()
	_style_budget = {
		"deadline_usec": Time.get_ticks_usec() + STYLE_SELECTION_BUDGET_USEC,
		"comparisons_left": STYLE_SELECTION_MAX_COMPARISONS,
	}
	var lv: int = request.level_num

	_ctx = LevelSelectContext.new()
	_ctx.level_num = lv
	_ctx.rank_override = request.rank_override

	_ctx.sz = SizeModifier.get_size(lv)
	if _ctx.sz == 0:
		return {"failed_reason": "no_size"}

	HardLevelModifier.apply(_ctx)
	var is_super_hard: bool = is_super_hard_level(lv)
	_sh_anchor = GameState.ensure_super_hard_anchor(lv) if is_super_hard else 0
	SuperHardModifier.apply(_ctx, is_super_hard, _sh_anchor)

	if request.rank_override > 0:
		StrategyModifier.apply_override(_ctx)
	elif not _ctx.is_hard and not _ctx.is_super_hard:
		_apply_strategy(_ctx)

	DailyFirstEasyModifier.apply(_ctx)
	TierFallbackModifier.apply(_ctx)

	_ensure_elo_initialized()

	_elo_filter_enabled = lv >= 21 and _ctx.rank in ELO_RANKS and not _ctx.is_super_hard
	if _elo_filter_enabled:
		var player_rating: float = GameState.get_elo_rating(_ctx.rank)
		var band: Vector2 = EloRatingMath.band_for_state(GameState.get_elo_band(_ctx.rank))
		_elo_target_band = band
		_elo_bounds = EloRatingMath.puzzle_rating_bounds(player_rating, band)
		_elo_target = EloRatingMath.random_target_rating(player_rating, band)

	_style_filter_enabled = _elo_filter_enabled
	_style_window = (
		GameState.get_recent_style_vectors(STYLE_WINDOW_LEVELS) if _style_filter_enabled else []
	)
	_style_reject_count = 0

	if _evaluate_alt_trigger(lv):
		var alternate: Dictionary = _try_deliver_alt(lv)
		if not alternate.is_empty():
			return alternate

	if SpecialProvider.SPECIAL_LEVELS.has(lv) and not _ctx.is_super_hard:
		var sp_entry: Dictionary = SpecialProvider.new().next_entry(_ctx)
		if not sp_entry.is_empty():
			return _deliver_special(sp_entry, lv)

	_is_main_path = lv >= 51
	_strict_rank = _ctx.is_hard or _ctx.is_super_hard
	_use_super_hard_pool = _ctx.is_super_hard
	_pools = _build_pools_for_ctx()
	_cursor = _create_cursor(lv)
	_coarse_single_limit = COARSE_SINGLE_LIMIT
	_dispersion_enabled = false
	_ab_filter_enabled = true
	_outer_budget = _ctx.sz * _ctx.sz * 12
	_inner_budget = _cursor.budget()
	_dedup_retries = 0
	_relax_phase = 0
	_original_rank = _ctx.rank

	if _elo_filter_enabled:
		var ordered_entry: Dictionary = _try_normal_elo_delivery(lv)
		if not ordered_entry.is_empty():
			return ordered_entry

	while true:
		var entry: Dictionary = _next_candidate()
		if entry.is_empty():
			return {}

		var validation: Dictionary = FinalLevelValidator.validate(entry, lv)
		if not bool(validation.valid):
			_outer_budget -= 1
			if _strict_rank:
				_strict_rank = false
				_rebuild_pools()
			continue
		entry = validation.entry

		if _ab_filter_enabled and _exceeds_single_region_limit(entry, _ab_single_limit()):
			_outer_budget -= 1
			continue

		var dedup: Dictionary = PuzzleDeduplicator.inspect(entry, lv)
		if bool(dedup.duplicate):
			if _dedup_retries < _dedup_retry_cap():
				_outer_budget -= 1
				_dedup_retries += 1
				continue
			PuzzleDeduplicator.log_duplicate(dedup.previous, entry, lv, dedup.puzzle_id)
			return _delivered(entry, str(dedup.puzzle_id), &"duplicate_fallback")

		return _delivered(entry, str(dedup.puzzle_id), &"selected")
	return {}


func _apply_strategy(ctx: LevelSelectContext) -> void:
	var cur: int = GameState.get_current_strategy()
	if ctx.level_num >= 51 and cur < 2:
		GameState.set_current_strategy(2)
	var strategy: int = LevelData.resolve_strategy(
		ctx.level_num, GameState.get_current_strategy(), 5
	)
	if ctx.level_num >= 51:
		strategy = mini(strategy, 4)
	elif ctx.level_num >= 21:
		strategy = mini(strategy, 3)
	else:
		strategy = mini(strategy, 2)

	if strategy >= 3:
		strategy = NL11709Strategy._pick_untagged(strategy)

	ctx.strategy = strategy
	ctx.rank = LevelData.strategy_to_rank(strategy)
	ctx.tier = LevelData.strategy_to_tier(strategy)


func _ensure_elo_initialized() -> void:
	var is_new_player: bool = GameState.ensure_elo_group2_cohort()
	var initial: float = ELO_INITIAL_NEW_PLAYER if is_new_player else ELO_INITIAL_OLD_PLAYER
	for rank: int in ELO_RANKS:
		GameState.init_elo_rating(rank, initial)


func _create_cursor(level_num: int) -> BankCursor:
	if _use_super_hard_pool:
		return SuperHardBankCursor.new(level_num, _sh_anchor, _pools)
	if _is_main_path:
		return DeliveryPacedCursor.new(_ctx.sz, _ctx.rank, _ctx.tier, level_num, _pools)
	return BankCursor.create(level_num, _ctx.sz, _ctx.rank, _ctx.tier, _pools)


## 给出去重重试次数上限，避免候选空间不足时无限选题。
func _dedup_retry_cap() -> int:
	return mini(_cursor.budget(), GameState.get_recent_puzzle_count() + 1)


func _next_candidate() -> Dictionary:
	if _outer_budget <= 0:
		return _relax_next()
	_inner_budget = _cursor.budget()

	var entry: Dictionary = _scan_current_pool()
	if entry.is_empty():
		return _relax_next()

	_cursor.advance(entry)
	return entry


func _scan_current_pool() -> Dictionary:
	while true:
		var entry: Dictionary = LevelData.pick_at(_pools, _cursor.pos(), _ctx.rank, _ctx.tier)
		if entry.is_empty():
			return {}

		var rejected: bool = false

		if _exceeds_single_region_limit(entry, _coarse_single_limit):
			rejected = true

		if not rejected and _dispersion_enabled and _is_too_dispersed(entry):
			rejected = true

		if not rejected:
			return entry

		if _inner_budget <= 1:
			return entry

		_cursor.advance(entry)
		_inner_budget -= 1
	return {}


func _exceeds_single_region_limit(entry: Dictionary, limit: int) -> bool:
	if limit < 0:
		return false
	var src: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
	if src in ["lk_mod", "sp", "lk"]:
		return false
	var rm: Array = entry.get("regionMap", [])
	if rm.size() != _ctx.sz:
		return false
	return _count_single_regions(rm, _ctx.sz) > limit


## 按当前关卡和难度查询单格区域数量实验，返回这一轮筛选的上限。
func _ab_single_limit() -> int:
	return ABTestManager.single_region_num.single_limit_at(_ctx.level_num, _ctx.rank)


func _is_too_dispersed(entry: Dictionary) -> bool:
	var src: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
	if src in ["lk_mod", "sp", "lk"]:
		return false
	var rm: Array = entry.get("regionMap", [])
	if rm.size() != _ctx.sz:
		return false
	return (
		QueendokuCore.compute_avg_region_bbox_fill_ratio(rm)
		< QueendokuCore.DISPERSION_DENSITY_THRESHOLD
	)


## 统计只包含一个格子的区域；用于限制可直接确定猫位置的单格区域数量。
static func _count_single_regions(region_map: Array, board_size: int) -> int:
	var region_counts: Dictionary = {}
	for row: int in range(board_size):
		for column: int in range(board_size):
			var region_id: int = int((region_map[row] as Array)[column])
			region_counts[region_id] = int(region_counts.get(region_id, 0)) + 1
	var single: int = 0
	var counts: Array = region_counts.values()
	for count: int in counts:
		if count == 1:
			single += 1
	return single


## 过滤 v113 批次题目；是否剔除由本实验组的 _should_drop_v113 决定。
func _filter_v113(regular: Array) -> Array:
	var kept: Array = []
	for entry: Dictionary in regular:
		if str(entry.get("batch", "")) == "v113" and _should_drop_v113(entry):
			continue
		kept.append(entry)
	return kept


func _should_drop_v113(_entry: Dictionary) -> bool:
	return true


## 按本组顺序放宽筛选条件或切换题库，直到取得候选或耗尽兜底阶段。
func _relax_next() -> Dictionary:
	while _relax_phase < RELAX_PHASE_COUNT:
		_relax_phase += 1
		match _relax_phase:
			1:
				_dispersion_enabled = false
			2:
				_coarse_single_limit = -1
			3:
				_ab_filter_enabled = false
			4:
				_elo_filter_enabled = false
			5:
				_style_filter_enabled = false
			6:
				_switch_pool(_ctx.rank, "")
			7:
				for r: int in range(_original_rank - 1, 0, -1):
					_switch_pool(r, "")
					var lower: Dictionary = _scan_after_switch()
					if not lower.is_empty():
						return lower
				continue
			8:
				var max_r: int = _max_available_rank()
				for r: int in range(_original_rank + 1, max_r + 1):
					_switch_pool(r, "")
					var higher: Dictionary = _scan_after_switch()
					if not higher.is_empty():
						return higher
				continue

		_outer_budget = _ctx.sz * _ctx.sz * 12
		_inner_budget = _cursor.budget()
		var entry: Dictionary = _scan_current_pool()
		if not entry.is_empty():
			_cursor.advance(entry)
			return entry
	return {}


## 切换上下文里的难度和层级，同时重建候选池与游标扫描预算。
func _switch_pool(new_rank: int, new_tier: String) -> void:
	_ctx.rank = new_rank
	_ctx.tier = new_tier
	_use_super_hard_pool = false
	_rebuild_pools()
	_cursor = _create_cursor(_ctx.level_num)
	_outer_budget = _ctx.sz * _ctx.sz * 12


## 按当前上下文重新取得候选池，并把已有游标绑定到新池。
func _rebuild_pools() -> void:
	_pools = _build_pools_for_ctx()
	_cursor.rebind_pools(_pools)


func _scan_after_switch() -> Dictionary:
	_outer_budget = _ctx.sz * _ctx.sz * 12
	_inner_budget = _cursor.budget()
	var entry: Dictionary = _scan_current_pool()
	if not entry.is_empty():
		_cursor.advance(entry)
	return entry


func _max_available_rank() -> int:
	var top: int = 1
	for r: int in range(1, MAX_RANK_PROBE + 1):
		var pools: Dictionary = LevelData.build_pools(_ctx.sz, r, "", false, false, _is_main_path)
		if _pool_total(pools) > 0:
			top = r
	return top


## 合计各候选题库的题目数量，供探测当前难度是否还有可用题目。
static func _pool_total(pools: Dictionary) -> int:
	return (
		(pools.get("regular", []) as Array).size()
		+ (pools.get("lkstyle", []) as Array).size()
		+ (pools.get("gc", []) as Array).size()
		+ (pools.get("lk_mod", []) as Array).size()
	)


func _deliver_special(entry: Dictionary, lv: int) -> Dictionary:
	var validation: Dictionary = FinalLevelValidator.validate(entry, lv)
	if not bool(validation.valid):
		return {}
	var final_entry: Dictionary = validation.entry
	var dedup: Dictionary = PuzzleDeduplicator.inspect(final_entry, lv)
	if bool(dedup.duplicate):
		PuzzleDeduplicator.log_duplicate(dedup.previous, final_entry, lv, dedup.puzzle_id)
		return _delivered(final_entry, str(dedup.puzzle_id), &"duplicate_fallback", false)
	return _delivered(final_entry, str(dedup.puzzle_id), &"selected", false)


func _attach_elo_fields(entry: Dictionary) -> Dictionary:
	entry["is_elo_delivery"] = false
	var rank: int = int(entry.get("_bank_rank", entry.get("r", 0)))
	if (
		_ctx.is_super_hard
		or _ctx.level_num < 21
		or not rank in ELO_RANKS
		or not _has_valid_elo_rating(entry)
	):
		return entry
	var puzzle_rating: float = float(entry["eloRating"])
	var player_rating: float = GameState.get_elo_rating(rank)
	var band: Vector2 = EloRatingMath.band_for_state(GameState.get_elo_band(rank))
	var bounds: Vector2 = EloRatingMath.puzzle_rating_bounds(player_rating, band)
	entry["_elo_e"] = EloRatingMath.e_from_ratings(puzzle_rating, player_rating)
	entry["_elo_k"] = EloRatingMath.k_for_group(
		ELO_POLICY_VALUE, GameState.get_elo_games(rank), GameState.is_elo_group2_new_player()
	)
	entry["_elo_player_rating"] = player_rating
	entry["_elo_Emin"] = band.x
	entry["_elo_Emax"] = band.y
	entry["_elo_in_band"] = puzzle_rating >= bounds.x and puzzle_rating <= bounds.y
	entry["is_elo_delivery"] = true
	return entry


## 把题目、去重标识与交付状态装进统一结果，交给选题入口完成后续提交。
func _delivered(
	entry: Dictionary, puzzle_id: String, status: StringName, attach_elo: bool = true
) -> Dictionary:
	entry = _attach_elo_fields(entry) if attach_elo else entry
	if not attach_elo:
		entry["is_elo_delivery"] = false
	return {"entry": entry, "puzzle_id": puzzle_id, "status": status}


func on_delivery(entry: Dictionary) -> void:
	if not _alt_pending_commit.is_empty():
		_commit_alt_delivery(entry)
	elif not _ctx.is_super_hard:
		DeliveryPacedCursor.count_delivery(_ctx.level_num, _ctx.sz, _ctx.rank, _ctx.tier, entry)
	var rank: int = int(entry.get("_bank_rank", entry.get("r", 0)))
	if bool(entry.get("is_elo_delivery", false)) and rank in ELO_RANKS and not _ctx.is_super_hard:
		GameState.set_elo_active_delivery(rank, float(entry["eloRating"]))
		GameState.mark_elo_pid_selected(str(entry.get("_pid_h", "")))
		_log_pre(rank, float(entry["eloRating"]), str(entry.get("_bank_source_main", "")))
	else:
		GameState.set_elo_active_delivery(0, 0.0)


func _log_pre(rank: int, puzzle_rating: float, source: String) -> void:
	var player_rating: float = GameState.get_elo_rating(rank)
	var k_factor: float = EloRatingMath.k_for_group(
		ELO_POLICY_VALUE, GameState.get_elo_games(rank), GameState.is_elo_group2_new_player()
	)
	var band: Vector2 = EloRatingMath.band_for_state(GameState.get_elo_band(rank))
	var expected_score: float = EloRatingMath.e_from_ratings(puzzle_rating, player_rating)
	print(
		(
			"[Level.ELO] PRE group=%s lv=%d rank=%d K=%.1f E=%.4f Emin=%.2f Emax=%.2f player=%.2f puzzle=%.2f source=%s style_rejects=%d"
			% [
				get_strategy_id(),
				_ctx.level_num,
				rank,
				k_factor,
				expected_score,
				band.x,
				band.y,
				player_rating,
				puzzle_rating,
				source,
				_style_reject_count
			]
		)
	)


func on_level_won_settlement(ctx: LevelSettlementContext) -> void:
	var delivery: Dictionary = ctx.elo_original_delivery
	var rank: int = int(delivery.get("rank", 0))
	if not rank in ELO_RANKS:
		return
	var puzzle_rating: float = float(delivery.get("puzzle_rating", 0.0))
	var player_rating: float = float(delivery.get("player_rating", 0.0))
	var k_factor: float = EloRatingMath.k_for_group(
		ELO_POLICY_VALUE,
		int(delivery.get("games_before", 0)),
		bool(delivery.get("is_new_player", false))
	)
	var performance_score: float = EloRatingMath.s_from_fish(
		int(delivery.get("fish_consumed", 0)), ctx.tool_or_revive_used
	)
	var expected_score: float = EloRatingMath.e_from_ratings(puzzle_rating, player_rating)
	var new_rating: float = EloRatingMath.new_player_rating(
		player_rating, k_factor, performance_score, expected_score
	)
	var new_band: int = EloRatingMath.next_band_state(
		ctx.strategy - ctx.strategy_before_all, int(delivery.get("band", 0))
	)
	ctx.elo_v2_settlement = {"rank": rank, "rating": new_rating, "band": new_band}
	print(
		(
			"[Level.ELO] POST group=%s lv=%d rank=%d K=%.1f S=%.2f E=%.4f delta=%.2f player_new=%.2f puzzle=%.2f"
			% [
				get_strategy_id(),
				ctx.level_num,
				rank,
				k_factor,
				performance_score,
				expected_score,
				k_factor * (performance_score - expected_score),
				new_rating,
				puzzle_rating
			]
		)
	)


func _pick_elo_order(order: Array, source_key: String = "") -> Dictionary:
	var selected_ids: Array = (
		GameState.get_elo_v2_source_selected_ids(source_key) if not source_key.is_empty() else []
	)
	var validate: Callable = func(candidate: Dictionary) -> bool:
		if not _has_valid_elo_rating(candidate):
			return false
		var checked: Dictionary = FinalLevelValidator.validate(candidate, _ctx.level_num)
		if not bool(checked.get("valid", false)):
			return false
		var valid_entry: Dictionary = checked.get("entry", {})
		if _reject_style(valid_entry):
			return false
		var duplicate: Dictionary = PuzzleDeduplicator.inspect(valid_entry, _ctx.level_num)
		return not bool(duplicate.get("duplicate", false))
	var is_selected: Callable = func(pid: String) -> bool:
		if source_key.is_empty():
			return GameState.is_elo_pid_selected(pid)
		return selected_ids.has(int(pid))
	var picked: Dictionary = EloSortedPickProvider.pick_from_order(
		order,
		_ctx.rank,
		_ctx.tier,
		_elo_target,
		_elo_bounds,
		validate,
		is_selected,
		func(_pid: String) -> void: return,
		false
	)
	if not picked.is_empty():
		picked["_elo_pick_mode"] = "in_band"
		picked["_elo_fallback_reason"] = "none"
	if picked.is_empty():
		var in_band_count: int = 0
		for item: Dictionary in order:
			var rating: float = float(item.get("elo", INF))
			if rating >= _elo_bounds.x and rating <= _elo_bounds.y:
				in_band_count += 1
		picked = EloSortedPickProvider.pick_from_order(
			order,
			_ctx.rank,
			_ctx.tier,
			_elo_target,
			_elo_bounds,
			validate,
			is_selected,
			func(_pid: String) -> void: return,
			true
		)
		if not picked.is_empty():
			var rating: float = float(picked["eloRating"])
			var matched: bool = rating >= _elo_bounds.x and rating <= _elo_bounds.y
			picked["_elo_pick_mode"] = "in_band_retry" if matched else "nearest"
			picked["_elo_fallback_reason"] = (
				"target_scan_exhausted"
				if matched
				else ("empty_rating_band" if in_band_count == 0 else "no_usable_in_band")
			)
	return picked


func _try_normal_elo_delivery(level_num: int) -> Dictionary:
	var position: Dictionary = _cursor.pos()
	var scheduled: Dictionary = LevelData.pick_at(_pools, position, _ctx.rank, _ctx.tier)
	if scheduled.is_empty() or not _has_valid_elo_rating(scheduled):
		return {}
	var scheduled_source: String = str(
		scheduled.get("_bank_source_main", scheduled.get("_bank_source", ""))
	)
	var merged_order: Array = EloSortedPickProvider.get_sorted_order(
		_pools, _ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, _is_main_path, "main"
	)
	var order: Array = []
	for item: Dictionary in merged_order:
		if str(item.get("source", "")) != scheduled_source:
			continue
		var transformed_item: Dictionary = item.duplicate()
		transformed_item["transform"] = int(position.get("transform", 0))
		order.append(transformed_item)
	var picked: Dictionary = _pick_elo_order(order)
	if picked.is_empty():
		return {}
	var checked: Dictionary = FinalLevelValidator.validate(picked, level_num)
	if not bool(checked.get("valid", false)):
		return {}
	var entry: Dictionary = checked.get("entry", {})
	var dedup: Dictionary = PuzzleDeduplicator.inspect(entry, level_num)
	_cursor.advance(entry)
	return _delivered(entry, str(dedup.get("puzzle_id", "")), &"selected")


func _has_valid_elo_rating(entry: Dictionary) -> bool:
	var rating: Variant = entry.get("eloRating")
	return (rating is int or rating is float) and is_finite(float(rating))


func _source_order(
	bucket: Array, source: String, start_index: int, transform: int, selected_ids: Array
) -> Array:
	var result: Array = []
	for index: int in range(start_index, bucket.size()):
		var original: Dictionary = bucket[index]
		var entry_id: int = int(original.get("id", -1))
		if selected_ids.has(entry_id) or not _has_valid_elo_rating(original):
			continue
		result.append(
			{
				"elo": float(original["eloRating"]),
				"pid": str(entry_id),
				"ref": original,
				"source": source,
				"idx": index,
				"transform": transform,
				"tier": ""
			}
		)
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			if float(left["elo"]) != float(right["elo"]):
				return float(left["elo"]) < float(right["elo"])
			return int(left["idx"]) < int(right["idx"])
	)
	return result


func _next_unselected_index(
	bucket: Array, start_index: int, selected_ids: Array, chosen_id: int
) -> int:
	var next_index: int = start_index
	while next_index < bucket.size():
		var entry: Dictionary = bucket[next_index]
		var entry_id: int = int(entry.get("id", -1))
		if entry_id != chosen_id and not selected_ids.has(entry_id):
			break
		next_index += 1
	return next_index


func _next_elo_sp_tt() -> Dictionary:
	var start_category: int = GameState.get_sp_tt_category_cursor()
	for offset: int in range(SpTtProvider.CATEGORY_COUNT):
		var category: int = ((start_category - 1 + offset) % SpTtProvider.CATEGORY_COUNT) + 1
		var bucket: Array = SpTtProvider.bucket_entries(category, _ctx.sz, _ctx.rank)
		if bucket.is_empty():
			continue
		var allowed: Array = SpTtProvider.allowed_transforms(category)
		var progress: Dictionary = GameState.get_sp_tt_progress(category, _ctx.sz, _ctx.rank)
		var start_index: int = int(progress.get("idx", 0))
		var transform_position: int = int(progress.get("t_pos", 0))
		if start_index >= bucket.size():
			start_index = 0
			transform_position += 1
		if transform_position >= allowed.size():
			continue
		var transform: int = int(allowed[transform_position])
		var source_key: String = (
			"sp_tt:%d:%d:%d:%d" % [category, _ctx.sz, _ctx.rank, transform_position]
		)
		var selected_ids: Array = GameState.get_elo_v2_source_selected_ids(source_key)
		start_index = _next_unselected_index(bucket, start_index, selected_ids, -1)
		if start_index >= bucket.size():
			continue
		var head: Dictionary = bucket[start_index]
		var entry: Dictionary = {}
		if _has_valid_elo_rating(head):
			var order: Array = _source_order(bucket, "sp_tt", start_index, transform, selected_ids)
			entry = _pick_elo_order(order, source_key)
		if entry.is_empty():
			entry = BankData.materialize_entry(bucket[start_index] as Dictionary, true)
			if transform > 0:
				entry = SpTtProvider.apply_entry_transform(entry, transform)
			entry["_bank_idx"] = start_index + 1
			entry["_bank_transform"] = transform
			entry["_bank_rank"] = _ctx.rank
			entry["_bank_tier"] = ""
		entry["_bank_source"] = "sp_tt%d" % category
		entry["_bank_source_main"] = "sp_tt"
		entry["_sp_tt_category"] = category
		var chosen_id: int = int(entry.get("id", -1))
		var next_index: int = _next_unselected_index(bucket, start_index, selected_ids, chosen_id)
		return {
			"entry": entry,
			"category": category,
			"sz": _ctx.sz,
			"rank": _ctx.rank,
			"new_progress": {"idx": next_index, "t_pos": transform_position},
			"elo_key": source_key
		}
	return {}


func _try_elo_lk_mod(level_num: int) -> Dictionary:
	var pools: Dictionary = LevelData.build_pools(_ctx.sz, _ctx.rank, _ctx.tier, false, true)
	var bucket: Array = pools.get("lk_mod", [])
	if bucket.is_empty():
		return {}
	var progress: Dictionary = GameState.get_lkmod_progress(_ctx.sz, _ctx.rank)
	var start_index: int = int(progress.get("idx", 0))
	var source_key: String = "lk_mod:%d:%d" % [_ctx.sz, _ctx.rank]
	var selected_ids: Array = GameState.get_elo_v2_source_selected_ids(source_key)
	start_index = _next_unselected_index(bucket, start_index, selected_ids, -1)
	if start_index >= bucket.size():
		return {}
	var head: Dictionary = bucket[start_index]
	var entry: Dictionary = {}
	if _has_valid_elo_rating(head):
		var order: Array = _source_order(bucket, "lk_mod", start_index, 0, selected_ids)
		entry = _pick_elo_order(order, source_key)
	if entry.is_empty():
		entry = BankData.materialize_entry(bucket[start_index] as Dictionary, true)
		entry["_bank_idx"] = start_index + 1
		entry["_bank_transform"] = 0
		entry["_bank_rank"] = _ctx.rank
		entry["_bank_tier"] = ""
	entry["_bank_source"] = "lk_mod"
	entry["_bank_source_main"] = "lk_mod"
	var delivered: Dictionary = _deliver_alt(entry, level_num)
	if delivered.is_empty():
		return {}
	var next_index: int = _next_unselected_index(
		bucket, start_index, selected_ids, int(entry.get("id", -1))
	)
	_alt_pending_commit = {
		"source": "lk_mod",
		"sz": _ctx.sz,
		"rank": _ctx.rank,
		"new_idx": next_index,
		"elo_key": source_key
	}
	return delivered


func is_super_hard_level(level_num: int) -> bool:
	return SuperHardSchedule.is_super_hard(level_num)


func _reset_run_state() -> void:
	_ctx = null
	_pools = {}
	_cursor = null
	_strict_rank = false
	_is_main_path = false
	_outer_budget = 0
	_inner_budget = 0
	_coarse_single_limit = COARSE_SINGLE_LIMIT
	_dispersion_enabled = false
	_ab_filter_enabled = false
	_elo_filter_enabled = false
	_elo_bounds = Vector2(-INF, INF)
	_elo_target = 0.0
	_elo_target_band = Vector2.ZERO
	_style_filter_enabled = false
	_style_window = []
	_style_reject_count = 0
	_style_budget = {}
	_dedup_retries = 0
	_relax_phase = 0
	_original_rank = 0
	_use_super_hard_pool = false
	_sh_anchor = 0
	_alt_pending_commit = {}


func _build_pools_for_ctx() -> Dictionary:
	if _use_super_hard_pool:
		return LevelData.build_super_hard_pools()
	var pools: Dictionary = LevelData.build_pools(
		_ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, false, _is_main_path
	)
	pools["regular"] = _filter_v113(pools.get("regular", []))
	return pools


func _reject_style(entry: Dictionary) -> bool:
	if not _style_filter_enabled or LevelSimilarity.is_budget_exhausted(_style_budget):
		return false
	var rejected: bool = LevelSimilarity.creates_excess_groups(
		entry, _style_window, STYLE_MAX_GROUPS, _style_budget
	)
	if rejected:
		_style_reject_count += 1
	return rejected


func _evaluate_alt_trigger(level_num: int) -> bool:
	var last: int = GameState.get_sp_tt_lk_alt_last_replaced_level()
	var target: int = FIRST_TARGET_LEVEL if last == 0 else last + COOLDOWN_LEVELS
	return (
		level_num >= target
		and not _ctx.is_hard
		and not _ctx.is_super_hard
		and not SpecialProvider.SPECIAL_LEVELS.has(level_num)
		and not GameState.is_current_level_daily_first_easy()
	)


func _try_deliver_alt(level_num: int) -> Dictionary:
	return (
		_try_deliver_lk_mod(level_num)
		if GameState.get_sp_tt_lk_alt_block_source() == "lk_mod"
		else _try_deliver_sp_tt(level_num)
	)


func _try_deliver_sp_tt(level_num: int) -> Dictionary:
	var picked: Dictionary = (
		_next_elo_sp_tt() if _elo_filter_enabled else SpTtProvider.next_entry(_ctx.sz, _ctx.rank)
	)
	if picked.is_empty():
		return {}
	var delivered: Dictionary = _deliver_alt(picked.get("entry", {}), level_num, picked)
	if not delivered.is_empty():
		_alt_pending_commit = {
			"source": "sp_tt", "picked": picked, "elo_key": str(picked.get("elo_key", ""))
		}
	return delivered


func _try_deliver_lk_mod(level_num: int) -> Dictionary:
	if _elo_filter_enabled:
		return _try_elo_lk_mod(level_num)
	var pools: Dictionary = LevelData.build_pools(_ctx.sz, _ctx.rank, _ctx.tier, false, true)
	var bucket: Array = pools.get("lk_mod", [])
	var progress: Dictionary = GameState.get_lkmod_progress(_ctx.sz, _ctx.rank)
	var index: int = int(progress.get("idx", 0))
	if index >= bucket.size():
		return {}
	var entry: Dictionary = BankData.materialize_entry(bucket[index] as Dictionary, true)
	entry["_bank_source"] = "lk_mod"
	entry["_bank_source_main"] = "lk_mod"
	entry["_bank_idx"] = index + 1
	entry["_bank_transform"] = 0
	entry["_bank_rank"] = _ctx.rank
	entry["_bank_tier"] = ""
	var delivered: Dictionary = _deliver_alt(entry, level_num)
	if not delivered.is_empty():
		_alt_pending_commit = {
			"source": "lk_mod", "sz": _ctx.sz, "rank": _ctx.rank, "new_idx": index + 1
		}
	return delivered


func _deliver_alt(entry: Dictionary, level_num: int, picked: Dictionary = {}) -> Dictionary:
	var scan: Dictionary = {}
	while true:
		var validation: Dictionary = FinalLevelValidator.validate(entry, level_num)
		if not bool(validation.valid):
			return {}
		var final_entry: Dictionary = validation.entry
		var dedup: Dictionary = PuzzleDeduplicator.inspect(final_entry, level_num)
		if not bool(dedup.duplicate):
			return _delivered(final_entry, str(dedup.puzzle_id), &"selected")
		var source: String = str(
			final_entry.get("_bank_source_main", final_entry.get("_bank_source", ""))
		)
		if source != "sp_tt":
			PuzzleDeduplicator.log_duplicate(
				dedup.previous, final_entry, level_num, dedup.puzzle_id
			)
			return _delivered(final_entry, str(dedup.puzzle_id), &"duplicate_fallback")
		var next_picked: Dictionary = _next_sp_tt_after_duplicate(picked, scan)
		if next_picked.is_empty():
			return {}
		picked.clear()
		picked.merge(next_picked)
		entry = picked["entry"]
	return {}


func _next_sp_tt_after_duplicate(picked: Dictionary, scan: Dictionary) -> Dictionary:
	if picked.is_empty():
		return {}
	if scan.is_empty():
		var progress: Dictionary = picked.get("new_progress", {})
		scan.merge(
			{
				"category": int(picked["category"]),
				"categories_left": SpTtProvider.CATEGORY_COUNT,
				"idx": int(progress.get("idx", 0)),
				"t_pos": int(progress.get("t_pos", 0)),
				"buckets": {}
			}
		)
	var buckets: Dictionary = scan["buckets"]
	while int(scan["categories_left"]) > 0:
		var category: int = int(scan["category"])
		if not buckets.has(category):
			buckets[category] = SpTtProvider.bucket_entries(category, _ctx.sz, _ctx.rank)
		var bucket: Array = buckets[category]
		var allowed: Array = SpTtProvider.allowed_transforms(category)
		while not bucket.is_empty() and int(scan["t_pos"]) < allowed.size():
			var transform_position: int = int(scan["t_pos"])
			var transform: int = int(allowed[transform_position])
			var source_key: String = (
				"sp_tt:%d:%d:%d:%d" % [category, _ctx.sz, _ctx.rank, transform_position]
			)
			var selected_ids: Array = (
				GameState.get_elo_v2_source_selected_ids(source_key) if _elo_filter_enabled else []
			)
			while int(scan["idx"]) < bucket.size():
				var index: int = int(scan["idx"])
				scan["idx"] = index + 1
				var original: Dictionary = bucket[index]
				if selected_ids.has(int(original.get("id", -1))):
					continue
				var candidate: Dictionary = BankData.materialize_entry(original, true)
				if transform > 0:
					candidate = SpTtProvider.apply_entry_transform(candidate, transform)
				candidate["_bank_source"] = "sp_tt%d" % category
				candidate["_bank_source_main"] = "sp_tt"
				candidate["_sp_tt_category"] = category
				candidate["_bank_idx"] = index + 1
				candidate["_bank_transform"] = transform
				candidate["_bank_rank"] = _ctx.rank
				candidate["_bank_tier"] = ""
				return {
					"entry": candidate,
					"category": category,
					"sz": _ctx.sz,
					"rank": _ctx.rank,
					"new_progress": {"idx": index + 1, "t_pos": transform_position},
					"elo_key": source_key if _elo_filter_enabled else ""
				}
			scan["idx"] = 0
			scan["t_pos"] = transform_position + 1
		scan["categories_left"] = int(scan["categories_left"]) - 1
		if int(scan["categories_left"]) <= 0:
			break
		var next_category: int = category % SpTtProvider.CATEGORY_COUNT + 1
		var next_progress: Dictionary = GameState.get_sp_tt_progress(
			next_category, _ctx.sz, _ctx.rank
		)
		scan["category"] = next_category
		scan["idx"] = int(next_progress.get("idx", 0))
		scan["t_pos"] = int(next_progress.get("t_pos", 0))
	return {}


func _commit_alt_delivery(entry: Dictionary) -> void:
	var source: String = str(_alt_pending_commit.get("source", ""))
	if str(entry.get("_bank_source_main", "")) != source:
		return
	var source_key: String = str(_alt_pending_commit.get("elo_key", ""))
	if not source_key.is_empty():
		GameState.record_elo_v2_source_selected_id(source_key, int(entry.get("id", -1)))
	if source == "sp_tt":
		SpTtProvider.commit(_alt_pending_commit.get("picked", {}), _ctx.level_num)
	elif source == "lk_mod":
		GameState.set_lkmod_progress(
			int(_alt_pending_commit.get("sz", 0)),
			int(_alt_pending_commit.get("rank", 0)),
			{"idx": int(_alt_pending_commit.get("new_idx", 0))}
		)
	else:
		return
	var count: int = GameState.get_sp_tt_lk_alt_block_count() + 1
	var next_source: String = source
	if count >= BLOCK_SIZE:
		next_source = "lk_mod" if source == "sp_tt" else "sp_tt"
		count = 0
	GameState.commit_sp_tt_lk_alt_delivery(_ctx.level_num, next_source, count)
