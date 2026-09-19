# 滑动操作基类：on_paint 逐格产出命令（null 表示这格不动），on_end 提供收尾钩子
class_name BaseSwipeOperation
extends RefCounted

# ---- 依赖 ----
var board: BoardView # 棋盘视图


# 绑定棋盘视图
func _init(p_board: BoardView) -> void:
	board = p_board


# 逐格处理；is_current = false 的是补插出来的中间格
func on_paint(_r: int, _c: int, _stroke: BoardStrokeContext, _is_current: bool) -> CellAction:
	return null


# 抬手时的收尾钩子，默认什么都不做
func on_end(_stroke: BoardStrokeContext) -> void:
	pass
