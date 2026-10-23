## 实验配置 push_sounds：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PushSoundsConfig

const VALUE_NONE: int = 0
const VALUE_G1: int = 1
const VALUE_G5: int = 5


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "push_sounds"
	default_value = VALUE_NONE


static func sound_group_for(v: int) -> int:
	if v >= VALUE_G1 and v <= VALUE_G5:
		return v
	return 0


static func sound_name_for(group: int, push_id: String) -> String:
	if group <= 0:
		return ""
	var slot: String = "noon" if push_id == "daily_noon" else "eve"
	return "push_sound_g%d_%s.wav" % [group, slot]


func sound_group() -> int:
	return sound_group_for(value())
