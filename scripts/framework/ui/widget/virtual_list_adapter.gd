## 虚拟列表适配接口：提供稳定条目键、数据、场景、高度和绑定清理回调。
## 业务子类只实现取数和单元表现，滚动、可见区计算与复用池由 VirtualList 统一管理。
class_name VirtualListAdapter
extends RefCounted

const Binding: GDScript = preload("res://scripts/framework/ui/widget/virtual_list_binding.gd") # 绑定凭据类型别名，供业务适配器覆写 bind/unbind 参数使用

const INITIAL_MODES_META: StringName = &"virtual_list_initial_modes" # 工厂写入的元数据键，保存禁用前模式供 CellState 恢复


## 返回条目总数；基类代表空列表，有数据的适配器应覆写。
func get_item_count() -> int:
	return 0


## 返回非空且全列表唯一的稳定键；重排后键不变，列表才能找回同一条目的滚动锚点。
func get_item_key(_index: int) -> String:
	push_error("VirtualListAdapter: get_item_key must be overridden for nonempty data")
	return ""


## 返回交给绑定回调的业务数据；列表不解释内容，也不替适配器深拷贝数据。
func get_item_data(_index: int) -> Variant:
	push_error("VirtualListAdapter: get_item_data must be overridden for nonempty data")
	return null


## 返回该条目使用的 PackedScene；根必须为 Control，复用时按 PackedScene 匹配实例。
func get_item_scene(_index: int) -> PackedScene:
	push_error("VirtualListAdapter: get_item_scene must be overridden for nonempty data")
	return null


## 返回给定可用宽度下的行高（像素）；只在 PRECOMPUTED 模式调用，结果必须有限且大于零。
func get_item_height(_index: int, _available_width: float) -> float:
	push_error("VirtualListAdapter: get_item_height must be overridden for variable geometry")
	return 0.0


## 返回条目内容版本；reload 后版本变化会触发重绑，默认 0 适合内容不变或显式 refresh_item 的情况。
func get_item_revision(_index: int) -> int:
	return 0


## 默认工厂：实例化 Control、先隐藏并禁用子树再挂到 parent；失败返回 null。
## 覆写时也须返回已挂载且隐藏、禁用的单元，不能让尚未绑定的数据参与输入。
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
	# 挂树会触发 _ready；因此先把输入和处理关掉，不让未绑定实例短暂参与交互。
	cell.hide()
	_preserve_and_disable_modes(cell)
	parent.add_child(cell)
	return cell


## 每个新实例只调用一次的初始化钩子；复用时不重复调用，适合配置固定节点与公共表现接入。
func initialize_cell(_cell: Control) -> void:
	return


## 同步把一条数据写入单元；此时单元仍隐藏且禁用，回调返回并通过校验后才显示。
## 若另行发起异步工作，续跑前须检查 binding 有效性；回收会使旧凭据失效，但不会替业务取消任务。
func bind_cell(_cell: Control, _binding: Binding) -> void:
	push_error("VirtualListAdapter: bind_cell must be overridden for nonempty data")


## 对当前有效单元更新可见表现；滚动刷新也可能调用，不应重复做一次性领取或绑定副作用。
func present_cell(_cell: Control, _binding: VirtualListBinding, _item_rect: Rect2) -> void:
	return


## 解除旧条目的连接或异步任务；调用时 binding 已失效，仅可读取旧条目标识进行清理。
func unbind_cell(_cell: Control, _binding: Binding) -> void:
	return


## 把单元恢复到可复用的安静状态：适配器负责停动画、补间和自己的任务，框架随后禁用子树。
func reset_cell(_cell: Control) -> void:
	return


## 最终处置实例；默认 queue_free，已失效或已排队删除时不再操作。
func dispose_cell(cell: Control) -> void:
	if is_instance_valid(cell) and not cell.is_queued_for_deletion():
		cell.queue_free()


## 递归保存场景原始处理、鼠标与焦点模式，再整体禁用；必须在 add_child 前执行，保留 _ready 前的基线。
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
	# 这份元数据是场景初始配置，后续捕获会复制它，不让绑定逻辑改坏恢复基线。
	modes.make_read_only()
	node.set_meta(INITIAL_MODES_META, modes)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	var children: Array[Node] = node.get_children(true)
	for child: Node in children:
		_preserve_and_disable_modes(child)
