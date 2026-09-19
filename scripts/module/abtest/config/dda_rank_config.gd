# 失败降档(DDA)实验：普通关过关后是否把下一关难度降一档（strategy-1）；0=不降 1=本关重试或复活过才降 2=用过道具/复活才降 3=失败过就降
extends AbConfigBase
class_name DdaRankConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，失败不降档
const VALUE_RETRY_ONCE: int = 1 # 本关重试过或复活过才降档
const VALUE_TOOL_REVIVE: int = 2 # 用过道具或复活才降档
const VALUE_ANY_ACTION: int = 3 # 任何一次失败收场就降档


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "dda_rank"
	default_value = VALUE_CONTROL # 默认档：不降档
	timing = ABTestManager.TIMING_GAME_START_NORMAL # 染色时机：普通模式开局时


# 是否按「重试一次」降档
func is_retry_once_demote() -> bool:
	return value() == VALUE_RETRY_ONCE


# 是否按「用过道具/复活」降档
func is_tool_revive_demote() -> bool:
	return value() == VALUE_TOOL_REVIVE


# 是否任何失败动作都降档（失败结算时也会记下用过道具）
func is_any_action_demote() -> bool:
	return value() == VALUE_ANY_ACTION
