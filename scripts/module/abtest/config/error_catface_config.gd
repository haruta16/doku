extends AbConfigBase
class_name ErrorCatfaceConfig

const VALUE_FRUSTRATED: int = 0
const VALUE_SURPRISED: int = 1
const VALUE_TEARFUL: int = 2
const VALUE_SHAKE_ONLY: int = 3

const _ANIM_BY_VALUE: Dictionary = {
	VALUE_FRUSTRATED: &"CatIconFrustrated",
	VALUE_SURPRISED: &"CatIconSurprise",
	VALUE_TEARFUL: &"CatIconSad",
	VALUE_SHAKE_ONLY: &"CatIconShakehead",
}


func _init() -> void:
	key = "error_catface"
	default_value = VALUE_FRUSTRATED
	timing = ABTestManager.TIMING_GAME_START


func anim_for_error() -> StringName:
	return _ANIM_BY_VALUE.get(value(), &"CatIconFrustrated")
