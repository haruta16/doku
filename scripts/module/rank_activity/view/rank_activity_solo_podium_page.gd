## 活动结束时单人领奖台的容器；等待内部演出完成后通知管理器结束该展示阶段。

extends UIFrameWindow

const _CELL_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/rank_activity_change_page_v3.tscn"
)

const _CELL_DESIGN_H: float = 2400.0

@onready var _cell_layer: Control = $CellLayer

var _cell = null


func on_create() -> void:
	_warm_cell()
	_gpu_warm_cell()


func on_show(params: Dictionary = {}) -> void:
	var rank: int = int(params.get("rank", 4))
	_destroy_cell()
	_cell = create_child(_CELL_SCENE)
	if _cell == null:
		push_error("rank_activity_solo_podium_page: cell 创建失败,直接关页避免卡住结算流程")

		UIManager.hide_ui.call_deferred(UiName.RANK_ACTIVITY_SOLO_PODIUM)
		return

	_cell.reparent(_cell_layer, false)
	_center_cell_layer()
	if _cell.has_method("setup"):
		_cell.setup(rank)

	if _cell.has_signal("finished"):
		connect_managed(_cell.finished, _on_cell_finished)
	if _cell.has_method("play_appear"):
		_cell.play_appear()


func on_hide() -> void:
	_destroy_cell()


func on_escape() -> bool:
	return true


## 内部演出完成后关闭页面；外层等待页面隐藏的流程再继续处理活动展示收尾。
func _on_cell_finished() -> void:
	if is_showing():
		UIManager.hide_ui(UiName.RANK_ACTIVITY_SOLO_PODIUM)


func _center_cell_layer() -> void:
	if _cell_layer == null:
		return
	var dy: float = (get_viewport_rect().size.y - _CELL_DESIGN_H) * 0.5
	_cell_layer.offset_top = dy
	_cell_layer.offset_bottom = dy


func _destroy_cell() -> void:
	if _cell != null:
		destroy_child(_cell)
		_cell = null


func _warm_cell() -> void:
	var w: Control = _CELL_SCENE.instantiate()
	add_child(w)
	remove_child(w)
	w.free()


func _gpu_warm_cell() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var host: Node = tree.current_scene
	if host == null:
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(270, 600)
	vp.transparent_bg = true

	if "disable_3d" in vp:
		vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var cell := _CELL_SCENE.instantiate() as Control
	if cell == null:
		vp.queue_free()
		return
	cell.position = Vector2.ZERO
	cell.size = Vector2(1080.0, _CELL_DESIGN_H)
	cell.scale = Vector2(0.25, 0.25)
	vp.add_child(cell)

	for ci in cell.find_children("*", "CanvasItem", true, false):
		(ci as CanvasItem).visible = true
	for p in cell.find_children("*", "GPUParticles2D", true, false):
		(p as GPUParticles2D).emitting = true
	for p2 in cell.find_children("*", "CPUParticles2D", true, false):
		(p2 as CPUParticles2D).emitting = true
	for fw in cell.find_children("*", "FireworkLineTrail", true, false):
		(fw as FireworkLineTrail).emitting = true

	for _i in 5:
		await tree.process_frame
	if is_instance_valid(vp):
		vp.queue_free()
