## 普通关卡策略 normal_level_11919：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL11919Strategy
extends LevelSelectionStrategy

const COARSE_SINGLE_LIMIT: int = 2

const MAX_RANK_PROBE: int = 7

const RELAX_PHASE_COUNT: int = 9

const ELO_RANKS: Array = [3, 4, 5]

const ELO_INITIAL_RATING: float = 400.0

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


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_11919"


## 声明策略实现版本，和实验组标识一起描述当前选题规则。
func get_strategy_version() -> int:
	return 1


func select(request: LevelSelectRequest) -> Dictionary:
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

	if request.rank_override > 0:
		StrategyModifier.apply_override(_ctx)
	elif not _ctx.is_hard:
		_apply_strategy(_ctx)

	DailyFirstEasyModifier.apply(_ctx)
	TierFallbackModifier.apply(_ctx)

	_elo_filter_enabled = _ctx.rank in ELO_RANKS
	if _elo_filter_enabled:
		var player_rating: float = GameState.get_elo_rating(_ctx.rank)
		var band: Vector2 = EloRatingMath.fixed_target_band()
		_elo_bounds = EloRatingMath.puzzle_rating_bounds(player_rating, band)
		_elo_target = EloRatingMath.random_target_rating(player_rating, band)

	_style_filter_enabled = _elo_filter_enabled
	_style_window = (
		GameState.get_recent_style_vectors(STYLE_WINDOW_LEVELS) if _style_filter_enabled else []
	)
	_style_reject_count = 0

	if SpecialProvider.SPECIAL_LEVELS.has(lv):
		var sp_entry: Dictionary = SpecialProvider.new().next_entry(_ctx)
		if not sp_entry.is_empty():
			return _deliver_special(sp_entry, lv)

	_is_main_path = lv >= 51
	_strict_rank = _ctx.is_hard
	_pools = LevelData.build_pools(_ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, _is_main_path)
	_pools["regular"] = _filter_v113(_pools["regular"])
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
		var sorted_entry: Dictionary = _try_sorted_pick(lv)
		if not sorted_entry.is_empty():
			return sorted_entry
		var aux_entry: Dictionary = _try_elo_aux_delivery()
		if not aux_entry.is_empty():
			return aux_entry
		var closest_entry: Dictionary = _try_closest_elo_delivery()
		if not closest_entry.is_empty():
			return closest_entry

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

		if _elo_filter_enabled and _outside_elo_band(entry):
			_outer_budget -= 1
			continue

		if (
			_style_filter_enabled
			and LevelSimilarity.creates_excess_groups(
				entry, _style_window, STYLE_MAX_GROUPS, _style_budget
			)
		):
			_style_reject_count += 1
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
	_ensure_elo_initialized()

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
	for r: int in ELO_RANKS:
		GameState.init_elo_rating(r, ELO_INITIAL_RATING)


func _create_cursor(level_num: int) -> BankCursor:
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


func _outside_elo_band(entry: Dictionary) -> bool:
	if not entry.has("eloRating"):
		return false
	var v: float = float(entry["eloRating"])
	return v < _elo_bounds.x or v > _elo_bounds.y


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
static func _count_single_regions(rm: Array, sz: int) -> int:
	var cnt: Dictionary = {}
	for r: int in range(sz):
		for c: int in range(sz):
			var rid: int = int((rm[r] as Array)[c])
			cnt[rid] = cnt.get(rid, 0) + 1
	var single: int = 0
	for v: int in cnt.values():
		if v == 1:
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


func _try_sorted_pick(lv: int) -> Dictionary:
	return _pick_from_elo_order(_main_elo_order(), lv, false, true)


func _main_source_mode() -> String:
	var pos: Dictionary = _cursor.pos()
	return (
		"lk_mod"
		if (
			_is_main_path
			and int(pos.get("since_lk", 0)) >= 4
			and int(pos.get("lk_idx", 0)) < (_pools.get("lk_mod", []) as Array).size()
		)
		else "main"
	)


func _main_elo_order() -> Array:
	return EloSortedPickProvider.get_sorted_order(
		_pools, _ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, _is_main_path, _main_source_mode()
	)


func _pick_from_elo_order(
	order: Array, lv: int, allow_nearest: bool, respect_selected: bool
) -> Dictionary:
	var validate: Callable = func(candidate: Dictionary) -> bool:
		var validation: Dictionary = FinalLevelValidator.validate(candidate, lv)
		if not bool(validation.valid):
			return false
		if (
			_style_filter_enabled
			and not LevelSimilarity.is_budget_exhausted(_style_budget)
			and LevelSimilarity.creates_excess_groups(
				validation.entry, _style_window, STYLE_MAX_GROUPS, _style_budget
			)
		):
			_style_reject_count += 1
			return false
		var dedup: Dictionary = PuzzleDeduplicator.inspect(validation.entry, lv)
		if bool(dedup.duplicate) and _dedup_retries < _dedup_retry_cap():
			_dedup_retries += 1
			return false
		return true
	var candidate: Dictionary = EloSortedPickProvider.pick_from_order(
		order,
		_ctx.rank,
		_ctx.tier,
		_elo_target,
		_elo_bounds,
		validate,
		func(pid: String) -> bool: return respect_selected and GameState.is_elo_pid_selected(pid),
		func(pid: String) -> void: GameState.mark_elo_pid_selected(pid),
		allow_nearest
	)
	if candidate.is_empty():
		return {}
	var final_entry: Dictionary = FinalLevelValidator.validate(candidate, lv).entry
	var dedup: Dictionary = PuzzleDeduplicator.inspect(final_entry, lv)
	var status: StringName = &"selected"
	if bool(dedup.duplicate):
		PuzzleDeduplicator.log_duplicate(dedup.previous, final_entry, lv, dedup.puzzle_id)
		status = &"duplicate_fallback"
	EloAuxProvider.commit_entry(final_entry, _ctx.sz, _ctx.rank)
	print(
		(
			"[LEVEL.elo_sorted] 组11919 lv=%d rank=%d 目标分=%.1f 实际分=%.1f"
			% [lv, _ctx.rank, _elo_target, float(final_entry.get("eloRating", 0.0))]
		)
	)
	return _delivered(final_entry, str(dedup.puzzle_id), status)


func _try_elo_aux_delivery() -> Dictionary:
	if not _elo_aux_eligible():
		return {}
	for order: Array in [
		EloAuxProvider.get_single_region_order(_ctx.sz, _ctx.rank),
		EloAuxProvider.get_climax_order(_ctx.sz, _ctx.rank),
	]:
		var delivered: Dictionary = _pick_from_elo_order(order, _ctx.level_num, false, true)
		if not delivered.is_empty():
			return delivered
	return {}


func _elo_aux_eligible() -> bool:
	return _elo_filter_enabled and _elo_bounds.x > 0.0 and _main_source_mode() == "main"


func _try_closest_elo_delivery() -> Dictionary:
	var orders: Array = [_main_elo_order()]
	if _main_source_mode() == "main":
		orders.append(EloAuxProvider.get_single_region_order(_ctx.sz, _ctx.rank))
		orders.append(EloAuxProvider.get_climax_order(_ctx.sz, _ctx.rank))
	var order: Array = EloAuxProvider.combined_order(orders)
	return _pick_from_elo_order(order, _ctx.level_num, true, true)


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
	_rebuild_pools()
	_cursor = _create_cursor(_ctx.level_num)
	_outer_budget = _ctx.sz * _ctx.sz * 12


## 按当前上下文重新取得候选池，并把已有游标绑定到新池。
func _rebuild_pools() -> void:
	_pools = LevelData.build_pools(_ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, _is_main_path)
	_pools["regular"] = _filter_v113(_pools["regular"])
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
		var p: Dictionary = LevelData.build_pools(_ctx.sz, r, "", false, _is_main_path)
		if _pool_total(p) > 0:
			top = r
	return top


## 合计各候选题库的题目数量，供探测当前难度是否还有可用题目。
static func _pool_total(p: Dictionary) -> int:
	return (
		(p.get("regular", []) as Array).size()
		+ (p.get("lkstyle", []) as Array).size()
		+ (p.get("gc", []) as Array).size()
		+ (p.get("lk_mod", []) as Array).size()
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
	if not entry.has("eloRating"):
		return entry
	var r: int = int(entry.get("r", 0))
	if not (r in ELO_RANKS):
		return entry
	var puzzle_rating: float = float(entry["eloRating"])
	var player_rating: float = GameState.get_elo_rating(r)
	entry["_elo_e"] = EloRatingMath.e_from_ratings(puzzle_rating, player_rating)
	entry["_elo_k"] = EloRatingMath.k_for_games(GameState.get_elo_games(r))
	entry["_elo_player_rating"] = player_rating
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
	DeliveryPacedCursor.count_delivery(_ctx.level_num, _ctx.sz, _ctx.rank, _ctx.tier, entry)
	var r: int = int(entry.get("r", 0))
	if bool(entry.get("is_elo_delivery", false)) and r in ELO_RANKS and entry.has("eloRating"):
		GameState.set_elo_active_delivery(r, float(entry["eloRating"]))
		_log_pre(r, float(entry["eloRating"]))
	else:
		GameState.set_elo_active_delivery(0, 0.0)


func _log_pre(rank: int, puzzle_rating: float) -> void:
	var player_rating: float = GameState.get_elo_rating(rank)
	var k: float = EloRatingMath.k_for_games(GameState.get_elo_games(rank))
	print(
		(
			"[Level.ELO] PRE lv=%d rank=%d K=%.1f Emin=%.2f Emax=%.2f 玩家eloRating=%.2f 题目eloRating=%.2f 取题时跳过了%d个玩法同构关卡"
			% [
				_ctx.level_num,
				rank,
				k,
				_elo_bounds.x,
				_elo_bounds.y,
				player_rating,
				puzzle_rating,
				_style_reject_count
			]
		)
	)


func on_level_won_settlement(ctx: LevelSettlementContext) -> void:
	var rank: int = GameState.get_elo_active_rank()
	if not (rank in ELO_RANKS):
		return
	var puzzle_rating: float = GameState.get_elo_active_puzzle_rating()
	var player_rating: float = GameState.get_elo_rating(rank)
	var k: float = EloRatingMath.k_for_games(GameState.get_elo_games(rank))
	var e: float = EloRatingMath.e_from_ratings(puzzle_rating, player_rating)
	var used_tool: bool = ctx.tool_or_revive_used
	var fish_consumed: int = GameState.get_elo_fish_consumed()
	var s: float = EloRatingMath.s_from_fish(fish_consumed, used_tool)
	var new_rating: float = EloRatingMath.new_player_rating(player_rating, k, s, e)
	var bounds: Vector2 = EloRatingMath.puzzle_rating_bounds(
		player_rating, EloRatingMath.fixed_target_band()
	)
	print(
		(
			(
				"[Level.ELO] POST lv=%d rank=%d K=%.1f S=%.2f(总共消耗%d个小鱼干，使用了%d次道具) "
				+ "E=%.4f Emin=%.2f Emax=%.2f K(S-E)=%.2f 玩家eloRating(迭代后)=%.2f 题目eloRating=%.2f"
			)
			% [
				ctx.level_num,
				rank,
				k,
				s,
				fish_consumed,
				int(used_tool),
				e,
				bounds.x,
				bounds.y,
				k * (s - e),
				new_rating,
				puzzle_rating
			]
		)
	)

	GameState.commit_elo_settlement(rank, new_rating, GameState.get_elo_band(rank))
