## 教学搭盘故障必须阻止真实启动器确认候选版本健康，保留下一次冷启动回退的依据。
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
	var store := _trial_store()
	var candidate: Dictionary = store.begin_cold_start()
	_check(candidate.ok and candidate.get("trial", false), "real signed candidate begins an unconfirmed cold start")
	if not candidate.ok:
		quit(1)
		return
	var runtime: Node = root.get_node("ContentRuntime")
	runtime._store = store
	runtime._catalog = candidate.catalog
	runtime._trial = true
	runtime._last_result = candidate
	ContentContext.publish(candidate.catalog)

	var ui: Node = root.get_node("UIManager")
	var tutorial: Variant = ui._get_or_create("tutorial")
	var failed_board: Node = load("res://tools/validation/fixtures/incomplete_tutorial_board.gd").new()
	tutorial.add_child(failed_board)
	tutorial._board_view = failed_board
	var launcher: Node = load("res://products/meowdoku/app/bootstrap/launcher.gd").new()
	host.add_child(launcher)
	var deadline: int = Time.get_ticks_msec() + 10000
	while not _has_error_screen(launcher) and not launcher._startup_complete and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not tutorial.is_board_ready() and tutorial._current_mode == tutorial.StepMode.NONE, "failed board never starts teaching steps")
	_check(failed_board.mouse_filter == Control.MOUSE_FILTER_IGNORE, "failed board does not accept input")
	_check(_has_error_screen(launcher) and not launcher._startup_complete, "actual launcher shows startup error instead of declaring completion")
	_check(runtime._trial and store.state_snapshot().trial == "tutorial-failure", "actual launcher leaves signed trial unconfirmed")
	var reopened := ContentStore.new("user://tutorial-boot/cache", "test", "runtime-v1", store._public_key)
	var recovered: Dictionary = reopened.begin_cold_start()
	_check(recovered.ok and recovered.get("builtin", false) and recovered.get("fallback_reason") == "trial_incomplete", "next cold-start decision rolls back the unconfirmed trial")
	_check(reopened.state_snapshot().rejected == "tutorial-failure", "failed trial is recorded as rejected")
	print("CONTENT_TUTORIAL_BOOT_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _trial_store() -> ContentStore:
	var directory: String = "user://tutorial-boot"
	var source: String = directory.path_join("source")
	DirAccess.make_dir_recursive_absolute(source)
	var key := Crypto.new().generate_rsa(2048)
	var body := '{"schema":1,"draft_unlock_level":21}'.to_utf8_buffer()
	ContentStore._write_bytes(source.path_join("policy.json"), body)
	var manifest := JSON.stringify({"format": 1, "product": "test", "runtime": "runtime-v1", "release": "tutorial-failure", "files": [{"id": "doku/policy", "path": "policy.json", "kind": "json", "bytes": body.size(), "sha256": FileAccess.get_sha256(source.path_join("policy.json"))}]}).to_utf8_buffer()
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, ContentManifest.digest(manifest), key)
	var store := ContentStore.new(directory.path_join("cache"), "test", "runtime-v1", key.save_to_string(true))
	_check(store.install(source, manifest, signature).ok, "signed content fixture installs")
	_check(store.stage("tutorial-failure").ok, "signed content fixture stages")
	return store


func _has_error_screen(launcher: Node) -> bool:
	for child: Node in launcher.get_children():
		if child is CanvasLayer and child.get_script() == null:
			return true
	return false


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
