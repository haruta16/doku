## 玩家得分后机器人响应的算法；抽取响应强度，规划追加的得分时点，再写入机器人的时间线。

class_name RobotBoost
extends RefCounted

const _DEFAULT_NEIGHBOR_SPAN: int = 3
const _DEFAULT_TOP_GATE: int = 5
const _DEFAULT_TOP_COUNT: int = 3

const _ROUND_EPSILON: float = 1e-06


static func roll(g: int, range_pair: Array, rng: RandomNumberGenerator) -> int:
	if g <= 0 or range_pair.size() < 2:
		return 0
	var bounds: Vector2i = roll_bounds(g, range_pair)
	if bounds.y <= 0:
		return 0
	return rng.randi_range(bounds.x, bounds.y)


static func roll_bounds(g: int, range_pair: Array) -> Vector2i:
	var low: int = maxi(0, int(floor(float(g) * float(range_pair[0]) + _ROUND_EPSILON)))
	var high: int = maxi(low, int(ceil(float(g) * float(range_pair[1]) - _ROUND_EPSILON)))
	return Vector2i(low, high)


## 按加成规则和当前排名计算各机器人的响应分数，返回计划，尚未直接修改时间线。
static func plan(
	ordered: Array,
	g: int,
	spec: Dictionary,
	excluded_ids: Array,
	skip_zero: bool,
	rng: RandomNumberGenerator,
	detail: Dictionary = {}
) -> Dictionary:
	var out: Dictionary = {}
	if g <= 0 or spec.is_empty():
		return out
	var player_index: int = -1
	for i in ordered.size():
		if ordered[i].is_player:
			player_index = i
			break
	if player_index < 0:
		return out
	var neighbor_span: int = int(spec.get("neighbor_span", _DEFAULT_NEIGHBOR_SPAN))
	var top_gate: int = int(spec.get("top_gate", _DEFAULT_TOP_GATE))
	var top_count: int = int(spec.get("top_count", _DEFAULT_TOP_COUNT))
	var a1: Array = spec.get("a1", [])
	var a2: Array = spec.get("a2", [])
	var a3: Array = spec.get("a3", [])
	var player_rank: int = player_index + 1
	for i in ordered.size():
		var entry: Dictionary = ordered[i]
		if entry.is_player:
			continue
		var robot: RobotData = entry.robot
		if excluded_ids.has(robot.id):
			continue
		var part_a1: int = 0
		var part_a2: int = 0
		var part_a3: int = 0
		if not (skip_zero and int(entry.score) <= 0):
			part_a1 = roll(g, a1, rng)

		var distance: int = absi(i - player_index)
		if distance >= 1 and distance <= neighbor_span:
			part_a2 = roll(g, a2, rng)

		if player_rank <= top_gate and i < top_count:
			part_a3 = roll(g, a3, rng)
		var amount: int = part_a1 + part_a2 + part_a3
		if amount > 0:
			out[robot.id] = amount

		var is_neighbor: bool = distance >= 1 and distance <= neighbor_span
		var is_top: bool = player_rank <= top_gate and i < top_count
		if amount > 0 or is_neighbor or is_top:
			detail[robot.id] = {
				"rank": i + 1,
				"score": int(entry.score),
				"a1": part_a1,
				"a2": part_a2,
				"a3": part_a3,
				"neighbor": is_neighbor,
				"top": is_top
			}
	return out


## 将计划中的增分追加到该机器人的时间线，并返回实际应用的分数。
static func apply_to_robot(robot: RobotData, amount: int, now_min: float, now_unix: int) -> int:
	if amount <= 0:
		return 0
	var future: Array = []
	for point in robot.timeline:
		if float(point.min) > now_min:
			future.append(point)
	future.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool: return int(left.min) < int(right.min)
	)
	var moved: int = 0
	for point in future:
		if moved >= amount:
			break
		var take: int = mini(int(point.delta), amount - moved)
		point.delta = int(point.delta) - take
		moved += take
	if moved <= 0:
		return 0

	var kept: Array = []
	for point in robot.timeline:
		if int(point.delta) > 0 or float(point.min) <= now_min:
			kept.append(point)
	kept.append({"min": int(now_min), "delta": moved, "ts": now_unix, "boost": true})
	robot.timeline = kept
	return moved
