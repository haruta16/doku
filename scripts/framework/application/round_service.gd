## 窄对局宿主：命名空间、递增请求序号、原子库存变化与模块快照提交。
## 不识别棋盘、玩法动作、动画或关卡规则；模块返回不含运行时引用的普通数据。
class_name RoundService
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
const MAX_SEQUENCE: int = 9223372036854775807 # 有符号 64 位整数上限；序号耗尽就拒绝，不能回绕复用旧请求身份。

var _store: RefCounted # 注入的核心存档端口；快照、库存与请求回执共用一次提交。
var _modules: Dictionary = {} # module_id → 玩法模块；只保留运行时依赖，不把这些对象写进存档。


## 绑定核心存档端口；本身不打开文件，调用方需先把存档准备好。
func _init(core_store: RefCounted) -> void:
	_store = core_store


## 注册一个命名玩法模块，检查所需方法是否齐全；返回是否接受，不验证或创建对局。
func register_module(module_id: String, module: RefCounted) -> bool:
	if not _valid_name(module_id) or module == null:
		return false
	for method: String in ["create_snapshot", "validate_snapshot", "sync_runtime", "apply_action", "settle_snapshot"]:
		if not module.has_method(method):
			return false
	_modules[module_id] = module
	return true


## 读取 module/mode 命名空间已有对局并验证，返回快照与下一请求序号；只读，不创建新局。
func resume(module_id: String, mode_id: String) -> Dictionary:
	var error: String = _availability_error(module_id, mode_id)
	if not error.is_empty():
		return Result.failure(error)
	var state: Variant = _store.snapshot()
	if not _valid_store_state(state):
		return Result.failure("invalid_store_state")
	var records: Dictionary = state.get("round_services", {})
	var key: String = module_id + "/" + mode_id
	if not records.has(key):
		return Result.failure("missing", "", {"start_sequence": 0, "next_sequence": 1})
	if not records[key] is Dictionary:
		return Result.failure("invalid_record", "record must be a dictionary")
	var record: Dictionary = records[key]
	var record_error: String = _validate_record(record, module_id, mode_id)
	if not record_error.is_empty():
		return Result.failure("invalid_record", record_error)
	var module: RefCounted = _modules[module_id]
	var invalid: String = _validate_snapshot(module, record.snapshot)
	if not invalid.is_empty():
		return Result.failure("invalid_snapshot", invalid)
	return _response(record)


## start_sequence 必须是该命名空间的上一序号 +1；重试复用同一序号。
## 新局显式替换此命名空间旧局；旧 round_id 的延迟操作随后会被拒绝。
func start(module_id: String, mode_id: String, start_sequence: int, context: Dictionary) -> Dictionary:
	var error: String = _availability_error(module_id, mode_id)
	if not error.is_empty():
		return Result.failure(error)
	# 先捕获读取版本；后面的模块计算若触发别的提交，最终提交会因版本变化而拒绝旧候选。
	var expected: int = _store.revision()
	var candidate: Variant = _store.snapshot()
	if not _valid_store_state(candidate):
		return Result.failure("invalid_store_state")
	var records: Dictionary = candidate.get("round_services", {})
	var key: String = module_id + "/" + mode_id
	if records.has(key) and not records[key] is Dictionary:
		return Result.failure("invalid_record", "record must be a dictionary")
	var previous: Dictionary = records.get(key, {})
	if not previous.is_empty():
		var invalid_record: String = _validate_record(previous, module_id, mode_id)
		if not invalid_record.is_empty():
			return Result.failure("invalid_record", invalid_record)
	var previous_sequence: int = int(previous.get("start_sequence", 0))
	# 重试不仅要复用序号，也必须复用原开局上下文；同序号换内容属于碰撞，不能当作同一请求。
	if start_sequence == previous_sequence and not previous.is_empty():
		if previous.get("status") == "reset":
			return Result.failure("round_inactive")
		if previous.get("start_context", {}) != context:
			return Result.failure("sequence_collision")
		var duplicate: Dictionary = _response(previous)
		duplicate["duplicate"] = true
		return duplicate
	if previous_sequence == MAX_SEQUENCE or start_sequence != previous_sequence + 1:
		return Result.failure("invalid_start_sequence")
	var module: RefCounted = _modules[module_id]
	# 模块只负责创建可保存的数据；不能把 Node、资源实例或外部服务句柄当快照返回。
	var prepared: Variant = module.create_snapshot(context.duplicate(true))
	var contract_error: String = _validate_module_response(prepared)
	if not contract_error.is_empty():
		return Result.failure("invalid_module_result", contract_error)
	if not prepared.ok:
		return prepared
	var invalid_snapshot: String = _validate_snapshot(module, prepared.snapshot)
	if not invalid_snapshot.is_empty():
		return Result.failure("invalid_module_result", invalid_snapshot)
	var record: Dictionary = {
		"module_id": module_id, "mode_id": mode_id,
		"round_id": "%s#%d" % [key, start_sequence],
		"start_sequence": start_sequence, "last_sequence": 0,
		"start_context": context.duplicate(true),
		"status": "active", "snapshot": prepared.snapshot,
		"last_receipt": {}, "settlement": {},
	}
	records[key] = record
	candidate["round_services"] = records
	# 提交成功前 round_id 只存在于候选；失败返回后，调用方可以复用同一 start_sequence 重试。
	var committed: Dictionary = _store.commit(candidate, expected)
	if not committed.get("ok", false):
		return Result.wrap_failure("commit_failed", committed)
	return _response(record)


## runtime_snapshot 是兼容旧玩法时从唯一活模型捕获的检查点，不是第二份活状态。
## policy 由产品业务层提供，与玩家动作 payload 分开；具体含义仅由玩法模块解释。
func action(
	module_id: String, mode_id: String, round_id: String, sequence: int,
	kind: String, payload: Dictionary = {}, runtime_snapshot: Dictionary = {}, policy: Dictionary = {}
) -> Dictionary:
	if kind.is_empty() or kind.begins_with("__"):
		return Result.failure("invalid_action_kind")
	return _execute(module_id, mode_id, round_id, sequence, kind, payload, runtime_snapshot, policy)


## 使用保留动作名执行终局事务；payload 由模块解释，重复结算返回既有回执而不重复发奖。
func settle(
	module_id: String, mode_id: String, round_id: String, sequence: int,
	payload: Dictionary = {}, runtime_snapshot: Dictionary = {}
) -> Dictionary:
	return _execute(module_id, mode_id, round_id, sequence, "__settle", payload, runtime_snapshot, {})


## 动作和结算的共同入口：核对身份/顺序 → 模块计算候选 → 合并库存 → 一次提交。
## 任何阶段失败都不发布候选；成功返回的 changes 供页面表现，不在此播放动画。
func _execute(
	module_id: String, mode_id: String, round_id: String, sequence: int,
	kind: String, payload: Dictionary, runtime_snapshot: Dictionary, policy: Dictionary
) -> Dictionary:
	var error: String = _availability_error(module_id, mode_id)
	if not error.is_empty():
		return Result.failure(error)
	var expected: int = _store.revision()
	var candidate: Variant = _store.snapshot()
	if not _valid_store_state(candidate):
		return Result.failure("invalid_store_state")
	var records: Dictionary = candidate.get("round_services", {})
	var key: String = module_id + "/" + mode_id
	if records.has(key) and not records[key] is Dictionary:
		return Result.failure("invalid_record", "record must be a dictionary")
	var record: Dictionary = records.get(key, {})
	if record.is_empty() or str(record.get("round_id", "")) != round_id:
		return Result.failure("stale_round")
	var record_error: String = _validate_record(record, module_id, mode_id)
	if not record_error.is_empty():
		return Result.failure("invalid_record", record_error)
	if record.get("status") == "reset":
		return Result.failure("round_inactive")
	var last_sequence: int = int(record.get("last_sequence", 0))
	# 只保留最近一次请求回执：同序号、同动作和 payload 直接返回旧结果，不再次消费道具。
	if sequence == last_sequence and sequence > 0:
		var receipt: Dictionary = record.get("last_receipt", {})
		if receipt.get("kind") != kind or receipt.get("payload") != payload:
			return Result.failure("sequence_collision")
		var duplicate: Dictionary = _response(record)
		duplicate["duplicate"] = true
		return duplicate
	if record.get("status") not in ["active", "settled"]:
		return Result.failure("round_inactive")
	# 已结算对局拒绝普通动作；再次请求结算返回保存的 settlement，并清空待播放 changes。
	if record.get("status") == "settled":
		if kind != "__settle":
			return Result.failure("round_settled")
		var settled: Dictionary = _response(record)
		settled["result"] = record.get("settlement", {}).duplicate(true)
		settled["changes"] = []
		settled["duplicate"] = true
		return settled
	if last_sequence == MAX_SEQUENCE or sequence != last_sequence + 1:
		return Result.failure("stale_sequence" if sequence <= last_sequence else "sequence_gap")
	var module: RefCounted = _modules[module_id]
	var snapshot: Dictionary = record.get("snapshot", {})
	var invalid: String = _validate_snapshot(module, snapshot)
	if not invalid.is_empty():
		return Result.failure("invalid_snapshot", invalid)
	# 兼容入口先把页面唯一活模型的检查点交给模块同步；宿主仍只操作从存档取出的候选。
	if not runtime_snapshot.is_empty():
		var synced: Variant = module.sync_runtime(snapshot, runtime_snapshot.duplicate(true))
		var sync_error: String = _validate_module_response(synced)
		if not sync_error.is_empty():
			return Result.failure("invalid_module_result", sync_error)
		if not synced.ok:
			return synced
		snapshot = synced.snapshot
		invalid = _validate_snapshot(module, snapshot)
		if not invalid.is_empty():
			return Result.failure("invalid_module_result", invalid)
	var prepared: Variant
	if kind == "__settle":
		prepared = module.settle_snapshot(snapshot, payload.duplicate(true))
	else:
		prepared = module.apply_action(snapshot, kind, payload.duplicate(true), {
			"round_id": round_id, "sequence": sequence, "policy": policy.duplicate(true)
		})
	var contract_error: String = _validate_module_response(prepared)
	if not contract_error.is_empty():
		return Result.failure("invalid_module_result", contract_error)
	if not prepared.ok:
		return prepared
	invalid = _validate_snapshot(module, prepared.snapshot)
	if not invalid.is_empty():
		return Result.failure("invalid_module_result", invalid)
	# 动作快照与道具扣款先合在同一候选内；不会出现棋盘已变但库存仍未扣的中间存档。
	var inventory_error: String = _apply_inventory_delta(candidate, prepared.get("inventory_delta", {}))
	if not inventory_error.is_empty():
		return Result.failure(inventory_error)
	record["snapshot"] = prepared.snapshot
	record["last_sequence"] = sequence
	# 把结果和请求身份一起保存；写成功但响应丢失时，重试仍能读到同一笔结果。
	record["last_receipt"] = {
		"kind": kind, "payload": payload.duplicate(true),
		"result": prepared.get("result", {}).duplicate(true),
		"changes": prepared.get("changes", []).duplicate(true),
	}
	if kind == "__settle":
		record["status"] = "settled"
		record["settlement"] = prepared.get("result", {}).duplicate(true)
	records[key] = record
	candidate["round_services"] = records
	var committed: Dictionary = _store.commit(candidate, expected)
	if not committed.get("ok", false):
		return Result.wrap_failure("commit_failed", committed)
	return _response(record)


## 把模块给出的整数增减量应用到候选库存；空串表示成功，余额不足、未知道具或溢出则拒绝。
## 失败时可能已暂存前面的条目，调用方必须丢弃整个候选。
func _apply_inventory_delta(candidate: Dictionary, delta: Dictionary) -> String:
	var inventory: Dictionary = candidate.get("inventory", {})
	for item: Variant in delta:
		if typeof(item) != TYPE_STRING or not inventory.has(item):
			return "unknown_item"
		if typeof(delta[item]) != TYPE_INT or typeof(inventory[item]) != TYPE_INT:
			return "invalid_inventory"
		var current: int = inventory[item]
		var change: int = delta[item]
		if current < 0:
			return "invalid_inventory"
		if change < -current:
			return "insufficient_items"
		if change > 0 and current > MAX_SEQUENCE - change:
			return "inventory_overflow"
		inventory[item] = current + change
	candidate["inventory"] = inventory
	return ""


## 从已验证的对局记录构造统一响应；嵌套快照与回执深拷贝，外部修改不能反向污染记录。
func _response(record: Dictionary) -> Dictionary:
	var receipt: Dictionary = record.get("last_receipt", {})
	return Result.success({
		"duplicate": false,
		"round_id": record.get("round_id", ""), "status": record.get("status", "active"),
		"start_sequence": int(record.get("start_sequence", 0)),
		"sequence": int(record.get("last_sequence", 0)),
		"next_sequence": int(record.get("last_sequence", 0)) + 1 if int(record.get("last_sequence", 0)) < MAX_SEQUENCE else -1,
		"snapshot": record.get("snapshot", {}).duplicate(true),
		"result": receipt.get("result", {}).duplicate(true),
		"changes": receipt.get("changes", []).duplicate(true),
	})


## 检查存档端口是否开放、命名空间是否合法、模块是否注册；返回空串或错误码。
func _availability_error(module_id: String, mode_id: String) -> String:
	if _store == null:
		return "store_not_open"
	for method: String in ["is_open", "revision", "snapshot", "commit"]:
		if not _store.has_method(method):
			return "invalid_store_port"
	if not _store.is_open():
		return "store_not_open"
	if not _valid_name(module_id) or not _valid_name(mode_id):
		return "invalid_namespace"
	return "" if _modules.has(module_id) else "unknown_module"


## 模块是可替换边界，不能因为它返回 ok 就信任字段类型或快照。
## 提前给出错误，避免 .duplicate()/点访问在新玩法接入时变成脚本异常。
static func _validate_module_response(value: Variant) -> String:
	if not value is Dictionary or typeof(value.get("ok")) != TYPE_BOOL:
		return "module response requires a boolean ok"
	if not value.ok:
		return "" if typeof(value.get("error")) == TYPE_STRING else "module failure requires an error string"
	if not value.get("snapshot") is Dictionary:
		return "module success requires a snapshot dictionary"
	for field: String in ["result", "inventory_delta"]:
		if not value.get(field, {}) is Dictionary:
			return field + " must be a dictionary"
	if not value.get("changes", []) is Array and not value.get("changes", []) is Dictionary:
		return "changes must be an array or dictionary"
	return ""


## 只核对宿主会读取的根字典形状；具体玩家字段与玩法快照交各自验证器判断。
static func _valid_store_state(value: Variant) -> bool:
	return value is Dictionary and value.get("round_services", {}) is Dictionary and value.get("inventory", {}) is Dictionary


## 把快照副本交给玩法模块校验；要求返回字符串，避免验证器写坏待提交快照。
static func _validate_snapshot(module: RefCounted, snapshot: Dictionary) -> String:
	var verdict: Variant = module.validate_snapshot(snapshot.duplicate(true))
	return verdict if verdict is String else "snapshot validator must return a string"


## 保留产品附加字段，只验证宿主自己拥有的身份、顺序和回执。
static func _validate_record(record: Dictionary, module_id: String, mode_id: String) -> String:
	if typeof(record.get("module_id")) != TYPE_STRING or typeof(record.get("mode_id")) != TYPE_STRING:
		return "invalid record namespace"
	if record.module_id != module_id or record.mode_id != mode_id:
		return "record namespace mismatch"
	if typeof(record.get("start_sequence")) != TYPE_INT or record.start_sequence < 1:
		return "invalid start sequence"
	if typeof(record.get("round_id")) != TYPE_STRING or record.round_id != "%s/%s#%d" % [module_id, mode_id, record.start_sequence]:
		return "invalid round identity"
	if typeof(record.get("last_sequence")) != TYPE_INT or record.last_sequence < 0:
		return "invalid action sequence"
	if typeof(record.get("status")) != TYPE_STRING or record.status not in ["active", "settled", "reset"]:
		return "invalid round status"
	for field: String in ["snapshot", "start_context", "last_receipt", "settlement"]:
		if not record.get(field) is Dictionary:
			return "invalid record " + field
	var receipt: Dictionary = record.last_receipt
	if record.last_sequence > 0 and record.status != "reset":
		if typeof(receipt.get("kind")) != TYPE_STRING or not receipt.get("payload") is Dictionary:
			return "invalid request receipt"
		if not receipt.get("result") is Dictionary:
			return "invalid receipt result"
		if not receipt.get("changes") is Array and not receipt.get("changes") is Dictionary:
			return "invalid receipt changes"
	return ""


## 限制命名空间为字母、数字、横线、点和下划线；排除 / 与 #，避免拼出的 key/round_id 歧义。
static func _valid_name(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not ((code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57) or code in [45, 46, 95]):
			return false
	return true

