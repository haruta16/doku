## 存档文件层：新档按槽内 revision 恢复；flag 只参与无 revision 旧档的选择。
## 保证完整提交的恢复，不承诺系统掉电持久性，也不支持多个进程同时写同一路径。
class_name SaveStore
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
const _META := "__save_store" # 文件层自己的节名；保存时重建，调用方不能指定 revision。
const _FORMAT_VERSION: int = 1 # 文件封装版本；独立于 core/schema_version 的产品数据结构。

var _plain: bool = false # 仅显式工具入口使用明文；默认读写仍走密码加密。
var _password: String # 加解密口令，由宿主注入；本类不选择或存储账号凭证。
var _dir: String # 临时文件及目标槽所在目录，写入前确保存在。
var _dual_slot: bool # 双槽时交替写 A/B；单槽用于兼容文件或工具。
var _path_a: String # A 槽路径；单槽模式的唯一目标文件。
var _path_b: String # 双槽模式下的 B 槽路径。
var _flag_path: String # 兼容旧档的 A/B 指示文件；新档恢复以槽内 revision 为准。
var _legacy_path: String # 可选旧单文件兜底；不负责拆解产品的多个旧业务文件。
var _writing: bool = false # 一次同步写入期间的重入锁，不防护另一个进程。
var _fault_injector: Callable # 测试故障入口，接收阶段名并返回是否模拟失败。
var _last_result: Dictionary = {} # 最近一次公开 load/commit 结果；内部扫描不会覆盖它。


## 保留旧调用的构造参数；路径全部由调用方注入。
func _init(
	password: String,
	dir: String,
	dual_slot: bool,
	path_a: String,
	path_b: String = "",
	flag_path: String = "",
	legacy_path: String = "",
	plain: bool = false
) -> void:
	_plain = plain
	_password = password
	_dir = dir
	_dual_slot = dual_slot
	_path_a = path_a
	_path_b = path_b
	_flag_path = flag_path
	_legacy_path = legacy_path


## 兼容旧 API；新业务应使用 commit_config 的明确结果。
func save_config(cfg: ConfigFile) -> bool:
	return bool(commit_config(cfg).get("ok", false))


## 旧接口只返回读取到的 ConfigFile 或 null；需要区分缺失、损坏、版本不支持时用 load_result。
func load_config() -> ConfigFile:
	return load_result().get("config") as ConfigFile


## missing 与 corrupt/unsupported 明确区分，后两者绝不能当作新用户覆盖。
func load_result(slot_validator: Callable = Callable()) -> Dictionary:
	_last_result = _scan_slots(slot_validator)
	return _last_result.duplicate()


## 最近完成的公开读取/提交结果；内部槽扫描不单独发布诊断。
func last_result() -> Dictionary:
	return _last_result.duplicate()


## expected_revision < 0 仅供旧 API；新业务必须带上读到的 revision。
func commit_config(cfg: ConfigFile, expected_revision: int = -1, slot_validator: Callable = Callable()) -> Dictionary:
	_last_result = _commit_config(cfg, expected_revision, slot_validator)
	return _last_result.duplicate()


## 提交的内部流程：扫描当前槽 → 校验读取版本 → 写目标临时文件 → 原子替换；双槽时选择另一槽。
## 返回明确的提交结果；替换已经成功时，兼容 flag 写失败不回滚已完成的提交。
func _commit_config(cfg: ConfigFile, expected_revision: int, slot_validator: Callable) -> Dictionary:
	if _writing:
		return _failure("busy", "存档提交尚未结束")
	if cfg == null:
		return _failure("invalid", "待保存配置为空")
	_writing = true
	# 提交前重新读当前槽，供 expected_revision 核对与下一版本发号；旧接口省略预期版本时不检查过期读取。
	var current := _scan_slots(slot_validator)
	if not bool(current.get("ok", false)) and current.get("status") != "missing":
		_writing = false
		return current
	var revision: int = int(current.get("revision", 0))
	if expected_revision >= 0 and expected_revision != revision:
		_writing = false
		return _failure("conflict", "存档 revision 已改变", revision)
	if revision == 9223372036854775807:
		_writing = false
		return _failure("invalid", "存档 revision 已耗尽", revision)
	# 版本只由文件层分配；调用方配置里的旧 __save_store 元数据会被剔除。
	var candidate := _copy_config(cfg)
	candidate.set_value(_META, "format_version", _FORMAT_VERSION)
	candidate.set_value(_META, "revision", revision + 1)
	var target := "A"
	# 双槽写非当前槽，替换前仍保留上一份可恢复的完整提交。
	if _dual_slot and current.get("slot", "") == "A":
		target = "B"
	var path: String = _path_b if target == "B" else _path_a
	var write_result := _atomic_write(candidate, path)
	if not bool(write_result.get("ok", false)):
		write_result["revision"] = revision
		_writing = false
		return write_result
	# rename 完成就是本协议的提交点；flag 失败不能把已提交的数据说成未提交。
	var flag_updated: bool = _write_flag(target) if _dual_slot else true
	_writing = false
	return Result.success({
		"status": "committed", "revision": revision + 1,
		"slot": target, "flag_updated": flag_updated,
	})


## 仅供旧残局单槽删除；双槽核心存档必须通过业务提交重置。
func remove() -> void:
	if _dual_slot:
		push_error("[SaveStore] 不允许 remove 双槽存档")
		return
	for path in [_path_a, _path_a + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## 测试钩子只模拟提交点之前失败及非必要 flag 写失败；不伪造提交后回滚。
func set_fault_injector_for_tests(injector: Callable) -> void:
	_fault_injector = injector


## slot_validator 只读检查已存配置，返回 OperationResult；仅 recoverable=true 的已知坏数据可退回旧槽。
## 调用方提交时使用同一验证，恢复后的 revision 才能继续向前；无验证器保留原文件层语义。
func _scan_slots(slot_validator: Callable = Callable()) -> Dictionary:
	if _path_a.is_empty() or (_dual_slot and _path_b.is_empty()):
		return _failure("invalid", "存档路径未配置")
	if (_dual_slot and _path_a == _path_b) or _flag_path == _path_a or (_dual_slot and _flag_path == _path_b):
		return _failure("invalid", "存档槽和兼容标记必须使用不同路径")
	var candidates: Array[Dictionary] = [_read_candidate(_path_a, "A", slot_validator)]
	if _dual_slot:
		candidates.append(_read_candidate(_path_b, "B", slot_validator))
	var valid: Array[Dictionary] = []
	var has_corrupt := false
	var invalid_state: Dictionary = {}
	var highest_revision: int = 0
	for candidate in candidates:
		highest_revision = maxi(highest_revision, int(candidate.get("revision", 0)))
		# 业务验证器可以禁止回退；例如未来 schema 的数据不能被旧客户端当作坏档忽略。
		if candidate.has("recoverable"):
			if not candidate.recoverable:
				return candidate
			if invalid_state.is_empty():
				invalid_state = candidate
		# 旧程序不能忽略一个可识别的未来格式再覆盖它。
		if candidate.get("status") == "unsupported":
			return candidate
		if bool(candidate.get("ok", false)):
			valid.append(candidate)
		elif candidate.get("status") != "missing":
			has_corrupt = true
	if not valid.is_empty():
		var selected: Dictionary = valid[0]
		for candidate in valid.slice(1):
			var candidate_revision := int(candidate.get("revision", 0))
			var selected_revision := int(selected.get("revision", 0))
			if candidate_revision > selected_revision:
				selected = candidate
			elif candidate_revision == selected_revision:
				# 同一正 revision 应唯一标识一次提交；内容不同就拒绝猜选，旧无版本档才参考 flag。
				if selected_revision > 0:
					var left := selected.get("config") as ConfigFile
					var right := candidate.get("config") as ConfigFile
					if left.encode_to_text() != right.encode_to_text():
						return _failure("conflict", "同 revision 的两个槽内容不同", selected_revision)
				elif candidate.get("slot") == _read_flag():
					selected = candidate
		selected["status"] = "recovered" if has_corrupt else "loaded"
		if slot_validator.is_valid() and highest_revision > int(selected.get("revision", 0)):
			# 坏新槽的业务状态不采用，但可识别的文件发号水位不能重用。
			selected["source_revision"] = int(selected.get("revision", 0))
			selected["revision"] = highest_revision
		return selected
	# 仅为原 SaveStore 的旧单文件兜底保留；LocalCoreStore 不自动导入旧业务档。
	if not _legacy_path.is_empty():
		# 只有没有选中有效槽才尝试旧单文件；它仍要经过相同的文件与业务验证。
		var legacy := _read_candidate(_legacy_path, "legacy", slot_validator)
		if bool(legacy.get("ok", false)):
			legacy["status"] = "recovered_legacy"
			if slot_validator.is_valid() and highest_revision > int(legacy.get("revision", 0)):
				legacy["source_revision"] = int(legacy.get("revision", 0))
				legacy["revision"] = highest_revision
			return legacy
		if legacy.get("status") == "unsupported" or (legacy.has("recoverable") and not legacy.recoverable):
			return legacy
		if legacy.get("status") != "missing":
			has_corrupt = true
	if not invalid_state.is_empty():
		return invalid_state
	return _failure("corrupt" if has_corrupt else "missing", "没有可恢复的完整存档" if has_corrupt else "")


## 只读解析一个槽并验证文件元数据，再交可选业务验证器；返回配置、revision 和槽身份或失败。
func _read_candidate(path: String, slot: String, slot_validator: Callable = Callable()) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("missing", "")
	var cfg := ConfigFile.new()
	if (cfg.load(path) if _plain else cfg.load_encrypted_pass(path, _password)) != OK:
		return _failure("corrupt", "存档读取或校验失败: " + path)
	var revision: int = 0
	# 没有元数据的是可兼容旧档，revision 保持 0；有元数据却版本非法不能降格当旧档。
	if cfg.has_section(_META):
		var version: Variant = cfg.get_value(_META, "format_version", null)
		if typeof(version) != TYPE_INT or version != _FORMAT_VERSION:
			return _failure("unsupported", "不支持的存档文件格式: " + path)
		var stored_revision: Variant = cfg.get_value(_META, "revision", null)
		if typeof(stored_revision) != TYPE_INT or stored_revision <= 0:
			return _failure("corrupt", "存档 revision 无效: " + path)
		revision = stored_revision
	if slot_validator.is_valid():
		var verdict: Variant = slot_validator.call(cfg)
		if not verdict is Dictionary or typeof(verdict.get("ok")) != TYPE_BOOL:
			return Result.failure("invalid_validator", "配置验证器必须返回明确结果", {"status": "invalid_validator", "recoverable": false})
		if not verdict.ok:
			var rejected: Dictionary = verdict.duplicate(true)
			rejected["recoverable"] = bool(verdict.get("recoverable", false))
			rejected["revision"] = revision
			rejected["slot"] = slot
			return rejected
	return Result.success({"status": "loaded", "config": cfg, "revision": revision, "slot": slot})


## 把完整配置写到同目录临时文件并回读核对，最后 rename 到目标路径；rename 是本协议提交点。
## 失败只报告当前操作未完成，不宣称提供断电 fsync 保证。
func _atomic_write(cfg: ConfigFile, final_path: String) -> Dictionary:
	if _inject_fault("before_write"):
		return _failure("write_failed", "注入写入失败")
	if DirAccess.make_dir_recursive_absolute(_dir) != OK:
		return _failure("write_failed", "无法创建存档目录")
	var tmp_path := final_path + ".tmp"
	if (cfg.save(tmp_path) if _plain else cfg.save_encrypted_pass(tmp_path, _password)) != OK:
		return _failure("write_failed", "无法写入临时存档")
	if _inject_fault("after_temp_write"):
		return _failure("write_failed", "注入临时文件写后中断")
	var verify := ConfigFile.new()
	if (verify.load(tmp_path) if _plain else verify.load_encrypted_pass(tmp_path, _password)) != OK:
		return _failure("write_failed", "临时存档回读失败")
	# ConfigFile 的浮点文本 parse→encode 可能改变末位；校验实际写入的原文，
	# 不把重编码当保真依据，也不以浮点容差放过损坏。解密和配置解析仍须成功。
	var verified_file: FileAccess = FileAccess.open(tmp_path, FileAccess.READ) if _plain else FileAccess.open_encrypted_with_pass(tmp_path, FileAccess.READ, _password)
	if verified_file == null:
		return _failure("write_failed", "临时存档回读失败")
	var verified_text: String = verified_file.get_as_text()
	verified_file.close()
	if verified_text != cfg.encode_to_text():
		return _failure("write_failed", "临时存档回读不一致")
	if _inject_fault("before_replace"):
		return _failure("write_failed", "注入替换前中断")
	# 此处之前任何失败都不能当作提交成功；替换完成后新槽才参与下一次恢复。
	if DirAccess.rename_absolute(tmp_path, final_path) != OK:
		return _failure("write_failed", "无法提交临时存档")
	return Result.success()


## 读取旧 A/B 标记；缺失、不可读或内容无效都返回空串，不把标记当新档权威版本。
func _read_flag() -> String:
	if _flag_path.is_empty() or not FileAccess.file_exists(_flag_path):
		return ""
	var file := FileAccess.open(_flag_path, FileAccess.READ)
	if file == null:
		return ""
	var flag := file.get_as_text().strip_edges()
	return flag if flag in ["A", "B"] else ""


## 尽力写入兼容标记并 flush，返回是否成功；调用点已经完成主存档替换。
func _write_flag(slot: String) -> bool:
	if _flag_path.is_empty():
		return true
	if _inject_fault("flag_write"):
		return false
	var file := FileAccess.open(_flag_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(slot)
	file.flush()
	return file.get_error() == OK


## 询问测试钩子当前阶段是否应失败；未设置钩子时始终为 false。
func _inject_fault(phase: String) -> bool:
	return _fault_injector.is_valid() and bool(_fault_injector.call(phase))


## 复制配置节与键并跳过调用方元数据，供本层重新编号；这是 ConfigFile 外壳复制，不是嵌套 Variant 深拷贝。
func _copy_config(source: ConfigFile) -> ConfigFile:
	var copy := ConfigFile.new()
	for section in source.get_sections():
		if section == _META:
			continue
		for key in source.get_section_keys(section):
			copy.set_value(section, key, source.get_value(section, key))
	return copy


## 统一失败状态与版本号；调用方不需要从错误文本猜测是否冲突或能否重试。
func _failure(status: String, message: String, revision: int = 0) -> Dictionary:
	return Result.failure(status, message, {"status": status, "revision": revision})

## 为旧工具/造数器创建明文单槽存档端口；构造不写文件，仍沿用临时校验和 revision 机制。
## 需要冲突保护时调用 commit_config 并传 expected_revision；旧 save_config 接口不提供这个读取版本。
static func plain_file(path: String) -> SaveStore:
	return SaveStore.new("", path.get_base_dir(), false, path, "", "", "", true)
