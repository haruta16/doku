## Meowdoku 资产规则：道具和头像框同一候选入账；头像框不随广告翻倍。
class_name MeowdokuAwardPolicy
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
const Catalog = preload("res://products/meowdoku/app/features/profile/model/profile_catalog.gd")
const TOOL_MAX: int = 999999 # 产品库存上限；有效奖励达到上限后只记实际增加量。
const TOOL: int = 0 # 旧奖励未带 category 时也按道具解释。
const FRAME: int = 1 # 头像框资产类别，数据存入 features.identity 而不是 inventory。


## 只读校验条目、数量与资产标识，返回空串或拒绝原因；库存累计溢出留给实际入账阶段检查。
static func validate_award(items: Array, candidate: Dictionary) -> String:
	if items.is_empty():
		return "奖励条目为空"
	for item: Variant in items:
		if not item is Dictionary or typeof(item.get("count")) != TYPE_INT or item.count <= 0:
			return "奖励条目和数量无效"
		var category: Variant = item.get("category", TOOL)
		if typeof(category) != TYPE_INT or category not in [TOOL, FRAME]:
			return "奖励类别无效"
		if category == FRAME:
			if typeof(item.get("frame_id")) != TYPE_INT or not Catalog.is_valid_frame(item.frame_id):
				return "头像框编号无效"
		elif typeof(item.get("kind")) != TYPE_STRING or not candidate.get("inventory", {}).has(item.kind):
			return "奖励包含未注册道具"
	return ""


## 回答额外一份奖励是否适用该条目；只有道具翻倍，头像框仍按基础份数领取。
func can_double(item: Dictionary) -> bool:
	return int(item.get("category", TOOL)) == TOOL


## 将一项资产写入传入候选并返回实际 grant；不写文件、不刷新 UI，reason 随回执用于归因。
## 调用方需先通过 validate_award；整笔奖励任一项失败时应丢弃整个候选。
func stage_item(candidate: Dictionary, item: Dictionary, reason: String) -> Dictionary:
	var count: int = int(item.count)
	if int(item.get("category", TOOL)) == TOOL:
		var kind: String = item.kind
		var current: int = int(candidate.inventory[kind])
		# 异常的大额旧值不可通过钳制变成零入账却消耗领取资格。
		if current > TOOL_MAX or count > 9223372036854775807 - current:
			return Result.failure("overflow", "库存累计超过允许范围")
		# 合法旧余额达到上限时只截掉超出部分；返回 count 是实际到账数，不是请求数。
		var balance: int = current + mini(count, maxi(0, TOOL_MAX - current))
		candidate.inventory[kind] = balance
		return Result.success({"grant": {"category": TOOL, "kind": kind, "count": balance - current, "reason": reason, "balance": balance}})
	var frame_id: int = int(item.frame_id)
	var identity: Dictionary = candidate.features.get("identity", {}).duplicate(true)
	var frames: Array = identity.get("owned_frames", []).duplicate(true)
	var index: int = -1
	for i: int in frames.size():
		if int(frames[i].get("id", 0)) == frame_id:
			index = i
			break
	# 首次获得头像框先补齐目录给定的初始形态/计数；已有框只累计次数，不覆盖其当前形态。
	if index < 0:
		frames.append({"id": frame_id, "acquired_count": Catalog.default_frame_count(frame_id), "form": 0})
		index = frames.size() - 1
	var before: int = maxi(0, int(frames[index].get("acquired_count", 0)))
	if count > 9223372036854775807 - before:
		return Result.failure("overflow", "头像框累计次数超过整数范围")
	frames[index]["acquired_count"] = before + count
	identity["owned_frames"] = frames
	# 从未拥有到首次拥有才点亮资料红点；同一框重复奖励不重复制造首次获得状态。
	if before == 0:
		identity["frame_red_dot"] = true
	candidate.features["identity"] = identity
	return Result.success({"grant": {"category": FRAME, "frame_id": frame_id, "kind": "frame", "count": count, "reason": reason, "balance": before + count}})
