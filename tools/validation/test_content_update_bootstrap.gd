## 由 run_tests.py 建立最小 Autoload 工程；真实 ContentRuntime 不接触玩家存档。
extends SceneTree

const FixtureGuard = preload("res://tools/validation/fixtures/content_fixture_guard.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not FixtureGuard.allows(args[0]):
		quit(2)
		return
	var runtime := root.get_node("ContentRuntime")
	if args.size() == 3 and args[2] == "resume":
		_check(runtime.release_id() == "http", "independent process loads persisted active JSON without network")
		_check(runtime._store.state_snapshot().channel.revision == 2, "independent process retains accepted channel revision")
		_check(ContentContext.read_json("levels").value.level == 8, "independent process publishes actual cached data")
		_check(not runtime.diagnostics().updating, "empty update source does not start a request")
	else:
		var result: Dictionary = await runtime.check_for_updates()
		if result.get("error") == "download_busy":
			while runtime.diagnostics().updating:
				await process_frame
			result = runtime.diagnostics().last_result
		_check(result.ok and runtime._store.state_snapshot().pending == "http", "autoload discovers and stages verified channel target")
		_check(runtime.release_id() == "builtin", "background download does not change current content")
		_check(runtime.activate_for_new_round().ok and runtime.release_id() == "http", "new-round activation publishes staged JSON")
		_check(ContentContext.read_json("levels").value.level == 8, "actual content facade sees chosen data")
		result = await runtime.check_for_updates()
		_check(result.ok and result.already_installed and runtime._store.state_snapshot().pending.is_empty(), "repeat autoload update does not create trial for active version")
		var cancel_callback := func(progress: Dictionary) -> void:
			if progress.phase == "discovering":
				runtime.cancel_update()
		runtime.update_progress.connect(cancel_callback)
		result = await runtime.check_for_updates()
		runtime.update_progress.disconnect(cancel_callback)
		_check(result.get("cancelled", false) and not runtime.diagnostics().updating and runtime.release_id() == "http", "public cancel API finishes without staging or changing active data")
		await _test_fixed_update_config(runtime, str(args[0]), str(args[1]))
		ProjectSettings.set_setting("content/channel_url", str(args[1]) + "/missing-channel")
		result = await runtime.check_for_updates()
		_check(not result.ok and runtime.release_id() == "http", "discovery failure leaves published content available")
		_check(runtime.diagnostics().maintenance.has("interrupted") and runtime.diagnostics().maintenance.has("pruned"), "startup and post-activation maintenance are observable")
		await _test_activation_during_download_finish(runtime, str(args[0]), str(args[1]))
		await _test_confirmation_during_download_finish(runtime, str(args[0]), str(args[1]))
	print("CONTENT_BOOTSTRAP_TESTS checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_fixed_update_config(runtime: Node, work: String, url: String) -> void:
	ProjectSettings.set_setting("content/channel_url", "")
	ProjectSettings.set_setting("content/release_url", url + "/http")
	var result: Dictionary = await runtime.check_for_updates()
	_check(result.get("error") == "release_identity_required", "automatic fixed URL requires an explicit manifest identity")
	ProjectSettings.set_setting("content/release_id", "http")
	result = await runtime.check_for_updates()
	_check(result.get("error") == "release_identity_invalid", "automatic fixed URL rejects partial identity configuration")
	ProjectSettings.set_setting("content/release_manifest_sha256", "0".repeat(64))
	result = await runtime.check_for_updates()
	_check(result.get("error") == "release_identity_mismatch" and runtime.release_id() == "http", "automatic fixed URL cannot replay other signed manifest bytes")
	ProjectSettings.set_setting("content/release_manifest_sha256", FileAccess.get_sha256(work.path_join("http/manifest.json")))
	result = await runtime.check_for_updates()
	_check(result.ok and result.get("already_installed", false) and runtime._store.state_snapshot().pending.is_empty(), "automatic fixed URL accepts the complete pinned identity")
	ProjectSettings.set_setting("content/release_url", "")
	ProjectSettings.set_setting("content/release_id", "")
	ProjectSettings.set_setting("content/release_manifest_sha256", "")


## 下载完成通知可同步开启新局；已安装但尚未 stage 的版本不能被该次激活清理掉。
func _test_activation_during_download_finish(runtime: Node, work: String, url: String) -> void:
	var next := _write_release(work, "next", 9)
	_write_release(work, "later", 10)
	_check(runtime._store.install(work.path_join("next"), next.bytes, next.signature).ok and runtime._store.stage("next").ok, "prepare one pending release while another is downloaded")
	var activated: Dictionary = {"called": false}
	var callback := func(progress: Dictionary) -> void:
		if progress.phase == "complete":
			activated.called = true
			activated.result = runtime.activate_for_new_round()
	runtime.update_progress.connect(callback)
	var result: Dictionary = await runtime.download_and_stage(url + "/later")
	runtime.update_progress.disconnect(callback)
	_check(activated.called and activated.result.ok and runtime.release_id() == "next", "download completion listener can activate existing pending release")
	_check(result.ok and runtime._store.state_snapshot().pending == "later", "activation cleanup preserves freshly installed release until staging")
	_check(runtime._store.verify_release("later").ok, "staged new release retains its signed files")
	_check(runtime.activate_for_new_round().ok and ContentContext.read_json("levels").value.level == 10, "following round can consume the downloaded release")
	# 第二进程沿用原有 http 恢复断言；测试不依赖新增候选残留。
	var original := work.path_join("http")
	_check(runtime._store.install(original, FileAccess.get_file_as_bytes(original.path_join("manifest.json")), FileAccess.get_file_as_bytes(original.path_join("manifest.sig"))).ok and runtime._store.stage("http").ok and runtime.activate_for_new_round().ok, "restore original active release for independent-process fixture")


func _test_confirmation_during_download_finish(runtime: Node, work: String, url: String) -> void:
	var candidate := _write_release(work, "trial-next", 11)
	_write_release(work, "trial-later", 12)
	_check(runtime._store.install(work.path_join("trial-next"), candidate.bytes, candidate.signature).ok and runtime._store.stage("trial-next").ok, "prepare JSON trial candidate")
	# 与冷启动相同的持久状态决策；此处只有 JSON，没有同进程换挂 PCK。
	var resumed := ContentStore.new(runtime._store._root, "test", "runtime-v1", FileAccess.get_file_as_string(work.path_join("http-public.pem")))
	var trial: Dictionary = resumed.begin_cold_start()
	_check(trial.ok and trial.get("trial", false), "fresh store enters a real persisted trial")
	runtime._store = resumed
	runtime._catalog = trial.catalog
	runtime._trial = true
	ContentContext.publish(trial.catalog)
	var confirmed: Dictionary = {"called": false}
	var callback := func(progress: Dictionary) -> void:
		if progress.phase == "complete":
			confirmed.called = true
			confirmed.result = runtime.confirm_boot_healthy()
	runtime.update_progress.connect(callback)
	var result: Dictionary = await runtime.download_and_stage(url + "/trial-later")
	runtime.update_progress.disconnect(callback)
	_check(confirmed.called and confirmed.result.ok and not runtime._trial, "download completion listener can confirm current trial")
	_check(result.ok and runtime._store.state_snapshot().pending == "trial-later" and runtime._store.verify_release("trial-later").ok, "trial confirmation preserves downloaded release before staging")
	_check(runtime.activate_for_new_round().ok and ContentContext.read_json("levels").value.level == 12, "confirmed boot can activate the subsequently staged release")
	var original := work.path_join("http")
	_check(runtime._store.install(original, FileAccess.get_file_as_bytes(original.path_join("manifest.json")), FileAccess.get_file_as_bytes(original.path_join("manifest.sig"))).ok and runtime._store.stage("http").ok and runtime.activate_for_new_round().ok, "restore original active release after trial confirmation")


func _write_release(work: String, release: String, level: int) -> Dictionary:
	var key := CryptoKey.new()
	key.load(work.path_join("private.pem"))
	var directory := work.path_join(release)
	DirAccess.make_dir_recursive_absolute(directory.path_join("data"))
	var payload := JSON.stringify({"level": level}).to_utf8_buffer()
	ContentStore._write_bytes(directory.path_join("data/levels.json"), payload)
	var bytes := JSON.stringify({"format": 1, "product": "test", "release": release, "runtime": "runtime-v1", "files": [{"id": "levels", "path": "data/levels.json", "kind": "json", "bytes": payload.size(), "sha256": ContentManifest.digest(payload).hex_encode()}]}).to_utf8_buffer()
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, ContentManifest.digest(bytes), key)
	ContentStore._write_bytes(directory.path_join("manifest.json"), bytes)
	ContentStore._write_bytes(directory.path_join("manifest.sig"), signature)
	return {"bytes": bytes, "signature": signature}


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("TEST_FAILED: " + label)
