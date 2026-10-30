## 独立接入验收；只由 run_framework_boundary_tests.py 复制到无产品的工程运行。
extends SceneTree

const Files = preload("res://scripts/framework/storage/save_store.gd")
const Core = preload("res://scripts/framework/storage/local_core_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const Catalog = preload("res://scripts/framework/content/content_catalog.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	if not ProjectSettings.get_setting("test/framework_boundary_isolated", false) or not ProjectSettings.globalize_path("res://").contains("/doku-framework-boundary-"):
		printerr("TEST_FAILED: use tools/run_framework_boundary_tests.py")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	for folder: String in ["app", "gameplays", "examples"]:
		_check(not DirAccess.dir_exists_absolute("res://scripts/" + folder), "no product directory: " + folder)
	_check(not DirAccess.dir_exists_absolute("res://products"), "no product implementation or assets")
	_check(not DirAccess.dir_exists_absolute("res://assets"), "no product assets")
	_check(not DirAccess.dir_exists_absolute("res://addons"), "no product plugins")
	var autoloads: Array[String] = []
	for setting: Dictionary in ProjectSettings.get_property_list():
		if str(setting.name).begins_with("autoload/"):
			autoloads.append(str(setting.name))
	_check(autoloads.is_empty(), "no product Autoload")
	var scripts: Array = ProjectSettings.get_setting("test/framework_scripts", [])
	_check(scripts.size() > 20, "entire framework manifest is populated")
	for path: String in scripts:
		var script: Script = load(path)
		_check(script != null and script.can_instantiate(), "standalone script: " + path)
	var directory := ProjectSettings.globalize_path("res://validation_artifacts")
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "isolated writable directory")
	_test_storage_and_rewards(directory.path_join("profile"))
	_test_content(directory)
	await _test_windows(directory)
	await process_frame
	print("FRAMEWORK CONSUMER TESTS: %d assertions, %d failures" % [_checks, _failures])
	quit.call_deferred(0 if _failures == 0 else 1)


func _files(directory: String) -> RefCounted:
	return Files.new("consumer-fixture-only", directory, true, directory.path_join("a.cfg"), directory.path_join("b.cfg"), directory.path_join("flag"))


func _validate(state: Dictionary) -> String:
	if typeof(state.get("score")) != TYPE_INT or state.score < 0:
		return "score must be a nonnegative integer"
	if not state.get("inventory") is Dictionary or typeof(state.inventory.get("gem")) != TYPE_INT or state.inventory.gem < 0:
		return "gem inventory is invalid"
	return ""


func _test_storage_and_rewards(directory: String) -> void:
	var files := _files(directory)
	var core := Core.new(files, 1, _validate)
	var opened: Dictionary = core.open({"score": 0, "inventory": {"gem": 0}})
	_check(opened.ok, "fresh product state opens without GameState")
	if not opened.ok:
		return
	var candidate: Dictionary = core.snapshot()
	candidate.score = 10
	_check(core.commit(candidate, core.revision()).ok, "commit custom product field")
	var revision: int = core.revision()
	candidate.score = -1
	_check(not core.commit(candidate, revision).ok, "product validator rejects invalid candidate")
	_check(core.snapshot().score == 10 and core.revision() == revision, "rejection preserves live state and revision")
	candidate.score = 20
	files.set_fault_injector_for_tests(func(stage: String) -> bool: return stage == "before_replace")
	var failed: Dictionary = core.commit(candidate, revision)
	_check(not failed.ok and core.snapshot().score == 10, "write failure preserves live product state")
	files.set_fault_injector_for_tests(Callable())
	_check(core.commit(candidate, revision).ok, "retry same revision succeeds")
	var economy := Economy.new(core)
	var registered: Dictionary = economy.register_award([{"kind": "gem", "count": 3}], 0, "sample_reward", "", "sample/one")
	_check(registered.ok, "optional reward service accepts product inventory kind")
	if registered.ok:
		var duplicate: Dictionary = economy.register_award([{"kind": "gem", "count": 3}], 0, "sample_reward", "", "sample/one")
		_check(duplicate.get("duplicate", false) and duplicate.uid == registered.uid, "product claim identity deduplicates registration")
		_check(economy.claim_award(registered.uid).ok, "claim custom product reward")
		_check(economy.claim_award(registered.uid).ok and core.snapshot().inventory.gem == 3, "duplicate claim does not grant twice")
	var reopened := Core.new(_files(directory), 1, _validate)
	_check(reopened.open({}).ok and reopened.snapshot() == core.snapshot(), "new instance restores committed state")
	var incompatible := Core.new(_files(directory), 2, _validate)
	_check(not incompatible.open({"score": 0, "inventory": {"gem": 0}}).ok, "schema mismatch is not silently reset")


func _test_content(directory: String) -> void:
	ContentContext.publish(null)
	_check(ContentContext.read_json("tuning").get("error") == "unknown_content", "unconfigured content allows explicit builtin fallback")
	_check(ContentSceneBindings.registry().is_empty(), "no implicit Meowdoku scene bindings")
	var fallback := GradientTexture2D.new()
	_check(ContentContext.load_texture("custom/logo", fallback) == fallback, "missing optional media preserves supplied resource")
	var path := directory.path_join("tuning.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "create custom content fixture")
		return
	file.store_string('{"board_width": 8}')
	file.close()
	var entry := {"id": "tuning", "kind": "json", "path": "tuning.json", "bytes": FileAccess.get_file_as_bytes(path).size(), "sha256": FileAccess.get_sha256(path)}
	# 直接验证 catalog 消费合同；签名/下载/激活由已有内容专项验证，不在这里伪装成已验收。
	var catalog := Catalog.new(directory, {"release": "sample-1", "files": [entry]})
	ContentContext.publish(catalog)
	var loaded: Dictionary = ContentContext.read_json("tuning")
	_check(loaded.ok and loaded.value.board_width == 8, "consume custom JSON without Doku schema")
	if loaded.ok:
		loaded.value.board_width = 1
		_check(ContentContext.read_json("tuning").value.board_width == 8, "consumer cannot mutate cached content")
	ContentContext.publish(null)
	_check(ContentContext.data_release_id() == "builtin", "product can release its active context")


func _test_windows(directory: String) -> void:
	var scene := Control.new()
	root.add_child(scene)
	current_scene = scene
	var prototype := UIFrameWindow.new()
	var packed := PackedScene.new()
	_check(packed.pack(prototype) == OK, "pack product-owned window")
	prototype.free()
	var path := directory.path_join("sample_window.tscn")
	_check(ResourceSaver.save(packed, path) == OK, "save isolated window fixture")
	var manager := UIWindowManager.new()
	manager.configure({"sample": path})
	scene.add_child(manager)
	var shown: UIFrameWindow = manager.show_ui("sample")
	_check(shown != null and shown.is_showing(), "show window without UiName, sounds or product assets")
	if shown != null:
		manager.hide_ui("sample")
		await process_frame
		_check(not shown.is_showing(), "close product window")
		_check(manager.show_ui("sample") == shown, "reuse cached product window")
	manager.queue_free()
	await process_frame
	current_scene = null
	scene.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("TEST_FAILED: " + message)
