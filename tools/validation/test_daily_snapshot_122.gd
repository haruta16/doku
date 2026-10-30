## 1.22 每日残局：三种恢复模式、不可恢复边界与脏题池输入。
extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var regions: Array = [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]]
	var solution: Array = [1, 3, 0, 2]
	var snapshot: Dictionary = DailyEndgameSnapshot.build("2026-10-30", "session-a", {"size": 4, "rank": 1}, regions, solution,
		{"placed_cats": [[0, 1]], "marks": [[1, 0]], "errors": [[2, 3]]}, 2, 1,
		{"score": 42, "combo": 2, "max_combo": 2, "se_count": 1, "se_last_step": 3}, 35,
		{"operable_sec": 20.5, "cat_toast": {"last_cat_sec": 20.0, "fired": [1]}, "cat_progress_rotate_start": 1})
	_check(not _restore(snapshot, false, false), "OFF does not restore")
	_check(_restore(snapshot, true, true), "SAME_SESSION restores current session")
	_check(not _restore(snapshot, true, true, "session-b"), "SAME_SESSION rejects another session")
	_check(_restore(snapshot, true, false, "session-b"), "ALL_DAY accepts another session on same date")
	_check(not DailyEndgameSnapshot.should_restore(snapshot, true, false, true, true, "2026-10-30", "session-a", 3), "explicit restart/replay stays fresh")
	_check(not DailyEndgameSnapshot.should_restore(snapshot, true, false, false, true, "2026-10-31", "session-a", 3), "next day rejects old snapshot")
	_check(not DailyEndgameSnapshot.should_restore(snapshot, true, false, false, false, "2026-10-30", "session-a", 3), "missing started-today receipt rejects restoration")
	var params: Dictionary = DailyEndgameSnapshot.restore_params(snapshot)
	_check(params.restore_score == 42 and params.restore_operable_sec == 20.5 and params.restore_cat_progress_rotate == 1, "score, timing, toast and rotation survive adaptation")
	_check(not params.has("content_release") and not params.has("policy_snapshot"), "legacy 1.22 snapshot preserves active content defaults")
	params.restore_cat_toast.fired.append(99)
	_check(snapshot.cat_toast.fired == [1], "restored UI state is not aliased to saved state")
	regions[0][0] = 9
	solution[0] = 0
	_check(snapshot.regions[0][0] == 0 and snapshot.solution[0] == 1, "snapshot owns puzzle copy")
	for pair: Array in [["lives", 0], ["lives", 4], ["elapsed_sec", -1], ["elapsed_sec", NAN], ["elapsed_sec", 1.25], ["size", 100000000], ["score", -1], ["combo", 10]]:
		var damaged: Dictionary = snapshot.duplicate(true)
		damaged[pair[0]] = pair[1]
		_check(not _restore(damaged), "invalid numeric field is rejected: " + str(pair))
	for cells: Array in [[[0, 1], [0, 1]], [[0, 0]], [[0.5, 1]], [[4, 1]]]:
		var damaged: Dictionary = snapshot.duplicate(true)
		damaged.placed_cats = cells
		_check(not _restore(damaged), "duplicate, wrong solution, fractional and out-of-range cats rejected")
	var overlap: Dictionary = snapshot.duplicate(true)
	overlap.marks.append([0, 1])
	_check(not _restore(overlap), "cross-category cell overlap rejected")
	var completed: Dictionary = snapshot.duplicate(true)
	completed.placed_cats = [[0, 1], [1, 3], [2, 0], [3, 2]]
	completed.marks = []
	completed.errors = []
	_check(not _restore(completed), "completed puzzle cannot revive as endgame")
	var empty: Dictionary = snapshot.duplicate(true)
	empty.placed_cats = []; empty.marks = []; empty.errors = []; empty.mistake_count = 0; empty.score = 0
	_check(not _restore(empty), "no-progress snapshot does not restore")
	_check(DailyEndgameSnapshot.puzzle_entry_is_valid({"regionMap": snapshot.regions, "solution": snapshot.solution}, 4), "valid bank entry accepted before transform")
	for entry: Dictionary in [{}, {"regionMap": [[1]], "solution": [1, 3, 0, 2]}, {"regionMap": "invalid", "solution": []}, {"regionMap": snapshot.regions, "solution": [1, 1, 0, 2]}, {"regionMap": snapshot.regions, "solution": [NAN, 3, 0, 2]}]:
		_check(not DailyEndgameSnapshot.puzzle_entry_is_valid(entry, 4), "malformed bank record rejected before indexing or transform")
	print("DAILY SNAPSHOT 122 TESTS: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _restore(snapshot: Dictionary, enabled: bool = true, same_session: bool = false, session: String = "session-a") -> bool:
	return DailyEndgameSnapshot.should_restore(snapshot, enabled, same_session, false, true, "2026-10-30", session, 3)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TEST_FAILED: " + message)
