# 错标表情实验：玩家标错时猫摆哪张脸；0=懊恼 1=惊讶 2=流泪 3=只摇头
extends AbConfigBase
class_name ErrorCatfaceConfig

# ---- 分组取值 ----
const VALUE_FRUSTRATED: int = 0 # 懊恼
const VALUE_SURPRISED: int = 1 # 惊讶
const VALUE_TEARFUL: int = 2 # 流泪
const VALUE_SHAKE_ONLY: int = 3 # 只摇头，不换脸

# 档位 → AnimationPlayer 里的动画名
const _ANIM_BY_VALUE: Dictionary = {
	VALUE_FRUSTRATED: &"CatIconFrustrated",
	VALUE_SURPRISED: &"CatIconSurprise",
	VALUE_TEARFUL: &"CatIconSad",
	VALUE_SHAKE_ONLY: &"CatIconShakehead",
}


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "error_catface"
	default_value = VALUE_FRUSTRATED # 默认档：懊恼
	timing = ABTestManager.TIMING_GAME_START # 染色时机：每局开局时


# 取错标时要播的动画名，兜底为懊恼
func anim_for_error() -> StringName:
	return _ANIM_BY_VALUE.get(value(), &"CatIconFrustrated")
