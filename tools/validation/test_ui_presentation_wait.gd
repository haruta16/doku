extends SceneTree

class Emitter extends Node:
	signal empty
	signal value(number: int, label: String)

class WaitingPage extends UIFrameWindow:
	signal release
	signal owned_release
	var destroy_calls: Array[int] = [0]
	var _created_resource: RefCounted
	func on_create() -> void:
		_created_resource = RefCounted.new()
	var normal_completions: int = 0
	var show_calls: int = 0
	func on_show(_params: Dictionary = {}) -> void:
		show_calls += 1
	func on_hide() -> void:
		if not await wait_presentation_signal(release, get_presentation_revision()):
			return
		normal_completions += 1
	func on_destroy() -> void:
		destroy_calls[0] += 1
		# Product destruction hooks can legitimately depend on on_create setup.
		_created_resource.set_meta("released", true)
		_created_resource = null
		owned_release.emit()
	func wait_owned_release() -> void:
		await owned_release

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("TEST_FAILED: ", message)

func _record_signal(page: UIBaseWindow, source: Signal, output: Dictionary) -> void:
	output.success = await page.wait_presentation_signal(source, page.get_presentation_revision())
	output.done = true

func _record_until(page: UIBaseWindow, predicate: Callable, output: Dictionary) -> void:
	output.success = await page.wait_presentation_until(predicate, page.get_presentation_revision())
	output.done = true

func _record_hide(page: UIBaseWindow, output: Dictionary) -> void:
	await page._do_hide()
	output.done = true

func _record_owned_wait(page: WaitingPage, output: Dictionary) -> void:
	await page.wait_owned_release()
	output.done = true

func _reenter(page: UIBaseWindow, source: Signal, output: Dictionary, next: Dictionary) -> void:
	output.success = await page.wait_presentation_signal(source, page.get_presentation_revision())
	output.done = true
	_record_signal(page, source, next)

func _queue_after_cancel(page: UIBaseWindow, source: Signal, output: Dictionary) -> void:
	output.success = await page.wait_presentation_signal(source, page.get_presentation_revision())
	output.done = true
	page.queue_free()

func _refresh_after_cancel(page: UIBaseWindow, source: Signal, output: Dictionary) -> void:
	output.success = await page.wait_presentation_signal(source, page.get_presentation_revision())
	output.done = true
	page._do_refresh()

func _destroy_after_cancel(page: UIBaseWindow, source: Signal, output: Dictionary) -> void:
	output.success = await page.wait_presentation_signal(source, page.get_presentation_revision())
	output.done = true
	page._do_destroy()

func _new_page(host: Node) -> WaitingPage:
	var page := WaitingPage.new()
	host.add_child(page)
	page._do_create()
	page._do_show()
	return page

func _run() -> void:
	var isolated: bool = ProjectSettings.get_setting("test/ui_framework_isolated", false)
	if not isolated and not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: isolated UI or product validation fixture required")
		quit(2)
		return
	var host := Control.new()
	root.add_child(host)
	current_scene = host
	var source := Emitter.new()
	host.add_child(source)
	var page := _new_page(host)
	var result: Dictionary = {}
	_record_signal(page, source.value, result)
	_check(not result.has("done"), "two-argument signal suspends")
	_check(source.value.get_connections().size() == 1, "one registered source callback")
	source.value.emit(5, "ok")
	_check(result == {"done": true, "success": true}, "two-argument signal resolves true")
	_check(page._presentation_waits.is_empty() and source.value.get_connections().is_empty(), "normal resolution removes both registrations")

	result = {}
	_record_signal(page, source.empty, result)
	page._do_refresh()
	_check(result == {"done": true, "success": false}, "refresh synchronously cancels old zero-argument signal")
	_check(source.empty.get_connections().is_empty(), "refresh disconnects source")
	source.empty.emit()
	_check(not result.success and page.is_showing(), "late source emission cannot complete old wait or hide refreshed page")

	result = {}
	_record_signal(page, source.empty, result)
	page._do_show()
	_check(result == {"done": true, "success": false}, "show synchronously cancels old signal")
	var next: Dictionary = {}
	result = {}
	_reenter(page, source.empty, result, next)
	page._do_refresh()
	_check(result == {"done": true, "success": false}, "reentrant cancelled caller receives false")
	_check(not next.has("done") and page._presentation_waits.size() == 1, "new presentation waiter survives old cancellation drain")
	source.empty.emit()
	_check(next == {"done": true, "success": true}, "new presentation completes independently")

	result = {}
	_record_until(page, func() -> bool: return true, result)
	_check(result == {"done": true, "success": true}, "true predicate completes immediately")
	result = {}
	_record_until(page, func() -> bool: return false, result)
	_check(not result.has("done"), "false predicate suspends")
	page._do_refresh()
	_check(result == {"done": true, "success": false}, "refresh cancels frame polling synchronously")
	result = {}
	_record_until(page, func() -> bool:
		page._do_refresh()
		return true, result)
	_check(result == {"done": true, "success": false}, "predicate reentry cannot claim old presentation completed")
	result = {}
	var ready: Array[bool] = [false]
	_record_until(page, func() -> bool: return ready[0], result)
	ready[0] = true
	await process_frame
	_check(result == {"done": true, "success": true}, "predicate completes on next frame")

	result = {}
	_record_hide(page, result)
	page._do_destroy()
	_check(result.get("done", false), "destroy synchronously unwinds on_hide and parent _do_hide")
	_check(page.normal_completions == 0, "cancelled hide cannot publish business completion")
	_check(page.get_window_state() == UIBaseWindow.WindowState.DESTROYED, "old parent hide cannot overwrite terminal state")
	_check(page.release.get_connections().is_empty(), "destroy disconnects dead signal")
	page.free()

	page = _new_page(host)
	result = {}
	_record_hide(page, result)
	page.free()
	_check(result.get("done", false), "unmanaged direct free synchronously unwinds parent hide")

	page = _new_page(host)
	result = {}
	_record_hide(page, result)
	page.queue_free()
	await process_frame
	_check(result.get("done", false), "unmanaged queued free unwinds parent hide")

	page = _new_page(host)
	result = {}
	_record_hide(page, result)
	page._do_show()
	_check(result.get("done", false) and page.is_showing(), "reopen synchronously ends old parent hide")
	_check(page.normal_completions == 0, "reopen is not a close completion")
	result = {}
	_record_hide(page, result)
	page.release.emit()
	_check(result.get("done", false) and page.is_hidden(), "normal hide reaches hidden")
	_check(page.normal_completions == 1, "normal close completion runs once")
	page.free()

	page = _new_page(host)
	_check(not await page.wait_presentation_signal(Signal(source, &"nonexistent")), "unknown source signal fails closed")
	_check(not await page.wait_presentation_signal(Signal()), "empty source signal fails closed")
	_check(page._presentation_waits.is_empty(), "invalid signals leave no pending registration")
	page.free()
	for action: String in ["_do_refresh", "_do_show", "_do_destroy"]:
		page = _new_page(host)
		result = {}
		_queue_after_cancel(page, source.empty, result)
		match action:
			"_do_refresh": page._do_refresh()
			"_do_show": page._do_show()
			"_do_destroy": page._do_destroy()
		_check(result == {"done": true, "success": false} and page.is_queued_for_deletion(), "synchronous queued deletion during " + action + " cancels safely")
		_check(source.empty.get_connections().is_empty(), "queued deletion reentry disconnects source during " + action)
	page = _new_page(host)
	result = {}
	var page_ref: WeakRef = weakref(page)
	_record_until(page, func() -> bool:
		page_ref.get_ref().queue_free()
		return true, result)
	_check(result == {"done": true, "success": false}, "predicate can queue its owner for deletion without stale completion")

	page = _new_page(host)
	result = {}
	_refresh_after_cancel(page, source.empty, result)
	page._do_refresh()
	_check(result == {"done": true, "success": false}, "cancelled continuation may synchronously refresh again")
	_check(page.show_calls == 2, "outer refresh does not call on_show after nested refresh takes ownership")
	page.free()
	page = _new_page(host)
	result = {}
	_destroy_after_cancel(page, source.empty, result)
	page._do_show()
	_check(result == {"done": true, "success": false}, "cancelled continuation may synchronously destroy")
	_check(page.show_calls == 1 and page.get_window_state() == UIBaseWindow.WindowState.DESTROYED, "outer show does not revive synchronously destroyed owner")
	page.free()

	_test_uncreated_templates()
	await _test_destroy_hook_once(host)
	await _test_manager_close(host)
	host.free()
	await process_frame
	print("UI_PRESENTATION_WAIT_TESTS: ", checks, " assertions, ", failures, " failures")
	quit(0 if failures == 0 else 1)

func _record_manager_hide(manager: UIWindowManager, output: Dictionary) -> void:
	await manager.hide_ui("animated")
	output.done = true

func _test_manager_close(host: Node) -> void:
	var template := UIFrameWindow.new()
	template.close_anim_name = &"close"
	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	template.add_child(anim)
	anim.owner = template
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 20.0
	library.add_animation(&"close", animation)
	anim.add_animation_library(&"", library)
	var packed := PackedScene.new()
	_check(packed.pack(template) == OK, "animated fixture packs")
	template.free()
	var path: String = "res://ui_presentation_wait_fixture.tscn"
	_check(ResourceSaver.save(packed, path) == OK, "animated fixture saved only in isolated project")
	var manager := UIWindowManager.new()
	manager.configure({"animated": path})
	host.add_child(manager)
	var page := manager.show_ui("animated")
	var hidden: Array[String] = []
	manager.events.window_hidden.connect(func(name: String, _win: Variant) -> void: hidden.append(name))
	var result: Dictionary = {}
	_record_manager_hide(manager, result)
	_check(page.get_window_state() == UIBaseWindow.WindowState.CLOSING and not result.has("done"), "manager waits for close animation")
	manager.show_ui("animated")
	_check(result.get("done", false) and page.is_showing(), "show aborts animation and synchronously unwinds manager hide")
	_check(hidden.is_empty(), "aborted manager close does not publish hidden")
	result = {}
	_record_manager_hide(manager, result)
	page.free()
	_check(result.get("done", false), "direct managed free synchronously unwinds animation and manager")
	_check(hidden.size() == 1, "actual removal publishes hidden exactly once")
	manager.free()


func _test_destroy_hook_once(host: Node) -> void:
	for mode: String in ["explicit", "direct", "queued", "managed"]:
		var page := _new_page(host)
		var calls: Array[int] = page.destroy_calls
		var hide_result: Dictionary = {}
		var owned_result: Dictionary = {}
		_record_hide(page, hide_result)
		_record_owned_wait(page, owned_result)
		var manager: UIWindowManager
		if mode == "managed":
			manager = UIWindowManager.new()
			host.add_child(manager)
			# Mirror the manager's real registration so PREDELETE is followed by
			# its tree_exiting teardown for this observable hook implementation.
			manager._cache["owned"] = page
			manager._push_stack(page.ui_layer, page)
			page.tree_exiting.connect(manager._on_window_exiting.bind("owned", page))
		if mode == "explicit":
			page._do_destroy()
			page._do_destroy()
			_check(calls[0] == 1, "explicit repeated destroy invokes its hook once")
			_check(owned_result.get("done", false), "explicit hook synchronously unwinds page-owned parent wait")
			page.free()
		elif mode == "queued":
			page.queue_free()
			await process_frame
		else:
			page.free()
		_check(calls[0] == 1, mode + " invokes on_destroy exactly once including PREDELETE")
		_check(hide_result.get("done", false), mode + " cancels managed wait before freeing owner")
		_check(owned_result.get("done", false), mode + " runs real hook side effect to unwind page-owned wait")
		if manager != null:
			_check(manager.get_ui("owned") == null and manager._ordered_windows().is_empty(), "manager tree_exiting cleans ownership after PREDELETE hook")
			manager.free()


func _test_uncreated_templates() -> void:
	var template := WaitingPage.new()
	var template_calls: Array[int] = template.destroy_calls
	var packed := PackedScene.new()
	_check(packed.pack(template) == OK, "uncreated fixture packs before entering the tree")
	template.free()
	_check(template_calls[0] == 0, "uncreated template cannot invoke initialization-dependent on_destroy")
	var instance := packed.instantiate() as WaitingPage
	_check(instance != null and instance.get_window_state() == UIBaseWindow.WindowState.INVALID, "PackedScene instance starts outside the UI lifecycle")
	var instance_calls: Array[int] = instance.destroy_calls
	instance.free()
	_check(instance_calls[0] == 0, "PackedScene instantiate then free skips uninitialized product hook")
	instance = packed.instantiate() as WaitingPage
	instance_calls = instance.destroy_calls
	instance._do_destroy()
	_check(instance.get_window_state() == UIBaseWindow.WindowState.DESTROYED and instance_calls[0] == 0, "explicit destroy of INVALID template still reaches terminal state without hook")
	instance.free()
	_check(instance_calls[0] == 0, "subsequent PREDELETE does not create or rerun a hook")
