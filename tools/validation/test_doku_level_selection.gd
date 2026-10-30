## 必须运行于 tools/run_validation.py 隔离副本；真实题库与核心存档的选题事务回归。
extends SceneTree

var _checks: int = 0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + message)


func _run() -> void:
	var levels: GDScript = load("res://products/meowdoku/gameplay/application/level_data.gd")
	var state: Node = root.get_node("GameState")
	var ab: Node = root.get_node("ABTestManager")
	var content: GDScript = load("res://scripts/framework/content/content_context.gd")
	var initial: Dictionary = state.get_core_candidate()
	initial.profile.current_level = 1
	initial.profile.current_strategy = 1
	initial.profile.daily_first_easy_date = ""
	initial.profile.bank_progress = {}
	initial.profile.main_bank_progress = {}
	initial.profile.lkmod_progress = {}
	initial.profile.recent_puzzles = []
	initial.round_runtime.is_daily_first_easy_level = false
	_check(state.commit_core_candidate(initial, state.get_core_store().revision()).get("ok", false), "selection fixture committed")
	state.set("_daily_first_easy_available", true)
	ab.rule_normal_rank.set_debug_override(1)
	ab.single_region_num.set_debug_override(0)
	var baseline: Dictionary = state.get_core_candidate()
	var revision: int = state.get_core_store().revision()
	var plan: Dictionary = levels.resolve_level_entry(1, 4, 1234)
	_check(plan.get("ok", false), "real bank resolves first level")
	if not plan.get("ok", false):
		quit(1)
		return
	_check(state.get_core_candidate() == baseline and state.get_core_store().revision() == revision, "preview changes no cursor, qualification, recent history or saved revision")
	var same: Dictionary = levels.resolve_level_entry(1, 4, 1234)
	_check(same.selection_id == plan.selection_id and same.entry == plan.entry, "same seed and state resolve the same plan")
	_check(plan.next_selection.profile.daily_first_easy_date != "" and not plan.next_selection.runtime.is_daily_first_easy_level, "first-level opportunity is consumed without falsely marking a difficulty reduction")
	var unrelated: Dictionary = state.get_core_candidate()
	unrelated.profile["has_used_tool"] = true
	_check(state.commit_core_candidate(unrelated, state.get_core_store().revision()).get("ok", false), "unrelated profile update succeeds")
	var checkpoint: Dictionary = {"level": 1, "lives": 3, "selection_test": true}
	var retry: Dictionary = {"retry_level": 1, "bank_mode": true}
	var committed: Dictionary = levels.commit_selected(plan, checkpoint, retry)
	_check(committed.get("ok", false), "unrelated revision does not invalidate selection")
	var saved: Dictionary = state.get_core_store().snapshot()
	_check(saved.profile.has_used_tool, "selection preserves unrelated update")
	_check(saved.endgame.snapshot == checkpoint and saved.profile.retry_puzzle_params == retry, "cursor and starting snapshot/retry cache commit together")
	_check(saved.profile.recent_puzzles.size() == 1 and saved.profile.recent_puzzles[0].puzzle_id == plan.puzzle_id, "only selected puzzle becomes seen")
	_check(not state.is_daily_first_easy_available(), "commit updates transient daily availability")
	revision = state.get_core_store().revision()
	_check(levels.commit_selected(plan, checkpoint, retry).get("duplicate", false), "selection commit retries are idempotent")
	_check(state.get_core_store().revision() == revision, "duplicate commit does not write another slot")
	var next_fixture: Dictionary = state.get_core_candidate()
	next_fixture.profile.current_level = 51
	next_fixture.profile.current_strategy = 1
	next_fixture.profile.daily_first_easy_date = ""
	next_fixture.profile.recent_puzzles = []
	_check(state.commit_core_candidate(next_fixture, state.get_core_store().revision()).get("ok", false), "new segment fixture commits")
	state.set("_daily_first_easy_available", true)
	ab.rule_normal_rank.set_debug_override(6)
	baseline = state.get_core_candidate()
	plan = levels.resolve_level_entry(51, 6, 9876)
	_check(plan.get("ok", false), "main bank and mod1 exemption resolve")
	if plan.get("ok", false):
		_check(state.get_core_candidate() == baseline, "main cursor migration and daily downgrade remain private until commit")
		_check(plan.next_selection.profile.current_strategy == 2 and plan.next_selection.runtime.is_daily_first_easy_level, "strategy floor and real daily downgrade are staged")
		var file_store: RefCounted = state.get_core_store().get("_file_store")
		file_store.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
		var failed: Dictionary = levels.commit_selected(plan)
		_check(failed.get("error") == "selection_commit_failed", "write failure rejects start")
		_check(failed.get("cause", {}).get("error") == "write_failed" and not str(failed.get("detail", "")).is_empty(), "selection failure retains the storage cause and diagnostic detail")
		_check(state.get_core_candidate() == baseline, "write failure does not consume cursor or daily qualification")
		file_store.set_fault_injector_for_tests(Callable())
		_check(levels.commit_selected(plan).get("ok", false), "same planned start retries after disk failure")
		_check(state.get_endgame_snapshot().is_empty(), "new selection without a checkpoint clears the previous puzzle snapshot")
	var conflict_plan: Dictionary = levels.resolve_level_entry(51, 6, 123)
	if conflict_plan.get("ok", false):
		var changed: Dictionary = state.get_core_candidate()
		changed.profile.current_strategy = int(changed.profile.current_strategy) + 1
		state.commit_core_candidate(changed, state.get_core_store().revision())
		_check(levels.commit_selected(conflict_plan).get("error") == "selection_conflict", "relevant DDA change rejects stale plan")
	var content_plan: Dictionary = levels.resolve_level_entry(51, 6, 456)
	if content_plan.get("ok", false):
		content.publish(null)
		_check(levels.commit_selected(content_plan).get("error") == "selection_content_changed", "content activation rejects old selection")
	if _failures == 0:
		print("PASS: Level selection preview, deterministic seed, atomic commit, retries, daily downgrade and conflict guards checks=%d failures=0" % _checks)
	quit(0 if _failures == 0 else 1)
