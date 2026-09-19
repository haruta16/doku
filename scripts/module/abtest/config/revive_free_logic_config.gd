# 免费复活实验：0=对照组（复活都要消耗道具/广告） 1=第 1 关无限免费复活 2=整个账号生命周期只免费一次
extends AbConfigBase
class_name ReviveFreeLogicConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不免费
const VALUE_FIRST_LEVEL_UNLIMITED: int = 1 # 第 1 关不限次数免费复活
const VALUE_FIRST_EVER_ONCE: int = 2 # 只免费一次，用过就永久失效


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "revive_free_logic"
	default_value = VALUE_CONTROL # 默认档：不免费
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 本次失败是否可免费复活（档位 2 会读 GameState 的「已用过」标记）
func should_free_revive() -> bool:
	var v: int = value()
	match v:
		VALUE_FIRST_LEVEL_UNLIMITED:
			return GameState.get_current_level() == 1
		VALUE_FIRST_EVER_ONCE:
			return not GameState.has_used_revive_free()
		_:
			return false


# 消耗免费次数：档位 2 才写 GameState（有存档副作用）
func consume_if_needed() -> void:
	if value() == VALUE_FIRST_EVER_ONCE:
		GameState.mark_revive_free_used()
