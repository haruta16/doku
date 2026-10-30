## 通关文案策略入口：按实验选择实现，统一返回标题、正文及已展示百分比。
class_name PassTextStrategy
extends RefCounted


## 按当前文案实验创建具体策略，未识别分组回退到第三版第一组。
static func create() -> PassTextStrategy:
	match ABTestManager.pass_text.value():
		PassTextConfig.VALUE_V3_G1:
			return PassTextStrategyV3G1.new()
		PassTextConfig.VALUE_V4_G1:
			return PassTextStrategyV4G1.new()
		PassTextConfig.VALUE_V4_G2:
			return PassTextStrategyV4G2.new()
		PassTextConfig.VALUE_V4_G3:
			return PassTextStrategyV4G3.new()
		_:
			return PassTextStrategyV3G1.new()


## 定义统一返回字段；基础实现留空，由具体策略提供文案。
func get_win_text(_level_config: Dictionary) -> Dictionary:
	return {"title": "", "body": "", "body_key": "", "shown_percent": -1.0}
