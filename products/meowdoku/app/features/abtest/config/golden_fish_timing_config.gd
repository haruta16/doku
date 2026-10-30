## 实验配置 golden_fish_timing：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GoldenFishTimingConfig

const VALUE_CONTROL: int = 0

const VALUE_EARLY_UNLOCK: int = 1

const VALUE_STICKY_BOOST: int = 2

const VALUE_SKIP_PENALTY: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "golden_fish_timing"
	default_value = VALUE_CONTROL


func unlock_min_level() -> int:
	if int(peek_value()) == VALUE_EARLY_UNLOCK:
		return GoldenFishGate.EARLY_UNLOCK_MIN_LEVEL
	return GoldenFishGate.INSERT_MODE_MIN_LEVEL


func uses_sticky_boost() -> bool:
	return int(peek_value()) == VALUE_STICKY_BOOST


func uses_skip_penalty() -> bool:
	return int(peek_value()) == VALUE_SKIP_PENALTY


func current_group() -> int:
	return int(peek_value())
