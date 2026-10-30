## 实验配置 streak_protect：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name StreakProtectConfig

const VALUE_CONTROL: int = 0
const VALUE_NUMBER_ROLL: int = 1
const VALUE_BACKFILL_1: int = 2
const VALUE_BACKFILL_2: int = 3
const VALUE_RESUME: int = 4

const REVIVE_MAX_DAYS_BASELINE: int = 1


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "streak_protect"
	default_value = VALUE_BACKFILL_1
