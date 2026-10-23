## 日常互动策略：声明陪伴猫与喂食能力，其余行为沿用基类。
extends HomeCompanionCatStrategy
class_name HomeCompanionCatStrategyInteract


func business_mode() -> int:
	return System.Mode.DAILY_INTERACT


func has_companion() -> bool:
	return true


func allows_feeding() -> bool:
	return true
