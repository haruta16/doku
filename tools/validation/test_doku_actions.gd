## 纯规则、无界面对局动作，以及真实页面复用的回调隔离。
extends SceneTree

const Actions = preload("res://products/meowdoku/gameplay/domain/doku_action_rules.gd")
const Module = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")
const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")
var Policy: Script

var checks: int = 0
var failures: int = 0
var regions: Array = [[0, 0, 0, 0], [1, 1, 1, 1], [2, 2, 2, 2], [3, 3, 3, 3]]
var solution: Array = [[false, true, false, false], [false, false, false, true], [true, false, false, false], [false, false, true, false]]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	# 产品策略依赖产品 autoload；等运行器完成 autoload 初始化再加载。
	root.get_node("GameState").set_sound_on(false)
	root.get_node("GameState").set_music_on(false)
	Policy = load("res://products/meowdoku/gameplay/application/meowdoku_gameplay_policy.gd")
	_test_inputs()
	_test_drafts()
	_test_automatic_rules()
	_test_module()
	_test_policy()
	await _test_page()
	await _test_life_plus_transaction()
	await _test_failure_policy()
	await create_timer(0.5).timeout
	print("DOKU ACTION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _empty(size: int = 4) -> Array:
	var board: Array = []
	for row in size:
		var line: Array = []
		line.resize(size)
		line.fill(States.EMPTY)
		board.append(line)
	return board


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)


func _test_inputs() -> void:
	for value in [States.CAT, States.ERROR, States.LOCKED_MARK]:
		_check(not Actions.tap(value, false).allowed and not Actions.swipe(value, false, States.MARK, false).allowed, "normal input preserves protected cells")
	_check(Actions.tap(States.EMPTY, false).target == States.MARK, "tap empty marks")
	_check(Actions.tap(States.MARK, false).target == States.EMPTY, "tap mark erases")
	_check(Actions.tap(States.DRAFT_CROSS, false).before == States.EMPTY, "normal tap retains legacy draft history predecessor")
	_check(Actions.swipe(States.EMPTY, false, States.EMPTY, true).target == States.MARK, "stroke after blocked origin chooses first usable cell")
	_check(not Actions.swipe(States.DRAFT_CAT, true, States.DRAFT_CROSS, false).allowed, "draft stroke protects cats")
	_check(Actions.draft_double_tap(States.DRAFT_CROSS).target == States.DRAFT_CAT, "draft double tap changes cross to cat")
	_check(Actions.draft_double_tap(States.DRAFT_CAT).target == States.EMPTY, "draft double tap clears cat")
	var board: Array = _empty()
	var right: Dictionary = Actions.guess(board, solution, 0, 1, 3)
	var wrong: Dictionary = Actions.guess(board, solution, 0, 0, 1)
	_check(right.correct and right.lives == 3 and right.final_state == States.CAT, "correct guess preserves lives")
	_check(not wrong.correct and wrong.after == States.MARK and wrong.final_state == States.ERROR and wrong.lives == 0, "wrong guess separates presentation phase from final error state")
	_check(not Actions.guess(board, solution, -1, 0, 3).ok, "invalid coordinate rejected")
	_check(Actions.lose_lives(1, 4).lost == 1 and Actions.lose_lives(1, 4).lives == 0, "batch mistakes cannot underflow lives")
	_check(Actions.prior_tap([[0, 1, 0, 2]], 0, 1, 2) == {"consume": true, "before": 0}, "double tap merges same-cell prior tap")
	_check(not Actions.prior_tap([[0, 0, 0, 2], [0, 1, 0, 2]], 0, 1, 2).consume, "double tap does not merge entire swipe")


func _test_drafts() -> void:
	var board: Array = _empty()
	board[0][1] = States.DRAFT_CAT
	board[1][0] = States.DRAFT_CAT
	board[2][1] = States.DRAFT_CROSS
	board[3][3] = States.LOCKED_MARK
	var original: Array = board.duplicate(true)
	var plan: Dictionary = Actions.commit_draft(board, solution, 3)
	_check(plan.board[0][1] == States.CAT and plan.board[1][0] == States.ERROR and plan.board[2][1] == States.MARK, "draft plan resolves correct cat, wrong cat and cross")
	_check(plan.board[3][3] == States.LOCKED_MARK and plan.lives == 2 and plan.lost == 1, "draft preserves locked cells and batches life loss")
	_check(board == original, "draft planning never mutates caller")
	_check(plan.changes[0].row == 2 and plan.changes[1].row == 1 and plan.changes[2].row == 0, "draft keeps diagonal then descending-row application order")
	var cleared: Dictionary = Actions.clear_draft(board)
	_check(cleared.changes.size() == 3 and cleared.board[3][3] == States.LOCKED_MARK, "draft discard clears only draft values")
	_check(Actions.clear_draft(board, true).board == board, "keep-draft exit leaves state intact")
	board = _empty()
	for row in 4:
		for col in 4:
			if solution[row][col]:
				board[row][col] = States.DRAFT_CAT
	_check(Actions.draft_all_correct(board, solution) and not Actions.draft_contradiction(board, regions), "all valid draft cats are recognized")
	_check(Actions.commit_draft(board, solution, 2).solution_complete, "complete draft plan exposes terminal result")
	board = _empty()
	board[0] = [States.DRAFT_CROSS, States.DRAFT_CROSS, States.DRAFT_CROSS, States.DRAFT_CROSS]
	_check(Actions.draft_contradiction(board, regions), "fully crossed row without cat is contradiction")
	board = _empty()
	board[0][0] = States.DRAFT_CAT
	board[1][1] = States.DRAFT_CAT
	_check(Actions.draft_contradiction(board, regions), "adjacent draft cats violate rules")


func _test_automatic_rules() -> void:
	var board: Array = _empty()
	board[0][1] = States.CAT
	var excluded: Array = Actions.auto_marks(board, regions, Vector2i(0, 1), true)
	_check(excluded.has(Vector2i(0, 3)) and excluded.has(Vector2i(3, 1)) and not excluded.has(Vector2i(1, 3)), "automatic exclusions follow row column neighbor region")
	board[0] = [States.MARK, States.CAT, States.ERROR, States.MARK]
	var groups: Array = Actions.lock_sets(board, regions)
	_check(not groups.is_empty() and groups[0].marks.has(Vector2i(0, 0)), "completed constraint produces lock plan")
	_check(Actions.axis_targets(board, 0, 0, true) == [Vector2i(0, 3), Vector2i(0, 0)], "erase axis reverses order and preserves error/cat")
	_check(Actions.axis_targets(board, 0, 99, false).is_empty(), "invalid axis is harmless")
	var complete: Dictionary = Actions.auto_complete(board, solution, true)
	_check(complete.cats.size() == 3 and complete.board[1][3] == States.CAT, "auto completion plans remaining cats")
	_check(complete.board[0][2] == States.ERROR and not complete.marks.has(Vector2i(0, 2)), "auto completion preserves existing errors")
	_check(Actions.auto_complete(board, solution, false).marks.is_empty(), "cat-only variant has no mark phase")
	_check(not Actions.can_offer_auto_complete(board, true, false), "small boards do not offer auto completion")
	board = _empty()
	board[0] = [States.MARK, States.CAT, States.MARK, States.EMPTY]
	_check(Actions.life_plus_eligible(board, regions, 0, 1, 1, true, false, false, 61.0, 60.0, true, 0.9), "first eligible two-choice placement grants life")
	_check(not Actions.life_plus_eligible(board, regions, 0, 1, 1, true, false, false, 61.0, 60.0, false, 0.5), "later life grant respects random threshold")
	_check(not Actions.life_plus_eligible(board, regions, 0, 1, 1, true, false, true, 61.0, 60.0, true, 0.0), "daily mode cannot receive main life grant")


func _test_module() -> void:
	var module := Module.new()
	var opened: Dictionary = module.create_snapshot({"board": _empty(), "regions": regions, "solution": solution})
	_check(opened.ok, "pure round snapshot created")
	var activated: Dictionary = module.apply_action(opened.snapshot, "activate_draft", {}, {"policy": {"enabled": true, "cost": 0}})
	_check(activated.ok and activated.snapshot.draft_active, "draft entry activation is part of the domain transaction")
	var marked: Dictionary = module.apply_action(activated.snapshot, "draft_mark", {"row": 0, "col": 0, "state": States.DRAFT_CAT}, {})
	_check(marked.ok and marked.snapshot.board[0][0] == States.DRAFT_CAT, "round module accepts independent draft input")
	var committed: Dictionary = module.apply_action(marked.snapshot, "draft_commit", {}, {})
	_check(committed.ok and committed.snapshot.lives == 2 and committed.snapshot.board[0][0] == States.ERROR, "headless draft commit uses same rules")
	_check(committed.snapshot.history.size() == 1 and committed.snapshot.history[0].wrong, "draft history batches the action and preserves wrong marker")
	var right: Dictionary = module.apply_action(opened.snapshot, "place_cat", {"row": 0, "col": 1}, {})
	_check(right.ok and right.snapshot.history.size() == 1 and right.snapshot.history[0].cat, "headless normal placement now records history")
	var wrong: Dictionary = module.apply_action(opened.snapshot, "place_cat", {"row": 0, "col": 0}, {})
	_check(wrong.ok and wrong.snapshot.lives == 2 and wrong.snapshot.history[0].wrong and wrong.snapshot.board[0][0] == States.ERROR, "headless wrong guess commits one error and its history")
	_check(not module.apply_action(wrong.snapshot, "place_cat", {"row": 0, "col": 0}, {}).ok, "error cell cannot lose a second life")
	_check(not module.apply_action(opened.snapshot, "axis_mark", {"axis": 3, "index": 0, "erase": false}, {"policy": {"dot_toggle": true}}).ok, "invalid axis does not become successful no-op")
	_check(not module.apply_action(opened.snapshot, "auto_mark", {"row": 0, "col": 0}, {"policy": {"auto_mark_enabled": "true"}}).ok, "malformed action policy is rejected without implicit coercion")
	var bad: Dictionary = opened.snapshot.duplicate(true)
	bad.schema = "1"
	_check(not module.validate_snapshot(bad).is_empty(), "bad schema type returns validation error")
	var life_state: Dictionary = opened.snapshot.duplicate(true)
	life_state.board[0] = [States.MARK, States.CAT, States.MARK, States.EMPTY]
	life_state.lives = 1
	var policy := {"enabled": true, "daily": false, "elapsed_sec": 61.0, "minimum_sec": 60.0, "first_use": true, "random_value": 0.0}
	var life: Dictionary = module.apply_action(life_state, "life_plus", {"row": 0, "col": 1}, {"policy": policy})
	_check(life.ok and life.snapshot.lives == 2 and life.snapshot.life_plus_used and life.result.first_done, "life grant is a standalone state transition")
	life.snapshot.lives = 1
	_check(not module.apply_action(life.snapshot, "life_plus", {"row": 0, "col": 1}, {"policy": policy}).ok, "life grant once per round")
	var large_board: Array = _empty(6)
	var large_solution: Array = []
	var large_regions: Array = []
	var columns: Array = [1, 3, 5, 0, 2, 4]
	for row in range(6):
		var answer: Array = [false, false, false, false, false, false]
		answer[columns[row]] = true
		large_solution.append(answer)
		large_regions.append([row, row, row, row, row, row])
		if row < 5:
			large_board[row][columns[row]] = States.CAT
	var large: Dictionary = module.create_snapshot({"board": large_board, "solution": large_solution, "regions": large_regions})
	_check(large.ok, "six-cell fixture validates actual Doku constraints")
	var completed: Dictionary = module.apply_action(large.snapshot, "auto_complete", {}, {"policy": {"auto_complete_enabled": true, "auto_complete_marks": true}})
	_check(completed.ok and completed.result.complete and completed.snapshot.board[5][4] == States.CAT and completed.snapshot.board[5][5] == States.MARK, "headless automatic completion applies ordered rule plan")
	large.snapshot.board[5][0] = States.ERROR
	_check(not module.apply_action(large.snapshot, "auto_complete", {"had_error": false}, {"policy": {"auto_complete_enabled": true}}).ok, "automatic completion derives errors from state rather than caller assertion")


func _test_policy() -> void:
	var ab: Node = root.get_node("ABTestManager")
	var captured: Dictionary = Policy.capture(ab)
	_check(Policy.validate(captured), "actual AB values form a valid plain-data snapshot")
	var changed: Dictionary = captured.duplicate(true)
	changed.undo_free = not changed.undo_free
	_check(Policy.restore(captured, changed) == captured, "saved round policy wins over newly fetched AB")
	_check(Policy.restore({}, changed) == changed, "legacy round gets a current compatibility snapshot")
	_check(not Policy.validate({"schema": "1"}), "malformed policy safely rejected")
	_check(Policy.resolve(captured, null) == captured, "complete saved policy resolves without reading AB or current content")
	var previous_schema: Dictionary = captured.duplicate(true)
	previous_schema.erase("dda")
	previous_schema.erase("swipe_guard_variant")
	_check(not Policy.is_complete(previous_schema), "older policy is valid but requires missing-field upgrade")
	var upgraded: Dictionary = Policy.restore(previous_schema, changed)
	_check(upgraded.undo_free == captured.undo_free and upgraded.dda == changed.dda, "old policy gains missing fields without replacing frozen values")
	_check(Policy.validate_dda(captured.dda) and not Policy.validate_dda({"retry_once": "true"}), "DDA policy validates strict boolean fields")
	var guard: Dictionary = captured.duplicate(true)
	guard.swipe_guard = true
	guard.swipe_guard_variant = 3
	var raised: Dictionary = Policy.swipe_guard_parameters(guard, 9)
	_check(raised.min_size == 7 and raised.threshold == 6 and raised.tolerance_pct == 0.4, "frozen raised swipe policy retains size threshold and tolerance")
	guard.swipe_guard_variant = 2
	_check(Policy.swipe_guard_parameters(guard, 9).tolerance_pct == 0.1, "frozen narrow swipe policy retains tolerance")
	var revive_policy: Dictionary = captured.duplicate(true)
	revive_policy.reward_unlock_level = 0
	revive_policy.revive_free_variant = 2
	_check(Policy.revive_offer(revive_policy, 40, false) == {"free": true, "consume_free_once": true}, "frozen once-only mode offers unused free revive")
	_check(not Policy.revive_offer(revive_policy, 40, true).free, "current consumed entitlement overrides frozen once-only mode")


func _test_page() -> void:
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	var scene: PackedScene = load("res://products/meowdoku/gameplay/presentation/main/ui/game_page.tscn")
	var page: Variant = scene.instantiate()
	host.add_child(page)
	page.set_process(false)
	page._entry_ready = true # 本用例手工装配题面，跳过真实入场；入场门槛由专门页面回归验证。
	page._puzzle = {"regions": regions, "solution": solution}
	page._level_config = {"level": 0, "size": 4, "rank": 1, "seed": 9}
	page._round_policy = {"schema": 1, "draft_unlock_level": 0}
	page._freeze_gameplay_policy()
	page._gameplay_policy.draft_variant = 2
	page._gameplay_policy.auto_mark_variant = 0
	var colors: Array[int] = [0, 1, 2, 3]
	page._board_view.setup(4, regions, colors, [], true)
	page._entry_anim_playing = false
	page._is_complete = false
	page._entry_preparing = false
	page._business_history = []
	page._business_session = load("res://products/meowdoku/gameplay/application/meowdoku_round_session.gd").new(root.get_node("GameState"), "main")
	_check(page._ensure_business_round().ok, "manual draft presentation fixture owns a durable round")
	var activation: Dictionary = page._execute_business_action("activate_draft", {}, {"enabled": true, "cost": 0})
	_check(activation.ok, "actual page draft entry has durable activation before cells")
	page._enter_draft_mode(false)
	page._set_cell_draft(0, 1, States.DRAFT_CAT)
	page._set_cell_draft(1, 0, States.DRAFT_CAT)
	page._set_cell_draft(2, 1, States.DRAFT_CROSS)
	page._apply_draft_commit()
	_check(page._board_view.get_board()[0][1] == States.CAT and page._board_view.get_board()[1][0] == States.ERROR and page._lives == 2, "actual draft presenter matches pure plan")
	_check(page._business_history.size() == 1 and page._business_history[0].wrong, "actual draft keeps one compound history step")
	# 旧错误回调不能清掉新局的 pending 标记；页面此时仍然可见。
	page._business_generation += 1
	page._wrong_guess_pending = true
	await create_timer(0.45).timeout
	_check(page._wrong_guess_pending, "old draft callback cannot mutate a visible reused page")
	# 1.22 移除了行列自动标记按钮；当前页面仍以冻结题面与输入开关控制实际格子。
	_check(page._board_view._cells.size() == 4 and page._board_view._cells[0].size() == 4, "current board view uses the prepared 4x4 puzzle")
	page._board_view.set_touch_enabled(false)
	_check(not page._board_view._touch_enabled, "current board view disables input without old axis button controls")
	page._board_view.set_touch_enabled(true)
	page._gameplay_policy.swipe_guard = true
	page._gameplay_policy.swipe_guard_variant = 2
	page._ensure_input_system()
	_check(page._ensure_slot(-1).recognizer.get_script().get_global_name() == &"SwipeGuardRecognizer" and page._ensure_slot(-1).recognizer._frozen_policy.get("swipe_guard_variant") == 2, "actual 1.22 pointer recognizer receives frozen swipe policy")
	var recognizer: Variant = page._ensure_slot(-1).recognizer
	# 独立验证旧超时不能取消重开窗口；窗口长度固定，避免跟随当前 AB。
	recognizer.window_sec_provider = func(_r: int, _c: int) -> float: return 0.35
	recognizer._open_double_tap_window(0, 0)
	await create_timer(0.2).timeout
	recognizer.reset_for_scheme_switch()
	recognizer._open_double_tap_window(0, 0)
	await create_timer(0.18).timeout
	_check(recognizer._last_tap_cell == Vector2i(0, 0), "old tap timeout cannot close reused same-cell window")
	await create_timer(0.2).timeout
	_check(recognizer._last_tap_cell == Vector2i(-1, -1), "current tap timeout closes its own window")
	var token: int = page._auto_complete_token
	page._board_view.set_cell_input_locked(0, 0, true)
	page.on_hide()
	_check(page._auto_complete_token > token and not page._board_view.is_cell_input_locked(0, 0), "hide cancels automatic work and clears temporary input locks")
	page._do_destroy()
	page.queue_free()
	await process_frame


## 赠命已从 1.22 UI 退役，保留旧快照/域动作的原子兼容合同，不制造旧页面按钮。
func _test_life_plus_transaction() -> void:
	var game: Node = root.get_node("GameState")
	_check(game.reset_all(), "legacy life transaction starts from isolated state")
	game.set_sound_on(false)
	game.set_music_on(false)
	var session_script: Script = load("res://products/meowdoku/gameplay/application/meowdoku_round_session.gd")
	var session: RefCounted = session_script.new(game, "main")
	var board: Array = _empty()
	board[0] = [States.MARK, States.CAT, States.MARK, States.EMPTY]
	var started: Dictionary = session.ensure_started({"board": board, "regions": regions, "solution": solution, "lives": 1})
	_check(started.ok, "legacy life port starts actual persisted main round")
	var revision: int = game.get_core_store().revision()
	var before: Dictionary = game.get_core_store().snapshot()
	var files: RefCounted = game._product_store.files
	var policy: Dictionary = {"enabled": true, "daily": false, "elapsed_sec": 61.0, "minimum_sec": 60.0, "first_use": true, "random_value": 0.0}
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failed: Dictionary = session.execute("life_plus", {"row": 0, "col": 1}, {}, {}, policy)
	_check(not failed.ok and not game.is_life_plus_first_done(), "failed compatibility action never consumes first-use entitlement")
	_check(game.get_core_store().revision() == revision and game.get_core_store().snapshot() == before, "failed life action preserves entire durable round")
	files.set_fault_injector_for_tests(Callable())
	var applied: Dictionary = session.execute("life_plus", {"row": 0, "col": 1}, {}, {}, policy)
	_check(applied.ok and applied.snapshot.lives == 2 and game.is_life_plus_first_done(), "life and first-use entitlement commit together")
	var core: Dictionary = game.get_core_store().snapshot()
	_check(core.profile.life_plus_first_done and core.round_services["doku/main"].snapshot.life_plus_used, "product receipt retains legacy life eligibility")
	_check(game.get_core_store().revision() == revision + 1, "legacy life grant uses one durable commit")
	revision = game.get_core_store().revision()
	var repeated: Dictionary = session.execute("life_plus", {"row": 0, "col": 1}, {}, {}, policy)
	_check(not repeated.ok and game.get_core_store().revision() == revision, "repeated life action cannot grant again")
	var later: RefCounted = session_script.new(game, "main")
	_check(later.ensure_started({"board": board, "regions": regions, "solution": solution, "lives": 1}).ok, "later compatible round starts independently of first life grant")
	policy.first_use = false
	var granted: Dictionary = later.execute("life_plus", {"row": 0, "col": 1}, {}, {}, policy)
	_check(granted.ok and granted.result.lives == 2 and not granted.result.first_done, "first-use flag does not block later rounds")


func _test_failure_policy() -> void:
	var game: Node = root.get_node("GameState")
	var ab: Node = root.get_node("ABTestManager")
	var policy: Dictionary = Policy.capture(ab, 40)
	policy.reward_unlock_level = 50
	var params := {"level_config": {"level": 40, "size": 4}, "remaining_cats": 2, "gameplay_level": 40, "gameplay_policy_snapshot": policy}
	for path: String in ["res://products/meowdoku/gameplay/presentation/result/ui/game_fail_page.tscn", "res://products/meowdoku/gameplay/presentation/daily/ui/daily_fail_page.tscn"]:
		var scene: PackedScene = load(path)
		var page: Variant = scene.instantiate()
		current_scene.add_child(page)
		# 与实际管理器一致地进入窗口生命周期，不能只调用钩子而仍停在 INVALID。
		page._do_create()
		page._do_show(params)
		_check(page._is_free_revive(), "actual failure page reads frozen reward unlock threshold")
		var requested: Array = []
		page.revive_requested.connect(func(context: Dictionary) -> void: requested.append(context))
		page._on_revive_btn_pressed()
		_check(requested == [{}] and not game.has_used_revive_free(), "failure button emits eligibility intent without consuming entitlement")
		page._do_hide()
		page._do_show(params)
		page._anim.animation_finished.emit(&"disappear")
		_check(page.visible, "old failure-page hide callback cannot hide reused page")
		page._do_destroy()
		page.queue_free()
		await process_frame
