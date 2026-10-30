## 实验配置 misplace_react：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name MisplaceReactionConfig

const VALUE_CONTROL: int = 0
const VALUE_SHORT_SHAKE: int = 1
const VALUE_CONFLICT: int = 2

const TARGET_REACTION_ANIM_NAME: String = "CatIconAngry"
const CONFLICT_REACTION_ANIM_NAME: String = "CatIconAngry2"

const CONFLICT_ANIM_DURATION_SEC: float = 1.25

const CONFLICT_LINE_DELAY_SEC: float = 0.25


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "misplace_react"
	default_value = VALUE_CONFLICT


func is_conflict_reaction() -> bool:
	var group: int = value()
	return group == VALUE_CONFLICT or group == VALUE_SHORT_SHAKE
