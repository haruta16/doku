## 一期活动内的点赞记录；保存玩家与机器人点赞状态、累计计数及结算序号，避免展示重复消费。

class_name RankLikePeriodData
extends RefCounted

var player_liked_robot_ids: Dictionary = {}
var player_liked_self: bool = false
var robot_self_like_counts: Dictionary = {}
var robots_liked_player_ids: Dictionary = {}
var player_liker_order: Array[String] = []
var last_seen_player_like_count: int = 0
var settlement_serial: int = 0
var resolved_settlement_serial: int = 0

var skip_player_like_settlement_serial: int = 0


func reset() -> void:
	player_liked_robot_ids = {}
	player_liked_self = false
	robot_self_like_counts = {}
	robots_liked_player_ids = {}
	player_liker_order = []
	last_seen_player_like_count = 0
	settlement_serial = 0
	resolved_settlement_serial = 0
	skip_player_like_settlement_serial = 0


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	return {
		"player_liked_robot_ids": player_liked_robot_ids.duplicate(),
		"player_liked_self": player_liked_self,
		"robot_self_like_counts": robot_self_like_counts.duplicate(),
		"robots_liked_player_ids": robots_liked_player_ids.duplicate(),
		"player_liker_order": player_liker_order.duplicate(),
		"last_seen_player_like_count": last_seen_player_like_count,
		"settlement_serial": settlement_serial,
		"resolved_settlement_serial": resolved_settlement_serial,
		"skip_player_like_settlement_serial": skip_player_like_settlement_serial,
	}


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(raw: Dictionary) -> RankLikePeriodData:
	var data := RankLikePeriodData.new()
	data.player_liked_robot_ids = _read_true_id_map(raw.get("player_liked_robot_ids", {}))
	data.player_liked_self = bool(raw.get("player_liked_self", false))
	data.robot_self_like_counts = _read_nonnegative_count_map(raw.get("robot_self_like_counts", {}))
	data.robots_liked_player_ids = _read_true_id_map(raw.get("robots_liked_player_ids", {}))
	data.player_liker_order = _read_id_order(raw.get("player_liker_order", []))
	data.last_seen_player_like_count = maxi(
		0, int(raw.get("last_seen_player_like_count", data.last_seen_player_like_count))
	)
	data.settlement_serial = maxi(0, int(raw.get("settlement_serial", data.settlement_serial)))
	data.resolved_settlement_serial = maxi(
		0, int(raw.get("resolved_settlement_serial", data.resolved_settlement_serial))
	)
	data.skip_player_like_settlement_serial = maxi(
		0,
		int(raw.get("skip_player_like_settlement_serial", data.skip_player_like_settlement_serial))
	)
	return data


static func _read_true_id_map(raw_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not raw_value is Dictionary:
		return result
	var raw_map: Dictionary = raw_value
	for raw_robot_id: Variant in raw_map:
		var robot_id: String = str(raw_robot_id)
		if not robot_id.is_empty() and bool(raw_map[raw_robot_id]):
			result[robot_id] = true
	return result


static func _read_nonnegative_count_map(raw_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not raw_value is Dictionary:
		return result
	var raw_map: Dictionary = raw_value
	for raw_robot_id: Variant in raw_map:
		var robot_id: String = str(raw_robot_id)
		if robot_id.is_empty():
			continue
		result[robot_id] = maxi(0, int(raw_map[raw_robot_id]))
	return result


static func _read_id_order(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	var raw_order: Array = raw_value
	for raw_robot_id: Variant in raw_order:
		var robot_id: String = str(raw_robot_id)
		if not robot_id.is_empty():
			result.append(robot_id)
	return result
