## 实际语言页、弹窗队列及字号组的消费者合同；只在隔离副本运行。
extends SceneTree

var checks: int = 0
var failures: int = 0
var ui: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	var host := Control.new()
	root.add_child(host)
	current_scene = host
	ui = root.get_node("UIManager")
	await _test_language()
	await _test_popup_queue()
	await _test_font_group(host)
	await _test_real_hide_wait_cancellation()
	ui.hide_all()
	await create_timer(0.7).timeout
	print("UI COMPONENT TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_language() -> void:
	var page: Variant = ui.show_ui("language")
	var option_count: int = page._option_nodes[0].pressed.get_connections().size()
	var yes_count: int = page._yes_btn.pressed.get_connections().size()
	for i in 3:
		_check(ui.show_ui("language") == page, "language refresh reuses the existing page")
		_check(page._option_nodes[0].pressed.get_connections().size() == option_count, "refresh does not accumulate option callbacks")
		_check(page._yes_btn.pressed.get_connections().size() == yes_count, "refresh does not reconnect the fixed confirmation button")
	page._option_nodes[1].button_down.emit()
	page._option_nodes[1].pressed.emit()
	_check(page._selected_index == 1, "refreshed option still selects its current list entry")
	await ui.hide_ui("language")
	page._selected_index = -1
	page._option_nodes[1].pressed.emit()
	_check(page._selected_index == -1, "hidden page ignores its persistent button connection")
	ui.show_ui("language")
	_check(page._option_nodes[0].pressed.get_connections().size() == option_count and page._yes_btn.pressed.get_connections().size() == yes_count, "cached reopen retains exactly the original connections")
	page._option_nodes[1].button_down.emit()
	page._option_nodes[1].pressed.emit()
	_check(page._selected_index == 1, "cached reopen remains interactive")
	await ui.hide_ui("language")


func _make_queue_scene(name: String, stage: String, action: String, wait_stage: String = "") -> void:
	var fixture = load("res://tools/validation/fixtures/ui_creating_frame.gd")
	var node = fixture.new()
	node.trigger_stage = stage
	node.action = action
	node.wait_on_hide = wait_stage == "hide"
	node.wait_on_close = wait_stage == "close"
	var packed := PackedScene.new()
	_check(packed.pack(node) == OK, "pack popup queue fixture")
	node.free()
	var path: String = "res://%s.tscn" % name
	_check(ResourceSaver.save(packed, path) == OK, "save popup queue fixture")
	ui._registry[name] = path


func _entry(name: String, once: bool = false) -> Resource:
	var script = load("res://products/meowdoku/app/ui/queue/ui_popup_entry.gd")
	var entry = script.new()
	entry.ui_name = name
	entry.once_per_session = once
	return entry


func _test_popup_queue() -> void:
	var script = load("res://products/meowdoku/app/ui/queue/ui_popup_queue.gd")
	_make_queue_scene("queue_next", "", "")
	for mode: String in ["cancel", "shown_hide", "creation_cancel"]:
		var name: String = "queue_" + mode
		_make_queue_scene(name, "show" if mode == "cancel" else ("ready" if mode == "creation_cancel" else ""), "close" if mode == "cancel" else "queue_free")
		var queue = script.new()
		var close_shown := func(shown_name: String, _window: UIFrameWindow) -> void:
			if mode == "shown_hide" and shown_name == name:
				ui.hide_ui(name)
		ui.events.window_shown.connect(close_shown)
		var listeners_before: int = ui.events.window_hidden.get_connections().size()
		var cancelled_before: int = ui.events.window_show_cancelled.get_connections().size()
		queue.enqueue(_entry(name, true))
		queue.enqueue(_entry("queue_next"))
		queue.flush()
		_check(queue._is_showing and queue._current_ui_name == "queue_next" and ui.get_ui("queue_next").is_showing(), mode + " advances past a cancelled/closed first entry")
		_check((name in queue._shown_this_session) == (mode == "shown_hide"), mode + " once-per-session counts only an actual display")
		await ui.hide_ui("queue_next")
		_check(not queue._is_showing and queue._current.is_empty(), mode + " completes the next entry without a stale lock")
		_check(ui.events.window_hidden.get_connections().size() == listeners_before, mode + " releases its event listeners")
		_check(ui.events.window_show_cancelled.get_connections().size() == cancelled_before, mode + " releases its cancellation listener")
		ui.events.window_shown.disconnect(close_shown)
		await process_frame
	# 首次显示取消时可能仍在异步退场；必须完整交接后推进，且不能消费 once 资格。
	for wait_stage: String in ["hide", "close", "exit"]:
		var name: String = "queue_delayed_" + wait_stage
		_make_queue_scene(name, "show", "close", "hide" if wait_stage == "exit" else wait_stage)
		var delayed_queue = script.new()
		var cancelled: Array[String] = []
		var on_cancelled := func(cancelled_name: String, _window: UIFrameWindow) -> void:
			cancelled.append(cancelled_name)
		ui.events.window_show_cancelled.connect(on_cancelled)
		delayed_queue.enqueue(_entry(name, true))
		delayed_queue.enqueue(_entry("queue_next"))
		delayed_queue.flush()
		var closing: Variant = ui.get_ui(name)
		_check(closing.get_window_state() == UIBaseWindow.WindowState.CLOSING and delayed_queue._current_ui_name == name, wait_stage + " cancellation waits for the closing lifecycle")
		await process_frame
		_check(not ui.get_ui("queue_next").is_showing() and cancelled.is_empty(), wait_stage + " cancellation does not overlap the next popup")
		if wait_stage == "hide": closing.hide_release.emit()
		elif wait_stage == "close": closing.close_release.emit()
		else:
			closing.queue_free()
			await process_frame
		_check(cancelled == [name] and (not is_instance_valid(closing) or closing.is_hidden()), wait_stage + " cancellation publishes completion after hiding or destruction")
		_check(delayed_queue._current_ui_name == "queue_next" and ui.get_ui("queue_next").is_showing(), wait_stage + " cancellation hands ownership to the next popup")
		_check(name not in delayed_queue._shown_this_session, wait_stage + " cancellation retains once-per-session eligibility")
		await ui.hide_ui("queue_next")
		_check(not delayed_queue._is_showing and delayed_queue._current.is_empty(), wait_stage + " successor closes without a stale request")
		ui.events.window_show_cancelled.disconnect(on_cancelled)
	# 更早的 hidden 订阅者可以合法直接释放窗口；队列收到的是失效引用。
	_make_queue_scene("queue_disposed", "", "")
	var disposed_queue = script.new()
	var dispose_hidden := func(name: String, window: UIFrameWindow) -> void:
		if name == "queue_disposed": window.free()
	ui.events.window_hidden.connect(dispose_hidden)
	disposed_queue.enqueue(_entry("queue_disposed", true))
	disposed_queue.enqueue(_entry("queue_next"))
	disposed_queue.flush()
	await ui.hide_ui("queue_disposed")
	await process_frame
	_check(disposed_queue._current_ui_name == "queue_next" and ui.get_ui("queue_next").is_showing(), "earlier hidden listener can free the window before queue handoff")
	_check("queue_disposed" in disposed_queue._shown_this_session, "a genuinely shown then disposed entry consumes once eligibility")
	await ui.hide_ui("queue_next")
	ui.events.window_hidden.disconnect(dispose_hidden)
	# 大量同步取消走循环而非递归；一次性资格仍可在之后真正显示时使用。
	var queue = script.new()
	for i in 300:
		queue.enqueue(_entry("queue_cancel", true))
	queue.enqueue(_entry("queue_next", true))
	queue.flush()
	_check(queue._queue.is_empty() and queue._current_ui_name == "queue_next", "synchronous cancellation chain drains without recursive stack growth")
	await ui.hide_ui("queue_next")
	queue.enqueue(_entry("queue_next", true))
	queue.flush()
	_check(not queue._is_showing, "an actually displayed once-per-session entry is not shown again")
	# 即使目标已经显示，也必须等它关闭，不能依赖一次新的 shown 事件。
	ui.show_ui("queue_next")
	queue = script.new()
	queue.enqueue(_entry("queue_next", true))
	queue.flush()
	_check(queue._is_showing and "queue_next" in queue._shown_this_session, "queue can take ownership of a refreshed visible page")
	await ui.hide_ui("queue_next")
	_check(not queue._is_showing, "refreshed existing page releases queue on close")


## 真页面的关闭等待必须在重开/销毁时同步取消，不能只保护测试夹具。
func _test_real_hide_wait_cancellation() -> void:
	for name: String in ["account_result", "no_connection", "sign_out_confirm", "login", "delete_account_confirm", "subscription_success", "streak_backfill", "setting", "language", "home_companion_reward"]:
		var close_calls: Array[int] = [0]
		var params: Dictionary = {"channel": "google", "channels": [], "reward_tier": 2, "from_streak": 3, "to_streak": 4, "info_days": 3}
		if name == "setting":
			params["on_close"] = func() -> void: close_calls[0] += 1
		var page: Variant = ui.show_ui(name, params)
		_check(page != null and page.is_showing(), name + " real page shows for cancellation contract")
		if page == null:
			continue
		await process_frame
		ui.hide_ui(name)
		_check(page.get_window_state() == UIBaseWindow.WindowState.CLOSING, name + " enters asynchronous close")
		_check(ui.show_ui(name, params) == page and page.is_showing(), name + " cancels close and reuses the page")
		await process_frame
		_check(page.is_showing() and page.visible, name + " old hide continuation cannot hide reopened page")
		if name == "setting":
			_check(close_calls[0] == 0, "cancelled setting hide cannot invoke old callback")
		ui.hide_ui(name)
		_check(page.get_window_state() == UIBaseWindow.WindowState.CLOSING, name + " can close again after cancellation")
		page.queue_free()
		await process_frame
		await process_frame
		_check(not is_instance_valid(page), name + " direct free during close releases the page")
		if name == "setting":
			_check(close_calls[0] == 0, "destroyed setting hide cannot invoke callback")
		page = ui.show_ui(name, params)
		_check(page != null and page.is_showing(), name + " recreates after cancelled destruction")
		await ui.hide_ui(name)
		_check(page.is_hidden(), name + " ordinary close still completes")
		if name == "setting":
			_check(close_calls[0] == 1, "successful setting close invokes its current callback exactly once")
		page.queue_free()
		await process_frame


func _test_font_group(host: Node) -> void:
	var script = load("res://scripts/framework/ui/extensions/auto_fit_label_group.gd")
	var group = script.new()
	group.base_font_size = 60
	group.min_font_size = 10
	group.height_budget = 160.0
	group.size = Vector2(400, 160)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "The quick brown fox jumps over the lazy dog beside the river."
	group.add_child(label)
	host.add_child(group)
	await _layout_frames()
	var initial: int = label.get_theme_font_size("font_size")
	group.refit()
	await _layout_frames()
	_check(initial > 10 and initial == label.get_theme_font_size("font_size"), "initial fit waits for a usable layout and needs no manual correction")
	group.size.x = 120
	await _layout_frames()
	var narrow: int = label.get_theme_font_size("font_size")
	var labels: Array[Node] = [label]
	_check(narrow < initial and group._group_fits(labels, narrow, 160.0), "narrow layout automatically shrinks text into its height budget")
	group.refit()
	await _layout_frames()
	_check(narrow == label.get_theme_font_size("font_size"), "narrow layout already chose the same font as explicit refit")
	group.size.x = 400
	await _layout_frames()
	_check(label.get_theme_font_size("font_size") == initial, "wider layout restores the available font size")
	label.text += " " + label.text
	await _layout_frames()
	_check(label.get_theme_font_size("font_size") < initial, "changed text is refitted through label minimum-size notification")
	_check(not group._fit_queued, "stable layout does not keep queuing font recalculations")
	group.queue_free()
	await process_frame


func _layout_frames() -> void:
	for i in 6:
		await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("TEST_FAILED: " + message)
