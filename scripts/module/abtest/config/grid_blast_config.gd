## 实验配置 grid_blast：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GridBlastConfig

const VALUE_CONTROL: int = 0
const VALUE_UNIFORM: int = 1
const VALUE_TIERED: int = 2

const _TIER_BOUNDS: Array[int] = [30, 60]

const _TIER_UNIFORM: int = 1

const TIER_COUNT: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "grid_blast"
	default_value = VALUE_CONTROL


func is_enabled() -> bool:
	var group: int = int(value())
	return group == VALUE_UNIFORM or group == VALUE_TIERED


func is_tiered() -> bool:
	return int(value()) == VALUE_TIERED


func blast_tier(found: int, total: int) -> int:
	if not is_enabled() or found <= 0 or total <= 0:
		return 0
	if not is_tiered():
		return _TIER_UNIFORM
	var tier: int = 1
	for bound: int in _TIER_BOUNDS:
		if found * 100 > bound * total:
			tier += 1
	return tier
