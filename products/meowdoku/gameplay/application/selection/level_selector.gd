## 1.22 选题用例：完整策略只操作候选，成功结果携带计划，实际开局统一提交。
class_name LevelSelector
extends RefCounted

static var _last_trace: Dictionary = {}


static func capture_context(seed_value: int = 0, frozen_policy: Dictionary = {}) -> Dictionary:
	var policy: Dictionary = frozen_policy.duplicate(true)
	if policy.is_empty():
		policy = {"schema": 1, "normal_level": int(ABTestManager.normal_level.value()), "single_region_num": int(ABTestManager.single_region_num.value())}
	if not policy.has("content_policy"):
		var downloaded: Dictionary = ContentContext.read_json("doku/policy")
		policy["content_policy"] = downloaded.get("value", {}).duplicate(true) if downloaded.get("ok", false) else {}
	var scripts: Dictionary = {}
	for name: String in ["normal_level", "single_region_num", "normal_endgame_save", "color_challenge_func", "golden_fish_func", "golden_fish_precat", "golden_fish_timing"]:
		var config: RefCounted = ABTestManager.get(name)
		if config != null:
			scripts[name] = config.get_script()
			if not policy.has(name):
				policy[name] = config.value()
	return {
		"config_scripts": scripts, "policy": policy, "seed": seed_value,
		"today": Time.get_date_string_from_system(), "now_unix": int(Time.get_unix_time_from_system()),
		"daily_available": GameState.is_daily_first_easy_available(),
		"returnee_gap_days": ABTestManager.normal_endgame_save.returnee_gap_days(),
		"app_version": UniKitManager.get_version_name(),
		"assist_user": HasAssistUserTag.cached_value() == 1 or GameState.is_has_assist_confirmed(),
		"normal_level_config": ABTestManager.normal_level.get_script(),
		"single_region_config": ABTestManager.single_region_num.get_script(),
	}


static func make_runtime(candidate: Dictionary, context: Dictionary) -> DokuSelectionRuntime:
	return DokuSelectionRuntime.new(candidate, context)


static func create_entry_state(seed_value: int = 0) -> DokuSelectionState:
	return make_runtime(GameState.get_core_candidate(), capture_context(seed_value)).state


static func _resolve_strategy(value: int, runtime: DokuSelectionRuntime) -> LevelSelectionStrategy:
	# 每次请求独立实例；不把可变 _ctx/_cursor 留在跨局缓存中。
	var resolver := LevelSelectionStrategyResolver.new()
	var strategy: LevelSelectionStrategy = resolver.resolve_by_value(value)
	if strategy != null:
		strategy.bind_runtime(runtime)
	return strategy


static func prewarm_strategy() -> void:
	var runtime := make_runtime(GameState.get_core_candidate(), capture_context())
	_resolve_strategy(int(runtime.policy.get("normal_level", 0)), runtime)


static func prepare(level_num: int, rank_override: int = 0, pre_cat_pend: Dictionary = {}, ignore_special: bool = false, seed_value: int = 0, context: Dictionary = {}, existing_state: DokuSelectionState = null) -> Dictionary:
	if not GameState.is_storage_ready() or level_num < 1:
		return OperationResult.failure("invalid_selection_context")
	var before: Dictionary = existing_state.base_candidate() if existing_state != null else GameState.get_core_candidate()
	if context.is_empty():
		context = existing_state.selection_context() if existing_state != null else capture_context(seed_value)
	var runtime := make_runtime(before, context)
	if existing_state != null:
		runtime.state = existing_state
	var strategy: LevelSelectionStrategy = _resolve_strategy(int(runtime.policy.get("normal_level", 0)), runtime)
	if strategy == null:
		return OperationResult.failure("strategy_unavailable")
	var trace := LevelSelectionTrace.new(strategy.get_strategy_id(), strategy.get_strategy_version(), level_num)
	trace.add_event(&"resolver", {"normal_level_value": runtime.policy.normal_level, "resolved_strategy_id": str(strategy.get_strategy_id())})
	var request := LevelSelectRequest.new(level_num, trace, rank_override, pre_cat_pend.duplicate(true))
	request.ignore_special = ignore_special
	var configured: Dictionary = DokuLevelCatalog.resolve(level_num)
	if not configured.get("ok", false):
		return configured
	var catalog_entry: bool = bool(configured.get("found", false))
	var outcome: Dictionary
	if catalog_entry:
		var checked: Dictionary = FinalLevelValidator.validate(configured.entry, level_num)
		if not checked.get("valid", false):
			return OperationResult.failure("invalid_catalog_level", str(checked.get("reason", "")))
		outcome = {"entry": checked.entry, "puzzle_id": LevelData.compute_puzzle_id(int(checked.entry.size), checked.entry.regionMap)}
	else:
		outcome = strategy.select(request)
	if not outcome.has("entry"):
		trace.set_status(&"failed", {"reason": str(outcome.get("failed_reason", "exhausted"))})
		_last_trace = trace.to_dict()
		return OperationResult.failure("no_valid_level", str(outcome.get("failed_reason", "exhausted")))
	var entry: Dictionary = outcome.entry
	if not catalog_entry:
		strategy.on_delivery(entry)
	var retry: Dictionary = RetryPuzzleBuilder.build(level_num, entry)
	PaceRetryAugmenter.augment(retry, entry)
	var puzzle_id: String = str(outcome.get("puzzle_id", ""))
	entry["_puzzle_id"] = puzzle_id
	entry["_prefill_positions"] = retry.get("prefill_positions", [])
	entry["_strategy_steps"] = [int(retry.get("r1_steps", 0)), int(retry.get("r2_steps", 0)), int(retry.get("r3_steps", 0)), int(retry.get("r4_steps", 0)), int(retry.get("r5_steps", 0))]
	retry["selection_policy"] = runtime.policy.duplicate(true)
	runtime.state.finalize_selected_puzzle(level_num, {
		"puzzle_id": puzzle_id, "v": runtime.app_version, "nl": runtime.policy.normal_level,
		"src": entry.get("_bank_source_main", entry.get("_bank_source", "")),
		"iso_sig": entry.get("_iso_sig", []), "style_hist": entry.get("stepHist", []),
		"style_order_z": entry.get("stepOrderZ", []), "style_size": int(entry.get("size", 0)),
	}, retry)
	runtime.mark_delivered(str(entry.get("_rec_qid", "")))
	trace.set_status(outcome.get("status", &"selected"), {"puzzle_id": puzzle_id, "level_num": level_num})
	_last_trace = trace.to_dict()
	return build_plan(before, runtime, level_num, entry, retry, puzzle_id, seed_value)


static func build_plan(before: Dictionary, runtime: DokuSelectionRuntime, level_num: int, entry: Dictionary, retry: Dictionary, puzzle_id: String, seed_value: int = 0) -> Dictionary:
	if not ContentContext.content_error().is_empty():
		return OperationResult.failure("content_unavailable", str(ContentContext.content_error()))
	var after: Dictionary = runtime.export_candidate()
	var generation: int = ContentContext.generation()
	var identity: String = JSON.stringify({"level": level_num, "seed": seed_value, "before": before, "policy": runtime.policy, "puzzle_id": puzzle_id, "generation": generation})
	return {"ok": true, "entry": entry.duplicate(true), "size": BankData.get_region_map(entry).size(), "level": level_num,
		"puzzle_id": puzzle_id, "seed": seed_value, "selection_id": identity.sha256_text(),
		"expected_selection": before.duplicate(true), "next_selection": after,
		"read_selection_fields": runtime.state.observed_selection_fields(),
		"retry_params": retry.duplicate(true), "selection_policy": runtime.policy.duplicate(true),
		"content_generation": generation, "effects": runtime.export_effects(), "previous": {},
		"selection_context": {"today": runtime.today, "now_unix": runtime.now_unix, "seed": seed_value}}


## 兼容 1.22 页面取 entry；此函数不再交付落盘，调用者必须接收 _selection_plan。
static func select(level_num: int, rank_override: int = 0, pre_cat_pend: Dictionary = {}, ignore_special: bool = false, existing_state: DokuSelectionState = null) -> Dictionary:
	var plan: Dictionary = prepare(level_num, rank_override, pre_cat_pend, ignore_special, int(Time.get_ticks_usec()), {}, existing_state)
	if not plan.get("ok", false):
		return {}
	var entry: Dictionary = plan.entry.duplicate(true)
	entry["_selection_plan"] = plan
	return entry


static func stage_won_settlement(candidate: Dictionary, settlement: LevelSettlementContext, frozen_policy: Dictionary, context: Dictionary = {}) -> Dictionary:
	if frozen_policy.is_empty():
		return OperationResult.failure("missing_selection_policy")
	if context.is_empty():
		context = capture_context(0, frozen_policy)
	else:
		context = context.duplicate(true)
		context["policy"] = frozen_policy.duplicate(true)
	var runtime := make_runtime(candidate, context)
	var strategy: LevelSelectionStrategy = _resolve_strategy(int(frozen_policy.get("normal_level", 0)), runtime)
	if strategy == null:
		return OperationResult.failure("strategy_unavailable")
	strategy.on_level_won_settlement(settlement)
	return {"ok": true, "candidate": runtime.export_candidate(), "context": settlement, "effects": runtime.export_effects()}


static func apply_won_settlement(ctx: LevelSettlementContext) -> void:
	push_error("Use stage_won_settlement with the saved policy inside the product transaction")


static func elo_v2_performance_score(facts: Dictionary, frozen_policy: Dictionary = {}) -> float:
	var context: Dictionary = capture_context(0, frozen_policy)
	var runtime := make_runtime(GameState.get_core_candidate(), context)
	var strategy: LevelSelectionStrategy = _resolve_strategy(int(runtime.policy.get("normal_level", 0)), runtime)
	return strategy.elo_v2_performance_score(facts) if strategy != null else -1.0


static func is_hard_level(level_num: int, frozen_policy: Dictionary = {}, runtime: DokuSelectionRuntime = null) -> bool:
	if runtime == null:
		runtime = make_runtime(GameState.get_core_candidate(), capture_context(0, frozen_policy))
	var strategy: LevelSelectionStrategy = _resolve_strategy(int(runtime.policy.get("normal_level", 0)), runtime)
	return strategy.is_hard_level(level_num) if strategy != null else false


static func is_super_hard_level(level_num: int, frozen_policy: Dictionary = {}, runtime: DokuSelectionRuntime = null) -> bool:
	if runtime == null:
		runtime = make_runtime(GameState.get_core_candidate(), capture_context(0, frozen_policy))
	var strategy: LevelSelectionStrategy = _resolve_strategy(int(runtime.policy.get("normal_level", 0)), runtime)
	return strategy.is_super_hard_level(level_num) if strategy != null else false


static func max_strategy_at(level_num: int, frozen_policy: Dictionary = {}, runtime: DokuSelectionRuntime = null) -> int:
	if runtime == null:
		runtime = make_runtime(GameState.get_core_candidate(), capture_context(0, frozen_policy))
	var strategy: LevelSelectionStrategy = _resolve_strategy(int(runtime.policy.get("normal_level", 0)), runtime)
	return strategy.max_strategy_at(level_num) if strategy != null else 1


static func get_last_trace() -> Dictionary:
	return _last_trace.duplicate(true)


static func apply_won_in_runtime(ctx: LevelSettlementContext, runtime: DokuSelectionRuntime) -> Dictionary:
	var strategy: LevelSelectionStrategy = _resolve_strategy(int(runtime.policy.get("normal_level", 0)), runtime)
	if strategy == null:
		return OperationResult.failure("strategy_unavailable")
	strategy.on_level_won_settlement(ctx)
	return {"ok": true, "context": ctx}


## 入口后处理沿用同一候选；推荐队列的消费由选题 runtime 拥有，不被页面覆盖。
static func refresh_plan_state(plan: Dictionary, state: DokuSelectionState) -> Dictionary:
	if not plan.get("ok", false) or state == null:
		return OperationResult.failure("invalid_selection_plan")
	var after: Dictionary = state.export_candidate()
	var selected_features: Dictionary = plan.get("next_selection", {}).get("features", {})
	if selected_features.has("recommendation"):
		after.get("features", {})["recommendation"] = selected_features.recommendation.duplicate(true)
	plan["next_selection"] = after
	plan["read_selection_fields"] = state.observed_selection_fields()
	return plan


## 已有题面仍创建新交付计划；每日、重试、恢复和预览不执行普通关选题游标推进。
static func prepare_existing_entry(state: DokuSelectionState, level_num: int, entry: Dictionary) -> Dictionary:
	if state == null or entry.is_empty():
		return OperationResult.failure("invalid_selection_context")
	var context: Dictionary = state.selection_context()
	if entry.get("selection_policy") is Dictionary and not entry.selection_policy.is_empty():
		context["policy"] = entry.selection_policy.duplicate(true)
	var runtime := make_runtime(state.base_candidate(), context)
	runtime.state = state
	var pid: String = str(entry.get("puzzle_id", entry.get("_puzzle_id", "")))
	var plan: Dictionary = build_plan(state.base_candidate(), runtime, level_num, entry, {}, pid, int(context.get("seed", 0)))
	if not plan.get("ok", false):
		return plan
	plan["existing_entry"] = true
	plan["mode"] = "daily" if bool(entry.get("is_daily", false)) else ("preview" if level_num <= 0 else "main")
	plan["date"] = str(entry.get("date", ""))
	plan["is_restore"] = bool(entry.get("is_restore", false))
	plan["selection_id"] = (str(plan.selection_id) + "/existing/" + str(Time.get_ticks_usec())).sha256_text()
	return plan
