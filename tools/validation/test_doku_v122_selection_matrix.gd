## tools/run_validation.py 隔离工程：所有实际注册的 NL 值均运行同一候选边界。
extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TEST_FAILED: " + message)

func _run() -> void:
	var state: Node = root.get_node("GameState")
	var selector: GDScript = load("res://products/meowdoku/gameplay/application/selection/level_selector.gd")
	var resolver: GDScript = load("res://products/meowdoku/gameplay/application/selection/strategy/level_selection_strategy_resolver.gd")
	var runtime_script: GDScript = load("res://products/meowdoku/gameplay/application/selection/selection_runtime.gd")
	var trace_script: GDScript = load("res://products/meowdoku/gameplay/application/selection/level_selection_trace.gd")
	var request_script: GDScript = load("res://products/meowdoku/gameplay/application/selection/level_select_request.gd")
	var validator: GDScript = load("res://products/meowdoku/gameplay/application/selection/delivery/final_level_validator.gd")
	var before: Dictionary = state.get_core_candidate()
	var revision: int = state.get_core_store().revision()
	var context: Dictionary = selector.capture_context(8122)
	context["daily_available"] = false
	var values: Array = resolver._VALUE_TO_ID.keys()
	values.sort()
	for value: int in values:
		var candidate: Dictionary = before.duplicate(true)
		candidate.profile["current_level"] = 51
		candidate.profile["current_strategy"] = 3
		candidate.profile["recent_puzzles"] = []
		var config: Dictionary = context.duplicate(true)
		config.policy["normal_level"] = value
		var runtime: RefCounted = runtime_script.new(candidate, config)
		var strategy: RefCounted = resolver.new().resolve_by_value(value)
		_check(strategy != null, "NL%d has implementation" % value)
		if strategy == null: continue
		strategy.bind_runtime(runtime)
		var trace: RefCounted = trace_script.new(strategy.get_strategy_id(), strategy.get_strategy_version(), 51)
		var request: RefCounted = request_script.new(51, trace)
		var outcome: Dictionary = strategy.select(request)
		_check(outcome.has("entry"), "NL%d has playable fallback" % value)
		if outcome.has("entry"):
			var checked: Dictionary = validator.validate(outcome.entry, 51)
			_check(checked.get("valid", false), "NL%d delivers a valid puzzle" % value)
			strategy.on_delivery(outcome.entry)
			var after: Dictionary = runtime.export_candidate()
			_check(after.get("profile") is Dictionary and after.get("round_runtime") is Dictionary, "NL%d exports full candidate" % value)
		_check(state.get_core_candidate() == before and state.get_core_store().revision() == revision, "NL%d never writes live state" % value)
	_test_frozen_content_branches(state, selector, resolver, runtime_script, context)
	_test_special_table_branches(state, resolver, runtime_script, context)
	print("PASS: 1.22 selection matrix values=%d checks=%d failures=%d" % [values.size(), checks, failures])
	quit(1 if failures else 0)


func _test_frozen_content_branches(state: Node, selector: GDScript, resolver: GDScript, runtime_script: GDScript, base: Dictionary) -> void:
	var before: Dictionary = state.get_core_candidate()
	for value: int in [12100, 12207, 12208]:
		for is_special: bool in [true, false]:
			var context: Dictionary = base.duplicate(true)
			context.policy.normal_level = value
			context.policy.content_policy = {"special_levels": {"1": {"source": "sp", "index": 1}} if is_special else {}}
			var runtime: RefCounted = runtime_script.new(before, context)
			var strategy: RefCounted = resolver.new().resolve_by_value(value)
			strategy.bind_runtime(runtime)
			var settled: RefCounted = LevelSettlementContext.new()
			settled.level_num = 1
			settled.strategy = 2
			settled.strategy_before_all = 2
			settled.pending_restore_strategy = 4
			if value == 12100:
				strategy.on_level_won_settlement(settled)
			else:
				strategy._apply_fusion_settlement(settled)
			_check(settled.strategy == (2 if is_special else 4) and settled.pending_restore_strategy == (4 if is_special else 0), "NL%d fusion settlement obeys frozen special level override=%s" % [value, str(is_special)])
	var context: Dictionary = base.duplicate(true)
	context.policy.normal_level = 12002
	context.policy.content_policy = {"size_cycles": {"12002": [{"from": 1, "sizes": [5]}]}}
	var runtime: RefCounted = runtime_script.new(before, context)
	var strategy: RefCounted = resolver.new().resolve_by_value(12002)
	strategy.bind_runtime(runtime)
	var request: RefCounted = LevelSelectRequest.new(51, LevelSelectionTrace.new(strategy.get_strategy_id(), 1, 51))
	strategy._select_easy_rank(request, 1)
	_check(strategy._ctx.sz == 5, "NL12002 returnee easy branch uses frozen configured size instead of default eight")
	_check(state.get_core_candidate() == before, "frozen content branch checks never mutate live state")


func _test_special_table_branches(state: Node, resolver: GDScript, runtime_script: GDScript, base: Dictionary) -> void:
	var before: Dictionary = state.get_core_candidate()
	var provider: GDScript = load("res://products/meowdoku/gameplay/application/selection/provider/special_provider.gd")
	var rating: GDScript = load("res://products/meowdoku/gameplay/application/selection/strategy/hard_rating_selector.gd")
	var context: Dictionary = base.duplicate(true)
	context.policy.content_policy = {}
	var runtime: RefCounted = runtime_script.new(before, context)
	_check(provider.levels_for(runtime) == provider.SPECIAL_LEVELS and provider.levels_for().has(10), "absent special override preserves complete built-in schedule")
	context.policy.content_policy = {"special_levels": {}}
	runtime = runtime_script.new(before, context)
	_check(provider.levels_for(runtime).is_empty() and rating.rank_at(210, true, runtime) == 4 and rating.rank_at(210, true) == 5, "explicit empty schedule removes fixed levels from hard-rank alternation")
	context.policy.content_policy = {"special_levels": {"120": {"source": "sp", "index": 1}}}
	runtime = runtime_script.new(before, context)
	_check(provider.levels_for(runtime).has(120) and rating.rank_at(130, true, runtime) == 5 and rating.rank_at(130, true) == 4, "added configured special level participates in hard-rank alternation")
	for level: int in [10, 21]:
		context = base.duplicate(true)
		context.policy.normal_level = 12002
		context.policy.content_policy = {"special_levels": {} if level == 10 else {"21": {"source": "sp", "index": 1}}, "size_cycles": {"12002": [{"from": 1, "sizes": [5]}]}}
		runtime = runtime_script.new(before, context)
		runtime.state.begin_returnee_event(12002, 2, 2)
		var strategy: RefCounted = resolver.new().resolve_by_value(12002)
		strategy.bind_runtime(runtime)
		var request: RefCounted = LevelSelectRequest.new(level, LevelSelectionTrace.new(strategy.get_strategy_id(), 1, level))
		var selected: Dictionary = strategy.select(request)
		_check(strategy._fixed_sp_delivery == (level == 21), "returnee fixed-special branch follows added/deleted configured level %d" % level)
		_check(selected.has("entry"), "returnee modified schedule level %d still delivers a puzzle" % level)
	for value: int in [11515, 11710, 11711, 11923, 11924, 11925]:
		context = base.duplicate(true)
		context.policy.normal_level = value
		context.policy.content_policy = {"special_levels": {"21": {"source": "sp", "index": 1}}}
		runtime = runtime_script.new(before, context)
		var strategy: RefCounted = resolver.new().resolve_by_value(value)
		strategy.bind_runtime(runtime)
		_check(strategy._preview_branch_name(21).contains("特殊") and strategy._preview_detail(21).contains("idx=1"), "NL%d recommendation preview recognizes added special level and same provider spec" % value)
		_check(not strategy._preview_branch_name(30).contains("特殊"), "NL%d recommendation preview forgets deleted built-in special level" % value)
	_check(state.get_core_candidate() == before, "all special schedule branches remain candidate-only")
