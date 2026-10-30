## 真实奖励/签到的同步交接：旧领取/关闭/签到结果不能改变回调中新展示或清档后的状态。
extends SceneTree
var checks: int = 0
var failures: int = 0
var game: Node
var awards: Node
var ui: Node
var streak: Node
var files: RefCounted


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
	awards = root.get_node("AwardManager")
	ui = root.get_node("UIManager")
	streak = root.get_node("StreakManager")
	files = game.get_core_store().get("_file_store")
	root.get_node("ABTestManager").daily_streak.set_debug_override(1)
	for action: String in ["collect", "double", "hide", "failed_collect"]:
		await _test_award_replaced_during_commit(action)
	await _test_streak_reset_during_checkin()
	await _test_old_ad_callback()
	await _test_award_shown_reentry()
	await _test_failed_claim_reentry()
	await _test_switch_gift_reopened()
	await _test_covered_streak_input()
	await _test_streak_presentation_reopened(false)
	await _test_streak_presentation_reopened(true)
	ui.hide_all()
	await create_timer(0.4).timeout
	for name: String in ["award", "streak", "reward_claim_popup", "mock_ad", "toast"]:
		ui.destroy_ui(name)
	await process_frame
	print("PRODUCT REWARD OWNERSHIP TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _reset() -> void:
	files.set_fault_injector_for_tests(Callable())
	ui.hide_all()
	await process_frame
	_check(game.reset_all(), "reset isolated player")
	game.set_sound_on(false)
	game.set_tutorial_done(true)


func _test_award_replaced_during_commit(action: String) -> void:
	await _reset()
	var hint_before: int = game.get_tool_count("hint")
	var locate_before: int = game.get_tool_count("locate")
	var first: int = awards.dispatch([{"kind": "hint", "count": 2}], 1, "ownership_a", "ownership_a_double")
	var second: int = awards.dispatch([{"kind": "locate", "count": 3}], 1, "ownership_b", "ownership_b_double")
	awards.show_award(first)
	var page: Variant = ui.get_ui("award")
	await _wait_gift_ready(page, "_test_award_replaced_during_commit")
	_check(page != null and page._streak_uid == first, action + " displays first actual reward")
	var state := {"called": false}
	var replace := func() -> void:
		if state.called:
			return
		state.called = true
		awards.show_award(second)
	var committed := func(_revision: int) -> void:
		var pending: Dictionary = game.find_in_flight_award(first)
		if (action == "double" and pending.get("doubled", false)) or (action != "double" and pending.is_empty()):
			replace.call()
	if action == "failed_collect":
		files.set_fault_injector_for_tests(func(phase: String) -> bool:
			if phase != "before_replace":
				return false
			replace.call()
			return true
		)
	else:
		game.get_core_store().committed.connect(committed)
	if action == "hide":
		ui.hide_ui("award")
	else:
		if action == "double":
			page._double_pending = true
		page._on_collect_pressed()
	if action != "failed_collect":
		game.get_core_store().committed.disconnect(committed)
	files.set_fault_injector_for_tests(Callable())
	await process_frame
	_check(state.called, action + " reaches actual save notification and replaces cached page")
	_check(page.is_showing() and page.visible and page._streak_uid == second, action + " old continuation cannot close or clear second reward")
	_check(game.get_tool_count("locate") == locate_before and not game.find_in_flight_award(second).is_empty(), action + " second reward remains unclaimed until its own input")
	_check(page._on_persisted.is_valid(), action + " second reward retains its own collect callback")
	await _wait_gift_ready(page, "_test_award_replaced_during_commit")
	var expected_hint: int = hint_before + (2 if action in ["collect", "hide"] else 0)
	_check(game.get_tool_count("hint") == expected_hint, action + " first result preserves only its committed grant")
	page._on_collect_pressed()
	await process_frame
	_check(game.get_tool_count("locate") == locate_before + 3 and game.find_in_flight_award(second).is_empty(), action + " second input claims exactly second reward")
	if action == "double":
		_check(game.find_in_flight_award(first).get("doubled", false), "interrupted first double remains durably pending")
		awards.show_award(first)
		await _wait_gift_ready(page, "_test_award_replaced_during_commit")
		page._on_collect_pressed()
		_check(game.get_tool_count("hint") == hint_before + 4, "first doubled reward remains claimable later")


func _test_streak_reset_during_checkin() -> void:
	await _reset()
	var prior: Dictionary = {"current_streak": 6, "best_streak": 6, "reward_cycle_day": 6,
		"last_checkin_date": streak._date_offset_str(-1), "streak_start_weekday": 1,
		"last_group": 1, "pending_switch_page": 0}
	_check(game.commit_streak_data(prior), "prepare actual seventh-day eligibility")
	var events: Array = []
	var observed := func(value: Dictionary) -> void: events.append(value.duplicate(true))
	streak.checkin_completed.connect(observed)
	var state := {"called": false}
	var listener := func(_revision: int) -> void:
		if state.called or game.get_streak_data().get("current_streak", 0) != 7:
			return
		state.called = true
		_check(game.reset_all(), "reset within successful check-in commit")
	game.get_core_store().committed.connect(listener)
	var result: Dictionary = streak.do_checkin()
	game.get_core_store().committed.disconnect(listener)
	streak.checkin_completed.disconnect(observed)
	_check(state.called, "check-in entered controlled reset callback")
	_check(game.get_streak_data().get("current_streak", 0) == 0 and game.get_in_flight_awards().is_empty(), "reset remains authoritative durable state")
	_check(not streak.has_pending_show(), "old receipt cannot recreate pending presentation after reset")
	_check(events.is_empty() and not result.get("has_reward", false), "old receipt cannot announce seventh-day reward in cleared player")
	var next: Dictionary = streak.do_checkin()
	_check(next.get("ok", false) and streak.get_data().current_streak == 1, "subsequent new-player check-in still works")


func _test_old_ad_callback() -> void:
	await _reset()
	var kit: Node = root.get_node("UniKitManager")
	kit.cheat_show_reward = true
	root.get_node("ABTestManager").common_rewardad_logic.set_debug_override(1)
	root.get_node("ABTestManager").reward_unlock_level.set_debug_override(0)
	var first: int = awards.dispatch([{"kind": "hint", "count": 2}], 1, "ad_ownership_a", "ad_ownership_a_double")
	var second: int = awards.dispatch([{"kind": "locate", "count": 3}], 1, "ad_ownership_b", "ad_ownership_b_double")
	awards.show_award(first)
	var page: Variant = ui.get_ui("award")
	await _wait_gift_ready(page, "_test_old_ad_callback")
	await page._on_collect_double_pressed()
	var show_id: String = kit._reward_active_show_id
	_check(not show_id.is_empty() and kit._reward_callbacks.has(show_id), "actual double button registers identified Mock reward")
	if show_id.is_empty() or not kit._reward_callbacks.has(show_id):
		return
	var old_callback: Callable = kit._reward_callbacks[show_id]
	var locate_before: int = game.get_tool_count("locate")
	awards.show_award(second)
	_check(not kit._reward_callbacks.has(show_id), "directly reused reward page revokes old ad consumer")
	old_callback.call("reward")
	kit._on_ad_closed_for_show("reward", show_id)
	_check(page.is_showing() and page._streak_uid == second, "old ad callbacks cannot close replacement reward page")
	_check(game.get_tool_count("locate") == locate_before and not game.find_in_flight_award(second).get("doubled", false), "old ad cannot grant or double replacement reward")
	ui.hide_ui("mock_ad")
	await _wait_gift_ready(page, "_test_old_ad_callback")
	page._on_collect_pressed()
	_check(game.get_tool_count("locate") == locate_before + 3, "replacement reward remains normally claimable")


func _test_award_shown_reentry() -> void:
	await _reset()
	var first: int = awards.dispatch([{"kind": "hint", "count": 2}], 1, "shown_a")
	var second: int = awards.dispatch([{"kind": "locate", "count": 3}], 1, "shown_b")
	var state := {"called": false}
	var listener := func(name: String, _page: Node) -> void:
		if name == "award" and not state.called:
			state.called = true
			awards.show_award(second)
	ui.events.window_shown.connect(listener)
	awards.show_award(first)
	ui.events.window_shown.disconnect(listener)
	var page: Variant = ui.get_ui("award")
	await _wait_gift_ready(page, "_test_award_shown_reentry")
	_check(state.called, "actual shown notification opens a newer reward")
	_check(page._streak_uid == second, "outer render cannot overwrite newly shown reward data")
	var before: int = game.get_tool_count("locate")
	page._on_collect_pressed()
	_check(game.get_tool_count("locate") == before + 3 and not game.find_in_flight_award(first).is_empty(), "new shown reward keeps its own collect action")


func _test_streak_presentation_reopened(with_reward: bool) -> void:
	await _reset()
	var day: int = 6 if with_reward else 0
	_check(game.commit_streak_data({"current_streak": day, "best_streak": day, "reward_cycle_day": day,
		"last_checkin_date": streak._date_offset_str(-1), "streak_start_weekday": 1,
		"last_group": 1, "pending_switch_page": 0}), "prepare actual pending streak presentation")
	_check(streak.do_checkin().get("ok", false), "actual checkin creates pending presentation")
	var pending: int = streak.get_pending_show_uid()
	var page: Variant = ui.show_ui("streak", {"state": 2})
	if with_reward:
		# The first delay has completed; abandon during the real chest animation.
		await create_timer(0.4).timeout
	ui.hide_ui("streak")
	ui.show_ui("streak", {"state": 0})
	await create_timer(2.0 if with_reward else 0.6).timeout
	_check(page.is_showing() and page._state == 0, "new regular streak page remains current")
	_check(streak.get_pending_show_uid() == pending, "old settle wait cannot consume pending presentation after reopening")
	var reward: Variant = ui.get_ui("award")
	_check(reward == null or not reward.is_showing(), "old settle wait cannot open reward over a new regular page")


func _test_failed_claim_reentry() -> void:
	await _reset()
	var uid: int = awards.dispatch([{"kind": "hint", "count": 2}], 1, "reentrant_failed_claim")
	awards.show_award(uid)
	var page: Variant = ui.get_ui("award")
	await _wait_gift_ready(page, "_test_failed_claim_reentry")
	var before: int = game.get_tool_count("hint")
	var state := {"called": false}
	files.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase != "before_replace":
			return false
		if not state.called:
			state.called = true
			page._on_collect_pressed()
		return true
	)
	page._on_collect_pressed()
	files.set_fault_injector_for_tests(Callable())
	_check(state.called and page.is_showing() and page._on_persisted.is_valid(), "nested input during failed claim cannot close or lose retry")
	_check(game.get_tool_count("hint") == before and not game.find_in_flight_award(uid).is_empty(), "failed nested claim leaves reward and balance intact")
	page._on_collect_pressed()
	_check(game.get_tool_count("hint") == before + 2 and page.is_hidden(), "same actual claim button retries once after storage recovery")


func _test_switch_gift_reopened() -> void:
	await _reset()
	# 旧切组界面已退役；保留旧档礼包资格，经 1.22 通用领取页验证相同交接边界。
	var data: Dictionary = game.get_streak_data().duplicate(true)
	data.pending_switch_page = 1
	data.last_group = 3
	var registered: Dictionary = game.commit_streak_transition(data, [{"kind": "hint", "count": 2}], "switch_reentry")
	_check(registered.get("ok", false), "legacy switch transition still registers one candidate gift")
	var uid: int = int(game.get_streak_data().get("switch_award_uid", 0))
	_check(uid > 0, "switch fixture has a real unclaimed award")
	var second: int = awards.dispatch([{"kind": "locate", "count": 3}], 1, "switch_replacement")
	var item_script: Script = load("res://products/meowdoku/app/features/award/model/award_item.gd")
	var params := {"items": [item_script.make("hint", 2)], "claim": func() -> bool: return awards._persist_award(uid)}
	var replacement := {"items": [item_script.make("locate", 3)], "claim": func() -> bool: return awards._persist_award(second)}
	var page: Variant = ui.show_ui("reward_claim_popup", params)
	var state := {"called": false}
	var before: int = game.get_tool_count("locate")
	var listener := func(_revision: int) -> void:
		if not state.called and game.find_in_flight_award(uid).is_empty():
			state.called = true
			ui.show_ui("reward_claim_popup", replacement)
	game.get_core_store().committed.connect(listener)
	page._on_action_pressed()
	game.get_core_store().committed.disconnect(listener)
	_check(state.called and page.is_showing() and not page._claiming, "old successful gift cannot close or lock a synchronously reopened 1.22 popup")
	_check(game.get_tool_count("locate") == before and not game.find_in_flight_award(second).is_empty(), "replacement popup retains its distinct unclaimed gift")
	page._on_action_pressed()
	_check(page.is_hidden() and game.get_tool_count("locate") == before + 3, "replacement uses its own claim callback exactly once")


func _test_covered_streak_input() -> void:
	await _reset()
	var page: Variant = ui.show_ui("streak", {"state": 1})
	page._lit_enter_done = true
	page.visible = false
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	page._input(press)
	_check(page._state == 1 and not page._lit_consumed, "occluded lit page ignores global input")
	page.visible = true
	page._input(press)
	_check(page._state == 2 and page._lit_consumed, "visible lit page still responds normally")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)


func _wait_gift_ready(page: Variant, context: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while is_instance_valid(page) and page.is_showing() and page._buttons_locked and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(is_instance_valid(page) and page.is_showing() and not page._buttons_locked, "1.22 actual reward input waits for gift appearance: " + context + " uid=" + str(page._streak_uid) + " showing=" + str(page.is_showing()) + " locked=" + str(page._buttons_locked))
