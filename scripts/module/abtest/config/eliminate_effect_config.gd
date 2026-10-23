## 实验配置 eliminate_effect：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name EliminateEffectConfig

const VALUE_LEGACY_DEFAULT: int = 0
const VALUE_LEGACY_SHRINK: int = 1
const VALUE_CONTROL: int = 2
const VALUE_CELL_SQUEEZE: int = 3
const VALUE_CROSS_BIG: int = 4
const VALUE_NEW_ART: int = 5
const VALUE_FULL: int = 6


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "eliminate_effect"
	default_value = VALUE_CONTROL


func is_experiment_group() -> bool:
	var v: int = value()
	return v == VALUE_CELL_SQUEEZE or v == VALUE_CROSS_BIG or v == VALUE_NEW_ART or v == VALUE_FULL


func is_cell_squeeze() -> bool:
	var v: int = value()
	return v == VALUE_CELL_SQUEEZE or v == VALUE_FULL


func is_cross_big() -> bool:
	var v: int = value()
	return v == VALUE_CROSS_BIG or v == VALUE_FULL


func use_new_art() -> bool:
	var v: int = value()
	return v == VALUE_NEW_ART or v == VALUE_FULL
