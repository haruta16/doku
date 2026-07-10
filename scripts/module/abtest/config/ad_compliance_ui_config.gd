extends AbConfigBase
class_name AdComplianceUiConfig









const VALUE_HIDE: int = 0
const VALUE_SHOW: int = 1
const VALUE_SHOW_ICON: int = 2
const VALUE_SHOW_ICON_TEXT: int = 3
const VALUE_REGION_SPLIT: int = 4

func _init() -> void :
    key = "ad_compliance_ui"
    default_value = VALUE_HIDE
    timing = ABTestManager.TIMING_APP_START

func should_show_ad_tag() -> bool:
    return value() != VALUE_HIDE

func should_show_ad_icon() -> bool:
    return value() == VALUE_SHOW_ICON

func should_show_ad_icon_text() -> bool:
    return value() == VALUE_SHOW_ICON_TEXT
