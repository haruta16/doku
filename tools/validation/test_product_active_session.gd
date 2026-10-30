## 真实会话 Autoload：重复焦点、写失败、清档和同步监听不能丢失或串用前台时长。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var session: Node
var files: RefCounted
var protect: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	game = root.get_node("GameState")
	session = root.get_node("SessionManager")
	files = game.get_core_store().get("_file_store")
	protect = load("res://products/meowdoku/app/features/abtest/protect_scheme.gd")
	session._active_flush_timer.stop()
	# 只回拨这个会话的单调计时起点；不改系统时间，也不让负数撞上后台哨兵。
	await create_timer(2.1).timeout
	_test_duplicate_focus()
	_test_flush_retry(false)
	_test_flush_retry(true)
	_test_reset(false)
	_test_reset(true)
	_test_reentrant_flush()
	_test_reset_during_flush(false)
	_test_reset_during_flush(true)
	_test_pending_reset()
	_test_projection_day_boundary()
	_test_debug_session_boundary()
	files.set_fault_injector_for_tests(Callable())
	print("PRODUCT ACTIVE SESSION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _fixture() -> void:
	files.set_fault_injector_for_tests(Callable())
	_check(game.reset_all(), "fixture reset succeeds")
	session._session_active_sec = 0
	session._active_seg_start_ms = Time.get_ticks_msec()
	session._last_pause_unix = 0


func _seed_elapsed(seconds: int = 2) -> void:
	session._active_seg_start_ms = Time.get_ticks_msec() - seconds * 1000


func _test_duplicate_focus() -> void:
	_fixture()
	_seed_elapsed()
	var start: int = session._active_seg_start_ms
	var record: int = session.session_record
	var id: String = session.session_id
	session.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(session._active_seg_start_ms == start, "duplicate focus-in keeps the unflushed segment")
	_check(session.get_session_active_sec() == 2 and session.session_record == record, "duplicate focus-in neither loses time nor counts a foreground segment")
	session.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(game.get_total_active_sec() == 2 and session._active_seg_start_ms == -1, "first focus-out captures only foreground time")
	var paused: int = int(Time.get_unix_time_from_system()) - session.SESSION_REFRESH_INTERVAL_SEC - 1
	session._last_pause_unix = paused
	session.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(session._last_pause_unix == paused and game.get_total_active_sec() == 2, "duplicate focus-out preserves the first background instant")
	session.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(session.session_id != id and session.session_record == 1, "the full long background span starts exactly one new session")
	_check(session.get_session_active_sec() == 0 and game.get_total_active_sec() == 2, "background time never enters the new session's active duration")
	id = session.session_id
	session.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(session.session_id == id and session.session_record == 1, "repeated foreground notification cannot start or count another session")
	session.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	session.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(session.session_id == id and session.session_record == 2, "a genuine short background cycle retains the session and counts one segment")


func _test_flush_retry(background: bool) -> void:
	_fixture()
	_seed_elapsed()
	var hit := {"count":0}
	var observed := {"today":-1}
	var on_failed := func(_result: Dictionary) -> void: observed.today = session.get_today_active_sec()
	game.storage_failed.connect(on_failed)
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			hit.count += 1
			return true
		return false)
	if background:
		session.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	else:
		session._flush_active_segment()
	game.storage_failed.disconnect(on_failed)
	_check(hit.count == 1 and game.get_total_active_sec() == 0, "failed active-time commit leaves durable counters unchanged")
	_check(observed.today == 2, "synchronous storage-failure observer still sees the elapsed foreground time")
	_check(session.get_today_active_sec() == 2 and session.get_session_active_sec() == 2, "failed commit preserves observed foreground time for reads and retry")
	files.set_fault_injector_for_tests(Callable())
	session._flush_active_segment()
	_check(game.get_total_active_sec() == 2 and game.get_today_active_sec() == 2, "retry persists the same pending time even while backgrounded")
	session._flush_active_segment()
	_check(game.get_total_active_sec() == 2 and session.get_session_active_sec() == 2, "successful retry consumes time exactly once")
	if background:
		_check(session._active_seg_start_ms == -1, "background retry does not restart the foreground clock")


func _test_reset(fail: bool) -> void:
	_fixture()
	_seed_elapsed()
	session._session_active_sec = 60
	_check(not protect.eval_scheme("session_min_1").blocked, "actual ad protection reads the prior session's minute qualification")
	var start: int = session._active_seg_start_ms
	if fail:
		files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(game.reset_all() == not fail, "clear-data reports its actual persistence result")
	files.set_fault_injector_for_tests(Callable())
	if fail:
		_check(session._active_seg_start_ms == start and session.get_session_active_sec() == 62, "failed clear-data retains the old foreground interval and session eligibility")
		_check(not protect.eval_scheme("session_min_1").blocked, "failed clear-data preserves actual session ad protection qualification")
		session._flush_active_segment()
		_check(game.get_total_active_sec() == 2, "old interval remains persistable after a failed reset")
	else:
		_check(session.get_session_active_sec() == 0 and session.get_today_active_sec() == 0, "successful clear-data clears both captured and unflushed runtime eligibility")
		_check(protect.eval_scheme("session_min_1").blocked, "successful clear-data restores the real ad protection consumer to its new-profile state")
		session._flush_active_segment()
		_check(game.get_total_active_sec() == 0, "old foreground interval cannot be saved into the cleared profile")


func _test_reentrant_flush() -> void:
	_fixture()
	_seed_elapsed()
	var nested := {"done":false,"visible_total":-1}
	var listener := func(_revision: int) -> void:
		if nested.done:
			return
		nested.done = true
		nested.visible_total = session.get_today_active_sec()
		session._flush_active_segment()
	game.get_core_store().committed.connect(listener)
	session._flush_active_segment()
	game.get_core_store().committed.disconnect(listener)
	_check(nested.done and nested.visible_total == 2, "commit observer sees the duration once without pending double-count")
	_check(game.get_total_active_sec() == 2 and session.get_session_active_sec() == 2, "synchronous nested flush does not commit or count the same interval twice")


func _test_reset_during_flush(fail: bool) -> void:
	_fixture()
	_seed_elapsed()
	var nested := {"done":false,"ok":false}
	var listener := func(_result: Variant) -> void:
		if nested.done:
			return
		nested.done = true
		files.set_fault_injector_for_tests(Callable())
		nested.ok = game.reset_all()
	var notified: Signal = game.storage_failed if fail else game.get_core_store().committed
	if fail:
		files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	notified.connect(listener)
	session._flush_active_segment()
	notified.disconnect(listener)
	_check(nested.done and nested.ok and game.get_total_active_sec() == 0, "clear-data from the commit listener becomes the latest durable state")
	_check(session.get_session_active_sec() == 0 and session.get_today_active_sec() == 0, "old commit return cannot restore runtime duration after nested reset")
	session._flush_active_segment()
	_check(game.get_total_active_sec() == 0, "nested reset also clears the old pending retry intent")


func _test_pending_reset() -> void:
	_fixture()
	_seed_elapsed()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	session.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(session.get_today_active_sec() == 2, "background write failure leaves a retryable interval")
	_check(not game.reset_all() and session.get_today_active_sec() == 2, "failed clear-data preserves a previously pending interval")
	files.set_fault_injector_for_tests(Callable())
	_check(game.reset_all(), "background clear-data can retry successfully")
	_check(session._active_seg_start_ms == -1 and session.get_session_active_sec() == 0 and session.get_today_active_sec() == 0, "successful background clear-data drops old retry time without starting foreground accounting")
	session._flush_active_segment()
	_check(game.get_total_active_sec() == 0, "a later timer cannot restore the cleared pending interval")


func _test_debug_session_boundary() -> void:
	_fixture()
	_seed_elapsed()
	var id: String = session.session_id
	session.debug_advance_session()
	_check(session.session_id != id and session.session_record == 1, "explicit session advance changes identity once")
	_check(game.get_total_active_sec() == 2, "explicit session advance flushes the prior active segment")
	_check(session.get_session_active_sec() == 0, "new debug session cannot inherit the old unflushed foreground interval")


func _test_projection_day_boundary() -> void:
	_fixture()
	# 构造保存期间跨过午夜后的旧投影；只挪动测试状态，不改系统时钟或引入公共时钟依赖。
	var previous_day: String = root.get_node("StreakManager")._date_offset_str(-1)
	var candidate: Dictionary = game.get_core_candidate()
	candidate.profile.today_date = previous_day
	candidate.profile.today_active_sec = 600
	candidate.profile.total_active_sec = 600
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).get("ok", false), "prepare previous-day persisted activity")
	if "_flush_today_date" in session:
		session._flush_today_date = previous_day
		session._flush_today_active_sec = 602
	_check(session.get_today_active_sec() == 0, "yesterday's in-flight read projection cannot raise today's active time")
	_check(game.get_total_active_sec() == 600, "daily rollover preserves lifetime activity")
	_check(game.reset_all() and session.get_today_active_sec() == 0, "clear-data removes a previous-day projection as well")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TEST_FAILED: " + message)
