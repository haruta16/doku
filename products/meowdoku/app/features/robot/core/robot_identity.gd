## 给本地机器人分配昵称、头像和头像框；处理名字去重、保留名及不同徽章/昵称桶的权重。

class_name RobotIdentity
extends RefCounted


## 先检查昵称池容量，再为整批机器人分配身份；可按权重桶选择来源并排除保留名字。
static func assign(
	robots: Array[RobotData],
	avatar_ids: Array,
	frame_ids: Array,
	nickname_pool: Array,
	open_period: int,
	first_place_frame_id: int,
	first_frame_badge_table: Array,
	rng: RandomNumberGenerator,
	nickname_buckets: Array = [],
	reserved_nicknames: Array = []
) -> bool:
	if robots.is_empty():
		return true

	var used_nicknames: Dictionary = {}
	for reserved_name in reserved_nicknames:
		var nickname := str(reserved_name)
		if not nickname.is_empty():
			used_nicknames[nickname] = true

	if (
		not nickname_buckets.is_empty()
		and not _has_nickname_capacity(nickname_buckets, used_nicknames, robots.size())
	):
		return false

	for robot in robots:
		if not nickname_buckets.is_empty():
			robot.nickname = _pick_nickname(nickname_buckets, used_nicknames, rng)
			if not robot.nickname.is_empty():
				used_nicknames[robot.nickname] = true
		elif not nickname_pool.is_empty():
			robot.nickname = str(nickname_pool[rng.randi_range(0, nickname_pool.size() - 1)])
		if not avatar_ids.is_empty():
			robot.avatar_id = int(avatar_ids[rng.randi_range(0, avatar_ids.size() - 1)])
		if not frame_ids.is_empty():
			robot.frame_id = int(frame_ids[rng.randi_range(0, frame_ids.size() - 1)])
		robot.is_first_frame = false
		robot.frame_badge = 0

	var first_frame_count: int = rng.randi_range(1, 3)

	var order: Array[int] = []
	for i in range(robots.size()):
		order.append(i)
	order.sort_custom(
		func(left_index: int, right_index: int) -> bool:
			return robots[left_index].final_score > robots[right_index].final_score
	)

	var chosen: Dictionary = {}
	for i in range(min(first_frame_count, order.size())):
		chosen[order[i]] = true

	var rest: Array[int] = []
	for i in order:
		if not chosen.has(i):
			rest.append(i)
	_shuffle_int(rest, rng)
	for i in range(min(first_frame_count + 2, rest.size())):
		chosen[rest[i]] = true

	for idx in chosen:
		robots[idx].is_first_frame = true
		if first_frame_badge_table.is_empty():
			robots[idx].frame_badge = rng.randi_range(1, int(max(1, open_period)))
		else:
			var bucket: Dictionary = _pick_badge_bucket(first_frame_badge_table, rng)
			robots[idx].frame_badge = rng.randi_range(
				int(bucket.get("badge_min", 1)), int(max(1, bucket.get("badge_max", 1)))
			)
		if first_place_frame_id != 0:
			robots[idx].frame_id = first_place_frame_id
	return true


static func _has_nickname_capacity(
	buckets: Array, reserved_nicknames: Dictionary, required_count: int
) -> bool:
	var has_positive_bucket := false
	for bucket in buckets:
		if int(bucket.get("weight", 0)) <= 0:
			continue
		has_positive_bucket = true
		var available_names: Dictionary = {}
		var names: Array = bucket.get("names", [])
		for name in names:
			var nickname := str(name)
			if not nickname.is_empty() and not reserved_nicknames.has(nickname):
				available_names[nickname] = true
		if available_names.size() < required_count:
			return false
	return has_positive_bucket


static func _pick_nickname(
	buckets: Array, used_nicknames: Dictionary, rng: RandomNumberGenerator
) -> String:
	var total := 0
	for bucket in buckets:
		if not bucket.get("names", []).is_empty():
			total += maxi(0, int(bucket.get("weight", 0)))
	if total <= 0:
		return ""
	var roll := rng.randi_range(1, total)
	for bucket in buckets:
		var names: Array = bucket.get("names", [])
		var weight := maxi(0, int(bucket.get("weight", 0))) if not names.is_empty() else 0
		roll -= weight
		if roll <= 0:
			var available_names: Array[String] = []
			var seen_names: Dictionary = {}
			for name in names:
				var nickname := str(name)
				if (
					not nickname.is_empty()
					and not used_nicknames.has(nickname)
					and not seen_names.has(nickname)
				):
					available_names.append(nickname)
					seen_names[nickname] = true
			if available_names.is_empty():
				return ""
			return available_names[rng.randi_range(0, available_names.size() - 1)]
	return ""


static func _pick_badge_bucket(table: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total: int = 0
	for b in table:
		total += int(b.get("weight", 0))
	if total <= 0:
		return table[0]
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	for b in table:
		acc += int(b.get("weight", 0))
		if roll <= acc:
			return b
	return table[table.size() - 1]


static func _shuffle_int(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
