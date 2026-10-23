## 实验配置 near_death_fdb：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name NearDeathFdbConfig

const VALUE_CONTROL: int = 0
const VALUE_SAFE_TEXT: int = 1
const VALUE_BOUNCE_GLOW: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "near_death_fdb"
	default_value = VALUE_CONTROL


func should_show_safe_text() -> bool:
	return int(value()) == VALUE_SAFE_TEXT


func should_play_bounce_glow() -> bool:
	return int(value()) == VALUE_BOUNCE_GLOW
