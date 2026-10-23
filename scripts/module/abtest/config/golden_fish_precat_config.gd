## 实验配置 golden_fish_precat：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GoldenFishPrecatConfig

const VALUE_EXCLUDE_GOLDEN_FISH: int = 0
const VALUE_INCLUDE_GOLDEN_FISH: int = 1
const VALUE_ISOLATE_GOLDEN_FISH: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "golden_fish_precat"
	default_value = VALUE_EXCLUDE_GOLDEN_FISH


func uses_control_behavior() -> bool:
	return not includes_golden_fish() and not isolates_golden_fish()


func includes_golden_fish() -> bool:
	return value() == VALUE_INCLUDE_GOLDEN_FISH


func isolates_golden_fish() -> bool:
	return value() == VALUE_ISOLATE_GOLDEN_FISH
