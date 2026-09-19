# 区域配色实验：给棋盘区域换调色板；0=对照组（CellView 自带） 1=自定义配色 2=新格子专用配色 3=配色 v3 4=新配色并重算区域色 5~7=调色板 v5/v6/v7
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


# 初始化：登记实验 key、默认档与染色时机
func _init() -> void:
	key = "region_color"
	default_value = VALUE_NEW_CELL_ONLY # 默认档：新格子专用配色
	timing = ABTestManager.TIMING_APP_START # 染色时机：冷启动就绪即定档


# 是否用自定义调色板
func is_custom_palette() -> bool:
	return value() == VALUE_CUSTOM_PALETTE


# 是否用新格子专用调色板
func is_new_cell_only_palette() -> bool:
	return value() == VALUE_NEW_CELL_ONLY


# 是否用配色 v3
func is_cell_color_v3() -> bool:
	return value() == VALUE_CELL_COLOR_V3


# 是否用新配色并重算区域色
func is_new_cell_recompute() -> bool:
	return value() == VALUE_NEW_CELL_RECOMPUTE


# 是否用调色板 v5
func is_palette_v5() -> bool:
	return value() == VALUE_PALETTE_V5


# 是否用调色板 v6
func is_palette_v6() -> bool:
	return value() == VALUE_PALETTE_V6


# 是否用调色板 v7
func is_palette_v7() -> bool:
	return value() == VALUE_PALETTE_V7
