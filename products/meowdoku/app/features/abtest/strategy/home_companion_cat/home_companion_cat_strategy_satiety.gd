## 饱食度策略：继承罐头模式，增加饱食度能力并切换引导类型。
extends HomeCompanionCatStrategyCans
class_name HomeCompanionCatStrategySatiety


func business_mode() -> int:
	return System.Mode.SATIETY


func has_satiety() -> bool:
	return true


func tutorial_kind() -> StringName:
	return &"satiety"
