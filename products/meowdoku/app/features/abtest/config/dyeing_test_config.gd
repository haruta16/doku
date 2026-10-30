## 实验配置 dyeing_test：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DyeingTestConfig

const VALUE_SKIP_WAIT: int = 0

const VALUE_WAIT: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "dyeing_test"
	default_value = VALUE_SKIP_WAIT


static func should_skip_for_cached(cached: int) -> bool:
	return cached != VALUE_WAIT
