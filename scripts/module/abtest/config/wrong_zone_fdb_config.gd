## 实验配置 wrong_zone_fdb：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name WrongZoneFdbConfig

const VALUE_CONTROL: int = 0
const VALUE_HIGHLIGHT: int = 1
const VALUE_GOOD_EYE: int = 2
const VALUE_HIGHLIGHT_GOOD_EYE: int = 3
const VALUE_PROGRESS_SLOT_MARK: int = 4


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "wrong_zone_fdb"
	default_value = VALUE_CONTROL


func should_highlight_zone() -> bool:
	var group: int = int(value())
	return group == VALUE_HIGHLIGHT or group == VALUE_HIGHLIGHT_GOOD_EYE


func should_show_good_eye() -> bool:
	var group: int = int(value())
	return group == VALUE_GOOD_EYE or group == VALUE_HIGHLIGHT_GOOD_EYE


func should_mark_progress_slot() -> bool:
	return int(value()) == VALUE_PROGRESS_SLOT_MARK
