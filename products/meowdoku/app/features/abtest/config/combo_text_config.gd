## 实验配置 combo_text：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ComboTextConfig

const VALUE_CONTROL: int = 0

const VALUE_VARIANT_ORDINARY_1: int = 1

const VALUE_VARIANT_ORDINARY_2: int = 2

const VALUE_VARIANT_MEOW: int = 3

const VALUE_JAPANESE: int = 4

const ENCOURAGE_PLAYER: String = "AnimationPlayer2"

const ENCOURAGE_LEVEL_MAX: int = 10


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "combo_text"

	default_value = VALUE_VARIANT_ORDINARY_2


func uses_japanese_text() -> bool:
	return value() == VALUE_JAPANESE and LanguageManager.resolve_language_family() == "jp"
