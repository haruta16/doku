extends AbConfigBase
class_name LivingDaysConfig

const VALUE_NO_SEGMENT: String = "{0,2},{2,4},{4,7},{7,inf}"

var _seg_regex: RegEx = null


func _init() -> void:
	key = "living_days"
	default_value = VALUE_NO_SEGMENT
	timing = ABTestManager.TIMING_GAME_START


func segment_count() -> int:
	return _parse_segments().size()


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


func days_since_first_open() -> int:
	return _days_since_first_open()


func _days_since_first_open() -> int:
	return ProtectScheme.days_since_first_open()
