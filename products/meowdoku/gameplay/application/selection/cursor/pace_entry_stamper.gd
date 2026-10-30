## 节奏标记复制器：把游标排序使用的实验组与评分附到题目记录。
class_name PaceEntryStamper
extends RefCounted


## 游标带节奏组时原地写入题目节奏字段，否则不改记录。
static func try_stamp(entry: Dictionary, pos: Dictionary) -> void:
	if not pos.has("_pace_group"):
		return
	entry["_bank_pace_group"] = int(pos["_pace_group"])
	entry["_bank_pace_score"] = float(pos.get("_pace_score", 0.0))
