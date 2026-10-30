## 在无 Autoload 的临时项目运行；-- --test-root=/private/tmp/... 指定隔离目录。
extends SceneTree

const FileStore = preload("res://scripts/framework/storage/save_store.gd")
const CoreStore = preload("res://scripts/framework/storage/local_core_store.gd")
const PASSWORD := "storage-test-password"

var _test_root: String
var _assertions: int = 0
var _failures: int = 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test-root="):
			_test_root = argument.trim_prefix("--test-root=")
	var isolated_project := ProjectSettings.globalize_path("res://")
	var from_validation_runner := isolated_project.contains("/doku-validation-")
	if _test_root.is_empty() and from_validation_runner:
		_test_root = isolated_project.path_join("storage_test_fixtures")
		DirAccess.make_dir_recursive_absolute(_test_root)
	if not (from_validation_runner or _test_root.begins_with("/private/tmp/") or _test_root.begins_with("/tmp/")):
		printerr("test_storage 只允许显式指定 /private/tmp 或 /tmp 中的隔离目录")
		quit(2)
		return
	if not DirAccess.dir_exists_absolute(_test_root):
		printerr("请由隔离测试运行器预先建立空 test-root")
		quit(2)
		return
	if not DirAccess.get_files_at(_test_root).is_empty() or not DirAccess.get_directories_at(_test_root).is_empty():
		printerr("test-root 必须为空；测试不会清空现有目录")
		quit(2)
		return
	_run()
	print("STORAGE TESTS: %d assertions, %d failures" % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _run() -> void:
	_test_revisions_and_flags()
	_test_legacy()
	_test_failures_and_recovery()
	_test_unsupported_and_conflict()
	_test_core_store()
	_test_core_refuses_unknown_data()
	_test_last_result()
	_test_float_serialization_verification()


func _test_last_result() -> void:
	var store := _store("last_result")
	_check(store.commit_config(_cfg("baseline"), 0).ok, "诊断测试基线提交")
	var invalid: Dictionary = store.commit_config(null)
	_check(invalid.status == "invalid" and store.last_result() == invalid, "空配置的早退更新最近结果")
	var conflict: Dictionary = store.commit_config(_cfg("stale"), 0)
	_check(conflict.status == "conflict" and store.last_result() == conflict, "revision 冲突的早退更新最近结果")
	var nested: Dictionary = {}
	store.set_fault_injector_for_tests(func(phase: String) -> bool:
		if phase == "before_replace":
			nested["result"] = store.commit_config(_cfg("nested"))
			nested["last"] = store.last_result()
		return false)
	var committed: Dictionary = store.commit_config(_cfg("outer"), 1)
	_check(nested.result.status == "busy" and nested.last == nested.result, "重入拒绝在返回时更新最近结果")
	_check(committed.ok and store.last_result() == committed, "外层稍后完成时发布自己的最终结果")
	store.set_fault_injector_for_tests(Callable())
	var loaded: Dictionary = store.load_result()
	_check(loaded.status == "loaded" and store.last_result() == loaded, "公开读取更新最近操作结果")
	var last: Dictionary = store.last_result()
	last["status"] = "mutated_outside"
	_check(store.last_result().status == "loaded", "诊断字典不暴露内部状态")
	var exhausted := _store("last_result_exhausted")
	var cfg := _cfg("exhausted")
	cfg.set_value("__save_store", "format_version", 1)
	cfg.set_value("__save_store", "revision", 9223372036854775807)
	_write_cfg(_path("last_result_exhausted", "a.cfg"), cfg)
	_check(exhausted.load_result().ok, "准备合法的最大 revision")
	var rejected: Dictionary = exhausted.commit_config(_cfg("overflow"))
	_check(rejected.status == "invalid" and exhausted.last_result() == rejected, "revision 耗尽的早退更新最近结果")


func _test_revisions_and_flags() -> void:
	var store := _store("revisions")
	var missing: Dictionary = store.load_result()
	_check(missing.status == "missing", "空目录明确返回 missing")
	_check(not missing.ok and missing.error == "missing" and missing.detail == "", "缺档失败使用机器码，空说明不影响分支")
	var original := _cfg("first")
	_check(store.save_config(original), "首次保存成功")
	_check(not original.has_section("__save_store"), "写入不污染调用方 ConfigFile")
	_check(store.load_result().revision == 1, "首次 revision 为 1")
	_check(store.save_config(_cfg("second")), "第二次保存成功")
	_write_text(_path("revisions", "flag"), "A")
	_check(_marker(_store("revisions")) == "second", "过期 flag 不覆盖更新 revision")
	_write_text(_path("revisions", "flag"), "broken")
	_check(_marker(_store("revisions")) == "second", "损坏 flag 不影响读取")
	DirAccess.remove_absolute(_path("revisions", "flag"))
	_check(_marker(_store("revisions")) == "second", "缺失 flag 不影响读取")
	store.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "flag_write")
	var result: Dictionary = store.commit_config(_cfg("third"), 2)
	_check(result.ok and not result.flag_updated, "flag 失败时已提交数据仍明确成功")
	_check(_marker(_store("revisions")) == "third", "新实例恢复 flag 失败后的最新数据")
	_check(store.commit_config(_cfg("stale"), 1).status == "conflict", "文件层拒绝过期 revision")
	_check(_marker(store) == "third", "过期提交不改变持久数据")


func _test_legacy() -> void:
	var store := _store("legacy_slots")
	_write_cfg(_path("legacy_slots", "a.cfg"), _cfg("old_a"))
	_write_cfg(_path("legacy_slots", "b.cfg"), _cfg("old_b"))
	_write_text(_path("legacy_slots", "flag"), "B")
	_check(_marker(store) == "old_b", "旧无 revision 双槽沿用 flag")
	_check(store.save_config(_cfg("upgraded")), "旧双槽可升级到 revision 协议")
	_check(store.load_result().revision == 1, "旧双槽升级 revision 从 1 开始")
	_write_text(_path("legacy_slots", "flag"), "B")
	_check(_marker(store) == "upgraded", "新协议优先于旧无 revision 槽")
	var fallback := _store("legacy_file", true)
	_write_cfg(_path("legacy_file", "legacy.cfg"), _cfg("old_file"))
	_check(_marker(fallback) == "old_file", "保留旧单文件导入兼容入口")
	_check(fallback.load_result().status == "recovered_legacy", "旧文件来源可辨认")
	var single := FileStore.new(PASSWORD, _path("single", ""), false, _path("single", "one.cfg"))
	_check(single.save_config(_cfg("one")), "旧单槽 API 仍可保存")
	_check(_marker(single) == "one", "旧单槽 API 仍可读取")
	single.remove()
	_check(single.load_result().status == "missing", "仅单槽允许旧 remove 行为")


func _test_failures_and_recovery() -> void:
	for phase in ["before_write", "after_temp_write", "before_replace"]:
		var case_name: String = "failure_" + phase
		var store := _store(case_name)
		_check(store.save_config(_cfg("previous")), phase + " 基线提交")
		store.set_fault_injector_for_tests(func(point: String) -> bool: return point == phase)
		_check(not store.save_config(_cfg("not_committed")), phase + " 明确报告失败")
		var failure: Dictionary = store.last_result()
		_check(failure.error == "write_failed" and failure.status == "write_failed" and not failure.detail.is_empty(), phase + " 保存失败保留机器码及诊断说明")
		_check(_marker(_store(case_name)) == "previous", phase + " 新实例仍读取完整旧提交")
		store.set_fault_injector_for_tests(Callable())
		_check(store.save_config(_cfg("retry")), phase + " 可重试且覆盖孤立临时文件")
		_check(store.load_result().revision == 2, phase + " 失败不消耗提交 revision")
	var recover := _store("recover")
	_check(recover.save_config(_cfg("valid_backup")), "恢复测试首次提交")
	_check(recover.save_config(_cfg("bad_latest")), "恢复测试第二次提交")
	_write_text(_path("recover", "b.cfg"), "broken encrypted data")
	_check(recover.load_result().status == "recovered", "坏最新槽明确报告恢复")
	_check(_marker(recover) == "valid_backup", "坏最新槽退完整备份")
	_check(recover.save_config(_cfg("repaired")), "可替换损坏槽恢复写入")
	var corrupt := _store("corrupt")
	_write_text(_path("corrupt", "a.cfg"), "broken encrypted data")
	_check(corrupt.load_result().status == "corrupt", "全坏存档不冒充 missing")
	var before := FileAccess.get_sha256(_path("corrupt", "a.cfg"))
	_check(not corrupt.save_config(_cfg("must_not_replace")), "全坏存档禁止默认值覆盖")
	_check(FileAccess.get_sha256(_path("corrupt", "a.cfg")) == before, "坏档保留以便显式恢复")


func _test_unsupported_and_conflict() -> void:
	var store := _store("future_format")
	_check(store.save_config(_cfg("known")), "未来格式测试基线")
	var future := _cfg("future")
	future.set_value("__save_store", "format_version", 99)
	future.set_value("__save_store", "revision", 2)
	_write_cfg(_path("future_format", "b.cfg"), future)
	_check(store.load_result().status == "unsupported", "未来存储格式不回退旧数据")
	_check(not store.save_config(_cfg("overwrite")), "未来格式禁止旧程序覆盖")
	var conflict := _store("equal_revision")
	for name in ["a.cfg", "b.cfg"]:
		var cfg := _cfg(name)
		cfg.set_value("__save_store", "format_version", 1)
		cfg.set_value("__save_store", "revision", 2)
		_write_cfg(_path("equal_revision", name), cfg)
	_check(conflict.load_result().status == "conflict", "相同 revision 不同内容拒绝任意挑选")
	_check(not conflict.save_config(_cfg("overwrite")), "冲突数据禁止覆盖")


func _test_core_store() -> void:
	var file_store := _store("core")
	var core := CoreStore.new(file_store, 1, _validate_inventory)
	var initial := {"inventory": {"hint": 2}, "round": {"moves": []}}
	var opened: Dictionary = core.open(initial)
	_check(opened.ok, "核心状态可在真正缺档时初始化")
	_check(opened.error == "" and opened.status == "missing", "成功初始化可携带 missing 读取状态，不能按 status 判断成败")
	initial.inventory.hint = 99
	_check(core.snapshot().inventory.hint == 2, "初始化深拷贝")
	_check(file_store.load_result().status == "missing", "open 不自动写入默认值")
	var candidate := core.snapshot()
	candidate.inventory.hint = 1
	candidate.round.moves.append("used_hint")
	_check(core.commit(candidate, 0).ok, "库存及玩法结果一起提交")
	candidate.inventory.hint = 80
	candidate.round.moves.append("outside_mutation")
	_check(core.snapshot().inventory.hint == 1 and core.snapshot().round.moves.size() == 1, "提交后候选别名不能改变内部状态")
	var detached := core.snapshot()
	detached.inventory.hint = 70
	_check(core.snapshot().inventory.hint == 1, "读快照不暴露内部引用")
	_check(core.commit(core.snapshot(), 0).status == "conflict", "核心状态拒绝旧 revision")
	var invalid := core.snapshot()
	invalid.inventory.hint = -1
	var invalid_result: Dictionary = core.commit(invalid, 1)
	_check(invalid_result.status == "invalid_state", "业务验证器拒绝负库存")
	_check(invalid_result.error == "invalid_state" and invalid_result.detail == "hint 不能为负", "业务验证失败将诊断与机器码分开")
	file_store.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	var failing := core.snapshot()
	failing.inventory.hint = 0
	var failure: Dictionary = core.commit(failing, 1)
	_check(not failure.ok, "核心业务提交暴露文件失败")
	_check(failure.error == "write_failed" and failure.detail == file_store.last_result().detail, "核心层完整传递文件失败说明")
	_check(core.revision() == 1 and core.snapshot().inventory.hint == 1, "失败不发布候选状态或消耗 revision")
	file_store.set_fault_injector_for_tests(Callable())
	var reopened := CoreStore.new(_store("core"), 1, _validate_inventory)
	_check(reopened.open().ok, "新实例恢复核心状态")
	_check(reopened.snapshot().inventory.hint == 1 and reopened.snapshot().round.moves.size() == 1, "恢复看到完整旧业务提交")
	_check(reopened.commit(reopened.snapshot(), 1).ok, "新实例可以继续提交")
	_check(core.commit(core.snapshot(), 1).status == "conflict", "另一持有者的旧 revision 也受文件层保护")
	var object_candidate := reopened.snapshot()
	object_candidate["object"] = RefCounted.new()
	_check(reopened.commit(object_candidate, 2).status == "invalid_state", "不能把运行时对象塞进存档")


func _test_core_refuses_unknown_data() -> void:
	var file_store := _store("schema")
	var cfg := ConfigFile.new()
	cfg.set_value("core", "schema_version", 8)
	cfg.set_value("core", "state", {"future": true})
	_check(file_store.save_config(cfg), "建立未来业务 schema 样本")
	var core := CoreStore.new(file_store, 1)
	_check(core.open({"inventory": {"hint": 0}}).status == "schema_mismatch", "未知业务 schema 不当作新档")
	_check(not core.is_open(), "不兼容 schema 不发布状态")
	_check(core.commit({}, 0).status == "not_open", "未知 schema 后无法覆盖存档")
	_check(file_store.load_result().revision == 1, "拒绝后持久 revision 保持原值")
	var corrupt := _store("core_corrupt")
	_write_text(_path("core_corrupt", "a.cfg"), "corrupt")
	var corrupt_core := CoreStore.new(corrupt, 1)
	_check(corrupt_core.open({"inventory": {"hint": 0}}).status == "corrupt", "损坏业务存档不能初始化默认值")


func _validate_inventory(state: Dictionary) -> String:
	if not state.get("inventory") is Dictionary:
		return "缺少 inventory"
	if int(state.inventory.get("hint", -1)) < 0:
		return "hint 不能为负"
	return ""


func _store(case_name: String, legacy: bool = false) -> RefCounted:
	var dir := _path(case_name, "")
	DirAccess.make_dir_recursive_absolute(dir)
	return FileStore.new(PASSWORD, dir, true, dir + "a.cfg", dir + "b.cfg", dir + "flag", dir + "legacy.cfg" if legacy else "")


func _path(case_name: String, name: String) -> String:
	return _test_root.path_join(case_name).path_join(name) + ("/" if name.is_empty() else "")


func _cfg(marker: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value("data", "marker", marker)
	return cfg


func _marker(store: RefCounted) -> String:
	var cfg: ConfigFile = store.load_config()
	return str(cfg.get_value("data", "marker", "")) if cfg != null else ""


func _write_cfg(path: String, cfg: ConfigFile) -> void:
	_check(cfg.save_encrypted_pass(path, PASSWORD) == OK, "写入隔离样本 " + path.get_file())


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "打开隔离样本 " + path.get_file())
	if file != null:
		file.store_string(value)


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		printerr("[FAIL] " + label)


## Godot parse 后浮点末位可重编码为另一字符串；仍须精确校验原文且拒绝实际篡改。
func _test_float_serialization_verification() -> void:
	for plain: bool in [false, true]:
		var dir: String = _test_root.path_join("float-plain" if plain else "float-encrypted")
		DirAccess.make_dir_recursive_absolute(dir)
		var path: String = dir.path_join("state.cfg")
		var store: RefCounted = FileStore.new(PASSWORD, dir, false, path, "", "", "", plain)
		var cfg := ConfigFile.new()
		cfg.set_value("state", "in_game_sec", 2.0080965555555514)
		_check(store.commit_config(cfg, 0).ok, "浮点计时可提交，不以重编码末位变化误判损坏")
		var loaded: Dictionary = store.load_result()
		_check(loaded.ok and is_equal_approx(float(loaded.config.get_value("state", "in_game_sec")), 2.0080965555555514), "回读配置可解析并保留计时精度")
		var original: String = FileAccess.get_sha256(path)
		store.set_fault_injector_for_tests(func(phase: String) -> bool:
			if phase == "after_temp_write":
				var altered := ConfigFile.new()
				if plain:
					altered.load(path + ".tmp")
				else:
					altered.load_encrypted_pass(path + ".tmp", PASSWORD)
				altered.set_value("state", "in_game_sec", 10.0)
				if plain:
					altered.save(path + ".tmp")
				else:
					altered.save_encrypted_pass(path + ".tmp", PASSWORD)
			return false)
		var rejected: Dictionary = store.commit_config(cfg, 1)
		_check(not rejected.ok and rejected.detail == "临时存档回读不一致", "完整且可解析但内容已变的临时配置仍被逐字节拒绝")
		_check(FileAccess.get_sha256(path) == original and store.load_result().revision == 1, "拒绝篡改不发布 revision 或覆盖已有槽")
