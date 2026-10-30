## 通用库存与奖励用例。只依赖核心存档，不访问页面、SDK 或全局单例。
class_name EconomyService
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")

var _store: RefCounted


func _init(core_store: RefCounted) -> void:
	_store = core_store


## claim_key 是业务身份，重试必须复用；空字符串表示每次都是新的一笔。
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
	var error := validate_items(items, inventory)
	if not error.is_empty() or reason.is_empty():
		return _failure("invalid_award", error if not error.is_empty() else "奖励来源不能为空")
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


## 供包含其他资格变化的业务事务使用；这里只改变候选，不写盘。
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
	var error := validate_items(items, inventory)
	if not error.is_empty():
		return _failure("invalid_award", error)
	var grants: Array = []
	var copies: int = 2 if entry.get("doubled", false) else 1
	for copy_index in copies:
		var reason: String = str(entry.get("reason", ""))
		if copy_index == 1 and not str(entry.get("bonus_reason", "")).is_empty():
			reason = str(entry.bonus_reason)
		for item: Dictionary in items:
			var kind: String = item.kind
			var amount: int = item.count
			var current: int = inventory.get(kind, 0)
			if amount > 9223372036854775807 - current:
				return _failure("overflow", "库存超过整数范围")
			inventory[kind] = current + amount
			grants.append({"kind": kind, "count": amount, "reason": reason, "balance": current + amount})
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
	pending[index]["doubled"] = true
	candidate["pending_awards"] = pending
	return _store.commit(candidate, _store.revision())


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


func _find(entries: Array, uid: int) -> int:
	for index in entries.size():
		if int(entries[index].get("uid", -1)) == uid:
			return index
	return -1


func _failure(status: String, message: String) -> Dictionary:
	return Result.failure(status, message, {"status": status})
