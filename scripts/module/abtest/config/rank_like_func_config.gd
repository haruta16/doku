## 实验配置 rank_like_func：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RankLikeFuncConfig

const VALUE_CONTROL: int = 0
const VALUE_LIKE: int = 1
const VALUE_LIKE_AND_BARRAGE: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "rank_like_func"
	default_value = VALUE_CONTROL


func is_like_enabled() -> bool:
	return value() != VALUE_CONTROL


func has_barrage() -> bool:
	return value() == VALUE_LIKE_AND_BARRAGE
