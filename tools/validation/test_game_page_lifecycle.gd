## 真实对局页面的关闭、复用与异步续跑；仅在隔离工程运行。
extends SceneTree

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var ui: Node = root.get_node("UIManager")
	var game: Node = root.get_node("GameState")
	var ab: Node = root.get_node("ABTestManager")
	game.set_tutorial_done(true)
	game.set_current_level(50)
	ab.auto_x_fill_mode.set_debug_override(0)
	ab.dc_level.set_debug_override(0)
	ab.daily_streak.set_debug_override(1)
	ab.daily_streak_success_page.set_debug_override(0)
	ab.dc_endgame_save.set_debug_override(0)
	ab.dc_start_toast.set_debug_override(0)
	game.set_sound_on(false)
	game.set_music_on(false)
	game.set_tool_count("hint", 20)
	await _daily_entry(ui)
	await _daily_restart_and_ad_clock(ui, game)
	await _invalid_daily_pool(ui)
	for mode: String in ["daily_game", "game"]:
		await _streak_lifecycle(ui, mode)
	await _main_entry_wait(ui)
	await _daily_popup_lifecycle(ui)
	await _popup_close_parent_cancellation(ui)
	await _daily_tutorial_child_cancellation(ui)
	ui.hide_all()
	for name: String in ["game", "daily_game", "streak", "confirm"]:
		await ui.destroy_ui(name)
	await _frames(2)
	print("GAME PAGE LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _daily_entry(ui: Node) -> void:
	# 第一次排版等待前关闭，旧 on_show 不能继续锁按钮或铺盘。
	var page: Variant = ui.show_ui("daily_game")
	var lock_count: int = page._entry_btn_lock_seq
	ui.hide_ui("daily_game")
	lock_count = page._entry_btn_lock_seq
	await create_timer(0.4).timeout
	_check(not page.visible and page._clock_timer.is_stopped(), "daily closes while entry is waiting")
	_check(page._entry_btn_lock_seq == lock_count, "closed entry does not resume after first layout wait")
	_check(not page._entry_anim_playing and not page._board_view.visible, "closed entry stays cancelled and board stays hidden")

	# 第一帧已经铺盘，第二次排版等待仍必须能够取消。
	page = ui.show_ui("daily_game")
	await process_frame
	_check(page._business_generation > 0 and not page._entry_error, "daily entry reaches its next layout wait")
	ui.hide_ui("daily_game")
	await _frames(3)
	_check(not page._board_view.visible, "closed entry does not reveal board after second layout wait")
	_check(not page._anim_player.is_playing(), "hiding stops the entry animation")
	_check(not page.get_node("Root").animation_finished.is_connected(page._on_appear_animation_finished), "hiding disconnects the entry completion callback")
	for button: Button in [page._back_setting_header._back_btn, page._back_setting_header._settings_btn]:
		_check(button.mouse_filter == Control.MOUSE_FILTER_STOP, "hiding clears temporary header input locks")

	# 同一窗口同帧刷新两次，只能有最后一代的铺盘/开局副作用。
	lock_count = page._entry_btn_lock_seq
	page = ui.show_ui("daily_game")
	var generation: int = page._business_generation
	ui.show_ui("daily_game")
	await create_timer(2.0).timeout
	_check(page._business_generation == generation + 1, "visible daily re-entry creates a new generation")
	_check(page._entry_ready and not page._entry_preparing, "rapid daily reuse commits only the newest playable entry")
	_check(page.visible and page._board_view.visible and not page._puzzle.is_empty(), "latest daily entry remains usable")
	_check(not page._entry_anim_playing, "normal daily entry still unlocks after animation")
	ui.hide_ui("daily_game")
	page._on_appear_animation_finished()
	_check(not page._entry_ready and not page._anim_player.is_playing(), "late entry completion cannot reactivate a hidden page")


func _daily_restart_and_ad_clock(ui: Node, game: Node) -> void:
	var page: Variant = ui.show_ui("daily_game")
	await _wait_ready(page)
	var first: Dictionary = page._execute_business_action("request_hint", {}, {"hint_cost": 1})
	_check(first.get("ok", false), "daily supports a paid hint in the current round")
	var balance: int = game.get_tool_count("hint")
	var puzzle: Dictionary = page._puzzle.duplicate(true)
	page._on_ad_shown_for_timer("reward")
	_check(page._ad_show_unix > 0.0, "visible daily records its ad interval")
	ui.hide_ui("daily_game")
	var hidden_start: float = page._start_unix
	page._on_ad_shown_for_timer("reward")
	page._on_ad_closed("reward")
	_check(page._ad_show_unix == 0.0 and page._start_unix == hidden_start, "hidden daily ignores unrelated ad timing")
	page = ui.show_ui("daily_game")
	await _wait_ready(page)
	_check(page._puzzle == puzzle and page._lives == 3, "daily re-entry keeps the day's puzzle and restarts lives")
	_check(page._ad_show_unix == 0.0, "daily re-entry has no stale ad interval")
	var second: Dictionary = page._execute_business_action("request_hint", {}, {"hint_cost": 1})
	_check(second.get("ok", false) and second.round_id != first.get("round_id"), "daily preserves its existing new-round-on-reentry semantics")
	_check(game.get_tool_count("hint") == balance - 1, "a new daily round has its own hint purchase")
	ui.hide_ui("daily_game")


func _invalid_daily_pool(ui: Node) -> void:
	# 模拟所有候选都不满足玩法规则；不把旧页面残留题面当成开局成功。
	var original: Array = BankData.get_levels(10, 3).duplicate(true)
	var regions: Array = []
	var solution: Array = []
	for row in 10:
		var cells: Array = []
		cells.resize(10)
		cells.fill(row)
		regions.append(cells)
		solution.append(0)
	BankData._cache["10_3"] = [{"regionMap": regions, "solution": solution}]
	var page: Variant = ui.show_ui("daily_game")
	await _frames(3)
	_check(page._puzzle.is_empty() and page._level_config.is_empty(), "all-invalid daily pool does not retain a previous puzzle")
	_check(not page._board_view.visible and page._clock_timer.is_stopped(), "all-invalid daily pool does not start a playable board or clock")
	_check(not page._entry_ready and not page._execute_business_action("request_hint").get("ok", false), "failed daily entry keeps gameplay actions blocked")
	BankData._cache["10_3"] = original
	ui.hide_ui("daily_game")


func _streak_lifecycle(ui: Node, mode: String) -> void:
	var source: StringName = &"challenge" if mode == "daily_game" else &"main"
	var streak: Node = root.get_node("StreakManager")
	var params: Dictionary = {"level_index": root.get_node("GameState").get_current_level()}
	# SceneTree 脚本在 Autoload 注册前解析；运行时再读页面常量。
	var win_script: Script = load("res://products/meowdoku/gameplay/presentation/daily/view/daily_win_page.gd" if mode == "daily_game" else "res://products/meowdoku/gameplay/presentation/result/view/game_win_page.gd")
	var appear_delay: float = float(win_script.APPEAR_DELAY)
	var page: Variant = ui.show_ui(mode, params)
	await _wait_ready(page)
	# 只控制已存在的待展示资格；真实 helper、计时器、UIManager 和窗口均参与。
	streak._pending_show_uid = 0
	var closed_result: Dictionary = {"done": false, "value": false}
	_wait_for_streak(page, source, closed_result)
	ui.hide_ui(mode)
	await create_timer(appear_delay + 0.2).timeout
	_check(not _visible(ui, "streak"), mode + ": hiding during delay does not open streak")
	_check(closed_result.done and not closed_result.value, mode + ": cancelled streak continuation returns false")
	_check(streak.has_pending_show(), mode + ": cancelled presentation preserves pending eligibility")

	page = ui.show_ui(mode, params)
	await _wait_ready(page)
	streak._pending_show_uid = 0
	var reused_result: Dictionary = {"done": false, "value": false}
	_wait_for_streak(page, source, reused_result)
	ui.show_ui(mode, params)
	await create_timer(appear_delay + 0.2).timeout
	_check(page.visible and not _visible(ui, "streak"), mode + ": old delayed popup cannot attach to reused page")
	_check(reused_result.done and not reused_result.value, mode + ": reused page rejects previous generation")

	# 正常等待仍然展示打卡页，关掉之后继续当前流程。
	streak._pending_show_uid = 0
	var normal_result: Dictionary = {"done": false, "value": false}
	_wait_for_streak(page, source, normal_result)
	await create_timer(appear_delay + 0.2).timeout
	_check(_visible(ui, "streak") and not normal_result.done, mode + ": current flow opens and waits for streak")
	ui.hide_ui("streak")
	await create_timer(0.5).timeout
	_check(normal_result.done and normal_result.value, mode + ": current flow resumes after streak closes")

	# 已经展示之后更换代次，等关闭的旧协程也不能继续宣布成功。
	streak._pending_show_uid = 0
	var late_result: Dictionary = {"done": false, "value": false}
	_wait_for_streak(page, source, late_result, true)
	_check(_visible(ui, "streak"), mode + ": skip-delay flow opens immediately")
	ui.hide_ui(mode)
	ui.hide_ui("streak")
	await create_timer(0.5).timeout
	_check(late_result.done and not late_result.value, mode + ": hidden parent rejects continuation after popup closes")
	streak.consume_pending_show()


func _main_entry_wait(ui: Node) -> void:
	var page: Variant = ui.show_ui("game", {"level_index": root.get_node("GameState").get_current_level()})
	await _frames(5)
	page._entry_anim_pending_state = {"done": false}
	page._fire_entry_anim("lifecycle_test")
	ui.hide_ui("game")
	await _frames(4)
	_check(not page.visible and not page._anim_player.is_playing(), "main ad-entry continuation cannot restart animation after close")


func _wait_for_streak(page: Variant, source: StringName, result: Dictionary, skip_delay: bool = false) -> void:
	result.value = await page._try_run_streak_flow_after_win(source, skip_delay)
	result.done = true


func _visible(ui: Node, name: String) -> bool:
	var page: Variant = ui.get_ui(name)
	return page != null and page.visible


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TEST_FAILED: " + message)


func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while not page._entry_ready and page._entry_error.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._entry_ready, "lifecycle fixture starts a durable round")


func _daily_popup_lifecycle(ui: Node) -> void:
	for name: String in ["dc_costume_tutorial", "dc_costume_unlock", "dc_replay_confirm"]:
		var calls := {"confirm": 0, "close": 0}
		var params: Dictionary = {"costume_id": 1, "beat_percent": 88.0, "on_confirm": func() -> void: calls.confirm += 1, "on_close": func() -> void: calls.close += 1}
		var page: Variant = ui.show_ui(name, params)
		await _frames(2)
		_check(page != null and page.is_showing(), name + " opens a real 1.22 scene")
		ui.hide_ui(name)
		ui.show_ui(name, params)
		await create_timer(0.5).timeout
		_check(page.is_showing(), name + " old close animation cannot hide a refreshed presentation")
		if name == "dc_replay_confirm":
			ui.hide_ui(name)
			page._on_replay_btn_pressed()
			page._on_close_btn_pressed()
			_check(calls.confirm == 0 and calls.close == 0, "hidden daily replay rejects late button callbacks")
		ui.hide_ui(name)
		await ui.destroy_ui(name)
		await _frames(2)
		_check(ui.get_ui(name) == null, name + " destroys during close without retaining animation waiters")


func _capture_hide(ui: Node, name: String, result: Dictionary) -> void:
	await ui.hide_ui(name)
	result.done = true


func _popup_close_parent_cancellation(ui: Node) -> void:
	for name: String in ["dc_costume_tutorial", "dc_costume_unlock", "dc_replay_confirm", "win"]:
		for transition: String in ["refresh", "free", "complete"]:
			var events := {"tutorial": 0, "choice": 0, "callback": 0}
			var params := {"costume_id": 1, "beat_percent": 88.0, "on_confirm": func() -> void: events.callback += 1, "on_close": func() -> void: events.callback += 1}
			var page: Variant = ui.show_ui(name, params)
			if name == "dc_costume_tutorial":
				page.tutorial_closed.connect(func() -> void: events.tutorial += 1)
			if name == "dc_costume_unlock":
				page.choice_made.connect(func(_equipped: bool) -> void: events.choice += 1)
			var result := {"done": false}
			_capture_hide(ui, name, result)
			_check(not result.done, name + " starts a real asynchronous close")
			if transition == "refresh":
				ui.show_ui(name, params)
			elif transition == "free":
				page.free()
			else:
				var deadline: int = Time.get_ticks_msec() + 3000
				while not result.done and Time.get_ticks_msec() < deadline:
					await process_frame
			# Cancellation assertions precede every await; a normal completion may wait for its animation.
			_check(result.done, name + " " + transition + " releases the complete close parent chain")
			var expected_tutorial: int = 1 if name == "dc_costume_tutorial" and transition == "complete" else 0
			_check(events == {"tutorial": expected_tutorial, "choice": 0, "callback": 0}, name + " " + transition + " preserves completion and user-choice signal semantics")
			if is_instance_valid(page):
				_check(page.is_hidden() if transition == "complete" else page.is_showing(), name + " keeps the correct completed or replacement presentation")
				page.free()
			await _frames(2)
	# Win owns the wait, although the companion popup has its own longer-lived close.
	var win: Variant = ui.show_ui("win")
	var reward: Variant = ui.show_ui("home_companion_reward", {"reward_tier": 1})
	win._companion_reward_sequence = win._show_seq_id
	var result := {"done": false}
	_capture_hide(ui, "win", result)
	_check(not result.done, "win awaits its owned companion close")
	win.free()
	_check(result.done, "freeing win cancels its close parent while companion still exists")
	_check(is_instance_valid(reward), "win cancellation does not destroy another window's current instance")
	await ui.hide_ui("home_companion_reward")
	await ui.destroy_ui("home_companion_reward")


func _capture_costume_tutorial(page: Variant, result: Dictionary) -> void:
	await page._maybe_show_costume_tutorial()
	result.done = true


func _daily_tutorial_child_cancellation(ui: Node) -> void:
	var game: Node = root.get_node("GameState")
	var ab: Node = root.get_node("ABTestManager")
	var profile: Node = root.get_node("ProfileService")
	for transition: String in ["free", "refresh", "refresh_then_closed", "complete"]:
		ui.hide_all()
		await _frames(2)
		_check(game.reset_all(), "tutorial wait prepares isolated state")
		game.set_tutorial_done(true)
		game.set_current_level(50)
		game.set_sound_on(false)
		ab.dc_costume.set_debug_override(0)
		var daily: Variant = ui.show_ui("daily_game")
		await _wait_ready(daily)
		var deadline: int = Time.get_ticks_msec() + 8000
		while daily._entry_anim_playing and Time.get_ticks_msec() < deadline:
			await process_frame
		ab.dc_costume.set_debug_override(1)
		var result := {"done": false}
		_capture_costume_tutorial(daily, result)
		await _frames(2)
		var child: Variant = ui.get_ui("dc_costume_tutorial")
		_check(is_instance_valid(child) and child.is_showing() and not result.done and daily._clock_timer.is_stopped(), "daily pauses its clock while the actual costume tutorial is pending")
		if transition == "free":
			child.free()
		elif transition.begins_with("refresh"):
			ui.show_ui("dc_costume_tutorial", {"costume_id": 1})
			if transition == "refresh_then_closed":
				# A completion belonging to the replacement must not complete the old daily wait.
				child.tutorial_closed.emit()
		else:
			await ui.hide_ui("dc_costume_tutorial")
		await _frames(2)
		_check(result.done and not daily._clock_timer.is_stopped(), "tutorial " + transition + " releases the current daily clock without waiting for timeout")
		_check(profile.is_costume_tutorial_shown() == (transition == "complete"), "tutorial " + transition + " records completion only for a successful close")
		if is_instance_valid(child):
			child.free()
		ui.hide_ui("daily_game")
	ab.dc_costume.set_debug_override(0)
