class_name BoardInputScheme
extends RefCounted





var tap_op: BaseTapOperation
var double_tap_op: BaseDoubleTapOperation
var swipe_op: BaseSwipeOperation

func _init(p_tap: BaseTapOperation, p_double_tap: BaseDoubleTapOperation, p_swipe: BaseSwipeOperation) -> void :
    tap_op = p_tap
    double_tap_op = p_double_tap
    swipe_op = p_swipe

static func create_normal(board: BoardView) -> BoardInputScheme:
    return BoardInputScheme.new(
        NormalTapOperation.new(board), 
        NormalDoubleTapOperation.new(board), 
        NormalSwipeOperation.new(board), 
    )

static func create_draft(board: BoardView) -> BoardInputScheme:
    return BoardInputScheme.new(
        DraftTapOperation.new(board), 
        DraftDoubleTapOperation.new(board), 
        DraftSwipeOperation.new(board), 
    )
