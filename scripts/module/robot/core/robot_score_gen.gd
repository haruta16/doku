## 机器人初始得分生成算法；从玩家上一期表现计算基准分，再生成目标分数、得分片段与时间分布。

class_name RobotScoreGen
extends RefCounted


## 按上一期分数、名次系数与上下限计算本期参考分，决定对手强度的大致量级。
static func player_base(s_prev: int, prev_rank: int, cfg: RobotConfig) -> int:
	var alpha: float = alpha_for_rank(prev_rank, cfg)
	var raw: float = float(s_prev) * (1.0 + alpha)
	return int(max(float(cfg.base_floor), min(raw, float(cfg.ceiling))))


static func alpha_for_rank(rank: int, cfg: RobotConfig) -> float:
	if rank <= 1:
		return cfg.alpha_first
	if rank <= 10:
		return cfg.alpha_top10
	if rank <= 30:
		return cfg.alpha_top30
	return cfg.alpha_rest


static func bot_final_score(x_base: int, cfg: RobotConfig, rng: RandomNumberGenerator) -> int:
	var r: float = pow(rng.randf(), cfg.rand_power)
	return cfg.bot_offset + int(round(float(x_base) * r))


static func top_score(x_base: int, cfg: RobotConfig, rng: RandomNumberGenerator) -> int:
	var lo: int = int(round(float(x_base) * cfg.top_score_ratio_min))
	var hi: int = int(round(float(x_base) * cfg.top_score_ratio_max))
	if lo > hi:
		var t: int = lo
		lo = hi
		hi = t
	return rng.randi_range(lo, hi)


static func bottom_score(cfg: RobotConfig, rng: RandomNumberGenerator) -> int:
	var lo: int = cfg.bottom_score_min
	var hi: int = cfg.bottom_score_max
	if lo > hi:
		var t: int = lo
		lo = hi
		hi = t
	return rng.randi_range(lo, hi)


static func ranked_score(s_f: int, s_l: int, index: int, total: int, cfg: RobotConfig) -> int:
	if index <= 0:
		return s_f
	if index >= total - 1:
		return s_l
	var t: float = pow(float(index + 1) / float(total), cfg.rank_density)
	return int(round(float(s_f) - float(s_f - s_l) * t))


## 把目标分拆成可分时发放的得分片段，为后续时间分布提供输入。
static func score_array(x_bot: int, cfg: RobotConfig, rng: RandomNumberGenerator) -> Array[int]:
	match cfg.array_strategy:
		"closest_approach":
			return _array_closest_approach(x_bot, cfg, rng)
		"fill_to_zero":
			return _array_fill_to_zero(x_bot, cfg, rng)
		_:
			push_error("RobotScoreGen: array_strategy=%s 未实现" % cfg.array_strategy)
			return []


static func _array_closest_approach(
	x_bot: int, cfg: RobotConfig, rng: RandomNumberGenerator
) -> Array[int]:
	var arr: Array[int] = []
	var s_cur: int = 0
	while true:
		var v: int = _weighted_pick(cfg.arr_values, cfg.arr_weights, rng)
		if s_cur + v <= x_bot:
			arr.append(v)
			s_cur += v
		else:
			var before: int = abs(x_bot - s_cur)
			var after: int = abs(x_bot - (s_cur + v))
			if after < before:
				arr.append(v)
			break
	_shuffle_int(arr, rng)
	return arr


static func _array_fill_to_zero(
	x_bot: int, cfg: RobotConfig, rng: RandomNumberGenerator
) -> Array[int]:
	var arr: Array[int] = []
	var r: int = x_bot
	while r > 0:
		var v: int
		if r >= 3:
			v = _weighted_pick(cfg.arr_values, cfg.arr_weights, rng)
		elif r == 2:
			v = 2
		else:
			v = 1
		arr.append(v)
		r -= v
	_shuffle_int(arr, rng)
	return arr


## 按照配置的时间段和权重，把得分片段放入相对活动起点的时间线。
static func distribute_timeline(
	arr: Array[int], cfg: RobotConfig, rng: RandomNumberGenerator
) -> Array:
	var buckets: Array = _parse_format(cfg.timeline_format, cfg.total_minutes)
	var pts: Array = []
	for i in range(arr.size()):
		var m: int
		if i < cfg.first_hour_forced_count:
			m = rng.randi_range(0, cfg.first_hour_minutes)
		else:
			m = _pick_minute(buckets, rng)
		pts.append({"min": m, "delta": arr[i]})
	pts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.min < b.min)

	for i in range(1, pts.size()):
		if pts[i].min - pts[i - 1].min < cfg.cooldown_minutes:
			pts[i].min = pts[i - 1].min + cfg.cooldown_minutes

	var n: int = pts.size()
	if n > 0 and pts[n - 1].min >= cfg.total_minutes:
		pts[n - 1].min = cfg.total_minutes - 1
		for i in range(n - 2, -1, -1):
			if pts[i + 1].min - pts[i].min < cfg.cooldown_minutes:
				pts[i].min = pts[i + 1].min - cfg.cooldown_minutes
	return pts


## 检查实际有得分的机器人数量并补足最低要求，避免随机分配产生过多零分对手。
static func ensure_min_scoring(robots: Array, count: int) -> void:
	var n: int = min(count, robots.size())
	for i in range(n):
		var tl: Array = robots[i].timeline
		if tl.is_empty():
			continue
		if int(tl[0].min) > 0:
			tl[0].min = 0


static func _weighted_pick(
	values: Array[int], weights: Array[float], rng: RandomNumberGenerator
) -> int:
	var total: float = 0.0
	for w in weights:
		total += w
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for i in range(values.size()):
		acc += weights[i]
		if roll <= acc:
			return values[i]
	return values[values.size() - 1]


static func _parse_format(fmt: String, total_minutes: int) -> Array:
	var out: Array = []
	var prev: int = 0
	for seg in fmt.split(",", false):
		var kv: PackedStringArray = seg.split(";")
		if kv.size() < 2:
			continue
		var end: int = kv[0].to_int()
		var weight: float = kv[1].to_float()
		out.append({"start": prev, "end": end, "weight": weight})
		prev = end
	if out.is_empty():
		out.append({"start": 0, "end": total_minutes, "weight": 1.0})
	return out


static func _pick_minute(buckets: Array, rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for b in buckets:
		total += b.weight
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for b in buckets:
		acc += b.weight
		if roll <= acc:
			return rng.randi_range(b.start, b.end)
	var last: Dictionary = buckets[buckets.size() - 1]
	return rng.randi_range(last.start, last.end)


static func _shuffle_int(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
