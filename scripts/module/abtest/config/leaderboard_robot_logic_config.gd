## 实验配置 leaderboard_robot_logic：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name LeaderboardRobotLogicConfig

const VALUE_CONTROL: int = 0
const VALUE_DT_LEGACY: int = 1
const VALUE_PRESET_SCORE: int = 2
const VALUE_STALK_OVERTAKE: int = 3
const VALUE_BOTH: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "leaderboard_robot_logic"
	default_value = VALUE_CONTROL


func is_dt_from_last_timeline_point() -> bool:
	return int(value()) == VALUE_DT_LEGACY


func is_ranked_preset_score() -> bool:
	var v: int = int(value())
	return v == VALUE_PRESET_SCORE or v == VALUE_BOTH


func is_stalk_overtake() -> bool:
	var v: int = int(value())
	return v == VALUE_STALK_OVERTAKE or v == VALUE_BOTH
