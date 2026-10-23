## 实验配置 is_vip：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name IsVipConfig

const VALUE_NO_ENTRY: int = 0
const VALUE_SETTINGS_ENTRY: int = 1
const VALUE_INTERSTITIAL: int = 2

const INTERSTITIAL_REPLACE_AT_COUNT: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "is_vip"
	default_value = VALUE_NO_ENTRY


static func entry_enabled_for(v: int) -> bool:
	return v != VALUE_NO_ENTRY


static func interstitial_replace_for(v: int) -> bool:
	return v == VALUE_INTERSTITIAL


static func replace_at_count_for(v: int, session_interstitial_count: int) -> bool:
	return (
		interstitial_replace_for(v) and session_interstitial_count == INTERSTITIAL_REPLACE_AT_COUNT
	)


func is_entry_enabled() -> bool:
	return entry_enabled_for(value())


func is_interstitial_replace_enabled() -> bool:
	return interstitial_replace_for(value())


func should_replace_interstitial_at(session_interstitial_count: int) -> bool:
	if is_debug_disabled():
		return false
	return replace_at_count_for(value(), session_interstitial_count)
