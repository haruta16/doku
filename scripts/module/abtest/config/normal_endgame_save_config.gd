## 实验配置 normal_endgame_save：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name NormalEndgameSaveConfig

# ---- 分组取值 ----
const VALUE_OFF: int = 0 # 不保存残局
const VALUE_ON: int = 1 # 保存残局，允许恢复
const VALUE_STALE_RESTART: int = 2
const VALUE_STALE_NEW_EASIER: int = 3
const VALUE_STALE_NEW_EASIER_TWO_DAYS: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "normal_endgame_save"
	default_value = VALUE_ON


func is_enabled() -> bool:
	return value() != VALUE_OFF


func is_stale_restart_current() -> bool:
	return value() == VALUE_STALE_RESTART


func is_stale_new_easier() -> bool:
	return value() == VALUE_STALE_NEW_EASIER or value() == VALUE_STALE_NEW_EASIER_TWO_DAYS


func returnee_gap_days() -> int:
	return 2 if value() == VALUE_STALE_NEW_EASIER_TWO_DAYS else 3
