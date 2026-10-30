## 万圣节奖励策略：启用陪伴猫、节日皮肤与喂食，以 candy 作为所得货币。
extends HomeCompanionCatStrategy
class_name HomeCompanionCatStrategyRewards


func business_mode() -> int:
	return System.Mode.HALLOWEEN_REWARDS


func has_companion() -> bool:
	return true


func halloween_skin() -> bool:
	return true


func allows_feeding() -> bool:
	return true


func earned_currency() -> StringName:
	return &"candy"


func tutorial_kind() -> StringName:
	return &"halloween"
