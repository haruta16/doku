## 普通关卡策略 normal_level_11504：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL11504Strategy
extends LevelSelectionStrategy

const COARSE_SINGLE_LIMIT: int = 2

const MAX_RANK_PROBE: int = 7

const RELAX_PHASE_COUNT: int = 7

const ISO_WINDOW_LEVELS: int = 30

const SMALL_SIZE_ISO_BYPASS: int = 8

const ISO_TIME_BUDGET_USEC: int = 2000000

const LARGE_CLUSTER_THRESHOLD_PCT: Dictionary = {
	8: {1: 55, 2: 63, 3: 63, 4: 65, 5: 63},
	9: {1: 48, 2: 58, 3: 55, 4: 55, 5: 55},
	10: {1: 30, 2: 50, 3: 40, 4: 30, 5: 30},
}

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

var _iso_filter_enabled: bool

var _iso_window: Array

var _iso_elapsed_usec: int = 0

var _iso_reject_count: int = 0


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_11504"


## 声明策略实现版本，和实验组标识一起描述当前选题规则。
func get_strategy_version() -> int:
	return 1


func select(request: LevelSelectRequest) -> Dictionary:
	var lv: int = request.level_num

	var _bypass_sz: int = SizeModifier.get_size(lv)
	if _bypass_sz > 0 and _bypass_sz <= SMALL_SIZE_ISO_BYPASS:
		_ctx = LevelSelectContext.new()
		_ctx.level_num = lv
		_iso_filter_enabled = false
		_iso_reject_count = 0
		_iso_elapsed_usec = 0
		var bypass_result: Dictionary = NLControlStrategy.new().select(request)
		if bypass_result.has("entry"):
			(bypass_result["entry"] as Dictionary)["_iso_check"] = "size_bypass"
		return bypass_result

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

	if SpecialProvider.SPECIAL_LEVELS.has(lv):
		var sp_entry: Dictionary = SpecialProvider.new().next_entry(_ctx)
		if not sp_entry.is_empty():
			return _deliver_special(sp_entry, lv)

	_is_main_path = lv >= 51
	_strict_rank = _ctx.is_hard
	_pools = LevelData.build_pools(_ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, _is_main_path)
	_cursor = BankCursor.create(lv, _ctx.sz, _ctx.rank, _ctx.tier, _pools)
	_coarse_single_limit = COARSE_SINGLE_LIMIT
	_dispersion_enabled = false
	_ab_filter_enabled = true
	_iso_filter_enabled = true
	_iso_window = _flatten_iso_window(GameState.get_recent_iso_signatures(ISO_WINDOW_LEVELS))
	_iso_elapsed_usec = 0
	_iso_reject_count = 0
	_outer_budget = _ctx.sz * _ctx.sz * 12
	_inner_budget = _cursor.budget()
	_dedup_retries = 0
	_relax_phase = 0
	_original_rank = _ctx.rank

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


func _large_cluster_min_size() -> int:
	return large_cluster_min_size(_ctx.sz, _ctx.rank)


static func large_cluster_min_size(sz: int, rank: int) -> int:
	var by_rank: Dictionary = LARGE_CLUSTER_THRESHOLD_PCT.get(sz, {})
	var pct: int = int(by_rank.get(rank, 0))
	if pct <= 0:
		return 0
	return int(sz * sz * pct / 100.0)


static func _flatten_iso_window(raw_window: Array) -> Array:
	var flat: Array = []
	for level_sigs: Array in raw_window:
		for cluster: Array in level_sigs:
			flat.append(cluster)
	return flat


func _apply_strategy(ctx: LevelSelectContext) -> void:
	StrategyModifier.apply_normal(ctx)


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

		if _iso_filter_enabled and _iso_elapsed_usec >= ISO_TIME_BUDGET_USEC:
			_iso_filter_enabled = false

		if not rejected and _iso_filter_enabled:
			var src: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
			if src == "sp":
				entry["_iso_check"] = "sp"
			else:
				var _iso_t0: int = Time.get_ticks_usec()
				var sig: Array = RegionClusterSignature.compute_signatures(
					entry.get("regionMap", []), _ctx.sz, _large_cluster_min_size()
				)
				entry["_iso_sig"] = sig
				var matched: bool = RegionClusterSignature.has_isomorphic_match(
					sig, _iso_window, RegionClusterSignature.ISO_TOLERANCE_CELLS
				)
				_iso_elapsed_usec += Time.get_ticks_usec() - _iso_t0
				entry["_iso_check"] = "matched" if matched else "clear"
				if matched:
					rejected = true
					_iso_reject_count += 1

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
	if _iso_filter_enabled:
		_iso_filter_enabled = false
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
	_cursor = BankCursor.create(_ctx.level_num, _ctx.sz, new_rank, new_tier, _pools)
	_outer_budget = _ctx.sz * _ctx.sz * 12


## 按当前上下文重新取得候选池，并把已有游标绑定到新池。
func _rebuild_pools() -> void:
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
static func _delivered(entry: Dictionary, puzzle_id: String, status: StringName) -> Dictionary:
	return {"entry": entry, "puzzle_id": puzzle_id, "status": status}


func on_delivery(entry: Dictionary) -> void:
	if not entry.has("_iso_check"):
		var src: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
		entry["_iso_check"] = "sp" if src == "sp" else "matched"
	LevelSelectionLog.log_isomorphic_dedup(
		_ctx.level_num, entry, _iso_filter_enabled, _iso_reject_count, _iso_elapsed_usec
	)
