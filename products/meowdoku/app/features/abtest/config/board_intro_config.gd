## 实验配置 board_intro：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name BoardIntroConfig

const VALUE_CONTROL: int = 0
const VALUE_PATTERN_FIRST: int = 1
const VALUE_PATTERN_SWEEP: int = 2
const VALUE_PATTERN_FIRST_RETEST: int = 3
const VALUE_PATTERN_SWEEP_RETEST: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "board_intro"
	default_value = VALUE_CONTROL


func is_enabled() -> bool:
	return value() != VALUE_CONTROL


func is_pattern_first_intro() -> bool:
	return value() == VALUE_PATTERN_FIRST or value() == VALUE_PATTERN_FIRST_RETEST


func is_pattern_sweep() -> bool:
	return value() == VALUE_PATTERN_SWEEP or value() == VALUE_PATTERN_SWEEP_RETEST
