## 实验配置 swipe_logic：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name SwipeLogicConfig

const VALUE_CONTROL: int = 0
const VALUE_EXTENDED_20: int = 1

const DEFAULT_SLOP_PCT: float = 0.2

static var _dbg_slop_pct_override: float = -1.0


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "swipe_logic"
	default_value = VALUE_CONTROL


func slop_pct() -> float:
	if int(value()) != VALUE_EXTENDED_20:
		return 0.0
	return effective_slop_pct()


func is_extended() -> bool:
	return int(value()) == VALUE_EXTENDED_20


static func effective_slop_pct() -> float:
	return _dbg_slop_pct_override if _dbg_slop_pct_override > 0.0 else DEFAULT_SLOP_PCT


static func debug_set_slop_pct_override(pct: float) -> void:
	_dbg_slop_pct_override = pct


static func debug_slop_pct_is_overridden() -> bool:
	return _dbg_slop_pct_override > 0.0
