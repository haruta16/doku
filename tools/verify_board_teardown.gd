## 棋盘对象池的退出回归：使用真实 BoardView、CellView 和 SpineSprite，保持离树以隔离页面逻辑。
## 运行：godot-4.6.1 --headless --path . --script tools/verify_board_teardown.gd
extends SceneTree

var failures: Array[String] = []
var checks: int = 0
var _board_script: GDScript
var _cell_script: GDScript
var _skeleton: Resource


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Autoload 要先完成建立；顶层类型注解/预加载会过早解析这些类所依赖的单例。
	if _load_components():
		_verify_normal_recycle()
		_verify_teardown(true)
		_verify_teardown(false)
	if checks != 17:
		failures.append("Expected 17 checks, completed %d; an earlier runtime error may have interrupted a case" % checks)
	print(JSON.stringify({
		"audit": "board_teardown",
		"status": "passed" if failures.is_empty() else "failed",
		"checks": checks,
		"failures": failures,
	}))
	quit(0 if failures.is_empty() else 1)


func _load_components() -> bool:
	_board_script = load("res://scripts/module/gameplay/view/board_view.gd") as GDScript
	_cell_script = load("res://scripts/module/gameplay/view/cell_view.gd") as GDScript
	var costume_script := load("res://scripts/module/profile/core/costume_skin.gd") as GDScript
	for script in [_board_script, _cell_script, costume_script]:
		if script == null or not script.can_instantiate():
			failures.append("A production component script did not compile")
			return false
	_skeleton = costume_script.get_script_constant_map().get("SKELETON_RES") as Resource
	if _skeleton == null:
		failures.append("CostumeSkin did not provide its real skeleton resource")
		return false
	return true


func _new_spine() -> SpineSprite:
	var spine := SpineSprite.new()
	spine.skeleton_data_res = _skeleton
	return spine


func _bind_cell(cell: Node, spine: SpineSprite, label: String) -> Callable:
	cell.set("_cat_spine", spine)
	var callback := Callable(self, "_before_draw_probe").bind(label)
	cell.set("_frame_pre_draw_cb", callback)
	RenderingServer.frame_pre_draw.connect(callback)
	return callback


func _before_draw_probe(_label: String) -> void:
	pass


func _verify_normal_recycle() -> void:
	var board: Variant = _board_script.new()
	var cell: Variant = _cell_script.new()
	if not _check_instances(board, cell):
		return
	var layer: Node = board.ensure_cat_batch_layer()
	board.add_child(cell)
	var spine := _new_spine()
	layer.add_child(spine)
	var callback := _bind_cell(cell, spine, "normal")
	cell.release_cat_spine()
	_check(not cell.has_cat_spine(), "normal: cell must release its binding")
	_check(not RenderingServer.frame_pre_draw.is_connected(callback), "normal: draw callback must disconnect")
	_check(is_instance_valid(spine) and spine.get_parent() == null, "normal: recycled spine must remain alive and detached")
	_check(board.get("_cat_spine_pool").size() == 1, "normal: pool must contain the recycled spine")
	var acquired: Variant = board.acquire_pooled_cat_spine()
	_check(acquired == spine, "normal: acquire must return the recycled instance")
	_check(board.get("_cat_spine_pool").is_empty(), "normal: acquire must empty the pool")
	board.recycle_cat_spine(acquired)
	board.free()
	_check(not is_instance_valid(spine), "normal: board destruction must free its idle pool")
	if is_instance_valid(spine):
		spine.free()


func _verify_teardown(layer_first: bool) -> void:
	var label := "layer_before_cell" if layer_first else "layer_after_cell"
	var board: Variant = _board_script.new()
	var cell: Variant = _cell_script.new()
	if not _check_instances(board, cell):
		return
	var layer: Node = board.ensure_cat_batch_layer()
	board.add_child(cell)
	if not layer_first:
		board.move_child(layer, board.get_child_count() - 1)
	_check((layer.get_index() < cell.get_index()) == layer_first, label + ": child order must match the case")
	var active := _new_spine()
	var idle := _new_spine()
	layer.add_child(active)
	board.recycle_cat_spine(idle)
	var callback := _bind_cell(cell, active, label)
	board.free()
	_check(not is_instance_valid(cell), label + ": cell must be destroyed")
	_check(not is_instance_valid(active), label + ": active spine must not survive its board")
	_check(not is_instance_valid(idle), label + ": idle spine must not survive its board")
	_check(not RenderingServer.frame_pre_draw.is_connected(callback), label + ": draw callback must disconnect")
	# 失败也回收测试留下的孤儿，避免测试进程的退出警告盖过具体断言。
	if is_instance_valid(active):
		active.free()
	if is_instance_valid(idle):
		idle.free()
	if RenderingServer.frame_pre_draw.is_connected(callback):
		RenderingServer.frame_pre_draw.disconnect(callback)


func _check_instances(board: Variant, cell: Variant) -> bool:
	if is_instance_valid(board) and board is Node and is_instance_valid(cell) and cell is Node:
		return true
	failures.append("Could not instantiate the production board/cell components")
	if is_instance_valid(board) and board is Node:
		board.free()
	if is_instance_valid(cell) and cell is Node:
		cell.free()
	return false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)
