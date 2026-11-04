## 核心业务状态的唯一提交入口；候选状态落盘成功后才发布到内存。
## 同步单写者，不执行 SDK、埋点或 UI，也不自动迁移未知业务 schema。
class_name LocalCoreStore
extends RefCounted

signal committed(revision: int) # 落盘并更新内存后同步发出；监听者读取到的是新版本。

const Result = preload("res://scripts/framework/operation_result.gd")

var _file_store: RefCounted # 文件层端口，负责槽恢复、revision 检查和原子替换。
var _schema_version: int # 宿主产品当前业务结构版本；不是 SaveStore 的文件格式版本。
var _validator: Callable # 业务验证器：只检查副本，返回空串或拒绝原因。
var _schema_migrator: Callable # 显式版本转换器；可能在槽扫描中多次调用，必须纯计算且结果确定。
var _state: Dictionary = {} # 最近一次成功打开/提交的权威内存状态；不直接交给页面修改。
var _revision: int = 0 # 当前读写版本；0 表示尚无带版本的已提交文件。
var _opened: bool = false # 只有成功打开现档、初始化或迁移后才允许业务提交。
var _committing: bool = false # 同步重入锁，防验证器或文件回调嵌套提交；不是跨线程/跨进程互斥锁。


## 注入文件端口、目标 schema 与可选验证/迁移函数；构造时不读写文件。
## validator(candidate) 返回空字符串或拒绝原因；migrator(from, to, state) 返回 {ok, state} 或失败。
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
	# 槽选择同时检查业务有效性：已知坏状态可恢复旧槽，未知版本则由验证结果阻止整个恢复。
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
	# 切断调用方持有的嵌套字典/数组引用，后续修改原 candidate 不会改写这里准备的状态。
	var next_state := candidate.duplicate(true)
	var result := Result.success({"status": loaded.get("status"), "revision": int(loaded.get("revision", 0))})
	var initialize_file: bool = persist_initial and loaded.get("status") == "missing"
	# 首次主动建档和旧版本升级都要先落盘；persist_initial 只控制新档，不能跳过迁移写入。
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
	# 必要的文件操作已成功；仅在内存建立的新档也已通过验证。此前任何失败都没有发布候选。
	_state = next_state
	_revision = int(result.get("revision", 0))
	_opened = true
	if initialize_file or migrated:
		committed.emit(_revision)
	return result


## 返回存档是否已经成功开放；失败的首次打开不会留下可写的半初始化状态。
func is_open() -> bool:
	return _opened


## 取得当前版本号，调用方应与 snapshot 配对捕获，并在提交时原样带回。
func revision() -> int:
	return _revision


## 深拷贝避免页面或调用方绕过提交直接修改库存/进度。
func snapshot() -> Dictionary:
	return _state.duplicate(true)


## 按 expected_revision 提交完整候选；拒绝旧版本或非法状态，成功才替换内存并通知观察者。
func commit(candidate: Dictionary, expected_revision: int) -> Dictionary:
	if not _opened:
		return _failure("not_open", "核心存档未成功打开")
	if _committing:
		return _failure("busy", "核心业务提交尚未结束")
	# 候选属于读取时的版本，不能拿过期副本覆盖期间已经完成的另一笔业务。
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
	# 先解除同步提交锁再发信号；观察者可以开始下一笔业务，但旧候选已不再具有写入资格。
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


## 解出业务状态或调用显式迁移器，返回 {state, migrated}；此函数自身不写盘。
## 迁移器仅接收副本；未明确支持的 schema 阻断槽扫描，不能静默回退旧槽后覆盖它。
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
	# 扫描各槽、打开选中槽和提交前复核都可能到达这里；迁移器不能消耗随机数、资格或发送外部请求。
	var converted: Variant = _schema_migrator.call(stored_schema, _schema_version, state.duplicate(true))
	if not converted is Dictionary or not converted.get("ok", false):
		var detail := "未配置该版本的显式迁移"
		if converted is Dictionary:
			detail = str(converted.get("detail", detail))
		return Result.failure("schema_mismatch", detail, {"status": "schema_mismatch", "recoverable": false})
	if not converted.get("state") is Dictionary:
		return Result.failure("invalid_state", "迁移器未返回字典状态", {"status": "invalid_state", "recoverable": false})
	return Result.success({"state": converted.state.duplicate(true), "migrated": true})


## 先拒绝运行时引用等不可保存结构，再交产品验证器检查字段；返回空串或原因。
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
	# 深度上限也能截断自引用容器；不会无限递归追踪到栈耗尽。
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


## 构造失败结果并附当前 revision，便于调用方区分冲突、未打开和数据无效。
func _failure(status: String, message: String) -> Dictionary:
	return Result.failure(status, message, {"status": status, "revision": _revision})
