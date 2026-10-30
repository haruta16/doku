extends SceneTree

var _checks: int = 0

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	var policy_script: Script = load("res://products/meowdoku/gameplay/content/doku_policy.gd")
	var validator: Script = load("res://products/meowdoku/gameplay/content/doku_content_validator.gd")
	var context: Script = load("res://scripts/framework/content/content_context.gd")
	var bank: Script = load("res://products/meowdoku/gameplay/content/bank_data.gd")
	var catalog_script: Script = load("res://scripts/framework/content/content_catalog.gd")
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/validation/fixtures/doku_size_baseline.json"))
	for level in range(1, 301):
		_check(policy_script.cycle_size(-1, level) == int(expected.base[level - 1]), "base size %d" % level)
		_check(policy_script.cycle_size(-2, level) == int(expected.j[level - 1]), "J size %d" % level)
		for group in range(2, 9):
			_check(policy_script.cycle_size(group, level) == int(expected.groups[str(group)][level - 1]), "size group %d level %d" % [group, level])
	_check(validator.validate("doku/policy", policy_script.snapshot()), "builtin policy schema")
	_check(not validator.validate("doku/policy", {"schema": 1, "size_cycles": {"2": [{"from": 1, "sizes": [0]}]}}), "reject invalid size")
	_check(not validator.validate("doku/levels/bankdata4x4", {"1": [{"regionMap": [[], [], [], []], "solution": [0, 1, 2, 3]}]}), "reject malformed rows safely")
	_check(not validator.validate("doku/levels/bankdata4x4", {"1": [{"regionMap": [[], [], [], []], "solution": "bad"}]}), "reject malformed solution safely")
	var original: Array = bank.get_levels(4, 1).duplicate(true)
	_check(not original.is_empty(), "builtin bank readable")
	var previous_policy: Dictionary = policy_script.snapshot()
	var directory: String = "user://content-integration-test"
	if directory.is_empty() or DirAccess.make_dir_recursive_absolute(directory) != OK:
		quit(1)
		return
	var data: Dictionary = {"schema": 1, "draft_unlock_level": 35, "size_cycles": {"2": [{"from": 1, "sizes": [5]}]}}
	var bank_override: Dictionary = {"1": [original[0].duplicate(true)]}
	bank_override["1"][0]["seed"] = 20261026
	_check(validator.validate("doku/levels/bankdata4x4", bank_override), "valid override bank")
	var entries: Array = []
	for item: Dictionary in [{"id": "doku/policy", "name": "policy.json", "value": data}, {"id": "doku/levels/bankdata4x4", "name": "bank.json", "value": bank_override}]:
		var path: String = directory.path_join(item.name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		var bytes: PackedByteArray = JSON.stringify(item.value).to_utf8_buffer()
		file.store_buffer(bytes)
		file.close()
		entries.append({"id": item.id, "path": item.name, "kind": "json", "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)})
	var catalog: RefCounted = catalog_script.new(directory, {"release": "integration-r2", "files": entries})
	context.publish(catalog)
	_check(policy_script.cycle_size(2, 100) == 5, "new policy used")
	_check(policy_script.cycle_size(-1, 100) == int(expected.base[99]), "partial cycle override preserves unrelated curves")
	_check(policy_script.draft_unlock_level() == 35, "new unlock policy used")
	_check(int(previous_policy.draft_unlock_level) == 21, "old round policy unchanged")
	var updated: Array = bank.get_levels(4, 1)
	_check(updated.size() == 1 and int(updated[0].seed) == 20261026, "existing BankData reads new catalog")
	_check(int(original[0].seed) != 20261026, "old resolved puzzle unchanged")
	context.publish(null)
	_check(bank.get_levels(4, 1).size() == original.size(), "builtin fallback rebuilds cache")
	_check(policy_script.draft_unlock_level() == 21, "builtin policy restored")
	for name: String in ["policy.json", "bank.json"]:
		DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	if _failures.is_empty():
		print("PASS: 2700 baseline size decisions, content schema, real bank/policy activation and old-round isolation checks=%d failures=0" % _checks)
		quit(0)
	else:
		for failure: String in _failures:
			push_error("TEST_FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
