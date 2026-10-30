## 首次持久化必须先成功再开放核心；失败保留旧档，同一实例可安全重试。
extends SceneTree

const Files = preload("res://scripts/framework/storage/save_store.gd")
const Core = preload("res://scripts/framework/storage/local_core_store.gd")
const Product = preload("res://products/meowdoku/app/state/meowdoku_store.gd")
const PASSWORD := "storage-initialization-test"

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use tools/run_validation.py")
		quit(2)
		return
	_test_memory_open()
	_test_initial_failure("before_write", false)
	for phase: String in ["before_write", "after_temp_write", "before_replace"]:
		_test_initial_failure(phase, true)
	_test_initial_publication()
	for kind: String in ["corrupt", "invalid_state", "future_schema", "future_format"]:
		_test_existing_rejected(kind)
	_test_existing_preserved()
	print("STORAGE INITIALIZATION TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _profile(level: int = 1) -> ConfigFile:
	var profile := ConfigFile.new()
	profile.set_value("progress", "current_level", level)
	profile.set_value("progress", "tool_hint", 7)
	profile.set_value("progress", "tool_locate", 5)
	profile.set_value("progress", "tool_undo", 3)
	return profile


func _legacy(dir: String) -> Array:
	return [Files.new(PASSWORD, dir, false, dir.path_join("player.cfg")), Files.new(PASSWORD, dir, false, dir.path_join("endgame.cfg"))]


func _open(product: RefCounted, legacy: Array, dir: String) -> Dictionary:
	return product.open(_profile(), legacy[0], legacy[1], dir.path_join("streak.cfg"))


func _test_memory_open() -> void:
	var dir := "user://initialization-memory"
	var product := Product.new(dir, PASSWORD)
	var events := [0]
	var listener := func(_revision: int) -> void: events[0] += 1
	product.core.committed.connect(listener)
	var result: Dictionary = product.core.open({"product": "meowdoku"}, true)
	_check(not result.ok and not product.core.is_open(), "invalid initial state never opens the core")
	var initial: Dictionary = Product.from_legacy(_profile(), null, {})
	result = product.core.open(initial)
	_check(result.ok and result.status == "missing" and product.core.is_open() and product.core.revision() == 0, "default open preserves the explicit in-memory initialization contract")
	_check(product.files.load_result().status == "missing" and events[0] == 0, "default open neither persists nor emits a commit")
	initial.inventory.hint = 99
	_check(product.core.snapshot().inventory.hint == 7, "opened initial state owns its nested data")
	product.core.committed.disconnect(listener)


func _test_initial_failure(phase: String, migrate: bool) -> void:
	var label := phase + ("-migration" if migrate else "-fresh")
	var dir := "user://initialization-" + label
	var legacy := _legacy(dir)
	var paths: Array[String] = []
	if migrate:
		var profile := _profile(48)
		profile.set_value("progress", "in_flight_awards", [{"uid": 12, "items": [{"kind": "hint", "count": 2}], "reason": "legacy", "display_type": 0}])
		_check(legacy[0].save_config(profile), label + " prepares legacy progress and reward")
		var endgame := ConfigFile.new()
		endgame.set_value("snapshot", "data", {"level": 48, "fixture": "kept"})
		_check(legacy[1].save_config(endgame), label + " prepares a legacy checkpoint")
		var streak := ConfigFile.new()
		streak.set_value("streak", "pending_switch_page", 1)
		_check(streak.save(dir.path_join("streak.cfg")) == OK, label + " prepares the pending migration award")
		paths = [dir.path_join("player.cfg"), dir.path_join("endgame.cfg"), dir.path_join("streak.cfg")]
	var hashes: Dictionary = {}
	for path: String in paths:
		hashes[path] = FileAccess.get_sha256(path)
	var product := Product.new(dir, PASSWORD)
	var original_core: RefCounted = product.core
	var events := [0]
	var listener := func(_revision: int) -> void: events[0] += 1
	original_core.committed.connect(listener)
	product.files.set_fault_injector_for_tests(func(point: String) -> bool: return point == phase)
	var failed: Dictionary = _open(product, legacy, dir)
	_check(not failed.ok and failed.error == "write_failed", label + " exposes the first write failure")
	_check(product.core == original_core and not original_core.is_open() and original_core.revision() == 0 and original_core.snapshot().is_empty(), label + " publishes no candidate and keeps the same unopened core")
	_check(original_core.commit(Product.from_legacy(_profile(), null, {}), 0).error == "not_open", label + " cannot bypass initialization through a business commit")
	_check(events[0] == 0 and product.files.load_result().status == "missing", label + " emits no success and creates no committed slot")
	for path: String in paths:
		_check(FileAccess.get_sha256(path) == hashes[path], label + " preserves the legacy source " + path.get_file())
	product.files.set_fault_injector_for_tests(Callable())
	var retried: Dictionary = _open(product, legacy, dir)
	_check(retried.ok and product.core == original_core and original_core.is_open() and original_core.revision() == 1, label + " retries successfully with the retained core reference")
	_check(events[0] == 1, label + " publishes exactly one successful initialization")
	var saved: Dictionary = original_core.snapshot()
	_check(saved.profile.current_level == (48 if migrate else 1) and saved.inventory.hint == 7, label + " commits the intended progress and inventory")
	_check(saved.award_sequence == (13 if migrate else 0) and saved.pending_awards.size() == (2 if migrate else 0), label + " does not duplicate migrated or switch awards on retry")
	if migrate:
		_check(saved.endgame.snapshot.fixture == "kept" and saved.features.streak.switch_award_uid == 13, label + " retains checkpoint and once-only switch entitlement")
	var committed_hash: String = FileAccess.get_sha256(dir.path_join("core_a.cfg"))
	var repeated: Dictionary = _open(product, legacy, dir)
	_check(not repeated.ok and repeated.error == "already_open" and events[0] == 1 and original_core.revision() == 1, label + " reopening the same live instance does not write again")
	_check(FileAccess.get_sha256(dir.path_join("core_a.cfg")) == committed_hash and not FileAccess.file_exists(dir.path_join("core_b.cfg")), label + " has only one committed initialization revision")
	var reopened := Product.new(dir, PASSWORD)
	_check(_open(reopened, legacy, dir).ok and reopened.core.snapshot() == saved and reopened.core.revision() == 1, label + " a fresh instance recovers the exact committed state")
	for path: String in paths:
		_check(FileAccess.get_sha256(path) == hashes[path], label + " successful migration leaves source unchanged " + path.get_file())
	original_core.committed.disconnect(listener)


func _test_initial_publication() -> void:
	var dir := "user://initialization-publication"
	var files := Files.new(PASSWORD, dir, true, dir.path_join("a.cfg"), dir.path_join("b.cfg"), dir.path_join("flag"))
	var core := Core.new(files, 1)
	var events := [0]
	var listener := func(revision: int) -> void:
		events[0] += 1
		_check(core.is_open() and core.revision() == revision and files.load_result().revision == revision, "initial notification observes the already-published durable state")
		if revision == 1:
			_check(core.snapshot().counter == 1, "initial notification sees the first candidate")
			_check(core.commit({"counter": 2}, revision).ok, "initial notification may submit a subsequent transaction")
	core.committed.connect(listener)
	var result: Dictionary = core.open({"counter": 1}, true)
	_check(result.ok and result.revision == 1 and core.revision() == 2 and core.snapshot().counter == 2 and events[0] == 2, "returning from initialization never overwrites a newer notification commit")
	core.committed.disconnect(listener)


func _test_existing_rejected(kind: String) -> void:
	var dir := "user://initialization-reject-" + kind
	_check(DirAccess.make_dir_recursive_absolute(dir) == OK, kind + " creates its isolated fixture directory")
	var path := dir.path_join("core_a.cfg")
	if kind == "corrupt":
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("not a valid encrypted save")
		file.close()
	else:
		var cfg := ConfigFile.new()
		cfg.set_value("core", "schema_version", 2 if kind == "future_schema" else 1)
		cfg.set_value("core", "state", {"product": "invalid"} if kind == "invalid_state" else Product.from_legacy(_profile(48), null, {}))
		cfg.set_value("__save_store", "format_version", 2 if kind == "future_format" else 1)
		cfg.set_value("__save_store", "revision", 7)
		_check(cfg.save_encrypted_pass(path, PASSWORD) == OK, kind + " writes a versioned fixture")
	var hash_before := FileAccess.get_sha256(path)
	var product := Product.new(dir, PASSWORD)
	var expected: String = {"corrupt": "corrupt", "invalid_state": "invalid_state", "future_schema": "schema_mismatch", "future_format": "unsupported"}[kind]
	for attempt in 2:
		var rejected: Dictionary = product.core.open(Product.from_legacy(_profile(), null, {}), true)
		_check(not rejected.ok and rejected.error == expected and not product.core.is_open() and product.core.snapshot().is_empty() and product.core.revision() == 0, kind + " cannot become a fresh player on attempt " + str(attempt))
	_check(FileAccess.get_sha256(path) == hash_before and not FileAccess.file_exists(dir.path_join("core_b.cfg")), kind + " leaves existing evidence intact")


func _test_existing_preserved() -> void:
	var dir := "user://initialization-existing"
	var product := Product.new(dir, PASSWORD)
	var initial: Dictionary = Product.from_legacy(_profile(48), null, {})
	_check(product.core.open(initial, true).ok, "existing-state fixture is committed once")
	var hash_before := FileAccess.get_sha256(dir.path_join("core_a.cfg"))
	var reopened := Product.new(dir, PASSWORD)
	var result: Dictionary = reopened.core.open(Product.from_legacy(_profile(), null, {}), true)
	_check(result.ok and result.status == "loaded" and reopened.core.snapshot() == initial and reopened.core.revision() == 1, "persist_initial only applies to missing files and never substitutes defaults")
	_check(FileAccess.get_sha256(dir.path_join("core_a.cfg")) == hash_before and not FileAccess.file_exists(dir.path_join("core_b.cfg")), "opening existing state performs no redundant commit")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
