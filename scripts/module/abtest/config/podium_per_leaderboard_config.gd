## 实验配置 podium_per_leaderboard：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PodiumPerLeaderboardConfig

const VALUE_NO: int = 0
const VALUE_END_SOLO_PODIUM: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "podium_per_leaderboard"
	default_value = VALUE_NO


func has_end_solo_podium() -> bool:
	return value() == VALUE_END_SOLO_PODIUM
