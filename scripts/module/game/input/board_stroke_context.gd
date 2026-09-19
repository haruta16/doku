# 一次手势（按下 → 拖动 → 抬起）的共享状态，同一笔里所有 Operation 都读写它
class_name BoardStrokeContext
extends RefCounted

# ---- 手势过程状态 ----
var start_cell: Vector2i = Vector2i(-1, -1) # 起点格，(-1,-1) 表示没在拖动
var last_cell: Vector2i = Vector2i(-1, -1) # 上一个处理过的格子，用于补插中间格
var target_state: int = 0 # 这一笔要刷成的目标状态，0 = CellState.EMPTY
var target_pending: bool = false # 目标状态待定，等第一格的现有状态来推断
var had_move: bool = false # 手指是否移动过（区分点击与滑动）
var changed: bool = false # 这一笔是否真的改过格子
var wants_double_tap_window: bool = false # 是否需要双击判定窗口


# 复位成「没有手势」的状态
func reset() -> void:
	start_cell = Vector2i(-1, -1)
	last_cell = Vector2i(-1, -1)
	target_state = 0
	target_pending = false
	had_move = false
	changed = false
	wants_double_tap_window = false


# 是否有进行中的手势
func is_active() -> bool:
	return start_cell != Vector2i(-1, -1)
