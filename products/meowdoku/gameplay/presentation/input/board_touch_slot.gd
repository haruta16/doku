## 单个触点的所有权和笔画状态：保存待消费锁定与当前笔画阶段，供输入识别器复用。
class_name BoardTouchSlot
extends RefCounted

var recognizer: BoardGestureRecognizer = null
var drag_in_progress: bool = false
var pending_enter: bool = false
var latched: bool = false
var last_drag_pos: Vector2 = Vector2.ZERO

var step_dirty: bool = false

var pending_x_marks: Array[String] = []

var cat_placed_this_stroke: bool = false

var cat_streak_break_pending: bool = false

var cat_streak_break_seq: int = 0

var lock_pending: bool = false

var physically_down: bool = false

var step_cells: Array[Dictionary] = []


func is_owned() -> bool:
	return drag_in_progress or pending_enter or latched


func consume_lock_pending() -> bool:
	var pending: bool = lock_pending
	lock_pending = false
	return pending


func reset_stroke_phase() -> void:
	pending_enter = false
	latched = false
	drag_in_progress = false


func reset_stroke() -> void:
	reset_stroke_phase()
	step_dirty = false
	lock_pending = false
	cat_placed_this_stroke = false
	pending_x_marks.clear()
	step_cells.clear()
