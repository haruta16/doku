## 提交后选题效果：隔离 SDK 标签、真实 GameState、局部候选与失败/重入边界。
extends SceneTree

class Reply extends RefCounted:
	signal released(tags: Dictionary)

class DeferredTags extends UniKitUserTagModule:
	var replies: Array[Reply] = []
	func get_remote_tags() -> Dictionary:
		var reply := Reply.new()
		replies.append(reply)
		return await reply.released
	func release(index: int, tags: Dictionary) -> void:
		replies[index].released.emit(tags)

class EffectPort extends RefCounted:
	var backing: Node
	var published: Array[Dictionary] = []
	func _init(value: Node) -> void: backing = value
	func is_storage_ready() -> bool: return backing.is_storage_ready()
	func get_core_store() -> RefCounted: return backing.get_core_store()
	func get_core_candidate() -> Dictionary: return backing.get_core_candidate()
	func commit_core_candidate(candidate: Dictionary, revision: int) -> Dictionary: return backing.commit_core_candidate(candidate, revision)
	func stage_round_selection(candidate: Dictionary, plan: Dictionary, checkpoint: Dictionary) -> Dictionary: return backing.stage_round_selection(candidate, plan, checkpoint)
	func capture_selection_effect_context() -> Dictionary: return backing.capture_selection_effect_context()
	func publish_selection_effects(plan: Dictionary, guard: Dictionary) -> void: published.append({"plan": plan.duplicate(true), "guard": guard.duplicate(true)})

var checks: int = 0
var failures: int = 0
var game: Node
var ab: Node
var sdk: Node
var manager: Node
var selector: GDScript
var assist: GDScript
var files: RefCounted
var tags: DeferredTags
var original_tags: UniKitUserTagModule

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-") or not ProjectSettings.get_setting("doku/validation/offline", false):
		quit(2)
		return
	game = root.get_node("GameState")
	ab = root.get_node("ABTestManager")
	sdk = root.get_node("UniKit")
	manager = root.get_node("UniKitManager")
	selector = load("res://products/meowdoku/gameplay/application/selection/level_selector.gd")
	assist = load("res://products/meowdoku/app/features/user_tag/config/has_assist_user_tag.gd")
	files = game.get_core_store().get("_file_store")
	original_tags = sdk.usertag_module
	tags = DeferredTags.new(sdk)
	tags._is_usertag_data_ready = true
	sdk.usertag_module = tags
	ab.normal_level.set_debug_override(11911)
	_test_all_assist_groups()
	await _test_legacy_publication()
	await _test_async_reset()
	await _test_direct_selection_commit()
	await _test_round_session()
	await _test_ready_binding()
	_test_injected_publisher()
	_test_recommendation_head()
	_fault(false)
	sdk.usertag_module = original_tags
	ab.normal_level.clear_debug_override()
	await process_frame
	print("SELECTION EFFECTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _reset() -> void:
	_fault(false)
	_check(game.reset_all(), "reset selection effects fixture")
	assist._cached = -1
	assist._fetch_in_flight = false

func _prepare() -> Dictionary:
	return selector.prepare(game.get_current_level(), 0, {}, false, 122)

func _test_all_assist_groups() -> void:
	_reset()
	var count: int = tags.replies.size()
	for variant: int in [11911, 11961, 12209]:
		ab.normal_level.set_debug_override(variant)
		var plan: Dictionary = _prepare()
		_check(plan.get("ok", false) and plan.get("effects", []).has({"kind": "refresh_assist_user"}) and tags.replies.size() == count, "assist group %d keeps refresh deferred until commit" % variant)
	ab.normal_level.set_debug_override(11911)

func _test_legacy_publication() -> void:
	_reset()
	var before: Dictionary = game.get_core_candidate()
	var initial: Dictionary = selector.capture_context(122)
	var count: int = tags.replies.size()
	var plan: Dictionary = _prepare()
	_check(plan.get("ok", false) and plan.get("effects", []).has({"kind": "refresh_assist_user"}), "11911 retains original refresh request as a candidate effect")
	_check(not initial.assist_user and tags.replies.size() == count and game.get_core_candidate() == before, "unknown first selection uses old cache and starts no remote work")
	var invalid: Dictionary = {"kind": "invalid_recommendation", "entry": {"_rec_decision_id": "selection-effects-fault"}, "reason": "invalid_shape"}
	plan.effects.append(invalid)
	var batches: Dictionary = root.get_node("LevelRecManager")._invalid_reported_batches.duplicate(true)
	_fault(true)
	_check(not game.on_level_won(1, LevelKind.MAIN, 0, 0, true, null, plan), "failed diagnostic transaction rejects publication")
	_check(tags.replies.size() == count and game.get_core_candidate() == before and root.get_node("LevelRecManager")._invalid_reported_batches == batches, "failed commit neither starts tag refresh nor reports invalid recommendation")
	_fault(false)
	plan.effects.erase(invalid)
	_check(game.on_level_won(1, LevelKind.MAIN, 0, 0, true, null, plan), "diagnostic commit accepts candidate and then publishes")
	_check(tags.replies.size() == count + 1 and assist.cached_value() == -1, "successful commit starts one asynchronous refresh")
	_check(game.on_level_won(1, LevelKind.MAIN, 0, 0, true, null, plan) and tags.replies.size() == count + 1, "replayed plan does not publish refresh twice")
	tags.release(count, {"has_assist": 1})
	await process_frame
	_check(assist.cached_value() == 1 and game.is_has_assist_confirmed(), "accepted remote tag updates cache and persisted confirmation")
	_check(not initial.assist_user and selector.capture_context(123).assist_user, "refresh affects subsequent contexts without changing the initial context")
	assist._cached = -1
	var revision: int = game.get_core_store().revision()
	_check(selector.capture_context(124).assist_user and game.get_core_store().revision() == revision, "cold cache preserves already confirmed assist user on first selection without a write")
	_test_assist_rule(initial, selector.capture_context(125))

func _test_assist_rule(before: Dictionary, after: Dictionary) -> void:
	for context: Dictionary in [before, after]:
		var runtime: RefCounted = selector.make_runtime(game.get_core_candidate(), context)
		var strategy: RefCounted = load("res://products/meowdoku/gameplay/application/selection/strategy/nl_11911_strategy.gd").new()
		strategy.bind_runtime(runtime)
		var settlement: RefCounted = LevelSettlementContext.new()
		settlement.strategy = 2
		settlement.strategy_before_all = 3
		settlement.tool_or_revive_used = true
		strategy.on_level_won_settlement(settlement)
		_check(settlement.strategy == (3 if context.assist_user else 2), "11911 tool demotion exemption follows captured assist context")

func _test_async_reset() -> void:
	_reset()
	var count: int = tags.replies.size()
	var plan: Dictionary = _prepare()
	_check(game.on_level_failed(1, LevelKind.MAIN, plan) and tags.replies.size() == count + 1, "successful diagnostic loss also publishes selection effects")
	_check(game.reset_all(), "reset during outstanding remote tag request succeeds")
	tags.release(count, {"has_assist": 1})
	await process_frame
	_check(not game.is_has_assist_confirmed() and assist.cached_value() != 1, "stale remote completion cannot mark replacement storage generation")

func _test_direct_selection_commit() -> void:
	_reset()
	var levels: GDScript = load("res://products/meowdoku/gameplay/application/level_data.gd")
	var plan: Dictionary = _prepare()
	var count: int = tags.replies.size()
	_fault(true)
	_check(not levels.commit_selected(plan).get("ok", false) and tags.replies.size() == count, "direct selection commit failure publishes no effect")
	_fault(false)
	_check(levels.commit_selected(plan).get("ok", false) and tags.replies.size() == count + 1, "public selection commit API also publishes accepted effects")
	_check(levels.commit_selected(plan).get("duplicate", false) and tags.replies.size() == count + 1, "duplicate direct selection commit is effect-free")
	tags.release(count, {"has_assist": 0})
	await process_frame

func _context(plan: Dictionary) -> Dictionary:
	var board: Array = []
	var solution: Array = []
	var size: int = plan.entry.regionMap.size()
	for row: int in range(size):
		var line: Array = []
		var answers: Array = []
		for col: int in range(size):
			line.append(0)
			answers.append(col == int(plan.entry.solution[row]))
		board.append(line)
		solution.append(answers)
	return {"board": board, "regions": plan.entry.regionMap, "solution": solution, "lives": 3, "level": int(plan.level), "kind": LevelKind.MAIN}

func _test_round_session() -> void:
	_reset()
	var session_script: GDScript = load("res://products/meowdoku/gameplay/application/meowdoku_round_session.gd")
	var session: RefCounted = session_script.new(game, "main")
	var plan: Dictionary = _prepare()
	var context: Dictionary = _context(plan)
	var before: Dictionary = game.get_core_candidate()
	var count: int = tags.replies.size()
	_fault(true)
	_check(not session.ensure_started(context, "", {}, plan).get("ok", false), "formal round failed start does not publish")
	_check(tags.replies.size() == count and game.get_core_candidate() == before, "formal failed start preserves candidate and external effect count")
	_fault(false)
	var accepted: Dictionary = session.ensure_started(context, "", {}, plan)
	_check(accepted.get("ok", false) and tags.replies.size() == count + 1, "formal round start publishes committed selection effects")
	var restored: RefCounted = session_script.new(game, "main")
	_check(restored.ensure_started(context, str(accepted.get("round_id", "")), {}, plan).get("ok", false) and tags.replies.size() == count + 1, "same committed plan restore does not repeat external effects")
	if tags.replies.size() > count:
		tags.release(count, {"has_assist": 0})
	await process_frame
	_reset()
	plan = _prepare()
	context = _context(plan)
	count = tags.replies.size()
	var reset_once: Callable = func(_revision: int) -> void: game.reset_all()
	game.get_core_store().committed.connect(reset_once, CONNECT_ONE_SHOT)
	var reentered: RefCounted = session_script.new(game, "main")
	reentered.ensure_started(context, "", {}, plan)
	_check(tags.replies.size() == count and not game.is_has_assist_confirmed(), "synchronous reset from commit notification invalidates old pending effects")

func _test_ready_binding() -> void:
	_reset()
	tags._is_usertag_data_ready = false
	var count: int = tags.replies.size()
	var plan: Dictionary = _prepare()
	_check(game.on_level_failed(1, LevelKind.MAIN, plan) and tags.replies.size() == count, "uninitialized SDK queues refresh until usertag readiness")
	tags._is_usertag_data_ready = true
	manager.usertag_ready.emit({})
	_check(tags.replies.size() == count + 1, "actual manager usertag_ready signal starts pending refresh")
	tags.release(count, {"has_assist": 0})
	await process_frame
	_check(assist.cached_value() == 0, "ready-triggered refresh resolves exactly once")
	_reset()
	tags._is_usertag_data_ready = false
	count = tags.replies.size()
	plan = _prepare()
	_check(game.on_level_failed(1, LevelKind.MAIN, plan), "prepare pending readiness request before reset")
	_check(game.reset_all(), "reset pending readiness generation")
	tags._is_usertag_data_ready = true
	manager.usertag_ready.emit({})
	_check(tags.replies.size() == count, "old SDK-ready callback cannot launch refresh after reset")

func _test_injected_publisher() -> void:
	_reset()
	var proxy := EffectPort.new(game)
	var session_script: GDScript = load("res://products/meowdoku/gameplay/application/meowdoku_round_session.gd")
	var session: RefCounted = session_script.new(proxy, "main")
	var plan: Dictionary = _prepare()
	var invalid: Dictionary = {"kind": "invalid_recommendation", "entry": {"_rec_decision_id": "injected-port"}, "reason": "invalid_shape"}
	plan.effects.append(invalid)
	var context: Dictionary = _context(plan)
	_fault(true)
	_check(not session.ensure_started(context, "", {}, plan).get("ok", false) and proxy.published.is_empty(), "injected publisher receives no refresh or invalid report from failed commit")
	_fault(false)
	var accepted: Dictionary = session.ensure_started(context, "", {}, plan)
	_check(accepted.get("ok", false) and proxy.published.size() == 1 and proxy.published[0].plan.effects.has(invalid), "successful formal commit forwards complete invalid-report payload to injected publisher")
	_check(proxy.published[0].plan.selection_id == game.get_core_candidate().features.doku_selection.selection_id and proxy.published[0].guard.storage_epoch == game.get_storage_epoch(), "publisher receives committed selection identity and original storage epoch")
	var restored: RefCounted = session_script.new(proxy, "main")
	restored.ensure_started(context, str(accepted.get("round_id", "")), {}, plan)
	_check(proxy.published.size() == 1, "restored same-plan commit skips injected publisher")

func _test_recommendation_head() -> void:
	_reset()
	var rec: Node = root.get_node("LevelRecManager")
	var plan: Dictionary = _prepare()
	var entry: Dictionary = plan.entry
	var raw: Dictionary = {"qid": "%d_regular_1_1_0" % entry.size, "region_map": entry.regionMap, "solution": entry.solution, "size": entry.size}
	var queue: Dictionary = {"levels": [raw], "cursor": 0, "extra_values": {}, "request_id": "effects-head", "delivered_qids": {}}
	rec._queue.load_from(queue)
	var before: Dictionary = game.get_core_candidate()
	var valid: Dictionary = rec._validate_current_head(false)
	_check(not valid.is_empty() and game.get_core_candidate() == before and rec._queue.remaining() == 1, "real recommendation head inspection injects candidate runtime without consuming or writing")
	_check(game.on_level_won(1, LevelKind.MAIN, 0, 0, true, null, plan), "commit original puzzle before cross-level recommendation check")
	if assist._fetch_in_flight:
		tags.release(tags.replies.size() - 1, {"has_assist": 0})
	rec._queue.load_from(queue)
	before = game.get_core_candidate()
	_check(rec._validate_current_head(false).is_empty() and game.get_core_candidate() == before, "real recommendation head rejects recently delivered puzzle at another level without mutation")
	rec._queue.clear()

func _fault(enabled: bool) -> void:
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return enabled and phase == "before_replace")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("ASSERT FAILED: " + message)
