## 实验配置 win_encourage：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name WinEncourageConfig

const VALUE_OFF: int = 0
const VALUE_PERFECT: int = 1
const VALUE_FULL_HP: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "win_encourage"
	default_value = VALUE_OFF


func is_enabled() -> bool:
	return int(value()) != VALUE_OFF


func should_show_win_encourage(is_perfect_win: bool, is_full_hp_win: bool) -> bool:
	match int(value()):
		VALUE_PERFECT:
			return is_perfect_win
		VALUE_FULL_HP:
			return is_full_hp_win
		_:
			return false
