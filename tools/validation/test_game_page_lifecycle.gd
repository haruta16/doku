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
	ab.game_auto_mark.set_debug_override(0)
	ab.dc_level.set_debug_override(0)
	ab.daily_streak.set_debug_override(1)
	await _daily_entry(ui)
	await _daily_restart_and_ad_clock(ui, game)
	await _invalid_daily_pool(ui)
	for mode: String in ["daily_game", "game"]:
		await _streak_lifecycle(ui, mode)
	await _main_entry_wait(ui)
	ui.hide_all()
	await create_timer(0.4).timeout
	print("GAME PAGE LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _daily_entry(ui: Node) -> void:
	# 第一次排版等待前关闭，旧 on_show 不能继续锁按钮或铺盘。
	var page: Variant = ui.show_ui("daily_game")
	var lock_count: int = page._entry_btn_lock_seq
	ui.hide_ui("daily_game")
	await _frames(3)
	_check(not page.visible and page._clock_timer.is_stopped(), "daily closes while entry is waiting")
	_check(page._entry_btn_lock_seq == lock_count, "closed entry does not resume after first layout wait")
	_check(not page._entry_anim_playing and not page._board_view.visible, "closed entry stays cancelled and board stays hidden")

	# 第一帧已经铺盘，第二次排版等待仍必须能够取消。
	page = ui.show_ui("daily_game")
	await process_frame
	_check(page._entry_btn_lock_seq == lock_count + 1, "daily entry reaches its second layout wait")
	ui.hide_ui("daily_game")
	await _frames(3)
	_check(not page._board_view.visible, "closed entry does not reveal board after second layout wait")
	_check(not page._anim_player.is_playing(), "hiding stops the entry animation")
	_check(not page.get_node("Root").animation_finished.is_connected(page._on_appear_animation_finished), "hiding disconnects the entry completion callback")
	for button: Button in page._entry_locked_buttons:
		_check(button.mouse_filter == Control.MOUSE_FILTER_STOP, "hiding clears temporary header input locks")

	# 同一窗口同帧刷新两次，只能有最后一代的铺盘/开局副作用。
	lock_count = page._entry_btn_lock_seq
	page = ui.show_ui("daily_game")
	var generation: int = page._business_generation
	ui.show_ui("daily_game")
	await create_timer(2.0).timeout
	_check(page._business_generation == generation + 1, "visible daily re-entry creates a new generation")
	_check(page._entry_btn_lock_seq == lock_count + 1, "rapid daily reuse runs only the newest entry")
	_check(page.visible and page._board_view.visible and not page._puzzle.is_empty(), "latest daily entry remains usable")
	_check(not page._entry_anim_playing, "normal daily entry still unlocks after animation")
	ui.hide_ui("daily_game")
	page._pending_show_auto_mark_popup = true
	page._on_appear_animation_finished()
	_check(not _visible(ui, "daily_auto_mark_popup"), "late entry completion cannot open a popup on a hidden page")
	page._pending_show_auto_mark_popup = false


func _daily_restart_and_ad_clock(ui: Node, game: Node) -> void:
	var page: Variant = ui.show_ui("daily_game")
	await _frames(4)
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
	await _frames(4)
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
	_check(page._entry_anim_playing, "failed daily entry keeps gameplay actions blocked")
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
	await _frames(5)
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
	await _frames(5)
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
