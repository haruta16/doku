## 真实页面入场：内容失败、落盘失败和布局等待中取消均不得提前消耗资格或丢失旧题。
extends SceneTree

var failures: int = 0
var checks: int = 0
var state: Node
var ui: Node
var ab: Node
var files: RefCounted
var content: GDScript


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	state = root.get_node("GameState")
	ui = root.get_node("UIManager")
	ab = root.get_node("ABTestManager")
	files = state.get_core_store().get("_file_store")
	content = load("res://scripts/framework/content/content_context.gd")
	state.set_sound_on(false) # 频繁取消入场仅测事务，避免测试退出时音效仍在播放。
	var levels: GDScript = load("res://products/meowdoku/gameplay/application/level_data.gd")
	ab.daily_first_level_difficulty.set_debug_override(1)
	ab.rule_normal_rank.set_debug_override(1)
	ab.normal_endgame_save.set_debug_override(1)
	var hard_level: int = 1
	while not levels.is_hard_level(hard_level):
		hard_level += 1
	_prepare(hard_level)
	content.report_content_error("doku/levels/test", "test_entry_read_failed")
	var page: Variant = ui.show_ui("game", {"level_index": hard_level})
	await process_frame
	_check(not page._entry_error.is_empty(), "content error blocks hard-level entry")
	_check(_saved().profile.daily_first_easy_date == "", "failed hard-level entry does not consume today's opportunity")
	_check(state.is_daily_first_easy_available(), "failed entry retains evaluated qualification")
	await _close()
	content.publish(null)
	var entry_date: String = Time.get_date_string_from_system()
	page = ui.show_ui("game", {"level_index": hard_level})
	await create_timer(0.1).timeout
	_check(page._entry_error.is_empty() and not page._entry_preparing, "hard level can retry successfully")
	# 异步入场可能跨午夜；保存日期属于本次调用覆盖的日期，而非断言时刻的新一天。
	_check(_saved().profile.daily_first_easy_date in [entry_date, Time.get_date_string_from_system()], "successful hard level consumes daily opportunity")
	_check(not state.is_current_level_daily_first_easy(), "hard level does not pretend its difficulty was reduced")
	_check(_saved().endgame.stats.main_id != "entry-prior-id", "ready main entry commits a new tracking identity")
	_check(_saved().endgame.stats.main_total.is_empty() and _saved().endgame.stats.main_round.is_empty(), "ready main entry resets statistics in the same commit")
	_check(root.get_node("Tracker").get_game_id() == _saved().endgame.stats.main_id, "tracker publishes only the committed main identity")
	await _close()

	# 建立尚未操作的有效旧题，模拟隔天重新进入。
	ab.daily_first_level_difficulty.set_debug_override(0)
	_prepare(1)
	state.set("_daily_first_easy_evaluated", true)
	page = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.1).timeout
	_check(page._entry_error.is_empty(), "unused old puzzle fixture starts")
	await _close()
	_rearm_daily()
	ab.daily_first_level_difficulty.set_debug_override(1)
	var before: Dictionary = _saved()
	content.report_content_error("doku/levels/test", "test_entry_read_failed")
	page = ui.show_ui("game", {"level_index": 1})
	await process_frame
	_assert_old_entry(before, "content failure")
	await _close()
	content.publish(null)

	page = ui.show_ui("game", {"level_index": 1})
	ui.hide_ui("game") # on_show 尚停在首次布局等待中。
	await create_timer(0.4).timeout
	_assert_old_entry(before, "entry cancelled during layout")

	_fail_writes(true)
	page = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.1).timeout
	_check(page._entry_error.get("error") == "selection_commit_failed", "new selection reports failed entry transaction")
	_assert_old_entry(before, "selection write failure")
	_check(state.is_daily_first_easy_available(), "failed selection keeps daily opportunity retryable")
	await _close()
	_fail_writes(false)
	entry_date = Time.get_date_string_from_system()
	page = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.1).timeout
	_check(page._entry_error.is_empty() and not page._entry_preparing, "fresh daily puzzle retries successfully")
	_check(_saved().profile.daily_first_easy_date in [entry_date, Time.get_date_string_from_system()], "fresh puzzle commits daily date")
	_check(_saved().endgame.snapshot.regionMap == page._puzzle.regions, "new checkpoint matches prepared board")
	_check(_saved().profile.saved_game_auto_mark == page._gameplay_policy.auto_mark_variant, "entry metadata commits with selected puzzle")
	await _close()

	# 有操作的残局优先恢复，但资格评估本身不能落盘。
	_rearm_daily()
	var candidate: Dictionary = state.get_core_candidate()
	var snapshot: Dictionary = candidate.endgame.snapshot
	var mark: Array = []
	for row: int in range(int(snapshot.size)):
		for column: int in range(int(snapshot.size)):
			if not snapshot.placed_cats.has([row, column]):
				mark = [row, column]
				break
		if not mark.is_empty():
			break
	snapshot.marks = [mark]
	candidate.endgame.snapshot = snapshot
	candidate.round_runtime.current_level_dirty = true
	_check(state.commit_core_candidate(candidate, state.get_core_store().revision()).get("ok", false), "progressed checkpoint fixture commits")
	before = _saved()
	state.evaluate_daily_first_easy()
	_check(not state.is_daily_first_easy_available(), "progressed checkpoint disables difficulty replacement")
	_check(_saved().profile.daily_first_easy_date == "", "eligibility evaluation does not consume persistent date")
	_fail_writes(true)
	page = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.1).timeout
	_check(page._is_endgame_restore_session and page._entry_error.get("error") == "entry_commit_failed", "restored entry reports metadata write failure")
	_assert_old_entry(before, "restored entry write failure")
	await _close()
	_fail_writes(false)
	page = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.1).timeout
	_check(page._is_endgame_restore_session and page._entry_error.is_empty(), "progressed checkpoint retries as restoration")
	_check(_saved().profile.daily_first_easy_date == Time.get_date_string_from_system(), "ready restored entry consumes daily date")
	_check(page._puzzle.regions == before.endgame.snapshot.regionMap, "restored entry retains its puzzle")
	_check(page._board_view.count_mark_cells() >= 1, "restored entry retains saved player marks")
	_check(state.is_current_level_dirty(), "restoration preserves the round's dirty status")
	await _close()
	await _daily_entry_transaction()
	print("GAME ENTRY TRANSACTION: checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _prepare(level: int) -> void:
	var candidate: Dictionary = state.get_core_candidate()
	candidate.profile.current_level = level
	candidate.profile.current_strategy = 1
	candidate.profile.tutorial_done = true
	candidate.profile.daily_first_easy_date = ""
	candidate.profile.retry_puzzle_level = 0
	candidate.profile.retry_puzzle_params = {}
	candidate.profile.saved_game_auto_mark = -1
	candidate.endgame.snapshot = {}
	candidate.endgame.stats.main_total = {"hint_used_total": 9}
	candidate.endgame.stats.main_round = {"hint_used": 4}
	candidate.endgame.stats.main_id = "entry-prior-id"
	candidate.round_runtime.is_daily_first_easy_level = false
	_check(state.commit_core_candidate(candidate, state.get_core_store().revision()).get("ok", false), "entry fixture commits")
	state.set("_daily_first_easy_available", false)
	state.set("_daily_first_easy_evaluated", false)


func _rearm_daily() -> void:
	var candidate: Dictionary = state.get_core_candidate()
	candidate.profile.daily_first_easy_date = ""
	candidate.profile.saved_game_auto_mark = -1
	_check(state.commit_core_candidate(candidate, state.get_core_store().revision()).get("ok", false), "new-day fixture commits")
	state.set("_daily_first_easy_available", false)
	state.set("_daily_first_easy_evaluated", false)


func _saved() -> Dictionary:
	return state.get_core_store().snapshot()


func _assert_old_entry(before: Dictionary, context: String) -> void:
	var after: Dictionary = _saved()
	for field: String in ["daily_first_easy_date", "retry_puzzle_level", "retry_puzzle_params", "bank_progress", "main_bank_progress", "saved_game_auto_mark"]:
		_check(after.profile.get(field) == before.profile.get(field), context + " preserves " + field)
	_check(after.endgame.snapshot == before.endgame.snapshot, context + " preserves previous checkpoint")
	_check(after.round_runtime.current_level_dirty == before.round_runtime.current_level_dirty, context + " preserves round dirty status")
	for field: String in ["main_total", "main_round", "main_id"]:
		_check(after.endgame.stats[field] == before.endgame.stats[field], context + " preserves tracking " + field)


func _daily_entry_transaction() -> void:
	ab.game_auto_mark.set_debug_override(0)
	ab.dc_level.set_debug_override(0)
	var candidate: Dictionary = state.get_core_candidate()
	candidate.profile.daily_started_date = ""
	candidate.profile.saved_game_auto_mark = -1
	candidate.endgame.stats.daily_total = {"hint_used_total": 7}
	candidate.endgame.stats.daily_round = {"hint_used": 3}
	candidate.endgame.stats.daily_id = "daily-prior-id"
	_check(state.commit_core_candidate(candidate, state.get_core_store().revision()).get("ok", false), "daily fixture commits")
	var before: Dictionary = _saved()
	content.report_content_error("doku/levels/test", "test_entry_read_failed")
	var page: Variant = ui.show_ui("daily_game")
	await process_frame
	_check(page._puzzle.is_empty(), "daily content failure rejects puzzle preparation")
	_assert_daily_entry(before, "daily content failure")
	ui.hide_ui("daily_game")
	await create_timer(0.4).timeout
	content.publish(null)
	page = ui.show_ui("daily_game")
	ui.hide_ui("daily_game")
	await create_timer(0.4).timeout
	_assert_daily_entry(before, "daily cancelled before first layout")
	page = ui.show_ui("daily_game")
	await process_frame
	ui.hide_ui("daily_game")
	await create_timer(0.4).timeout
	_assert_daily_entry(before, "daily cancelled before second layout")
	_fail_writes(true)
	page = ui.show_ui("daily_game")
	await create_timer(0.1).timeout
	_check(not page._board_view.visible and page._clock_timer.is_stopped(), "daily commit failure keeps the board locked and clock stopped")
	_assert_daily_entry(before, "daily commit failure")
	_check(root.get_node("Tracker").get_game_id() == "daily-prior-id", "failed daily commit does not publish a new tracker identity")
	_check(root.get_node("Tracker").get_stat("hint_used") == 3, "failed daily commit does not clear live tracker statistics")
	ui.hide_ui("daily_game")
	await create_timer(0.4).timeout
	_fail_writes(false)
	page = ui.show_ui("daily_game")
	await create_timer(0.1).timeout
	_check(page._stat_status == "new" and page._board_view.visible, "first successful daily entry is still NEW")
	_check(_saved().profile.daily_started_date == Time.get_date_string_from_system(), "successful daily entry commits today's date")
	_check(_saved().endgame.stats.daily_id != "daily-prior-id", "successful daily entry commits a new identity")
	_check(_saved().endgame.stats.daily_total.is_empty() and _saved().endgame.stats.daily_round.is_empty(), "successful daily entry commits empty new-round statistics")
	_check(root.get_node("Tracker").get_game_id() == _saved().endgame.stats.daily_id and root.get_node("Tracker").get_stat("hint_used") == 0, "daily tracker matches the successful commit")
	var daily_id: String = _saved().endgame.stats.daily_id
	ui.hide_ui("daily_game")
	await create_timer(0.4).timeout
	page = ui.show_ui("daily_game")
	await create_timer(0.1).timeout
	_check(page._stat_status == "continue" and _saved().endgame.stats.daily_id == daily_id, "same-day continuation retains tracking identity")
	ui.hide_ui("daily_game")
	await create_timer(0.4).timeout


func _assert_daily_entry(before: Dictionary, context: String) -> void:
	var after: Dictionary = _saved()
	for field: String in ["daily_started_date", "saved_game_auto_mark"]:
		_check(after.profile[field] == before.profile[field], context + " preserves " + field)
	for field: String in ["daily_total", "daily_round", "daily_id"]:
		_check(after.endgame.stats[field] == before.endgame.stats[field], context + " preserves " + field)


func _close() -> void:
	ui.hide_ui("game")
	await create_timer(0.4).timeout


func _fail_writes(enabled: bool) -> void:
	files.set_fault_injector_for_tests((func(phase: String) -> bool: return phase == "before_replace") if enabled else Callable())


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TEST_FAILED: " + message)
