## 实际首页转场与启动页收尾：取消、缓存刷新及同步完成不能影响下一次展示。
extends SceneTree

var checks: int = 0
var failures: int = 0
var ui: Node
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	ui = root.get_node("UIManager")
	game = root.get_node("GameState")
	game.set_sound_on(false)
	game.set_music_on(false)
	game.set_tutorial_done(true)
	game.mark_rate_us_shown()
	root.get_node("ABTestManager").daily_streak.set_debug_override(0)
	for action: String in ["hide", "refresh", "reopen"]:
		await _test_cancel_before_entry(action)
	await _test_target_callback(false)
	await _test_target_callback(true)
	await _test_normal_transition()
	await _test_splash_refresh()
	for mode: String in ["normal", "full", "completed", "hidden", "refresh", "destroyed"]:
		await _test_completed_splash_wait(mode)
	for seconds: float in [0.0, -1.0, INF, NAN]:
		var page: Variant = ui.show_ui("splash", {"min_wait_seconds": seconds})
		page._process(0.1)
		_check(is_finite(page._current_progress) and page._current_progress > 0.0 and page._current_progress < 1.0, "invalid duration uses finite default progress")
	ui.hide_all()
	await create_timer(0.7).timeout
	print("UI NAVIGATION LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _home() -> Variant:
	ui.hide_all()
	var page: Variant = ui.show_ui("home")
	await create_timer(0.7).timeout
	return page

func _test_cancel_before_entry(action: String) -> void:
	var page: Variant = await _home()
	page._exit_to_page("splash", {})
	if action != "refresh": ui.hide_ui("home")
	if action != "hide": ui.show_ui("home")
	await create_timer(0.8).timeout
	var target: Variant = ui.get_ui("splash")
	_check(target == null or not target.is_showing(), action + " cancels the old home entry timer")
	if action != "hide":
		_check(page.is_showing() and not page._is_exiting, action + " leaves refreshed home actionable")

func _test_target_callback(reopen_home: bool) -> void:
	var page: Variant = await _home()
	var callback := func(name: String, _window: Variant) -> void:
		if name == "splash":
			ui.hide_ui("splash")
			if reopen_home: ui.show_ui("home")
	ui.events.window_shown.connect(callback)
	page._exit_to_page("splash", {})
	await create_timer(0.9).timeout
	ui.events.window_shown.disconnect(callback)
	_check(page.is_showing() and page.visible and not page._is_exiting, "cancelled target/reopened home survives old transition: " + str(reopen_home))

func _test_normal_transition() -> void:
	var page: Variant = await _home()
	page._exit_to_page("splash", {})
	await create_timer(0.9).timeout
	_check(ui.get_ui("splash").is_showing() and page.is_hidden(), "normal transition still opens target and retires home")

func _test_splash_refresh() -> void:
	ui.hide_all()
	var splash: Variant = ui.show_ui("splash")
	var done := {"count": 0}
	var callback := func() -> void: done.count += 1
	splash.loading_complete.connect(callback)
	splash.force_complete()
	splash._process(0.01)
	ui.show_ui("splash")
	await create_timer(0.25).timeout
	_check(done.count == 0 and splash._running and not splash._completed, "old finish tween cannot complete refreshed splash")
	splash.force_complete()
	await create_timer(0.25).timeout
	_check(done.count == 1 and splash._completed, "refreshed splash can finish once")
	splash.loading_complete.disconnect(callback)

func _test_completed_splash_wait(mode: String) -> void:
	var splash: Variant = ui.show_ui("splash")
	if mode in ["full", "completed"]: splash._apply_progress(1.0)
	if mode == "completed": splash.force_complete()
	var probe := GDScript.new()
	probe.source_code = "extends \"res://products/meowdoku/app/bootstrap/launcher.gd\"\nfunc _ready() -> void:\n\tpass\n"
	_check(probe.reload() == OK, "launcher fixture compiles after Autoload initialization")
	var launcher: Variant = probe.new()
	current_scene.add_child(launcher)
	launcher._splash_page = splash
	launcher._perf_t0 = Time.get_ticks_msec() - 3000
	var state := {"done": false}
	_wait_splash(launcher, state)
	await create_timer(0.55).timeout
	if mode == "hidden": ui.hide_ui("splash")
	if mode == "refresh": ui.show_ui("splash")
	if mode == "destroyed":
		splash._do_destroy()
		splash.queue_free()
	await create_timer(0.3).timeout
	_check(state.done, "launcher wait terminates after " + mode)
	if not state.done and is_instance_valid(splash): splash.loading_complete.emit()
	launcher.queue_free()

func _wait_splash(launcher: Node, state: Dictionary) -> void:
	await launcher._wait_splash_complete()
	state.done = true

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + label)
