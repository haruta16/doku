# 普通关残局存档实验：0=关（退出即丢当前进度） 1=开（退出后可从残局继续）
extends AbConfigBase
class_name NormalEndgameSaveConfig

# ---- 分组取值 ----
const VALUE_OFF: int = 0 # 不保存残局
const VALUE_ON: int = 1 # 保存残局，允许恢复


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "normal_endgame_save"
	default_value = VALUE_ON # 默认档：开启存档
	timing = ABTestManager.TIMING_GAME_START_NORMAL # 染色时机：普通模式开局时


# 是否启用残局存档
func is_enabled() -> bool:
	return value() == VALUE_ON
