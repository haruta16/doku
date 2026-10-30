## 1.22 真实每日场景：候选提交、残局身份、无效题池和重开/隐藏边界。
extends SceneTree

var checks := 0
var failures := 0
var game: Node
var ui: Node
var ab: Node
var files: RefCounted
var fault_hits: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	game = root.get_node("GameState")
	ui = root.get_node("UIManager")
	ab = root.get_node("ABTestManager")
	files = game.get_core_store().get("_file_store")
	_check(game.reset_all(), "isolated daily player resets")
	game.set_sound_on(false)
	game.set_music_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(31)
	ab.dc_level.set_debug_override(0)
	ab.dc_costume.set_debug_override(0)
	ab.dc_start_toast.set_debug_override(0)
	ab.dc_endgame_save.set_debug_override(2)
	var candidate: Dictionary = game.get_core_candidate()
	candidate.endgame.stats.main_id = "preserve-main-id"
	candidate.endgame.stats.main_total = {"hint_used_total": 4}
	candidate.profile.daily_started_date = "2026-01-01"
	candidate.endgame.stats.daily_id = "previous-daily-id"
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).get("ok", false), "daily metadata fixture commits")
	var before: Dictionary = game.get_core_candidate()
	_fail_writes(true)
	var page: Variant = ui.show_ui("daily_game", {})
	await create_timer(0.4).timeout
	_check(fault_hits > 0, "daily entry failure reaches injected before_replace storage fault")
	_check(page._entry_error.get("error") != "selection_conflict", "daily entry failure is not unrelated candidate conflict")
	_check(page != null and not page._entry_ready, "failed initial daily commit cannot open board")
	_check(game.get_daily_started_date() == before.profile.daily_started_date, "failed entry preserves started date")
	_check(game.get_persisted_game_id("daily") == "previous-daily-id", "failed entry preserves tracking identity")
	_check(game.get_core_candidate().endgame.daily_snapshot == before.endgame.daily_snapshot, "failed entry preserves previous daily checkpoint")
	_fail_writes(false)
	await _close()
	page = ui.show_ui("daily_game", {})
	await _wait_ready(page)
	_check(page._entry_ready, "real 1.22 daily scene starts after retry")
	if not page._entry_ready:
		_finish()
		return
	var round_id: String = page._business_session.round_id()
	_check(not round_id.is_empty() and game.get_daily_started_date() == Time.get_date_string_from_system(), "daily board and date own one durable round")
	_check(game.get_core_candidate().endgame.stats.main_id == "preserve-main-id" and game.get_core_candidate().endgame.stats.main_total.hint_used_total == 4, "daily entry preserves main-mode identity and statistics")
	page._entry_anim_playing = false
	var column: int = page._puzzle_sol_1d()[0]
	var placed: Dictionary = page._execute_business_action("place_cat", {"row": 0, "col": column})
	_check(placed.get("ok", false), "daily first cat commits through round service")
	if placed.get("ok", false):
		page._accept_business_model(placed)
		page._flush_endgame_snapshot()
	_check(game.get_daily_endgame_snapshot().get("placed_cats", []).has([0, column]), "daily checkpoint contains committed cat")
	_check(game.get_daily_endgame_snapshot().get("business_round_id", "") == round_id, "daily checkpoint owns exact round identity")
	await _close()
	page = ui.show_ui("daily_game", {})
	await _wait_ready(page)
	_check(page._entry_ready and not page._dc_restore_snapshot.is_empty(), "ALL_DAY restores real checkpoint")
	_check(page._business_session.round_id() == round_id and page._board_view.count_cat_cells() == 1, "restore keeps durable round and committed board")
	await _close()
	var snapshot: Dictionary = game.get_daily_endgame_snapshot().duplicate(true)
	snapshot.session_id = "another-session"
	_check(game.set_daily_endgame_snapshot(snapshot), "different-session fixture persists")
	ab.dc_endgame_save.set_debug_override(1)
	page = ui.show_ui("daily_game", {})
	await _wait_ready(page)
	_check(page._entry_ready and page._dc_restore_snapshot.is_empty(), "SAME_SESSION refuses previous session and starts fresh")
	_check(page._business_session.round_id() != round_id and page._board_view.count_cat_cells() == 0, "fresh daily start cannot reuse previous restored round")
	await _close()
	ab.dc_endgame_save.set_debug_override(0)
	var original_pool: Array = BankData.get_levels(10, 3)
	BankData._cache["10_3"] = [{"regionMap": [], "solution": []}]
	before = game.get_core_candidate()
	page = ui.show_ui("daily_game", {})
	await process_frame
	_check(not page._entry_ready and not page._board_view.visible, "all-invalid pool refuses entry without indexing an invalid board")
	_check(game.get_core_candidate().round_services == before.round_services and game.get_daily_endgame_snapshot() == before.endgame.daily_snapshot, "invalid pool preserves previous round/checkpoint")
	BankData._cache["10_3"] = original_pool
	await _close()
	before = game.get_core_candidate()
	page = ui.show_ui("daily_game", {})
	ui.hide_ui("daily_game")
	await create_timer(0.4).timeout
	_check(not page._entry_ready and game.get_core_candidate().round_services == before.round_services, "hide during layout cancels old entry before durable start")
	var generation: int = page._business_generation
	page = ui.show_ui("daily_game", {})
	await _wait_ready(page)
	_check(page._entry_ready and page._business_generation != generation, "cached daily page reopens in a new generation")
	await _test_settlement(page)
	page._do_destroy()
	_check(not page._entry_ready and page._business_generation != generation, "destroy invalidates daily callbacks immediately")
	_finish()


func _test_settlement(page: Variant) -> void:
	page._entry_anim_playing = false
	var solution: Array = page._puzzle_sol_1d()
	for row: int in solution.size():
		var placed: Dictionary = page._execute_business_action("place_cat", {"row": row, "col": int(solution[row])})
		_check(placed.get("ok", false), "solved daily board commits cat %d" % row)
		if placed.get("ok", false):
			page._accept_business_model(placed)
	page._flush_endgame_snapshot()
	var identity: String = page._business_settlement_id()
	var runtime: Dictionary = page._business_runtime()
	var context: Dictionary = page._daily_settlement_context()
	var before: Dictionary = game.get_core_candidate()
	_fail_writes(true)
	await page._on_game_win()
	_check(fault_hits > 0 and page._settlement_pending and not page._is_complete, "daily win storage failure retains board and exposes actual retry dialog")
	var failed: Dictionary = game.get_core_candidate()
	_check(failed.profile == before.profile and failed.features == before.features and failed.endgame.daily_snapshot == before.endgame.daily_snapshot, "failed daily win changes neither progress, feature rewards nor checkpoint")
	_fail_writes(false)
	var dialog: Variant = page._settlement_retry_dialog
	_check(dialog != null and dialog._on_confirm.is_valid(), "daily win failure has a live retry action")
	if dialog == null:
		return
	dialog._on_action_btn_pressed()
	var after: Dictionary = game.get_core_candidate()
	_check(page._is_complete and not page._settlement_pending, "actual retry callback commits terminal daily result")
	_check(after.profile.today_played_count == before.profile.today_played_count + 1, "successful daily win counts exactly one finished game")
	_check(after.profile.today_cat_found == int(before.profile.today_cat_found) + int(context.today_cat_delta) and after.profile.today_mark_placed == int(before.profile.today_mark_placed) + int(context.today_mark_delta), "daily cat and mark totals commit once with result")
	_check(after.features.streak.last_checkin_date == Time.get_date_string_from_system() and int(after.features.streak.get("current_streak", 0)) == int(before.features.streak.get("current_streak", 0)) + 1, "daily win checks in once in the same durable result")
	_check(after.endgame.daily_snapshot.is_empty() and after.profile.daily_completed_date == page._start_date, "daily win clears checkpoint only with completed date")
	_check(after.features.rank_activity == before.features.rank_activity, "daily settlement leaves main-only ranking unchanged")
	var revision: int = game.get_core_store().revision()
	var duplicate: Dictionary = game.settle_daily_round(identity, page._start_date, "win", page._terminal_elapsed_sec, float(page._level_config.beat_percent), runtime, context)
	_check(duplicate.get("ok", false) and duplicate.get("duplicate", false), "repeated daily result returns existing receipt")
	_check(game.get_core_store().revision() == revision and game.get_core_candidate() == after, "duplicate daily result writes nothing and cannot repeat statistics or streak")


func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while not page._entry_ready and page._entry_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame


func _close() -> void:
	ui.hide_ui("daily_game")
	await create_timer(0.4).timeout


func _fail_writes(enabled: bool) -> void:
	if not enabled:
		files.set_fault_injector_for_tests(Callable())
		return
	fault_hits = 0
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			fault_hits += 1
			return true
		return false
	)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TEST_FAILED: " + message)


func _finish() -> void:
	_fail_writes(false)
	ui.hide_all()
	for name: String in ["game", "daily_game", "confirm"]:
		await ui.destroy_ui(name)
	await process_frame
	await process_frame
	print("DAILY 1.22 TRANSACTION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
