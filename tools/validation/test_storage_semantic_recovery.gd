## 可解密但业务结构已坏的槽：旧完整快照恢复、发号水位、继续提交及未来版本拒绝。
extends SceneTree
const Files = preload("res://scripts/framework/storage/save_store.gd")
const Core = preload("res://scripts/framework/storage/local_core_store.gd")
const ProductStore = preload("res://products/meowdoku/app/state/meowdoku_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")
const Doku = preload("res://products/meowdoku/gameplay/domain/doku_round_module.gd")
const PASSWORD := "semantic-recovery-test"
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	for damage: String in ["round_record", "round_snapshot", "round_content", "round_policy", "round_definition", "round_level", "round_attempt", "settlement_record", "settlement_receipt", "settlement_attempt", "settlement_level"]:
		_test_recover(damage)
	_test_double_invalid()
	_test_future(ProductStore.SCHEMA + 1, 1)
	_test_future(ProductStore.SCHEMA, 2)
	_test_recovered_reset()
	_test_legacy_watermark(3)
	_test_legacy_watermark(20)
	print("STORAGE SEMANTIC RECOVERY TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _state() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "current_level", 6)
	cfg.set_value("progress", "tool_hint", 11)
	cfg.set_value("progress", "tool_locate", 7)
	cfg.set_value("progress", "tool_undo", 4)
	var result: Dictionary = ProductStore.from_legacy(cfg, null, {})
	result.award_sequence = 9
	result.claims = {"fixture/already_claimed": 7}
	result.pending_awards = [{"uid": 9, "items": [{"kind": "hint", "count": 2}], "display_type": 0, "reason": "legacy", "bonus_reason": "", "doubled": false}]
	var created: Dictionary = Doku.new().create_snapshot({"board": [[0]], "regions": [[0]], "solution": [[true]], "content": {"level": 6}})
	result.round_services = {"doku/main": {"module_id": "doku", "mode_id": "main", "round_id": "doku/main#4", "start_sequence": 4, "last_sequence": 0, "status": "active", "start_context": {}, "snapshot": created.snapshot, "last_receipt": {}, "settlement": {}}}
	result.product_settlements = {"main": {"round_id": "doku/main#3", "last_attempt": 0, "receipt": {}, "level": 5}}
	return result

func _damage(state: Dictionary, kind: String) -> void:
	match kind:
		"round_record": state.round_services["doku/main"] = 7
		"round_snapshot": state.round_services["doku/main"].snapshot = 7
		"round_content": state.round_services["doku/main"].snapshot.content = 7
		"round_policy": state.round_services["doku/main"].snapshot.content.gameplay_policy = 7
		"round_definition": state.round_services["doku/main"].snapshot.content.level_definition = 7
		"round_level": state.round_services["doku/main"].snapshot.content.level = {}
		"round_attempt": state.round_services["doku/main"].snapshot.attempt_sequence = {}
		"settlement_record": state.product_settlements.main = 7
		"settlement_receipt": state.product_settlements.main.receipt = 7
		"settlement_attempt": state.product_settlements.main.last_attempt = {}
		"settlement_level": state.product_settlements.main.level = {}

func _write(dir: String, slot: String, state: Dictionary, revision: int, schema: int = ProductStore.SCHEMA, format: int = 1) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var cfg := ConfigFile.new()
	cfg.set_value("core", "schema_version", schema)
	cfg.set_value("core", "state", state)
	cfg.set_value("__save_store", "format_version", format)
	cfg.set_value("__save_store", "revision", revision)
	_check(cfg.save_encrypted_pass(dir.path_join("core_" + slot + ".cfg"), PASSWORD) == OK, "write encrypted isolated " + slot + " fixture")

func _open(product: RefCounted, dir: String) -> Dictionary:
	var player := Files.new(PASSWORD, dir, false, dir.path_join("no-player.cfg"))
	var endgame := Files.new(PASSWORD, dir, false, dir.path_join("no-endgame.cfg"))
	return product.open(ConfigFile.new(), player, endgame, dir.path_join("no-streak.cfg"))

func _prepare(dir: String, damage: String) -> Dictionary:
	var good := _state()
	var bad := good.duplicate(true)
	bad.profile.current_level = 19
	_damage(bad, damage)
	_write(dir, "a", good, 7)
	_write(dir, "b", bad, 8)
	return good

func _test_recover(damage: String) -> void:
	var dir: String = "user://semantic-" + damage
	var good := _prepare(dir, damage)
	var product := ProductStore.new(dir, PASSWORD)
	var before_a: String = FileAccess.get_sha256(dir.path_join("core_a.cfg"))
	var before_b: String = FileAccess.get_sha256(dir.path_join("core_b.cfg"))
	var result: Dictionary = _open(product, dir)
	_check(result.ok and result.status == "recovered", damage + " recovers a verified older slot")
	if not result.ok:
		return
	_check(product.core.snapshot() == good, "recovery does not synthesize unverified newer state")
	_check(product.core.revision() == 8, "recognizable file revision watermark never rolls back")
	_check(FileAccess.get_sha256(dir.path_join("core_a.cfg")) == before_a and FileAccess.get_sha256(dir.path_join("core_b.cfg")) == before_b, "opening recovery never rewrites source evidence")
	var rejected: Dictionary = good.duplicate(true)
	_damage(rejected, damage)
	_check(not product.core.commit(rejected, product.core.revision()).ok, "same malformed shape cannot be newly committed")
	var next: Dictionary = product.core.snapshot()
	next.profile.current_level = 20
	product.files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not product.core.commit(next, 8).ok and product.core.revision() == 8 and product.core.snapshot() == good, "failed first repair retains recovered state and file watermark")
	_check(FileAccess.get_sha256(dir.path_join("core_b.cfg")) == before_b, "failed repair preserves the original bad slot for retry")
	product.files.set_fault_injector_for_tests(Callable())
	_check(product.core.commit(next, 8).ok and product.core.revision() == 9, "first save after recovery repairs bad slot with a new file revision")
	next = product.core.snapshot()
	next.profile.current_level = 21
	_check(product.core.commit(next, 9).ok and product.core.revision() == 10, "second save after recovery advances other slot")
	var reopened := ProductStore.new(dir, PASSWORD)
	_check(_open(reopened, dir).ok and reopened.core.revision() == 10 and reopened.core.snapshot().profile.current_level == 21, "reopen selects the latest post-recovery commit")
	var economy := Economy.new(reopened.core)
	var balance: int = reopened.core.snapshot().inventory.hint
	_check(economy.register_award([{ "kind": "hint", "count": 2}], 0, "duplicate", "", "fixture/already_claimed").duplicate, "known old claim retains idempotent qualification")
	_check(economy.claim_award(7).status == "already_applied" and reopened.core.snapshot().inventory.hint == balance, "known previously claimed uid cannot pay again")
	_check(economy.claim_award(9).ok and reopened.core.snapshot().inventory.hint == balance + 2, "verified pending old award remains claimable once")
	_check(economy.claim_award(9).status == "already_applied" and reopened.core.snapshot().inventory.hint == balance + 2, "recovered pending award remains idempotent")
	var registered: Dictionary = economy.register_award([{ "kind": "hint", "count": 1}], 0, "new")
	_check(registered.ok and registered.uid == 10, "verified award sequence continues above recovered watermark")

func _test_double_invalid() -> void:
	var dir: String = "user://semantic-double-invalid"
	var bad := _state()
	_damage(bad, "round_record")
	_write(dir, "a", bad, 7)
	_write(dir, "b", bad, 8)
	var product := ProductStore.new(dir, PASSWORD)
	var a: String = FileAccess.get_sha256(dir.path_join("core_a.cfg"))
	var b: String = FileAccess.get_sha256(dir.path_join("core_b.cfg"))
	var result: Dictionary = _open(product, dir)
	_check(not result.ok and result.status == "invalid_state" and not product.core.is_open(), "two invalid business snapshots refuse fresh-user fallback")
	_check(not product.core.commit(_state(), 8).ok, "failed open cannot overwrite bad slots with defaults")
	_check(FileAccess.get_sha256(dir.path_join("core_a.cfg")) == a and FileAccess.get_sha256(dir.path_join("core_b.cfg")) == b, "two bad slots are preserved for recovery")

func _test_future(schema: int, format: int) -> void:
	var dir: String = "user://semantic-future-" + str(schema) + "-" + str(format)
	_write(dir, "a", _state(), 7)
	_write(dir, "b", _state(), 8, schema, format)
	var product := ProductStore.new(dir, PASSWORD)
	var before: String = FileAccess.get_sha256(dir.path_join("core_b.cfg"))
	var result: Dictionary = _open(product, dir)
	_check(not result.ok and result.status == ("schema_mismatch" if schema > ProductStore.SCHEMA else "unsupported"), "future schema/file format prevents fallback to older application state")
	_check(not product.core.is_open() and not product.core.commit(_state(), 7).ok, "future data cannot be overwritten through unopened core")
	_check(FileAccess.get_sha256(dir.path_join("core_b.cfg")) == before, "future file remains untouched")

func _test_recovered_reset() -> void:
	var dir: String = "user://semantic-recovered-reset"
	_prepare(dir, "settlement_record")
	var product := ProductStore.new(dir, PASSWORD)
	var opened: Dictionary = _open(product, dir)
	_check(opened.ok, "prepare recovered reset facade")
	if not opened.ok:
		return
	var game: Node = root.get_node("GameState")
	game._product_store = product
	game._core_store = product.core
	game._economy_service = Economy.new(product.core)
	product.core.committed.connect(game._on_core_committed)
	game._load_data()
	game._storage_ready = true
	_check(game.reset_all(), "actual GameState reset works after semantic recovery")
	var after: Dictionary = game.get_core_store().snapshot()
	_check(after.award_sequence == 9 and after.round_services["doku/main"].start_sequence == 4, "reset preserves verified reward and round high watermarks")
	_check(after.pending_awards.is_empty() and after.claims.is_empty() and after.round_services["doku/main"].status == "reset", "reset cancels only old known qualifications")
	var economy: RefCounted = game.get_economy_service()
	_check(economy.claim_award(9).status == "already_applied", "old pre-reset uid cannot pay from new inventory")
	var registered: Dictionary = economy.register_award([{ "kind": "hint", "count": 1}], 0, "after_reset")
	_check(registered.ok and registered.uid == 10, "new award after recovered reset cannot reuse old uid")
	var host := Host.new(game.get_core_store())
	host.register_module("doku", Doku.new())
	_check(not host.start("doku", "main", 4, {}).ok, "old start identity remains invalid after recovered reset")
	_check(host.start("doku", "main", 5, {"board": [[0]], "regions": [[0]], "solution": [[true]]}).ok, "new round can start above the recovered reset watermark")

func _test_legacy_watermark(legacy_revision: int) -> void:
	var dir: String = "user://semantic-legacy-watermark-" + str(legacy_revision)
	var good := _state()
	var bad := good.duplicate(true)
	_damage(bad, "round_record")
	_write(dir, "a", bad, 10)
	_write(dir, "b", bad, 11)
	_write(dir, "legacy", good, legacy_revision)
	var legacy_path: String = dir.path_join("core_legacy.cfg")
	var legacy_hash: String = FileAccess.get_sha256(legacy_path)
	var files := Files.new(PASSWORD, dir, true, dir.path_join("core_a.cfg"), dir.path_join("core_b.cfg"), dir.path_join("flag"), legacy_path)
	_check(files.load_result().revision == 11, "without validator the existing physical-slot selection remains unchanged")
	var core := Core.new(files, ProductStore.SCHEMA, ProductStore.validate_state)
	var result: Dictionary = core.open()
	var watermark: int = maxi(11, legacy_revision)
	_check(result.ok and result.status == "recovered_legacy" and core.snapshot() == good, "semantic fallback may recover a verified legacy configuration")
	_check(core.revision() == watermark and int(files.last_result().get("source_revision", legacy_revision)) == legacy_revision, "legacy source revision is separate from maximum recognizable file watermark")
	var candidate: Dictionary = core.snapshot()
	candidate.profile.current_level = 7
	_check(core.commit(candidate, watermark).ok and core.revision() == watermark + 1, "first legacy recovery save advances above both invalid slots")
	candidate = core.snapshot()
	candidate.profile.current_level = 8
	_check(core.commit(candidate, watermark + 1).ok and core.revision() == watermark + 2, "second legacy recovery save does not conflict with a remaining old bad slot")
	var next_files := Files.new(PASSWORD, dir, true, dir.path_join("core_a.cfg"), dir.path_join("core_b.cfg"), dir.path_join("flag"), legacy_path)
	var reopened := Core.new(next_files, ProductStore.SCHEMA, ProductStore.validate_state)
	_check(reopened.open().ok and reopened.revision() == watermark + 2 and reopened.snapshot().profile.current_level == 8, "reopen selects the second saved recovery state")
	_check(FileAccess.get_sha256(legacy_path) == legacy_hash, "successful fallback and subsequent commits preserve the legacy source")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TEST_FAILED: " + message)
