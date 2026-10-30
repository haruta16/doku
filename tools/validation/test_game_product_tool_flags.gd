## 真实主线/每日按钮：付费资格标记随库存同事务提交，免费/失败不能结束首次引导。
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
	ab.normal_endgame_save.set_debug_override(0)
	ab.daily_first_level_difficulty.set_debug_override(0)
	ab.reward_unlock_level.set_debug_override(0)
	ab.draft_mode.set_debug_override(5)
	ab.dc_level.set_debug_override(0)
	ab.auto_x_fill_mode.set_debug_override(0)
	ab.prop_highlight.set_debug_override(0) # 1.22 的引导按本局播放次数，不由全局付费历史关闭。
	for mode: String in ["game", "daily_game"]:
		for scenario: String in ["hint", "locate", "locate_empty", "draft"]:
			await _exercise(mode, scenario)
	files.set_fault_injector_for_tests(Callable())
	ui.hide_all()
	await create_timer(0.5).timeout
	for name: String in ["game", "daily_game", "confirm"]:
		await ui.destroy_ui(name)
	await process_frame
	print("GAME PRODUCT TOOL FLAG TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _exercise(mode: String, scenario: String) -> void:
	var kind: String = "locate" if scenario == "locate_empty" else scenario
	var label: String = mode + "/" + scenario
	ui.hide_all()
	await create_timer(0.3).timeout
	_check(game.reset_all(), label + " resets isolated player")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	game.set_tool_count(kind, 10) # 只增加库存，不能预先污染 has_used_tool。
	var page: Variant = ui.show_ui(mode, {"level_index": 50} if mode == "game" else {})
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing or page._tool_btns_locked) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(page._is_round_entry_ready() and not page._entry_anim_playing and not page._tool_btns_locked, label + " actual page is ready")
	_check(not game.has_used_tool() and page._can_show_idle_hint(), label + " unused player retains the default first-tool guidance")
	if not page._is_round_entry_ready() or page._entry_anim_playing or page._tool_btns_locked:
		return
	# 空定位仍收费；草稿按 1.22 的激活入口验证，同一轮已激活时不再扣费。
	if scenario == "locate_empty":
		var size: int = page._level_config.size
		for row: int in size:
			for col: int in size:
				page._board_view.get_board_state().set_cell_state(row, col, CellState.CAT if page._puzzle.solution[row][col] else CellState.EMPTY)
		page._board_view.refresh_from_model()
		page._is_complete = false
	_prepare_attempt(page, kind)
	_check(page._ensure_business_round().get("ok", false), label + " durable round exists before injected action failures")
	var button: Variant = page._bt._get_btn(kind)
	var balance: int = game.get_tool_count(kind)
	var tracks_legacy_tool: bool = kind in ["hint", "locate", "undo"]
	if kind in ["hint", "locate"]:
		page.debug_force_free_tool = kind
		page._sync_tools_from_state()
		button.pressed.emit()
		await create_timer(1.1).timeout
		_dismiss_hint(page, kind)
		var key: String = "doku/" + ("main" if mode == "game" else "daily")
		var free_receipt: Dictionary = game.get_core_store().snapshot().round_services[key].last_receipt
		_check(free_receipt.get("kind") == ("request_hint" if kind == "hint" else kind) and free_receipt.result.get("cost", -1) == 0, label + " free button actually commits an accepted zero-price action")
		_check(game.get_tool_count(kind) == balance and not game.has_used_tool(), label + " accepted free use neither debits nor records a paid use")
		_check(page._can_show_idle_hint(), label + " free use keeps original default guidance eligibility")
		page.debug_force_free_tool = ""
		page._sync_tools_from_state()
	_prepare_attempt(page, kind)
	var before: Dictionary = game.get_core_store().snapshot()
	fault_hits = 0
	files.set_fault_injector_for_tests(_reject_commit)
	button.pressed.emit()
	await create_timer(0.4).timeout
	_check(fault_hits > 0, label + " paid action reaches the actual pre-replace fault boundary")
	_check(not game.has_used_tool() and game.get_tool_count(kind) == balance and game.get_core_store().snapshot() == before, label + " failed save changes neither live flag, inventory nor persisted core")
	_check(page._can_show_idle_hint(), label + " failed paid action retains guidance eligibility")
	files.set_fault_injector_for_tests(Callable())
	button.pressed.emit()
	await create_timer(1.1).timeout
	_dismiss_hint(page, kind)
	_check(game.get_tool_count(kind) == balance - 1 and game.has_used_tool() == tracks_legacy_tool, label + " successful retry debits once and records the 1.22 legacy-tool flag")
	_check(game.get_core_store().snapshot().profile.has_used_tool == tracks_legacy_tool, label + " 1.22 legacy-tool flag is in the committed core")
	var disk: Dictionary = files.load_result()
	var saved: Dictionary = disk.config.get_value("core", "state", {}) if disk.get("ok", false) else {}
	_check(saved.get("profile", {}).get("has_used_tool", false) == tracks_legacy_tool, label + " reading actual save slots recovers 1.22 legacy-tool flag")
	_check(page._can_show_idle_hint(), label + " 1.22 paid use preserves this round's unused hint presentation quota")
	page._idle_hint_round_count = 1
	_check(not page._can_show_idle_hint(), label + " this round's consumed hint quota prevents another presentation")


func _prepare_attempt(page: Variant, kind: String) -> void:
	page._last_tool_deplete_ms = -10000
	page._hint_cooldown = false
	if kind == "draft":
		page._draft_busy = false


func _dismiss_hint(page: Variant, kind: String) -> void:
	if kind == "hint" and page._hint_overlay.visible:
		page._hint_overlay._on_dismiss_btn_pressed()


func _reject_commit(phase: String) -> bool:
	if phase == "before_replace":
		fault_hits += 1
		return true
	return false


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEST_FAILED: " + message)
