## 预放猫逐行扫入表现：按格子顺序揭示棋盘并控制扫入方向。
extends PreCatFxVariant

const _SWEEP_INTERVAL: float = 0.05

const _REVEAL_SEC: float = 0.6

var _ctx: PreCatFxContext = null


func nominal_duration_sec() -> float:
	return _SWEEP_INTERVAL * float(_sweep_cell_count()) + _REVEAL_SEC


func setup(ctx: PreCatFxContext) -> void:
	_ctx = ctx


func play() -> void:
	if _ctx == null or _ctx.board == null or not is_instance_valid(_ctx.board):
		await get_tree().process_frame
		return
	var board: BoardView = _ctx.board
	var size_n: int = board.get_puzzle_size()
	var cat_row: int = _ctx.cat_cell.x
	var cat_col: int = _ctx.cat_cell.y
	if size_n <= 0 or cat_row < 0 or cat_col < 0:
		_reveal()
		await get_tree().create_timer(_REVEAL_SEC).timeout
		return

	var from_left: bool = _sweep_from_left()

	var flip: bool = not from_left

	var cols: Array[int] = []
	if from_left:
		for c: int in range(0, cat_col):
			cols.append(c)
	else:
		for c: int in range(size_n - 1, cat_col, -1):
			cols.append(c)

	for c: int in cols:
		if not is_instance_valid(board):
			return
		board.play_pre_cat_paw(cat_row, c, flip)
		await get_tree().create_timer(_SWEEP_INTERVAL).timeout
	if not is_instance_valid(board):
		return

	_reveal()
	await get_tree().create_timer(_REVEAL_SEC).timeout


func _reveal() -> void:
	if _ctx != null and _ctx.reveal_cat.is_valid():
		_ctx.reveal_cat.call(true, true)


func _sweep_from_left() -> bool:
	if _ctx == null:
		return true
	var cell_rect: Rect2 = _ctx.cell_rect_global
	if cell_rect.size == Vector2.ZERO:
		return true
	var viewport_cx: float = get_viewport_rect().size.x * 0.5
	return cell_rect.get_center().x >= viewport_cx


func _sweep_cell_count() -> int:
	if _ctx == null or _ctx.board == null or not is_instance_valid(_ctx.board):
		return 0
	var size_n: int = _ctx.board.get_puzzle_size()
	var cat_col: int = _ctx.cat_cell.y
	if size_n <= 0 or cat_col < 0:
		return 0
	return cat_col if _sweep_from_left() else maxi(size_n - 1 - cat_col, 0)
