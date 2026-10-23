## 预放猫特效上下文：从棋盘构造位置、边界与目标格子的共享几何信息。
class_name PreCatFxContext
extends RefCounted

var group: int = 0

var board: BoardView = null

var cat_cell: Vector2i = Vector2i.ZERO

var cell_rect_global: Rect2 = Rect2()

var board_rect_global: Rect2 = Rect2()

var cell_size_px: float = 0.0

var cat_icon_base_scale: Vector2 = Vector2.ONE

var board_scale: Vector2 = Vector2.ONE

var cat_icon_source: Node2D = null

var particles_source: Control = null

var reveal_cat: Callable = Callable()


static func for_board(target_board: BoardView, cell: Vector2i) -> PreCatFxContext:
	var ctx: PreCatFxContext = PreCatFxContext.new()
	ctx.board = target_board
	ctx.cat_cell = cell
	ctx.cat_icon_base_scale = CellView.get_cat_icon_base_scale()
	if target_board == null or not is_instance_valid(target_board):
		return ctx

	var xform: Transform2D = target_board.get_global_transform()
	ctx.board_rect_global = _aabb(Rect2(Vector2.ZERO, target_board.size), xform)
	ctx.cell_rect_global = _aabb(target_board.cell_to_local_rect(cell.x, cell.y), xform)
	ctx.cell_size_px = target_board.get_visible_cell_size()
	ctx.board_scale = target_board.scale

	var cat_cell_view: CellView = target_board.get_cell_view(cell.x, cell.y)
	if cat_cell_view != null:
		ctx.cat_icon_source = cat_cell_view.get_cat_icon()
		ctx.particles_source = cat_cell_view.get_appear_particles()
	return ctx


static func _aabb(rect: Rect2, xform: Transform2D) -> Rect2:
	var p0: Vector2 = xform * rect.position
	var p1: Vector2 = xform * Vector2(rect.end.x, rect.position.y)
	var p2: Vector2 = xform * rect.end
	var p3: Vector2 = xform * Vector2(rect.position.x, rect.end.y)
	var lo := Vector2(
		minf(minf(p0.x, p1.x), minf(p2.x, p3.x)), minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
	)
	var hi := Vector2(
		maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x)), maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
	)
	return Rect2(lo, hi - lo)
