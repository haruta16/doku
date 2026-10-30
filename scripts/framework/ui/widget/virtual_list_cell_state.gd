## 虚拟列表单元生命周期：缓存子树状态，回收时禁用、复用时恢复并重置按压效果。
class_name VirtualListCellState
extends RefCounted

enum Phase { IDLE, BINDING, ACTIVE, RELEASING, DISPOSED }

var cell: Control
var scene: PackedScene
var adapter: VirtualListAdapter
var binding: VirtualListBinding = null
var phase: Phase = Phase.IDLE
var display_cycle: int = -1
var modes: Array[Dictionary] = []
var scales: Array[Dictionary] = []
var _captured_nodes: Dictionary = {}


func _init(control: Control, packed_scene: PackedScene, owner_adapter: VirtualListAdapter) -> void:
	cell = control
	scene = packed_scene
	adapter = owner_adapter


static func factory_is_suppressed(node: Node) -> bool:
	if (
		node.process_mode != Node.PROCESS_MODE_DISABLED
		or not node.has_meta(VirtualListAdapter.INITIAL_MODES_META)
	):
		return false
	var metadata: Variant = node.get_meta(VirtualListAdapter.INITIAL_MODES_META)
	if not metadata is Dictionary or not metadata.has("process_mode"):
		return false
	if node is Control:
		var control: Control = node as Control
		if (
			control.mouse_filter != Control.MOUSE_FILTER_IGNORE
			or control.focus_mode != Control.FOCUS_NONE
			or control.mouse_behavior_recursive != Control.MOUSE_BEHAVIOR_DISABLED
			or control.focus_behavior_recursive != Control.FOCUS_BEHAVIOR_DISABLED
		):
			return false
		for property: String in [
			"mouse_filter", "focus_mode", "mouse_behavior_recursive", "focus_behavior_recursive"
		]:
			if not metadata.has(property):
				return false
	var children: Array[Node] = node.get_children(true)
	for child: Node in children:
		if not factory_is_suppressed(child):
			return false
	return true


func capture_subtree() -> void:
	_prune_captured()
	if is_instance_valid(cell) and not cell.is_queued_for_deletion():
		_capture(cell)


func _prune_captured() -> void:
	var owned_modes: Array[Dictionary] = []
	var owned_scales: Array[Dictionary] = []
	var owned_nodes: Dictionary = {}
	for saved: Dictionary in modes:
		var node: Node = saved.node.get_ref() as Node
		if (
			not is_instance_valid(node)
			or node.is_queued_for_deletion()
			or not is_instance_valid(cell)
			or (node != cell and not cell.is_ancestor_of(node))
		):
			continue
		owned_modes.append(saved)
		owned_nodes[node.get_instance_id()] = saved.node
	for saved: Dictionary in scales:
		var node: Node = saved.node.get_ref() as Node
		if (
			is_instance_valid(node)
			and owned_nodes.has(node.get_instance_id())
			and owned_nodes[node.get_instance_id()].get_ref() == node
		):
			owned_scales.append(saved)
	modes = owned_modes
	scales = owned_scales
	_captured_nodes = owned_nodes


func _capture(node: Node) -> void:
	if node.is_queued_for_deletion():
		return
	var identity: int = node.get_instance_id()
	if _captured_nodes.has(identity) and _captured_nodes[identity].get_ref() == node:
		var existing_children: Array[Node] = node.get_children(true)
		for child: Node in existing_children:
			_capture(child)
		return
	_captured_nodes[identity] = weakref(node)
	var saved: Dictionary
	if node.has_meta(VirtualListAdapter.INITIAL_MODES_META):
		saved = node.get_meta(VirtualListAdapter.INITIAL_MODES_META).duplicate()
	else:
		saved = {"process_mode": node.process_mode}
		if node is Control:
			var control: Control = node as Control
			saved.mouse_filter = control.mouse_filter
			saved.focus_mode = control.focus_mode
			saved.mouse_behavior_recursive = control.mouse_behavior_recursive
			saved.focus_behavior_recursive = control.focus_behavior_recursive
	saved.node = weakref(node)
	modes.append(saved)
	if node is Control or node is Node2D:
		scales.append({"node": weakref(node), "scale": node.get("scale")})
	var children: Array[Node] = node.get_children(true)
	for child: Node in children:
		_capture(child)


func disable_subtree() -> void:
	if is_instance_valid(cell):
		capture_subtree()
		cell.hide()
		_disable(cell)


func _disable(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is Control:
		var control: Control = node as Control
		if control.is_inside_tree():
			control.release_focus()
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
		control.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	var children: Array[Node] = node.get_children(true)
	for child: Node in children:
		_disable(child)


func restore_subtree() -> void:
	_prune_captured()
	for saved: Dictionary in modes:
		var node: Node = saved.node.get_ref() as Node
		if not is_instance_valid(node):
			continue
		node.process_mode = saved.process_mode
		if node is Control:
			var control: Control = node as Control
			control.mouse_filter = saved.mouse_filter
			control.focus_mode = saved.focus_mode
			control.mouse_behavior_recursive = saved.mouse_behavior_recursive
			control.focus_behavior_recursive = saved.focus_behavior_recursive


func reset_press_scales() -> void:
	_prune_captured()
	for saved: Dictionary in scales:
		var canvas_item: CanvasItem = saved.node.get_ref() as CanvasItem
		if is_instance_valid(canvas_item):
			UIHelper.reset_press_scale(canvas_item, saved.scale)
