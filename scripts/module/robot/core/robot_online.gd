## 根据机器人预定得分时间线推导在线标记与空闲时间。
## 这里的“在线”是模拟对手的表现规则，不表示正在连接真实远端玩家。

class_name RobotOnline
extends RefCounted

const BOOST_ONLINE_AFTER_SEC: int = 60


static func stalk_ids(pool: RobotPool, player_score: int, elapsed_min: float) -> Array[int]:
	var ids: Array[int] = []
	if pool == null or not pool.stalk_active:
		return ids
	var cfg: RobotConfig = pool.config
	if cfg.stalk_freeze_scope == "members_only":
		for member_id in pool.stalk_member_ids:
			ids.append(int(member_id))
		return ids
	var cap: int = mini(RobotStalking.stalk_capacity(player_score, cfg), cfg.stalk_top_pool)
	if cap <= 0:
		return ids
	var scored: Array = []
	for robot in pool.robots:
		scored.append({"id": robot.id, "score": RobotRanking.robot_score_at(robot, elapsed_min)})
	scored.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool: return left.score > right.score
	)
	for i in range(mini(cap, scored.size())):
		ids.append(int(scored[i].id))
	return ids


## 计算距离下一个模拟得分时点的秒数；UI 用此值判断是否显示在线，而非查询网络连接。
static func next_score_sec(
	robot: RobotData, now_unix: int, created_unix: int, elapsed_min: float, is_stalking: bool
) -> int:
	if is_stalking:
		return 0
	var boost_unix: int = _last_boost_unix(robot)
	if boost_unix > 0 and now_unix - boost_unix <= BOOST_ONLINE_AFTER_SEC:
		return 0
	var next_unix: int = next_score_unix(robot, elapsed_min, created_unix)
	if next_unix > now_unix:
		return next_unix - now_unix
	return -1


## 根据上次得分或响应记录计算空闲时长，供“多久前活跃”文案使用。
static func idle_sec(robot: RobotData, now_unix: int, created_unix: int, elapsed_min: float) -> int:
	var last_unix: int = RobotRanking.robot_last_unix(robot, elapsed_min, created_unix)
	var active_unix: int = maxi(last_unix, robot.marked_active_unix)
	var boost_unix: int = _last_boost_unix(robot)
	if boost_unix > 0:
		active_unix = maxi(active_unix, boost_unix + BOOST_ONLINE_AFTER_SEC)
	return maxi(0, now_unix - active_unix)


static func _last_boost_unix(robot: RobotData) -> int:
	var latest: int = 0
	for point in robot.timeline:
		if point.get("boost", false):
			latest = maxi(latest, int(point.get("ts", 0)))
	return latest


static func next_score_unix(robot: RobotData, elapsed_min: float, created_unix: int) -> int:
	var best_min: int = -1
	for point in robot.timeline:
		var point_min: int = int(point.min)
		if float(point_min) <= elapsed_min:
			continue
		if best_min < 0 or point_min < best_min:
			best_min = point_min
	if best_min < 0:
		return 0
	return created_unix + best_min * 60
