## 实验配置 leaderboard_anim：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name LeaderboardAnimConfig

const VALUE_CONTROL: int = 0
const VALUE_FAST_FORWARD: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "leaderboard_anim"
	default_value = VALUE_CONTROL


func is_fast_forward_enabled() -> bool:
	return value() == VALUE_FAST_FORWARD
