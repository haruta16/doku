## 实验配置 first_win_encourage：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name FirstWinEncourageConfig

const VALUE_CONTROL: int = 0
const VALUE_BRAIN_BOOST: int = 1
const VALUE_CAT_PRAISE: int = 2


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "first_win_encourage"
	default_value = VALUE_CONTROL


func get_first_win_text_keys(level_config: Dictionary) -> Dictionary:
	if int(level_config.get("level", 0)) != 1:
		return {}
	if bool(level_config.get("is_daily", false)):
		return {}
	if int(level_config.get("kind", LevelKind.MAIN)) != LevelKind.MAIN:
		return {}
	match int(value()):
		VALUE_BRAIN_BOOST:
			return {
				"title_key": &"FIRST_WIN_BRAIN_TITLE",
				"body_key": &"FIRST_WIN_BRAIN_BODY",
			}
		VALUE_CAT_PRAISE:
			return {
				"title_key": &"FIRST_WIN_CAT_TITLE",
				"body_key": &"FIRST_WIN_CAT_BODY",
			}
	return {}
