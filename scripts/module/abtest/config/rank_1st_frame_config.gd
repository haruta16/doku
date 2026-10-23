## 实验配置 rank_1st_frame：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name Rank1stFrameConfig

const VALUE_CONTROL: int = 0
const VALUE_ENABLED: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rank_1st_frame"
	default_value = VALUE_CONTROL


func is_enabled() -> bool:
	return value() == VALUE_ENABLED
