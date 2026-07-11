extends AbConfigBase
class_name RegionColorConfig

const VALUE_CONTROL: int = 0
const VALUE_CUSTOM_PALETTE: int = 1
const VALUE_NEW_CELL_ONLY: int = 2
const VALUE_CELL_COLOR_V3: int = 3
const VALUE_NEW_CELL_RECOMPUTE: int = 4
const VALUE_PALETTE_V5: int = 5
const VALUE_PALETTE_V6: int = 6
const VALUE_PALETTE_V7: int = 7


func _init() -> void:
	key = "region_color"
	default_value = VALUE_NEW_CELL_ONLY
	timing = ABTestManager.TIMING_APP_START


func is_custom_palette() -> bool:
	return value() == VALUE_CUSTOM_PALETTE


func is_new_cell_only_palette() -> bool:
	return value() == VALUE_NEW_CELL_ONLY


func is_cell_color_v3() -> bool:
	return value() == VALUE_CELL_COLOR_V3


func is_new_cell_recompute() -> bool:
	return value() == VALUE_NEW_CELL_RECOMPUTE


func is_palette_v5() -> bool:
	return value() == VALUE_PALETTE_V5


func is_palette_v6() -> bool:
	return value() == VALUE_PALETTE_V6


func is_palette_v7() -> bool:
	return value() == VALUE_PALETTE_V7
