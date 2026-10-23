## 实验配置 guide_eliminate：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GuideEliminateConfig

const VALUE_RELEASE_ON_UP: int = 0
const VALUE_PRESS_ALIGNED: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "guide_eliminate"
	default_value = VALUE_RELEASE_ON_UP


func is_press_aligned() -> bool:
	return value() == VALUE_PRESS_ALIGNED
