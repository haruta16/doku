## 通用事务端口的反证：候选允许局部暂存，但失败不能改变权威状态或妨碍下一次合法请求。
extends SceneTree

const Files = preload("res://scripts/framework/storage/save_store.gd")
const Core = preload("res://scripts/framework/storage/local_core_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")
const MAX_VALUE: int = 9223372036854775807

class CandidateModule extends RefCounted:
	var mode: String = "valid"
	var retained: Dictionary = {}

	func create_snapshot(_context: Dictionary) -> Dictionary:
		retained = {"value": 0}
		return {"ok": true, "snapshot": retained}

	func validate_snapshot(snapshot: Dictionary) -> String:
		return "" if typeof(snapshot.get("value")) == TYPE_INT else "invalid value"

	func sync_runtime(snapshot: Dictionary, _runtime: Dictionary) -> Dictionary:
		return {"ok": true, "snapshot": snapshot}

	func apply_action(snapshot: Dictionary, _kind: String, _payload: Dictionary, _context: Dictionary) -> Dictionary:
		snapshot.value += 1
		retained = snapshot
		if mode == "reject":
			return {"ok": false, "error": "rejected_after_candidate_edit"}
		return {"ok": true, "snapshot": snapshot, "inventory_delta": {"coin": 1, "ticket": -1 if mode == "insufficient" else 1}}

	func settle_snapshot(snapshot: Dictionary, _payload: Dictionary) -> Dictionary:
		return {"ok": true, "snapshot": snapshot, "inventory_delta": {"coin": 1}}

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use the isolated validation runner")
		quit(2)
		return
	for kind: String in ["multiple_items", "repeated_kind", "doubled"]:
		_test_claim_failure(kind)
	_test_economy_notification()
	_test_round_candidate()
	print("FRAMEWORK TRANSACTION BOUNDARY TESTS: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_claim_failure(kind: String) -> void:
	var fixture: Dictionary = _store(kind)
	var core: RefCounted = fixture.core
	var initial: Dictionary = _initial()
	initial.inventory.ticket = MAX_VALUE - 1 if kind != "multiple_items" else MAX_VALUE
	_check(core.open(initial).ok, kind + ": open real core")
	var economy := Economy.new(core)
	var items: Array = [{"kind": "coin", "count": 1}, {"kind": "ticket", "count": 1}]
	if kind == "repeated_kind":
		items.append({"kind": "ticket", "count": 1})
	var registered: Dictionary = economy.register_award(items, 0, "test", "bonus", "stable-award")
	_check(registered.ok, kind + ": register durable pending reward")
	if kind == "doubled":
		_check(economy.double_award(registered.uid).ok, "double entitlement is persisted")
	var before: Dictionary = core.snapshot()
	var revision: int = core.revision()
	for retry in 2:
		_check(economy.claim_award(registered.uid).get("error") == "overflow", kind + ": overflowing claim rejects on retry " + str(retry))
		_check(core.snapshot() == before and core.revision() == revision, kind + ": partial candidate credits and reward removal never publish")
	var candidate: Dictionary = core.snapshot()
	candidate.inventory.ticket = 0
	_check(core.commit(candidate, core.revision()).ok, kind + ": inventory becomes available in a later transaction")
	before = core.snapshot()
	fixture.files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not economy.claim_award(registered.uid).ok and core.snapshot() == before, kind + ": write failure also preserves full entitlement")
	fixture.files.set_fault_injector_for_tests(Callable())
	var claimed: Dictionary = economy.claim_award(registered.uid)
	var copies: int = 2 if kind == "doubled" else 1
	_check(claimed.ok and core.snapshot().inventory == {"coin": copies, "ticket": 2 if kind != "multiple_items" else 1}, kind + ": the full reward succeeds once after recovery")
	_check(economy.claim_award(registered.uid).get("status") == "already_applied", kind + ": committed receipt remains idempotent")
	var reopened: Dictionary = _store(kind)
	_check(reopened.core.open().ok and reopened.core.snapshot() == core.snapshot(), kind + ": restart sees the complete transaction")
	_check(Economy.new(reopened.core).claim_award(registered.uid).get("status") == "already_applied", kind + ": restart cannot pay a second time")


func _test_economy_notification() -> void:
	var fixture: Dictionary = _store("notification")
	var core: RefCounted = fixture.core
	_check(core.open(_initial()).ok, "notification: core opens")
	var economy := Economy.new(core)
	var nested: Dictionary = {}
	core.committed.connect(func(_revision: int) -> void:
		nested.registered = economy.register_award([{"kind": "coin", "count": 2}], 0, "second", "", "second")
	, CONNECT_ONE_SHOT)
	var registered: Dictionary = economy.register_award([{"kind": "coin", "count": 1}], 0, "first", "", "first")
	_check(registered.ok and nested.registered.ok and registered.uid == 1 and nested.registered.uid == 2, "nested registration preserves each request's own reward identity")
	core.committed.connect(func(_revision: int) -> void:
		nested.repeat = economy.claim_award(registered.uid)
		nested.claimed = economy.claim_award(nested.registered.uid)
	, CONNECT_ONE_SHOT)
	var claimed: Dictionary = economy.claim_award(registered.uid)
	_check(claimed.ok and claimed.uid == 1 and claimed.grants.size() == 1 and claimed.grants[0].count == 1, "outer claim retains its own durable grant")
	_check(nested.repeat.get("status") == "already_applied" and nested.claimed.ok and core.snapshot().inventory.coin == 3, "synchronous repeat and another reward neither lose nor duplicate credit")
	var next: Dictionary = economy.register_award([{"kind": "coin", "count": 1}], 0, "third")
	_check(next.ok and next.uid == 3 and economy.claim_award(next.uid).ok and core.snapshot().inventory.coin == 4, "next ordinary registration and claim work after nested notifications")


func _test_round_candidate() -> void:
	var fixture: Dictionary = _store("module-candidate")
	var core: RefCounted = fixture.core
	_check(core.open(_initial()).ok, "module candidate: core opens")
	var host := Host.new(core)
	var module := CandidateModule.new()
	_check(host.register_module("probe", module), "candidate module registers")
	var started: Dictionary = host.start("probe", "main", 1, {})
	module.retained.value = 900
	_check(started.ok and host.resume("probe", "main").snapshot.value == 0, "module-retained creation snapshot cannot change the stored round")
	var before: Dictionary = core.snapshot()
	for mode: String in ["reject", "insufficient"]:
		module.mode = mode
		var result: Dictionary = host.action("probe", "main", started.round_id, 1, "move")
		_check(not result.ok and core.snapshot() == before, mode + ": failed module preparation or partial inventory delta does not publish")
	module.mode = "valid"
	fixture.files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(host.action("probe", "main", started.round_id, 1, "move").get("error") == "commit_failed" and core.snapshot() == before, "failed host write preserves both module and inventory")
	fixture.files.set_fault_injector_for_tests(Callable())
	var moved: Dictionary = host.action("probe", "main", started.round_id, 1, "move")
	_check(moved.ok and moved.snapshot.value == 1 and core.snapshot().inventory == {"coin": 1, "ticket": 1}, "same sequence succeeds once after all failure modes")
	module.retained.value = 901
	moved.snapshot.value = 902
	_check(host.resume("probe", "main").snapshot.value == 1, "module and caller retained result aliases cannot edit committed state")
	_check(host.action("probe", "main", started.round_id, 1, "move").get("duplicate", false) and core.snapshot().inventory.coin == 1, "duplicate receipt does not repeat any inventory delta")
	var settled: Dictionary = host.settle("probe", "main", started.round_id, 2)
	_check(settled.ok and core.snapshot().inventory.coin == 2, "round can settle after failed and retried action")
	var reopened: Dictionary = _store("module-candidate")
	_check(reopened.core.open().ok and reopened.core.snapshot() == core.snapshot(), "module, last receipt, terminal state and inventory recover together")


func _store(name: String) -> Dictionary:
	var directory: String = "user://framework_transaction_boundaries/" + name
	var files := Files.new("framework-boundary", directory, true, directory.path_join("a.cfg"), directory.path_join("b.cfg"), directory.path_join("flag"))
	return {"files": files, "core": Core.new(files, 1)}


static func _initial() -> Dictionary:
	return {"inventory": {"coin": 0, "ticket": 0}, "round_services": {}, "award_sequence": 0, "pending_awards": [], "claims": {}}


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + description)
