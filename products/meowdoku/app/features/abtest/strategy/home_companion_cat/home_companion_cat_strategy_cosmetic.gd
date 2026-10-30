## 万圣节外观策略：只启用节日皮肤，不开放陪伴猫业务。
extends HomeCompanionCatStrategy
class_name HomeCompanionCatStrategyCosmetic


func business_mode() -> int:
	return System.Mode.HALLOWEEN_COSMETIC


func has_companion() -> bool:
	return false


func halloween_skin() -> bool:
	return true
