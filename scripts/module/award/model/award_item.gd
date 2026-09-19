# 奖励条目数据类：kind（道具种类）+ count（数量），纯数据无逻辑
extends RefCounted
class_name AwardItem

# ---- 数据字段 ----
var kind: String = "" # 道具种类（locate / hint / undo 等）
var count: int = 0 # 数量


# 工厂方法：外部不要直接 new
static func make(p_kind: String, p_count: int) -> AwardItem:
	var it := AwardItem.new()
	it.kind = p_kind
	it.count = p_count
	return it


# 转 Dictionary，方便塞进存档与跨模块传递
func to_dict() -> Dictionary:
	return {"kind": kind, "count": count}
