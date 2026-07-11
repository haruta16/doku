extends AbConfigBase
class_name AttDlgLogicConfig

const VALUE_DEFAULT: int = 0
const VALUE_SKIP_CUSTOM_GUIDE: int = 1
const VALUE_RESTYLED_GUIDE: int = 2


func _init() -> void:
	key = "att_dlg_logic"
	default_value = VALUE_DEFAULT
	timing = ABTestManager.TIMING_APP_START


func should_skip_custom_guide() -> bool:
	return value() == VALUE_SKIP_CUSTOM_GUIDE


func is_custom_guide_restyled() -> bool:
	return value() == VALUE_RESTYLED_GUIDE
