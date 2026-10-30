## 跨日资格与同步库存观察者：失败重试不能错误续签，嵌套提交不重复发布库存。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var streak: Node
var files: RefCounted


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	game = root.get_node("GameState")
	streak = root.get_node("StreakManager")
	files = game.get_core_store().get("_file_store")
	root.get_node("ABTestManager").daily_streak.set_debug_override(1)
	_test_inventory_observer()
	_test_inventory_nested_failure()
	_test_inventory_nested_preference()
	_test_streak_after_failed_continuity()
	_test_continuity_watch_retry()
	_test_direct_checkin_dates()
	_test_notify_win_retry()
	_test_switch_consumption()
	_test_switch_gift_retry()
	_test_reset_runtime()
	files.set_fault_injector_for_tests(Callable())
	print("STORAGE NOTIFICATION STREAK TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_inventory_observer() -> void:
	var before: Dictionary = game.get_core_candidate()
	var events: Array = []
	var nested := {"done": false, "ok": false}
	var observer := func(kind: String, count: int) -> void:
		events.append([kind, count])
		if kind == "locate" and not nested.done:
			nested.done = true
			nested.ok = game.set_tool_count("hint", int(before.inventory.hint) + 3)
	game.tool_count_changed.connect(observer)
	var next: Dictionary = before.duplicate(true)
	next.inventory.locate += 1
	next.inventory.hint += 2
	var committed: Dictionary = game.commit_core_candidate(next, game.get_core_store().revision())
	game.tool_count_changed.disconnect(observer)
	_check(committed.get("ok", false) and nested.ok, "outer and synchronous nested inventory commits both succeed")
	_check(game.get_tool_count("hint") == int(before.inventory.hint) + 3, "nested commit remains the latest inventory authority")
	_check(events.count(["hint", int(before.inventory.hint) + 3]) == 1, "nested final hint balance is published once")
	_check(events.size() == 2, "observers receive one effective update per changed inventory kind")


func _test_streak_after_failed_continuity() -> void:
	var prior := {"current_streak": 6, "best_streak": 6, "reward_cycle_day": 6,
		"last_checkin_date": streak._date_offset_str(-2), "streak_start_weekday": 1,
		"last_group": 1, "pending_switch_page": 0}
	_check(game.commit_streak_data(prior), "prepare a six-day streak interrupted by a missed day")
	var before: Dictionary = game.get_core_store().snapshot()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	streak._check_continuity()
	_check(game.get_streak_data().current_streak == 6, "failed continuity reset preserves durable data")
	files.set_fault_injector_for_tests(Callable())
	var result: Dictionary = streak.do_checkin()
	var after: Dictionary = game.get_core_store().snapshot()
	_check(result.get("ok", false), "checkin can retry after a failed continuity write")
	_check(game.get_streak_data().current_streak == 1 and game.get_streak_data().reward_cycle_day == 1, "today starts a new streak despite the missed reset")
	_check(game.get_streak_data().best_streak == 6, "new streak preserves historical best")
	_check(not result.get("has_reward", true) and after.award_sequence == before.award_sequence, "a missed day cannot incorrectly qualify as the seventh-day reward")
	var revision: int = game.get_core_store().revision()
	_check(streak.do_checkin().get("duplicate", false), "same-day retry is idempotent")
	_check(game.get_core_store().revision() == revision, "same-day retry does not write again")


func _test_inventory_nested_failure() -> void:
	var before: Dictionary = game.get_core_candidate()
	var events: Array = []
	var nested := {"done": false, "ok": true}
	var observer := func(kind: String, count: int) -> void:
		events.append([kind, count])
		if kind == "locate" and not nested.done:
			nested.done = true
			files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
			nested.ok = game.set_tool_count("hint", int(before.inventory.hint) + 3)
			files.set_fault_injector_for_tests(Callable())
	game.tool_count_changed.connect(observer)
	var next: Dictionary = before.duplicate(true)
	next.inventory.locate += 1
	next.inventory.hint += 2
	var committed: Dictionary = game.commit_core_candidate(next, game.get_core_store().revision())
	game.tool_count_changed.disconnect(observer)
	_check(committed.get("ok", false) and not nested.ok, "failed nested write does not invalidate the outer completed commit")
	_check(events == [["locate", int(next.inventory.locate)], ["hint", int(next.inventory.hint)]], "failed nested write publishes neither a false value nor a duplicate")
	_check(game.get_tool_count("hint") == int(next.inventory.hint), "failed nested write restores the outer authoritative inventory")


func _test_inventory_nested_preference() -> void:
	var before: Dictionary = game.get_core_candidate()
	var events: Array = []
	var nested := {"done": false, "ok": false}
	var observer := func(kind: String, count: int) -> void:
		events.append([kind, count])
		if kind == "locate" and not nested.done:
			nested.done = true
			nested.ok = game.set_sound_on(not game.is_sound_on())
	game.tool_count_changed.connect(observer)
	var next: Dictionary = before.duplicate(true)
	next.inventory.locate += 1
	next.inventory.hint += 2
	var committed: Dictionary = game.commit_core_candidate(next, game.get_core_store().revision())
	game.tool_count_changed.disconnect(observer)
	_check(committed.get("ok", false) and nested.ok, "unrelated nested preference commit succeeds")
	_check(events == [["locate", int(next.inventory.locate)], ["hint", int(next.inventory.hint)]], "nested preference commit still publishes the outer not-yet-notified balance once")


func _test_continuity_watch_retry() -> void:
	_prepare_streak(-2)
	streak._last_seen_jdn = 0
	streak._next_continuity_retry_msec = 0
	streak._pending_show_uid = 0
	var writes := {"count": 0}
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			writes.count += 1
			return true
		return false)
	streak._on_day_watch_tick()
	_check(streak._last_seen_jdn == 0 and streak._pending_show_uid == 0, "failed day watch preserves the retry date and pending presentation")
	_check(game.get_streak_data().current_streak == 6, "failed day watch does not publish an unsaved continuity reset")
	streak._on_day_watch_tick()
	streak._on_day_watch_tick()
	_check(writes.count == 1 and streak._next_continuity_retry_msec > Time.get_ticks_msec(), "failed background reset cools down instead of writing on each heartbeat")
	files.set_fault_injector_for_tests(Callable())
	streak._next_continuity_retry_msec = Time.get_ticks_msec() - 1
	streak._on_day_watch_tick()
	_check(streak._last_seen_jdn == streak._today_jdn() and streak._pending_show_uid == -1, "next successful day watch completes and consumes its reset")
	_check(game.get_streak_data().current_streak == 0 and game.get_streak_data().best_streak == 6, "day watch reset preserves historical best")
	var revision: int = game.get_core_store().revision()
	streak._on_day_watch_tick()
	streak._check_continuity()
	_check(game.get_core_store().revision() == revision, "completed continuity reset does not keep rewriting the same state")


func _test_direct_checkin_dates() -> void:
	_prepare_streak(-2)
	var sequence: int = game.get_core_store().snapshot().award_sequence
	var missed: Dictionary = streak.do_checkin()
	_check(missed.get("ok", false) and not missed.get("has_reward", true), "checkin applies a missed day even before the watch callback runs")
	_check(game.get_streak_data().current_streak == 1 and game.get_core_store().snapshot().award_sequence == sequence, "direct missed-day checkin starts day one without an award")
	_prepare_streak(-1)
	var continued: Dictionary = streak.do_checkin()
	_check(continued.get("ok", false) and continued.get("has_reward", false), "yesterday's sixth day legitimately earns the seventh-day reward")
	_check(game.get_streak_data().current_streak == 7 and game.get_streak_data().best_streak == 7, "continuous checkin preserves existing streak rules")
	_check(not game.find_in_flight_award(streak.get_pending_show_uid()).is_empty(), "seventh-day reward qualification is durable and still pending")
	var revision: int = game.get_core_store().revision()
	_check(streak.do_checkin().get("duplicate", false) and game.get_core_store().revision() == revision, "repeated seventh-day checkin cannot register another award")


func _test_switch_consumption() -> void:
	var candidate: Dictionary = game.get_core_candidate()
	candidate.features.streak["pending_switch_page"] = 3
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).get("ok", false), "prepare pending switch presentation")
	streak._pending_switch_eligible = true
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not streak.consume_pending_switch(), "failed switch consumption reports failure")
	_check(streak.get_pending_switch_page() == 3 and game.get_streak_data().pending_switch_page == 3, "failed switch consumption retains runtime and durable eligibility")
	files.set_fault_injector_for_tests(Callable())
	_check(streak.consume_pending_switch(), "switch consumption can retry")
	_check(streak.get_pending_switch_page() == 0 and game.get_streak_data().pending_switch_page == 0, "successful switch consumption removes both eligibility projections")


func _test_notify_win_retry() -> void:
	_prepare_streak(-1)
	_check(game.set_tutorial_done(true), "win-triggered checkin fixture is unlocked")
	streak._next_continuity_retry_msec = Time.get_ticks_msec() + 30_000
	var skipped: Dictionary = streak.notify_win(&"unrelated")
	_check(skipped.get("ok", false) and skipped.get("skipped", false), "unqualified win explicitly succeeds without a checkin")
	var before: Dictionary = game.get_core_store().snapshot()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failed: Dictionary = streak.notify_win(&"main")
	_check(not failed.get("ok", true) and failed.get("error") == "write_failed" and not failed.get("has_reward", true), "win-triggered checkin returns its actual write failure")
	_check(game.get_core_store().snapshot() == before and streak.can_checkin_today(), "failed win-triggered checkin retains its qualification for explicit retry")
	files.set_fault_injector_for_tests(Callable())
	var retried: Dictionary = streak.notify_win(&"main")
	_check(retried.get("ok", false) and retried.get("has_reward", false), "win-triggered checkin can retry and earn its award")
	_check(streak._next_continuity_retry_msec == 0, "explicit checkin bypasses and clears background retry cooldown")
	var revision: int = game.get_core_store().revision()
	_check(streak.notify_win(&"main").get("duplicate", false) and game.get_core_store().revision() == revision, "successful win-triggered checkin remains idempotent")


func _prepare_streak(offset: int) -> void:
	var candidate: Dictionary = game.get_core_candidate()
	candidate.features.streak = {"current_streak": 6, "best_streak": 6, "reward_cycle_day": 6,
		"last_checkin_date": streak._date_offset_str(offset), "streak_start_weekday": 1,
		"last_group": 1, "pending_switch_page": 0}
	candidate.claims.erase("streak/checkin/" + streak._today_str())
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).get("ok", false), "prepare isolated date-boundary state")


func _test_switch_gift_retry() -> void:
	var before: Dictionary = game.get_core_candidate()
	var next: Dictionary = game.get_streak_data()
	next["last_group"] = 3
	next["pending_switch_page"] = 1
	var registered: Dictionary = game.commit_streak_transition(next, [{"kind": "hint", "count": 2}], "test_switch_retry")
	_check(registered.get("ok", false), "switch gift qualification is registered")
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not streak.grant_switch_gift(), "failed switch gift reports failure to its page")
	_check(not game.find_in_flight_award(registered.uid).is_empty() and game.get_tool_count("hint") == before.inventory.hint, "failed switch gift preserves its pending award without adding inventory")
	files.set_fault_injector_for_tests(Callable())
	_check(streak.grant_switch_gift(), "switch gift can retry in the same process")
	_check(streak.grant_switch_gift() and game.get_tool_count("hint") == int(before.inventory.hint) + 2, "switch gift retry cannot grant twice")
	_check(game.find_in_flight_award(registered.uid).is_empty(), "successful switch gift removes the pending qualification")


func _test_reset_runtime() -> void:
	var previous := {"_session_played_count": 3, "_session_consecutive_wins": 2,
		"_session_reward_view_count": 5, "_has_won_since_cold_start": true,
		"_daily_first_easy_available": true, "_daily_first_easy_evaluated": true,
		"_fail_text_revive_x": {"fixture": 1}}
	for key: String in previous:
		game.set(key, previous[key])
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not game.reset_all(), "runtime reset still depends on successful durable reset")
	for key: String in previous:
		_check(game.get(key) == previous[key], "failed reset preserves runtime " + key)
	files.set_fault_injector_for_tests(Callable())
	_check(game.reset_all(), "runtime reset can retry")
	_check(game.get_session_played_count() == 0 and game.get_session_consecutive_wins() == 0 and game.get_session_reward_view_count() == 0, "successful reset clears session counters")
	_check(not game.has_won_since_cold_start() and not game._daily_first_easy_available and not game._daily_first_easy_evaluated, "successful reset clears prior eligibility caches")
	_check(game._fail_text_revive_x.is_empty(), "successful reset clears cached round failure presentation")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("TEST_FAILED: " + label)
