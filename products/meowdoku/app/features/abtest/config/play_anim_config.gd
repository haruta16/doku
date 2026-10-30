## 实验配置 play_anim：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name PlayAnimConfig

# ---- 分组取值（数值方向与函数名相反，注意） ----
const VALUE_CONTROL: int = 0 # 保留待机动画
const VALUE_DISABLED: int = 1 # 关闭待机动画


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "play_anim"
	default_value = VALUE_CONTROL
