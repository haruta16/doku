## 虚拟列表：只维护可见区及预留范围内的单元，复用节点并保留滚动锚点。
## Adapter 提供业务数据，Layout 计算几何，CellState 管回收，Binding 标识一次绑定；本类负责协调它们。
class_name VirtualList
extends Control

enum HeightMode { UNIFORM, PRECOMPUTED } # 等高用统一 item_height；预计算模式由适配器按宽度提供每行高度
enum Alignment { START, CENTER, END } # 滚动目标分别对齐可见区顶部、中心、底部

signal layout_updated # 新几何完成排版后的通知；不是每次滚动都发送
signal visible_range_changed # 可见条目的稳定键/索引组合变化时发送，不含预留区
signal viewport_updated # 活动列表完成一次显示更新时发送，供跟随视口的表现刷新
signal update_failed(operation: StringName, message: String) # 操作失败通知，与错误日志同时发送

@export var scroll: ScrollContainer = null # 宿主配置的滚动容器；提供滚动条与排序通知
@export var content: Control = null # scroll 的直接 Control 子节点；复用单元都挂在这里
@export var height_mode: HeightMode = HeightMode.UNIFORM: # 决定几何使用统一行高还是逐行测量值
	set(value):
		height_mode = value
		_mark_geometry_dirty()
@export var item_height: float = 100.0: # 等高模式行高（像素），变化后排队重建几何
	set(value):
		item_height = value
		_mark_geometry_dirty()
@export var spacing: float = 0.0: # 相邻行间距（像素）
	set(value):
		spacing = value
		_mark_geometry_dirty()
@export var padding_left: float = 0.0: # 内容左内边距（像素）
	set(value):
		padding_left = value
		_mark_geometry_dirty()
@export var padding_right: float = 0.0: # 内容右内边距（像素）
	set(value):
		padding_right = value
		_mark_geometry_dirty()
@export var padding_top: float = 0.0: # 内容上内边距（像素）
	set(value):
		padding_top = value
		_mark_geometry_dirty()
@export var padding_bottom: float = 0.0: # 内容下内边距（像素），另可叠加 _bottom_inset
	set(value):
		padding_bottom = value
		_mark_geometry_dirty()
@export var overscan_before: int = 1 # 可见区之前额外维持的行数，减少边缘滚动时临时创建
@export var overscan_after: int = 1 # 可见区之后额外维持的行数
@export var max_idle_per_scene: int = 2 # 每种 PackedScene 最多保留的空闲实例数，不限制活动实例
@export var max_idle_total: int = 8 # 全部场景合计的空闲实例上限
@export var with_inertia: bool = false: # 是否启用手势助手的纵向惯性，setter 同步已挂载助手
	set(value):
		with_inertia = value
		if is_instance_valid(_helper):
			_helper.with_inertia = value
@export var elastic_max_overscroll: float = 120.0: # 纵向橡皮筋位移上限（像素），同步给手势助手
	set(value):
		elastic_max_overscroll = value
		if is_instance_valid(_helper):
			_helper.elastic_max_overscroll = value

var _adapter: VirtualListAdapter = null # 当前业务数据与单元生命周期接口，列表持有其引用
var _layout := VirtualListLayout.new() # 已提交的纯几何模型；重算使用另一个候选模型
var _items: Array[Dictionary] = [] # 已提交条目描述快照，含 key/scene/height/revision/data
var _indices: Dictionary = {} # 稳定条目键 → 当前索引，用于查找与锚点恢复
var _active: Dictionary = {} # 索引 → 活动单元状态，含实际可见行和 overscan 预留行
var _idle: Array[VirtualListCellState] = [] # 已解绑但尚未释放的单元池，按场景匹配复用
var _helper: ScrollDragHelper = null # 挂在 scroll 下的手势助手；同步惯性、回弹与按压取消
var _requested_active: bool = true # 宿主要求是否运行；实际状态还受进树与可见性限制
var _effective_active: bool = false # 当前真正可更新单元的状态
var _layout_ready: bool = false # 几何已交给容器排版并完成，允许按该布局绑定单元
var _geometry_dirty: bool = true # 行高/宽度/边距等已变，下一次 flush 必须重算
var _waiting_sort: bool = false # 等待 ScrollContainer 采用新的最小尺寸完成排序
var _updating: bool = false # 正在一次显示更新中，回调中的结构操作先排队
var _lifecycle_depth: int = 0 # 回收/处置回调嵌套深度，避免它们同步改动正在遍历的集合
var _queued: bool = false # 是否已有延迟 flush，用于合并同轮多次通知
var _exiting: bool = false # 出树后拒绝新的显示更新与延迟回调
var _generation: int = 0 # 绑定代次计数；每次 _bind 都创建新的凭据身份
var _display_cycle: int = 0 # 列表显示周期；换适配器、启停、出树会递增
var _transaction: int = 0 # 几何事务号；排序完成回调必须匹配最新事务
var _pending_position: Dictionary = {} # 显式定位请求：绝对 offset 或稳定键加对齐方式，后一次覆盖前一次
var _pending_anchor: Dictionary = {} # 重排前的顶部锚点及像素差；只记最早尚未恢复的一份
var _pending_requests: Array[Dictionary] = [] # 重入时排队的换适配器/reload/单项刷新请求
var _pending_viewport_offsets: Dictionary = {} # 待应用的上下边缘 offset；必要时保留最初 origin_top 作滚动补偿
var _syncing_viewport: bool = false # 内部修改视口期间的重入保护，防止 resized 再发起一轮几何变化
var _viewport_scroll_remainder: float = 0.0 # 整数滚动条舍入后的亚像素余数，连续视口补偿时累积使用
var _forced: Dictionary = {} # 索引集合；显式 refresh_item 的条目即使版本未变也要重绑
var _bottom_inset: float = 0.0 # 运行时额外内容底部留白（像素）
var _width: float = -1.0 # 上一次提交几何时的内框宽度，-1 表示尚未记录
var _visible_signature: Array = [] # 上一轮实际可见条目的 [key, index] 序列，用于抑制重复变化通知
var _layout_signal_pending: bool = false # 新布局待发布标记，实际更新成功进入发布阶段后清除
var _diagnostics: Dictionary = { # 实例化/绑定等累计计数与最近一次更新时间（微秒），供宿主读取副本
	"instantiate": 0,
	"bind": 0,
	"reset": 0,
	"dirty_reset": 0,
	"layout_rebuild": 0,
	"update": 0,
	"update_usec": 0
}


## 校验 Scroll 与其直接 Content 子节点，连接滚动/布局通知并挂手势助手；场景契约不满足就报告失败。
func _ready() -> void:
	if scroll == null or content == null or content.get_parent() != scroll:
		_fail(&"initialize", "scene requires Scroll and its direct Content Control")
		return
	_helper = ScrollDragHelper.attach(scroll, with_inertia)
	_helper.elastic_max_overscroll = elastic_max_overscroll
	set_notify_transform(true)
	_helper.content_shifted.connect(_on_content_shifted)
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	scroll.resized.connect(_on_resized)
	content.resized.connect(_on_content_resized)
	scroll.sort_children.connect(_on_sorted)
	visibility_changed.connect(_on_visibility_changed)
	item_rect_changed.connect(_on_transform_changed)
	scroll.theme_changed.connect(_on_resized)
	_effective_active = _requested_active and is_visible_in_tree()
	_queue_update()


## 列表的画布变换改变后排一次更新；只移动或缩放祖先也会改变真正的可见区。
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_queue_update()


## 使当前显示周期失效，清理待处理请求并释放单元格，避免旧异步回调复用新状态。
func _exit_tree() -> void:
	_exiting = true
	_viewport_scroll_remainder = 0.0
	_display_cycle += 1
	_pending_position.clear()
	_pending_viewport_offsets.clear()
	_pending_requests.clear()
	_release_all(true)
	if is_instance_valid(_helper) and _helper.content_shifted.is_connected(_on_content_shifted):
		_helper.content_shifted.disconnect(_on_content_shifted)
	if is_instance_valid(scroll):
		var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
		if scrollbar.value_changed.is_connected(_on_scroll_changed):
			scrollbar.value_changed.disconnect(_on_scroll_changed)
		if scroll.resized.is_connected(_on_resized):
			scroll.resized.disconnect(_on_resized)
		if scroll.sort_children.is_connected(_on_sorted):
			scroll.sort_children.disconnect(_on_sorted)
		if scroll.theme_changed.is_connected(_on_resized):
			scroll.theme_changed.disconnect(_on_resized)
	if is_instance_valid(content) and content.resized.is_connected(_on_content_resized):
		content.resized.disconnect(_on_content_resized)


## 布局或生命周期回调中切换数据源会先排队；正式切换时清空缓存和滚动状态再重建。
func set_adapter(adapter: VirtualListAdapter) -> void:
	if _updating or _lifecycle_depth > 0:
		_pending_requests.append({"operation": &"adapter", "adapter": adapter})
		_queue_update()
		return
	if _adapter == adapter:
		return
	_display_cycle += 1
	_pending_position.clear()
	_pending_viewport_offsets.clear()
	_pending_requests.clear()
	_viewport_scroll_remainder = 0.0
	if is_instance_valid(_helper):
		_helper.stop_motion()
	_release_all(true)
	_adapter = adapter
	_items.clear()
	_indices.clear()
	_layout_ready = false
	_geometry_dirty = true
	_width = -1.0
	if adapter != null:
		reload(false)
	else:
		_queue_update()


## 先校验全部条目的稳定键、场景和几何数据，全部通过才提交；可保留当前滚动锚点。
## 重入时返回 true 只表示已排队；正常提交后仍需等待容器排序，才会更新实际单元。
func reload(preserve_anchor: bool = true) -> bool:
	if _adapter == null:
		return _fail(&"reload", "adapter is missing")
	if _updating or _lifecycle_depth > 0:
		_pending_requests.append({"operation": &"reload", "preserve": preserve_anchor})
		_queue_update()
		return true
	# 先收集整份描述与键索引；任何条目失败都保持当前数据与几何不变。
	var candidate: Array[Dictionary] = []
	var candidate_indices: Dictionary = {}
	var count: int = _adapter.get_item_count()
	if count < 0:
		return _fail(&"reload", "item count must be nonnegative")
	var available_width: float = maxf(0.0, _content_width() - padding_left - padding_right)
	for index: int in count:
		var key: String = _adapter.get_item_key(index)
		var scene: PackedScene = _adapter.get_item_scene(index)
		if key.is_empty() or candidate_indices.has(key):
			return _fail(&"reload", "item keys must be nonempty and unique")
		if not _valid_scene(scene):
			return _fail(&"reload", "item scene must have an instantiable Control root")
		var height: float = item_height
		if height_mode == HeightMode.PRECOMPUTED:
			height = _adapter.get_item_height(index, available_width)
		if not is_finite(height) or height <= 0.0:
			return _fail(&"reload", "item height must be positive and finite")
		candidate.append(
			{
				"key": key,
				"scene": scene,
				"height": height,
				"revision": _adapter.get_item_revision(index),
				"data": _adapter.get_item_data(index)
			}
		)
		candidate_indices[key] = index
	var geometry: VirtualListLayout = _prepare_layout(candidate, _content_width())
	if geometry == null:
		return _fail(&"reload", "invalid geometry configuration")
	# 锚点必须在替换 _items/_layout 前捕获，否则丢失旧行在屏幕上的相对位置。
	_begin_geometry_change(preserve_anchor)
	_items = candidate
	_indices = candidate_indices
	_layout = geometry
	_geometry_dirty = false
	_commit_geometry()
	return true


## 按已有数据与几何立即刷新可见表现；重入时延迟处理，不重新向适配器读取整份数据。
func refresh_presentation() -> void:
	if _updating or _lifecycle_depth > 0:
		_queue_update()
		return
	_update_now()


## 更新单项数据与可选高度；条目数量或稳定键变化属于结构调整，需要重新加载。
## 返回 false 表示校验失败；重入时返回 true 仅表示接受排队，不代表绑定已经刷新。
func refresh_item(index: int, geometry_changed: bool = false) -> bool:
	if not has_item(index) or _adapter == null:
		return _fail(&"refresh_item", "item index is out of range")
	if _updating or _lifecycle_depth > 0:
		_pending_requests.append(
			{"operation": &"refresh", "index": index, "geometry": geometry_changed}
		)
		_queue_update()
		return true
	if _adapter.get_item_count() != _items.size():
		return _fail(&"refresh_item", "structural changes require reload")
	# 单项刷新不能偷偷承接增删/重排；整份稳定键逐项一致才沿用原来的索引布局。
	for item_index: int in _items.size():
		if _adapter.get_item_key(item_index) != _items[item_index].key:
			return _fail(&"refresh_item", "structural changes require reload")
	var scene: PackedScene = _adapter.get_item_scene(index)
	if not _valid_scene(scene):
		return _fail(&"refresh_item", "item scene must have an instantiable Control root")
	var candidate: Array[Dictionary] = _items.duplicate()
	var descriptor: Dictionary = _items[index].duplicate()
	descriptor.scene = scene
	descriptor.data = _adapter.get_item_data(index)
	descriptor.revision = _adapter.get_item_revision(index)
	if geometry_changed and height_mode == HeightMode.PRECOMPUTED:
		descriptor.height = _adapter.get_item_height(
			index, maxf(0.0, _content_width() - padding_left - padding_right)
		)
		if not is_finite(descriptor.height) or descriptor.height <= 0.0:
			return _fail(&"refresh_item", "item height must be positive and finite")
	candidate[index] = descriptor
	var geometry: VirtualListLayout = null
	if geometry_changed:
		geometry = _prepare_layout(candidate, _content_width())
		if geometry == null:
			return _fail(&"refresh_item", "invalid geometry configuration")
		_begin_geometry_change(true)
	_items = candidate
	# 即使适配器没有递增 revision，显式刷新也必须让该单元重新绑定。
	_forced[index] = true
	if geometry_changed:
		_layout = geometry
		_geometry_dirty = false
		_commit_geometry()
	else:
		_update_now()
	return true


## 把索引转换为稳定键保存滚动请求，停止惯性后由可见区更新流程定位。
## 索引/对齐方式非法返回 false；true 表示接受请求，布局未就绪时会延后定位。
func scroll_to_index(index: int, alignment: Alignment = Alignment.START) -> bool:
	if not has_item(index) or alignment < Alignment.START or alignment > Alignment.END:
		return _fail(&"scroll_to_index", "invalid index or alignment")
	_pending_position = {"key": _items[index].key, "alignment": alignment}
	_viewport_scroll_remainder = 0.0
	if is_instance_valid(_helper):
		_helper.stop_motion()
	_update_now()
	return true


## 提交绝对纵向滚动量（像素）并停惯性；非法数值返回 false，实际位置在布局可用时夹到滚动范围。
func scroll_to_offset(offset: float) -> bool:
	if not is_finite(offset):
		return _fail(&"scroll_to_offset", "offset must be finite")
	_pending_position = {"offset": offset}
	_viewport_scroll_remainder = 0.0
	if is_instance_valid(_helper):
		_helper.stop_motion()
	_update_now()
	return true


## 设置本控件的上/下边缘 offset，并补偿滚动位置以保持内容视觉连续；true 表示接受请求，不保证已立即完成。
func set_viewport_offsets(top: float, bottom: float) -> bool:
	if not is_finite(top) or not is_finite(bottom):
		return _fail(&"set_viewport_offsets", "offsets must be finite")
	if _exiting:
		return _fail(&"set_viewport_offsets", "list is exiting")
	var pending: Dictionary = {"top": top, "bottom": bottom}
	if _pending_viewport_offsets.has("origin_top"):
		pending.origin_top = _pending_viewport_offsets.origin_top
	_pending_viewport_offsets = pending
	if (
		_updating
		or _lifecycle_depth > 0
		or not _effective_active
		or not _layout_ready
		or _waiting_sort
		or _geometry_dirty
	):
		_queue_update()
	else:
		_update_now()
	return true


## 判断索引是否属于已提交的数据快照；不查询适配器的即时数据。
func has_item(index: int) -> bool:
	return index >= 0 and index < _items.size()


## 用稳定键查当前索引，未找到返回 -1；结构变化后索引可变，键仍可用于定位。
func find_item_index(key: String) -> int:
	return _indices.get(key, -1)


## 返回内容局部坐标下的行矩形；索引非法会报错，布局尚未就绪时返回空矩形。
func get_item_rect(index: int) -> Rect2:
	if not has_item(index):
		_fail(&"get_item_rect", "item index is out of range")
		return Rect2()
	return _layout.get_item_rect(index) if _layout_ready else Rect2()


## 把行矩形转换到 viewport 坐标，供遮罩或其他界面对齐；不把矩形裁剪到可见范围。
func get_item_rect_in_viewport(index: int) -> Rect2:
	var rect: Rect2 = get_item_rect(index)
	if rect == Rect2() or not is_instance_valid(content):
		return Rect2()
	return content.get_global_transform_with_canvas() * rect


## 返回真正可见且属于当前显示周期的绑定；预留区虽然已创建，但不计入这个结果。
func get_visible_bindings() -> Array[VirtualListBinding]:
	var result: Array[VirtualListBinding] = []
	if not _effective_active or not _layout_ready:
		return result
	var interval: Vector2 = _visible_interval()
	var visible: Vector2i = _layout.get_visible_range(interval.x, interval.y)
	if visible == VirtualListLayout.EMPTY_RANGE:
		return result
	for index: int in range(visible.x, visible.y):
		var state: VirtualListCellState = _active.get(index)
		if state != null and is_binding_current(state.binding):
			result.append(state.binding)
	return result


## 同时核对凭据、活动单元、条目键和显示周期；异步表现回调可据此拒绝写入已被复用的节点。
func is_binding_current(binding: VirtualListBinding) -> bool:
	if (
		binding == null
		or not binding.is_valid()
		or not _effective_active
		or _exiting
		or not _layout_ready
		or not has_item(binding.index)
	):
		return false
	# 节点活着还不够：同一实例可能已绑定到另一条数据，必须核对列表当前持有的凭据和显示周期。
	var state: VirtualListCellState = _active.get(binding.index)
	return (
		state != null
		and state.phase == VirtualListCellState.Phase.ACTIVE
		and state.binding == binding
		and state.display_cycle == _display_cycle
		and state.binding.generation == binding.generation
		and _items[binding.index].key == binding.key
	)


## 设置宿主期望的活动状态；停用时丢弃待执行操作并回收活动单元，重新启用仍需在树中可见。
func set_active(active: bool) -> void:
	if not active:
		_pending_position.clear()
		_pending_viewport_offsets.clear()
		_pending_requests.clear()
	_requested_active = active
	_sync_activity()


## 返回诊断计数副本及当前活动/空闲数量；update_usec 是最近一次单元更新耗时，不含其后的信号回调。
func get_diagnostics() -> Dictionary:
	var result: Dictionary = _diagnostics.duplicate()
	result.active = _active.size()
	result.idle = _idle.size()
	return result


## 返回滚动条当前纵向偏移（像素，不含橡皮筋视觉位移）；容器无效时返回 0。
func get_scroll_offset() -> float:
	return float(scroll.scroll_vertical) if is_instance_valid(scroll) else 0.0


## 返回额外内容底部留白（像素），与 Inspector 的 padding_bottom 分开保存。
func get_content_bottom_inset() -> float:
	return _bottom_inset


## 设置非负的额外底部留白并使几何失效；非法输入返回 false，不改旧值。
func set_content_bottom_inset(value: float) -> bool:
	if not is_finite(value) or value < 0.0:
		return _fail(&"set_content_bottom_inset", "inset must be finite and nonnegative")
	if _bottom_inset != value:
		_bottom_inset = value
		_mark_geometry_dirty()
	return true


## 将滚动容器内框与所有启用裁剪的祖先、viewport 按矩形求交，返回 viewport 坐标中的裁剪范围。
func get_clip_rect_in_viewport() -> Rect2:
	if not is_instance_valid(scroll) or not is_inside_tree():
		return Rect2()
	var rect: Rect2 = scroll.get_global_transform_with_canvas() * _scroll_clip_rect()
	var ancestor: Node = scroll.get_parent()
	while ancestor != null:
		if ancestor is Control:
			var control: Control = ancestor as Control
			if control.clip_contents:
				rect = rect.intersection(
					control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
				)
		ancestor = ancestor.get_parent()
	return rect.intersection(get_viewport().get_visible_rect())


## 只读取 PackedScene 元数据检查可实例化且根类型为 Control，不为校验创建节点。
func _valid_scene(scene: PackedScene) -> bool:
	if scene == null or not scene.can_instantiate():
		return false
	var state: SceneState = scene.get_state()
	return (
		state.get_node_count() > 0 and ClassDB.is_parent_class(state.get_node_type(0), &"Control")
	)


## 由条目快照构造独立几何候选；配置非法返回 null，不替换当前模型。
func _prepare_layout(items: Array[Dictionary], width: float) -> VirtualListLayout:
	var heights := PackedFloat64Array()
	if height_mode == HeightMode.PRECOMPUTED:
		for descriptor: Dictionary in items:
			heights.append(descriptor.height)
	var layout := VirtualListLayout.new()
	var geometry_width: float = maxf(width, padding_left + padding_right) if width <= 0.0 else width
	if not layout.configure(
		items.size(),
		geometry_width,
		heights,
		item_height,
		spacing,
		Vector4(padding_left, padding_top, padding_right, padding_bottom + _bottom_inset)
	):
		return null
	return layout


## 在旧几何仍有效时记录顶部条目的稳定键与相对位移，停止惯性并递增布局事务号。
func _begin_geometry_change(preserve_anchor: bool) -> void:
	_viewport_scroll_remainder = 0.0
	# 多次几何改变合并时保留最初锚点，避免拿尚未排好的中间状态反复计算。
	if _pending_anchor.is_empty() and _layout_ready:
		if preserve_anchor and not _items.is_empty():
			var interval: Vector2 = _visible_interval()
			var index: int = _layout.find_anchor_index(interval.x)
			_pending_anchor = {
				"key": _items[index].key,
				"index": index,
				"offset": _layout.get_item_rect(index).position.y - interval.x
			}
		else:
			_pending_anchor = {"scroll": get_scroll_offset()}
	_waiting_sort = true
	if is_instance_valid(_helper):
		_helper.stop_motion()
	_transaction += 1


## 写入内容最小尺寸并等待 ScrollContainer 排版完成；尚无有效宽高时保留请求，稍后重试。
func _commit_geometry() -> void:
	_diagnostics.layout_rebuild += 1
	_layout_signal_pending = true
	_layout_ready = false
	_width = _content_width()
	if (
		not is_node_ready()
		or not is_instance_valid(content)
		or _width <= padding_left + padding_right
		or _scroll_clip_rect().size.y <= 0.0
	):
		_waiting_sort = false
		_queue_update()
		return
	# 只改模型不足以改变滚动条范围；先把总高度交给容器，再等排序通知确认新范围。
	content.custom_minimum_size = Vector2(_width, _layout.get_total_height())

	scroll.get_minimum_size()
	if _pending_viewport_offsets.has("origin_top"):
		_syncing_viewport = true
		scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
		_syncing_viewport = false
	_waiting_sort = true
	scroll.queue_sort()


## 标记行高、边距等几何参数已变并排队重算，避免 setter 直接进入布局。
func _mark_geometry_dirty() -> void:
	_geometry_dirty = true
	_queue_update()


## 把同一轮的多次刷新合并成一个延迟调用；退出后不再排新任务。
func _queue_update() -> void:
	if _queued or _exiting:
		return
	_queued = true
	_flush.call_deferred()


## 处理排队的适配器/数据请求，再按当前宽度重建几何或刷新单元；布局未完成时不抢先绑定。
func _flush() -> void:
	_queued = false
	if _exiting or not is_node_ready() or scroll == null or content == null:
		return
	if _updating:
		_queue_update()
		return
	# 取出一批后立刻换成空队列，处理期间的新请求留给下一轮，避免边遍历边追加。
	var requests: Array[Dictionary] = _pending_requests
	_pending_requests = []
	for request: Dictionary in requests:
		match request.operation:
			&"adapter":
				set_adapter(request.adapter)
			&"reload":
				reload(request.preserve)
			&"refresh":
				refresh_item(request.index, request.geometry)
	if (
		_layout_ready
		and not _waiting_sort
		and not _geometry_dirty
		and _effective_active
		and not _pending_viewport_offsets.is_empty()
	):
		_update_now()
	elif not _layout_ready and _effective_active and not _pending_viewport_offsets.is_empty():
		if not _pending_viewport_offsets.has("origin_top"):
			_pending_viewport_offsets.origin_top = offset_top
		_syncing_viewport = true
		offset_top = _pending_viewport_offsets.top
		offset_bottom = _pending_viewport_offsets.bottom
		_syncing_viewport = false
	var width: float = _content_width()
	if width <= padding_left + padding_right or _scroll_clip_rect().size.y <= 0.0:
		return
	# PRECOMPUTED 行高依赖宽度，容器宽度/滚动条占宽变化后需要重新测量；候选不完整则沿用已提交描述。
	if _geometry_dirty or not is_equal_approx(width, _width):
		var candidate: Array[Dictionary] = _items.duplicate()
		if height_mode == HeightMode.PRECOMPUTED and _adapter != null:
			var refreshed: Dictionary = _prepare_width_snapshot(width)
			if not refreshed.is_empty():
				candidate = refreshed.items
		var geometry: VirtualListLayout = _prepare_layout(candidate, width)
		_geometry_dirty = false
		if geometry == null:
			_fail(&"layout", "invalid geometry configuration")
			return
		_begin_geometry_change(true)
		_items = candidate
		_layout = geometry
		_commit_geometry()
		return
	if _waiting_sort:
		return
	if not _layout_ready:
		_commit_geometry()
		return
	_update_now()


## 宽度改变时重新向适配器测量行高；条目结构不一致或候选非法返回空字典，结构变化需显式 reload。
func _prepare_width_snapshot(width: float) -> Dictionary:
	if _adapter.get_item_count() != _items.size():
		return {}
	var candidate: Array[Dictionary] = []
	for index: int in _items.size():
		if _adapter.get_item_key(index) != _items[index].key:
			return {}
		var scene: PackedScene = _adapter.get_item_scene(index)
		var height: float = _adapter.get_item_height(index, width - padding_left - padding_right)
		if not _valid_scene(scene) or not is_finite(height) or height <= 0.0:
			_fail(&"layout", "width candidate contains invalid scene or height")
			return {}
		candidate.append(
			{
				"key": _items[index].key,
				"scene": scene,
				"height": height,
				"revision": _adapter.get_item_revision(index),
				"data": _adapter.get_item_data(index)
			}
		)
	if _prepare_layout(candidate, width) == null:
		_fail(&"layout", "width candidate contains invalid geometry")
		return {}
	return {"items": candidate}


## 容器排版后同步橡皮筋位移，并延迟确认当前事务完成，避免在排序通知内重入绑定。
func _on_sorted() -> void:
	if _layout_ready and not _waiting_sort and is_instance_valid(_helper):
		_helper.synchronize_content_position()
	# 捕获本次事务号；如果延迟执行前又开始了新布局，旧回调不能把新布局提前标为就绪。
	_complete_sort.call_deferred(_transaction)


## 只有仍属于当前布局事务的排序结果才标记就绪并更新；旧的延迟回调直接丢弃。
func _complete_sort(transaction: int) -> void:
	if _exiting or transaction != _transaction or not _waiting_sort:
		return
	_waiting_sort = false
	_layout_ready = true
	_update_now()


## 一次完整显示更新：定位 → 调整视口 → 回收/绑定单元 → 发布变化信号；保护回调重入并记录耗时。
func _update_now() -> void:
	if _exiting or _updating:
		return
	if _lifecycle_depth > 0:
		_queue_update()
		return
	if not _layout_ready or _waiting_sort or _geometry_dirty:
		if _geometry_dirty:
			_queue_update()
		return
	# 适配器回调与下方信号都可能同步调用列表 API；整轮持有重入标志，把结构操作推迟。
	_updating = true
	var started: int = Time.get_ticks_usec()
	if _effective_active:
		_apply_position()
		_apply_viewport_offsets()
		_update_cells()
	_diagnostics.update += 1
	_diagnostics.update_usec = Time.get_ticks_usec() - started
	if _layout_signal_pending:
		_layout_signal_pending = false
		layout_updated.emit()
	var signature: Array = []
	var bindings: Array[VirtualListBinding] = get_visible_bindings()
	for binding: VirtualListBinding in bindings:
		signature.append([binding.key, binding.index])
	# 这里只比较可见键和索引，不把每次滚动中的像素位移都当作范围变化。
	if signature != _visible_signature:
		_visible_signature = signature
		visible_range_changed.emit()
	if _effective_active:
		viewport_updated.emit()
	_updating = false
	if (
		not _pending_requests.is_empty()
		or (
			_effective_active
			and (not _pending_position.is_empty() or not _pending_viewport_offsets.is_empty())
		)
	):
		_queue_update()


## 应用上下边缘变化，把顶部位移折算成列表局部滚动补偿；保留不足一像素的余数，避免连续微调产生漂移。
func _apply_viewport_offsets() -> void:
	if _pending_viewport_offsets.is_empty():
		return
	var offsets: Dictionary = _pending_viewport_offsets
	_pending_viewport_offsets = {}
	var origin_top: float = offsets.get("origin_top", offset_top)
	var delta: float = offsets.top - origin_top
	if offset_top == offsets.top and offset_bottom == offsets.bottom and delta == 0.0:
		return
	# offset 的位移在父坐标系中；逆变换为本控件的局部距离，缩放后的补偿才不会过量。
	var logical_delta: float = get_transform().affine_inverse().basis_xform(Vector2(0.0, delta)).y
	var target: float = get_scroll_offset() + logical_delta
	if delta != 0.0:
		target += _viewport_scroll_remainder
	_syncing_viewport = true
	offset_top = offsets.top
	offset_bottom = offsets.bottom

	# 立即重排以取得新 page/max；先改滚动条再等下帧排序会用到旧边界。
	scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
	var clamped: float = clampf(target, 0.0, maxf(0.0, scrollbar.max_value - scrollbar.page))
	scroll.scroll_vertical = roundi(clamped)
	# 碰到滚动边界时舍弃余数，否则以后离开边界会把已被夹掉的位移补回来。
	if clamped != target:
		_viewport_scroll_remainder = 0.0
	elif delta != 0.0:
		_viewport_scroll_remainder = clamped - get_scroll_offset()
	if is_instance_valid(_helper):
		_helper.synchronize_content_position()
	_syncing_viewport = false


## 先恢复布局锚点，再应用显式滚动请求；目标键已删除时回退或报错，最后夹到合法滚动范围。
func _apply_position() -> void:
	if _pending_anchor.is_empty() and _pending_position.is_empty() and not _items.is_empty():
		return
	var target: float = get_scroll_offset()
	if _items.is_empty():
		target = 0.0
	if not _pending_anchor.is_empty():
		if _pending_anchor.has("scroll"):
			target = _pending_anchor.scroll
		elif not _items.is_empty():
			var index: int = find_item_index(_pending_anchor.key)
			# 原锚点还在就跟随其稳定键；锚点已删时退到原索引附近，尽量保持阅读位置。
			if index < 0:
				index = mini(_pending_anchor.index, _items.size() - 1)
			var clip: Rect2 = (
				content.get_global_transform_with_canvas().affine_inverse()
				* get_clip_rect_in_viewport()
			)
			var top_inset: float = clip.position.y - get_scroll_offset()
			target = _layout.get_item_rect(index).position.y - _pending_anchor.offset - top_inset
		_pending_anchor.clear()
	# 显式滚动请求比自动保留锚点优先；两者同时存在时以显式请求重新计算 target。
	if not _pending_position.is_empty():
		if _pending_position.has("offset"):
			target = _pending_position.offset
		else:
			var index: int = find_item_index(_pending_position.key)
			# 显式请求不接受锚点式回退；目标键已删就报错，不能默默滚到另一条数据。
			if index < 0:
				_fail(&"scroll_to_index", "pending target key was deleted")
			else:
				var rect: Rect2 = _layout.get_item_rect(index)
				var clip: Rect2 = (
					content.get_global_transform_with_canvas().affine_inverse()
					* get_clip_rect_in_viewport()
				)
				var top_inset: float = clip.position.y - get_scroll_offset()
				target = rect.position.y - top_inset
				if _pending_position.alignment == Alignment.CENTER:
					target -= (clip.size.y - rect.size.y) * 0.5
				elif _pending_position.alignment == Alignment.END:
					target -= clip.size.y - rect.size.y
		_pending_position.clear()
	var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
	target = clampf(target, 0.0, maxf(0.0, scrollbar.max_value - scrollbar.page))
	scroll.scroll_vertical = roundi(target)

	if (
		is_instance_valid(_helper)
		and not is_equal_approx(content.position.y, -float(scroll.scroll_vertical))
	):
		_helper.stop_motion()


## 计算可见区加预留行，先回收不再匹配的绑定，再按场景复用节点；显示周期改变就停止旧一轮处理。
func _update_cells() -> void:
	var interval: Vector2 = _visible_interval()
	var range_indices: Vector2i = _layout.get_active_range(
		interval.x, interval.y, maxi(0, overscan_before), maxi(0, overscan_after)
	)
	var recycled: Array[VirtualListCellState] = []
	var cycle: int = _display_cycle
	# 先快照索引再回收：解绑回调可能重入列表，不能直接遍历会被修改的活动字典。
	var active_indices: Array = _active.keys()
	for index: int in active_indices:
		if cycle != _display_cycle or _exiting:
			break
		var state: VirtualListCellState = _active.get(index)
		if state == null:
			continue
		var keep: bool = (
			range_indices != VirtualListLayout.EMPTY_RANGE
			and index >= range_indices.x
			and index < range_indices.y
			and has_item(index)
		)
		if keep:
			var descriptor: Dictionary = _items[index]
			keep = (
				state.binding != null
				and state.binding.key == descriptor.key
				and state.scene == descriptor.scene
				and state.binding.revision == descriptor.revision
				and not _forced.has(index)
				and state.binding.is_valid()
			)
		if not keep:
			_active.erase(index)
			_release(state)
			recycled.append(state)
	# 本轮刚释放的实例优先复用，滚动越过一行时通常无需再实例化同类场景。
	if range_indices != VirtualListLayout.EMPTY_RANGE:
		for index: int in range(range_indices.x, range_indices.y):
			if not _effective_active or _exiting or cycle != _display_cycle:
				break
			if _active.has(index):
				var retained: VirtualListCellState = _active[index]
				var rect: Rect2 = _layout.get_item_rect(index)
				_apply_cell_rect(retained.cell, rect)
				retained.cell.show()
				if not _present_cell(retained, rect):
					break
				continue
			var descriptor: Dictionary = _items[index]
			var state: VirtualListCellState = _take_cell(descriptor.scene, recycled)
			if state != null:
				_bind(state, index)
	_forced.clear()
	_finalize_recycled(recycled)


## 按本轮回收池 → 空闲池 → 工厂的顺序取得同场景单元；新实例须满足隐藏、禁用、归属正确的契约。
func _take_cell(scene: PackedScene, recycled: Array[VirtualListCellState]) -> VirtualListCellState:
	for index: int in recycled.size():
		if recycled[index].scene == scene:
			var state: VirtualListCellState = recycled[index]
			recycled.remove_at(index)
			return state
	for index: int in _idle.size():
		if _idle[index].scene == scene:
			var state: VirtualListCellState = _idle[index]
			_idle.remove_at(index)
			return state
	# 工厂和初始化属于业务回调；记住原适配器，失败处置不能误用后来切换的数据源。
	var owner_adapter: VirtualListAdapter = _adapter
	var cell: Control = owner_adapter.create_cell(scene, content)
	_diagnostics.instantiate += 1
	if not is_instance_valid(cell):
		_fail(&"create_cell", "factory returned invalid cell")
		return null
	var state := VirtualListCellState.new(cell, scene, owner_adapter)
	# 工厂契约保证新节点在首次绑定前没有可见/输入窗口；不满足时走重置和处置，拒绝直接投入使用。
	if (
		cell.is_queued_for_deletion()
		or cell.get_parent() != content
		or cell.visible
		or not VirtualListCellState.factory_is_suppressed(cell)
	):
		state.disable_subtree()
		owner_adapter.reset_cell(cell)
		_dispose(state)
		_fail(&"create_cell", "factory must return hidden disabled cell attached to Content")
		return null
	owner_adapter.initialize_cell(cell)
	if not is_instance_valid(cell) or cell.is_queued_for_deletion() or cell.get_parent() != content:
		_fail(&"initialize_cell", "initialization invalidated cell")
		if is_instance_valid(cell):
			_dispose(state)
		return null
	state.capture_subtree()
	state.disable_subtree()
	return state


## 在隐藏禁用态创建新凭据并调用适配器；同步回调后复查所有权与尺寸，通过后才登记活动单元并显示。
func _bind(state: VirtualListCellState, index: int) -> void:
	var cell: Control = state.cell
	var rect: Rect2 = _layout.get_item_rect(index)
	var minimum: Vector2 = cell.get_combined_minimum_size()
	if minimum.x > rect.size.x or minimum.y > rect.size.y:
		_dispose(state)
		_fail(&"bind_cell", "cell minimum size exceeds declared item rectangle")
		return
	state.phase = VirtualListCellState.Phase.BINDING
	state.disable_subtree()
	_apply_cell_rect(cell, rect)
	_generation += 1
	var descriptor: Dictionary = _items[index]
	state.binding = VirtualListBinding.new(
		cell, descriptor.key, index, descriptor.revision, _generation, descriptor.data
	)
	state.display_cycle = _display_cycle
	# bind 是同步准备阶段；若业务另起异步工作，完成时需自行检查这个新凭据。
	state.adapter.bind_cell(cell, state.binding)
	_diagnostics.bind += 1
	# 回调可能同步隐藏列表、释放节点或改周期，不能只凭调用前的检查就恢复输入。
	if (
		not state.binding.is_valid()
		or not is_instance_valid(cell)
		or cell.is_queued_for_deletion()
		or cell.get_parent() != content
		or not _effective_active
		or state.display_cycle != _display_cycle
	):
		_release(state)
		_dispose(state)
		_fail(&"bind_cell", "binding did not complete in current display cycle")
		return
	minimum = cell.get_combined_minimum_size()
	if minimum.x > rect.size.x or minimum.y > rect.size.y:
		_release(state)
		_dispose(state)
		_fail(&"bind_cell", "bound cell minimum size exceeds declared item rectangle")
		return
	state.capture_subtree()
	_apply_cell_rect(cell, rect)
	# 先登记当前绑定再恢复模式和显示；这些操作触发的回调才有正确的归属可查。
	state.phase = VirtualListCellState.Phase.ACTIVE
	_active[index] = state
	state.restore_subtree()
	cell.show()
	_present_cell(state, rect)


## 调用适配器更新当前单元表现；前后都核对绑定归属，回调使周期失效时返回 false。
func _present_cell(state: VirtualListCellState, rect: Rect2) -> bool:
	if (
		not _effective_active
		or _exiting
		or state.display_cycle != _display_cycle
		or state.binding == null
		or not is_binding_current(state.binding)
	):
		return false
	state.adapter.present_cell(state.cell, state.binding, rect)

	return (
		_effective_active
		and not _exiting
		and state.display_cycle == _display_cycle
		and state.binding != null
		and is_binding_current(state.binding)
	)


## 把复用单元还原到左上锚点、无旋转/缩放，再写入几何矩形，避免继承上一次表现的根变换。
func _apply_cell_rect(cell: Control, rect: Rect2) -> void:
	cell.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cell.rotation = 0.0
	cell.scale = Vector2.ONE
	cell.position = rect.position
	cell.size = rect.size


## 先使旧凭据失效，再取消按压、解绑和重置；最后隐藏禁用并转入空闲态，不在此处释放节点。
func _release(state: VirtualListCellState) -> void:
	if (
		state.phase == VirtualListCellState.Phase.RELEASING
		or state.phase == VirtualListCellState.Phase.DISPOSED
	):
		return
	# 先撤销凭据，再触发解绑/重置回调；即便回调同步唤醒旧任务，它也无法取得有效旧绑定。
	if state.binding != null:
		state.binding.invalidate()
	state.phase = VirtualListCellState.Phase.RELEASING
	# 清理期间的结构 API 先排队，不让适配器重入打乱正在回收的单元集合。
	_lifecycle_depth += 1
	if is_instance_valid(state.cell) and not state.cell.is_queued_for_deletion():
		state.capture_subtree()
		if is_instance_valid(_helper):
			_helper.cancel_pressed_interaction(state.cell)
		if state.binding != null:
			state.adapter.unbind_cell(state.cell, state.binding)
		if is_instance_valid(state.cell) and not state.cell.is_queued_for_deletion():
			state.reset_press_scales()
			state.adapter.reset_cell(state.cell)
			_diagnostics.reset += 1
			_report_unquiet_reset(state.cell)
			state.disable_subtree()
	state.binding = null
	state.phase = VirtualListCellState.Phase.IDLE
	_lifecycle_depth -= 1


## 非 rel 构建下检查 reset_cell 是否留下仍播放的 AnimationPlayer；只记录错误，不替业务停止它。
func _report_unquiet_reset(cell: Control) -> void:
	if OS.has_feature("rel"):
		return
	var players: Array[Node] = cell.find_children("*", "AnimationPlayer", true, false)
	var playing: PackedStringArray = PackedStringArray()
	for node: Node in players:
		var player: AnimationPlayer = node as AnimationPlayer
		if player.is_playing():
			playing.append(str(cell.get_path_to(player)))
	if playing.is_empty():
		return
	_diagnostics.dirty_reset += 1
	push_error(
		(
			"VirtualList: reset_cell: %s left AnimationPlayer playing: %s"
			% [cell.name, ", ".join(playing)]
		)
	)


## 把单元标记为已处置后交给创建它的适配器释放；先改状态以防清理回调重入导致重复处置。
func _dispose(state: VirtualListCellState) -> void:
	if state.phase == VirtualListCellState.Phase.DISPOSED:
		return
	state.phase = VirtualListCellState.Phase.DISPOSED
	if is_instance_valid(state.cell):
		_lifecycle_depth += 1
		state.adapter.dispose_cell(state.cell)
		_lifecycle_depth -= 1


## 移出所有活动绑定再逐一回收；dispose=true 时连空闲池一起处置，否则保留合格实例供复用。
func _release_all(dispose: bool) -> void:
	var states: Array = _active.values()
	# 先从活动表摘除，后续业务清理回调不会再把这些单元当作当前有效绑定。
	_active.clear()
	var recycled: Array[VirtualListCellState] = []
	if dispose:
		recycled = _idle
		_idle = []
	for state: VirtualListCellState in states:
		_release(state)
		recycled.append(state)
	if dispose:
		for state: VirtualListCellState in recycled:
			_dispose(state)
	else:
		_finalize_recycled(recycled)


## 本轮未复用的单元归入空闲池；退出、换适配器或节点无效的直接处置，随后执行容量限制。
func _finalize_recycled(recycled: Array[VirtualListCellState]) -> void:
	for state: VirtualListCellState in recycled:
		if state.phase != VirtualListCellState.Phase.IDLE:
			continue
		if (
			_exiting
			or state.adapter != _adapter
			or not is_instance_valid(state.cell)
			or state.cell.is_queued_for_deletion()
		):
			_dispose(state)
		else:
			_idle.append(state)
	_trim_idle()


## 同时限制每个场景和整个空闲池的数量；先更新池集合再调用处置回调，避免重入看到已淘汰实例。
func _trim_idle() -> void:
	var counts: Dictionary = {}
	for state: VirtualListCellState in _idle:
		counts[state.scene] = int(counts.get(state.scene, 0)) + 1
	var retained: Array[VirtualListCellState] = []
	var evicted: Array[VirtualListCellState] = []
	var remaining: int = _idle.size()
	for state: VirtualListCellState in _idle:
		if counts[state.scene] > maxi(0, max_idle_per_scene) or remaining > maxi(0, max_idle_total):
			counts[state.scene] -= 1
			remaining -= 1
			evicted.append(state)
		else:
			retained.append(state)
	# 先发布保留集合，再运行可能重入的 dispose_cell 回调。
	_idle = retained
	for state: VirtualListCellState in evicted:
		_dispose(state)


## 结合宿主开关与树中可见性计算实际活动态；切换时递增显示周期，停用会停止运动并回收活动单元。
func _sync_activity() -> void:
	var effective: bool = _requested_active and is_inside_tree() and is_visible_in_tree()
	if effective == _effective_active:
		return
	_effective_active = effective
	_display_cycle += 1
	if not effective:
		_viewport_scroll_remainder = 0.0
		_pending_position.clear()
		_pending_viewport_offsets.clear()
		_pending_requests.clear()
		if is_instance_valid(_helper):
			_helper.stop_motion()
		_release_all(false)
		_visible_signature.clear()
	else:
		_queue_update()


## 返回 ScrollContainer 局部坐标内的可用内框，扣除主题面板边距及当前可见滚动条。
func _scroll_clip_rect() -> Rect2:
	if not is_instance_valid(scroll):
		return Rect2()
	var panel: StyleBox = scroll.get_theme_stylebox(&"panel")
	var offset := Vector2(panel.get_margin(SIDE_LEFT), panel.get_margin(SIDE_TOP))
	var dimensions: Vector2 = (
		scroll.size - offset - Vector2(panel.get_margin(SIDE_RIGHT), panel.get_margin(SIDE_BOTTOM))
	)
	# 滚动条会占掉真正可用区域；行宽和可见高度都以扣除后的内框计算。
	if scroll.get_v_scroll_bar().visible:
		dimensions.x -= scroll.get_v_scroll_bar().size.x
	if scroll.get_h_scroll_bar().visible:
		dimensions.y -= scroll.get_h_scroll_bar().size.y
	return Rect2(offset, dimensions.max(Vector2.ZERO))


## 返回当前滚动内框宽度（像素）；条目再扣掉左右 padding 才得到实际可用宽度。
func _content_width() -> float:
	return _scroll_clip_rect().size.x


## 将最终裁剪矩形反变换到 Content 坐标，返回可见 y 区间；包含祖先变换与橡皮筋位移的影响。
func _visible_interval() -> Vector2:
	var clip: Rect2 = (
		content.get_global_transform_with_canvas().affine_inverse() * get_clip_rect_in_viewport()
	)
	return Vector2(clip.position.y, clip.end.y)


## 手势助手直接移动 Content 后立即刷新单元，避免越界回弹时可见范围滞后一帧。
func _on_content_shifted() -> void:
	_update_now()


## 滚动条数值变化时排队更新；同一轮多个通知合并处理。
func _on_scroll_changed(_value: float) -> void:
	_queue_update()


## 容器宽度变化时基于旧布局保留锚点并排队重算；内部视口补偿产生的通知由当前更新统一处理。
func _on_resized() -> void:
	if _syncing_viewport:
		return
	if (
		_layout_ready
		and _pending_anchor.is_empty()
		and not is_equal_approx(_content_width(), _width)
	):
		_begin_geometry_change(true)
	_queue_update()


## Content 尺寸变化后排队检查几何和可见单元。
func _on_content_resized() -> void:
	_queue_update()


## 列表矩形或变换变化后排队更新可见区，不假定滚动条变化是唯一来源。
func _on_transform_changed() -> void:
	_queue_update()


## 可见性变化时同步活动状态，隐藏列表不继续维持活动绑定。
func _on_visibility_changed() -> void:
	_sync_activity()


## 统一输出错误并发送 update_failed，返回 false 供调用链直接传播失败。
func _fail(operation: StringName, message: String) -> bool:
	push_error("VirtualList: %s: %s" % [operation, message])
	update_failed.emit(operation, message)
	return false
