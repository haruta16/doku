# 通关文案策略基类：按 AB 分组造出具体版本，并约定返回值结构
class_name PassTextStrategy
extends RefCounted


# 工厂：pass_text 分组决定版本 —— 1→V1（击败百分比）/ 2→V2（分档文案）/ 其余（含对照组）→V0
static func create() -> PassTextStrategy:
	match ABTestManager.pass_text.value():
		PassTextConfig.VALUE_BEAT_PERCENT:
			return PassTextStrategyV1.new()
		PassTextConfig.VALUE_V2:
			return PassTextStrategyV2.new()
		_:
			return PassTextStrategyV0.new()


# 基类默认实现：什么都不展示（空 title 用默认标题池，空 body 隐藏正文，-1 不产出百分比）
func get_win_text(_level_config: Dictionary) -> Dictionary:
	return {"title": "", "body": "", "shown_percent": -1.0}
