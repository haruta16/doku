## 滑动额外容错区域的调试描边层；只显示棋盘内框和扩展框，不接收鼠标输入。
class_name SwipeExtraZoneDebugOverlay
extends Control

var _slot: int = 0
var _padding: int = 0
var _n: int = 0
var _enabled: bool = false
var _slop_px: float = 0.0


## 忽略鼠标事件并提高绘制层级。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 99


## 接收棋盘布局，重置额外容错距离并重绘。
func configure(slot_px: int, padding: int, puzzle_size: int) -> void:
	_slot = slot_px
	_padding = padding
	_n = puzzle_size
	_slop_px = 0.0
	queue_redraw()


## 切换调试描边显示并请求重绘。
func set_enabled(on: bool) -> void:
	_enabled = on
	queue_redraw()


## 记录新的容错距离；只有可见时才请求重绘。
func refresh(slop_px: float) -> void:
	if is_equal_approx(_slop_px, slop_px):
		return
	_slop_px = slop_px
	if _enabled:
		queue_redraw()


## 用两层矩形对比原棋盘边界和向外扩张后的有效范围。
func _draw() -> void:
	if not _enabled or _slop_px <= 0.0 or _n == 0:
		return
	var board_x: float = float(_padding)
	var board_y: float = float(_padding)
	var board_w: float = float(_slot * _n)
	var board_h: float = float(_slot * _n)
	var outer := Rect2(
		board_x - _slop_px,
		board_y - _slop_px,
		board_w + _slop_px * 2.0,
		board_h + _slop_px * 2.0,
	)
	var edge := Color(1.0, 0.15, 0.25, 0.95)

	draw_rect(outer, edge, false, 3.0)

	var inner := Rect2(board_x, board_y, board_w, board_h)
	var inner_col := Color(1.0, 0.15, 0.25, 0.55)
	draw_rect(inner, inner_col, false, 1.5)
