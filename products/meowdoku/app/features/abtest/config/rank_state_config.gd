## 实验配置 rank_state：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RankStateConfig

const VALUE_HIDE: int = 0
const VALUE_WINDOW_3MIN: int = 1
const VALUE_WINDOW_5MIN: int = 2
const VALUE_WINDOW_10MIN: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rank_state"
	default_value = VALUE_HIDE


func is_enabled() -> bool:
	return value() != VALUE_HIDE


func window_sec() -> int:
	match value():
		VALUE_WINDOW_3MIN:
			return 180
		VALUE_WINDOW_5MIN:
			return 300
		VALUE_WINDOW_10MIN:
			return 600
		_:
			return 0
