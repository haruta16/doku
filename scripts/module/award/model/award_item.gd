extends RefCounted
class_name AwardItem









var kind: String = ""
var count: int = 0

static func make(p_kind: String, p_count: int) -> AwardItem:
    var it: = AwardItem.new()
    it.kind = p_kind
    it.count = p_count
    return it

func to_dict() -> Dictionary:
    return {"kind": kind, "count": count}
