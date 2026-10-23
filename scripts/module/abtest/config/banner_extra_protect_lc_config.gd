## 实验配置 banner_extra_protect_lc：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name BannerExtraProtectLcConfig

# ---- 方案串：{...} 一段对应一个存活天数分段，段内是 ProtectScheme 方案 ----
const VALUE_DEFAULT: String = "{no}" # 默认方案：不拦截

# ---- 解析缓存：正则只编译一次 ----
var _seg_regex: RegEx = null # 匹配 {...} 片段的正则


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "banner_extra_protect_lc"
	default_value = VALUE_DEFAULT


## 取当前存活天数分段的方案求值，返回 {blocked, reason}；段数与 living_days 不一致时退回第 0 段
func eval_start_banner() -> Dictionary:
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


## 解析出每段的保护方案串，空值返回空数组（=不拦截）
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
