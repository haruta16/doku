## 实际双槽文件的提交成本与宿主记录有界性；输出指标，不用桌面数据冒充真机预算。
extends SceneTree

const Files = preload("res://scripts/framework/storage/save_store.gd")
const Core = preload("res://scripts/framework/storage/local_core_store.gd")
const Host = preload("res://scripts/framework/application/round_service.gd")
const Block = preload("res://scripts/examples/block/domain/block_probe_module.gd")

var _checks: int = 0
var _failures: int = 0
var _root_path: String


func _initialize() -> void:
	var project: String = ProjectSettings.globalize_path("res://")
	if not project.contains("/doku-validation-"):
		printerr("TEST_FAILED: performance test requires the isolated runner")
		quit(2)
		return
	_root_path = project.path_join("storage_performance_fixtures")
	var measured: Array = []
	for records: int in [24, 384, 1536]:
		measured.append(_measure(records))
	var bounded: Dictionary = _bounded_round()
	var result: Dictionary = {
		"engine": Engine.get_version_info().string,
		"platform": OS.get_name(), "kind": "desktop_file_commit_measurement",
		"samples_per_size": 12, "sizes": measured, "bounded_round": bounded,
		"limitations": ["not a mobile budget", "includes encrypted double-slot scan/readback/rename", "single-process synchronous workload; no forced power loss"],
	}
	var destination: String = project.path_join("validation_artifacts")
	DirAccess.make_dir_recursive_absolute(destination)
	var file := FileAccess.open(destination.path_join("storage-performance.json"), FileAccess.WRITE)
	_check(file != null, "performance artifact can be written")
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("PERFORMANCE_RESULT=" + JSON.stringify(result))
	print("STORAGE PERFORMANCE TESTS: %d assertions, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _measure(record_count: int) -> Dictionary:
	var core: RefCounted = _store("size_%d" % record_count)
	var entries: Array = []
	for index in record_count:
		entries.append({"id": index, "label": "sample_" + str(index), "payload": "cell".repeat(128), "values": [index, 1, 2, 3, 5, 8]})
	var initial := {"counter": 0, "history": entries, "inventory": {"star": 0}, "round_services": {}}
	_check(core.open(initial).ok, "open size fixture")
	var cfg := ConfigFile.new()
	cfg.set_value("core", "state", initial)
	var encoded_bytes: int = cfg.encode_to_text().to_utf8_buffer().size()
	var snapshot_times: Array[int] = []
	var commit_times: Array[int] = []
	for index in range(15):
		var begin: int = Time.get_ticks_usec()
		var candidate: Dictionary = core.snapshot()
		var copy_us: int = Time.get_ticks_usec() - begin
		candidate.counter = index + 1
		begin = Time.get_ticks_usec()
		var result: Dictionary = core.commit(candidate, core.revision())
		var commit_us: int = Time.get_ticks_usec() - begin
		_check(result.get("ok", false), "measured commit succeeds")
		if index >= 3:
			snapshot_times.append(copy_us)
			commit_times.append(commit_us)
	var reopened: RefCounted = _store("size_%d" % record_count)
	_check(reopened.open().ok and reopened.snapshot().counter == 15, "measured writes reopen at latest revision")
	return {"record_count": record_count, "encoded_state_bytes": encoded_bytes, "snapshot_us": _distribution(snapshot_times), "commit_us": _distribution(commit_times)}


func _bounded_round() -> Dictionary:
	var core: RefCounted = _store("bounded_round")
	_check(core.open({"inventory": {"star": 0}, "round_services": {}}).ok, "open bounded round")
	var host := Host.new(core)
	host.register_module("block", Block.new())
	var pieces: Array = []
	for index in 64:
		pieces.append([[0, 0]])
	var current: Dictionary = host.start("block", "main", 1, {"size": 2, "pieces": pieces, "reward": {"star": 1}})
	_check(current.get("ok", false), "bounded round starts")
	var before: int = var_to_bytes(core.snapshot().round_services).size()
	for index in 64:
		current = host.action("block", "main", current.round_id, current.next_sequence, "place", {"row": 0, "col": index % 2})
		_check(current.get("ok", false), "bounded placement succeeds")
	var after: int = var_to_bytes(core.snapshot().round_services).size()
	var records: Dictionary = core.snapshot().round_services
	_check(records.size() == 1 and records["block/main"].last_sequence == 64, "one namespace retains only its current round")
	_check(after - before < 2048, "64 moves add one receipt rather than an unbounded request log")
	current = host.settle("block", "main", current.round_id, current.next_sequence)
	_check(current.get("ok", false) and core.snapshot().inventory.star == 1, "bounded round settles")
	for index in 12:
		var duplicate: Dictionary = host.settle("block", "main", current.round_id, current.next_sequence)
		_check(duplicate.get("duplicate", false) and core.snapshot().inventory.star == 1, "settlement retries stay bounded and idempotent")
	return {"actions": 64, "record_bytes_before": before, "record_bytes_after": after, "namespaces": records.size()}


func _store(name: String) -> RefCounted:
	var directory: String = _root_path.path_join(name)
	var files := Files.new("performance-only", directory, true, directory.path_join("a.cfg"), directory.path_join("b.cfg"), directory.path_join("flag"))
	return Core.new(files, 1)


static func _distribution(values: Array[int]) -> Dictionary:
	values.sort()
	var total: int = 0
	for value: int in values:
		total += value
	return {"p50": values[values.size() / 2], "p95": values[mini(values.size() - 1, ceili(values.size() * 0.95) - 1)], "max": values[-1], "mean": float(total) / values.size()}


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TEST_FAILED: " + description)
