## 本地模拟对手服务；创建活动池、按时间计算排名、响应玩家得分，并持久化到 user://robots.cfg。
## 查询排行榜也可能推进追赶逻辑并保存变化，调用者不能把所有 get_* 都视作纯读取。

extends Node

const SAVE_PATH := "user://robots.cfg"

const _MARK_ACTIVE_MIN_STEP_SEC: int = 30

const _DUMP_SCRIPT_RANKS: Array[int] = [1, 20, 50]

const _DUMP_POINTS_PER_LINE: int = 60

const _DUMP_RULE_THICK: String = "════════════════════════════════════════"
const _DUMP_RULE_THIN: String = "  ────────────────────────────────────"

var _pools: Dictionary = {}
var _key_seq: int = 0


func _ready() -> void:
	_load_all()

	GameState.all_data_reset.connect(_reset)


func _reset() -> void:
	_pools.clear()
	_persist()


## 用上一期分数与名次计算基准，生成每个对手的目标分与时间线，再分配不重复的身份。
## 身份素材不足时返回空键且不保存；创建成功后整池持久化，重启可重建同一批对手。
func create_pool(
	config: RobotConfig,
	s_prev: int,
	prev_rank: int,
	avatar_ids: Array,
	frame_ids: Array,
	first_place_frame_id: int,
	nickname_pool: Array,
	open_period: int,
	end_unix: int,
	first_frame_badge_table: Array = [],
	nickname_buckets: Array = [],
	reserved_nicknames: Array = []
) -> String:
	var rng := _rng()
	var pool := RobotPool.new()
	pool.key = _gen_key()
	pool.config = config
	pool.created_unix = _now()
	pool.end_unix = end_unix
	pool.x_base = RobotScoreGen.player_base(s_prev, prev_rank, config)

	var ranked: bool = config.target_score_strategy == "ranked_interpolate"
	var s_f: int = 0
	var s_l: int = 0
	if ranked:
		s_f = RobotScoreGen.top_score(pool.x_base, config, rng)
		s_l = RobotScoreGen.bottom_score(config, rng)

	for i in range(config.robot_count):
		var robot := RobotData.new()
		robot.id = i
		var x_bot: int = 0
		if ranked:
			x_bot = RobotScoreGen.ranked_score(s_f, s_l, i, config.robot_count, config)
		else:
			x_bot = RobotScoreGen.bot_final_score(pool.x_base, config, rng)
		var arr := RobotScoreGen.score_array(x_bot, config, rng)
		var realized := 0
		for v in arr:
			realized += v
		robot.final_score = realized
		robot.timeline = RobotScoreGen.distribute_timeline(arr, config, rng)
		pool.robots.append(robot)

	RobotScoreGen.ensure_min_scoring(pool.robots, config.min_scoring_robots)

	var identity_assigned := RobotIdentity.assign(
		pool.robots,
		avatar_ids,
		frame_ids,
		nickname_pool,
		open_period,
		first_place_frame_id,
		first_frame_badge_table,
		rng,
		nickname_buckets,
		reserved_nicknames
	)
	if not identity_assigned:
		push_error(
			(
				"RobotService.create_pool: positive-weight nickname bucket capacity "
				+ "is insufficient for %d robots" % pool.robots.size()
			)
		)
		return ""

	_pools[pool.key] = pool
	_persist()
	return pool.key


## 把查询时刻限制在活动有效区间，先推进可能的追赶，再计算排名；查询可能写入机器人存档。
func get_ranking(
	key: String, player_score: int, player_unix: int, now: int = -1, drop_zero_robots: bool = false
) -> Array:
	var pool: RobotPool = _pools.get(key, null)
	if pool == null:
		return []
	var t: int = _effective_now(pool, now if now >= 0 else _now())
	_tick_stalking_on_query(pool, player_score, player_unix, t)
	return RobotRanking.rank(pool, t, player_score, player_unix, drop_zero_robots)


func get_player_rank(
	key: String, player_score: int, player_unix: int, now: int = -1, drop_zero_robots: bool = false
) -> int:
	var pool: RobotPool = _pools.get(key, null)
	if pool == null:
		return -1
	var t: int = _effective_now(pool, now if now >= 0 else _now())
	_tick_stalking_on_query(pool, player_score, player_unix, t)
	return RobotRanking.player_rank(pool, t, player_score, player_unix, drop_zero_robots)


## 将排序结果转换为 UI 共用 RankInfo，并附带奖励档位和模拟在线信息。
func get_rank_list(
	key: String,
	player_info: PlayerInfo,
	player_score: int,
	player_unix: int,
	rank_awards: Array = [],
	now: int = -1,
	drop_zero_robots: bool = false
) -> Array[RankInfo]:
	var pool: RobotPool = _pools.get(key, null)
	if pool == null:
		return []
	var now_unix: int = _effective_now(pool, now if now >= 0 else _now())
	_tick_stalking_on_query(pool, player_score, player_unix, now_unix)
	var entries: Array = RobotRanking.rank(
		pool, now_unix, player_score, player_unix, drop_zero_robots
	)

	var elapsed_min: float = float(now_unix - pool.created_unix) / 60.0
	var stalking_ids: Array[int] = RobotOnline.stalk_ids(pool, player_score, elapsed_min)
	var out: Array[RankInfo] = []
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var info := RankInfo.new()
		info.rank = i + 1
		info.score = int(entry.score)
		info.player_info = player_info if entry.is_player else _robot_to_player_info(entry.robot)
		if info.rank - 1 < rank_awards.size():
			info.award_id = int(rank_awards[info.rank - 1])

		if not entry.is_player:
			var robot: RobotData = entry.robot
			info.next_score_sec = RobotOnline.next_score_sec(
				robot, now_unix, pool.created_unix, elapsed_min, stalking_ids.has(robot.id)
			)
			info.idle_sec = RobotOnline.idle_sec(robot, now_unix, pool.created_unix, elapsed_min)
		out.append(info)
	return out


func _robot_to_player_info(r: RobotData) -> PlayerInfo:
	var pi := PlayerInfo.new()
	pi.nickname = r.nickname
	pi.avatar_id = r.avatar_id
	var count: int = r.frame_badge if r.is_first_frame else -1
	pi.frame = AvatarFrame.new(r.frame_id, count)
	pi.player_id = "robot_%d" % r.id
	pi.is_robot = true
	return pi


## 更新玩家最新分数；超过基准后进入追赶态，按配置冻结未来时间线或选择追赶成员，再保存变化。
func on_player_score(key: String, score: int, score_unix: int, stalk_extra: float = 0.0) -> void:
	var pool: RobotPool = _pools.get(key, null)
	if pool == null:
		return
	var cfg: RobotConfig = pool.config
	var now := _effective_now(pool, _now())
	var elapsed_min := float(now - pool.created_unix) / 60.0
	pool.player_last_score = score
	pool.player_last_unix = score_unix
	var members_only: bool = cfg.stalk_freeze_scope == "members_only"

	if not pool.stalk_active and score > pool.x_base:
		pool.stalk_active = true
		if members_only:
			_select_stalk_members(pool, score, elapsed_min)
		else:
			for r in pool.robots:
				_freeze_future(r, elapsed_min, cfg)
	elif pool.stalk_active and members_only:
		_prune_stalk_members(pool, score, elapsed_min)

	if pool.stalk_active:
		_apply_catch_up(pool, score, score_unix, elapsed_min, stalk_extra)

	_persist()


## 在尚未进入追赶态时，把本次玩家增分转成部分对手的一次性响应；已追赶时跳过以免重复叠加。
func apply_player_boost(
	key: String,
	player_score: int,
	player_unix: int,
	gain: int,
	spec: Dictionary,
	drop_zero_robots: bool = false
) -> Dictionary:
	var pool: RobotPool = _pools.get(key, null)
	if pool == null or gain <= 0 or spec.is_empty():
		return {}
	if pool.stalk_active:
		print(
			(
				"[RobotBoost] G=%d 玩家分=%d → 已进陪伴态，一次性加成跳过：a1 全体 / a2 玩家周边 / a3 榜首 都不加（追分只走上面 [RobotStalk] 的陪伴公式）"
				% [gain, player_score]
			)
		)
		return {}
	var now := _effective_now(pool, _now())
	var elapsed_min := float(now - pool.created_unix) / 60.0
	var ordered: Array = RobotRanking.rank(pool, now, player_score, player_unix, drop_zero_robots)
	var detail: Dictionary = {}
	var plan: Dictionary = RobotBoost.plan(ordered, gain, spec, [], true, _rng(), detail)
	var applied: Dictionary = {}
	for robot in pool.robots:
		if not plan.has(robot.id):
			continue
		var moved: int = RobotBoost.apply_to_robot(robot, int(plan[robot.id]), elapsed_min, now)
		if moved > 0:
			applied[robot.id] = moved
	if not applied.is_empty():
		_persist()
	_log_boost(pool, ordered, gain, spec, detail, applied)
	return applied


func _log_boost(
	pool: RobotPool,
	ordered: Array,
	gain: int,
	spec: Dictionary,
	detail: Dictionary,
	applied: Dictionary
) -> void:
	var player_rank: int = 0
	for i in ordered.size():
		if ordered[i].is_player:
			player_rank = i + 1
			break
	var span: int = int(spec.get("neighbor_span", 3))
	var top_gate: int = int(spec.get("top_gate", 5))
	var top_count: int = int(spec.get("top_count", 3))
	var lines: Array[String] = []
	(
		lines
		. append(
			(
				"[RobotBoost] G=%d 玩家第%d名 | 每只 +randi(⌊G×lo⌋, ⌈G×hi⌉)：a1 全体非0分%s  a2 玩家前后%d名%s  a3 玩家≤第%d名时前%d名%s"
				% [
					gain,
					player_rank,
					_fmt_boost_range(gain, spec.get("a1", [])),
					span,
					_fmt_boost_range(gain, spec.get("a2", [])),
					top_gate,
					top_count,
					_fmt_boost_range(gain, spec.get("a3", []))
				]
			)
		)
	)
	var names: Dictionary = {}
	for robot: RobotData in pool.robots:
		names[robot.id] = robot.nickname

	var ids: Array = detail.keys()
	ids.sort_custom(
		func(left: int, right: int) -> bool: return int(detail[left].rank) < int(detail[right].rank)
	)
	for robot_id: int in ids:
		var row: Dictionary = detail[robot_id]
		var planned: int = int(row.a1) + int(row.a2) + int(row.a3)
		var moved: int = int(applied.get(robot_id, 0))
		var roles: Array[String] = ["非陪伴"]
		if bool(row.top):
			roles.append("榜首")
		if bool(row.neighbor):
			roles.append("玩家周边")
		lines.append(
			(
				"  第%02d名 #%02d %-12s [%s] %d→%d  a1=%d a2=%d a3=%d 应加=%d 实加=+%d%s"
				% [
					int(row.rank),
					robot_id,
					str(names.get(robot_id, "?")),
					"/".join(roles),
					int(row.score),
					int(row.score) + moved,
					int(row.a1),
					int(row.a2),
					int(row.a3),
					planned,
					moved,
					"（剧本余量不足）" if moved < planned else ""
				]
			)
		)
	if ids.is_empty():
		lines.append("  无机器人拿到加成，玩家周边 / 榜首位置上也没有机器人")
	print("\n".join(lines))


static func _fmt_boost_range(gain: int, range_pair: Array) -> String:
	if range_pair.size() < 2:
		return "关"
	var bounds: Vector2i = RobotBoost.roll_bounds(gain, range_pair)
	return "[%s,%s]→%d~%d" % [str(range_pair[0]), str(range_pair[1]), bounds.x, bounds.y]


func cheat_spread_scores(key: String, top: int, gap: int) -> Dictionary:
	var pool: RobotPool = _pools.get(key, null)
	if pool == null:
		return {"ok": false}
	var n: int = pool.robots.size()
	var g: int = maxi(2, gap)
	var t: int = top if top > 0 else g * n + 1
	var preview: Array[int] = []
	for i: int in range(n):
		var r: RobotData = pool.robots[i]
		var s: int = maxi(1, t - i * g)

		r.timeline = [{"min": 0, "delta": s, "ts": pool.created_unix + i}]
		r.final_score = s
		r.stalking = false
		r.last_update_min = -1.0
		if i < 10:
			preview.append(s)
	pool.stalk_active = false
	pool.x_base = t + 1000
	_persist()
	return {"ok": true, "gap": g, "top": t, "x_base": pool.x_base, "scores": preview}


func mark_robot_active(key: String, robot_id: int, now: int = -1) -> void:
	var pool: RobotPool = _pools.get(key, null)
	if pool == null:
		return
	var stamp: int = _effective_now(pool, now if now >= 0 else _now())
	for robot in pool.robots:
		if robot.id != robot_id:
			continue
		if stamp - robot.marked_active_unix < _MARK_ACTIVE_MIN_STEP_SEC:
			return
		robot.marked_active_unix = stamp
		_persist()
		return


func is_stalking(key: String) -> bool:
	var pool: RobotPool = _pools.get(key, null)
	return pool != null and pool.stalk_active


func get_x_base(key: String) -> int:
	var pool: RobotPool = _pools.get(key, null)
	return pool.x_base if pool != null else 0


## 删除已结束或不再使用的活动池并保存；其他活动池仍保留。
func discard_pool(key: String) -> void:
	if _pools.erase(key):
		_persist()


func has_pool(key: String) -> bool:
	return _pools.has(key)


## 截断或冻结追赶切入点之后的预定得分，使后续分数由新的响应逻辑接管。
func _freeze_future(r: RobotData, elapsed_min: float, cfg: RobotConfig) -> void:
	var kept: Array = []
	var last_min: float = -1.0
	for pt in r.timeline:
		if float(pt.min) <= elapsed_min:
			kept.append(pt)
			if float(pt.min) > last_min:
				last_min = float(pt.min)
	r.timeline = kept

	if cfg.stalk_dt_from_freeze or last_min < 0.0:
		r.last_update_min = elapsed_min
	else:
		r.last_update_min = last_min


func _apply_catch_up(
	pool: RobotPool,
	player_score: int,
	player_unix: int,
	elapsed_min: float,
	stalk_extra: float = 0.0
) -> bool:
	var cfg: RobotConfig = pool.config
	var targets: Array = []

	if cfg.stalk_freeze_scope == "members_only":
		for r in pool.robots:
			if pool.stalk_member_ids.has(r.id):
				targets.append({"r": r, "s": RobotRanking.robot_score_at(r, elapsed_min)})
		targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.s > b.s)
	else:
		var cap: int = min(RobotStalking.stalk_capacity(player_score, cfg), cfg.stalk_top_pool)
		if cap <= 0:
			return false

		var scored: Array = []
		for r in pool.robots:
			scored.append({"r": r, "s": RobotRanking.robot_score_at(r, elapsed_min)})
		scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.s > b.s)
		for i in range(min(cap, scored.size())):
			targets.append(scored[i])

	if targets.is_empty():
		return false
	var rng := _rng()
	var cur_min: int = int(elapsed_min)
	var changed: bool = false

	var log_lines: Array[String] = []
	if stalk_extra > 0.0:
		(
			log_lines
			. append(
				(
					"[RobotStalk] 玩家分=%d 陪伴追赶 %d 只  Max_add=round(max(0,min(dn%+d, dt×%.1f + k×G)))  k×G=%.1f"
					% [
						player_score,
						targets.size(),
						cfg.stalk_dn_offset,
						cfg.stalk_dt_factor,
						stalk_extra
					]
				)
			)
		)
	for e: Dictionary in targets:
		var r: RobotData = e.r
		var cur: int = int(e.s)
		var dn: int = player_score - cur
		var last: float = r.last_update_min if r.last_update_min >= 0.0 else elapsed_min
		var dt: float = max(0.0, elapsed_min - last)
		var delta: int = RobotStalking.catch_up_delta(dn, dt, cfg, rng, stalk_extra)
		if stalk_extra > 0.0:
			log_lines.append(
				(
					"  #%02d %-12s [陪伴] %d→%d  dn=%d dt=%.1f Max_add=%d 实加=+%d"
					% [
						r.id,
						r.nickname,
						cur,
						cur + maxi(0, delta),
						dn,
						dt,
						RobotStalking.catch_up_max(dn, dt, cfg, stalk_extra),
						maxi(0, delta)
					]
				)
			)
		if delta <= 0:
			continue
		(
			r
			. timeline
			. append(
				{
					"min": cur_min,
					"delta": delta,
					"ts": RobotStalking.overtake_guard_unix(player_unix, cfg, rng),
				}
			)
		)
		r.stalking = true
		r.last_update_min = elapsed_min
		changed = true
	if not log_lines.is_empty():
		print("\n".join(log_lines))
	return changed


func _select_stalk_members(pool: RobotPool, player_score: int, elapsed_min: float) -> void:
	var cfg: RobotConfig = pool.config
	pool.stalk_member_ids = []
	var cap: int = mini(RobotStalking.stalk_capacity(player_score, cfg), cfg.stalk_top_pool)
	if cap <= 0:
		return
	var scored: Array = []
	for r in pool.robots:
		scored.append({"r": r, "s": RobotRanking.robot_score_at(r, elapsed_min)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.s > b.s)
	for i in range(mini(cap, scored.size())):
		var r: RobotData = scored[i].r
		pool.stalk_member_ids.append(r.id)
		_freeze_future(r, elapsed_min, cfg)


func _prune_stalk_members(pool: RobotPool, player_score: int, elapsed_min: float) -> void:
	var cfg: RobotConfig = pool.config
	var cap: int = mini(RobotStalking.stalk_capacity(player_score, cfg), cfg.stalk_top_pool)
	if pool.stalk_member_ids.size() <= cap:
		return
	var scored: Array = []
	for r in pool.robots:
		if pool.stalk_member_ids.has(r.id):
			scored.append({"id": r.id, "s": RobotRanking.robot_score_at(r, elapsed_min)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.s > b.s)
	var kept: Array[int] = []
	for i in range(mini(cap, scored.size())):
		kept.append(int(scored[i].id))
	pool.stalk_member_ids = kept


## 查询时补进追赶进度；有有效状态变化时保存，避免只在玩家得分回调里推进模拟对手。
func _tick_stalking_on_query(
	pool: RobotPool, player_score: int, player_unix: int, eff_now: int
) -> void:
	if not pool.stalk_active or not pool.config.stalk_tick_on_query:
		return
	var elapsed_min: float = float(eff_now - pool.created_unix) / 60.0
	if _apply_catch_up(pool, player_score, player_unix, elapsed_min):
		_persist()


func debug_dump(
	key: String, player_score: int, player_unix: int, now: int = -1, online_window_sec: int = 0
) -> void:
	var pool: RobotPool = _pools.get(key, null)
	if pool == null:
		push_warning("[RobotDump] 无此池 key=%s（活动未开榜？）" % key)
		return
	var cfg: RobotConfig = pool.config

	var t: int = now if now >= 0 else _now()
	if pool.end_unix > 0:
		t = mini(t, pool.end_unix)
	t = maxi(t, pool.last_seen_unix)
	var elapsed_min: float = float(t - pool.created_unix) / 60.0
	var capacity: int = RobotStalking.stalk_capacity(player_score, cfg)

	var active_cap: int = 0
	if pool.stalk_active:
		active_cap = mini(mini(capacity, cfg.stalk_top_pool), pool.robots.size())

	var companions: Array = []
	if active_cap > 0:
		var scored: Array = []
		for r: RobotData in pool.robots:
			scored.append({"r": r, "s": RobotRanking.robot_score_at(r, elapsed_min)})
		scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.s > b.s)
		for i in range(mini(active_cap, scored.size())):
			companions.append(scored[i])

	var chasing_now: int = 0
	for e: Dictionary in companions:
		if player_score - int(e.s) + cfg.stalk_dn_offset > 0:
			chasing_now += 1

	var head: Array[String] = []
	head.append(
		"[RobotDump] %s 机器人池 dump %s" % [_DUMP_RULE_THICK.left(12), _DUMP_RULE_THICK.left(12)]
	)
	head.append(
		(
			"key=%s robots=%d x_base=%d elapsed=%.1fmin  玩家 score=%d unix=%d"
			% [key, pool.robots.size(), pool.x_base, elapsed_min, player_score, player_unix]
		)
	)
	(
		head
		. append(
			(
				"x_base 公式 max(%d, min(S_prev×(1+α), %d×k))  k=%d  α[第1/2-10/11-30/31+]=%+.2f/%+.2f/%+.2f/%+.2f"
				% [
					cfg.base_floor,
					cfg.ceiling / cfg.ceiling_mult,
					cfg.ceiling_mult,
					cfg.alpha_first,
					cfg.alpha_top10,
					cfg.alpha_top30,
					cfg.alpha_rest
				]
			)
		)
	)
	head.append(
		(
			"ceiling=%d  stalk_active=%s  容量=floor((%d-%d)/%d)=%d (top_pool=%d)"
			% [
				cfg.ceiling,
				str(pool.stalk_active),
				cfg.ceiling,
				player_score,
				cfg.stalk_slot_div,
				capacity,
				cfg.stalk_top_pool
			]
		)
	)
	(
		head
		. append(
			(
				"追赶步长 策略=%s values=%s uniform_min=%d  Max_add=max(0,min(dn%+d, dt*%.1f+extra))  extra=k×G 只在玩家得分那次生效(>0 四舍五入, =0 截断)"
				% [
					cfg.stalk_delta_strategy,
					str(cfg.stalk_values),
					cfg.stalk_uniform_min,
					cfg.stalk_dn_offset,
					cfg.stalk_dt_factor
				]
			)
		)
	)
	head.append(
		"★当前陪伴名额 = %d 只   其中仍在追赶(dn%+d>0) = %d 只" % [active_cap, cfg.stalk_dn_offset, chasing_now]
	)
	if companions.is_empty():
		head.append("★当前陪伴对象: 无（未触发 / 玩家分>=ceiling → 名额=0）")
	else:
		head.append("★当前陪伴对象（按当前分降序）:")
		for e: Dictionary in companions:
			var rc: RobotData = e.r
			var dn: int = player_score - int(e.s)
			var tag: String = (
				"追赶中" if dn + cfg.stalk_dn_offset > 0 else "已到上限(dn%+d<=0)" % cfg.stalk_dn_offset
			)
			head.append(
				"  #%02d %-12s cur=%3d dn=%d [%s]" % [rc.id, rc.nickname, int(e.s), dn, tag]
			)
	print("\n".join(head))
	_dump_online_script(pool, player_score, elapsed_min, t, online_window_sec)


func _dump_online_script(
	pool: RobotPool, player_score: int, elapsed_min: float, now_unix: int, window_sec: int
) -> void:
	var scored: Array = []
	for robot: RobotData in pool.robots:
		scored.append({"r": robot, "s": RobotRanking.robot_score_at(robot, elapsed_min)})
	if scored.is_empty():
		return
	scored.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.s > right.s)
	var stalking: Array[int] = RobotOnline.stalk_ids(pool, player_score, elapsed_min)
	var window_desc: String = "%ds" % window_sec if window_sec > 0 else "0(未注入/对照组,不判在线)"

	print(
		(
			"%s\n[RobotDump] ★涨分表 & 在线判定  window=%s  活动剩余=%s  (名次=机器人池内当前分降序,不含玩家)"
			% [_DUMP_RULE_THICK, window_desc, _fmt_countdown(pool.end_unix - now_unix)]
		)
	)
	for want_rank: int in _DUMP_SCRIPT_RANKS:
		var idx: int = mini(want_rank, scored.size()) - 1
		var robot: RobotData = scored[idx].r
		var cur_score: int = int(scored[idx].s)
		var is_stalking: bool = stalking.has(robot.id)
		var next_sec: int = RobotOnline.next_score_sec(
			robot, now_unix, pool.created_unix, elapsed_min, is_stalking
		)
		var idle: int = RobotOnline.idle_sec(robot, now_unix, pool.created_unix, elapsed_min)
		var marked_desc: String = "无"
		if robot.marked_active_unix > 0:
			marked_desc = "%s前(兜底展示成在线过)" % _fmt_duration(now_unix - robot.marked_active_unix)
		var next_desc: String = "无未来落点(终态/陪伴后静止)"
		if next_sec == 0:
			next_desc = "0(陪伴中/加成后1分钟内,在线)"
		elif next_sec > 0:
			next_desc = "%s后" % _fmt_duration(next_sec)
		var verdict: String = "未判定(window=0)"
		if window_sec > 0:
			verdict = (
				"在线"
				if next_sec >= 0 and next_sec <= window_sec
				else "离线 → 显示「%s前」" % _fmt_duration(idle)
			)

		print(
			(
				"%s\n  第%02d名 #%02d %-14s cur=%3d final=%3d 陪伴=%s 外部活跃戳=%s\n    下次得分=%s  距上次活跃=%ds(%s)  → %s"
				% [
					_DUMP_RULE_THIN,
					idx + 1,
					robot.id,
					robot.nickname,
					cur_score,
					robot.final_score,
					"是" if is_stalking else "否",
					marked_desc,
					next_desc,
					idle,
					_fmt_duration(idle),
					verdict
				]
			)
		)
		for line: String in _fmt_timeline(robot, now_unix, pool.created_unix, pool.end_unix):
			print("    %s" % line)


static func _fmt_timeline(
	robot: RobotData, now_unix: int, created_unix: int, end_unix: int
) -> Array[String]:
	var out: Array[String] = []
	var points: Array = robot.timeline.duplicate()
	var total: int = points.size()
	if total == 0:
		out.append("涨分表 0 项(空)")
		return out

	var elapsed_min: float = float(now_unix - created_unix) / 60.0

	points.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("min", 0)) < int(right.get("min", 0))
	)
	var happened: Array[String] = []
	var upcoming: Array[String] = []
	for point: Dictionary in points:
		var point_min: int = int(point.get("min", 0))
		var at_unix: int = int(point.get("ts", created_unix + point_min * 60))

		var when: String = (
			_fmt_countdown(end_unix - at_unix) if end_unix > 0 else "第%d分" % point_min
		)
		var item: String = (
			"%s%s(+%d)" % ["*" if point.has("ts") else "", when, int(point.get("delta", 0))]
		)
		if float(point_min) <= elapsed_min:
			happened.append(item)
		else:
			upcoming.append(item)
	out.append(
		(
			"涨分表 %d 项(已发生 %d / 待发生 %d) 当前剩余=%s  格式 倒计时(+涨几分), 倒计时递减, * = 陪伴增量"
			% [total, happened.size(), upcoming.size(), _fmt_countdown(end_unix - now_unix)]
		)
	)
	_append_point_chunks(out, "已发生", happened)
	_append_point_chunks(out, "待发生", upcoming)
	return out


static func _append_point_chunks(out: Array[String], label: String, items: Array[String]) -> void:
	if items.is_empty():
		out.append("  %s: 无" % label)
		return
	var chunk_total: int = ceili(float(items.size()) / float(_DUMP_POINTS_PER_LINE))
	for chunk_idx: int in range(chunk_total):
		var from_idx: int = chunk_idx * _DUMP_POINTS_PER_LINE
		var part: Array[String] = items.slice(from_idx, from_idx + _DUMP_POINTS_PER_LINE)
		var suffix: String = "" if chunk_total == 1 else " (%d/%d)" % [chunk_idx + 1, chunk_total]
		out.append("  %s%s: [%s]" % [label, suffix, ",".join(part)])


static func _fmt_countdown(sec: int) -> String:
	var safe: int = maxi(0, sec)
	return "%02d:%02d:%02d" % [safe / 3600, (safe % 3600) / 60, safe % 60]


static func _fmt_duration(sec: int) -> String:
	var safe: int = maxi(0, sec)
	if safe >= 3600:
		return "%dh%02dm" % [safe / 3600, (safe % 3600) / 60]
	if safe >= 60:
		return "%dm%02ds" % [safe / 60, safe % 60]
	return "%ds" % safe


## 将全部活动池序列化到机器人配置文件；模拟器通过覆写此方法避免写入真实存档。
func _persist() -> void:
	var cfg := ConfigFile.new()
	for key: String in _pools:
		cfg.set_value(key, "data", (_pools[key] as RobotPool).to_dict())
	cfg.save(SAVE_PATH)


func _load_all() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for section: String in cfg.get_sections():
		var d: Dictionary = cfg.get_value(section, "data", {})
		if d.is_empty():
			continue
		var pool := RobotPool.from_dict(d)
		_pools[pool.key] = pool


## 约束活动池使用的时间，防止活动结束后继续累计原本只属于该周期的得分。
func _effective_now(pool: RobotPool, now_in: int) -> int:
	var eff: int = now_in
	if pool.end_unix > 0:
		eff = mini(eff, pool.end_unix)
	eff = maxi(eff, pool.last_seen_unix)
	pool.last_seen_unix = eff
	return eff


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


func _gen_key() -> String:
	_key_seq += 1
	return "rb_%d_%d" % [_now(), _key_seq]
