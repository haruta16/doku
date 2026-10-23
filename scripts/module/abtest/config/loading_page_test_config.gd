## 实验配置 loading_page_test：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name LoadingPageTestConfig

const VALUE_CONTROL: int = 0

const VALUE_PAW_SEGMENT_BAR: int = 1

const VALUE_BOX_CAT_ARROW_BAR: int = 2

const VALUE_RUNNING_CAT_BAR: int = 3

const VALUE_SWIMMING_FISH_NO_BAR: int = 4

const VALUE_FISHBOWL_CAT_BAR: int = 5

const VALUE_CLAW_MACHINE: int = 6

const VALUE_TREADMILL_CAT_BAR: int = 7

const VALUE_WEEKDAY_COMIC: int = 8

const VALUE_WEEKDAY_COMIC_TEXT: int = 9

const VALUE_TRUST_STATS: int = 10

const VALUE_TRUST_STATS_LIVE: int = 11


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "loading_page_test"
	default_value = VALUE_CONTROL
