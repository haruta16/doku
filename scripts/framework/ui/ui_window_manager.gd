## 可独立使用的窗口管理器：场景缓存、显示/隐藏、层级、遮罩与异步预热。
## 宿主在首次打开窗口前 configure；无需产品 Autoload。
class_name UIWindowManager
extends Node

var _announced_windows: Dictionary = {} # 已发布 shown 的窗口；同步取消显示时不发孤立 hidden。

# ---- 注册表与缓存（key 是宿主提供的窗口名） ----
var _registry: Dictionary = {} # 窗口名 -> 场景路径，由宿主配置
var _cache: Dictionary = {} # 窗口名 -> 已实例化的 UIFrameWindow（常驻复用，隐藏不销毁）
var _creating: Dictionary = {} # 创建中占位；同名同步重入返回 null，不能使用半初始化实例。
var _stacks: Dictionary = {} # layer -> 该层窗口栈，数组尾部是栈顶（最后显示的那个）
var events: UIEvents = UIEvents.new() # 创建、显示，以及正常关闭/首次显示取消的完成通知。

# 遮罩只负责表现；窗口选择、栈和开关时序仍由本管理器负责。
var _modal_mask: UIModalMask = UIModalMask.new()

# 可选的产品表现接入；省略时窗口仍可正常运行。
var _sound_player: Callable
var _scene_preparer: Callable
var _is_disposing: bool = false
var _refreshing_occlusion: bool = false
var _occlusion_dirty: bool = false
var _occlusion_retry_queued: bool = false


## 首次创建窗口前配置一次；复制注册表，避免外部修改产生半更新状态。
func configure(registry: Dictionary, sound_player: Callable = Callable(), scene_preparer: Callable = Callable()) -> void:
	if not _cache.is_empty() or not _loading.is_empty() or not _creating.is_empty():
		push_error("UIWindowManager: configure must precede window creation")
		return
	_registry = registry.duplicate()
	_sound_player = sound_player
	_scene_preparer = scene_preparer


func _ready() -> void:
	add_child(_modal_mask)


# ================= 显示 / 隐藏（对外主入口） =================
## 显示页面：查表 → 取/建实例 → 定层入栈 → 起遮罩 → 真正 show；返回窗口给调用方用
func show_ui(ui_name: String, params: Dictionary = {}) -> UIFrameWindow:
	if _is_disposing:
		return null
	# 名字不在注册表里＝写错，或者这个构建根本没注册它
	if not _registry.has(ui_name):
		push_error("UIWindowManager: unknown ui '%s'" % ui_name)
		return null
	# 命中缓存就复用，未命中才 load 场景
	var win: UIFrameWindow = _get_or_create(ui_name)
	if win == null:
		return null
	# 已经在显示：只补一次 on_show(params) 刷新参数，不入栈、不重播动画
	if win.is_showing():
		_apply_safe_area(ui_name, win)
		if not _is_live_window(ui_name, win):
			return null
		win.on_show(params)
		return win if _is_live_window(ui_name, win) else null
	# 关闭完成前始终保留栈占位，包括 visible=false 同步通知中的短暂 HIDDEN。
	# 这些时点重开仍是同一次显示，不能重复申请遮罩或发 window_shown。
	var was_open: bool = _ordered_windows().has(win)
	if win._window_state == UIBaseWindow.WindowState.CLOSING:
		win._abort_close_animation()
	# 所有层统一排序后分配绘制位置，低层无论打开多少次也不会越过高层。
	var layer: int = win.ui_layer
	if not was_open and _ordered_windows().size() >= UILayerConfig.MAX_OPEN_WINDOWS:
		push_error("UIWindowManager: too many simultaneously open windows")
		return null
	_push_stack(layer, win)
	_assign_z_indices()
	_apply_safe_area(ui_name, win)
	if not _is_live_window(ui_name, win):
		return null
	if win.show_mask:
		_modal_mask.show_for(get_tree().current_scene, win.mask_opacity, was_open)
	# 真正显示：visible=true、on_show、开场动画。
	var revision: int = win._show_revision + 1
	win._do_show(params)
	if not _is_live_window(ui_name, win):
		return null
	if win._show_revision != revision or not win.is_showing():
		return win

	# 先确定实际可见窗口，再让遮罩跟随最上层可见模态窗口。
	_refresh_occlusion()
	var top: UIFrameWindow = _top_mask_window()
	_modal_mask.restack(top, top.mask_opacity if top != null else 0.0)

	# 关闭被打断时不重复发 window_shown，避免埋点重复计数
	if _is_live_window(ui_name, win) and win._show_revision == revision and win.is_showing() and not _announced_windows.has(win.get_instance_id()):
		_announced_windows[win.get_instance_id()] = true
		events.window_shown.emit(ui_name, win)
	return win if _is_live_window(ui_name, win) else null


## 隐藏页面：置 CLOSING → 收遮罩 → 播关闭动画 → on_hide → 出栈并发 window_hidden
func hide_ui(ui_name: String) -> void:
	if _creating.has(ui_name):
		_creating[ui_name].cancelled = true
		var creating: Variant = _cache.get(ui_name)
		if is_instance_valid(creating) and creating.is_node_ready():
			creating._do_destroy()
		return
	# 没有缓存、或本来就没显示：直接返回（重复 hide 是安全的）
	var cached: Variant = _cache.get(ui_name, null)
	var win: UIFrameWindow = cached as UIFrameWindow if is_instance_valid(cached) else null
	if win == null or not win.is_showing():
		return
	var revision: int = win._show_revision
	# 先置 CLOSING：关闭动画期间 show_ui 靠这个状态判断能否打断
	win._window_state = UIBaseWindow.WindowState.CLOSING

	# 关闭被遮挡或下层模态窗口时，上层遮罩不参与淡出。
	if win.show_mask and _top_mask_window() == win:
		var next: UIFrameWindow = _top_mask_window(win)
		_modal_mask.begin_close(next, next.mask_opacity if next != null else 0.0, win.get_hide_anim_duration())
	# 等关闭动画播完；期间若被 show_ui 打断，状态会被改回 SHOWING，这里就放弃收尾
	await win._play_close_animation()
	if not is_instance_valid(win) or win._show_revision != revision or win._window_state != UIBaseWindow.WindowState.CLOSING:
		return
	# on_hide 钩子：内部还会断开 connect_managed 的连接、暂停托管定时器
	await win._do_hide()

	# 收尾前再确认一次状态：期间被打断过就什么都不做
	if not is_instance_valid(win) or win._show_revision != revision or win._window_state != UIBaseWindow.WindowState.HIDDEN:
		return
	# 恢复下层时的 visible 回调也可能重开/销毁本窗口；保留占位直到回调完成。
	# HIDDEN 项不参与遮挡，重开沿用原请求，销毁则由 tree_exiting 正常收尾。
	_refresh_occlusion()
	if not is_instance_valid(win) or win._show_revision != revision or win._window_state != UIBaseWindow.WindowState.HIDDEN:
		return
	_pop_stack(win.ui_layer, win)
	var top: UIFrameWindow = _top_mask_window()
	if win.show_mask:
		_modal_mask.finish_close(top, top.mask_opacity if top != null else 0.0)
	else:
		_modal_mask.restack(top, top.mask_opacity if top != null else 0.0)

	# 广播前栈、遮挡和遮罩已一致；监听者可继续打开下一个窗口。
	_publish_hidden(ui_name, win)


## 先移除发布记录再通知，监听者可同步重开而不与旧通知争用同一记录。
func _publish_hidden(ui_name: String, win: UIFrameWindow) -> void:
	if _announced_windows.erase(win.get_instance_id()):
		events.window_hidden.emit(ui_name, win)
	else:
		events.window_show_cancelled.emit(ui_name, win)


# ================= 查询 =================
func get_ui(ui_name: String) -> UIFrameWindow:
	if _is_disposing or is_queued_for_deletion() or _creating.has(ui_name):
		return null
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached) and not cached.is_queued_for_deletion() and cached.get_window_state() != UIBaseWindow.WindowState.DESTROYED:
		return cached as UIFrameWindow
	return null


func _is_live_window(ui_name: String, win: Variant) -> bool:
	return not _is_disposing and not is_queued_for_deletion() and is_inside_tree() \
		and is_instance_valid(win) and get_ui(ui_name) == win and win.is_inside_tree()


## 这个页面当前是否已经创建过（只看缓存，不触发创建）
func has_ui(ui_name: String) -> bool:
	return get_ui(ui_name) != null


# ================= 批量收起 =================
func hide_all() -> void:
	for ui_name in _cache.keys():
		var cached: Variant = _cache.get(ui_name, null)
		if is_instance_valid(cached) and (cached as UIFrameWindow).is_showing():
			hide_ui(ui_name)


## 收起除名单外的所有已显示页面（名单里的保持原样）
func hide_all_except(names: Array[String]) -> void:
	for ui_name in _cache.keys():
		if ui_name in names:
			continue
		var cached: Variant = _cache.get(ui_name, null)
		if is_instance_valid(cached) and (cached as UIFrameWindow).is_showing():
			hide_ui(ui_name)


# ================= 创建与缓存 =================
func _get_or_create(ui_name: String) -> UIFrameWindow:
	if _creating.has(ui_name):
		return null
	# 命中缓存
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		var win : UIFrameWindow = cached as UIFrameWindow
		if win.is_queued_for_deletion() or win.get_window_state() == UIBaseWindow.WindowState.DESTROYED:
			return null
		# 父节点没了（例如 current_scene 被换掉）→ 重新挂到当前场景根
		if win.get_parent() == null:
			get_tree().current_scene.add_child(win)
		return win if _is_live_window(ui_name, win) else null
	# 没缓存才真的 load 场景并实例化
	var packed: PackedScene = load(_registry[ui_name])
	if packed == null:
		push_error("UIWindowManager: cannot load '%s'" % _registry[ui_name]) # 加载失败只报错，返回 null
		return null
	return _create_and_cache(ui_name, packed)


## 入栈：同层做过就把旧的挪到栈顶（重新显示算最新）
func _push_stack(layer: int, win: UIFrameWindow) -> void:
	if not _stacks.has(layer):
		_stacks[layer] = []
	var stack: Array = _stacks[layer]
	stack.erase(win)
	stack.append(win)
	_occlusion_dirty = true


## 出栈：把窗口从它那一层的栈里删掉
func _pop_stack(layer: int, win: UIFrameWindow) -> void:
	if _stacks.has(layer):
		_stacks[layer].erase(win)
		_occlusion_dirty = true


# ================= 层级栈与遮挡 =================
func _ordered_windows() -> Array[UIFrameWindow]:
	var ordered: Array[UIFrameWindow] = []
	var layers: Array = _stacks.keys()
	layers.sort()
	for l: int in layers:
		for cached: Variant in _stacks[l]:
			if is_instance_valid(cached):
				ordered.append(cached as UIFrameWindow)
	return ordered


## 从栈顶往下扫：第一个全屏窗口之上都可见，被它盖住的窗口隐藏并回调 on_stack_bottom
func _refresh_occlusion() -> void:
	_occlusion_dirty = true
	if _refreshing_occlusion or _is_disposing:
		return
	_refreshing_occlusion = true
	# 同步可见性/栈钩子可能继续导航：合并重入，并在栈变化后重新取快照。
	# 异常监听若反复相互开关窗口，分帧继续，不能阻塞整个主线程。
	var passes: int = 0
	while _occlusion_dirty and not _is_disposing and passes < UILayerConfig.MAX_OPEN_WINDOWS * 2:
		_occlusion_dirty = false
		_refresh_occlusion_pass()
		passes += 1
	_refreshing_occlusion = false
	if _occlusion_dirty and not _is_disposing and not _occlusion_retry_queued:
		_occlusion_retry_queued = true
		get_tree().process_frame.connect(_retry_occlusion, CONNECT_ONE_SHOT)


func _retry_occlusion() -> void:
	_occlusion_retry_queued = false
	_restore_stack_presentation()


func _refresh_occlusion_pass() -> void:
	var ordered: Array[UIFrameWindow] = _ordered_windows()
	var occluded: bool = false
	# 从栈顶（最后显示的）往前遍历
	for i in range(ordered.size() - 1, -1, -1):
		var win: UIFrameWindow = ordered[i]
		if not is_instance_valid(win) or not _is_live_window(win._ui_name, win):
			continue
		# visible=false 的同步回调可能打开另一窗口；尚未出栈的 HIDDEN 不能被重新显示。
		if not win.is_showing() and win.get_window_state() != UIBaseWindow.WindowState.CLOSING:
			continue
		# 只要上面还没出现全屏窗口，就该可见
		var should_visible: bool = not occluded
		var revision: int = win._show_revision
		# 由隐藏变可见：回调 on_stack_top，页面在这里恢复动效/计时
		if should_visible and not win.visible:
			win.visible = true
			if not _occlusion_callback_is_current(win, revision):
				return
			win.on_stack_top()
		# 被上层全屏挡住的：隐藏并回调 on_stack_bottom
		elif not should_visible and win.visible:
			win.visible = false
			if not _occlusion_callback_is_current(win, revision):
				return
			win.on_stack_bottom()
		if not _occlusion_callback_is_current(win, revision):
			return
		# 遇到全屏页面，再往下就全部判为被遮挡
		if should_visible and win.is_fullscreen:
			occluded = true


func _occlusion_callback_is_current(win: Variant, revision: int) -> bool:
	if _is_disposing or _occlusion_dirty:
		return false
	if not is_instance_valid(win) or not _is_live_window(win._ui_name, win) or win._show_revision != revision \
		or (not win.is_showing() and win.get_window_state() != UIBaseWindow.WindowState.CLOSING):
		_occlusion_dirty = true
		return false
	return true


## ui_layer 只表示逻辑顺序；实际 z_index 按所有打开的窗口重新编号。
## 相邻窗口预留一段空间给场景内部的相对 z_index，前一格留给模态遮罩。
func _assign_z_indices() -> void:
	var ordered: Array[UIFrameWindow] = _ordered_windows()
	for index: int in ordered.size():
		var win: UIFrameWindow = ordered[index]
		win.z_as_relative = false
		win.z_index = index * UILayerConfig.Z_STEP
		# Godot 的 GUI 命中顺序取决于节点顺序，不按 z_index 排序。
		# 与绘制顺序同步；调用方随后把模态遮罩放回目标窗口之前。
		win.get_parent().move_child(win, -1)


## 整层显示/隐藏；注意直接改 visible，不会触发 on_stack_top / on_stack_bottom 回调
func set_layer_visible(layer: int, is_visible: bool) -> void:
	var stack: Array = _stacks.get(layer, [])
	for win: UIFrameWindow in stack:
		win.visible = is_visible


## 某层栈里有几个窗口（含当前不可见的）
func get_window_count(layer: int) -> int:
	return _stacks.get(layer, []).size()


## 预热：提前实例化并保持隐藏，避免第一次打开时卡在加载
func warm_pool(ui_name: String) -> void:
	if _is_disposing or get_ui(ui_name) != null or not _registry.has(ui_name):
		return
	_get_or_create(ui_name)
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached) and (cached as UIFrameWindow).is_hidden():
		(cached as UIFrameWindow).visible = false


## Android 返回键：Godot 把它转成这个通知
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_button()


## Esc / ui_cancel 走同一条返回逻辑，并标记已处理，避免继续往下传
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button()
		get_viewport().set_input_as_handled()


## 返回：从最高层的栈顶往下找第一个可见窗口，交给它 on_escape()；只处理这一个
func _on_back_button() -> void:
	var layers: Array = _stacks.keys()
	layers.sort()
	for i in range(layers.size() - 1, -1, -1):
		var stack: Array = _stacks[layers[i]]
		for j in range(stack.size() - 1, -1, -1):
			var win: UIFrameWindow = stack[j]
			if win.visible:
				win.on_escape()
				return


# ================= 输入保护 =================
const _INPUT_BLOCKER_NAME: StringName = &"_InputBlocker" # 挡板节点名，重入时先找到旧的那块


## 在 target 上盖一层全屏透明挡板，duration 秒内吞掉所有点击（防连点、防动画期误触）
func block_input_briefly(target: Control, duration: float = 1.5) -> void:
	if not is_instance_valid(target) or duration <= 0.0:
		return
	# 已经有挡板就先干掉，重新计时
	var existing := target.get_node_or_null(NodePath(_INPUT_BLOCKER_NAME))
	if existing != null:
		target.remove_child(existing)
		existing.queue_free()
	# 全屏、拦鼠标、z_index 拉到最高
	var blocker := Control.new()
	blocker.name = _INPUT_BLOCKER_NAME # 固定名字，方便重入时找到上一块
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP # STOP：吃掉事件，不继续往下传
	blocker.z_index = 4095 # 4095：比常规页面/弹窗高得多，用来压住下面所有控件
	blocker.z_as_relative = false
	target.add_child(blocker)
	# 计时到点自己 queue_free；期间 target 被释放也不会报错
	var blocker_ref: WeakRef = weakref(blocker)
	target.get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			var current: Control = blocker_ref.get_ref()
			if is_instance_valid(current):
				current.queue_free()
	)


# ================= 模态遮罩目标 =================
## 窗口归属本管理器；遮罩组件只需要目标节点，不接触缓存或注册表。
func _top_mask_window(except_window: UIFrameWindow = null) -> UIFrameWindow:
	var top: UIFrameWindow
	for cached: Variant in _cache.values():
		if not is_instance_valid(cached):
			continue
		var win := cached as UIFrameWindow
		if win == except_window or not win.visible or not win.show_mask:
			continue
		if not win.is_showing() and win.get_window_state() != UIBaseWindow.WindowState.CLOSING:
			continue
		if top == null or win.z_index > top.z_index:
			top = win
	return top


## 产品可覆写安全区规则；通用窗口层不认识任何页面名。
func _apply_safe_area(_page_name: String, _node: Node) -> void:
	pass


# ================= 异步加载 / 预热 =================
var _loading: Dictionary = {} # 窗口名 -> 正在后台加载中，用来做并发去重


## 异步版 show_ui：场景走线程加载，避免大页面同步 load 卡帧；已在加载中则等它结束
func show_ui_async(ui_name: String, params: Dictionary = {}) -> UIFrameWindow:
	if _is_disposing:
		return null
	# 名字校验同 show_ui
	if not _registry.has(ui_name):
		push_error("UIWindowManager: unknown ui '%s'" % ui_name)
		return null
	# 已经实例化过：不用异步，直接走同步路径
	if _cache.has(ui_name) and is_instance_valid(_cache[ui_name]):
		return show_ui(ui_name, params)

	# 别人正在加载同一个页面：等它加载完再用缓存显示，不重复发起加载
	if _loading.has(ui_name):
		while _loading.has(ui_name):
			await get_tree().process_frame
			if _is_disposing or not is_inside_tree():
				return null
		if _cache.has(ui_name) and is_instance_valid(_cache[ui_name]):
			return show_ui(ui_name, params)
		return null
	# 线程加载 → 实例化入缓存 → 交给同步 show_ui 完成显示
	var packed: PackedScene = await _load_scene_async(ui_name)
	if packed == null or _is_disposing or not is_inside_tree():
		return null
	if _create_and_cache(ui_name, packed) == null:
		return null
	return show_ui(ui_name, params)


## 异步预热：后台加载并实例化后保持隐藏（进游戏前先铺路）
func warm_pool_async(ui_name: String) -> void:
	# 已经有缓存、或正在加载，就不用再来一次
	if _is_disposing or get_ui(ui_name) != null or _loading.has(ui_name):
		return
	if not _registry.has(ui_name):
		return
	var packed: PackedScene = await _load_scene_async(ui_name)
	if packed == null or _is_disposing or not is_inside_tree():
		return
	# 加载期间同步入口可能已创建并显示页面；预热不能把它覆盖或隐藏。
	if get_ui(ui_name) != null:
		return
	var win: UIFrameWindow = _create_and_cache(ui_name, packed)
	if win != null and win.is_hidden():
		win.visible = false


## 线程加载场景并等到结束；_loading 在整个过程中占位去重
func _load_scene_async(ui_name: String) -> PackedScene:
	# 先占位，避免并发重复加载
	_loading[ui_name] = true
	var path: String = _registry[ui_name]
	# 发起线程加载并每帧轮询，直到状态不再是 IN_PROGRESS
	var requested: Error = ResourceLoader.load_threaded_request(path)
	if requested != OK:
		_loading.erase(ui_name)
		push_error("UIWindowManager: async request failed '%s' (%d)" % [path, requested])
		return null
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		if _is_disposing or not is_inside_tree():
			_loading.erase(ui_name)
			return null
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		_loading.erase(ui_name)
		push_error("UIWindowManager: async load failed '%s'" % path)
		return null
	var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
	# 无论成败都清掉占位；失败时报错返回 null
	_loading.erase(ui_name)
	if packed == null:
		push_error("UIWindowManager: async load failed '%s'" % path)
	return packed


## 创建期间不向调用者发布实例；window_created 发出时才允许重入显示。
func _create_and_cache(ui_name: String, packed: PackedScene) -> UIFrameWindow:
	# 同步显示和异步预热共用一个实例；加载完成不代表仍需要创建。
	var cached: UIFrameWindow = get_ui(ui_name)
	if cached != null:
		return cached
	if _creating.has(ui_name) or _is_disposing:
		return null
	var request := {"cancelled": false}
	_creating[ui_name] = request
	# 根节点必须是 UIFrameWindow，否则报错并释放（注册表和场景对不上时能立刻发现）
	var node : Node = packed.instantiate()
	var win : UIFrameWindow = node as UIFrameWindow
	if win == null:
		_creating.erase(ui_name)
		push_error("UIWindowManager: '%s' root must extend UIFrameWindow" % ui_name)
		if is_instance_valid(node):
			node.queue_free()
		return null
	# 把自己的注册名写回窗口，窗口内部调 hide_ui 时要用
	win._ui_name = ui_name
	win.configure_ui(_sound_player, _scene_preparer)
	win.close_requested.connect(hide_ui.bind(ui_name))
	win.tree_exiting.connect(_on_window_exiting.bind(ui_name, win))
	_cache[ui_name] = win
	if _scene_preparer.is_valid():
		_scene_preparer.call(node)
	if not _creation_is_valid(ui_name, win, request):
		_discard_creation(ui_name, win, request)
		return null
	# 挂在 current_scene 下，而不是管理器自己身上
	var host: Node = get_tree().current_scene
	if not is_instance_valid(host) or host.is_queued_for_deletion():
		_discard_creation(ui_name, win, request)
		return null
	host.add_child(win)
	if not _creation_is_valid(ui_name, win, request) or not win.is_inside_tree() or win.get_parent() != host:
		_discard_creation(ui_name, win, request)
		return null
	win._do_create()
	if not _creation_is_valid(ui_name, win, request) or not win.is_inside_tree() or win.get_parent() != host:
		_discard_creation(ui_name, win, request)
		return null
	_creating.erase(ui_name)
	# 创建完成事件：此时还没显示
	events.window_created.emit(ui_name, win)
	return win if _is_live_window(ui_name, win) else null


func _creation_is_valid(ui_name: String, win: Variant, request: Dictionary) -> bool:
	return not _is_disposing and not is_queued_for_deletion() and is_inside_tree() and is_same(_creating.get(ui_name), request) \
		and not request.cancelled and is_instance_valid(win) and not win.is_queued_for_deletion() \
		and _cache.get(ui_name) == win and win.get_window_state() != UIBaseWindow.WindowState.DESTROYED


func _discard_creation(ui_name: String, win: Variant, request: Dictionary) -> void:
	if is_same(_creating.get(ui_name), request):
		_creating.erase(ui_name)
	if _cache.get(ui_name) == win:
		_cache.erase(ui_name)
	if is_instance_valid(win):
		if win.is_node_ready():
			win._do_destroy()
		if is_instance_valid(win):
			win.queue_free()


## 场景切换或宿主直接释放窗口时，也必须同步清理缓存、栈和遮罩。
func _on_window_exiting(ui_name: String, win: UIFrameWindow) -> void:
	if _is_disposing or _cache.get(ui_name) != win:
		return
	var was_open: bool = _ordered_windows().has(win)
	_cache.erase(ui_name)
	_pop_stack(win.ui_layer, win)
	win._do_destroy()
	if was_open and win.show_mask:
		_modal_mask.finish_close(null, 0.0)
	# tree_exiting 时父节点仍在移除子节点，不能 move_child 重排遮罩。
	# 请求立即释放；待移除完成后，从最新窗口栈恢复表现。
	_restore_stack_presentation.call_deferred()
	if was_open:
		_publish_hidden(ui_name, win)


func _restore_stack_presentation() -> void:
	if _is_disposing or not is_inside_tree():
		return
	_refresh_occlusion()
	var top: UIFrameWindow = _top_mask_window()
	_modal_mask.restack(top, top.mask_opacity if top != null else 0.0)


## 管理器拥有缓存窗口；宿主释放管理器时同时结束它们的生命周期。
func _exit_tree() -> void:
	_is_disposing = true
	# Godot 的线程加载请求没有取消入口，提交后必须 get 才能释放其内部引用。
	# 仅在管理器退出时等待仍在解析的资源收尾；不会再实例化窗口。
	for ui_name: String in _loading.keys():
		var path: String = _registry[ui_name]
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	_loading.clear()
	_creating.clear()
	for cached: Variant in _cache.values():
		if is_instance_valid(cached):
			var win := cached as UIFrameWindow
			win._do_destroy()
			win.queue_free()
	_cache.clear()
	_stacks.clear()
	_announced_windows.clear()
