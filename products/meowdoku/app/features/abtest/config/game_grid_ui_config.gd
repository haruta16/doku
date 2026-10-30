## 实验配置 game_grid_ui：登记默认分组并向业务代码解释取值，调试覆盖与远端回退由 AbConfigBase 统一处理。
extends AbConfigBase
class_name GameGridUiConfig

const VALUE_NOMAL: int = 0
const VALUE_SINGLE_LINE: int = 1
const VALUE_REDUCE_SPACING: int = 2
const VALUE_DIFFERENT_CORNERS: int = 3

const VALUE_RESTORE_PRE_111: int = 4

const CORNER_RADIUS_BY_SIZE: Dictionary = {
	12: 4,
	11: 5,
	10: 6,
	9: 7,
	8: 8,
	7: 9,
	6: 10,
	5: 11,
	4: 12,
}


## 登记实验键与默认分组，供 ABTestManager 初始化并在远端值不可用时回退。
func _init() -> void:
	key = "game_grid_ui"
	default_value = VALUE_NOMAL


func is_single_line() -> bool:
	return value() == VALUE_SINGLE_LINE


func is_reduce_spacing() -> bool:
	return value() == VALUE_REDUCE_SPACING


func is_different_corners() -> bool:
	return value() == VALUE_DIFFERENT_CORNERS


func is_restore_pre_111() -> bool:
	return value() == VALUE_RESTORE_PRE_111


func get_difference_size_cell_corners(size: int) -> int:
	return CORNER_RADIUS_BY_SIZE.get(size, 10)


const LAYOUT_BY_GROUP: Array[Dictionary] = [
	{board_padding = 15, cell_gap = 4, bg_corner = 30},
	{board_padding = 7, cell_gap = 2, bg_corner = 30},
	{board_padding = 9, cell_gap = 3, bg_corner = 10},
	{board_padding = 15, cell_gap = 5, bg_corner = 30},
	{board_padding = 15, cell_gap = 4, bg_corner = 30},
]

const CELL_FACE_PX_DEFAULT: int = 100
const CELL_FACE_PX_PRE_111: int = 95


func get_cell_face_px() -> int:
	return CELL_FACE_PX_PRE_111 if is_restore_pre_111() else CELL_FACE_PX_DEFAULT


func get_board_layout() -> Dictionary:
	var g: int = int(value())
	if g < 0 or g >= LAYOUT_BY_GROUP.size():
		g = 0
	return LAYOUT_BY_GROUP[g]


const _CELL_PX: float = 100.0
const _FIXED_BOARD_WIDTH: float = 1008.0


func solve_local_layout(sz: int) -> Dictionary:
	var g: int = int(value())
	if g < 0 or g >= LAYOUT_BY_GROUP.size():
		g = 0
	var lo: Dictionary = LAYOUT_BY_GROUP[g]
	var p_s: int = int(lo.board_padding)
	var g_s: int = int(lo.cell_gap)

	if g == VALUE_NOMAL or g == VALUE_RESTORE_PRE_111 or sz <= 0:
		return {padding = p_s, gap = g_s, slot = int(_CELL_PX) + 2 * g_s}
	var scale: float = (
		(_FIXED_BOARD_WIDTH - 2.0 * float(p_s) - 2.0 * float(sz) * float(g_s))
		/ (_CELL_PX * float(sz))
	)
	if scale <= 0.0:
		return {padding = p_s, gap = g_s, slot = int(_CELL_PX) + 2 * g_s}
	var gap_local: int = int(round(float(g_s) / scale))
	var padding_local: int = int(round(float(p_s) / scale))
	return {padding = padding_local, gap = gap_local, slot = int(_CELL_PX) + 2 * gap_local}
