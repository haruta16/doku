# 广告合规标识实验：控制「AD」标识的样式；0=不标 1=文字 2=纯图标 3=图标+文字 4=按地区分流（欧美用文字，其余用图标）
extends AbConfigBase
class_name AdComplianceUiConfig

# ---- 分组取值 ----
const VALUE_HIDE: int = 0 # 完全不显示广告标识
const VALUE_SHOW: int = 1 # 显示「AD」文字角标
const VALUE_SHOW_ICON: int = 2 # 只显示广告图标
const VALUE_SHOW_ICON_TEXT: int = 3 # 图标 + 「AD」文字
const VALUE_REGION_SPLIT: int = 4 # 按地区分流：US/CA/GB/IE/AU/NZ 用文字，其余用图标


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "ad_compliance_ui"
	default_value = VALUE_HIDE # 默认档：不显示广告标识
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否需要展示广告标识（除档位 0 外都要）
func should_show_ad_tag() -> bool:
	return value() != VALUE_HIDE


# 是否用「纯图标」样式
func should_show_ad_icon() -> bool:
	return value() == VALUE_SHOW_ICON


# 是否用「图标 + 文字」样式
func should_show_ad_icon_text() -> bool:
	return value() == VALUE_SHOW_ICON_TEXT
