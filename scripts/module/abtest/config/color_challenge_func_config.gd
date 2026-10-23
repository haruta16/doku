## 实验配置 color_challenge_func：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name ColorChallengeFuncConfig

const VALUE_CONTROL: int = 0

const VALUE_SINGLE: int = 1

const VALUE_SINGLE_QUIET: int = 2

const VALUE_DUAL: int = 3


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "color_challenge_func"
	default_value = VALUE_CONTROL


func is_enabled() -> bool:
	return ColorChallengeGate.is_enabled(int(value()))


func has_quiet_rule() -> bool:
	return ColorChallengeGate.has_quiet_rule(int(value()))


func is_dual_color() -> bool:
	return ColorChallengeGate.is_dual_color(int(value()))


func group_value() -> int:
	return int(value())
