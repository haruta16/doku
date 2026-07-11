class_name UndoHighlightExecutor
extends RefCounted

enum Mode { UNDO, HIGHLIGHT_ONLY }

signal execution_finished

var _board_view: BoardView = null
var _timer_node: Node = null
var _page_node: Node = null
var _outline_renderer: UndoOutlineRenderer = null
var _highlight_cells: Array[Vector2i] = []
var _is_executing: bool = false
var _pending_undo_step: StepHistory.StepRecord = null
var _mode: int = Mode.UNDO
var _exec_token: int = 0
var _scale_tween: Tween = null
var _cell_clones: Array[Node] = []
var _hidden_cells: Array[CellView] = []


func setup(board_view: BoardView, timer_node: Node, page_node: Node) -> void:
	_board_view = board_view
	_timer_node = timer_node
	_page_node = page_node


func is_executing() -> bool:
	return _is_executing


func _ensure_renderer() -> void:
	if _outline_renderer != null and is_instance_valid(_outline_renderer):
		return
	_outline_renderer = UndoOutlineRenderer.new()
	_page_node.add_child(_outline_renderer)
	_outline_renderer.visible = false


func execute(step: StepHistory.StepRecord, mode: int, duration: float) -> void:
	if step == null or step.cells.is_empty():
		execution_finished.emit()
		return
	if _board_view == null or _timer_node == null or _page_node == null:
		execution_finished.emit()
		return

	_exec_token += 1
	var token: int = _exec_token
	_is_executing = true
	_mode = mode
	_pending_undo_step = step if mode == Mode.UNDO else null
	_highlight_cells.clear()

	for entry: Dictionary in step.cells:
		var pos: Vector2i = entry["pos"]
		_highlight_cells.append(pos)

	_ensure_renderer()

	_outline_renderer.position = _board_view.global_position
	_outline_renderer.scale = _board_view.scale
	(
		_outline_renderer
		. show_outline(
			_highlight_cells,
			BoardView.CELL_PX,
			BoardView.BOARD_PADDING,
			BoardView.SLOT_PX,
			BoardView.CELL_GAP,
		)
	)

	_play_appear_scale()

	var timer: SceneTreeTimer = _timer_node.get_tree().create_timer(duration)
	timer.timeout.connect(_on_highlight_timeout.bind(token))


func _on_highlight_timeout(token: int) -> void:
	if token != _exec_token:
		return
	_stop_all_highlights()

	if _mode == Mode.UNDO and _pending_undo_step != null:
		_apply_undo(_pending_undo_step)

	_pending_undo_step = null
	_is_executing = false
	execution_finished.emit()


func _play_appear_scale() -> void:
	_kill_scale_tween()
	_cleanup_clones()
	var slot_px: int = BoardView.SLOT_PX
	var pad: int = BoardView.BOARD_PADDING
	var cluster_count: int = _outline_renderer.get_cluster_count()

	for ci in range(cluster_count):
		var wrapper: Node2D = _outline_renderer.get_cluster_wrapper(ci)
		if wrapper == null:
			continue
		var cluster_positions: Array[Vector2i] = _outline_renderer.get_cluster_cells(ci)
		var min_pos := Vector2(INF, INF)
		var max_pos := Vector2(-INF, -INF)
		for pos: Vector2i in cluster_positions:
			var cell: CellView = _board_view.get_cell_view(pos.x, pos.y)
			if cell == null:
				continue
			cell.modulate.a = 0.0
			_hidden_cells.append(cell)
			var clone: Control = cell.duplicate(0)
			clone.modulate.a = 1.0
			clone.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrapper.add_child(clone)
			var clone_anim: AnimationPlayer = clone.get_node_or_null("AnimationPlayer")
			var orig_anim: AnimationPlayer = cell.get_node_or_null("AnimationPlayer")
			if clone_anim != null:
				clone_anim.stop()
				if orig_anim != null and orig_anim.current_animation != "":
					clone_anim.play(orig_anim.current_animation)
					clone_anim.advance(orig_anim.current_animation_length)
			var orig_cross: Node = cell.get_node_or_null("CrossOut")
			var clone_cross: Node = clone.get_node_or_null("CrossOut")
			if orig_cross != null and clone_cross != null:
				clone_cross.visible = orig_cross.visible
			for child in clone.get_children():
				if child is Timer:
					(child as Timer).stop()
			_cell_clones.append(clone)
			var x: float = pad + pos.y * slot_px
			var y: float = pad + pos.x * slot_px
			min_pos = Vector2(minf(min_pos.x, x), minf(min_pos.y, y))
			max_pos = Vector2(maxf(max_pos.x, x + slot_px), maxf(max_pos.y, y + slot_px))
		var center: Vector2 = (min_pos + max_pos) * 0.5
		wrapper.set_meta("_center", center)

	_scale_tween = _timer_node.create_tween()
	(
		_scale_tween
		. tween_method(_apply_per_cluster_scale, 1.0, 1.05, 0.117)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	(
		_scale_tween
		. tween_method(_apply_per_cluster_scale, 1.05, 1.0, 0.166)
		. set_ease(Tween.EASE_IN_OUT)
		. set_trans(Tween.TRANS_QUAD)
	)
	_scale_tween.tween_callback(_cleanup_clones)


func _apply_per_cluster_scale(s: float) -> void:
	if _outline_renderer == null or not is_instance_valid(_outline_renderer):
		return
	var sv := Vector2(s, s)
	for i in range(_outline_renderer.get_cluster_count()):
		var wrapper: Node2D = _outline_renderer.get_cluster_wrapper(i)
		if wrapper == null or not is_instance_valid(wrapper):
			continue
		var center: Vector2 = wrapper.get_meta("_center", Vector2.ZERO)
		wrapper.scale = sv
		wrapper.position = center * (1.0 - s)


func _cleanup_clones() -> void:
	for clone: Node in _cell_clones:
		if is_instance_valid(clone):
			clone.queue_free()
	_cell_clones.clear()
	for cell: CellView in _hidden_cells:
		if is_instance_valid(cell):
			cell.modulate.a = 1.0
	_hidden_cells.clear()
	if _outline_renderer != null and is_instance_valid(_outline_renderer):
		for i in range(_outline_renderer.get_cluster_count()):
			var wrapper: Node2D = _outline_renderer.get_cluster_wrapper(i)
			if wrapper != null and is_instance_valid(wrapper):
				wrapper.scale = Vector2.ONE
				wrapper.position = Vector2.ZERO


func _kill_scale_tween() -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
		_scale_tween = null


func _stop_all_highlights() -> void:
	_kill_scale_tween()
	_cleanup_clones()
	if _outline_renderer != null and is_instance_valid(_outline_renderer):
		_outline_renderer.hide_outline()
	_highlight_cells.clear()


func _apply_undo(step: StepHistory.StepRecord) -> void:
	for entry: Dictionary in step.cells:
		var pos: Vector2i = entry["pos"]
		var before_state: int = entry["before"]
		var cv: CellView = _board_view.get_cell_view(pos.x, pos.y)
		var current_state: int = cv.get_state() if cv != null else CellState.EMPTY
		if current_state == CellState.CAT or current_state == CellState.ERROR:
			continue
		_board_view.set_cell_state(
			pos.x, pos.y, before_state, true, true, BoardView.ChangeSource.UNDO
		)


func cancel() -> void:
	if not _is_executing:
		return
	_exec_token += 1
	_stop_all_highlights()
	if _outline_renderer != null and is_instance_valid(_outline_renderer):
		_outline_renderer.visible = false
	if _mode == Mode.UNDO and _pending_undo_step != null:
		_apply_undo(_pending_undo_step)
	_pending_undo_step = null
	_is_executing = false
