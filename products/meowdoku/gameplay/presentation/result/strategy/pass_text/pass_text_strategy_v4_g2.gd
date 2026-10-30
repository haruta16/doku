## 画叉里程碑分组：启用第四版策略的当日画叉计数文案。
class_name PassTextStrategyV4G2
extends PassTextStrategyV4


## 允许当日画叉累计里程碑参与文案选择。
func _wants_mark_scene() -> bool:
	return true
