## 排行榜点赞的本地结算逻辑；按名次生成模拟对手点赞和弹幕计划，活动模型记录已消费结果。
## 这些互动由本地规则生成，不是向真实玩家发送网络消息。

class_name RankLikeLogic
extends RefCounted

const MAX_PLAYER_RECEIVED_LIKES: int = 49
const MAX_NEW_PLAYER_LIKES_PER_SETTLEMENT: int = 5
const MAX_ROBOT_SELF_LIKES: int = 49
const BARRAGE_LANE_COUNT: int = 3
const BARRAGE_NEXT_DELAY_MIN_SEC: float = 1.0
const BARRAGE_NEXT_DELAY_MAX_SEC: float = 3.0


## 基于玩家名次与机器人列表生成本期互动变化，并记录结算消费状态。
static func resolve_settlement(
	data: RankLikePeriodData,
	ranked_robots: Array[Dictionary],
	rng: RandomNumberGenerator,
	allow_player_likes: bool = true
) -> Array[String]:
	var new_liker_ids: Array[String] = []
	if allow_player_likes:
		var shuffled_robots: Array[Dictionary] = ranked_robots.duplicate(true)
		_shuffle_robots(shuffled_robots, rng)
		for ranked_robot: Dictionary in shuffled_robots:
			if (
				new_liker_ids.size() >= MAX_NEW_PLAYER_LIKES_PER_SETTLEMENT
				or data.player_liker_order.size() >= MAX_PLAYER_RECEIVED_LIKES
			):
				break
			var robot_id: String = str(ranked_robot.get("id", ""))
			if robot_id.is_empty() or data.robots_liked_player_ids.has(robot_id):
				continue
			var player_liked_robot: bool = data.player_liked_robot_ids.has(robot_id)
			var robot_likes_player: bool = false
			if player_liked_robot:
				robot_likes_player = rng.randi_range(1, 100) <= player_like_probability(true)
			if not robot_likes_player:
				robot_likes_player = rng.randi_range(1, 100) <= player_like_probability(false)
			if robot_likes_player:
				data.robots_liked_player_ids[robot_id] = true
				data.player_liker_order.append(robot_id)
				new_liker_ids.append(robot_id)
	_apply_robot_self_likes(data, ranked_robots, rng)
	return new_liker_ids


## 取出待展示弹幕并标记消费，防止页面重开再次播放同一批点赞通知。
static func consume_barrage(
	data: RankLikePeriodData,
	nicknames_by_id: Dictionary,
	with_barrage: bool,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var current_like_count: int = data.player_liker_order.size()
	var snapshot_index: int = clampi(data.last_seen_player_like_count, 0, current_like_count)
	var new_liker_ids: Array[String] = []
	for index: int in range(snapshot_index, current_like_count):
		new_liker_ids.append(data.player_liker_order[index])

	data.last_seen_player_like_count = current_like_count
	if not with_barrage or new_liker_ids.is_empty():
		return []
	if new_liker_ids.size() <= 3:
		return _single_barrages(new_liker_ids, nicknames_by_id, rng)
	return _aggregate_barrage(new_liker_ids, nicknames_by_id, rng)


## 将弹幕分配到展示时间和轨道；生成计划与实际创建弹幕节点分离。
static func make_barrage_schedule(
	barrage_count: int, rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var schedule: Array[Dictionary] = []
	if barrage_count <= 0:
		return schedule
	var lane_indices: Array[int] = []
	for lane_index: int in BARRAGE_LANE_COUNT:
		lane_indices.append(lane_index)
	_shuffle_indices(lane_indices, rng)
	for barrage_index: int in barrage_count:
		if barrage_index > 0 and barrage_index % BARRAGE_LANE_COUNT == 0:
			_shuffle_indices(lane_indices, rng)
		var is_last_barrage: bool = barrage_index == barrage_count - 1
		(
			schedule
			. append(
				{
					"lane_index": lane_indices[barrage_index % BARRAGE_LANE_COUNT],
					"next_delay_sec":
					(
						0.0
						if is_last_barrage
						else rng.randf_range(BARRAGE_NEXT_DELAY_MIN_SEC, BARRAGE_NEXT_DELAY_MAX_SEC)
					),
				}
			)
		)
	return schedule


static func self_like_rule_for_rank(rank: int) -> Dictionary:
	if rank >= 1 and rank <= 3:
		return {"chance": 20, "max_add": 3}
	if rank >= 4 and rank <= 15:
		return {"chance": 10, "max_add": 2}
	if rank >= 16 and rank <= 50:
		return {"chance": 5, "max_add": 2}
	return {"chance": 0, "max_add": 0}


static func player_like_probability(player_liked_robot: bool) -> int:
	return 35 if player_liked_robot else 5


static func _apply_robot_self_likes(
	data: RankLikePeriodData, ranked_robots: Array[Dictionary], rng: RandomNumberGenerator
) -> void:
	for ranked_robot: Dictionary in ranked_robots:
		var robot_id: String = str(ranked_robot.get("id", ""))
		if robot_id.is_empty():
			continue
		var rule: Dictionary = self_like_rule_for_rank(int(ranked_robot.get("rank", 0)))
		var chance: int = int(rule["chance"])
		if chance <= 0 or rng.randi_range(1, 100) > chance:
			continue
		var current_count: int = maxi(0, int(data.robot_self_like_counts.get(robot_id, 0)))
		var added_count: int = rng.randi_range(0, int(rule["max_add"]))
		data.robot_self_like_counts[robot_id] = mini(
			MAX_ROBOT_SELF_LIKES, current_count + added_count
		)


static func _single_barrages(
	new_liker_ids: Array[String], nicknames_by_id: Dictionary, rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var shuffled_liker_ids: Array[String] = new_liker_ids.duplicate()
	_shuffle_ids(shuffled_liker_ids, rng)
	var template_indices: Array[int] = [1, 2, 3, 4, 5]
	_shuffle_indices(template_indices, rng)
	var barrages: Array[Dictionary] = []
	for barrage_index: int in shuffled_liker_ids.size():
		var robot_id: String = shuffled_liker_ids[barrage_index]
		var template_index: int = template_indices[barrage_index]
		(
			barrages
			. append(
				{
					"key": "RANK_BULLET_SINGLE_%d" % template_index,
					"args": [_nickname_for_id(robot_id, nicknames_by_id)],
				}
			)
		)
	return barrages


static func _aggregate_barrage(
	new_liker_ids: Array[String], nicknames_by_id: Dictionary, rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var shuffled_ids: Array[String] = new_liker_ids.duplicate()
	_shuffle_ids(shuffled_ids, rng)
	var template_index: int = rng.randi_range(1, 3)
	return [
		{
			"key": "RANK_BULLET_MULTIPLE_%d" % template_index,
			"args":
			[
				_nickname_for_id(shuffled_ids[0], nicknames_by_id),
				_nickname_for_id(shuffled_ids[1], nicknames_by_id),
				new_liker_ids.size() - 2,
			],
		}
	]


static func _nickname_for_id(robot_id: String, nicknames_by_id: Dictionary) -> String:
	return str(nicknames_by_id.get(robot_id, robot_id))


static func _shuffle_robots(robots: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for shuffle_index: int in range(robots.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, shuffle_index)
		var previous_robot: Dictionary = robots[shuffle_index]
		robots[shuffle_index] = robots[swap_index]
		robots[swap_index] = previous_robot


static func _shuffle_ids(robot_ids: Array[String], rng: RandomNumberGenerator) -> void:
	for shuffle_index: int in range(robot_ids.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, shuffle_index)
		var previous_robot_id: String = robot_ids[shuffle_index]
		robot_ids[shuffle_index] = robot_ids[swap_index]
		robot_ids[swap_index] = previous_robot_id


static func _shuffle_indices(indices: Array[int], rng: RandomNumberGenerator) -> void:
	for shuffle_index: int in range(indices.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, shuffle_index)
		var previous_index: int = indices[shuffle_index]
		indices[shuffle_index] = indices[swap_index]
		indices[swap_index] = previous_index
