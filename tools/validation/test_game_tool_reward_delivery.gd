## 真实 Mock 道具广告：区分历史、登记、领取提交，验证失败后权益交接与幂等重试。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
var kit: Node
var files: RefCounted
var fault_hits: int = 0


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
	game = root.get_node("GameState")
	ui = root.get_node("UIManager")
	kit = root.get_node("UniKitManager")
	files = game.get_core_store().get("_file_store")
	var ab: Node = root.get_node("ABTestManager")
	ab.normal_endgame_save.set_debug_override(0)
	ab.common_rewardad_logic.set_debug_override(1)
	ab.reward_unlock_level.set_debug_override(0)
	ab.auto_x_fill_mode.set_debug_override(0)
	kit.cheat_show_reward = true
	await _test_history_failure()
	for stage: String in ["register", "claim"]:
		for transition: String in ["stay", "hide", "new_round", "reset"]:
			await _test_retry(stage, transition)
	await _test_reentrant_rewards()
	await _test_multiple_failed_rewards()
	for stage: String in ["register", "claim"]:
		await _test_reset_during_commit(stage)
	ui.hide_all()
	await create_timer(0.7).timeout
	for name: String in ["game", "home", "mock_ad", "ad_reward_restored", "confirm"]:
		await ui.destroy_ui(name)
	await process_frame
	await process_frame
	print("GAME TOOL REWARD DELIVERY TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _open() -> Variant:
	files.set_fault_injector_for_tests(Callable())
	ui.hide_all()
	await create_timer(0.4).timeout
	_check(game.reset_all(), "reset isolated player")
	game.set_sound_on(false)
	game.set_music_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	game.set_tool_count("hint", 0)
	game.set_tool_count("locate", 0)
	var page: Variant = ui.show_ui("game", {"level_index": 50})
	await _wait_ready(page)
	page._last_tool_deplete_ms = -10000
	_check(page._is_round_entry_ready(), "real main entry ready")
	fault_hits = 0
	return page


func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing or page._tool_btns_locked) and Time.get_ticks_msec() < deadline:
		await process_frame


func _request(page: Variant, kind: String = "hint") -> String:
	await page.call("_on_" + kind + "_btn_pressed")
	await process_frame
	var id: String = kit._reward_active_show_id
	_check(not id.is_empty() and kit._reward_callbacks.has(id), "real depleted-tool request starts an identified Mock")
	var mock: Variant = ui.get_ui("mock_ad")
	_check(mock != null and mock.is_showing(), "Mock actually opens")
	if mock != null:
		mock._on_close_pressed()
		var deadline: int = Time.get_ticks_msec() + 2000
		while not mock.is_hidden() and Time.get_ticks_msec() < deadline:
			await process_frame
	return id


func _reward(id: String) -> void:
	kit._on_ad_rewarded_for_show("reward", id)


func _fail_writes(phase: String) -> bool:
	if phase != "before_replace":
		return false
	fault_hits += 1
	return true


func _history_count() -> int:
	return game.get_core_store().snapshot().profile.reward_history_ts.size()


func _test_history_failure() -> void:
	var page: Variant = await _open()
	var id: String = await _request(page)
	# 仅首个历史提交失败；后续交接重试恢复，业务奖励仍只能发一次。
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace" and fault_hits == 0:
			fault_hits += 1
			return true
		return false)
	_reward(id)
	files.set_fault_injector_for_tests(Callable())
	_check(fault_hits == 1, "normal history really reaches before_replace failure")
	_check(_history_count() == 1 and kit._pending_reward_history.is_empty(), "normal history recovers exactly once")
	_check(game.get_tool_count("hint") == 1 and game.get_in_flight_awards().is_empty(), "history failure does not prevent actual award")
	_reward(id)
	kit._retry_reward_records()
	_check(game.get_tool_count("hint") == 1 and _history_count() == 1, "duplicate SDK callback and retry do not duplicate history or award")
	_check(not kit.queue_direct_reward(id, [{"kind": "hint", "count": 1}], "duplicate"), "completed callback cannot accept another right")


func _test_retry(stage: String, transition: String) -> void:
	var page: Variant = await _open()
	var id: String = await _request(page)
	var before_sequence: int = game.get_core_store().snapshot().award_sequence
	var history_before: Array = page._business_history.duplicate(true)
	var before_board: Array = page._board_view.get_board()
	var armed := {"value": false}
	# 按真实业务阶段开启故障，不依赖这是整场测试的第几次写入。
	var on_commit := func(_revision: int) -> void:
		var ready: bool = _history_count() == 1 if stage == "register" else not game.get_in_flight_awards().is_empty()
		if not armed.value and ready:
			armed.value = true
			files.set_fault_injector_for_tests(_fail_writes)
	game.get_core_store().committed.connect(on_commit)
	_reward(id)
	game.get_core_store().committed.disconnect(on_commit)
	_check(armed.value and fault_hits > 0, stage + " failure injection reaches intended business phase")
	_check(_history_count() == 1 and game.get_tool_count("hint") == 0, stage + " failure preserves normal history without publishing inventory")
	_check(kit._pending_direct_rewards.has(id), stage + " failure retains accepted show entitlement")
	var pending: Array = game.get_in_flight_awards()
	_check(pending.size() == (1 if stage == "claim" else 0), stage + " durable pending matches actual registration outcome")
	var uid: int = int(kit._pending_direct_rewards.get(id, {}).get("uid", -1))
	_check((uid > 0) == (stage == "claim"), "registered uid is retained only after success")
	_check(page._business_history.duplicate(true) == history_before and page._board_view.get_board() == before_board, "ad only replenishes inventory; no automatic tool use")
	var timer: Timer = kit._reward_record_retry_timer
	_check(is_instance_valid(timer) and not timer.is_stopped(), stage + " failure starts shared retry timer")
	files.set_fault_injector_for_tests(Callable())
	if transition == "hide":
		await ui.hide_ui("game")
	elif transition == "new_round":
		ui.show_ui("game", {"level_index": 50})
		await _wait_ready(page)
	elif transition == "reset":
		_check(game.reset_all(), "explicit reset cancels old accepted right")
		var reset_inventory: int = game.get_tool_count("hint")
		_check(kit._pending_direct_rewards.is_empty() and timer.is_stopped(), "reset clears pending direct rights and timer")
		timer.timeout.emit()
		_reward(id)
		_check(game.get_tool_count("hint") == reset_inventory and game.get_in_flight_awards().is_empty(), "old retry and SDK callback cannot restore cleared rights")
		return
	timer.start(0.01)
	await create_timer(0.08).timeout
	_check(game.get_tool_count("hint") == 1, stage + "/" + transition + " accepted right recovers through real timer")
	_check(kit._pending_direct_rewards.is_empty() and game.get_in_flight_awards().is_empty() and timer.is_stopped(), "successful drain leaves no pending claim or polling")
	_check(int(game.get_core_store().snapshot().award_sequence) == before_sequence + 1, "retry registers exactly one award; claim failure reuses its uid")
	_reward(id)
	kit._on_reward_grant_timeout(id, "props_normal_hint")
	kit._retry_reward_records()
	_check(game.get_tool_count("hint") == 1 and game.get_pending_rewards().is_empty(), "late duplicate and watchdog cannot award again")
	var saved: Dictionary = files.load_result().config.get_value("core", "state")
	_check(int(saved.inventory.hint) == 1 and saved.pending_awards.is_empty(), "recovered actual inventory is durable")


func _test_reentrant_rewards() -> void:
	var page: Variant = await _open()
	var a: String = await _request(page)
	var b: String = await _request(page, "locate")
	var nested := {"done": false}
	var on_commit := func(_revision: int) -> void:
		if not nested.done and not game.get_in_flight_awards().is_empty():
			nested.done = true
			_reward(a)
			_reward(b)
	game.get_core_store().committed.connect(on_commit)
	_reward(b)
	game.get_core_store().committed.disconnect(on_commit)
	_check(nested.done, "out-of-order B registration synchronously receives A and duplicate B")
	kit._retry_reward_records()
	_check(game.get_tool_count("hint") == 1 and game.get_tool_count("locate") == 1, "nested awards retain their own identity and tool kind")
	_check(_history_count() == 2 and kit._pending_direct_rewards.is_empty(), "nested history and direct-right queues both drain exactly once")


func _test_multiple_failed_rewards() -> void:
	var page: Variant = await _open()
	var a: String = await _request(page)
	var b: String = await _request(page, "locate")
	files.set_fault_injector_for_tests(_fail_writes)
	_reward(b)
	_reward(a)
	_reward(b)
	_check(fault_hits > 0 and kit._pending_direct_rewards.size() == 2, "two out-of-order SDK rights survive simultaneous history and registration failures")
	_check(kit._pending_reward_history.size() == 2 and _history_count() == 0, "each failed history event also remains exactly once")
	_check(game.get_tool_count("hint") == 0 and game.get_tool_count("locate") == 0, "no partial inventory is published under failed writes")
	files.set_fault_injector_for_tests(Callable())
	kit._reward_record_retry_timer.start(0.01)
	await create_timer(0.08).timeout
	_check(game.get_tool_count("hint") == 1 and game.get_tool_count("locate") == 1 and _history_count() == 2, "one timer drains both histories and both actual grants")
	_check(kit._pending_direct_rewards.is_empty() and game.get_in_flight_awards().is_empty(), "batch recovery leaves no undelivered rights")


func _test_reset_during_commit(stage: String) -> void:
	var page: Variant = await _open()
	var id: String = await _request(page)
	var reset := {"done": false, "inventory": -1}
	var on_commit := func(_revision: int) -> void:
		var ready: bool = not game.get_in_flight_awards().is_empty() if stage == "register" else game.get_tool_count("hint") == 1
		if not reset.done and ready:
			reset.done = true
			_check(game.reset_all(), "synchronous reset succeeds during " + stage)
			reset.inventory = game.get_tool_count("hint")
	game.get_core_store().committed.connect(on_commit)
	_reward(id)
	game.get_core_store().committed.disconnect(on_commit)
	_check(reset.done, stage + " commit really enters reset listener")
	kit._retry_reward_records()
	_reward(id)
	_check(game.get_tool_count("hint") == reset.inventory and kit._pending_direct_rewards.is_empty(), stage + " stale result cannot claim into reset data")
	_check(game.get_in_flight_awards().is_empty() and _history_count() == 0, "reset state remains free of old award and history")
	_check(game.get_game_total_stat("normal", "rv_count") == 0, "old callback does not publish its ad count into reset player statistics")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + label)
