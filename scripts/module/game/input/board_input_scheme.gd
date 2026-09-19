# 输入方案：把 点击/双击/滑动 三个操作策略打包成一套，normal 与 draft 各一套，可整组热切换
class_name BoardInputScheme
extends RefCounted

# ---- 三个手势对应的操作策略 ----
var tap_op: BaseTapOperation # 点击操作
var double_tap_op: BaseDoubleTapOperation # 双击操作
var swipe_op: BaseSwipeOperation # 滑动操作


# 注入三个操作对象（只由下面两个工厂函数调用）
func _init(
	p_tap: BaseTapOperation, p_double_tap: BaseDoubleTapOperation, p_swipe: BaseSwipeOperation
) -> void:
	tap_op = p_tap
	double_tap_op = p_double_tap
	swipe_op = p_swipe


# 造「正常模式」方案：三个手势都按正式落子/打叉处理
static func create_normal(board: BoardView) -> BoardInputScheme:
	return (
		BoardInputScheme
		. new(
			NormalTapOperation.new(board),
			NormalDoubleTapOperation.new(board),
			NormalSwipeOperation.new(board),
		)
	)


# 造「草稿模式」方案：同样三个手势，改成操作草稿层
static func create_draft(board: BoardView) -> BoardInputScheme:
	return (
		BoardInputScheme
		. new(
			DraftTapOperation.new(board),
			DraftDoubleTapOperation.new(board),
			DraftSwipeOperation.new(board),
		)
	)
