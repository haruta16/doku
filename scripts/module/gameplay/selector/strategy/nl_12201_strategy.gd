## 普通关卡策略 normal_level_12201：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name NL12201Strategy
extends NL12100Strategy

enum PickStage { IN_BAND_FRESH, IN_BAND_RESTART, ABOVE_BAND }

const RATING_RANKS: Array[int] = [3, 4, 5]
const STYLE_WINDOW_LEVELS: int = 14
const STYLE_MAX_GROUPS: int = 2
const STYLE_SELECTION_BUDGET_USEC: int = 400000
const STYLE_SELECTION_MAX_COMPARISONS: int = 100

var _style_window: Array = []
var _style_budget: Dictionary = {}


## 提供本策略的稳定标识，供交付记录与选题追踪区分实验组。
func get_strategy_id() -> StringName:
	return &"normal_level_12201"


func _style_filter_active() -> bool:
	return true


func is_rating_level(lv: int) -> bool:
	if _ctx == null or _ctx.is_super_hard or _use_super_hard_pool:
		return false
	if not RATING_RANKS.has(_ctx.rank) or _ctx.tier == "H":
		return false
	return RatingBandTable.is_valid_band(RatingBandTable.band(lv, _ctx.rank))


func _try_ordered_delivery(lv: int) -> Dictionary:
	_style_window = []
	_style_budget = {}
	if not is_rating_level(lv):
		return {}
	var band: Vector2 = RatingBandTable.band(lv, _ctx.rank)
	var order: Array = RatingSortedPickProvider.get_sorted_order(
		_pools, _ctx.sz, _ctx.rank, _ctx.tier, _strict_rank, _is_main_path
	)
	var style_on: bool = _style_filter_active()
	if style_on:
		_style_window = GameState.get_recent_style_vectors(STYLE_WINDOW_LEVELS)
		_style_budget = {
			"deadline_usec": Time.get_ticks_usec() + STYLE_SELECTION_BUDGET_USEC,
			"comparisons_left": STYLE_SELECTION_MAX_COMPARISONS,
		}
	var delivered: Dictionary = _pick_with_fallback(order, band, lv, style_on)
	if delivered.is_empty() and style_on:
		delivered = _pick_with_fallback(order, band, lv, false)
	if delivered.is_empty():
		print(
			(
				"[LEVEL.rating_sorted] %s lv=%d rank=%d band=[%.2f,%.2f] 区间内外均无可交付题，回落游标"
				% [String(get_strategy_id()), lv, _ctx.rank, band.x, band.y]
			)
		)
	return delivered


func _pick_with_fallback(order: Array, band: Vector2, lv: int, style_on: bool) -> Dictionary:
	var delivered: Dictionary = _pick_in_band(order, band, lv, style_on, PickStage.IN_BAND_FRESH)
	if delivered.is_empty():
		delivered = _pick_in_band(order, band, lv, style_on, PickStage.IN_BAND_RESTART)
	if delivered.is_empty():
		delivered = _pick_in_band(order, band, lv, style_on, PickStage.ABOVE_BAND)
	return delivered


func _pick_in_band(
	order: Array, band: Vector2, lv: int, style_on: bool, stage: PickStage
) -> Dictionary:
	var accepted: Dictionary = {}
	var respect_selected: bool = stage != PickStage.IN_BAND_RESTART
	var is_selected: Callable = func(pid_h: String) -> bool:
		return respect_selected and GameState.is_rating_pid_selected(pid_h)
	var accept: Callable = func(candidate: Dictionary) -> bool:
		var verdict: Dictionary = _accept_candidate(candidate, lv, style_on)
		if verdict.is_empty():
			return false
		accepted["entry"] = verdict["entry"]
		accepted["puzzle_id"] = verdict["puzzle_id"]
		return true
	var picked: Dictionary = {}
	if stage == PickStage.ABOVE_BAND:
		picked = RatingSortedPickProvider.pick_above_band(
			order, band, _ctx.rank, _ctx.tier, _is_main_path, is_selected, accept
		)
	else:
		picked = RatingSortedPickProvider.pick_from_order(
			order, band, _ctx.rank, _ctx.tier, _is_main_path, is_selected, accept
		)
	if picked.is_empty() or accepted.is_empty():
		return {}
	var entry: Dictionary = accepted["entry"]
	entry["_rating_pick_stage"] = int(stage)
	print(
		(
			"[LEVEL.rating_sorted] %s lv=%d rank=%d band=[%.2f,%.2f] rating=%.2f src=%s style=%s stage=%s"
			% [
				String(get_strategy_id()),
				lv,
				_ctx.rank,
				band.x,
				band.y,
				float(entry.get("rating", 0.0)),
				str(entry.get("_bank_source", "")),
				style_on,
				PickStage.keys()[stage]
			]
		)
	)
	return _delivered(entry, str(accepted["puzzle_id"]), &"selected")


func _accept_candidate(candidate: Dictionary, lv: int, style_on: bool) -> Dictionary:
	if _exceeds_single_region_limit(candidate, COARSE_SINGLE_LIMIT):
		return {}
	var validation: Dictionary = FinalLevelValidator.validate(candidate, lv)
	if not bool(validation.valid):
		return {}
	var entry: Dictionary = validation.entry
	if _exceeds_single_region_limit(entry, _ab_single_limit()):
		return {}
	if (
		style_on
		and not LevelSimilarity.is_budget_exhausted(_style_budget)
		and LevelSimilarity.creates_excess_groups(
			entry, _style_window, STYLE_MAX_GROUPS, _style_budget
		)
	):
		return {}
	var dedup: Dictionary = PuzzleDeduplicator.inspect(entry, lv)
	if bool(dedup.duplicate):
		return {}
	return {"entry": entry, "puzzle_id": str(dedup.puzzle_id)}


func on_delivery(entry: Dictionary) -> void:
	super.on_delivery(entry)
	if bool(entry.get("_rating_sorted_pick", false)):
		GameState.mark_rating_pid_selected(str(entry.get("_pid_h", "")), false)
