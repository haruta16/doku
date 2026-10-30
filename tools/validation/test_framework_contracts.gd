## 新玩法边界故意返回坏数据；必须明确拒绝，不能污染存档或触发脚本异常。
extends SceneTree

const Files = preload("res://scripts/framework/storage/save_store.gd")
const Core = preload("res://scripts/framework/storage/local_core_store.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")

class Module extends RefCounted:
	var mode: String = "valid"

	func create_snapshot(_context: Dictionary) -> Variant:
		return _response()

	func validate_snapshot(snapshot: Dictionary) -> Variant:
		if mode == "bad_validator":
			return true
		var valid: bool = typeof(snapshot.get("value")) == TYPE_INT
		# 验证器不能通过参数别名修改待提交/正在读取的数据。
		snapshot["value"] = 999
		return "" if valid else "value must be an integer"

	func sync_runtime(_snapshot: Dictionary, _runtime: Dictionary) -> Variant:
		return _response()

	func apply_action(_snapshot: Dictionary, _kind: String, _payload: Dictionary, _context: Dictionary) -> Variant:
		return _response()

	func settle_snapshot(_snapshot: Dictionary, _payload: Dictionary) -> Variant:
		return _response()

	func _response() -> Variant:
		match mode:
			"not_dictionary": return []
			"missing_ok": return {"snapshot": {"value": 1}}
			"bad_ok": return {"ok": 1, "snapshot": {"value": 1}}
			"missing_snapshot": return {"ok": true}
			"invalid_snapshot": return {"ok": true, "snapshot": {"value": "wrong"}}
			"bad_failure": return {"ok": false}
			"bad_result": return {"ok": true, "snapshot": {"value": 1}, "result": 3}
			"bad_changes": return {"ok": true, "snapshot": {"value": 1}, "changes": true}
			"bad_delta": return {"ok": true, "snapshot": {"value": 1}, "inventory_delta": []}
		return {"ok": true, "snapshot": {"value": 1}, "result": {"value": 1}, "inventory_delta": {"coin": 1}}

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		printerr("TEST_FAILED: use the isolated validation runner")
		quit(2)
		return
	var directory: String = "user://framework_contracts"
	var files := Files.new("framework-test", directory, true, directory + "/a.cfg", directory + "/b.cfg", directory + "/flag")
	var core := Core.new(files, 1)
	_check(core.open({"inventory": {"coin": 0}, "round_services": {}}).ok, "store opens")
	var module := Module.new()
	var host := Host.new(core)
	_check(host.register_module("probe", module), "module registers")
	for mode: String in ["not_dictionary", "missing_ok", "bad_ok", "missing_snapshot", "invalid_snapshot", "bad_failure", "bad_result", "bad_changes", "bad_delta", "bad_validator"]:
		module.mode = mode
		var rejected: Dictionary = host.start("probe", "main", 1, {})
		_check(rejected.get("error") == "invalid_module_result" and core.revision() == 0, "invalid start contract rejected: " + mode)
	module.mode = "valid"
	var opened: Dictionary = host.start("probe", "main", 1, {})
	_check(opened.ok and opened.snapshot.value == 1, "validator mutation cannot change initial snapshot")
	var baseline: Dictionary = core.snapshot()
	_check(host.action("probe", "main", opened.round_id, 1, "__settle").error == "invalid_action_kind", "action cannot impersonate settlement")
	for mode: String in ["not_dictionary", "missing_snapshot", "invalid_snapshot", "bad_result", "bad_changes", "bad_delta"]:
		module.mode = mode
		_check(host.action("probe", "main", opened.round_id, 1, "move").get("error") == "invalid_module_result", "bad action contract rejected: " + mode)
		_check(core.snapshot() == baseline, "bad action leaves state unchanged: " + mode)
		_check(host.action("probe", "main", opened.round_id, 1, "move", {}, {"value": 0}).get("error") == "invalid_module_result", "bad sync contract rejected: " + mode)
	module.mode = "valid"
	var moved: Dictionary = host.action("probe", "main", opened.round_id, 1, "move")
	_check(moved.ok and moved.snapshot.value == 1 and core.snapshot().inventory.coin == 1, "valid module action commits once")
	_check(host.action("probe", "main", opened.round_id, 1, "move").duplicate and core.snapshot().inventory.coin == 1, "valid receipt remains idempotent")
	baseline = core.snapshot()
	for field: String in ["module_id", "mode_id", "snapshot", "last_receipt", "start_context", "settlement", "start_sequence", "last_sequence", "round_id", "status"]:
		var damaged: Dictionary = baseline.duplicate(true)
		damaged.round_services["probe/main"][field] = false
		_check(core.commit(damaged, core.revision()).ok, "prepare malformed record: " + field)
		_check(host.resume("probe", "main").get("error") == "invalid_record", "resume rejects malformed metadata: " + field)
		_check(core.commit(baseline, core.revision()).ok, "restore valid fixture: " + field)
	var reset: Dictionary = baseline.duplicate(true)
	reset.round_services["probe/main"].status = "reset"
	reset.round_services["probe/main"].last_receipt = {}
	_check(core.commit(reset, core.revision()).ok, "prepare reset record")
	_check(host.start("probe", "main", 1, {}).get("error") == "round_inactive", "reset cannot reuse start receipt")
	_check(host.action("probe", "main", opened.round_id, 1, "move").get("error") == "round_inactive", "reset cannot replay action receipt")
	_check(host.start("probe", "main", 2, {}).ok, "new round can follow reset")
	var invalid_container: Dictionary = core.snapshot()
	invalid_container.round_services = []
	_check(core.commit(invalid_container, core.revision()).ok, "prepare invalid container")
	_check(host.resume("probe", "main").get("error") == "invalid_store_state", "bad container returns explicit error")
	_check(Host.new(RefCounted.new()).start("x", "y", 1, {}).get("error") == "invalid_store_port", "invalid port is rejected")
	print("FRAMEWORK CONTRACT TESTS: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + description)
