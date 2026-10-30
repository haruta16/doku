## 拒绝池大于调用栈上限时仍须有界结束，并保留游标、轮换和 LK 插题语义。
extends SceneTree

var checks: int = 0
var failures: int = 0
var levels: Script
var banks: Script
var selection: Script
var core: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	levels = load("res://products/meowdoku/gameplay/application/level_data.gd")
	banks = load("res://products/meowdoku/gameplay/content/bank_data.gd")
	selection = load("res://products/meowdoku/gameplay/application/doku_selection_state.gd")
	core = load("res://products/meowdoku/gameplay/domain/queendoku_core.gd")
	var state: Node = root.get_node("GameState")
	var initial: Dictionary = state.get_core_candidate()
	var revision: int = state.get_core_store().revision()
	var rejected: Dictionary = {"size": 4, "r": 1, "regionMap": [[3, 0, 3, 3], [3, 3, 3, 1], [2, 3, 3, 3], [3, 3, 3, 3]], "solution": [1, 3, 0, 2]}
	var accepted: Dictionary = {"size": 4, "r": 1, "regionMap": [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]], "solution": [1, 3, 0, 2]}
	_check(core.validate_solution_entry(rejected, 4) and core.validate_solution_entry(accepted, 4), "both fixtures have legal answers")
	var pool: Array = []
	pool.resize(1200)
	pool.fill(rejected)
	_install(pool)
	var working: RefCounted = _working()
	var entry: Dictionary = levels.get_next_entry(4, 1, "", -1, working, {"single_region": 1})
	_check(entry._bank_idx == 1200 and working.get_bank_index(4, 1) == 1200, "legacy rejection exhausts a long pool and advances the final playable candidate once")
	_check(core.validate_solution_entry(entry, 4), "legacy preference exhaustion returns a legal board")
	pool.resize(200)
	_install(pool)
	working = _working()
	entry = levels.get_next_entry_main(4, 1, "", -1, false, working, {"single_region": 1})
	var progress: Dictionary = working.get_main_progress(4, 1)
	_check(entry._bank_idx == 200 and entry._bank_transform == 7, "main rejection visits all eight rotations without recursive stack growth")
	_check(progress.idx == 200 and progress.transform == 7 and progress.since_lk == 1, "only the selected fallback counts toward the next LK insertion")
	_check(core.validate_solution_entry(entry, 4), "transformed fallback still has a legal answer")

	_install([rejected, accepted])
	working = _working()
	entry = levels.get_next_entry(4, 1, "", -1, working, {"single_region": 1})
	_check(entry._bank_idx == 2 and working.get_bank_index(4, 1) == 2, "legacy selection skips rejected preference and consumes the accepted candidate")
	working = _working()
	working.set_main_progress(4, 1, "", {"idx": 2, "since_lk": 3, "transform": 7})
	entry = levels.get_next_entry_main(4, 1, "", -1, false, working, {"single_region": 1})
	progress = working.get_main_progress(4, 1)
	_check(entry._bank_idx == 2 and entry._bank_transform == 0 and progress.since_lk == 1, "rotation wraps to zero and skipped preferences do not count as played levels")

	var invalid: Dictionary = accepted.duplicate(true)
	invalid.solution = [0, 0, 0, 0]
	_install([invalid, accepted])
	working = _working()
	working.set_main_progress(4, 1, "", {"idx": 0, "since_lk": 0, "transform": 3})
	entry = levels.get_next_entry_main(4, 1, "", -1, false, working, {})
	_check(entry._bank_idx == 2 and entry._bank_transform == 3 and core.validate_solution_entry(entry, 4), "invalid answers are rejected before the rotation algorithm")
	_check(working.get_main_progress(4, 1).since_lk == 1, "invalid skipped answers do not count toward insertion")
	_install([invalid, invalid])
	working = _working()
	entry = levels.get_next_entry_main(4, 1, "", -1, false, working, {})
	progress = working.get_main_progress(4, 1)
	_check(not core.validate_solution_entry(entry, 4) and entry._bank_transform == 7, "all-invalid pool stops after its finite retry budget for the caller to reject")
	_check(progress.idx == 1 and progress.transform == 7 and progress.since_lk == 0, "an invalid final candidate is never consumed as a selected level")

	var modified: Dictionary = accepted.duplicate(true)
	modified.r = 2
	modified.maxR = 1
	_install([invalid, invalid, invalid, invalid, invalid], [modified])
	working = _working()
	working.set_main_progress(4, 1, "", {"idx": 0, "since_lk": 4, "transform": 0})
	entry = levels.get_next_entry_main(4, 1, "", -1, true, working, {})
	_check(entry._bank_source == "lk_mod" and entry._bank_idx == 1, "invalid-answer retry preserves existing strict-rank relaxation for LK modified entries")
	_check(working.get_lkmod_progress(4, 1).idx == 1 and working.get_main_progress(4, 1).since_lk == 0, "LK selection advances its own cursor and clears the insertion counter")
	_install([], [modified])
	working = _working()
	entry = levels.get_next_entry_main(4, 1, "", -1, false, working, {})
	_check(entry.get("_bank_source") == "lk_mod" and core.validate_solution_entry(entry, 4), "an LK-only legal pool supplies its available puzzle without requiring four regular puzzles")
	_check(working.get_lkmod_progress(4, 1).idx == 1 and working.get_main_progress(4, 1).transform == 0, "LK-only selection consumes its cursor without rotating a nonexistent regular pool")
	entry = levels.get_next_entry_main(4, 1, "", -1, false, working, {})
	_check(entry.is_empty() and working.get_lkmod_progress(4, 1).idx == 1, "an exhausted LK-only pool reports no puzzle instead of resetting its one-time progress")
	_check(state.get_core_candidate() == initial and state.get_core_store().revision() == revision, "all selection previews keep real core state and its revision unchanged")
	ContentContext.publish(null)
	print("DOKU_SELECTION_FALLBACK_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _working() -> RefCounted:
	return selection.new({"profile": {"current_level": 51, "current_strategy": 1}, "runtime": {}, "daily_available": false, "today": "2026-10-27"})


func _install(entries: Array, modified: Array = []) -> void:
	banks._content_generation = ContentContext.generation()
	banks._cache = {"4_1": entries}
	banks._loaded_sizes.assign([4])
	banks._lk_style_loaded_sizes.assign([4])
	banks._lk_style_cache = {}
	banks._lk_modified_loaded = true
	banks._lk_modified_levels = modified


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
