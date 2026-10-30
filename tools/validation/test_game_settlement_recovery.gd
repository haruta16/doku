## 真实终局写失败：不能继续零命对局或丢掉完成盘面，必须有可点击的重试路径。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
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
	files = game.get_core_store().get("_file_store")
	var ab: Node = root.get_node("ABTestManager")
	ab.dc_level.set_debug_override(0)
	ab.auto_x_fill_mode.set_debug_override(0)
	ab.win_toast.set_debug_override(0)
	ab.dc_start_toast.set_debug_override(0)
	ab.dc_endgame_save.set_debug_override(0)
	ab.daily_streak_success_page.set_debug_override(0)
	for mode: String in ["game", "daily_game"]:
		for outcome: String in ["win", "fail"]:
			await _test_terminal_retry(mode, outcome)
	await _test_abandoned_retry()
	await _test_win_checkin_retry(false)
	await _test_win_checkin_retry(true)
	ui.hide_all()
	for name: String in ["game", "daily_game", "home", "confirm", "fail", "daily_fail", "streak"]:
		await ui.destroy_ui(name)
	await process_frame
	await process_frame
	print("GAME SETTLEMENT RECOVERY TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _open(mode: String) -> Variant:
	ui.hide_all()
	await create_timer(0.1).timeout
	game.reset_all()
	game.set_sound_on(false)
	game.set_music_on(false)
	game.set_tutorial_done(true)
	var page: Variant = ui.show_ui(mode, {"level_index": 1} if mode == "game" else {})
	await _wait_ready(page)
	page._on_appear_animation_finished()
	_check(page._ensure_business_round().get("ok", false), mode + " prepares a durable active round")
	return page


func _test_terminal_retry(mode: String, outcome: String) -> void:
	var page: Variant = await _open(mode)
	page._stat_start_ms -= 10000
	if mode == "daily_game" and outcome == "win":
		page._start_unix -= 1000.0
	if outcome == "win":
		var size: int = page._level_config.size
		for row: int in size:
			for column: int in size:
				page._board_view.get_board_state().set_cell_state(row, column, CellState.CAT if page._puzzle.solution[row][column] else CellState.EMPTY)
		page._board_view.refresh_from_model()
	else:
		page._lives = 0
	var before: Dictionary = game.get_core_store().snapshot()
	var time_before: int = game.get_game_total_stat("main" if mode == "game" else "daily", "time_total")
	page._build_game_end_params("quit")
	page._build_game_end_params("quit")
	_check(game.get_game_total_stat("main" if mode == "game" else "daily", "time_total") == time_before, "building an end request has no statistics side effects")
	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("fr")
	_fail(true)
	if outcome == "win":
		await page._on_game_win()
	else:
		await page._on_game_fail()
	_check(fault_hits > 0, "terminal failure reaches injected before_replace storage fault")
	var dialog: Variant = ui.get_ui("confirm")
	_check(dialog != null and dialog.is_showing(), mode + " " + outcome + " exposes retry after failed terminal commit")
	if dialog != null:
		_check(dialog.get_node("Root/Content/DialogRoot/ActionButton").btn_text == "Réessayer", "terminal recovery uses the existing French retry translation")
	TranslationServer.set_locale(previous_locale)
	_check(not page._is_complete and game.get_core_store().snapshot() == before, "failed terminal commit publishes no outcome")
	_check(page._clock_timer.is_stopped() and page._board_view.mouse_filter == Control.MOUSE_FILTER_IGNORE, "terminal retry pauses clock and board input")
	if dialog != null and dialog.is_showing():
		dialog.get_node("Root/Content/DialogRoot/ActionButton").tag_pressed.emit()
		await create_timer(0.4).timeout
		_check(dialog.is_showing() and not page._is_complete, "another failed retry remains actionable after old close animation")
		_fail(false)
		var first_score: float = float(page._level_config.get("beat_percent", 0.0))
		# 修改运行中实验不能重算此前已经捕获的终局分数。
		root.get_node("ABTestManager").dc_beat_percent.set_debug_override(1)
		dialog.get_node("Root/Content/DialogRoot/ActionButton").tag_pressed.emit()
		dialog.get_node("Root/Content/DialogRoot/ActionButton").tag_pressed.emit()
		await create_timer(0.1).timeout
		_check(page._is_complete, "real retry button completes terminal save")
		var saved: Dictionary = game.get_core_store().snapshot()
		var record: Dictionary = saved.round_services["doku/main" if mode == "game" else "doku/daily"]
		_check(record.status == ("settled" if outcome == "win" else "active"), "win closes host and failure retains revivable host")
		_check(game.get_current_level() == (2 if mode == "game" and outcome == "win" else 1), "retry advances main progress exactly once")
		if mode == "game":
			_check(game.get_game_total_stat("main", "time_total") == time_before + 10, "failed terminal retries do not double-count or extend end time")
		if outcome == "fail":
			page._on_revive_requested()
			_check(not page._like_hand_state.clock_paused and not page._is_complete and page._lives > 0, "revive after terminal save retry resumes the gameplay clock")
		if mode == "daily_game" and outcome == "win":
			_check(is_equal_approx(game.get_daily_beat_percent(), first_score), "daily retry preserves the first score when live experiment changes")
			_check(game.get_daily_completed_date() == Time.get_date_string_from_system(), "daily retry records completion date")
	_fail(false)
	ui.hide_all()
	await create_timer(0.2).timeout


func _test_abandoned_retry() -> void:
	var page: Variant = await _open("game")
	page._lives = 0
	_fail(true)
	await page._on_game_fail()
	var dialog: Variant = ui.get_ui("confirm")
	if dialog == null or not dialog.is_showing():
		_fail(false)
		return
	var old_retry: Callable = dialog._on_confirm
	dialog.get_node("Root/Content/DialogRoot/CloseButton").pressed.emit()
	await create_timer(0.2).timeout
	_check(page.is_hidden() and ui.get_ui("home").is_showing(), "cancel explicitly returns home")
	_fail(false)
	page = ui.show_ui("game", {"level_index": 1})
	await create_timer(0.2).timeout
	var revision: int = game.get_core_store().revision()
	old_retry.call()
	_check(game.get_core_store().revision() == revision and not page._is_complete, "abandoned retry cannot settle a newer page generation")
	ui.hide_all()
	await create_timer(0.2).timeout


func _fail(enabled: bool) -> void:
	fault_hits = 0
	files.set_fault_injector_for_tests((func(phase: String) -> bool:
		if phase == "before_replace":
			fault_hits += 1
			return true
		return false
	) if enabled else Callable())


func _test_win_checkin_retry(cancel: bool) -> void:
	var page: Variant = await _open("game")
	var streak: Node = root.get_node("StreakManager")
	root.get_node("ABTestManager").daily_streak.set_debug_override(1)
	game.set_tutorial_done(true)
	var candidate: Dictionary = game.get_core_candidate()
	candidate.features.streak = {"current_streak": 6, "best_streak": 6, "reward_cycle_day": 6, "last_checkin_date": streak._date_offset_str(-1), "streak_start_weekday": 1, "last_group": 1, "pending_switch_page": 0}
	candidate.claims.erase("streak/checkin/" + streak._today_str())
	_check(game.commit_core_candidate(candidate, game.get_core_store().revision()).ok, "check-in fixture is persisted before actual win")
	for row: int in page._level_config.size:
		for column: int in page._level_config.size:
			page._board_view.get_board_state().set_cell_state(row, column, CellState.CAT if page._puzzle.solution[row][column] else CellState.EMPTY)
	page._board_view.refresh_from_model()
	var previous_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("ja")
	# 1.22 移植合同：胜利、签到、奖励在一个候选提交；任何写失败都不得先公布胜利。
	_fail(true)
	await page._on_game_win()
	var dialog: Variant = ui.get_ui("confirm")
	_check(fault_hits > 0, "combined win/check-in reaches injected storage failure")
	_check(not page._is_complete and game.get_current_level() == 1, "failed win/check-in leaves progress and terminal presentation untouched")
	_check(dialog != null and dialog.is_showing() and streak.get_data().current_streak == 6, "failed atomic check-in exposes terminal retry without partial check-in")
	if dialog != null:
		_check(dialog.get_node("Root/Content/DialogRoot/ActionButton").btn_text == "もう一度", "atomic check-in recovery uses the existing Japanese retry translation")
	TranslationServer.set_locale(previous_locale)
	if dialog != null and dialog.is_showing():
		var old_retry: Callable = dialog._on_confirm
		if cancel:
			ui.hide_ui("game")
			await process_frame
			_check(not dialog.is_showing(), "leaving game cancels its pending combined result prompt")
			_fail(false)
			old_retry.call()
			await create_timer(0.1).timeout
			_check(streak.get_data().current_streak == 6 and game.get_current_level() == 1, "old combined retry changes neither check-in nor progress after owner leaves")
		else:
			dialog._on_action_btn_pressed()
			await create_timer(0.4).timeout
			_check(dialog.is_showing() and streak.get_data().current_streak == 6 and game.get_current_level() == 1, "repeated failed combined result keeps an actionable prompt")
			_fail(false)
			dialog._on_action_btn_pressed()
			await process_frame
			_check(streak.get_data().current_streak == 7 and streak.get_pending_show_uid() > 0, "combined retry atomically registers day-seven reward")
			_check(game.get_current_level() == 2 and page._is_complete, "combined retry commits exactly one victory")
			var revision: int = game.get_core_store().revision()
			old_retry.call()
			_check(game.get_core_store().revision() == revision, "late duplicate combined result callback writes nothing")

	_fail(false)
	ui.hide_all()
	await create_timer(0.2).timeout


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)


func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while not page._entry_ready and page._entry_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
