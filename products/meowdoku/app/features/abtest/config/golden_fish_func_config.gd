## 实验配置 golden_fish_func：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GoldenFishFuncConfig

const VALUE_CONTROL: int = 0

const VALUE_ON: int = 1

const VALUE_RANDOM: int = 2

const VALUE_RANK_ALT: int = 3

const VALUE_SIZE_UP: int = 4

const VALUE_DIFF_EXT: int = 5


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "golden_fish_func"
	default_value = VALUE_CONTROL


func is_enabled() -> bool:
	return int(peek_value()) != VALUE_CONTROL


func uses_shuffled_pick() -> bool:
	var group: int = int(value())
	return group == VALUE_RANDOM or group == VALUE_RANK_ALT


func uses_upsized_size_cycle() -> bool:
	return int(value()) == VALUE_SIZE_UP


func uses_alternating_rank() -> bool:
	return int(value()) == VALUE_RANK_ALT


func uses_random_first_rank() -> bool:
	return int(value()) == VALUE_RANK_ALT


func uses_diff_ext_rank() -> bool:
	return int(value()) == VALUE_DIFF_EXT


func current_group() -> int:
	return int(value())
