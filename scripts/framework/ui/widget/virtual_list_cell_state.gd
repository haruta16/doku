## 虚拟列表单元生命周期：缓存子树状态，回收时禁用、复用时恢复并重置按压效果。
## 一个状态对象对应一个节点实例，可以先后绑定多条数据；保存的弱引用仅用于恢复仍归属它的子树。
class_name VirtualListCellState
extends RefCounted

enum Phase { IDLE, BINDING, ACTIVE, RELEASING, DISPOSED } # 单元从空闲到绑定、活动、回收、处置的状态；处置后不再复用

var cell: Control # 此状态对象对应的单元节点；释放动作由原 adapter 负责
var scene: PackedScene # 来源 PackedScene，用作同场景复用的匹配键
var adapter: VirtualListAdapter # 创建该单元的适配器，换数据源后旧单元仍用它解绑和处置
var binding: VirtualListBinding = null # 当前条目的凭据；空闲时为 null，回收开始即使它失效
var phase: Phase = Phase.IDLE # 防止重入导致重复回收或处置的生命周期状态
var display_cycle: int = -1 # 绑定所属的列表显示周期，隐藏或更换数据源会使旧周期失效
var modes: Array[Dictionary] = [] # 各节点的原始模式记录，node 字段保存 WeakRef
var scales: Array[Dictionary] = [] # Control/Node2D 的基线缩放，清除按压效果时恢复
var _captured_nodes: Dictionary = {} # 实例 ID → WeakRef；去重同时核对真实节点，避免误用失效记录


## 记录单元、来源场景和创建它的适配器；即使列表后来换适配器，旧单元仍交给原适配器清理。
func _init(control: Control, packed_scene: PackedScene, owner_adapter: VirtualListAdapter) -> void:
	cell = control
	scene = packed_scene
	adapter = owner_adapter


## 递归验证工厂返回值：处理、鼠标、焦点均已禁用，且有恢复所需的原始模式；任一不符返回 false。
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


## 清理失效记录并补录当前子树；已有节点保留首次基线，新绑定动态添加的节点也会纳入回收。
func capture_subtree() -> void:
	_prune_captured()
	if is_instance_valid(cell) and not cell.is_queued_for_deletion():
		_capture(cell)


## 只保留仍属于该单元的存活节点；已释放或移到别处的节点不再被本单元恢复或重置。
func _prune_captured() -> void:
	var owned_modes: Array[Dictionary] = []
	var owned_scales: Array[Dictionary] = []
	var owned_nodes: Dictionary = {}
	# 节点可以被业务移走；清理时同时核对存活与祖先关系，避免下次恢复误改别的单元。
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


## 递归记录模式和原始缩放；优先读工厂保存的模式，避免把临时禁用态误当作复用后的正常态。
func _capture(node: Node) -> void:
	if node.is_queued_for_deletion():
		return
	var identity: int = node.get_instance_id()
	# 已有记录不重写基线，但仍递归其孩子，才能捕获后来动态添加的节点。
	if _captured_nodes.has(identity) and _captured_nodes[identity].get_ref() == node:
		var existing_children: Array[Node] = node.get_children(true)
		for child: Node in existing_children:
			_capture(child)
		return
	_captured_nodes[identity] = weakref(node)
	var saved: Dictionary
	# 工厂先禁用再挂树，这里必须读禁用前的元数据，而不是记录当前 DISABLED。
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


## 先补录动态节点，再隐藏单元并禁用整棵子树；保留节点实例供下一条数据复用。
func disable_subtree() -> void:
	if is_instance_valid(cell):
		capture_subtree()
		cell.hide()
		_disable(cell)


## 递归停止节点处理并关闭 Control 输入/焦点；不替适配器 kill 自建补间或取消业务异步任务。
func _disable(node: Node) -> void:
	# 只隐藏根节点不够：子节点可能启用独立处理或输入模式，所以逐层禁用。
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


## 恢复仍归属本单元的节点模式；只还原处理与输入，不负责显示单元或重启业务动画。
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


## 清掉按压缩放动效并恢复记录的基线缩放，防止被回收时的按下外观带到下一条数据。
func reset_press_scales() -> void:
	_prune_captured()
	for saved: Dictionary in scales:
		var canvas_item: CanvasItem = saved.node.get_ref() as CanvasItem
		if is_instance_valid(canvas_item):
			UIHelper.reset_press_scale(canvas_item, saved.scale)
