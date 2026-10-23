## 普通关卡策略 normal_level_12100：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12100Strategy
extends LevelSelectionStrategy

const COARSE_SINGLE_LIMIT: int = 2
const MAX_RANK_PROBE: int = 7
const RELAX_PHASE_COUNT: int = 7
const ALT_FIRST_TARGET_LEVEL: int = 11
const ALT_COOLDOWN_LEVELS: int = 3
const ALT_BLOCK_SIZE: int = 6

const FIXED_R1_UPPER_LEVEL: int = 5

var _ctx: LevelSelectContext
var _pools: Dictionary
var _cursor: BankCursor
var _strict_rank: bool
var _is_main_path: bool
var _use_super_hard_pool: bool = false
var _sh_anchor: int = 0
var _outer_budget: int
var _inner_budget: int
var _coarse_single_limit: int
var _dispersion_enabled: bool
var _ab_filter_enabled: bool
var _dedup_retries: int
var _relax_phase: int
var _original_rank: int
var _daily_first_easy_applied: bool = false
var _alt_pending_commit: Dictionary = {}


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12100"


## 声明策略实现版本，和实验组标识一起描述当前选题规则。
func get_strategy_version() -> int:
	return 1


func is_super_hard_level(level_num: int) -> bool:
	return SuperHardSchedule.is_super_hard(level_num)


func select(request: LevelSelectRequest) -> Dictionary:
	var lv: int = request.level_num
	_alt_pending_commit = {}
	_daily_first_easy_applied = false

	_ctx = LevelSelectContext.new()
	_ctx.level_num = lv
	_ctx.rank_override = request.rank_override

	_ctx.sz = SizeModifier.get_size(lv)
	if _ctx.sz == 0:
		return {"failed_reason": "no_size"}

	HardLevelModifier.apply(_ctx)
	var is_sh: bool = is_super_hard_level(lv)
	_sh_anchor = GameState.ensure_super_hard_anchor(lv) if is_sh else 0
	var sh_bank: Array = _super_hard_bank() if is_sh else []
	SuperHardModifier.apply_with_bank(_ctx, is_sh, _sh_anchor, sh_bank)
	_ctx.sz = _resolve_board_size(lv)

	if request.rank_override > 0:
		StrategyModifier.apply_override(_ctx)
	elif not _ctx.is_hard and not _ctx.is_super_hard:
		_apply_strategy(_ctx)

	var daily_first_easy_before: bool = GameState.is_daily_first_easy_available()
	DailyFirstEasyModifier.apply(_ctx)
	_daily_first_easy_applied = (
		daily_first_easy_before and not GameState.is_daily_first_easy_available()
	)
	TierFallbackModifier.apply(_ctx)

	if not request.ignore_special and _evaluate_alt_trigger(lv):
		var alt_delivered: Dictionary = _try_deliver_alt(lv)
		if not alt_delivered.is_empty():
			return alt_delivered

	if (
		not request.ignore_special
		and SpecialProvider.SPECIAL_LEVELS.has(lv)
		and not _ctx.is_super_hard
	):
		var sp_entry: Dictionary = SpecialProvider.new().next_entry(_ctx)
		if not sp_entry.is_empty():
			return _deliver_special(sp_entry, lv)

	if request.rank_override <= 0 and not _ctx.is_hard and not _ctx.is_super_hard:
		_apply_normal_level_override(_ctx)

	_is_main_path = lv >= 51
	_strict_rank = _ctx.is_hard or _ctx.is_super_hard
	_use_super_hard_pool = _ctx.is_super_hard
	_pools = _build_pools_for_ctx()
	_cursor = _create_cursor_for_ctx(lv)
	_coarse_single_limit = COARSE_SINGLE_LIMIT
	_dispersion_enabled = false
	_ab_filter_enabled = true
	_outer_budget = _ctx.sz * _ctx.sz * 12
	_inner_budget = _cursor.budget()
	_dedup_retries = 0
	_relax_phase = 0
	_original_rank = _ctx.rank

	var ordered: Dictionary = _try_ordered_delivery(lv)
	if not ordered.is_empty():
		return ordered

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


func _resolve_board_size(_level_num: int) -> int:
	return _ctx.sz


func _try_ordered_delivery(_lv: int) -> Dictionary:
	return {}


func _super_hard_bank() -> Array:
	return BankData.get_all_super_hard_levels()


func _apply_strategy(ctx: LevelSelectContext) -> void:
	var cur: int = GameState.get_current_strategy()
	if ctx.level_num >= 51 and cur < 2:
		GameState.set_current_strategy(2)
	var strategy: int = LevelData.resolve_strategy(
		ctx.level_num, GameState.get_current_strategy(), FIXED_R1_UPPER_LEVEL
	)
	strategy = mini(strategy, _segment_strategy_cap(ctx.level_num))

	if strategy >= 3:
		strategy = _pick_untagged(strategy)

	ctx.strategy = strategy
	ctx.rank = LevelData.strategy_to_rank(strategy)
	ctx.tier = LevelData.strategy_to_tier(strategy)


func _segment_strategy_cap(level_num: int) -> int:
	if level_num >= 51:
		return 4
	if level_num >= 21:
		return 3
	if level_num > FIXED_R1_UPPER_LEVEL:
		return 2
	return 1


static func _pick_untagged(strategy_after_cap: int) -> int:
	var weights: Array = (
		NL11502Strategy.WEIGHTS_R3 if strategy_after_cap == 3 else NL11502Strategy.WEIGHTS_R4
	)
	var picked: int = NL11502Strategy._pick_reasoning(strategy_after_cap)
	print(
		(
			"[LEVEL.diff_difficulty] 12100 pick strategy_after_cap=%d weights=%s drawn=%d buckets=%s idx=%d → picked=R%d"
			% [
				strategy_after_cap,
				str(weights),
				LevelSelectionRandom.get_last_drawn(),
				LevelSelectionRandom.format_weight_buckets(weights),
				picked - 2,
				picked
			]
		)
	)
	return picked


func _normal_level_override(_ctx_for_override: LevelSelectContext) -> Dictionary:
	return {}


func _apply_normal_level_override(ctx: LevelSelectContext) -> void:
	if _daily_first_easy_applied:
		return
	var override: Dictionary = _normal_level_override(ctx)
	var forced_strategy: int = int(override.get("strategy", 0))
	var forced_size: int = int(override.get("sz", 0))
	if forced_strategy <= 0 and forced_size <= 0:
		return
	if forced_strategy > 0:
		ctx.strategy = forced_strategy
	if forced_size > 0:
		ctx.sz = forced_size
	ctx.rank = LevelData.strategy_to_rank(ctx.strategy)
	ctx.tier = LevelData.strategy_to_tier(ctx.strategy)
	TierFallbackModifier.apply(ctx)


func _pass_time_verdict() -> int:
	var records: Array = GameState.get_normal_pass_time_records()
	var pass_secs: Array[int] = []
	var median_secs: Array[int] = []
	for record: Dictionary in records:
		pass_secs.append(int(record.get("sec", 0)))
		median_secs.append(
			LevelPassTimeMedian.median_sec(int(record.get("size", 0)), int(record.get("rank", 0)))
		)
	var verdict: int = PassTimeDda.evaluate(pass_secs, median_secs)
	print(
		(
			"[LEVEL.pass_time_dda] %s lv=%d verdict=%s secs=%s medians=%s"
			% [
				String(get_strategy_id()),
				_ctx.level_num,
				PassTimeDda.verdict_name(verdict),
				str(pass_secs),
				str(median_secs)
			]
		)
	)
	return verdict


## 给出去重重试次数上限，避免候选空间不足时无限选题。
func _dedup_retry_cap() -> int:
	return mini(_cursor.budget(), GameState.get_recent_puzzle_count() + 1)


func on_level_won_settlement(ctx: LevelSettlementContext) -> void:
	if ctx.is_daily_first_easy_level:
		return
	if ctx.strategy < ctx.strategy_before_all:
		ctx.pending_restore_strategy = ctx.strategy_before_all
		return
	if ctx.pending_restore_strategy <= 0:
		return
	if LevelSelector.is_hard_level(ctx.level_num) or LevelData.is_special_level(ctx.level_num):
		return
	ctx.strategy = maxi(ctx.strategy, ctx.pending_restore_strategy)
	ctx.pending_restore_strategy = 0


func _evaluate_alt_trigger(lv: int) -> bool:
	var last: int = GameState.get_sp_tt_lk_alt_last_replaced_level()
	var target: int = ALT_FIRST_TARGET_LEVEL if last == 0 else last + ALT_COOLDOWN_LEVELS
	if lv < target:
		return false
	if SpecialProvider.SPECIAL_LEVELS.has(lv):
		return false
	if GameState.is_current_level_daily_first_easy():
		return false
	if _ctx.is_hard or _ctx.is_super_hard:
		return false
	return true


func _try_deliver_alt(lv: int) -> Dictionary:
	var source: String = GameState.get_sp_tt_lk_alt_block_source()
	if source == "lk_mod":
		return _try_deliver_lk_mod(lv)
	return _try_deliver_sp_tt(lv)


func _try_deliver_sp_tt(lv: int) -> Dictionary:
	var picked: Dictionary = SpTtProvider.next_entry(_ctx.sz, _ctx.rank, _alt_skip_ids("sp_tt"))
	if picked.is_empty():
		return {}
	var entry: Dictionary = picked.get("entry", {})
	if entry.is_empty():
		return {}
	var delivered: Dictionary = _deliver_special(entry, lv, picked)
	if delivered.is_empty():
		return {}
	_alt_pending_commit = {"source": "sp_tt", "picked": picked}
	return delivered


func _try_deliver_lk_mod(lv: int) -> Dictionary:
	var lk_mod_bucket: Array = (
		LevelData.build_pools(_ctx.sz, _ctx.rank, _ctx.tier, false, true).get("lk_mod", [])
	)
	if lk_mod_bucket.is_empty():
		return {}
	var lk_prog: Dictionary = GameState.get_lkmod_progress(_ctx.sz, _ctx.rank)
	var idx: int = int(lk_prog.get("idx", 0))
	var skip_ids: Array = _alt_skip_ids("lk_mod")
	while (
		idx < lk_mod_bucket.size()
		and skip_ids.has(int((lk_mod_bucket[idx] as Dictionary).get("id", -1)))
	):
		idx += 1
	if idx >= lk_mod_bucket.size():
		return {}

	var entry: Dictionary = (lk_mod_bucket[idx] as Dictionary).duplicate(true)
	entry["_bank_source"] = "lk_mod"
	entry["_bank_source_main"] = "lk_mod"
	entry["_bank_idx"] = idx + 1
	entry["_bank_transform"] = 0
	entry["_bank_rank"] = _ctx.rank
	entry["_bank_tier"] = ""

	var delivered: Dictionary = _deliver_special(entry, lv)
	if delivered.is_empty():
		return {}
	_alt_pending_commit = {"source": "lk_mod", "sz": _ctx.sz, "rank": _ctx.rank, "new_idx": idx + 1}
	return delivered


func _alt_skip_ids(_source: String) -> Array:
	return []


func _commit_alt_delivery(entry: Dictionary) -> bool:
	if _alt_pending_commit.is_empty():
		return false
	var source: String = str(_alt_pending_commit.get("source", ""))
	if entry.get("_bank_source_main", "") != source:
		return false

	if source == "sp_tt":
		SpTtProvider.commit(_alt_pending_commit.get("picked", {}), _ctx.level_num)
	elif source == "lk_mod":
		GameState.set_lkmod_progress(
			int(_alt_pending_commit.get("sz", 0)),
			int(_alt_pending_commit.get("rank", 0)),
			{"idx": int(_alt_pending_commit.get("new_idx", 0))}
		)
	else:
		return false
	_advance_alt_block(source)
	return true


func _advance_alt_block(source: String) -> void:
	var new_count: int = GameState.get_sp_tt_lk_alt_block_count() + 1
	var new_source: String = source
	if new_count >= ALT_BLOCK_SIZE:
		new_source = "lk_mod" if source == "sp_tt" else "sp_tt"
		new_count = 0
	GameState.commit_sp_tt_lk_alt_delivery(_ctx.level_num, new_source, new_count)


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
	if src in ["lk_mod", "sp", "lk", "sp_tt"]:
		return false
	var region_map: Array = entry.get("regionMap", [])
	if region_map.size() != _ctx.sz:
		return false
	return _count_single_regions(region_map, _ctx.sz) > limit


## 按当前关卡和难度查询单格区域数量实验，返回这一轮筛选的上限。
func _ab_single_limit() -> int:
	return ABTestManager.single_region_num.single_limit_at(_ctx.level_num, _ctx.rank)


func _is_too_dispersed(entry: Dictionary) -> bool:
	var src: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
	if src in ["lk_mod", "sp", "lk", "sp_tt"]:
		return false
	var region_map: Array = entry.get("regionMap", [])
	if region_map.size() != _ctx.sz:
		return false
	return (
		QueendokuCore.compute_avg_region_bbox_fill_ratio(region_map)
		< QueendokuCore.DISPERSION_DENSITY_THRESHOLD
	)


## 统计只包含一个格子的区域；用于限制可直接确定猫位置的单格区域数量。
static func _count_single_regions(region_map: Array, sz: int) -> int:
	var cnt: Dictionary = {}
	for r: int in range(sz):
		for c: int in range(sz):
			var rid: int = int((region_map[r] as Array)[c])
			cnt[rid] = cnt.get(rid, 0) + 1
	var single: int = 0
	var counts: Array = cnt.values()
	for v: int in counts:
		if v == 1:
			single += 1
	return single


## 过滤 v113 批次题目；是否剔除由本实验组的 _should_drop_v113 决定。
func _filter_v113(regular: Array) -> Array:
	var kept: Array = []
	for entry: Dictionary in regular:
		if str(entry.get("batch", "")) == "v113":
			continue
		kept.append(entry)
	return kept


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
				_switch_pool(_ctx.rank, "")
			5:
				for r: int in range(_original_rank - 1, 0, -1):
					_switch_pool(r, "")
					var lower: Dictionary = _scan_after_switch()
					if not lower.is_empty():
						return lower
				continue
			6:
				var max_rank: int = _max_available_rank()
				for r: int in range(_original_rank + 1, max_rank + 1):
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
	_pools = _build_pools_for_ctx()
	_cursor = _create_cursor_for_ctx(_ctx.level_num)
	_outer_budget = _ctx.sz * _ctx.sz * 12


## 按当前上下文重新取得候选池，并把已有游标绑定到新池。
func _rebuild_pools() -> void:
	_pools = _build_pools_for_ctx()
	_cursor.rebind_pools(_pools)


func _build_pools_for_ctx() -> Dictionary:
	if _use_super_hard_pool:
		return LevelData.build_super_hard_pools_from(_super_hard_bank())
	var pools: Dictionary = LevelData.build_pools(
		_ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, false, _is_main_path
	)
	pools["regular"] = _filter_v113(pools["regular"])
	return pools


func _create_cursor_for_ctx(level_num: int) -> BankCursor:
	if _use_super_hard_pool:
		return SuperHardBankCursor.new(level_num, _sh_anchor, _pools)
	if _is_main_path:
		return DeliveryPacedCursor.new(_ctx.sz, _ctx.rank, _ctx.tier, level_num, _pools)
	return BankCursor.create(level_num, _ctx.sz, _ctx.rank, _ctx.tier, _pools)


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
		var probe: Dictionary = LevelData.build_pools(_ctx.sz, r, "", false, false, _is_main_path)
		if _pool_total(probe) > 0:
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


func _deliver_special(entry: Dictionary, lv: int, picked: Dictionary = {}) -> Dictionary:
	var scan: Dictionary = {}
	while true:
		var validation: Dictionary = FinalLevelValidator.validate(entry, lv)
		if not bool(validation.valid):
			return {}
		var final_entry: Dictionary = validation.entry
		var dedup: Dictionary = PuzzleDeduplicator.inspect(final_entry, lv)
		if not bool(dedup.duplicate):
			return _delivered(final_entry, str(dedup.puzzle_id), &"selected")
		var source: String = str(
			final_entry.get("_bank_source_main", final_entry.get("_bank_source", ""))
		)
		if source != "sp_tt":
			PuzzleDeduplicator.log_duplicate(dedup.previous, final_entry, lv, dedup.puzzle_id)
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
			var selected_ids: Array = _alt_skip_ids("sp_tt")
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
					"new_progress": {"idx": index + 1, "t_pos": transform_position}
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


## 把题目、去重标识与交付状态装进统一结果，交给选题入口完成后续提交。
static func _delivered(entry: Dictionary, puzzle_id: String, status: StringName) -> Dictionary:
	return {"entry": entry, "puzzle_id": puzzle_id, "status": status}


func on_delivery(entry: Dictionary) -> void:
	if _commit_alt_delivery(entry):
		return
	DeliveryPacedCursor.count_delivery(_ctx.level_num, _ctx.sz, _ctx.rank, _ctx.tier, entry)
