## 机器人算法的可控时间模拟器；继承服务但覆写时钟、随机源和持久化，以便复现一段活动过程。
## 模拟时不会读写真实 robots.cfg，适合观察玩家不同得分节奏如何影响对手追赶。

extends "res://scripts/module/robot/robot_service.gd"

var sim_unix: int = 1700000000

var player_timeline: Array = []

var board_open_minutes: Array[float] = []

var stalk_timeline: Array = []
var _stalk_touched: Array[int] = []
var _rng_inst: RandomNumberGenerator = null


## 初始化固定随机种子与模拟状态，使同一组输入可重复得到同一段机器人过程。
func begin(rng_seed: int) -> void:
	_rng_inst = RandomNumberGenerator.new()
	_rng_inst.seed = rng_seed
	_pools = {}
	_key_seq = 0
	sim_unix = 1700000000
	player_timeline = []
	board_open_minutes = []
	stalk_timeline = []
	_stalk_touched = []


## 模拟器屏蔽磁盘持久化，防止试验参数覆盖游戏中的真实活动池。
func _persist() -> void:
	pass


func _load_all() -> void:
	pass


func _now() -> int:
	return sim_unix


func _rng() -> RandomNumberGenerator:
	return _rng_inst


func open_period(cfg: RobotConfig, s_prev: int, prev_rank: int) -> String:
	return create_pool(
		cfg,
		s_prev,
		prev_rank,
		[1, 2, 3, 4, 5],
		[1, 2],
		100,
		RobotNicknamePool.NAMES,
		1,
		sim_unix + 86400
	)


## 推进模拟时钟到活动内指定分钟；时间由测试场景控制，不依赖真实等待。
func at_minute(key: String, minute: float) -> void:
	var pool: RobotPool = _pools[key]
	sim_unix = pool.created_unix + int(minute * 60.0)


## 在当前模拟时刻提交玩家得分，观察真实服务算法如何修改对手时间线。
func player_win(key: String, new_score: int) -> void:
	var pool: RobotPool = _pools[key]
	(
		player_timeline
		. append(
			{
				"min": float(sim_unix - pool.created_unix) / 60.0,
				"score": new_score,
				"unix": sim_unix,
			}
		)
	)
	var before: Dictionary = _timeline_sizes(key)
	on_player_score(key, new_score, sim_unix)
	_snapshot_stalk(key, before)


func open_board(key: String, player_score: int) -> Array:
	var pool: RobotPool = _pools[key]
	board_open_minutes.append(float(sim_unix - pool.created_unix) / 60.0)
	var before: Dictionary = _timeline_sizes(key)
	var out: Array = get_ranking(key, player_score, sim_unix, -1, true)
	_snapshot_stalk(key, before)
	return out


func _timeline_sizes(key: String) -> Dictionary:
	var out := {}
	for r: RobotData in (_pools[key] as RobotPool).robots:
		out[r.id] = r.timeline.size()
	return out


func _snapshot_stalk(key: String, before: Dictionary) -> void:
	var pool: RobotPool = _pools[key]
	for r: RobotData in pool.robots:
		if r.timeline.size() > int(before.get(r.id, 0)) and not _stalk_touched.has(r.id):
			_stalk_touched.append(r.id)
	(
		stalk_timeline
		. append(
			{
				"min": float(sim_unix - pool.created_unix) / 60.0,
				"touched": _stalk_touched.duplicate(),
				"members": pool.stalk_member_ids.duplicate(),
				"active": pool.stalk_active,
			}
		)
	)


func stalk_snapshot_at(minute: float) -> Dictionary:
	var out := {"touched": [], "members": [], "active": false}
	for e: Dictionary in stalk_timeline:
		if float(e["min"]) <= minute:
			out = e
	return out


func members_at(minute: float) -> Array[int]:
	var snap: Dictionary = stalk_snapshot_at(minute)
	var out: Array[int] = []
	for rid: int in snap["touched"] as Array:
		out.append(rid)
	for rid: int in snap["members"] as Array:
		if not out.has(rid):
			out.append(rid)
	return out


func active_at(minute: float) -> bool:
	return bool(stalk_snapshot_at(minute)["active"])


func peek_scores(key: String, minute: float) -> Array[int]:
	var pool: RobotPool = _pools[key]
	var out: Array[int] = []
	for r in pool.robots:
		out.append(RobotRanking.robot_score_at(r, minute))
	out.sort()
	out.reverse()
	return out


func player_at(minute: float) -> Dictionary:
	var out := {"score": 0, "unix": 0}
	for e: Dictionary in player_timeline:
		if float(e["min"]) <= minute:
			out["score"] = int(e["score"])
			out["unix"] = int(e["unix"])
	return out


func peek_board(key: String, minute: float) -> Array:
	var pool: RobotPool = _pools[key]
	var pa: Dictionary = player_at(minute)
	var t: int = pool.created_unix + int(minute * 60.0)
	return RobotRanking.rank(pool, t, int(pa["score"]), int(pa["unix"]), true)


func peek_player_rank(key: String, minute: float) -> int:
	var board: Array = peek_board(key, minute)
	for i in range(board.size()):
		if bool((board[i] as Dictionary).get("is_player", false)):
			return i + 1
	return -1


func peek_rank_list(
	key: String,
	minute: float,
	player_info: PlayerInfo,
	rank_awards: Array = [],
	stalk_suffix: String = "",
	stopped_suffix: String = ""
) -> Array[RankInfo]:
	var pool: RobotPool = _pools[key]
	var pa: Dictionary = player_at(minute)
	var t: int = pool.created_unix + int(minute * 60.0)
	var entries: Array = RobotRanking.rank(pool, t, int(pa["score"]), int(pa["unix"]), true)
	var snap: Dictionary = stalk_snapshot_at(minute)
	var snap_members: Array = snap["members"]
	var snap_touched: Array = snap["touched"]
	var members_only: bool = str(pool.config.stalk_freeze_scope) == "members_only"
	var out: Array[RankInfo] = []
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var ri := RankInfo.new()
		ri.rank = i + 1
		ri.score = int(e["score"])
		if bool(e.get("is_player", false)):
			ri.player_info = player_info
		else:
			var r: RobotData = e["robot"]
			var pi: PlayerInfo = _robot_to_player_info(r)
			if stalk_suffix != "":
				if snap_members.has(r.id):
					pi.nickname = "%s %s" % [pi.nickname, stalk_suffix]
				elif snap_touched.has(r.id):
					var sfx: String = stalk_suffix
					if members_only and stopped_suffix != "":
						sfx = stopped_suffix
					pi.nickname = "%s %s" % [pi.nickname, sfx]
			ri.player_info = pi
		if ri.rank - 1 < rank_awards.size():
			ri.award_id = int(rank_awards[ri.rank - 1])
		out.append(ri)
	return out


func members(key: String) -> Array[int]:
	return (_pools[key] as RobotPool).stalk_member_ids.duplicate()


func is_active(key: String) -> bool:
	return (_pools[key] as RobotPool).stalk_active


func x_base(key: String) -> int:
	return (_pools[key] as RobotPool).x_base
