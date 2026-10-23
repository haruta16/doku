## 编辑器拖尾预览插件：监听画布拖动，将采样通知传给选中节点所属的拖尾控制器。
@tool
extends EditorPlugin


## 只处理能找到拖尾控制器的选中对象。
func _handles(object: Object) -> bool:
	return _resolve_controller(object) != null


## 观察左键按下与移动状态，通知拖尾后仍把输入交回编辑器。
func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var dragging: bool = (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		_notify_controllers(dragging)
		return false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_notify_controllers(event.pressed)
		return false

	return false


## 把拖动状态和强制采样请求发送给选中的拖尾控制器。
func _notify_controllers(dragging: bool) -> void:
	for controller in _get_selected_controllers():
		controller.call("editor_trail_dragging", dragging)
		controller.call("editor_force_trail_sample")


## 从编辑器选中节点查找控制器并去重。
func _get_selected_controllers() -> Array[Node]:
	var result: Array[Node] = []
	var selected := get_editor_interface().get_selection().get_selected_nodes()

	for object in selected:
		var controller := _resolve_controller(object)
		if controller != null and not result.has(controller):
			result.append(controller)

	return result


## 仅对节点对象沿父级查找拖尾控制器。
func _resolve_controller(object: Object) -> Node:
	if object is Node:
		return _find_controller_from_node(object as Node)
	return null


## 通过两个约定方法识别控制器，允许选择其子节点时也能预览。
func _find_controller_from_node(node: Node) -> Node:
	var current: Node = node

	while current != null:
		if (
			current.has_method("editor_trail_dragging")
			and current.has_method("editor_force_trail_sample")
		):
			return current
		current = current.get_parent()

	return null
