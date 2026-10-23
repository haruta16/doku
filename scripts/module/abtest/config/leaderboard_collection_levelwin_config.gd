## 实验配置 leaderboard_collection_levelwin：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name LeaderboardCollectionLevelwinConfig

const VALUE_CONTROL: int = 0
const VALUE_EXP1: int = 1
const VALUE_EXP2: int = 2
const VALUE_EXP3: int = 3
const VALUE_EXP4: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "leaderboard_collection_levelwin"
	default_value = VALUE_CONTROL


func should_keep_life_fish() -> bool:
	return value() == VALUE_EXP3 or value() == VALUE_EXP4


func should_play_collect_before_trail() -> bool:
	return value() == VALUE_EXP3 or value() == VALUE_EXP4


func is_settle_page_flight() -> bool:
	return value() == VALUE_EXP1


func is_center_relay_flight() -> bool:
	return value() == VALUE_EXP2 or value() == VALUE_EXP4
