## 打卡历史区间工具：以儒略日合并连续日期，生成月历标记并限制历史区间数量。
extends RefCounted

const MIN_YEAR: int = 1
const MAX_YEAR: int = 9999
const MIN_JDN: int = 1721426
const MAX_JDN: int = 5373484
const MAX_HISTORY_RANGES: int = 1000
const INVALID_JDN: int = -1


## 过滤非法区间，排序后合并重叠或相邻日期，再在保护指定日期的前提下裁剪历史。
static func normalize_ranges(ranges: Variant, protected_jdn: int = INVALID_JDN) -> Array:
	var valid_ranges: Array = []
	if not ranges is Array:
		return valid_ranges
	for item: Variant in ranges:
		if not item is Array or item.size() != 2:
			continue
		if not item[0] is int or not item[1] is int:
			continue
		var start_jdn: int = item[0]
		var end_jdn: int = item[1]
		if not _is_valid_range(start_jdn, end_jdn):
			continue
		valid_ranges.append([start_jdn, end_jdn])
	valid_ranges.sort_custom(_range_starts_before)
	var merged_ranges: Array = []
	for interval: Array in valid_ranges:
		if merged_ranges.is_empty():
			merged_ranges.append(interval)
			continue
		var previous: Array = merged_ranges[-1]
		if interval[0] <= previous[1] + 1:
			previous[1] = maxi(previous[1], interval[1])
		else:
			merged_ranges.append(interval)
	return _trim_ranges(merged_ranges, protected_jdn)


static func add_range(
	ranges: Variant, start_jdn: int, end_jdn: int, protected_jdn: int = INVALID_JDN
) -> Array:
	var combined: Array = ranges.duplicate() if ranges is Array else []
	if _is_valid_range(start_jdn, end_jdn):
		combined.append([start_jdn, end_jdn])
	return normalize_ranges(combined, protected_jdn)


## 从最近打卡日和连签长度推导区间，补回旧存档可能缺失的历史覆盖。
static func ensure_covers_current(ranges: Variant, last_jdn: int, current_streak: int) -> Array:
	if not _is_valid_jdn(last_jdn) or current_streak <= 0:
		return normalize_ranges(ranges)
	if current_streak > last_jdn - MIN_JDN + 1:
		return normalize_ranges(ranges)
	var start_jdn: int = last_jdn - current_streak + 1
	return add_range(ranges, start_jdn, last_jdn, last_jdn)


## 将日序区间与目标月份求交，生成每天是否打卡的布尔数组。
static func build_month(ranges: Variant, year: int, month: int) -> Array[bool]:
	var flags: Array[bool] = []
	var day_count: int = days_in_month(year, month)
	if day_count == 0:
		return flags
	flags.resize(day_count)
	flags.fill(false)
	var first_jdn: int = date_to_jdn(year, month, 1)
	var last_jdn: int = first_jdn + day_count - 1
	var normalized: Array = normalize_ranges(ranges)
	for interval: Array in normalized:
		if interval[1] < first_jdn:
			continue
		if interval[0] > last_jdn:
			break
		var first_index: int = maxi(interval[0], first_jdn) - first_jdn
		var last_index: int = mini(interval[1], last_jdn) - first_jdn
		for day_index in range(first_index, last_index + 1):
			flags[day_index] = true
	return flags


static func month_range(ranges: Variant, today_year: int, today_month: int) -> Dictionary:
	if days_in_month(today_year, today_month) == 0:
		return {}
	var min_date: Dictionary = {"year": today_year, "month": today_month}
	var max_date: Dictionary = min_date.duplicate()
	var normalized: Array = normalize_ranges(ranges)
	if not normalized.is_empty():
		var earliest: Dictionary = jdn_to_date(normalized[0][0])
		var latest: Dictionary = jdn_to_date(normalized[-1][1])
		var today_index: int = today_year * 12 + today_month - 1
		if earliest["year"] * 12 + earliest["month"] - 1 < today_index:
			min_date = earliest
		if latest["year"] * 12 + latest["month"] - 1 > today_index:
			max_date = latest
	return {
		"min_year": min_date["year"],
		"min_month": min_date["month"],
		"max_year": max_date["year"],
		"max_month": max_date["month"],
	}


static func days_in_month(year: int, month: int) -> int:
	if year < MIN_YEAR or year > MAX_YEAR or month < 1 or month > 12:
		return 0
	if month == 2:
		var is_leap_year: bool = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
		return 29 if is_leap_year else 28
	if month in [4, 6, 9, 11]:
		return 30
	return 31


@warning_ignore("integer_division")
static func date_to_jdn(year: int, month: int, day: int) -> int:
	var day_count: int = days_in_month(year, month)
	if day < 1 or day > day_count:
		return INVALID_JDN
	var month_shift: int = (14 - month) / 12
	var shifted_year: int = year + 4800 - month_shift
	var shifted_month: int = month + 12 * month_shift - 3
	return (
		day
		+ (153 * shifted_month + 2) / 5
		+ 365 * shifted_year
		+ shifted_year / 4
		- shifted_year / 100
		+ shifted_year / 400
		- 32045
	)


@warning_ignore("integer_division")
static func jdn_to_date(jdn: int) -> Dictionary:
	if not _is_valid_jdn(jdn):
		return {}
	var offset: int = jdn + 32044
	var century: int = (4 * offset + 3) / 146097
	var century_day: int = offset - (146097 * century) / 4
	var year_in_century: int = (4 * century_day + 3) / 1461
	var year_day: int = century_day - (1461 * year_in_century) / 4
	var shifted_month: int = (5 * year_day + 2) / 153
	return {
		"year": 100 * century + year_in_century - 4800 + shifted_month / 10,
		"month": shifted_month + 3 - 12 * (shifted_month / 10),
		"day": year_day - (153 * shifted_month + 2) / 5 + 1,
	}


static func _is_valid_jdn(jdn: int) -> bool:
	return jdn >= MIN_JDN and jdn <= MAX_JDN


static func _is_valid_range(start_jdn: int, end_jdn: int) -> bool:
	return _is_valid_jdn(start_jdn) and _is_valid_jdn(end_jdn) and start_jdn <= end_jdn


static func _range_starts_before(left: Array, right: Array) -> bool:
	if left[0] == right[0]:
		return left[1] < right[1]
	return left[0] < right[0]


## 超过 1000 个区间时优先移除较早记录，保留包含受保护日期的区间。
static func _trim_ranges(ranges: Array, protected_jdn: int) -> Array:
	var excess: int = ranges.size() - MAX_HISTORY_RANGES
	if excess <= 0:
		return ranges
	var retained: Array = []
	for interval: Array in ranges:
		var is_protected: bool = interval[0] <= protected_jdn and protected_jdn <= interval[1]
		if excess > 0 and not is_protected:
			excess -= 1
			continue
		retained.append(interval)
	return retained
