## 真实页面连续广告：未决奖励按展示身份保留，业务代次结束后失效。
extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node
var ui: Node
var kit: Node
var _saved_core_validator: Callable


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
	var ab: Node = root.get_node("ABTestManager")
	ab.daily_first_level_difficulty.set_debug_override(0)
	ab.normal_endgame_save.set_debug_override(0)
	ab.common_rewardad_logic.set_debug_override(1)
	ab.reward_unlock_level.set_debug_override(0)
	ab.revive_free_logic.set_debug_override(0)
	ab.dc_level.set_debug_override(0)
	ab.game_auto_mark.set_debug_override(0)
	kit.cheat_show_reward = true
	for different_tool: bool in [false, true]:
		for reverse: bool in [false, true]:
			await _test_tool_requests(different_tool, reverse)
	await _test_covered_page()
	await _test_daily_cached_observer()
	for transition: String in ["hide", "refresh", "destroy"]:
		await _test_tool_generation(transition)
	for mode: String in ["game", "daily_game"]:
		await _test_revive_requests(mode, false)
		await _test_revive_requests(mode, true)
		await _test_revive_requests(mode, false, true)
		await _test_revive_requests(mode, true, true)
		await _test_revive_burst(mode, 3, 0)
		await _test_revive_burst(mode, 5, 0)
		await _test_revive_burst(mode, 3, 1)
		await _test_revive_burst(mode, 3, 2)
		await _test_revive_burst(mode, 3, 3)
		await _test_revive_cancelled_retry(mode, false)
		await _test_revive_cancelled_retry(mode, true)
	await _test_covered_daily_revive()
	ui.hide_all()
	await create_timer(0.7).timeout
	print("GAME REWARD REQUEST TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _open(mode: String = "game") -> Variant:
	ui.hide_all()
	await create_timer(0.4).timeout
	_check(game.reset_all(), "prepare isolated player state")
	game.set_sound_on(false)
	game.set_tutorial_done(true)
	game.set_current_level(50)
	game.set_tool_count("hint", 0)
	game.set_tool_count("locate", 0)
	var page: Variant = ui.show_ui(mode, {"level_index": 50} if mode == "game" else {})
	await _wait_ready(page)
	page._last_tool_deplete_ms = -10000
	_check(page._is_round_entry_ready(), mode + " real entry ready")
	return page


func _wait_ready(page: Variant) -> void:
	var deadline: int = Time.get_ticks_msec() + 8000
	while (not page._entry_ready or page._entry_anim_playing) and Time.get_ticks_msec() < deadline:
		await process_frame


func _request_tool(page: Variant, kind: String) -> String:
	var button: Variant = page.get("_tool_" + kind + "_btn")
	button.pressed.emit()
	var id: String = kit._reward_active_show_id
	_check(not id.is_empty() and kit._reward_callbacks.has(id), "actual " + kind + " button registers and starts its reward")
	return id


func _close_mock() -> void:
	var mock: Variant = ui.get_ui("mock_ad")
	_check(mock != null and mock.is_showing(), "actual Mock ad is open")
	if mock == null:
		return
	mock._on_close_pressed()
	var deadline: int = Time.get_ticks_msec() + 2000
	while not mock.is_hidden() and Time.get_ticks_msec() < deadline:
		await process_frame


func _reward(id: String) -> void:
	kit._on_ad_rewarded_for_show("reward", id)


func _test_tool_requests(different_tool: bool, reverse: bool) -> void:
	var page: Variant = await _open()
	var generation: int = page._business_generation
	var a: String = _request_tool(page, "hint")
	await _close_mock()
	var b: String = _request_tool(page, "locate" if different_tool else "hint")
	await _close_mock()
	_check(a != b and page._business_generation == generation, "two shows belong to one real page generation")
	_check(kit._reward_callbacks.has(a) and kit._reward_callbacks.has(b), "request B retains unresolved A consumer")
	_reward(b if reverse else a)
	_reward(a if reverse else b)
	_reward(a)
	_reward(b)
	kit._on_reward_grant_timeout(a, "props_normal_hint")
	kit._on_reward_grant_timeout(b, "props_normal_locate" if different_tool else "props_normal_hint")
	_check(game.get_tool_count("hint") == (1 if different_tool else 2), "both reward orders deliver each earned hint once")
	_check(game.get_tool_count("locate") == (1 if different_tool else 0), "different tool requests preserve their own reward kind")
	_check(game.get_pending_rewards().is_empty(), "delivered rewards have no duplicate compensation")


func _test_covered_page() -> void:
	var page: Variant = await _open()
	var id: String = _request_tool(page, "hint")
	await _close_mock()
	var cover: Variant = ui.show_ui("home")
	# 通过真实管理器施加全屏遮挡；产品首页默认没有开启该窗口能力。
	cover.is_fullscreen = true
	ui._refresh_occlusion()
	_check(page.is_showing() and not page.visible, "full-screen home covers a still-open gameplay page")
	_reward(id)
	_check(game.get_tool_count("hint") == 1, "occlusion does not invalidate this page generation's earned tool")
	await ui.hide_ui("home")
	cover.is_fullscreen = false


func _test_tool_generation(transition: String) -> void:
	var page: Variant = await _open()
	var id: String = _request_tool(page, "hint")
	await _close_mock()
	var callback: Callable = kit._reward_callbacks[id]
	var generation: int = page._business_generation
	if transition == "destroy":
		page._do_destroy()
		page.queue_free()
	else:
		if transition == "hide":
			await ui.hide_ui("game")
		ui.show_ui("game", {"level_index": 50})
		await _wait_ready(page)
	_check(page._business_generation != generation and not kit._reward_callbacks.has(id), transition + " revokes old generation consumers")
	# 外部已取得 Callable 也必须受代次约束；直接销毁的节点此时尚未帧末释放。
	callback.call("reward")
	_reward(id)
	_check(game.get_tool_count("hint") == 0, transition + " rejects old reward without granting it to a reused page")
	await process_frame


func _test_daily_cached_observer() -> void:
	var page: Variant = await _open("daily_game")
	_check(kit.ad_closed.is_connected(page._on_ad_closed), "daily page installs its lifetime ad-time observer")
	await ui.hide_ui("daily_game")
	ui.show_ui("daily_game")
	await _wait_ready(page)
	_check(kit.ad_closed.is_connected(page._on_ad_closed), "cached daily hide/reopen retains the lifetime close observer")
	page._ad_show_unix = Time.get_unix_time_from_system() - 5.0
	var before: float = page._start_unix
	kit.ad_closed.emit("reward")
	_check(page._start_unix - before >= 5.0 and page._start_unix - before < 6.0 and page._ad_show_unix == 0.0, "cached daily close removes the observed ad duration from play time")
	var a: String = _request_tool(page, "hint")
	await _close_mock()
	var b: String = _request_tool(page, "locate")
	await _close_mock()
	_reward(b)
	_reward(a)
	_check(game.get_tool_count("hint") == 1 and game.get_tool_count("locate") == 1, "cached daily page also keeps both tool reward consumers")
	_check(kit.ad_closed.is_connected(page._on_ad_closed), "consecutive daily rewards preserve the lifetime close observer")


func _test_revive_requests(mode: String, fail_first: bool, reentrant: bool = false) -> void:
	var page: Variant = await _open(mode)
	_check(page._ensure_business_round().get("ok", false), mode + " durable round before failure")
	page._lives = 0
	page._on_game_over()
	var fail: Variant = ui.get_ui("fail" if mode == "game" else "daily_fail")
	_check(page._is_complete and fail != null and fail.is_showing(), mode + " real failure opens revive page")
	if fail == null:
		return
	_check(not fail._revive_offer().free, mode + " fixture requires an ad")
	var stats: String = "normal" if mode == "game" else "daily"
	var count_before: int = game.get_game_total_stat(stats, "revive_count")
	var attempt_before: int = page._business_attempt_sequence
	var local_before: int = int(page._revive_count) if mode == "game" else 0
	fail._on_revive_btn_pressed()
	var a: String = kit._reward_active_show_id
	await _close_mock()
	fail._on_revive_btn_pressed()
	var b: String = kit._reward_active_show_id
	await _close_mock()
	_check(not a.is_empty() and a != b and kit._reward_callbacks.has(a) and kit._reward_callbacks.has(b), mode + " failure retains both unresolved shows")
	var state_key: String = "doku/main" if mode == "game" else "doku/daily"
	var entered := {"done": false}
	var on_commit := func(_revision: int) -> void:
		var record: Dictionary = game.get_core_store().snapshot().round_services[state_key]
		if not entered.done and record.last_receipt.get("kind") == "revive":
			entered.done = true
			_reward(b)
	var on_failure := func(_result: Dictionary) -> void:
		if not entered.done:
			entered.done = true
			_reward(b)
	if reentrant and fail_first:
		game.storage_failed.connect(on_failure)
		_fail_revive_commits(state_key, 1)
	elif reentrant:
		game.get_core_store().committed.connect(on_commit)
	elif fail_first:
		game._product_store.files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_reward(a)
	if reentrant:
		_check(entered.done, mode + " second reward arrives inside the first revive commit notification")
		if fail_first:
			game.storage_failed.disconnect(on_failure)
		else:
			game.get_core_store().committed.disconnect(on_commit)
	elif fail_first:
		_check(page._is_complete and fail.is_showing() and page._business_attempt_sequence == attempt_before, mode + " rejected revive leaves the failure retryable")
	if fail_first:
		_clear_commit_fault()
	_reward(b)
	_reward(a)
	_reward(b)
	_check(not page._is_complete and page._lives > 0, mode + " one earned reward successfully revives")
	_check(page._business_attempt_sequence == attempt_before + 1, mode + " two show IDs advance the attempt only once")
	_check(game.get_core_store().snapshot().round_services[state_key].snapshot.attempt_sequence == attempt_before + 1, mode + " authoritative attempt advances once")
	_check(game.get_game_total_stat(stats, "revive_count") == count_before + 1, mode + " two show IDs count one successful revive")
	if mode == "game":
		_check(page._revive_count == local_before + 1, "main page counts this revive once")
	_check(not kit._reward_callbacks.has(a) and not kit._reward_callbacks.has(b), mode + " successful revive cancels other consumers of that failure")
	await create_timer(0.4).timeout


## 三笔以上同时在第一笔提交的通知内回奖，随后继续真实业务，而非只看复活动画。
func _test_revive_burst(mode: String, show_count: int, failed_commits: int) -> void:
	var page: Variant = await _open(mode)
	var fail: Variant = _fail_round(page, mode)
	if fail == null:
		return
	var ids: Array[String] = await _request_revives(fail, show_count)
	var state_key: String = "doku/main" if mode == "game" else "doku/daily"
	var stats: String = "normal" if mode == "game" else "daily"
	var before: int = page._business_attempt_sequence
	var count_before: int = game.get_game_total_stat(stats, "revive_count")
	var entered := {"done": false}
	var send_remaining := func() -> void:
		if entered.done:
			return
		entered.done = true
		for index: int in range(1, ids.size()):
			_reward(ids[index])
	var on_commit := func(_revision: int) -> void:
		var record: Dictionary = game.get_core_store().snapshot().round_services[state_key]
		if record.last_receipt.get("kind") == "revive":
			send_remaining.call()
	var on_failure := func(_result: Dictionary) -> void:
		send_remaining.call()
	var writes: Dictionary = {}
	if failed_commits > 0:
		game.storage_failed.connect(on_failure)
		writes = _fail_revive_commits(state_key, failed_commits)
	else:
		game.get_core_store().committed.connect(on_commit)
	var observe_close: bool = show_count == 3 and failed_commits == 0
	var closing := {"seen": false, "reward_returned": false}
	var on_animation := func(name: StringName) -> void:
		if name != &"disappear" or closing.seen:
			return
		closing.seen = true
		_check(not closing.reward_returned, mode + " failure close animation starts synchronously inside the reward call")
		_check(not page._is_complete and page._lives > 0 and page._business_attempt_sequence == before + 1, mode + " live state is published before close callbacks run")
		# 真实退场信号中同步请求复活：已成功的失败权益不能再执行。
		fail.revive_requested.emit({})
	if observe_close:
		fail._anim.animation_started.connect(on_animation)
	_reward(ids[0])
	closing.reward_returned = true
	if observe_close:
		_check(closing.seen, mode + " actual failure close emits the observed animation signal")
		fail._anim.animation_started.disconnect(on_animation)
	if failed_commits > 0:
		game.storage_failed.disconnect(on_failure)
		_clear_commit_fault()
		_check(writes.failed == failed_commits, mode + " burst injects failure into the revive commit")
	else:
		game.get_core_store().committed.disconnect(on_commit)
	var label := "%s %d rewards/failures=%d: " % [mode, show_count, failed_commits]
	_check(entered.done, label + "all remaining earned rewards arrive inside the first commit notification")
	if failed_commits == show_count:
		_check(page._is_complete and fail.is_showing(), label + "exhausting failed intents leaves this failure retryable")
		_check(game.get_core_store().snapshot().round_services[state_key].snapshot.attempt_sequence == before, label + "failed burst does not advance the durable attempt")
		_check(game.get_game_total_stat(stats, "revive_count") == count_before, label + "failed burst publishes no successful revive")
		_check(fail._earned_revive and fail._revive_main_label.text == tr("FAIL_TRY_AGAIN"), label + "earned retry is retained and presented")
		_check(not fail._revive_ad_icon.visible and not fail._revive_badge.visible, label + "retry no longer advertises another ad")
		var old_show: String = kit._reward_active_show_id
		var failed_retry: Dictionary = _fail_revive_commits(state_key, 1)
		fail._on_revive_btn_pressed()
		_clear_commit_fault()
		_check(failed_retry.failed == 1 and fail._earned_revive and page._is_complete, label + "manual retry can fail without consuming the earned right")
		fail._on_revive_btn_pressed()
		_check(kit._reward_active_show_id == old_show and not ui.get_ui("mock_ad").is_showing(), label + "retry succeeds without requesting another ad")
	_check(not page._is_complete and page._lives > 0, label + "one effective revive restores play")
	_check(page._business_attempt_sequence == before + 1, label + "presentation attempt advances exactly once")
	_check(game.get_core_store().snapshot().round_services[state_key].snapshot.attempt_sequence == before + 1, label + "durable attempt advances exactly once")
	_check(game.get_game_total_stat(stats, "revive_count") == count_before + 1, label + "one successful revive is counted")
	_check(not fail._earned_revive, label + "successful revive consumes the page-local right")
	for id: String in ids:
		_reward(id)
	_check(game.get_game_total_stat(stats, "revive_count") == count_before + 1, label + "duplicate callbacks stay inert after the burst")
	var located: Dictionary = page._execute_business_action("locate", {}, {"locate_cost": 0})
	_check(located.get("ok", false) and not located.get("duplicate", false), label + "next distinct business action has no sequence collision")
	_check(game.get_core_store().snapshot().round_services[state_key].snapshot.attempt_sequence == before + 1, label + "following tool does not change the revive attempt")
	await create_timer(0.4).timeout
	fail = _fail_round(page, mode)
	if fail == null:
		return
	_check(not fail._earned_revive, label + "the next failure cannot reuse an old earned right")
	var next_ids: Array[String] = await _request_revives(fail, 1)
	_reward(next_ids[0])
	_check(not page._is_complete and page._business_attempt_sequence == before + 2, label + "a later genuine failure can revive independently")
	_check(game.get_game_total_stat(stats, "revive_count") == count_before + 2, label + "the next failure publishes its own statistic once")
	located = page._execute_business_action("locate", {}, {"locate_cost": 0})
	_check(located.get("ok", false), label + "play still works after the second failure and revive")
	await create_timer(0.4).timeout


func _fail_round(page: Variant, mode: String) -> Variant:
	_check(page._ensure_business_round().get("ok", false), mode + " has a durable round before failing")
	page._lives = 0
	page._on_game_over()
	var fail: Variant = ui.get_ui("fail" if mode == "game" else "daily_fail")
	_check(page._is_complete and fail != null and fail.is_showing(), mode + " failure opens its real revive page")
	return fail


func _request_revives(fail: Variant, count: int) -> Array[String]:
	var ids: Array[String] = []
	for index: int in count:
		fail._on_revive_btn_pressed()
		var id: String = kit._reward_active_show_id
		_check(not id.is_empty() and not ids.has(id) and kit._reward_callbacks.has(id), "real revive button creates a distinct unresolved ad")
		ids.append(id)
		await _close_mock()
	return ids


## A 写失败的通知先送达 B/C，再立即离页；排队的旧权益不能复活已关闭的对局。
func _test_revive_cancelled_retry(mode: String, refresh: bool) -> void:
	var page: Variant = await _open(mode)
	var fail: Variant = _fail_round(page, mode)
	if fail == null:
		return
	var ids: Array[String] = await _request_revives(fail, 3)
	var state_key: String = "doku/main" if mode == "game" else "doku/daily"
	var before: int = page._business_attempt_sequence
	var generation: int = page._business_generation
	var entered := {"done": false}
	var on_failure := func(_result: Dictionary) -> void:
		if entered.done:
			return
		entered.done = true
		_reward(ids[1])
		_reward(ids[2])
		ui.hide_ui("fail" if mode == "game" else "daily_fail")
		if refresh:
			ui.show_ui(mode, {"level_index": 50} if mode == "game" else {})
		else:
			ui.hide_ui(mode)
	game.storage_failed.connect(on_failure)
	var writes: Dictionary = _fail_revive_commits(state_key, 1)
	_reward(ids[0])
	game.storage_failed.disconnect(on_failure)
	_clear_commit_fault()
	var label: String = mode + (" refresh: " if refresh else " hide: ")
	_check(writes.failed == 1 and not fail._earned_revive, label + "leaving clears the earned retry after a real revive write failure")
	_check(entered.done and page._business_generation != generation, label + "failure notification ends the old business generation")
	_check(game.get_core_store().snapshot().round_services[state_key].snapshot.attempt_sequence == before, label + "queued late rewards do not commit after leaving")
	await create_timer(0.4).timeout
	if not refresh:
		ui.show_ui(mode, {"level_index": 50} if mode == "game" else {})
	await _wait_ready(page)
	_check(page._is_round_entry_ready() and not page._is_complete and page._business_attempt_sequence == 0, label + "cached reopen is independent of cancelled retry intents")
	_check(page._execute_business_action("locate", {}, {"locate_cost": 0}).get("ok", false), label + "new generation accepts its own business action")


func _test_covered_daily_revive() -> void:
	var page: Variant = await _open("daily_game")
	var fail: Variant = _fail_round(page, "daily_game")
	if fail == null:
		return
	var ids: Array[String] = await _request_revives(fail, 1)
	var cover: Variant = ui.show_ui("home")
	cover.is_fullscreen = true
	ui._refresh_occlusion()
	_check(page.is_showing() and fail.is_showing() and not page.visible and not fail.visible, "full-screen cover occludes both live daily pages")
	_reward(ids[0])
	_check(not page._is_complete and page._lives > 0 and page._business_attempt_sequence == 1, "covered daily page accepts its valid earned revive")
	_check(game.get_game_total_stat("daily", "revive_count") == 1, "covered revive is counted once")
	await ui.hide_ui("home")
	cover.is_fullscreen = false
	_check(page._execute_business_action("locate", {}, {"locate_cost": 0}).get("ok", false), "uncovered daily page continues normal business after revive")


## 测试在候选校验边界辨认新复活事务，再使用原文件层故障钩子。
## 不依赖领奖历史、统计等无关写入的顺序，也不让存储实现认识游戏动作。
func _fail_revive_commits(state_key: String, count: int) -> Dictionary:
	var core = game.get_core_store()
	_saved_core_validator = core._validator
	var original: Callable = _saved_core_validator
	var observed := {"failed": 0, "target": false}
	core._validator = func(candidate: Dictionary) -> String:
		var error: String = original.call(candidate)
		var record: Dictionary = candidate.get("round_services", {}).get(state_key, {})
		var previous: Dictionary = core.snapshot().get("round_services", {}).get(state_key, {})
		# 候选之后还会校验磁盘槽；锁存目标直到本次写入抵达提交点，不能被旧快照覆盖。
		observed.target = observed.target or (error.is_empty() and record.get("last_receipt", {}).get("kind") == "revive" \
			and int(record.get("last_sequence", 0)) > int(previous.get("last_sequence", 0))
		)
		return error
	game._product_store.files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase != "before_replace":
			return false
		var target: bool = observed.target
		observed.target = false
		if target and observed.failed < count:
			observed.failed += 1
			return true
		return false)
	return observed


func _clear_commit_fault() -> void:
	game._product_store.files.set_fault_injector_for_tests(Callable())
	if _saved_core_validator.is_valid():
		game.get_core_store()._validator = _saved_core_validator
	_saved_core_validator = Callable()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + label)
