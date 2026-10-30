## 实验配置 leaderboard_reopen_timing：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name LeaderboardReopenTimingConfig

const VALUE_CONTROL: int = 0

const VALUE_SHORT_INTERVAL: int = 1

const VALUE_IMMEDIATE: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "leaderboard_reopen_timing"
	default_value = VALUE_CONTROL


func should_reopen_immediately() -> bool:
	return int(value()) == VALUE_IMMEDIATE


func reopen_wins() -> int:
	if should_reopen_immediately():
		return 0
	if int(value()) == VALUE_SHORT_INTERVAL:
		return 3
	return RankActivityConfig.REOPEN_WINS
