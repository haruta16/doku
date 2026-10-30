## 实验配置 ad_compliance_ui：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name AdComplianceUiConfig

# ---- 分组取值 ----
const VALUE_HIDE: int = 0 # 完全不显示广告标识
const VALUE_SHOW: int = 1 # 显示「AD」文字角标
const VALUE_SHOW_ICON: int = 2 # 只显示广告图标
const VALUE_SHOW_ICON_TEXT: int = 3 # 图标 + 「AD」文字
const VALUE_REGION_SPLIT: int = 4 # 按地区分流：US/CA/GB/IE/AU/NZ 用文字，其余用图标


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "ad_compliance_ui"
	default_value = VALUE_SHOW_ICON
