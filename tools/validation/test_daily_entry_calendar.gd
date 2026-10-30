## 每日入口的日期边界与缓存 UI：固定公历期望，不改系统时钟或既有本地日规则。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var streak: Node
var daily: Script
var entry: Script
var files: RefCounted
var today: String
var yesterday: String
var tomorrow: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	game = root.get_node("GameState")
	streak = root.get_node("StreakManager")
	daily = load("res://products/meowdoku/gameplay/presentation/daily/view/daily_game_page.gd")
	entry = load("res://products/meowdoku/gameplay/presentation/daily/model/daily_entry_state.gd")
	files = game.get_core_store().get("_file_store")
	today = entry._today_str()
	yesterday = streak._date_offset_str_from(today, -1)
	tomorrow = streak._date_offset_str_from(today, 1)
	_test_calendar()
	_test_entry_dates()
	await _test_cached_cell()
	files.set_fault_injector_for_tests(Callable())
	print("DAILY ENTRY CALENDAR TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_calendar() -> void:
	for pair: Array in [
		["2026-01-31", "2026-02-01"], ["2026-04-30", "2026-05-01"],
		["2026-12-31", "2027-01-01"], ["2024-02-28", "2024-02-29"],
		["2024-02-29", "2024-03-01"], ["1900-02-28", "1900-03-01"],
		["2000-02-28", "2000-02-29"], ["2100-02-28", "2100-03-01"]]:
		var first: PackedStringArray = pair[0].split("-")
		var second: PackedStringArray = pair[1].split("-")
		var a: int = daily._local_date_to_jdn(int(first[0]), int(first[1]), int(first[2]))
		var b: int = daily._local_date_to_jdn(int(second[0]), int(second[1]), int(second[2]))
		_check(b - a == 1, "daily puzzle calendar advances once at " + pair[0])
		_check(streak._date_str_to_jdn(pair[1]) - streak._date_str_to_jdn(pair[0]) == 1, "streak calendar agrees at " + pair[0])
		_check(streak._date_offset_str_from(pair[0], 1) == pair[1] and streak._date_offset_str_from(pair[1], -1) == pair[0], "date offsets preserve month/year/leap-day boundary " + pair[0])


func _set_profile(level: int, completed: String, latest: String) -> void:
	var candidate: Dictionary = game.get_core_candidate()
	candidate.profile.current_level = level
	candidate.profile.daily_completed_date = completed
	candidate.profile.max_daily_date = latest
	candidate.profile.daily_elapsed_sec = 125
	candidate.profile.daily_beat_percent = 80.0
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).get("ok", false), "calendar fixture commits through the real store")


func _test_entry_dates() -> void:
	_set_profile(20, "", yesterday)
	_check(entry.compute_state() == entry.State.LOCKED, "level 20 remains locked")
	_set_profile(21, yesterday, yesterday)
	_check(entry.compute_state() == entry.State.NORMAL, "yesterday's completion does not complete today's challenge")
	var hit := {"count":0}
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			hit.count += 1
			return true
		return false)
	entry.ensure_max_daily_advanced()
	_check(hit.count == 1 and game.get_max_daily_date() == yesterday, "failed max-date write rolls back and leaves the same update retryable")
	files.set_fault_injector_for_tests(Callable())
	entry.ensure_max_daily_advanced()
	_check(game.get_max_daily_date() == today, "next refresh can persist today's max date")
	var revision: int = game.get_core_store().revision()
	entry.ensure_max_daily_advanced()
	game.advance_max_daily_date(yesterday)
	_check(game.get_max_daily_date() == today and game.get_core_store().revision() == revision, "unchanged and older dates do not write or move the high-water date backwards")
	_set_profile(21, today, today)
	_check(entry.compute_state() == entry.State.REPLAY and entry.done_time_text() == "02:05", "current day's completed state retains its actual elapsed result")
	_set_profile(21, yesterday, tomorrow)
	_check(entry.compute_state() == entry.State.DONE, "moving local date behind the recorded high-water date keeps the existing anti-replay rule")


func _test_cached_cell() -> void:
	_set_profile(21, yesterday, today)
	var scene: PackedScene = load("res://products/meowdoku/gameplay/presentation/daily/ui/daily_challenge_entry_cell.tscn")
	var cell: Node = scene.instantiate()
	root.add_child(cell)
	cell._do_create()
	cell._do_show()
	_check(cell._state_normal.visible and not cell._state_done.visible and not cell._state_locked.visible, "real entry cell initially displays today's playable state")
	_check(cell._normal_date.text == entry.today_date_text(), "real entry uses the current localized date")
	_set_profile(21, today, today)
	await create_timer(1.1).timeout
	_check(cell._state_done.visible and cell._done_time.text == "02:05", "live cached entry refreshes completed state on its managed heartbeat")
	cell._do_hide()
	_set_profile(21, yesterday, today)
	root.get_node("ClockTicker").second_tick.emit()
	await process_frame
	_check(cell._state_done.visible and not cell._state_normal.visible, "hidden entry ignores the shared heartbeat and retains no active refresh")
	cell._do_show()
	_check(cell._state_normal.visible and not cell._state_done.visible, "reopening the same cell immediately refreshes date state and resumes its heartbeat")
	_set_profile(20, "", today)
	cell.on_show()
	_check(cell._state_locked.visible and not cell._state_normal.visible, "reusing the entry after progress reset refreshes its unlock state")
	cell._do_destroy()
	cell.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TEST_FAILED: " + message)
