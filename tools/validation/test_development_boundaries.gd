## 产品开发入口：默认验证 debug；独立 runner 在副本替换构建谓词并传入 simulated_release。
## 不模拟导出包或平台 SDK，只验证现有产品装配是否正确使用构建边界。
extends SceneTree

var checks: int = 0
var failures: int = 0
var expect_debug: bool = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if not args.is_empty() else "debug"
	if mode not in ["debug", "simulated_release"]:
		quit(2)
		return
	expect_debug = mode == "debug"
	_check(not OS.has_feature("rel"), "fixture omits the optional rel tag so the build predicate must enforce isolation")
	_test_registry()
	var game: Node = root.get_node("GameState")
	var ui: Node = root.get_node("UIManager")
	_check(game.is_storage_ready(), "isolated product storage is ready")
	game.set_debug_mode(true)
	_check(game.is_debug_mode() == expect_debug, "runtime debug flag cannot bypass a release build")
	game.set_debug_mode(false)
	_check(game.is_debug_mode() == expect_debug, "ordinary debug behavior remains available without the rel tag")
	_test_cheat_bus()
	game.set_sound_on(false)
	_check(game.set_tutorial_done(true), "fixture completes tutorial through the product transaction")

	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var launcher: Node = (load("res://products/meowdoku/launcher.tscn") as PackedScene).instantiate()
	host.add_child(launcher)
	var deadline: int = Time.get_ticks_msec() + 15000
	while not launcher.get("_startup_complete") and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(bool(launcher.get("_startup_complete")), "real launcher completes before gameplay assertions")
	_check((launcher.find_child("CheatOverlay", true, false) != null) == expect_debug, "launcher creates cheat overlay only for debug")
	_check((launcher.get("_in_game_log_buffer") != null) == expect_debug, "launcher retains diagnostic memory logger only for debug")
	_check((InGameLogBuffer.instance != null) == expect_debug, "global diagnostic log buffer agrees with the actual launcher")
	_check(launcher.get("_crashlytics_logger") != null, "ordinary crash logging stays enabled in both modes")
	if bool(launcher.get("_startup_complete")):
		await _test_gameplay(ui, "game")
		await _test_gameplay(ui, "daily_game")
	ui.hide_all()
	await create_timer(0.2).timeout
	print("DEVELOPMENT BOUNDARY TESTS: mode=%s %d assertions, %d failures" % [mode, checks, failures])
	quit(0 if failures == 0 else 1)


func _test_registry() -> void:
	var registry: Dictionary = load("res://products/meowdoku/app/ui/ui_registry.gd").build_registry()
	for name: String in ["home", "game", "daily_game", "setting", "confirm", "feedback"]:
		_check(registry.has(name), "ordinary route remains registered: " + name)
	for name: String in ["debug", "generator"]:
		_check(registry.has(name) == (expect_debug and not OS.has_feature("android")), "debug route follows build and platform: " + name)
	for name: String in ["ab_debug", "level_json_input", "playtest_simulator"]:
		_check(registry.has(name) == expect_debug, "developer route follows build: " + name)
	for name: String in ["mock_ad", "mock_banner"]:
		_check(registry.has(name) == (expect_debug and OS.has_feature("editor")), "editor mock also requires a debug build: " + name)


func _test_cheat_bus() -> void:
	var bus: Node = root.get_node("CheatBus")
	var seen: Array = []
	var observer := func(name: String, args: Array[String]) -> void: seen.append({"name": name, "args": args})
	bus.command_issued.connect(observer)
	bus.issue("boundary_probe first second")
	_check(seen.size() == (1 if expect_debug else 0), "CheatBus suppresses command delivery in release")
	if expect_debug and not seen.is_empty():
		_check(seen[0] == {"name": "boundary_probe", "args": ["first", "second"]}, "debug command parsing remains usable")
	bus.command_issued.disconnect(observer)


func _test_gameplay(ui: Node, mode: String) -> void:
	ui.hide_all()
	await create_timer(0.2).timeout
	var page: Variant = ui.show_ui(mode, {"level_index": 1} if mode == "game" else {})
	_check(page != null, mode + " is available in both builds")
	if page == null:
		return
	await create_timer(1.0).timeout
	_check(not page._puzzle.is_empty(), mode + " creates an actual gameplay board")
	_check(page._strategy_btn != null and page._strategy_btn.visible == expect_debug, mode + " strategy button follows build boundary")
	_check((page._board_view._zone_viz != null) == expect_debug, mode + " swipe-zone debug node is created only for debug")
	ui.hide_ui(mode)
	await create_timer(0.2).timeout


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + message)
