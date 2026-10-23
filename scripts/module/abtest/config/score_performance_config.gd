## 实验配置 score_performance：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ScorePerformanceConfig

const VALUE_OFF: int = 0
const VALUE_STAGE3_ALL_SIZE: int = 1
const VALUE_STAGE5_BIG_SIZE: int = 2

const _STAGE3_BOUNDS: Array[int] = [25, 50, 75]
const _STAGE5_BOUNDS: Array[int] = [15, 30, 45, 60, 75]

const _STAGE5_MIN_BOARD_SIZE: int = 7


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "score_performance"
	default_value = VALUE_OFF


func is_enabled() -> bool:
	return value() != VALUE_OFF


func applies_to_size(board_size: int) -> bool:
	match value():
		VALUE_STAGE3_ALL_SIZE:
			return true
		VALUE_STAGE5_BIG_SIZE:
			return board_size >= _STAGE5_MIN_BOARD_SIZE
		_:
			return false


func stage_count(board_size: int) -> int:
	if not applies_to_size(board_size):
		return 0
	return _bounds_for_group().size()


func stage_for_progress(found: int, total: int) -> int:
	if total <= 0 or found <= 0:
		return 0
	if not applies_to_size(total):
		return 0
	var bounds: Array[int] = _bounds_for_group()
	var stage: int = 0
	for bound in bounds:
		if found * 100 > bound * total:
			stage += 1
	return stage


func _bounds_for_group() -> Array[int]:
	if value() == VALUE_STAGE5_BIG_SIZE:
		return _STAGE5_BOUNDS
	return _STAGE3_BOUNDS
