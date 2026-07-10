class_name BaseSwipeOperation
extends RefCounted




var board: BoardView

func _init(p_board: BoardView) -> void :
    board = p_board

func on_paint(_r: int, _c: int, _stroke: BoardStrokeContext, _is_current: bool) -> CellAction:
    return null

func on_end(_stroke: BoardStrokeContext) -> void :
    pass
