class_name BaseDoubleTapOperation
extends RefCounted




var board: BoardView

func _init(p_board: BoardView) -> void :
    board = p_board

func on_double_tap(_r: int, _c: int) -> Array[CellAction]:
    return []
