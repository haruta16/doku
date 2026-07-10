class_name BaseTapOperation
extends RefCounted




var board: BoardView

func _init(p_board: BoardView) -> void :
    board = p_board

func on_tap(_r: int, _c: int, _stroke: BoardStrokeContext) -> Array[CellAction]:
    return []
