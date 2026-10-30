## 实验配置 inter_cd_lc：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name InterCdLcConfig

# ---- 分段配置：{秒数},{秒数},... 每段对应一个存活天数分段 ----
const VALUE_DEFAULT: String = "{60}" # 默认方案：一律 60 秒

# ---- 解析缓存：正则只编译一次 ----
var _seg_regex: RegEx = null # 匹配 {...} 片段的正则


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "inter_cd_lc"
	default_value = VALUE_DEFAULT


## 取当前存活天数分段的冷却秒数；段数不匹配用第 0 段，解析不出时兜底 60 秒
func get_cd_sec() -> int:
	var vals: Array = _parse_values()
	if vals.is_empty():
		return 60
	var idx: int = ABTestManager.living_days.current_segment_index()
	if idx >= 0 and vals.size() == ABTestManager.living_days.segment_count() and idx < vals.size():
		return vals[idx]
	return vals[0]


## 解析每段的整数秒，非数字段直接跳过
func _parse_values() -> Array:
	var raw: String = str(value()).strip_edges()
	if raw.is_empty():
		return []
	if _seg_regex == null:
		_seg_regex = RegEx.new()
		_seg_regex.compile("\\{([^}]*)\\}")
	var result: Array = []
	for m: RegExMatch in _seg_regex.search_all(raw):
		var inner: String = m.get_string(1).strip_edges()
		if inner.is_valid_int():
			result.append(inner.to_int())
	return result
