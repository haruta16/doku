## 普通关卡策略 normal_level_11966：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL11966Strategy
extends LevelSelectionStrategy

const COARSE_SINGLE_LIMIT: int = 2

const MAX_RANK_PROBE: int = 7

const RELAX_PHASE_COUNT: int = 7

const ENGAGE_MIN_LEVEL: int = 6

const TRIGGER_LEVEL_DIGIT: int = 3

const STOCK_THRESHOLD: int = 10

const DAILY_USAGE_CAP: int = 4

const TARGET_SINGLE_COUNT: int = 0

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
var _dedup_retries: int
var _relax_phase: int
var _original_rank: int

var _g4_active: bool

var _g4_force_bypass_exempt: bool

var _exact_filter_enabled: bool

var _supp_skip: int

var _supp_pending_commit: Dictionary


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_11966"


## 声明策略实现版本，和实验组标识一起描述当前选题规则。
func get_strategy_version() -> int:
	return 1


func select(request: LevelSelectRequest) -> Dictionary:
	var lv: int = request.level_num

	_ctx = LevelSelectContext.new()
	_ctx.level_num = lv
	_ctx.rank_override = request.rank_override
	_g4_active = false
	_g4_force_bypass_exempt = false

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

	if SpecialProvider.SPECIAL_LEVELS.has(lv) and not _g4_force_bypass_exempt:
		var sp_entry: Dictionary = SpecialProvider.new().next_entry(_ctx)
		if not sp_entry.is_empty():
			return _deliver_special(sp_entry, lv)

	_is_main_path = lv >= 51
	_strict_rank = _ctx.is_hard
	_exact_filter_enabled = _g4_active
	if _exact_filter_enabled:
		_pools = LevelData.build_pools(
			_ctx.sz,
			_ctx.rank,
			_ctx.tier,
			_strict_rank,
			_is_main_path,
			_is_main_path,
			_exact_filter_enabled
		)
	else:
		_pools = LevelData.build_pools(_ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, _is_main_path)
	_cursor = BankCursor.create(lv, _ctx.sz, _ctx.rank, _ctx.tier, _pools)
	_coarse_single_limit = COARSE_SINGLE_LIMIT
	_dispersion_enabled = false
	_ab_filter_enabled = true
	_outer_budget = _ctx.sz * _ctx.sz * 12
	_inner_budget = _cursor.budget()
	_dedup_retries = 0
	_relax_phase = 0
	_original_rank = _ctx.rank
	_supp_skip = 0
	_supp_pending_commit = {}

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

		if (
			_ab_filter_enabled
			and not _g4_active
			and _exceeds_single_region_limit(entry, _ab_single_limit())
		):
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
		strategy = NL11502Strategy._pick_untagged(strategy)

	if GameState.consume_g4_defer_pending():
		var rmax: int = _max_strategy_for_level(ctx.level_num)
		if _pressure_target_collides(ctx.level_num, ctx.sz, rmax):
			_g4_force_bypass_exempt = true
			strategy = rmax
			_g4_active = true
			print(
				(
					"[LEVEL.tool_hoard_v3] 组11966 lv=%d 顺延目标关仍命中特殊关/lk_mod碰撞,不再二次顺延,强制绕过该来源,Rmax=%d"
					% [ctx.level_num, strategy]
				)
			)
		else:
			strategy = rmax
			_g4_active = true
			print(
				(
					"[LEVEL.tool_hoard_v3] 组11966 lv=%d 顺延自上一关(xx3)命中dfld或碰撞,无条件强制Rmax=%d"
					% [ctx.level_num, strategy]
				)
			)
	elif (
		ctx.level_num >= ENGAGE_MIN_LEVEL
		and ctx.level_num % 10 == TRIGGER_LEVEL_DIGIT
		and _pressure_condition_met()
	):
		var dfld_will_fire: bool = GameState.is_daily_first_easy_available() and strategy > 1
		var rmax: int = _max_strategy_for_level(ctx.level_num)
		if dfld_will_fire:
			GameState.set_g4_defer_pending(true)
			print("[LEVEL.tool_hoard_v3] 组11966 lv=%d 命中压力关条件但本关dfld也会生效,顺延到下一关" % ctx.level_num)
		elif _pressure_target_collides(ctx.level_num, ctx.sz, rmax):
			strategy = rmax
			GameState.set_g4_defer_pending(true)
			print(
				(
					"[LEVEL.tool_hoard_v3] 组11966 lv=%d 命中压力关条件但候选来自特殊关/lk_mod结构性碰撞,本关按Rmax=%d正常交付(不标记压力关),压力关顺延到下一关"
					% [ctx.level_num, strategy]
				)
			)
		else:
			strategy = rmax
			_g4_active = true
			print(
				"[LEVEL.tool_hoard_v3] 组11966 lv=%d 命中压力关条件,强制Rmax=%d" % [ctx.level_num, strategy]
			)

	ctx.strategy = strategy
	ctx.rank = LevelData.strategy_to_rank(strategy)
	ctx.tier = LevelData.strategy_to_tier(strategy)


static func _pressure_condition_met() -> bool:
	var any_stock_high: bool = false
	for kind: String in GameState.CLOUD_TOOL_KINDS:
		if GameState.get_tool_count(kind) > STOCK_THRESHOLD:
			any_stock_high = true
			break
	if not any_stock_high:
		return false
	return (
		GameState.get_today_tool_consumed() + GameState.get_today_revive_count() < DAILY_USAGE_CAP
	)


static func _max_strategy_for_level(level_num: int) -> int:
	if level_num >= 201:
		return 6
	elif level_num >= 101:
		return 5
	elif level_num >= 51:
		return 4
	elif level_num >= 21:
		return 3
	else:
		return 2


static func _pressure_target_collides(level_num: int, sz: int, strategy_forced: int) -> bool:
	if SpecialProvider.SPECIAL_LEVELS.has(level_num):
		print("[LEVEL.tool_hoard_v3] 组11966 lv=%d 碰撞判定=特殊关(SP/LK固定题)" % level_num)
		return true
	if level_num < 51:
		return false
	var rank: int = LevelData.strategy_to_rank(strategy_forced)
	var tier: String = LevelData.strategy_to_tier(strategy_forced)
	var since_lk: int = int(GameState.get_main_progress(sz, rank, tier).get("since_lk", 0))
	var lk_idx: int = int(GameState.get_lkmod_progress(sz, rank).get("idx", 0))
	var lk_mod_pool_size: int = (
		LevelData.build_pools(sz, rank, tier, false, true).get("lk_mod", []).size()
	)
	var collides: bool = since_lk >= 4 and lk_idx < lk_mod_pool_size
	print(
		(
			"[LEVEL.tool_hoard_v3] 组11966 lv=%d 碰撞判定 sz=%d rank=%d tier=%s since_lk=%d lk_idx=%d lk_mod池大小=%d → %s"
			% [
				level_num,
				sz,
				rank,
				tier,
				since_lk,
				lk_idx,
				lk_mod_pool_size,
				"碰撞" if collides else "不碰撞"
			]
		)
	)
	return collides


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
		var entry: Dictionary = LevelData.pick_at(_pools, _scan_pos(), _ctx.rank, _ctx.tier)
		if entry.is_empty():
			return {}

		var rejected: bool = false

		if _exceeds_single_region_limit(entry, _coarse_single_limit):
			rejected = true

		if not rejected and _dispersion_enabled and _is_too_dispersed(entry):
			rejected = true

		if not rejected and _exact_filter_enabled and not _matches_exact_single_count(entry):
			rejected = true

		if not rejected:
			return entry

		if _inner_budget <= 1:
			if _exact_filter_enabled and not _matches_exact_single_count(entry):
				var supp: Dictionary = SingleRegionSuppProvider.next_entry(
					_ctx.sz, _ctx.rank, TARGET_SINGLE_COUNT, _supp_skip
				)
				if not supp.is_empty():
					_supp_skip += 1
					_supp_pending_commit = supp
					return supp.get("entry", {})
			return entry

		_cursor.advance(entry)
		_inner_budget -= 1
	return {}


func _scan_pos() -> Dictionary:
	var pos: Dictionary = _cursor.pos()
	if _g4_force_bypass_exempt:
		pos = pos.duplicate()
		pos["since_lk"] = 0
	return pos


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


func _matches_exact_single_count(entry: Dictionary) -> bool:
	var src: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
	if src in ["lk_mod", "sp", "lk"]:
		return true
	var rm: Array = entry.get("regionMap", [])
	if rm.size() != _ctx.sz:
		return false
	return _count_single_regions(rm, _ctx.sz) == TARGET_SINGLE_COUNT


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


## 按本组顺序放宽筛选条件或切换题库，直到取得候选或耗尽兜底阶段。
func _relax_next() -> Dictionary:
	if _exact_filter_enabled:
		_exact_filter_enabled = false
		_outer_budget = _ctx.sz * _ctx.sz * 12
		_inner_budget = _cursor.budget()
		var entry: Dictionary = _scan_current_pool()
		if not entry.is_empty():
			_cursor.advance(entry)
			return entry

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
				_switch_pool(_ctx.rank, "")
			5:
				for r: int in range(_original_rank - 1, 0, -1):
					_switch_pool(r, "")
					var lower: Dictionary = _scan_after_switch()
					if not lower.is_empty():
						return lower
				continue
			6:
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
	_cursor = BankCursor.create(_ctx.level_num, _ctx.sz, _ctx.rank, _ctx.tier, _pools)
	_outer_budget = _ctx.sz * _ctx.sz * 12


## 按当前上下文重新取得候选池，并把已有游标绑定到新池。
func _rebuild_pools() -> void:
	if _exact_filter_enabled:
		_pools = LevelData.build_pools(
			_ctx.sz,
			_ctx.rank,
			_ctx.tier,
			_strict_rank,
			_is_main_path,
			_is_main_path,
			_exact_filter_enabled
		)
	else:
		_pools = LevelData.build_pools(_ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, _is_main_path)
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
		return _delivered(final_entry, str(dedup.puzzle_id), &"duplicate_fallback")
	return _delivered(final_entry, str(dedup.puzzle_id), &"selected")


## 把题目、去重标识与交付状态装进统一结果，交给选题入口完成后续提交。
func _delivered(entry: Dictionary, puzzle_id: String, status: StringName) -> Dictionary:
	return {"entry": entry, "puzzle_id": puzzle_id, "status": status}


func on_delivery(entry: Dictionary) -> void:
	if _g4_active:
		GameState.mark_g4_pressure_level(_ctx.level_num)
	if (
		not _supp_pending_commit.is_empty()
		and entry.get("_bank_source_main", "") == "single_region_supp"
	):
		SingleRegionSuppProvider.commit(_supp_pending_commit)
