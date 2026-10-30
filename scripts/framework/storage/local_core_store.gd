## 核心业务状态的唯一提交入口；候选状态落盘成功后才发布到内存。
## 同步单写者，不执行 SDK、埋点或 UI，也不自动迁移未知业务 schema。
class_name LocalCoreStore
extends RefCounted

signal committed(revision: int)

const Result = preload("res://scripts/framework/operation_result.gd")

var _file_store: RefCounted
var _schema_version: int
var _validator: Callable
var _schema_migrator: Callable
var _state: Dictionary = {}
var _revision: int = 0
var _opened: bool = false
var _committing: bool = false


## validator(candidate) 返回空字符串表示有效，否则返回拒绝原因。
func _init(file_store: RefCounted, schema_version: int, validator: Callable = Callable(), schema_migrator: Callable = Callable()) -> void:
	_file_store = file_store
	_schema_version = schema_version
	_validator = validator
	_schema_migrator = schema_migrator


## 只有文件确实不存在才允许使用 initial_state；默认只打开内存，不创建存档。
## persist_initial 要求首次落盘成功后才开放业务写入，失败可用同一实例重试。
func open(initial_state: Dictionary = {}, persist_initial: bool = false) -> Dictionary:
	if _opened:
		return _failure("already_open", "核心存档已经打开")
	if _committing:
		return _failure("busy", "核心业务提交尚未结束")
	if _file_store == null or _schema_version <= 0:
		return _failure("invalid", "核心存档配置无效")
	var loaded: Dictionary = _file_store.load_result(_validate_config)
	var candidate: Dictionary
	var migrated: bool = false
	if loaded.get("status") == "missing":
		candidate = initial_state
	elif not bool(loaded.get("ok", false)):
		return loaded
	else:
		var decoded := _decode_config(loaded.get("config") as ConfigFile)
		if not decoded.get("ok", false):
			return decoded
		candidate = decoded.state
		migrated = bool(decoded.get("migrated", false))
	if loaded.get("status") == "missing":
		var error := _validate(candidate)
		if not error.is_empty():
			return _failure("invalid_state", error)
	var next_state := candidate.duplicate(true)
	var result := Result.success({"status": loaded.get("status"), "revision": int(loaded.get("revision", 0))})
	var initialize_file: bool = persist_initial and loaded.get("status") == "missing"
	if initialize_file or migrated:
		var initial_config := ConfigFile.new()
		initial_config.set_value("core", "schema_version", _schema_version)
		initial_config.set_value("core", "state", next_state)
		_committing = true
		result = _file_store.commit_config(initial_config, int(loaded.get("revision", 0)), _validate_config)
		_committing = false
		if not result.get("ok", false):
			return result
	if migrated:
		result["status"] = "migrated"
		result["schema_version"] = _schema_version
	_state = next_state
	_revision = int(result.get("revision", 0))
	_opened = true
	if initialize_file or migrated:
		committed.emit(_revision)
	return result


func is_open() -> bool:
	return _opened


func revision() -> int:
	return _revision


## 深拷贝避免页面或调用方绕过提交直接修改库存/进度。
func snapshot() -> Dictionary:
	return _state.duplicate(true)


func commit(candidate: Dictionary, expected_revision: int) -> Dictionary:
	if not _opened:
		return _failure("not_open", "核心存档未成功打开")
	if _committing:
		return _failure("busy", "核心业务提交尚未结束")
	if expected_revision != _revision:
		return _failure("conflict", "核心状态 revision 已改变")
	_committing = true
	var error := _validate(candidate)
	if not error.is_empty():
		_committing = false
		return _failure("invalid_state", error)
	var next_state := candidate.duplicate(true)
	var cfg := ConfigFile.new()
	cfg.set_value("core", "schema_version", _schema_version)
	cfg.set_value("core", "state", next_state)
	var result: Dictionary = _file_store.commit_config(cfg, expected_revision, _validate_config)
	if bool(result.get("ok", false)):
		_state = next_state
		_revision = int(result.get("revision"))
	_committing = false
	if bool(result.get("ok", false)):
		committed.emit(_revision)
	return result


## 文件可读不代表业务快照可用。只允许已知 schema 的坏状态回退；未知 schema 必须整体拒绝。
func _validate_config(cfg: ConfigFile) -> Dictionary:
	var decoded := _decode_config(cfg)
	if not decoded.get("ok", false):
		return decoded
	var error := _validate(decoded.state)
	if not error.is_empty():
		return Result.failure("invalid_state", error, {"status": "invalid_state", "recoverable": true})
	return Result.success()


## 显式迁移器仅接收副本；未知 schema 仍阻断整个槽扫描，不能静默回退覆盖。
## migrator(source_schema, target_schema, state) 返回 {ok, state} 或明确失败。
func _decode_config(cfg: ConfigFile) -> Dictionary:
	var stored_schema: Variant = cfg.get_value("core", "schema_version", null)
	if typeof(stored_schema) != TYPE_INT or stored_schema <= 0:
		return Result.failure("schema_mismatch", "核心存档 schema 无效", {"status": "schema_mismatch", "recoverable": false})
	var state: Variant = cfg.get_value("core", "state", null)
	if stored_schema != _schema_version and not _schema_migrator.is_valid():
		return Result.failure("schema_mismatch", "需要显式迁移核心存档 schema", {"status": "schema_mismatch", "recoverable": false})
	if not state is Dictionary:
		return Result.failure("invalid_state" if stored_schema == _schema_version else "schema_mismatch", "核心存档 state 不是字典", {"status": "invalid_state" if stored_schema == _schema_version else "schema_mismatch", "recoverable": stored_schema == _schema_version})
	if stored_schema == _schema_version:
		return Result.success({"state": state.duplicate(true), "migrated": false})
	var converted: Variant = _schema_migrator.call(stored_schema, _schema_version, state.duplicate(true))
	if not converted is Dictionary or not converted.get("ok", false):
		var detail := "未配置该版本的显式迁移"
		if converted is Dictionary:
			detail = str(converted.get("detail", detail))
		return Result.failure("schema_mismatch", detail, {"status": "schema_mismatch", "recoverable": false})
	if not converted.get("state") is Dictionary:
		return Result.failure("invalid_state", "迁移器未返回字典状态", {"status": "invalid_state", "recoverable": false})
	return Result.success({"state": converted.state.duplicate(true), "migrated": true})


func _validate(candidate: Dictionary) -> String:
	var error := _validate_data(candidate, 0)
	if not error.is_empty():
		return error
	if _validator.is_valid():
		# 验证器也只拿到副本，不能改写实际待提交值。
		var verdict: Variant = _validator.call(candidate.duplicate(true))
		if not verdict is String:
			return "状态验证器必须返回字符串"
		return verdict
	return ""


## 只拒绝不能作为持久数据的运行时引用；具体字段约束归业务验证器。
func _validate_data(value: Variant, depth: int) -> String:
	if depth > 64:
		return "状态嵌套过深或包含循环引用"
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return "状态不能包含节点、资源或运行时引用"
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]:
					return "状态字典的键必须为字符串或整数"
				var error := _validate_data(value[key], depth + 1)
				if not error.is_empty():
					return error
		TYPE_ARRAY:
			for entry in value:
				var error := _validate_data(entry, depth + 1)
				if not error.is_empty():
					return error
	return ""


func _failure(status: String, message: String) -> Dictionary:
	return Result.failure(status, message, {"status": status, "revision": _revision})
