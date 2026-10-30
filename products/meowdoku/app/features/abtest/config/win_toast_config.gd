## 实验配置 win_toast：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name WinToastConfig

# ---- 分组取值（数值即覆盖到的档位号） ----
const VALUE_CONTROL: int = 0 # 对照组，不弹 toast
const VALUE_P5: int = 1 # 只覆盖 p5 档
const VALUE_P10: int = 2 # 覆盖到 p10 档
const VALUE_P20: int = 3 # 覆盖到 p20 档


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "win_toast"

	default_value = VALUE_P10
