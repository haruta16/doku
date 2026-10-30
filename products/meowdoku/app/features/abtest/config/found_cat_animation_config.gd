## 实验配置 found_cat_animation：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name FoundCatAnimationConfig

const VALUE_CONTROL: int = 0
const VALUE_BLINK_ALL: int = 1
const VALUE_NEW_ANIM: int = 2
const VALUE_BLINK_ALL_PLUS_NEW_WIN: int = 3
const VALUE_SIGH_ALL_ON_WRONG: int = 4

const NEW_FOUND_ANIM_NAME: String = "Appear_heart"


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "found_cat_animation"
	default_value = VALUE_CONTROL


func should_blink_all_found() -> bool:
	var group: int = int(value())
	return group == VALUE_BLINK_ALL or group == VALUE_BLINK_ALL_PLUS_NEW_WIN


func single_found_anim_name() -> String:
	return NEW_FOUND_ANIM_NAME if int(value()) == VALUE_NEW_ANIM else ""


func win_replay_anim_name() -> String:
	var group: int = int(value())
	if group == VALUE_NEW_ANIM or group == VALUE_BLINK_ALL_PLUS_NEW_WIN:
		return NEW_FOUND_ANIM_NAME
	return ""


func should_sigh_all_on_wrong() -> bool:
	return int(value()) == VALUE_SIGH_ALL_ON_WRONG
