## HTTP 日期解析器：把响应 Date 的英文月份格式转换为 Unix 秒时间。
class_name HttpDate
extends RefCounted

const _MONTHS: Dictionary = {
	"Jan": 1,
	"Feb": 2,
	"Mar": 3,
	"Apr": 4,
	"May": 5,
	"Jun": 6,
	"Jul": 7,
	"Aug": 8,
	"Sep": 9,
	"Oct": 10,
	"Nov": 11,
	"Dec": 12,
}


## 解析日期各字段；月份或时间结构不符合预期时返回 -1。
static func parse_imf_fixdate(s: String) -> int:
	var parts: PackedStringArray = s.split(" ", false)
	if parts.size() < 6:
		return -1
	var mon: int = int(_MONTHS.get(parts[2], 0))
	var hms: PackedStringArray = parts[4].split(":")
	if mon == 0 or hms.size() != 3:
		return -1
	var dt: Dictionary = {
		"year": int(parts[3]),
		"month": mon,
		"day": int(parts[1]),
		"hour": int(hms[0]),
		"minute": int(hms[1]),
		"second": int(hms[2]),
	}
	return int(Time.get_unix_time_from_datetime_dict(dt))
