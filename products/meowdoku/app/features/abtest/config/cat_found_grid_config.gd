## 实验配置 cat_found_grid：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name CatFoundGridConfig

const VALUE_OFF: int = 0
const VALUE_DIM_G1: int = 1
const VALUE_DIM_G2: int = 2

const ALPHA_NONE: float = 1.0
const ALPHA_DIM_G1: float = 0.25
const ALPHA_DIM_G2: float = 0.15

const ALPHA_NO_OVERRIDE: float = -1.0

var _cheat_alpha_override: float = ALPHA_NO_OVERRIDE


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "cat_found_grid"
	default_value = VALUE_OFF


func is_dim_enabled() -> bool:
	return int(value()) != VALUE_OFF


func dim_alpha() -> float:
	if _cheat_alpha_override >= 0.0:
		return _cheat_alpha_override
	var v: int = int(value())
	if v == VALUE_DIM_G1:
		return ALPHA_DIM_G1
	if v == VALUE_DIM_G2:
		return ALPHA_DIM_G2
	return ALPHA_NONE


func set_cheat_alpha_override(a: float) -> void:
	_cheat_alpha_override = a


func has_cheat_alpha_override() -> bool:
	return _cheat_alpha_override >= 0.0
