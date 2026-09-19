# 「存活天数」分段配置：把首启以来的天数切成若干段，其它实验按段取不同档位；默认 0~2 / 2~4 / 4~7 / 7+ 共 4 段
extends AbConfigBase
class_name LivingDaysConfig

# ---- 分段配置：{起始天,结束天}，结束天 inf 表示无上界 ----
const VALUE_NO_SEGMENT: String = "{0,2},{2,4},{4,7},{7,inf}" # 默认分段：4 段

# ---- 解析缓存：正则只编译一次 ----
var _seg_regex: RegEx = null # 匹配 {...} 片段的正则


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "living_days"
	default_value = VALUE_NO_SEGMENT # 默认档：4 段分段
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 分段数量；其它实验用它判断自己的方案串段数是否对齐
func segment_count() -> int:
	return _parse_segments().size()


# 当前落在第几段；取不到首启时间或没命中任何段返回 -1
func current_segment_index() -> int:
	var segs: Array = _parse_segments()
	if segs.is_empty():
		return -1
	var day: int = _days_since_first_open()
	if day < 0:
		return -1
	for i in segs.size():
		var lo: int = segs[i][0]
		var hi: int = segs[i][1]
		if day >= lo and (hi < 0 or day < hi):
			return i
	return -1


# 解析出 [起始天, 结束天] 列表；结束天为 -1 表示无上界，非法段跳过
func _parse_segments() -> Array:
	var raw: String = str(value()).strip_edges()
	if raw.is_empty():
		return []
	if _seg_regex == null:
		_seg_regex = RegEx.new()
		_seg_regex.compile("\\{([^}]*)\\}")
	var result: Array = []
	for m: RegExMatch in _seg_regex.search_all(raw):
		var parts: PackedStringArray = m.get_string(1).split(",")
		if parts.size() != 2:
			continue
		var lo_str: String = parts[0].strip_edges()
		var hi_str: String = parts[1].strip_edges()
		if not lo_str.is_valid_int():
			continue
		var hi: int
		if hi_str == "inf":
			hi = -1
		elif hi_str.is_valid_int():
			hi = hi_str.to_int()
		else:
			continue
		result.append([lo_str.to_int(), hi])
	return result


# 对外暴露：距首次启动的天数（埋点/作弊面板用）
func days_since_first_open() -> int:
	return _days_since_first_open()


# 实际转调 ProtectScheme，保证与广告保护方案的天数口径一致
func _days_since_first_open() -> int:
	return ProtectScheme.days_since_first_open()
