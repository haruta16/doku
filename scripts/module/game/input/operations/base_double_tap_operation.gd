# 双击操作基类：定义 on_double_tap 接口，棋盘视图由构造函数注入
class_name BaseDoubleTapOperation
extends RefCounted

# ---- 依赖 ----
var board: BoardView # 棋盘视图


# 绑定棋盘视图
func _init(p_board: BoardView) -> void:
	board = p_board


# 默认不产生任何动作，由 normal/draft 子类覆写
func on_double_tap(_r: int, _c: int) -> Array[CellAction]:
	return []
