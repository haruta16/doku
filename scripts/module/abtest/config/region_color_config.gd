## 实验配置 region_color：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name RegionColorConfig

# ---- 分组取值 ----
const VALUE_CONTROL: int = 0 # 对照组，用 CellView 自带调色板
const VALUE_CUSTOM_PALETTE: int = 1 # 自定义调色板（BoardView 里硬编码的一整套）
const VALUE_NEW_CELL_ONLY: int = 2 # 新格子专用调色板
const VALUE_CELL_COLOR_V3: int = 3 # 第 3 版格子配色
const VALUE_NEW_CELL_RECOMPUTE: int = 4 # 新配色 + 重新计算区域色
const VALUE_PALETTE_V5: int = 5 # 调色板 v5
const VALUE_PALETTE_V6: int = 6 # 调色板 v6
const VALUE_PALETTE_V7: int = 7 # 调色板 v7
const VALUE_PALETTE_V8: int = 8
const VALUE_PALETTE_V9: int = 9
const VALUE_ALL_WARM: int = 10
const VALUE_ALL_COOL: int = 11
const VALUE_TEMP_BALANCED: int = 12
const VALUE_PALETTE_V13: int = 13
const VALUE_PALETTE_V14: int = 14


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "region_color"
	default_value = VALUE_NEW_CELL_ONLY


## 是否用新格子专用调色板
func is_new_cell_only_palette() -> bool:
	return value() == VALUE_NEW_CELL_ONLY


## 是否用调色板 v5
func is_palette_v5() -> bool:
	return value() == VALUE_PALETTE_V5


## 是否用调色板 v6
func is_palette_v6() -> bool:
	return value() == VALUE_PALETTE_V6


func is_palette_v8() -> bool:
	return value() == VALUE_PALETTE_V8


func is_all_warm() -> bool:
	return value() == VALUE_ALL_WARM


func is_all_cool() -> bool:
	return value() == VALUE_ALL_COOL


func is_palette_v13() -> bool:
	return value() == VALUE_PALETTE_V13


func is_palette_v14() -> bool:
	return value() == VALUE_PALETTE_V14
