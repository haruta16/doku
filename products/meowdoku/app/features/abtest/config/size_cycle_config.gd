## 实验配置 size_cycle：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name SizeCycleConfig

# ---- 分组取值（从 2 起，0/1 未使用） ----
const VALUE_CONTROL: int = 2 # 对照组，原尺寸曲线
const VALUE_CYCLE_V3_A: int = 3 # 尺寸循环方案 A
const VALUE_CYCLE_V3_B: int = 4 # 尺寸循环方案 B
const VALUE_CYCLE_V3_C: int = 5 # 尺寸循环方案 C
const VALUE_CYCLE_V3_D: int = 6 # 尺寸循环方案 D
const VALUE_CYCLE_V3_E: int = 7 # 尺寸循环方案 E
const VALUE_CYCLE_V3_F: int = 8 # 尺寸循环方案 F


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "size_cycle"
	default_value = VALUE_CYCLE_V3_D
