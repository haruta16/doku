## 选题总入口：解析实验策略、保存可回滚游标，成功后统一提交题目、重试参数和跟踪记录。
class_name LevelSelector
extends RefCounted

static var _resolver: RefCounted = null
static var _last_trace: Dictionary = {}


## 懒加载并缓存策略解析器，加载或实例化失败时报告错误。
static func _get_resolver() -> RefCounted:
	if _resolver != null:
		return _resolver
	var resolver_script: GDScript = (
		load("res://scripts/module/gameplay/selector/strategy/level_selection_strategy_resolver.gd")
		as GDScript
	)
	if resolver_script == null or not resolver_script.can_instantiate():
		push_error("LevelSelector: 无法加载策略解析器")
		return null
	_resolver = resolver_script.new() as RefCounted
	if _resolver == null:
		push_error("LevelSelector: 无法构造策略解析器")
	return _resolver


## 启动阶段提前解析当前实验策略，降低首次选题延迟。
static func prewarm_strategy() -> void:
	_resolve_strategy(ABTestManager.normal_level.value())


## 按实验值调用解析器并验证返回类型。
static func _resolve_strategy(normal_level_value: int) -> LevelSelectionStrategy:
	var resolver: RefCounted = _get_resolver()
	if resolver == null:
		return null

	var strategy: LevelSelectionStrategy = (
		resolver.call(&"resolve_by_value", normal_level_value) as LevelSelectionStrategy
	)
	if strategy == null:
		push_error("LevelSelector: 无法解析策略，normal_level=%d" % normal_level_value)
	return strategy


## 先保存游标快照再执行策略，无有效交付时回滚，有结果时进入统一提交。
static func select(
	level_num: int,
	rank_override: int = 0,
	pre_cat_pend: Dictionary = {},
	ignore_special: bool = false
) -> Dictionary:
	var progress_snapshot: Dictionary = GameState.get_level_selection_progress_snapshot()

	var nl_value: int = ABTestManager.normal_level.value()
	var strategy: LevelSelectionStrategy = _resolve_strategy(nl_value)
	if strategy == null:
		return _fail_and_restore(
			progress_snapshot, LevelSelectionTrace.new(&"", 1, level_num), "strategy_unavailable"
		)

	var trace := LevelSelectionTrace.new(
		strategy.get_strategy_id(), strategy.get_strategy_version(), level_num
	)
	(
		trace
		. add_event(
			&"resolver",
			{
				"normal_level_value": nl_value,
				"resolved_strategy_id": String(strategy.get_strategy_id()),
			}
		)
	)
	var request := LevelSelectRequest.new(level_num, trace, rank_override, pre_cat_pend)
	request.ignore_special = ignore_special

	var outcome: Dictionary = strategy.select(request)
	if not outcome.has("entry"):
		return _fail_and_restore(
			progress_snapshot, trace, str(outcome.get("failed_reason", "exhausted"))
		)

	return _finalize(
		level_num,
		outcome["entry"] as Dictionary,
		str(outcome.get("puzzle_id", "")),
		trace,
		outcome.get("status", &"selected"),
		strategy
	)


## 把通关上下文交当前选题策略处理，策略可回写难度与评分结果。
static func apply_won_settlement(ctx: LevelSettlementContext) -> void:
	var strategy: LevelSelectionStrategy = _resolve_strategy(ABTestManager.normal_level.value())
	if strategy == null:
		return
	strategy.on_level_won_settlement(ctx)


## 由当前策略解释 Elo 行为表现，策略不可用时返回 -1。
static func elo_v2_performance_score(facts: Dictionary) -> float:
	var strategy: LevelSelectionStrategy = _resolve_strategy(ABTestManager.normal_level.value())
	if strategy == null:
		return -1.0
	return strategy.elo_v2_performance_score(facts)


## 通知策略交付成功，构建重试参数并交 GameState 保存，随后记录推荐交付与完整轨迹。
static func _finalize(
	level_num: int,
	entry: Dictionary,
	puzzle_id: String,
	trace: LevelSelectionTrace,
	status: StringName,
	strategy: LevelSelectionStrategy
) -> Dictionary:
	strategy.on_delivery(entry)

	var retry_params: Dictionary = RetryPuzzleBuilder.build(level_num, entry)
	PaceRetryAugmenter.augment(retry_params, entry)
	var prefill_positions: Array = retry_params.get("prefill_positions", [])
	var strategy_steps: Array[int] = [
		int(retry_params.get("r1_steps", 0)),
		int(retry_params.get("r2_steps", 0)),
		int(retry_params.get("r3_steps", 0)),
		int(retry_params.get("r4_steps", 0)),
		int(retry_params.get("r5_steps", 0)),
	]
	entry["_puzzle_id"] = puzzle_id
	entry["_prefill_positions"] = prefill_positions
	entry["_strategy_steps"] = strategy_steps

	var recent_record: Dictionary = {
		"puzzle_id": puzzle_id,
		"v": UniKitManager.get_version_name(),
		"nl": ABTestManager.normal_level.value(),
		"src": entry.get("_bank_source_main", entry.get("_bank_source", "")),
		"iso_sig": entry.get("_iso_sig", []),
		"style_hist": entry.get("stepHist", []),
		"style_order_z": entry.get("stepOrderZ", []),
		"style_size": int(entry.get("size", 0)),
	}
	GameState.finalize_selected_puzzle(level_num, recent_record, retry_params)

	var rec_qid: String = str(entry.get("_rec_qid", ""))
	if not rec_qid.is_empty():
		LevelRecManager.mark_delivered(rec_qid)

	trace.set_status(status, {"puzzle_id": puzzle_id, "level_num": level_num})
	_last_trace = trace.to_dict()
	LevelSelectionLog.log_delivered(level_num, entry, puzzle_id)
	return entry


## 回滚三类选题游标，记录失败轨迹与原因，返回空题目。
static func _fail_and_restore(
	snapshot: Dictionary, trace: LevelSelectionTrace, reason: String
) -> Dictionary:
	GameState.restore_level_selection_progress(snapshot)
	trace.set_status(&"failed", {"reason": reason})
	_last_trace = trace.to_dict()
	push_error("LevelSelector: failed to deliver valid level, reason=%s" % reason)
	return {}


## 返回最近一次选题轨迹的深拷贝。
static func get_last_trace() -> Dictionary:
	return _last_trace.duplicate(true)


## 由当前实验策略判定困难关，解析失败时返回 false。
static func is_hard_level(level_num: int) -> bool:
	var nl_value: int = ABTestManager.normal_level.value()
	var strategy: LevelSelectionStrategy = _resolve_strategy(nl_value)
	if strategy == null:
		return false
	return strategy.is_hard_level(level_num)


## 由当前实验策略判定超难关，解析失败时返回 false。
static func is_super_hard_level(level_num: int) -> bool:
	var nl_value: int = ABTestManager.normal_level.value()
	var strategy: LevelSelectionStrategy = _resolve_strategy(nl_value)
	if strategy == null:
		return false
	return strategy.is_super_hard_level(level_num)


## 向已建立的策略解析器查询该关号允许的最高策略层级。
static func max_strategy_at(level_num: int) -> int:
	var nl_value: int = ABTestManager.normal_level.value()
	var strategy: LevelSelectionStrategy = _resolver.resolve_by_value(nl_value)
	return strategy.max_strategy_at(level_num)
