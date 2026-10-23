## 打卡历史造数器：校验日期与参数，生成连续、断签、跨月和旧档等测试快照。
extends RefCounted

const StreakHistory: GDScript = preload("res://scripts/module/daily_streak/core/streak_history.gd")


static func build_preset(preset: String) -> Dictionary:
	var today: String = Time.get_date_string_from_system(false)
	var today_jdn: int = _date(today)
	var arguments: Array[String] = []
	match preset:
		"first":
			arguments = ["empty"]
		"months":
			var date: Dictionary = StreakHistory.jdn_to_date(today_jdn)
			var month_start: int = StreakData.history_date_to_jdn(
				"%04d-%02d-01" % [date.year, date.month]
			)
			var ranges: String = (
				"%s..%s,%s..%s,%s..%s"
				% [
					date_string(month_start - 40),
					date_string(month_start - 38),
					date_string(month_start - 2),
					date_string(mini(month_start + 1, today_jdn)),
					date_string(today_jdn - 2),
					today
				]
			)
			arguments = ["ranges", today, "3", "3", ranges]
		_:
			return _failure("未知打卡场景：%s" % preset)
	return build(arguments)


## 校验造数类型、参数个数与日期边界，返回测试快照而不直接修改存档。
static func build(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty():
		return _failure("缺少造数类型")
	var operation: String = arguments[0]
	var expected: Dictionary = {
		"continuous": [3, 4],
		"ranges": [5, 5],
		"empty": [1, 1],
		"broken": [3, 4],
		"legacy": [4, 5],
		"pending": [5, 5]
	}
	if not expected.has(operation):
		return _failure("未知造数类型：%s" % operation)
	var counts: Array = expected[operation]
	if arguments.size() < counts[0] or arguments.size() > counts[1]:
		return _failure("%s 参数数量不正确，请使用 streak_history help" % operation)
	var today: String = Time.get_date_string_from_system(false)
	var today_jdn: int = _date(today)
	var data: Dictionary = StreakData.new().to_dict()
	if operation == "empty":
		return _success(data, today)
	var last_jdn: int = 0
	var current: int = 0
	var cycle: int = 0
	if operation == "broken":
		var missed: int = _count(arguments[1])
		current = _count(arguments[2])
		cycle = _count(arguments[3]) if arguments.size() == 4 else current
		if missed < 1:
			return _failure("missed 必须为正整数")
		last_jdn = today_jdn - missed - 1
	else:
		last_jdn = _date(arguments[1])
		current = _count(arguments[2])
		cycle = _count(arguments[3]) if arguments.size() >= 4 else current
	if (
		current < 1
		or cycle < 0
		or current > StreakData.BEST_STREAK_CAP
		or cycle > StreakData.BEST_STREAK_CAP
	):
		return _failure(
			(
				"current 为 1..%d，cycle 为 0..%d 的整数"
				% [StreakData.BEST_STREAK_CAP, StreakData.BEST_STREAK_CAP]
			)
		)
	if (
		last_jdn < StreakHistory.MIN_JDN
		or last_jdn > today_jdn
		or last_jdn - current + 1 < StreakHistory.MIN_JDN
	):
		return _failure("last 非法、晚于系统今天，或连胜倒推超出公历范围")
	data["current_streak"] = current
	data["best_streak"] = current
	data["reward_cycle_day"] = cycle
	data["last_checkin_date"] = date_string(last_jdn)
	data["last_checkin_minute"] = 600
	data["streak_start_weekday"] = (last_jdn - current + 2) % 7
	data["history_ranges"] = [[last_jdn - current + 1, last_jdn]]
	if operation == "ranges":
		var parsed: Dictionary = _ranges(arguments[4])
		if not parsed["ok"]:
			return parsed
		data["history_ranges"] = parsed["ranges"]
	elif operation == "legacy":
		data.erase("history_ranges")
	if operation == "pending" or (operation == "legacy" and arguments.size() == 5):
		var victory_jdn: int = _date(arguments[4])
		if victory_jdn <= last_jdn + 1 or victory_jdn > today_jdn:
			return _failure("待决策 D 必须晚于 last 至少两天，且不晚于系统今天")
		data["pending_win_checkin_date"] = date_string(victory_jdn)
	return _success(data, today)


static func date_string(jdn: int) -> String:
	var date: Dictionary = StreakHistory.jdn_to_date(jdn)
	if date.is_empty():
		return ""
	return "%04d-%02d-%02d" % [date["year"], date["month"], date["day"]]


static func summary(data: Dictionary, today: String) -> Dictionary:
	var ranges: Array = data.get("history_ranges", [])
	var dates: Array[String] = []
	for segment: Array in ranges:
		dates.append("%s..%s" % [date_string(segment[0]), date_string(segment[1])])
	return {
		"today": today,
		"last": data.get("last_checkin_date", ""),
		"current": data.get("current_streak", 0),
		"cycle": data.get("reward_cycle_day", 0),
		"history_present": data.has("history_ranges"),
		"ranges": dates,
		"pending_D": data.get("pending_win_checkin_date", "")
	}


static func _date(value: String) -> int:
	if value.length() != 10:
		return 0
	var jdn: int = StreakData.history_date_to_jdn(value)
	return jdn if jdn >= StreakHistory.MIN_JDN else 0


static func _count(value: String) -> int:
	if value.is_empty() or value.length() > 5:
		return -1
	for index in value.length():
		var character: int = value.unicode_at(index)
		if character < 48 or character > 57:
			return -1
	return value.to_int()


static func _ranges(value: String) -> Dictionary:
	if value == "empty":
		return {"ok": true, "ranges": []}
	var entries: PackedStringArray = value.split(",", true)
	if entries.size() > StreakHistory.MAX_HISTORY_RANGES:
		return _failure("指定段数超过上限")
	var ranges: Array = []
	for entry: String in entries:
		var endpoints: PackedStringArray = entry.split("..", true)
		if endpoints.size() < 1 or endpoints.size() > 2:
			return _failure("区间格式错误：%s" % entry)
		var start_jdn: int = _date(endpoints[0])
		var end_jdn: int = _date(endpoints[1]) if endpoints.size() == 2 else start_jdn
		if start_jdn == 0 or end_jdn == 0 or end_jdn < start_jdn:
			return _failure("非法日期或倒置区间：%s" % entry)
		ranges.append([start_jdn, end_jdn])
	return {"ok": true, "ranges": StreakHistory.normalize_ranges(ranges)}


static func _success(data: Dictionary, today: String) -> Dictionary:
	return {"ok": true, "data": data, "today": today, "summary": summary(data, today)}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
