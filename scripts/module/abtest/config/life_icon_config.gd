# 生命条图标实验：0=爱心 1=小鱼 2=闪电；同时影响失败页标题等文案分支
extends AbConfigBase
class_name LifeIconConfig

# ---- 分组取值 ----
const VALUE_HEART: int = 0 # 爱心
const VALUE_FISH: int = 1 # 小鱼
const VALUE_LIGHTNING: int = 2 # 闪电


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "life_icon"
	default_value = VALUE_FISH # 默认档：小鱼
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 是否用小鱼生命条
func is_fish_life_bar() -> bool:
	return value() == VALUE_FISH


# 是否用闪电生命条
func is_lightning_life_bar() -> bool:
	return value() == VALUE_LIGHTNING
