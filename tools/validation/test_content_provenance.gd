## 通过隔离 runner 验证实际题库/策略入口，区分“本代未覆盖”和“本代声明但已损坏”。
extends SceneTree

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var directory := "user://content-provenance-test"
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		push_error("TEST_FAILED: use tools/run_validation.py for isolated userdata")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var bank: Script = load("res://products/meowdoku/gameplay/content/bank_data.gd")
	var policy: Script = load("res://products/meowdoku/gameplay/content/doku_policy.gd")
	var validator: Script = load("res://products/meowdoku/gameplay/content/doku_content_validator.gd")
	var catalog_script: Script = load("res://scripts/framework/content/content_catalog.gd")
	ContentContext.publish(null)
	var builtin: Array = bank.get_levels(4, 1)
	_check(not builtin.is_empty(), "builtin puzzle exists")
	if builtin.is_empty():
		quit(1)
		return
	_check(builtin[0]._content_provenance == {"logical_id": "doku/levels/bankdata4x4", "release": "builtin", "fallback_error": ""}, "builtin puzzle records real source")
	var overridden: Dictionary = {"1": [builtin[0].duplicate(true)]}
	_check(validator.validate("doku/levels/bankdata4x4", overridden), "sized bank matches consumer")
	_check(not validator.validate("doku/levels/bankdata5x5", overridden), "filename dimensions enforced")
	_check(not validator.validate("doku/levels/bankdata4x4", overridden["1"]), "sized bank cannot silently become array")
	_check(not validator.validate("doku/levels/bankdatasp", overridden), "special bank requires levels wrapper")
	_check(validator.validate("doku/levels/bankdatasp", {"levels": overridden["1"]}), "special bank consumer shape accepted")
	_check(not validator.validate("doku/levels/bankdataunused", overridden), "unknown bank ID rejected")
	var gc_entry: Dictionary = bank.get_gc_levels(6, 1)[0].duplicate(true)
	gc_entry.seed = 8675309
	var gc_override: Dictionary = {"levels": [gc_entry]}
	_check(validator.validate("doku/levels/bankdatagc6x6", gc_override), "GC levels wrapper matches actual consumer")
	_check(not validator.validate("doku/levels/bankdatagc6x6", {"1": [gc_entry]}), "GC cannot masquerade as rank-keyed regular bank")
	_check(not validator.validate("doku/levels/bankdatagc7x7", gc_override), "GC filename dimensions enforced")
	var without_rank: Dictionary = gc_entry.duplicate(true)
	without_rank.erase("r")
	_check(not validator.validate("doku/levels/bankdatagc6x6", {"levels": [without_rank]}), "GC requires rank used by runtime filtering")
	for invalid: Dictionary in [{"size": 12}, {"seed": {}}, {"r": true}, {"r1": []}, {"tier": {}}, {"colorMap": "bad"}, {"colorMap": [0]}, {"patternRegions": [6]}, {"_level_definition": {}}]:
		var wrong: Dictionary = gc_entry.duplicate(true)
		wrong.merge(invalid, true)
		_check(not validator.validate("doku/levels/bankdatagc6x6", {"levels": [wrong]}), "unsafe consumed metadata rejected: " + str(invalid.keys()))
	for key: String in ["01", "+1", "0"]:
		_check(not validator.validate("doku/policy", {"schema": 1, "special_levels": {key: {"source": "sp", "index": 1}}}), "special-level keys cannot collapse into another level")
	var gc_entries: Array = [_write_json(directory, "gc.json", "doku/levels/bankdatagc6x6", gc_override)]
	ContentContext.publish(catalog_script.new(directory, {"release": "gc-r1", "files": gc_entries}))
	var consumed_gc: Array = bank.get_gc_levels(6, 1)
	_check(consumed_gc.size() == 1 and int(consumed_gc[0].seed) == 8675309 and consumed_gc[0]._content_provenance.release == "gc-r1", "validated GC update reaches real BankData filtering with provenance")
	_check(bank.get_gc_ranks(6) == [1] and bank.get_gc_levels(6, 2).is_empty(), "GC replacement respects actual rank filtering")
	var entries: Array = [_write_json(directory, "bank.json", "doku/levels/bankdata4x4", overridden)]
	var catalog: RefCounted = catalog_script.new(directory, {"release": "source-r2", "files": entries})
	ContentContext.publish(catalog)
	var remote: Array = bank.get_levels(4, 1)
	_check(remote.size() == 1 and remote[0]._content_provenance.release == "source-r2", "selected remote puzzle carries actual version")
	_check(not bank.get_levels(5, 1).is_empty() and bank.get_levels(5, 1)[0]._content_provenance.release == "builtin", "uncovered bank explicitly uses builtin")
	_check(policy.provenance().release == "builtin" and ContentContext.content_error().is_empty(), "uncovered policy is ordinary builtin, not corruption")
	# 新建目录快照后损坏文件，保证并非仅从已经校验过的内存副本读取。
	var corrupted: RefCounted = catalog_script.new(directory, {"release": "broken-bank", "files": entries})
	FileAccess.open(directory.path_join("bank.json"), FileAccess.WRITE).store_string("{}")
	ContentContext.publish(corrupted)
	_check(bank.get_levels(4, 1).is_empty(), "declared corrupted bank never silently changes puzzle source")
	_check(ContentContext.content_error().get("logical_id") == "doku/levels/bankdata4x4" and ContentContext.content_error().get("release") == "broken-bank", "entry gate receives observable corruption")
	var policies: Array = [_write_json(directory, "policy.json", "doku/policy", {"schema": 1, "draft_unlock_level": 35})]
	ContentContext.publish(catalog_script.new(directory, {"release": "policy-r3", "files": policies}))
	_check(policy.draft_unlock_level() == 35 and policy.provenance().release == "policy-r3", "policy source records real override")
	_check(ContentContext.content_error().is_empty(), "new activation resets prior error")
	FileAccess.open(directory.path_join("policy.json"), FileAccess.WRITE).store_string("{}")
	ContentContext.publish(catalog_script.new(directory, {"release": "broken-policy", "files": policies}))
	_check(policy.snapshot().is_empty() and not policy.provenance().fallback_error.is_empty(), "declared corrupted policy cannot masquerade as builtin")
	_check(ContentContext.content_error().get("logical_id") == "doku/policy", "policy corruption reaches entry gate")
	ContentContext.publish(null)
	_check(policy.draft_unlock_level() == 21 and ContentContext.content_error().is_empty(), "explicit builtin activation recovers cache and error state")
	print("CONTENT_PROVENANCE_TEST checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _write_json(directory: String, filename: String, logical_id: String, value: Variant) -> Dictionary:
	var bytes := JSON.stringify(value).to_utf8_buffer()
	var path := directory.path_join(filename)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return {"id": logical_id, "path": filename, "kind": "json", "bytes": bytes.size(), "sha256": FileAccess.get_sha256(path)}


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("TEST_FAILED: " + label)
