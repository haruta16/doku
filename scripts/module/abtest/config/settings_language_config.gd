extends AbConfigBase
class_name SettingsLanguageConfig

const VALUE_HIDE: int = 0
const VALUE_SHOW: int = 1


func _init() -> void:
	key = "settings_language"
	default_value = VALUE_HIDE
	timing = ABTestManager.TIMING_APP_START


func is_language_switch_enabled() -> bool:
	return value() == VALUE_SHOW
