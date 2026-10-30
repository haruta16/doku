## 实验配置 rate_us_pop_ui：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RateUsPopUiConfig

# ---- 分组取值 ----
const VALUE_OLD_UI: int = 0 # 旧版评分界面
const VALUE_NEW_UI: int = 1 # 新版评分界面


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rate_us_pop_ui"
	default_value = VALUE_NEW_UI
