## Spine 空闲保护：追踪骨骼节点可见性与静止标记，隐藏时停用处理并在恢复时还原模式。
extends Node

const _SPINE_CLASS := "SpineSprite"

const _ORIG_MODE_META := &"_spine_idle_guard_orig_mode"

var _tracked: Dictionary = {}


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan_existing()


func _scan_existing() -> void:
	var existing: Array[Node] = get_tree().root.find_children("*", _SPINE_CLASS, true, false)
	for node in existing:
		_track(node)


func _on_node_added(node: Node) -> void:
	if node.is_class(_SPINE_CLASS):
		_track(node)


## 记住 Spine 节点原处理模式，连接可见性和退出信号，避免重复追踪。
func _track(sprite: Node) -> void:
	var canvas := sprite as CanvasItem
	if canvas == null:
		return
	var id: int = canvas.get_instance_id()
	if _tracked.has(id):
		return
	_tracked[id] = canvas
	canvas.tree_exiting.connect(_untrack.bind(id), CONNECT_ONE_SHOT)
	if not canvas.has_meta(_ORIG_MODE_META):
		canvas.set_meta(_ORIG_MODE_META, canvas.process_mode)

	var vis_cb := _on_visibility_changed.bind(canvas)
	if not canvas.visibility_changed.is_connected(vis_cb):
		canvas.visibility_changed.connect(vis_cb)
	_refresh(canvas)


func _untrack(id: int) -> void:
	_tracked.erase(id)


func _on_visibility_changed(sprite: CanvasItem) -> void:
	_refresh(sprite)


## 仅让可见且未标为静止的骨骼恢复原模式，其余节点停用处理。
func _refresh(sprite: CanvasItem) -> void:
	if not is_instance_valid(sprite):
		return
	if sprite.is_visible_in_tree() and not bool(sprite.get_meta(_SETTLED_META, false)):
		var orig_mode: int = sprite.get_meta(_ORIG_MODE_META, Node.PROCESS_MODE_INHERIT)
		sprite.process_mode = orig_mode
	else:
		sprite.process_mode = Node.PROCESS_MODE_DISABLED


const _SETTLED_META := &"_spine_idle_guard_settled"


## 设置骨骼已静止标记并立即重评估处理模式，供页面表现结束时节省更新开销。
func set_settled(sprite: CanvasItem, settled: bool) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if bool(sprite.get_meta(_SETTLED_META, false)) == settled:
		return
	if settled:
		sprite.set_meta(_SETTLED_META, true)
	else:
		sprite.remove_meta(_SETTLED_META)
	if sprite.is_inside_tree():
		_refresh(sprite)
