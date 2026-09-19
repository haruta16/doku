# 撤销高亮执行器：把一步涉及的格子描边并做一次缩放脉冲，倒计时结束后才真正回滚棋盘
class_name UndoHighlightExecutor
extends RefCounted

# ---- 执行模式 ----
enum Mode { UNDO, HIGHLIGHT_ONLY } # UNDO 先高亮再回滚；HIGHLIGHT_ONLY 只高亮

signal execution_finished # 一次执行结束（含超时收尾）时发出

# ---- 依赖（setup 注入） ----
var _board_view: BoardView = null # 棋盘视图：坐标换算与格子状态都问它
var _timer_node: Node = null # 用来建计时器与补间，通常是页面节点
var _page_node: Node = null # 描边渲染器的挂载父节点
# ---- 运行时状态 ----
var _outline_renderer: UndoOutlineRenderer = null # 描边渲染器，懒创建
var _highlight_cells: Array[Vector2i] = [] # 本次要高亮的格子
var _is_executing: bool = false # 是否正在执行
var _pending_undo_step: StepHistory.StepRecord = null # 待回滚的那一步（HIGHLIGHT_ONLY 模式为 null）
var _mode: int = Mode.UNDO # 当前模式，见 Mode
var _exec_token: int = 0 # 执行序号，用来作废过期回调
var _scale_tween: Tween = null # 缩放脉冲用的 Tween
var _cell_clones: Array[Node] = [] # 复制出来的格子副本
var _hidden_cells: Array[CellView] = [] # 被副本顶替而临时隐藏的原格子


# ================= 对外接口 =================
# 注入依赖，由页面初始化时调用一次
func setup(board_view: BoardView, timer_node: Node, page_node: Node) -> void:
	_board_view = board_view
	_timer_node = timer_node
	_page_node = page_node


# 是否正在执行（页面据此挡重复点击）
func is_executing() -> bool:
	return _is_executing


# 懒创建描边渲染器并挂到页面上
func _ensure_renderer() -> void:
	if _outline_renderer != null and is_instance_valid(_outline_renderer):
		return
	_outline_renderer = UndoOutlineRenderer.new()
	_page_node.add_child(_outline_renderer)
	_outline_renderer.visible = false


# 执行一步：描边 + 缩放脉冲，duration 秒后收尾（UNDO 模式顺带回滚）
func execute(step: StepHistory.StepRecord, mode: int, duration: float) -> void:
	# 空步骤直接当完成，保证调用方总能收到结束信号
	if step == null or step.cells.is_empty():
		execution_finished.emit()
		return
	# 依赖没注入也直接完成
	if _board_view == null or _timer_node == null or _page_node == null:
		execution_finished.emit()
		return

	# 序号 +1，旧的计时回调作废
	_exec_token += 1
	var token: int = _exec_token
	_is_executing = true
	_mode = mode
	_pending_undo_step = step if mode == Mode.UNDO else null
	# 收集这一步涉及的全部格子
	_highlight_cells.clear()

	for entry: Dictionary in step.cells:
		var pos: Vector2i = entry["pos"]
		_highlight_cells.append(pos)

	_ensure_renderer()

	# 坐标与缩放跟随棋盘
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

	# 缩放脉冲
	_play_appear_scale()

	# 计时结束进入收尾
	var timer: SceneTreeTimer = _timer_node.get_tree().create_timer(duration)
	timer.timeout.connect(_on_highlight_timeout.bind(token))


# ================= 内部执行 =================
# 高亮计时结束：先清描边，UNDO 模式再回滚，最后发结束信号
func _on_highlight_timeout(token: int) -> void:
	# 过期回调直接丢弃
	if token != _exec_token:
		return
	_stop_all_highlights()

	# 只有 UNDO 模式需要改棋盘
	if _mode == Mode.UNDO and _pending_undo_step != null:
		_apply_undo(_pending_undo_step)

	_pending_undo_step = null
	_is_executing = false
	execution_finished.emit()


# ================= 缩放脉冲 =================
# 缩放脉冲：把待撤销的格子复制到描边层上做整体放大再回落
func _play_appear_scale() -> void:
	_kill_scale_tween()
	_cleanup_clones()
	# 每个连通簇单独算中心
	var slot_px: int = BoardView.SLOT_PX
	var pad: int = BoardView.BOARD_PADDING
	# 簇内格子的包围盒，用来算缩放中心
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
			# 原格子先隐形，改用副本显示（副本才参与缩放）
			cell.modulate.a = 0.0
			_hidden_cells.append(cell)
			var clone: Control = cell.duplicate(0)
			clone.modulate.a = 1.0
			clone.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrapper.add_child(clone)
			var clone_anim: AnimationPlayer = clone.get_node_or_null("AnimationPlayer")
			var orig_anim: AnimationPlayer = cell.get_node_or_null("AnimationPlayer")
			# 副本定格在原格子当前所在的动画帧
			if clone_anim != null:
				clone_anim.stop()
				if orig_anim != null and orig_anim.current_animation != "":
					clone_anim.play(orig_anim.current_animation)
					clone_anim.advance(orig_anim.current_animation_length)
			var orig_cross: Node = cell.get_node_or_null("CrossOut")
			var clone_cross: Node = clone.get_node_or_null("CrossOut")
			if orig_cross != null and clone_cross != null:
				clone_cross.visible = orig_cross.visible
			# 副本会被手动缩放，停掉它自己的计时器
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

	# 两段式：先放大到 1.05（0.117 秒），再回落到 1.0（0.166 秒）
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
	# 脉冲结束清理副本
	_scale_tween.tween_callback(_cleanup_clones)


# 按缩放系数 s 重新摆放每个簇（以各自中心为轴）
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


# 清理副本并恢复被隐藏的原格子
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


# 杀掉缩放 Tween
func _kill_scale_tween() -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
		_scale_tween = null


# 停止所有高亮：杀 Tween、清副本、隐藏描边
func _stop_all_highlights() -> void:
	_kill_scale_tween()
	_cleanup_clones()
	if _outline_renderer != null and is_instance_valid(_outline_renderer):
		_outline_renderer.hide_outline()
	_highlight_cells.clear()


# ================= 回滚与取消 =================
# 真正回滚：把每个格子写回 before，跳过已被猫/错误叉占用的格子
func _apply_undo(step: StepHistory.StepRecord) -> void:
	for entry: Dictionary in step.cells:
		var pos: Vector2i = entry["pos"]
		var before_state: int = entry["before"]
		var cv: CellView = _board_view.get_cell_view(pos.x, pos.y)
		var current_state: int = cv.get_state() if cv != null else CellState.EMPTY
		# 猫和错误叉不回滚，避免破坏当前局面
		if current_state == CellState.CAT or current_state == CellState.ERROR:
			continue
		_board_view.set_cell_state(
			pos.x, pos.y, before_state, true, true, BoardView.ChangeSource.UNDO
		)


# 取消执行：立刻回滚并作废计时回调（不发 execution_finished）
func cancel() -> void:
	# 没在执行就什么都不做
	if not _is_executing:
		return
	_exec_token += 1
	_stop_all_highlights()
	if _outline_renderer != null and is_instance_valid(_outline_renderer):
		_outline_renderer.visible = false
	# UNDO 模式补一次回滚
	if _mode == Mode.UNDO and _pending_undo_step != null:
		_apply_undo(_pending_undo_step)
	_pending_undo_step = null
	_is_executing = false
