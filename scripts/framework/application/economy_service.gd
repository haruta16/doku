## 通用库存与奖励用例：把「登记待领 → 确认翻倍 → 领取入账」放在同一核心状态中管理。
## 只依赖存档端口与可选资产策略，不访问页面、SDK 或全局单例；领取成功后再由产品播放表现。
class_name EconomyService
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")

var _store: RefCounted # 持有 snapshot/revision/commit 的核心存档端口；本类不自行维护另一份余额。
var _item_policy: RefCounted # 可选产品规则，提供 validate_award、can_double、stage_item；null 沿用普通库存规则。


## 注入存档和可选资产规则；这里只保存依赖，不读文件或创建奖励。
func _init(core_store: RefCounted, item_policy: RefCounted = null) -> void:
	_store = core_store
	_item_policy = item_policy


## claim_key 是业务身份，重试必须复用；空字符串表示每次都是新的一笔。
## 登记一笔待领取奖励并提交；返回保存结果与 uid，重复业务键返回原 uid 且不再写盘。
func register_award(items: Array, display_type: int, reason: String, bonus_reason: String = "", claim_key: String = "") -> Dictionary:
	var candidate: Dictionary = _store.snapshot()
	var staged := stage_award(candidate, items, display_type, reason, bonus_reason, claim_key)
	if not staged.get("ok", false) or staged.get("duplicate", false):
		return staged
	var result: Dictionary = _store.commit(candidate, _store.revision())
	if result.get("ok", false):
		result["uid"] = staged.uid
	return result


## 在调用方的候选状态登记奖励，供“资格变化 + 奖励登记”一起提交；本函数不写盘。
func stage_award(candidate: Dictionary, items: Array, display_type: int, reason: String, bonus_reason: String = "", claim_key: String = "") -> Dictionary:
	if not _store.is_open():
		return _failure("not_open", "核心存档不可用")
	var inventory: Dictionary = candidate.get("inventory", {})
	var error := _validate_award_items(items, candidate)
	if not error.is_empty() or reason.is_empty():
		return _failure("invalid_award", error if not error.is_empty() else "奖励来源不能为空")
	# claim_key 对应一次业务资格，uid 对应一次奖励流水；二者不能用页面实例身份代替。
	var claims: Dictionary = candidate.get("claims", {})
	if not claim_key.is_empty() and claims.has(claim_key):
		return Result.success({"status": "duplicate", "duplicate": true, "uid": int(claims[claim_key])})
	var previous: int = int(candidate.get("award_sequence", 0))
	if previous == 9223372036854775807:
		return _failure("sequence_exhausted", "奖励流水序号已耗尽")
	var uid := previous + 1
	var pending: Array = candidate.get("pending_awards", [])
	pending.append({"uid": uid, "items": items.duplicate(true), "display_type": display_type, "reason": reason, "bonus_reason": bonus_reason, "doubled": false})
	candidate["award_sequence"] = uid
	candidate["pending_awards"] = pending
	if not claim_key.is_empty():
		claims[claim_key] = uid
	candidate["claims"] = claims
	return Result.success({"status": "staged", "uid": uid, "duplicate": false})


## 从 pending 移除与全部库存增加只产生一个提交；没有部分到账的中间存档。
## 领取 uid 指定的待发奖励；成功结果包含实际 grants，失败时整个候选被丢弃。
func claim_award(uid: int) -> Dictionary:
	var candidate: Dictionary = _store.snapshot()
	var staged := stage_claim(candidate, uid)
	if not staged.get("ok", false) or staged.get("status") == "already_applied":
		return staged
	var result: Dictionary = _store.commit(candidate, _store.revision())
	if result.get("ok", false):
		result["uid"] = uid
		result["grants"] = staged.grants
	return result


## 在调用方候选中领取 uid，返回 grants；可与签到资格、补发账本等一起提交。
## 逐项处理期间若失败，candidate 可能已有局部变化，调用方必须丢弃整份候选，不能继续提交。
func stage_claim(candidate: Dictionary, uid: int) -> Dictionary:
	if not _store.is_open():
		return _failure("not_open", "核心存档不可用")
	var pending: Array = candidate.get("pending_awards", [])
	var index := _find(pending, uid)
	if index < 0:
		if uid > 0 and uid <= int(candidate.get("award_sequence", 0)):
			return Result.success({"status": "already_applied", "uid": uid, "grants": []})
		return _failure("unknown_award", "奖励流水不存在")
	var entry: Dictionary = pending[index]
	var inventory: Dictionary = candidate.get("inventory", {})
	var items: Array = entry.get("items", [])
	var error := _validate_award_items(items, candidate)
	if not error.is_empty():
		return _failure("invalid_award", error)
	var grants: Array = []
	# 翻倍是待发记录里的持久资格；第二份是否适用由资产类型决定，例如头像框可以不翻倍。
	var copies: int = 2 if entry.get("doubled", false) else 1
	for copy_index in copies:
		var reason: String = str(entry.get("reason", ""))
		if copy_index == 1 and not str(entry.get("bonus_reason", "")).is_empty():
			reason = str(entry.bonus_reason)
		for item: Dictionary in items:
			if _item_policy != null:
				if copy_index == 1 and not _item_policy.can_double(item):
					continue
				var applied: Dictionary = _item_policy.stage_item(candidate, item, reason)
				if not applied.get("ok", false):
					return applied
				grants.append(applied.grant)
				continue
			var kind: String = item.kind
			var amount: int = item.count
			var current: int = inventory.get(kind, 0)
			if amount > 9223372036854775807 - current:
				return _failure("overflow", "库存超过整数范围")
			inventory[kind] = current + amount
			grants.append({"kind": kind, "count": amount, "reason": reason, "balance": current + amount})
	# 只有全部条目都成功暂存后才移除待领记录；余额和移除动作仍要等待同一次 core.commit。
	pending.remove_at(index)
	candidate["inventory"] = inventory
	candidate["pending_awards"] = pending
	return Result.success({"status": "staged", "uid": uid, "grants": grants})


## 翻倍资格单独持久化；页面消失或进程退出后仍能按同一笔奖励补发。
func double_award(uid: int) -> Dictionary:
	if not _store.is_open():
		return _failure("not_open", "核心存档不可用")
	var candidate: Dictionary = _store.snapshot()
	var pending: Array = candidate.get("pending_awards", [])
	var index := _find(pending, uid)
	if index < 0:
		return _failure("award_closed", "基础奖励已经结束，不能改变其翻倍状态")
	if bool(pending[index].get("doubled", false)):
		return Result.success({"status": "already_doubled", "uid": uid})
	# 这里只确认额外一份的资格，不先把资产发到账户；claim_award 会统一处理实际入账。
	pending[index]["doubled"] = true
	candidate["pending_awards"] = pending
	return _store.commit(candidate, _store.revision())


## 默认道具校验：items 必须非空，kind 必须已注册且 count 为正整数；返回空串表示通过。
static func validate_items(items: Array, inventory: Dictionary) -> String:
	if items.is_empty():
		return "奖励条目为空"
	for item in items:
		if not item is Dictionary:
			return "奖励条目必须为字典"
		if typeof(item.get("kind")) != TYPE_STRING or not inventory.has(item.kind):
			return "奖励包含未注册道具"
		if typeof(item.get("count")) != TYPE_INT or int(item.count) <= 0:
			return "奖励数量必须为正整数"
	return ""


## 在待领奖励数组中按 uid 找下标；返回 -1 表示不存在，不改变队列。
func _find(entries: Array, uid: int) -> int:
	for index in entries.size():
		if int(entries[index].get("uid", -1)) == uid:
			return index
	return -1


## 生成统一失败结果；status 同时作为操作错误码，调用方据此决定提示或重试。
func _failure(status: String, message: String) -> Dictionary:
	return Result.failure(status, message, {"status": status})


## 校验入口按有无策略分流，返回空串或具体拒绝原因。
## 注入策略必须保持纯候选计算，不允许执行 UI、SDK、写盘或重入真实业务提交。
func _validate_award_items(items: Array, candidate: Dictionary) -> String:
	if _item_policy != null:
		return _item_policy.validate_award(items, candidate)
	return validate_items(items, candidate.get("inventory", {}))
