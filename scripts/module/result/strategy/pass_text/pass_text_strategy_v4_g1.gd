## 放猫里程碑分组：启用第四版策略的当日放猫计数文案。
class_name PassTextStrategyV4G1
extends PassTextStrategyV4


## 允许当日放猫累计里程碑参与文案选择。
func _wants_cat_scene() -> bool:
	return true
