# 开屏 banner 的尺寸白名单：按「存活天数」分段，规定该阶段哪些棋盘尺寸可以展示 banner
extends AbConfigBase
class_name BannerUnlockDiffLcConfig

# ---- 分段配置：每段取值 no / all / yes / 逗号分隔的尺寸列表 ----
const VALUE_DEFAULT: String = "{all}" # 默认方案：所有尺寸都允许

# ---- 解析缓存：正则只编译一次 ----
var _seg_regex: RegEx = null # 匹配 {...} 片段的正则


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "banner_unlock_diff_lc"
	default_value = VALUE_DEFAULT # 默认档：全尺寸允许
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 当前存活天数分段下，该棋盘尺寸是否允许展示 banner；段数不匹配时用第 0 段
func is_unlocked_for_size(size: int) -> bool:
	var segs: Array = _parse_segments()
	if segs.is_empty():
		return true
	var idx: int = ABTestManager.living_days.current_segment_index()
	var pick_idx: int = (
		idx
		if (
			idx >= 0
			and segs.size() == ABTestManager.living_days.segment_count()
			and idx < segs.size()
		)
		else 0
	)
	return _size_allowed(segs[pick_idx], size)


# 解析单段：no=全禁，all/yes=全放，否则按逗号分隔的尺寸列表匹配
func _size_allowed(seg: String, size: int) -> bool:
	var s: String = seg.strip_edges().to_lower()
	if s == "no":
		return false
	if s == "all" or s == "yes":
		return true
	for part in s.split(","):
		var p: String = part.strip_edges()
		if p.is_valid_int() and p.to_int() == size:
			return true
	return false


# 解析出每段配置串，空值返回空数组（=全放行）
func _parse_segments() -> Array:
	var raw: String = str(value()).strip_edges()
	if raw.is_empty():
		return []
	if _seg_regex == null:
		_seg_regex = RegEx.new()
		_seg_regex.compile("\\{([^}]*)\\}")
	var result: Array = []
	for m: RegExMatch in _seg_regex.search_all(raw):
		result.append(m.get_string(1).strip_edges())
	return result
