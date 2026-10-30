## 单个模拟对手的存档；保存身份、目标分、得分时间线以及追赶状态，供任意时刻重建分数。

class_name RobotData
extends RefCounted

var id: int = 0
var nickname: String = ""
var avatar_id: int = 0
var frame_id: int = 0
var is_first_frame: bool = false
var frame_badge: int = 0
var final_score: int = 0

var timeline: Array = []

var stalking: bool = false

var last_update_min: float = -1.0

var marked_active_unix: int = 0


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	return {
		"id": id,
		"nickname": nickname,
		"avatar_id": avatar_id,
		"frame_id": frame_id,
		"is_first_frame": is_first_frame,
		"frame_badge": frame_badge,
		"final_score": final_score,
		"timeline": timeline,
		"stalking": stalking,
		"last_update_min": last_update_min,
		"marked_active_unix": marked_active_unix,
	}


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(d: Dictionary) -> RobotData:
	var r := RobotData.new()
	r.id = int(d.get("id", 0))
	r.nickname = str(d.get("nickname", ""))
	r.avatar_id = int(d.get("avatar_id", 0))
	r.frame_id = int(d.get("frame_id", 0))
	r.is_first_frame = bool(d.get("is_first_frame", false))
	r.frame_badge = int(d.get("frame_badge", 0))
	r.final_score = int(d.get("final_score", 0))
	var tl: Array = d.get("timeline", [])
	r.timeline = []
	for pt in tl:
		var np: Dictionary = {"min": int(pt.get("min", 0)), "delta": int(pt.get("delta", 0))}
		if pt.has("ts"):
			np["ts"] = int(pt.get("ts", 0))
		if bool(pt.get("boost", false)):
			np["boost"] = true
		r.timeline.append(np)
	r.stalking = bool(d.get("stalking", false))
	r.last_update_min = float(d.get("last_update_min", -1.0))
	r.marked_active_unix = int(d.get("marked_active_unix", 0))
	return r
