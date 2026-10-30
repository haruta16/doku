## 实验配置 blind_mod_entry：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name BlindModEntryConfig

const VALUE_SETTING_ONLY: int = 0
const VALUE_GAME_PAGE: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "blind_mod_entry"
	default_value = VALUE_SETTING_ONLY
