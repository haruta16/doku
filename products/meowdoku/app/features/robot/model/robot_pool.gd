## 一场活动的机器人池；保存活动起止时间、生成配置、玩家历史分数和追赶成员列表。

class_name RobotPool
extends RefCounted

var key: String = ""
var config: RobotConfig = null
var created_unix: int = 0
var end_unix: int = 0

var x_base: int = 0

var last_seen_unix: int = 0
var robots: Array[RobotData] = []
var player_last_score: int = 0
var player_last_unix: int = 0
var stalk_active: bool = false

var stalk_member_ids: Array[int] = []


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	var robot_dicts: Array = []
	for r in robots:
		robot_dicts.append(r.to_dict())
	return {
		"key": key,
		"config": config.to_dict() if config != null else {},
		"created_unix": created_unix,
		"end_unix": end_unix,
		"x_base": x_base,
		"last_seen_unix": last_seen_unix,
		"robots": robot_dicts,
		"player_last_score": player_last_score,
		"player_last_unix": player_last_unix,
		"stalk_active": stalk_active,
		"stalk_member_ids": stalk_member_ids,
	}


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(d: Dictionary) -> RobotPool:
	var p := RobotPool.new()
	p.key = str(d.get("key", ""))
	p.config = RobotConfig.from_dict(d.get("config", {}))
	p.created_unix = int(d.get("created_unix", 0))
	p.end_unix = int(d.get("end_unix", 0))
	p.x_base = int(d.get("x_base", 0))
	p.last_seen_unix = int(d.get("last_seen_unix", 0))
	p.robots = []
	for rd in d.get("robots", []):
		p.robots.append(RobotData.from_dict(rd))
	p.player_last_score = int(d.get("player_last_score", 0))
	p.player_last_unix = int(d.get("player_last_unix", 0))
	p.stalk_active = bool(d.get("stalk_active", false))
	p.stalk_member_ids = []
	for x in d.get("stalk_member_ids", []):
		p.stalk_member_ids.append(int(x))
	return p
