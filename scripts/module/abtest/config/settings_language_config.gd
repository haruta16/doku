## 实验配置 settings_language：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name SettingsLanguageConfig

# ---- 分组取值 ----
const VALUE_HIDE: int = 0 # 隐藏语言切换
const VALUE_POPUP: int = 1
const VALUE_DROPDOWN: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "settings_language"
	default_value = VALUE_POPUP
