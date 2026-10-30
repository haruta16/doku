## 双里程碑分组：同时允许当日放猫和画叉计数进入文案候选。
class_name PassTextStrategyV4G3
extends PassTextStrategyV4


## 允许当日放猫累计里程碑参与文案选择。
func _wants_cat_scene() -> bool:
	return true


## 允许当日画叉累计里程碑参与文案选择。
func _wants_mark_scene() -> bool:
	return true
