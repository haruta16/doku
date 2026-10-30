## 真实启动说明页：旧动画等待与同步完成监听都不能隐藏新一代页面或重复推进启动。
extends SceneTree
var checks: int = 0
var failures: int = 0
var ui: Node
var att_helper: Script


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
	att_helper = load("res://products/meowdoku/app/platform/att_guide_helper.gd")
	root.get_node("GameState").set_sound_on(false)
	for name: String in ["privacy", "pre_att_guide", "pre_att_guide_v2"]:
		await _test_reopen_during_animation(name)
		await _test_reopen_from_completion(name)
	for group: int in [0, 1, 2]:
		await _test_mock_att_flow(group)
	ui.hide_all()
	await create_timer(0.3).timeout
	print("UI STARTUP DIALOG LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_reopen_during_animation(name: String) -> void:
	ui.hide_all()
	var page: Variant = ui.show_ui(name)
	var state := {"completed": 0}
	var signal_name: StringName = &"accepted" if name == "privacy" else &"continued"
	var callback := func() -> void: state.completed += 1
	page.connect(signal_name, callback)
	page.call("_on_accept_btn_pressed" if name == "privacy" else "_on_continue_btn_pressed")
	ui.show_ui(name)
	await create_timer(0.7).timeout
	_check(state.completed == 0, name + " old animation cannot complete a newer presentation")
	_check(page.is_showing() and page.visible and not page._closing, name + " new presentation remains visible and actionable")
	page.call("_on_accept_btn_pressed" if name == "privacy" else "_on_continue_btn_pressed")
	await create_timer(0.7).timeout
	_check(state.completed == 1, name + " new presentation still completes once from its own button")
	page.disconnect(signal_name, callback)


func _test_reopen_from_completion(name: String) -> void:
	ui.hide_all()
	var page: Variant = ui.show_ui(name)
	var signal_name: StringName = &"accepted" if name == "privacy" else &"continued"
	var state := {"reopened": false}
	page.connect(signal_name, func() -> void:
		state.reopened = true
		ui.show_ui(name)
	, CONNECT_ONE_SHOT)
	page.call("_on_accept_btn_pressed" if name == "privacy" else "_on_continue_btn_pressed")
	await create_timer(0.7).timeout
	_check(state.reopened, name + " completion listener reopens cached page")
	_check(page.is_showing() and page.visible and not page._closing, name + " old post-signal cleanup cannot hide new presentation")


func _test_mock_att_flow(group: int) -> void:
	ui.hide_all()
	var kit: Node = root.get_node("UniKitManager")
	root.get_node("ABTestManager").att_dlg_logic.set_debug_override(group)
	kit.debug_force_editor_test = true
	var state := {"done": false}
	_run_mock_att(state)
	await process_frame
	if group != 1:
		var page: Variant = ui.get_ui("pre_att_guide_v2" if group == 2 else "pre_att_guide")
		_check(page != null and page.is_showing(), "ATT group %d opens its actual custom guide" % group)
		if page != null:
			page._on_continue_btn_pressed()
	_check(not state.done, "ATT flow waits for its actual asynchronous mock dismissal")
	var deadline: int = Time.get_ticks_msec() + 4000
	while not state.done and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(state.done and not kit.debug_force_editor_test, "ATT group %d completes and releases editor test flag" % group)


func _run_mock_att(state: Dictionary) -> void:
	await att_helper.try_show_and_wait_dialog_close()
	state.done = true


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
