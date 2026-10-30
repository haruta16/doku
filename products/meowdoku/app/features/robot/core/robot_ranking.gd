## 本地排行榜计算；把时间线截到查询时刻得到机器人分数，再与玩家分数一起排序。

class_name RobotRanking
extends RefCounted


## 只累计查询时刻之前的时间线片段；未来预定分数尚未算入当前排行。
static func robot_score_at(robot: RobotData, elapsed_min: float) -> int:
	var s: int = 0
	for pt in robot.timeline:
		if float(pt.min) <= elapsed_min:
			s += int(pt.delta)
	return s


static func robot_last_unix(robot: RobotData, elapsed_min: float, created_unix: int) -> int:
	var best_min: int = -1
	var best_ts: int = created_unix
	for pt in robot.timeline:
		if pt.get("boost", false):
			continue
		var m: int = int(pt.min)
		if float(m) <= elapsed_min and m >= best_min:
			best_min = m
			best_ts = int(pt.get("ts", created_unix + m * 60))
	return best_ts


## 组合本机玩家与机器人当前分数并排序；同时保留同分时需要的时间信息。
static func rank(
	pool: RobotPool,
	now_unix: int,
	player_score: int,
	player_unix: int,
	drop_zero_robots: bool = false
) -> Array:
	var elapsed_min: float = float(now_unix - pool.created_unix) / 60.0
	var entries: Array = []
	for r in pool.robots:
		var rs: int = robot_score_at(r, elapsed_min)
		if drop_zero_robots and rs <= 0:
			continue
		(
			entries
			. append(
				{
					"is_player": false,
					"robot": r,
					"score": rs,
					"ts_unix": robot_last_unix(r, elapsed_min, pool.created_unix),
				}
			)
		)
	(
		entries
		. append(
			{
				"is_player": true,
				"robot": null,
				"score": player_score,
				"ts_unix": player_unix,
			}
		)
	)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.score != b.score:
				return a.score > b.score
			return a.ts_unix < b.ts_unix
	)
	return entries


static func player_rank(
	pool: RobotPool,
	now_unix: int,
	player_score: int,
	player_unix: int,
	drop_zero_robots: bool = false
) -> int:
	var entries: Array = rank(pool, now_unix, player_score, player_unix, drop_zero_robots)
	for i in range(entries.size()):
		if entries[i].is_player:
			return i + 1
	return entries.size()
