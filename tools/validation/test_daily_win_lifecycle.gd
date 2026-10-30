## 真实每日结算页：隐藏、同窗刷新与销毁都使旧延迟失效。
extends SceneTree

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var host := Node.new()
	root.add_child(host)
	current_scene = host
	root.get_node("GameState").set_sound_on(false)
	var ui: Node = root.get_node("UIManager")
	var page: Variant = ui.show_ui("daily_win", _params(10))
	await create_timer(0.05).timeout
	ui.hide_ui("daily_win")
	_check(page.is_hidden() and not page._anim.is_playing(), "hide stops appearance immediately")
	await create_timer(0.85).timeout
	_check(page.is_hidden() and not page._anim.is_playing() and not page._anim_loop.is_playing(), "hidden presentation cannot restart animations after old delay")
	_check(is_zero_approx(page._cat.get_animation_state().get_time_scale()), "hidden cat remains paused after old delay")

	ui.show_ui("daily_win", _params(20))
	await create_timer(0.55).timeout
	ui.show_ui("daily_win", _params(30))
	await create_timer(0.3).timeout
	_check(page.is_showing() and not page._anim.is_playing(), "refresh invalidates earlier delay while keeping the new presentation pending")
	_check(page._time_label.get_parsed_text().contains("00:30"), "refresh keeps the latest result text")
	await create_timer(0.55).timeout
	_check(page._anim.is_playing() and page._anim_loop.is_playing(), "current delayed presentation still starts normally")
	ui.hide_ui("daily_win")
	_check(not page._anim.is_playing() and not page._anim_loop.is_playing(), "hide stops both appearance and button loop")

	ui.show_ui("daily_win", {"level_config": {"elapsed_sec": 40, "beat_percent": 50.0, "skip_appear_delay": true}})
	_check(page._anim.is_playing(), "skip-delay presentation still starts immediately")
	ui.hide_ui("daily_win")
	ui.show_ui("daily_win", _params(50))
	page._do_destroy()
	await create_timer(0.85).timeout
	_check(page.get_window_state() == UIBaseWindow.WindowState.DESTROYED and not page._anim.is_playing(), "destroy invalidates a pending presentation without requiring node deletion")
	host.queue_free()
	await process_frame
	await process_frame
	print("DAILY WIN LIFECYCLE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _params(elapsed: int) -> Dictionary:
	return {"level_config": {"elapsed_sec": elapsed, "beat_percent": 50.0}}


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
