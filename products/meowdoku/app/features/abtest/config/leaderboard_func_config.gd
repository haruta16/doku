## 实验配置 leaderboard_func：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name LeaderboardFuncConfig

const VALUE_CONTROL: int = 0
const VALUE_CATS_PROP: int = 1
const VALUE_FISH_PROP: int = 2
const VALUE_CATS_FRAME_ONLY: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "leaderboard_func"
	default_value = VALUE_FISH_PROP
