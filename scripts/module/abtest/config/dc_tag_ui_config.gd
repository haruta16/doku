extends AbConfigBase
class_name DcTagUiConfig

const VALUE_CONTROL: int = 0
const VALUE_PAW: int = 1


func _init() -> void:
	key = "dc_tag_ui"
	default_value = VALUE_CONTROL
	timing = ABTestManager.TIMING_APP_START


func is_paw_enabled() -> bool:
	return value() == VALUE_PAW
