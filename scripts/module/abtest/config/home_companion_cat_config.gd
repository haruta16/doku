## 实验配置 home_companion_cat：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name HomeCompanionCatConfig

const VALUE_CONTROL: int = 0
const VALUE_HALLOWEEN_REWARDS: int = 1
const VALUE_CANNED_FOOD: int = 2
const VALUE_HALLOWEEN_COSMETIC: int = 3
const VALUE_SATIETY: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "home_companion_cat"
	default_value = VALUE_CONTROL


func has_companion() -> bool:
	return has_halloween_rewards() or has_canned_food()


func has_halloween_rewards() -> bool:
	return value() == VALUE_HALLOWEEN_REWARDS


func has_canned_food() -> bool:
	return value() == VALUE_CANNED_FOOD or has_satiety()


func has_satiety() -> bool:
	return value() == VALUE_SATIETY


func is_cosmetic_only() -> bool:
	return value() == VALUE_HALLOWEEN_COSMETIC


func peek_group() -> int:
	return int(peek_value())
