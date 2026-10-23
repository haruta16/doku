## 回流日期换算：优先使用服务端时间，加时区偏移后按自然日计算离线天数。
class_name ReturneeClock
extends RefCounted


## 选择服务端日期；服务端秒数为负时使用调用方提供的本地日期。
static func current_date(server_unix_sec: int, timezone_minutes: int, local_date: String) -> String:
	if server_unix_sec < 0:
		return local_date
	return date_at(server_unix_sec, timezone_minutes)


## 把 Unix 秒数加上以分钟为单位的时区偏移，生成年月日字符串。
static func date_at(unix_sec: int, timezone_minutes: int) -> String:
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(unix_sec + timezone_minutes * 60)
	return "%d-%02d-%02d" % [date.year, date.month, date.day]


## 计算两个日期相隔的自然日；缺失日期或倒退时间都返回零。
static func day_gap(previous: String, current: String) -> int:
	if previous.is_empty() or current.is_empty():
		return 0
	return maxi(0, _jdn(current) - _jdn(previous))


## 把年月日换算为儒略日序号，供跨月、跨年日期相减。
static func _jdn(date_string: String) -> int:
	var parts: PackedStringArray = date_string.split("-")
	if parts.size() != 3:
		return 0
	var year: int = int(parts[0])
	var month: int = int(parts[1])
	var day: int = int(parts[2])
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
