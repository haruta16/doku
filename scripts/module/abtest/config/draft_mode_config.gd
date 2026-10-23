## 实验配置 draft_mode：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name DraftModeConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，不开启草稿模式
const VALUE_APPLY_INPLACE: int = 1 # 草稿就地应用，全对时才显示「应用」按钮
const VALUE_APPLY_INDEPENDENT: int = 2 # 草稿独立成层，进入草稿模式即显示「应用」按钮
const VALUE_AUTO_WIN: int = 3 # 草稿全对即自动提交，不用点应用
const VALUE_AUTO_WIN_PERSIST: int = 4 # 自动提交，且中途退出保留草稿
const VALUE_TOOL: int = 5


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "draft_mode"
	default_value = VALUE_CONTROL


func is_tool_mode() -> bool:
	return int(peek_value()) == VALUE_TOOL
