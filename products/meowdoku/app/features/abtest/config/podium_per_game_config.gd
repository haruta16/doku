## 实验配置 podium_per_game：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PodiumPerGameConfig

const VALUE_NO_PODIUM: int = 0
const VALUE_TOP3_PODIUM: int = 1
const VALUE_LIST_PODIUM_STYLE: int = 2
const VALUE_TOP6_PODIUM: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "podium_per_game"
	default_value = VALUE_LIST_PODIUM_STYLE


func has_per_game_podium() -> bool:
	return value() == VALUE_TOP3_PODIUM


func podium_rank_limit() -> int:
	return 3 if value() == VALUE_TOP3_PODIUM else 0


func is_list_podium_style() -> bool:
	var v: int = value()
	return v != VALUE_NO_PODIUM and v != VALUE_TOP3_PODIUM
