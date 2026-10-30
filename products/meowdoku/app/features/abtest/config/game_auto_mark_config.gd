## 实验配置 game_auto_mark：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GameAutoMarkConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，纯手动
const VALUE_AUTO_CROSS: int = 1 # 放猫后自动补叉，开局也预填已定的叉
const VALUE_DOT_TOGGLE: int = 2 # 棋盘格子加「点」按钮辅助打叉
const VALUE_AUTO_CROSS_LV6: int = 3 # 同自动补叉，但只在前 6 关生效
const VALUE_LOCK_X: int = 4 # 打上的叉锁定为不可修改
const VALUE_PROP_AD: int = 5 # 每日挑战看广告换自动打叉


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "game_auto_mark"
	default_value = VALUE_CONTROL
