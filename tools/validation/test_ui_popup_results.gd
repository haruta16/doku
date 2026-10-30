## 真实评分、反馈与确认弹窗：重复动作及关闭动画不能跨展示发结果。
## 1.22已退休旧rate_us、设置分页帮助、streak_switch1和IQ反馈；已删除的 UI 合同由当前教学/奖励测试覆盖，不为旧测试恢复退役入口。
extends SceneTree

var checks: int = 0
var failures: int = 0
var ui: Node

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
	root.get_node("GameState").set_sound_on(false)
	await _test_rating()
	await _test_feedback()
	await _test_confirm()
	await _test_setting_close()
	await _test_confirm_back()
	await _test_result_waits()
	await _test_win_reopen()
	await _test_home_popup_cancellation()
	ui.hide_all()
	host.queue_free()
	await process_frame
	await create_timer(0.8).timeout
	print("UI POPUP RESULTS TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_rating() -> void:
	for name: String in ["rate_us_v2"]:
		var page: Variant = ui.show_ui(name)
		await create_timer(0.5).timeout
		var results: Array = []
		var observer := func(data: Dictionary) -> void: results.append(data)
		page.closed.connect(observer)
		page._select_stars(3)
		page._on_rate_us_btn_pressed()
		page._on_rate_us_btn_pressed()
		page._on_close_btn_pressed()
		_check(results.is_empty(), name + " repeated buttons cannot finish before the first animation")
		await create_timer(0.6).timeout
		_check(results.size() == 1 and results[0] == {"star_count": 3, "is_submitted": true}, name + " submits exactly one captured result")
		_check(page.is_hidden(), name + " closes through its manager after completion")
		ui.show_ui(name)
		page._on_close_btn_pressed()
		ui.hide_ui(name)
		ui.show_ui(name)
		await create_timer(0.6).timeout
		_check(results.size() == 1 and page.is_showing() and page.visible, name + " old close cannot finish into a reopened presentation")
		page.closed.disconnect(observer)
		ui.hide_ui(name)

func _test_feedback() -> void:
	var page: Variant = ui.show_ui("feedback")
	var results: Array = []
	var observer := func() -> void: results.append(page.is_submitted)
	page.closed.connect(observer)
	page._text_edit.text = "test"
	page._on_submit_pressed()
	page._on_submit_pressed()
	page._on_close_pressed()
	_check(results.is_empty(), "feedback repeated buttons wait for the first close")
	await create_timer(0.6).timeout
	_check(results == [true] and page.is_hidden(), "feedback submits and closes exactly once")
	ui.show_ui("feedback")
	page._on_close_pressed()
	ui.hide_ui("feedback")
	ui.show_ui("feedback")
	await create_timer(0.6).timeout
	_check(results == [true] and page.is_showing(), "feedback cancelled animation emits no new presentation result")
	page.closed.disconnect(observer)
	ui.hide_ui("feedback")

func _test_confirm() -> void:
	var result := {"confirmed": 0, "closed": 0}
	var params: Dictionary = {"on_confirm": func() -> void: result.confirmed += 1, "on_close": func() -> void: result.closed += 1}
	var page: Variant = ui.show_ui("confirm", params)
	var presentation: int = page.get_presentation_revision()
	page._on_action_btn_pressed()
	page._on_action_btn_pressed()
	page._on_close_btn_pressed()
	_check(result.confirmed == 1 and result.closed == 0, "confirm preserves immediate callback timing but accepts only the first button")
	await create_timer(0.6).timeout
	_check(page.is_hidden(), "confirm closes through manager lifecycle")
	_check(page.get_presentation_revision() == presentation and presentation == page._window_presentation_revision, "confirm normal close preserves the framework presentation identity")
	_check(not ui._ordered_windows().has(page), "confirm completed close removes its manager stack entry")
	var destroyed := {"done": false}
	_capture_destroy(ui, "confirm", destroyed)
	var deadline: int = Time.get_ticks_msec() + 1000
	while not destroyed.done and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(destroyed.done and ui.get_ui("confirm") == null, "confirm normal hide can be destroyed without waiting on a stale stack entry")
	if not destroyed.done and is_instance_valid(page):
		page.free()
	page = ui.show_ui("confirm", params)
	page.close()
	ui.show_ui("confirm", params)
	await create_timer(0.6).timeout
	_check(page.is_showing() and page.visible, "confirm old animation cannot hide a refreshed request")
	ui.hide_ui("confirm")


func _test_setting_close() -> void:
	var calls := {"old": 0, "new": 0}
	var old_callback := func() -> void: calls.old += 1
	var new_callback := func() -> void: calls.new += 1
	var page: Variant = ui.show_ui("setting", {"on_close": old_callback})
	await create_timer(0.5).timeout
	ui.hide_ui("setting")
	ui.show_ui("setting", {"on_close": new_callback})
	await create_timer(0.6).timeout
	_check(page.is_showing() and page.visible, "setting old close animation cannot hide the reopened presentation")
	_check(calls == {"old": 0, "new": 0}, "cancelled setting close calls neither the original nor replacement callback")
	await ui.hide_ui("setting")
	_check(calls == {"old": 0, "new": 1}, "setting completed close invokes only its captured callback")
	for _iteration: int in 2:
		ui.show_ui("setting", {"on_close": old_callback})
		var reopen := func() -> void:
			if not page.visible:
				ui.show_ui("setting", {"on_close": new_callback})
		page.visibility_changed.connect(reopen)
		await ui.hide_ui("setting")
		await create_timer(0.5).timeout
		_check(page.is_showing() and page.visible and calls == {"old": 0, "new": 1}, "setting visible callback cancels stale completion")
		page.visibility_changed.disconnect(reopen)
		await ui.hide_ui("setting")
		calls.new = 1


func _test_confirm_back() -> void:
	for source: String in ["escape", "android_back"]:
		var underlying: Variant = ui.show_ui("feedback")
		var result := {"confirmed": 0, "closed": 0, "underlying_closed": 0}
		var observer := func() -> void: result.underlying_closed += 1
		underlying.closed.connect(observer)
		var page: Variant = ui.show_ui("confirm", {
			"on_confirm": func() -> void: result.confirmed += 1,
			"on_close": func() -> void: result.closed += 1,
		})
		_dispatch_back(source)
		_dispatch_back(source)
		_check(result.closed == 1 and result.confirmed == 0, source + " cancels the confirmation exactly once while closing")
		await create_timer(0.6).timeout
		_check(page.is_hidden(), source + " closes the confirmation through its manager")
		_check(underlying.is_showing() and result.underlying_closed == 0, source + " never reaches the underlying page")
		underlying.closed.disconnect(observer)
		ui.hide_all()

	var reopened := {"closed": 0}
	var page: Variant = ui.show_ui("confirm", {"content": "first", "on_close": func() -> void:
		reopened.closed += 1
		ui.show_ui("confirm", {"content": "replacement"})
	})
	var revision: int = page.get_presentation_revision()
	_dispatch_back("escape")
	await create_timer(0.6).timeout
	_check(reopened.closed == 1 and page.is_showing() and page.get_presentation_revision() != revision,
		"escape cancellation may replace the popup without the old close hiding it")
	_dispatch_back("android_back")
	await create_timer(0.6).timeout
	_check(page.is_hidden() and reopened.closed == 1, "replacement popup does not reuse the previous cancellation callback")
	ui.hide_all()


func _dispatch_back(source: String) -> void:
	if source == "android_back":
		ui.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		return
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TEST_FAILED: " + message)


func _capture_rating(page: Variant, result: Dictionary, owner: Callable = Callable()) -> void:
	result["data"] = await page.get_script().wait_for_result(page, owner)
	result["done"] = true


func _capture_feedback(page: Variant, result: Dictionary, owner: Callable = Callable()) -> void:
	result["accepted"] = await page.get_script().wait_for_result(page, owner)
	result["done"] = true


func _test_result_waits() -> void:
	var rating: Variant = ui.show_ui("rate_us_v2")
	var result: Dictionary = {"done": false}
	_capture_rating(rating, result)
	rating._select_stars(4)
	rating._on_rate_us_btn_pressed()
	await create_timer(0.6).timeout
	_check(result.get("done", false) and result.get("data", {}) == {"star_count": 4, "is_submitted": true}, "rating waiter receives the completed presentation result")
	_check(rating.closed.get_connections().is_empty(), "rating waiter disconnects after success")
	ui.show_ui("rate_us_v2")
	result = {"done": false}
	_capture_rating(rating, result)
	ui.show_ui("rate_us_v2")
	await process_frame
	await process_frame
	_check(result.get("done", false) and result.get("data", null) == {}, "rating refresh cancels the prior waiter")
	_check(rating.closed.get_connections().is_empty(), "rating refresh removes prior listener")
	result = {"done": false}
	_capture_rating(rating, result)
	rating.free()
	await process_frame
	await process_frame
	_check(result.get("done", false) and result.get("data", null) == {}, "destroying rating page releases its caller")

	var feedback: Variant = ui.show_ui("feedback")
	result = {"done": false}
	_capture_feedback(feedback, result)
	ui.hide_ui("feedback")
	await process_frame
	await process_frame
	_check(result.get("done", false) and not result.get("accepted", true), "external feedback hide cancels its caller")
	_check(feedback.closed.get_connections().is_empty(), "feedback cancellation removes prior listener")
	ui.show_ui("feedback")
	result = {"done": false}
	_capture_feedback(feedback, result)
	feedback._on_close_pressed()
	await create_timer(0.6).timeout
	_check(result.get("done", false) and result.get("accepted", false), "feedback explicit close completes its caller")
	feedback = ui.show_ui("feedback")
	result = {"done": false}
	_capture_feedback(feedback, result)
	feedback.free()
	await process_frame
	await process_frame
	_check(result.get("done", false) and not result.get("accepted", true), "destroying feedback releases its caller")

	rating = ui.show_ui("rate_us_v2")
	var owner: Dictionary = {"active": true}
	result = {"done": false}
	_capture_rating(rating, result, func() -> bool: return owner.active)
	owner.active = false
	await process_frame
	await process_frame
	_check(result.get("done", false) and result.get("data", null) == {} and rating.is_hidden(), "owner cancellation closes only its current rating presentation")
	_check(rating.closed.get_connections().is_empty(), "owner cancellation clears result listener")

	var count := {"value": 0}
	var confirm: Variant = ui.show_ui("confirm", {"content": "first", "on_confirm": func() -> void:
		count.value += 1
		ui.show_ui("confirm", {"content": "retry"})
	})
	var revision: int = confirm.get_presentation_revision()
	confirm._on_action_btn_pressed()
	await create_timer(0.6).timeout
	_check(count.value == 1 and confirm.is_showing() and confirm.visible and confirm.get_presentation_revision() != revision, "confirm callback may synchronously replace its failed request without old close hiding retry")
	ui.hide_ui("confirm")




func _test_win_reopen() -> void:
	# 延迟消失动画中重开通关页；旧 on_hide 不能复位或隐藏后来的一次展示。
	var board_script: Script = load("res://products/meowdoku/gameplay/presentation/board/board_view.gd")
	var board: Node = board_script.new()
	current_scene.add_child(board)
	var params: Dictionary = {"board_view": board, "level_config": {"level": 1, "skip_appear_delay": true}}
	var page: Variant = ui.show_ui("win", params)
	ui.hide_ui("win")
	ui.show_ui("win", params)
	await create_timer(3.0).timeout
	_check(page.is_showing() and page.visible, "old win hide completion cannot hide a reopened window")
	ui.hide_ui("win")
	await create_timer(0.8).timeout
	board.queue_free()


## 排名任务由真实首页队列启动；取消必须在 hide/free/reset 返回前展开父 await，不能靠多等一帧。
func _test_home_popup_cancellation() -> void:
	var game: Node = root.get_node("GameState")
	var rank: Node = root.get_node("RankActivityManager")
	for phase: String in ["delay", "popup"]:
		for transition: String in ["hide", "free", "reset"]:
			ui.hide_all()
			await create_timer(0.2).timeout
			await ui.destroy_ui("home")
			await ui.destroy_ui("rank_activity_open_popup")
			_check(game.reset_all(), "home cancellation prepares isolated rank state")
			game.set_sound_on(false)
			game.set_tutorial_done(true)
			game.set_current_level(50)
			var home: Variant = ui.show_ui("home")
			var queue: Variant = home._popup_queue
			var label: String = "home rank " + phase + " " + transition
			_check(home._rank_popup_pending and queue.is_running(), label + " starts the real queued rank parent flow")
			if phase == "popup":
				var deadline: int = Time.get_ticks_msec() + 3000
				while Time.get_ticks_msec() < deadline:
					var popup: Variant = ui.get_ui("rank_activity_open_popup")
					if is_instance_valid(popup) and popup.is_showing():
						break
					await process_frame
				var popup: Variant = ui.get_ui("rank_activity_open_popup")
				_check(is_instance_valid(popup) and popup.is_showing() and queue.is_running(), label + " suspends the parent on its live popup")
			var observed: Dictionary = {"drained": false, "stale": 0}
			var drained: Callable = func() -> void: observed.drained = true
			queue.drained.connect(drained)
			var old_task := UIPopupEntry.new()
			old_task.key = "cancelled_home_regression"
			old_task.callable = func() -> void: observed.stale += 1
			queue.enqueue(old_task)
			match transition:
				"hide": ui.hide_ui("home")
				"free": home.free()
				"reset": _check(game.reset_all(), label + " resets successfully")
			# These assertions intentionally precede every await after cancellation.
			_check(observed.drained and not queue.is_running(), label + " synchronously exits the queued parent await")
			_check(queue.is_empty() and observed.stale == 0, label + " discards pending old-home tasks before waking the parent")
			_check(not rank._data.joined, label + " never confirms participation after its owner ends")
			queue.drained.disconnect(drained)
			ui.hide_all()
			if is_instance_valid(home):
				home.free()
			game.set_current_level(1)
			var replacement: Variant = ui.show_ui("home")
			await create_timer(0.15).timeout
			_check(replacement.is_showing() and not queue.is_running() and observed.stale == 0, label + " cannot advance old tasks into a replacement home")
			ui.hide_all()
			replacement.free()


func _capture_destroy(manager: Node, name: String, result: Dictionary) -> void:
	await manager.destroy_ui(name)
	result.done = true
