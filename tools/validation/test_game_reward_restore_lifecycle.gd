## 实际补发页与首页：动画取消、缓存重开、互斥监听和持久化失败后重试。
extends SceneTree

var checks: int = 0
var failures: int = 0
var ui: Node
var game: Node


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
	ui = root.get_node("UIManager")
	game = root.get_node("GameState")
	game.set_sound_on(false)
	game.set_music_on(false)
	await _test_page_lifecycle()
	await _test_home_flow()
	ui.hide_all()
	host.queue_free()
	await process_frame
	await process_frame
	print("REWARD RESTORE LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_page_lifecycle() -> void:
	var claims := {"count": 0}
	var claim := func() -> Dictionary:
		claims.count += 1
		return {"ok": true}
	var page: Variant = ui.show_ui("ad_reward_restored", _offer(1, claim))
	var collected: Array = []
	var closed: Array = []
	var on_collected := func(rewards: Array) -> void: collected.append(rewards)
	var on_closed := func() -> void: closed.append(true)
	page.collected.connect(on_collected)
	page.closed.connect(on_closed)
	page._on_collect_btn_tag_pressed()
	page._on_collect_btn_tag_pressed()
	page._on_close_btn_pressed()
	_check(claims.count == 1 and closed.is_empty(), "collect ignores repeated clicks and concurrent close")
	ui.hide_ui("ad_reward_restored")
	ui.show_ui("ad_reward_restored", _offer(9, claim))
	await create_timer(2.0).timeout
	_check(page.is_showing() and page.visible and page._rewards[0].count == 9, "old obtain animation cannot hide a reopened offer")
	_check(collected.is_empty() and ui._modal_mask.request_count() == 1, "cancelled offer emits no stale collection and retains current mask")
	_check(page._hint_slot.obtain_finished.get_connections().is_empty(), "cancelled obtain wait disconnects its listener")

	page._on_collect_btn_tag_pressed()
	ui.show_ui("ad_reward_restored", _offer(7, claim))
	await create_timer(2.0).timeout
	_check(page.is_showing() and page.visible and page._rewards[0].count == 7 and collected.is_empty(), "refresh of already shown cached offer invalidates the old animation")
	page.close()
	await _wait_hidden(page)
	_check(closed.size() == 1 and page.is_hidden() and not page.visible, "explicit close completes through manager lifecycle")
	_check(ui._modal_mask.request_count() == 0, "explicit close releases its modal request")

	ui.show_ui("ad_reward_restored", _offer(4, claim))
	page.close()
	ui.hide_ui("ad_reward_restored")
	ui.show_ui("ad_reward_restored", _offer(5, claim))
	await create_timer(0.6).timeout
	_check(page.is_showing() and page.visible and closed.size() == 1, "cancelled dismiss cannot close or cancel a newer offer")
	var show_next := func(_rewards: Array) -> void: ui.show_ui("ad_reward_restored", _offer(6, claim))
	page.collected.connect(show_next, CONNECT_ONE_SHOT)
	page._on_collect_btn_tag_pressed()
	await create_timer(2.5).timeout
	_check(collected.size() == 1 and collected[0][0].count == 5, "successful collection emits the captured reward batch once")
	_check(page.is_showing() and page.visible and page._rewards[0].count == 6, "collection listener may synchronously open the next offer")
	_check(ui._modal_mask.request_count() == 1, "reentrant next offer keeps exactly one modal request")
	page.collected.disconnect(on_collected)
	page.closed.disconnect(on_closed)
	ui.hide_ui("ad_reward_restored")
	await process_frame


func _test_home_flow() -> void:
	game.pop_all_pending_rewards()
	for i: int in 3:
		game.record_normal_reward(int(Time.get_unix_time_from_system()) - i)
	var home: Variant = ui.show_ui("home")
	await create_timer(0.7).timeout
	_check(game.get_restore_remaining_today(int(Time.get_unix_time_from_system())) == 3, "real product restore eligibility is available")
	for i: int in 2:
		_add_pending("decline_%d" % i)
		home._maybe_show_pending_rewards()
		await create_timer(0.5).timeout
		var page: Variant = ui.get_ui("ad_reward_restored")
		_check(page.is_showing() and page.collected.get_connections().size() == 1 and page.closed.get_connections().size() == 1, "each home offer owns exactly two mutually exclusive listeners %d" % i)
		page.close()
		await _wait_hidden(page)
		await process_frame
		_check(page.collected.get_connections().is_empty() and page.closed.get_connections().is_empty(), "decline cleans both result listeners %d" % i)
		_check(not game.has_pending_rewards(), "explicit decline retires only the shown pending offer %d" % i)

	_add_pending("interrupted")
	home._maybe_show_pending_rewards()
	await create_timer(0.5).timeout
	var page: Variant = ui.get_ui("ad_reward_restored")
	ui.hide_ui("ad_reward_restored")
	await process_frame
	await process_frame
	_check(game.has_pending_rewards() and page.collected.get_connections().is_empty() and page.closed.get_connections().is_empty(), "external popup hide preserves pending eligibility and cleans both listeners")
	home._maybe_show_pending_rewards()
	await create_timer(0.5).timeout
	ui.hide_ui("home")
	await process_frame
	await process_frame
	_check(game.has_pending_rewards() and page.is_hidden(), "leaving home cancels its unfinished offer without losing eligibility")
	_check(page.collected.get_connections().is_empty() and page.closed.get_connections().is_empty(), "leaving home cleans both listeners")

	ui.show_ui("home")
	await create_timer(0.7).timeout
	_check(page.is_showing() and page.collected.get_connections().size() == 1 and page.closed.get_connections().size() == 1, "returning home resumes the preserved offer with one listener pair")
	var before: int = game.get_tool_count("hint")
	var files: RefCounted = game._product_store.files
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	page._on_collect_btn_tag_pressed()
	await process_frame
	_check(page.is_showing() and not page._closing and game.get_tool_count("hint") == before and game.has_pending_rewards(), "failed durable claim leaves offer retryable without granting or losing eligibility")
	files.set_fault_injector_for_tests(Callable())
	page._on_collect_btn_tag_pressed()
	await _wait_hidden(page)
	await process_frame
	_check(page.is_hidden() and not page.visible and ui._modal_mask.request_count() == 0, "successful retry closes the real offer and releases its mask")
	_check(game.get_tool_count("hint") == before + 1 and not game.has_pending_rewards() and game.get_restored_today_count() == 1, "successful retry commits inventory eligibility and quota exactly once")
	_check(page.collected.get_connections().is_empty() and page.closed.get_connections().is_empty(), "successful claim also cleans the unused close listener")
	_check(game._product_store.files.load_result().config.get_value("core", "state").inventory.hint == before + 1, "reward is present in the isolated durable save")


func _offer(count: int, claim: Callable) -> Dictionary:
	return {"rewards": [{"kind": "hint", "count": count}], "claim": claim}


func _add_pending(id: String) -> void:
	game.add_pending_reward({"show_id": id, "source": "props_normal_hint", "ts": int(Time.get_unix_time_from_system())})


func _wait_hidden(page: UIFrameWindow) -> void:
	var deadline: int = Time.get_ticks_msec() + 4000
	while page.is_showing() and Time.get_ticks_msec() < deadline:
		await process_frame


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEST_FAILED: " + label)
