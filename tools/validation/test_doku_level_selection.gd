## 必须在 tools/run_validation.py 隔离副本运行：1.22 候选、恢复与提交边界。
extends SceneTree
var checks: int = 0
var failures: int = 0
func _initialize() -> void: _run.call_deferred()
func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("TEST_FAILED: " + message)
func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	var ab: Node = root.get_node("ABTestManager")
	var levels: GDScript = load("res://products/meowdoku/gameplay/application/level_data.gd")
	var selector: GDScript = load("res://products/meowdoku/gameplay/application/selection/level_selector.gd")
	var fixture: Dictionary = game_state.get_core_candidate()
	fixture.profile.current_level = 1
	fixture.profile.current_strategy = 1
	fixture.profile.recent_puzzles = []
	_check(game_state.commit_core_candidate(fixture, game_state.get_core_store().revision()).get("ok", false), "fixture commits")
	ab.normal_level.set_debug_override(0)
	ab.single_region_num.set_debug_override(0)
	var before: Dictionary = game_state.get_core_candidate()
	var revision: int = game_state.get_core_store().revision()
	var plan: Dictionary = levels.resolve_level_entry(1, 0, 122)
	_check(plan.get("ok", false), "1.22 first level resolves")
	if not plan.get("ok", false):
		quit(1)
		return
	_check(game_state.get_core_candidate() == before and game_state.get_core_store().revision() == revision, "selection has no live writes")
	var repeated: Dictionary = levels.resolve_level_entry(1, 0, 122)
	_check(repeated.get("entry", {}) == plan.entry, "same seed and candidate keep selected puzzle")
	ab.normal_level.set_debug_override(12208)
	_check(int(plan.selection_policy.normal_level) == 0, "prepared policy stays frozen after AB change")
	before = game_state.get_core_candidate() # AB调试写本身不属于选题事务。
	var files: RefCounted = game_state.get_core_store().get("_file_store")
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failed: Dictionary = levels.commit_selected(plan)
	_check(not failed.get("ok", false) and game_state.get_core_candidate() == before, "failed entry write preserves cursor and inventory")
	files.set_fault_injector_for_tests(Callable())
	_check(levels.commit_selected(plan).get("ok", false), "same plan can retry")
	revision = game_state.get_core_store().revision()
	_check(levels.commit_selected(plan).get("duplicate", false) and game_state.get_core_store().revision() == revision, "duplicate delivery is read-only")
	var state: RefCounted = selector.create_entry_state(122)
	var baseline: Dictionary = state.base_candidate()
	state.stage_daily_entry("2026-10-30", false, false, 0)
	_check(state.base_candidate() == baseline and state.export_candidate().profile.daily_started_date == "2026-10-30", "daily mutation keeps original conflict baseline")
	var entry: Dictionary = plan.entry.duplicate(true)
	entry["is_daily"] = true
	entry["date"] = "2026-10-30"
	entry["selection_policy"] = plan.selection_policy.duplicate(true)
	var daily: Dictionary = selector.prepare_existing_entry(state, 0, entry)
	_check(daily.mode == "daily" and daily.selection_policy.normal_level == 0, "existing daily keeps saved policy independent from current AB")
	var candidate: Dictionary = game_state.get_core_candidate()
	var main_snapshot: Dictionary = candidate.endgame.snapshot.duplicate(true)
	var staged: Dictionary = levels.stage_selected(candidate, daily, {"date": "2026-10-30"})
	_check(staged.get("ok", false) and candidate.endgame.snapshot == main_snapshot and candidate.endgame.daily_snapshot.date == "2026-10-30", "daily entry preserves main snapshot in same candidate")
	var conflict_state: RefCounted = selector.create_entry_state(123)
	conflict_state.get_current_strategy()
	var conflict: Dictionary = selector.prepare_existing_entry(conflict_state, 1, plan.entry)
	candidate = game_state.get_core_candidate()
	candidate.profile.current_strategy = int(candidate.profile.current_strategy) + 1
	_check(levels.stage_selected(candidate, conflict).get("error") == "selection_conflict", "relevant state change rejects stale plan")
	print("PASS: 1.22 selection transaction checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
