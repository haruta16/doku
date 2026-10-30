extends SceneTree

const FixtureGuard = preload("res://tools/validation/fixtures/content_fixture_guard.gd")

const Store = preload("res://scripts/framework/content/content_store.gd")
var _checks := 0
var _failures := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1 or not FixtureGuard.allows(args[0]):
		quit(2)
		return
	var directory := args[0]
	var source := directory.path_join("spine")
	var store := Store.new(directory.path_join("cache"), "test", "runtime-v1", FileAccess.get_file_as_string(directory.path_join("public.pem")))
	if args.size() > 1 and args[1] == "resume":
		var resumed: Dictionary = store.begin_cold_start()
		if not _check(resumed.ok and resumed.catalog.release_id() == "data-next" and resumed.has("resource_catalog") and resumed.resource_catalog.release_id() == "spine" and resumed.resource_catalog.load_spine("maomi_fuor.tres").ok):
			push_error("SPINE_TEST_FAILED: real cold-start media inheritance: " + str(resumed))
			quit(8)
			return
		print("SPINE_CONTENT_COLD_RESUME checks=%d failures=%d" % [_checks, _failures])
		quit(0)
		return
	var installed: Dictionary = store.install(source, FileAccess.get_file_as_bytes(source.path_join("manifest.json")), FileAccess.get_file_as_bytes(source.path_join("manifest.sig")))
	if not _check(installed.ok and store.stage("spine").ok):
		push_error("SPINE_TEST_FAILED: install: " + str(installed))
		quit(3)
		return
	var boot: Dictionary = store.begin_cold_start()
	if not _check(boot.ok and boot.trial):
		push_error("SPINE_TEST_FAILED: boot: " + str(boot))
		quit(4)
		return
	var loaded: Dictionary = boot.catalog.load_spine("maomi_fuor.tres")
	if not _check(loaded.ok and store.confirm_healthy("spine").ok):
		push_error("SPINE_TEST_FAILED: resource: " + str(loaded))
		quit(5)
		return
	var next_source := directory.path_join("data-next")
	var data_installed: Dictionary = store.install(next_source, FileAccess.get_file_as_bytes(next_source.path_join("manifest.json")), FileAccess.get_file_as_bytes(next_source.path_join("manifest.sig")))
	if not _check(data_installed.ok and store.stage("data-next").ok and store.activate_data().ok):
		push_error("SPINE_TEST_FAILED: JSON transition")
		quit(6)
		return
	if not _check(store.state_snapshot().active == "data-next" and store.state_snapshot().media_active == "spine"):
		push_error("SPINE_TEST_FAILED: independent media identity")
		quit(7)
		return
	store.prune_unreferenced()
	print("SPINE_CONTENT_TEST checks=%d failures=%d" % [_checks, _failures])
	quit(0)


func _check(passed: bool) -> bool:
	_checks += 1
	if not passed:
		_failures += 1
	return passed
