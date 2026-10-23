## 罐头陪伴猫策略：开放喂食，以 cans 作为通关所得货币，并使用罐头引导。
extends HomeCompanionCatStrategy
class_name HomeCompanionCatStrategyCans


func business_mode() -> int:
	return System.Mode.DAILY_CANS


func has_companion() -> bool:
	return true


func allows_feeding() -> bool:
	return true


func earned_currency() -> StringName:
	return &"cans"


func tutorial_kind() -> StringName:
	return &"cans"
