# 插屏的额外保护：按「存活天数」分段，每段一条保护方案串，决定该阶段是否拦截开局插屏
extends AbConfigBase
class_name InterExtraProtectLcConfig

# ---- 方案串：{...} 一段对应一个存活天数分段，段内是 ProtectScheme 方案 ----
const VALUE_DEFAULT: String = "{session_game_2}" # 默认方案：本 session 打完 2 局才放行

# ---- 解析缓存：正则只编译一次 ----
var _seg_regex: RegEx = null # 匹配 {...} 片段的正则


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "inter_extra_protect_lc"
	default_value = VALUE_DEFAULT # 默认档：本 session 满 2 局才放行
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 取当前存活天数分段的方案求值，返回 {blocked, reason}；段数与 living_days 不一致时退回第 0 段
func eval_start_interstitial() -> Dictionary:
	var schemes: Array = _parse_schemes()
	if schemes.is_empty():
		return {"blocked": false, "reason": ""}
	var idx: int = ABTestManager.living_days.current_segment_index()
	var pick_idx: int = (
		idx
		if (
			idx >= 0
			and schemes.size() == ABTestManager.living_days.segment_count()
			and idx < schemes.size()
		)
		else 0
	)
	return ProtectScheme.eval_scheme(schemes[pick_idx])


# 解析出每段的保护方案串，空值返回空数组（=不拦截）
func _parse_schemes() -> Array:
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
