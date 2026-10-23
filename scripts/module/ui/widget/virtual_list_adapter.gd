## 虚拟列表适配接口：提供稳定条目键、数据、场景、高度和绑定清理回调。
class_name VirtualListAdapter
extends RefCounted

const Binding: GDScript = preload("res://scripts/module/ui/widget/virtual_list_binding.gd")

const INITIAL_MODES_META: StringName = &"virtual_list_initial_modes"


func get_item_count() -> int:
	return 0


func get_item_key(_index: int) -> String:
	push_error("VirtualListAdapter: get_item_key must be overridden for nonempty data")
	return ""


func get_item_data(_index: int) -> Variant:
	push_error("VirtualListAdapter: get_item_data must be overridden for nonempty data")
	return null


func get_item_scene(_index: int) -> PackedScene:
	push_error("VirtualListAdapter: get_item_scene must be overridden for nonempty data")
	return null


func get_item_height(_index: int, _available_width: float) -> float:
	push_error("VirtualListAdapter: get_item_height must be overridden for variable geometry")
	return 0.0


func get_item_revision(_index: int) -> int:
	return 0


func create_cell(scene: PackedScene, parent: Control) -> Control:
	if scene == null or not is_instance_valid(parent) or parent.is_queued_for_deletion():
		push_error("VirtualListAdapter: cell scene and parent must be valid")
		return null
	if not scene.can_instantiate():
		push_error("VirtualListAdapter: cell scene cannot instantiate")
		return null
	var instance: Node = scene.instantiate()
	if not instance is Control:
		instance.free()
		push_error("VirtualListAdapter: cell scene root must be Control")
		return null
	var cell: Control = instance as Control
	cell.hide()
	_preserve_and_disable_modes(cell)
	parent.add_child(cell)
	return cell


func initialize_cell(_cell: Control) -> void:
	return


func bind_cell(_cell: Control, _binding: Binding) -> void:
	push_error("VirtualListAdapter: bind_cell must be overridden for nonempty data")


func present_cell(_cell: Control, _binding: VirtualListBinding, _item_rect: Rect2) -> void:
	return


func unbind_cell(_cell: Control, _binding: Binding) -> void:
	return


func reset_cell(_cell: Control) -> void:
	return


func dispose_cell(cell: Control) -> void:
	if is_instance_valid(cell) and not cell.is_queued_for_deletion():
		cell.queue_free()


func _preserve_and_disable_modes(node: Node) -> void:
	var modes: Dictionary = {"process_mode": node.process_mode}
	if node is Control:
		var control: Control = node as Control
		modes["mouse_filter"] = control.mouse_filter
		modes["focus_mode"] = control.focus_mode
		modes["mouse_behavior_recursive"] = control.mouse_behavior_recursive
		modes["focus_behavior_recursive"] = control.focus_behavior_recursive
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.focus_mode = Control.FOCUS_NONE
		control.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		control.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	modes.make_read_only()
	node.set_meta(INITIAL_MODES_META, modes)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	var children: Array[Node] = node.get_children(true)
	for child: Node in children:
		_preserve_and_disable_modes(child)
