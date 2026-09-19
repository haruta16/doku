# UI 管理器（autoload 单例 UIManager）：页面注册、显示/隐藏、层级栈、全局遮罩、安全区适配的唯一入口
# 用法：UIManager.show_ui(UiName.XXX, params) / hide_ui(UiName.XXX)；窗口实例常驻缓存，隐藏不销毁
extends Node

# ---- 注册表与缓存（key 都是 UiName 常量） ----
var _registry: Dictionary = {} # UiName -> 场景路径，_ready 时由 UIRegistry.build_registry 填充
var _cache: Dictionary = {} # UiName -> 已实例化的 UIFrameWindow（常驻复用，隐藏不销毁）
var _stacks: Dictionary = {} # layer -> 该层窗口栈，数组尾部是栈顶（最后显示的那个）
var _next_z: Dictionary = {} # layer -> 下一个可用的 z_index（每开一个窗口 +Z_STEP）
var events: UIEvents = UIEvents.new() # 对外事件总线：window_created / window_shown / window_hidden

# ---- 全局遮罩（运行时 new 出来的 ColorRect，不进场景文件） ----
var _mask: ColorRect = null # 主遮罩：盖住它下面所有内容
var _mask_ref_count: int = 0 # 引用计数：还有几个窗口要遮罩，归零才真的收起来
var _mask_tween: Tween = null # 主遮罩的淡入淡出 tween

var _mask_secondary: ColorRect = null # 副遮罩：两个带遮罩的窗口交接时做交叉淡化（旧的淡出、新的淡入）
var _mask_secondary_tween: Tween = null # 副遮罩的 tween

# ---- 埋点旁听 ----
var _tracker_observer: UITrackerObserver = null # 订阅 events.window_shown，把曝光上报转给 Tracker


# ================= 生命周期 =================
# 启动时建注册表并挂上埋点观察者（UIManager 是 autoload，比任何页面都早）
func _ready() -> void:
	_registry = UIRegistry.build_registry()
	_tracker_observer = UITrackerObserver.new(events)


# ================= 显示 / 隐藏（对外主入口） =================
# 显示页面：查表 → 取/建实例 → 定层入栈 → 起遮罩 → 真正 show；返回窗口给调用方用
func show_ui(ui_name: String, params: Dictionary = {}) -> UIFrameWindow:
	# 名字不在注册表里＝写错，或者这个构建根本没注册它（调试页在 Android 上就没有）
	if not _registry.has(ui_name):
		push_error("UIManager: unknown ui '%s'" % ui_name)
		return null
	# 命中缓存就复用，未命中才 load 场景
	var win: UIFrameWindow = _get_or_create(ui_name)
	if win == null:
		return null
	# 已经在显示：只补一次 on_show(params) 刷新参数，不入栈、不重播动画
	if win.is_showing():
		win.on_show(params)
		return win
	# 关闭动画途中又被打开：打断关闭，当作没关过
	# was_closing 决定后面要不要重发埋点、要不要重挂遮罩
	var was_closing: bool = win._window_state == UIBaseWindow.WindowState.CLOSING
	if was_closing:
		win._abort_close_animation()
	# 定层、发 z_index、按平台做安全区适配
	var layer: int = win.ui_layer
	_assign_z_index(win, layer)
	_apply_safe_area(ui_name, win)
	# 遮罩分两种：正常显示才淡入；被打断的关闭则复用还在淡出的那张，不重来一遍
	if win.show_mask and not was_closing:
		_show_mask(win.mask_opacity)
	# 打断场景：先把交叉淡化收尾成单张，再把不透明度拉回目标值
	elif win.show_mask and was_closing and _mask != null and is_instance_valid(_mask):
		_abort_mask_crossfade()
		_kill_mask_tween()
		_mask.color = Color(0, 0, 0, win.mask_opacity)
		_mask.visible = true
	# 先入栈（同层最后显示的在栈顶），再真正显示：visible=true、on_show、开场动画
	_push_stack(layer, win)
	win._do_show(params)

	# 遮罩要贴在自己下面一格，每显示一个带遮罩的窗口就重排一次
	if win.show_mask and _mask != null and is_instance_valid(_mask):
		_restack_mask()

	# 关闭被打断时不重复发 window_shown，避免埋点重复计数
	if not was_closing:
		events.window_shown.emit(ui_name, win)
	# 全屏页面会盖住下面所有窗口，需要重算遮挡链
	if win.is_fullscreen:
		_refresh_occlusion()
	return win


# 隐藏页面：置 CLOSING → 收遮罩 → 播关闭动画 → on_hide → 出栈并发 window_hidden
func hide_ui(ui_name: String) -> void:
	# 没有缓存、或本来就没显示：直接返回（重复 hide 是安全的）
	var cached: Variant = _cache.get(ui_name, null)
	var win: UIFrameWindow = cached as UIFrameWindow if is_instance_valid(cached) else null
	if win == null or not win.is_showing():
		return
	# 先置 CLOSING：关闭动画期间 show_ui 靠这个状态判断能否打断
	win._window_state = UIBaseWindow.WindowState.CLOSING

	# 遮罩的淡出时长要跟关闭动画对齐，先问窗口要
	var _hide_duration: float = win.get_hide_anim_duration()
	# 还有别的窗口需要遮罩就交叉淡化交接，否则整张淡出
	if win.show_mask and _mask != null and is_instance_valid(_mask) and _mask.visible:
		if _mask_ref_count <= 1:
			_fade_out_mask(_hide_duration)
		else:
			_start_mask_crossfade(win, _hide_duration)
	# 等关闭动画播完；期间若被 show_ui 打断，状态会被改回 SHOWING，这里就放弃收尾
	await win._play_close_animation()
	if win._window_state != UIBaseWindow.WindowState.CLOSING:
		return
	# 弹窗要从 Tracker 的来源栈里弹掉（普通页面不用）
	var dlg: String = win.get_dlg_name()
	if dlg != "":
		Tracker.notify_dlg_closed(dlg)
	# on_hide 钩子：内部还会断开 connect_managed 的连接、暂停托管定时器
	await win._do_hide()

	# 收尾前再确认一次状态：期间被打断过就什么都不做
	if win._window_state == UIBaseWindow.WindowState.SHOWING:
		return
	# 遮罩引用计数 -1，减到 0 才真的收起来
	if win.show_mask:
		_hide_mask()
	# 出栈
	var layer: int = win.ui_layer
	_pop_stack(layer, win)

	# 广播隐藏完成（弹窗队列靠它接着弹下一个）；再重算遮挡链
	events.window_hidden.emit(ui_name, win)
	_refresh_occlusion()


# ================= 查询 =================
func get_ui(ui_name: String) -> UIFrameWindow:
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		return cached as UIFrameWindow
	return null


# 这个页面当前是否已经创建过（只看缓存，不触发创建）
func has_ui(ui_name: String) -> bool:
	return get_ui(ui_name) != null


# ================= 批量收起 =================
func hide_all() -> void:
	for ui_name in _cache.keys():
		var cached: Variant = _cache[ui_name]
		if is_instance_valid(cached) and (cached as UIFrameWindow).visible:
			hide_ui(ui_name)


# 收起除名单外的所有已显示页面（名单里的保持原样）
func hide_all_except(names: Array[String]) -> void:
	for ui_name in _cache.keys():
		if ui_name in names:
			continue
		var cached: Variant = _cache[ui_name]
		if is_instance_valid(cached) and (cached as UIFrameWindow).visible:
			hide_ui(ui_name)


# ================= 创建与缓存 =================
func _get_or_create(ui_name: String) -> UIFrameWindow:
	# 命中缓存
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		var win : UIFrameWindow = cached as UIFrameWindow
		# 父节点没了（例如 current_scene 被换掉）→ 重新挂到当前场景根
		if win.get_parent() == null:
			get_tree().current_scene.add_child(win)
		else:
			# 还挂在树上 → 提到最后一个子节点，保证后显示的画在上面
			win.get_parent().move_child(win, -1)
		return win
	# 没缓存才真的 load 场景并实例化
	var packed: PackedScene = load(_registry[ui_name])
	if packed == null:
		push_error("UIManager: cannot load '%s'" % _registry[ui_name]) # 加载失败只报错，返回 null
		return null
	return _create_and_cache(ui_name, packed)


# 入栈：同层做过就把旧的挪到栈顶（重新显示算最新）
func _push_stack(layer: int, win: UIFrameWindow) -> void:
	if not _stacks.has(layer):
		_stacks[layer] = []
	var stack: Array = _stacks[layer]
	stack.erase(win)
	stack.append(win)


# 出栈：把窗口从它那一层的栈里删掉
func _pop_stack(layer: int, win: UIFrameWindow) -> void:
	if _stacks.has(layer):
		_stacks[layer].erase(win)


# ================= 层级栈与遮挡 =================
func _ordered_windows() -> Array[UIFrameWindow]:
	var ordered: Array[UIFrameWindow] = []
	var layers: Array = _stacks.keys()
	layers.sort()
	for l: int in layers:
		for win: UIFrameWindow in _stacks[l]:
			ordered.append(win)
	return ordered


# 从栈顶往下扫：第一个全屏窗口之上都可见，被它盖住的窗口隐藏并回调 on_stack_bottom
func _refresh_occlusion() -> void:
	var ordered: Array[UIFrameWindow] = _ordered_windows()
	var occluded: bool = false
	# 从栈顶（最后显示的）往前遍历
	for i in range(ordered.size() - 1, -1, -1):
		var win: UIFrameWindow = ordered[i]
		if not is_instance_valid(win):
			continue
		# 只要上面还没出现全屏窗口，就该可见
		var should_visible: bool = not occluded
		# 由隐藏变可见：回调 on_stack_top，页面在这里恢复动效/计时
		if should_visible and not win.visible:
			win.visible = true
			win.on_stack_top()
		# 被上层全屏挡住的：隐藏并回调 on_stack_bottom
		elif not should_visible and win.visible:
			win.visible = false
			win.on_stack_bottom()
		# 遇到全屏页面，再往下就全部判为被遮挡
		if should_visible and win.is_fullscreen:
			occluded = true


# 分配 z_index：每层从 layer 基址起按 Z_STEP 递增，保证后开的更高
func _assign_z_index(win: UIFrameWindow, layer: int) -> void:
	# 该层第一次用到，起点就是层基址
	if not _next_z.has(layer):
		_next_z[layer] = layer
	# 涨到上限就先重排一次，避免无限增长
	if _next_z[layer] >= layer + UILayerConfig.Z_MAX:
		_compact_z_indices(layer)
	# 取当前值，再为下一个窗口预留
	win.z_index = _next_z[layer]
	_next_z[layer] += UILayerConfig.Z_STEP


# 压缩重排：只保留可见窗口，按原 z_index 顺序重新均匀分配
func _compact_z_indices(layer: int) -> void:
	var stack: Array = _stacks.get(layer, [])
	var visible_wins: Array[UIFrameWindow] = []
	for win: UIFrameWindow in stack:
		if win.visible:
			visible_wins.append(win)
	# 按 z_index 升序排，保住原来的上下关系
	visible_wins.sort_custom(
		func(a: UIFrameWindow, b: UIFrameWindow) -> bool: return a.z_index < b.z_index
	)
	for i in visible_wins.size():
		visible_wins[i].z_index = layer + i * UILayerConfig.Z_STEP
	_next_z[layer] = layer + visible_wins.size() * UILayerConfig.Z_STEP


# 整层显示/隐藏；注意直接改 visible，不会触发 on_stack_top / on_stack_bottom 回调
func set_layer_visible(layer: int, is_visible: bool) -> void:
	var stack: Array = _stacks.get(layer, [])
	for win: UIFrameWindow in stack:
		win.visible = is_visible


# 某层栈里有几个窗口（含当前不可见的）
func get_window_count(layer: int) -> int:
	return _stacks.get(layer, []).size()


# 预热：提前实例化并保持隐藏，避免第一次打开时卡在加载
func warm_pool(ui_name: String) -> void:
	if _cache.has(ui_name):
		return
	_get_or_create(ui_name)
	var cached: Variant = _cache.get(ui_name, null)
	if is_instance_valid(cached):
		(cached as UIFrameWindow).visible = false


# Android 返回键：Godot 把它转成这个通知
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_button()


# Esc / ui_cancel 走同一条返回逻辑，并标记已处理，避免继续往下传
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button()
		get_viewport().set_input_as_handled()


# 返回：从最高层的栈顶往下找第一个可见窗口，交给它 on_escape()；只处理这一个
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


# 在 target 上盖一层全屏透明挡板，duration 秒内吞掉所有点击（防连点、防动画期误触）
func block_input_briefly(target: Control, duration: float = 1.5) -> void:
	if target == null or duration <= 0.0:
		return
	# 已经有挡板就先干掉，重新计时
	var existing := target.get_node_or_null(NodePath(_INPUT_BLOCKER_NAME))
	if existing != null:
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
	target.get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if is_instance_valid(blocker):
				blocker.queue_free()
	)


# 请求显示遮罩：引用计数 +1，不透明度和堆叠位置都按当前窗口刷新
func _show_mask(opacity: float) -> void:
	_mask_ref_count += 1 # 有一个窗口算一个，最后一个走了才收

	# 可能正处在交叉淡化中，先收尾成单张
	_abort_mask_crossfade()
	# 第一次用到才创建（手搓 ColorRect，挂在 current_scene 下）
	if _mask == null or not is_instance_valid(_mask):
		_mask = ColorRect.new()
		_mask.name = "_GlobalMask"
		_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_mask.mouse_filter = Control.MOUSE_FILTER_STOP
		get_tree().current_scene.add_child(_mask)

	# 杀掉旧 tween，直接给到「完全不透明」的目标状态
	_kill_mask_tween()
	_mask.color = Color(0, 0, 0, opacity)
	_mask.z_as_relative = false
	_mask.visible = true


# 请求收起遮罩：引用计数 -1
func _hide_mask() -> void:
	# 归零：副遮罩直接干掉；主遮罩只在没有淡出 tween 时才隐藏
	_mask_ref_count -= 1
	if _mask_ref_count <= 0:
		_mask_ref_count = 0

		_kill_mask_secondary_tween()
		if _mask_secondary != null and is_instance_valid(_mask_secondary):
			_mask_secondary.visible = false
		if _mask != null and is_instance_valid(_mask):
			if _mask_tween == null or not _mask_tween.is_valid():
				_mask.visible = false
	# 还没归零：若副遮罩正在显示（交叉淡化中）就把两张角色对调，否则重排遮罩位置
	elif _mask != null and is_instance_valid(_mask):
		if (
			_mask_secondary != null
			and is_instance_valid(_mask_secondary)
			and _mask_secondary.visible
		):
			_kill_mask_tween()
			_kill_mask_secondary_tween()
			var old_primary := _mask
			_mask = _mask_secondary
			_mask_secondary = old_primary
			old_primary.visible = false
			_mask_tween = null
		else:
			_restack_mask()


# 把遮罩贴到「最上面那个需要遮罩的窗口」下面一格：z_index 与同级子节点顺序一起调
func _restack_mask() -> void:
	if _mask == null or not is_instance_valid(_mask):
		return
	var top_win: UIFrameWindow = null
	# 找 z_index 最大且 show_mask 的可见窗口
	for ui_name: String in _cache.keys():
		var cached: Variant = _cache[ui_name]
		if not is_instance_valid(cached):
			continue
		var win: UIFrameWindow = cached as UIFrameWindow
		if win.visible and win.show_mask and (top_win == null or win.z_index > top_win.z_index):
			top_win = win
	if top_win == null:
		return
	# 不透明度和 z 对齐这个窗口，正好压在它下面一层
	_mask.color = Color(0, 0, 0, top_win.mask_opacity)
	_mask.z_index = top_win.z_index - 1
	# 同一个父节点下还要调整子节点顺序：move_child 到它前面
	var parent: Node = _mask.get_parent()
	if parent != null and top_win.get_parent() == parent:
		var target: int = top_win.get_index()

		if _mask.get_index() < top_win.get_index():
			target -= 1
		parent.move_child(_mask, target)


# 遮罩整体淡出；duration <= 0 就直接隐藏
func _fade_out_mask(duration: float) -> void:
	if _mask == null or not is_instance_valid(_mask):
		return
	_kill_mask_tween()
	if duration <= 0.0:
		_mask.visible = false
		return
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask, "color:a", 0.0, duration)
	_mask_tween.tween_callback(
		func() -> void:
			if _mask != null and is_instance_valid(_mask):
				_mask.visible = false
	)


# 杀掉主遮罩的 tween 并置空（凡是要直接改遮罩状态的地方都先调它）
func _kill_mask_tween() -> void:
	if _mask_tween != null and _mask_tween.is_valid():
		_mask_tween.kill()
	_mask_tween = null


# 同上，针对副遮罩
func _kill_mask_secondary_tween() -> void:
	if _mask_secondary_tween != null and _mask_secondary_tween.is_valid():
		_mask_secondary_tween.kill()
	_mask_secondary_tween = null


# 交叉淡化还没播完就被打断：把副遮罩顶上主位，旧主遮罩直接隐藏
func _abort_mask_crossfade() -> void:
	if (
		_mask_secondary == null
		or not is_instance_valid(_mask_secondary)
		or not _mask_secondary.visible
	):
		return
	_kill_mask_tween()
	_kill_mask_secondary_tween()
	var old_primary := _mask
	_mask = _mask_secondary
	_mask_secondary = old_primary
	if old_primary != null and is_instance_valid(old_primary):
		old_primary.visible = false


# 关闭中的窗口把遮罩交接给下一个窗口：旧遮罩淡出、新遮罩淡入，两者时长一致
func _start_mask_crossfade(closing_win: UIFrameWindow, duration: float) -> void:
	# 找除自己以外、z_index 最高且需要遮罩的可见窗口
	var next_top: UIFrameWindow = null
	for ui_name: String in _cache.keys():
		var cached: Variant = _cache[ui_name]
		if not is_instance_valid(cached):
			continue
		var win: UIFrameWindow = cached as UIFrameWindow
		if win == closing_win or not win.visible or not win.show_mask:
			continue
		if next_top == null or win.z_index > next_top.z_index:
			next_top = win
	# 后面没有别的窗口要遮罩：退回整体淡出
	if next_top == null:
		_fade_out_mask(duration)
		return

	# 副遮罩按需创建，先设成全透明再淡入
	_kill_mask_secondary_tween()
	if _mask_secondary == null or not is_instance_valid(_mask_secondary):
		_mask_secondary = ColorRect.new()
		_mask_secondary.name = "_GlobalMask2"
		_mask_secondary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_mask_secondary.mouse_filter = Control.MOUSE_FILTER_STOP
		get_tree().current_scene.add_child(_mask_secondary)
	_mask_secondary.z_as_relative = false
	_mask_secondary.z_index = next_top.z_index - 1
	_mask_secondary.color = Color(0, 0, 0, 0)
	_mask_secondary.visible = true

	# 同样调整同级顺序，保证贴在那个窗口下面
	var parent: Node = _mask_secondary.get_parent()
	if parent != null and next_top.get_parent() == parent:
		var target: int = next_top.get_index()
		if _mask_secondary.get_index() < next_top.get_index():
			target -= 1
		parent.move_child(_mask_secondary, target)

	# duration <= 0（关闭动画时长为 0）：不做过渡，直接就位
	_kill_mask_tween()
	if duration <= 0.0:
		_mask.visible = false
		_mask_secondary.color = Color(0, 0, 0, next_top.mask_opacity)
		return
	# 两条 tween 同时跑：旧的透明度到 0 后隐藏，新的升到目标不透明度
	_mask_tween = create_tween()
	_mask_tween.tween_property(_mask, "color:a", 0.0, duration)
	_mask_tween.tween_callback(
		func() -> void:
			if _mask != null and is_instance_valid(_mask):
				_mask.visible = false
	)
	_mask_secondary_tween = create_tween()
	_mask_secondary_tween.tween_property(
		_mask_secondary, "color:a", next_top.mask_opacity, duration
	)


# ================= 刘海屏 / 安全区适配 =================
const _SAFE_TOP_GROUP: StringName = &"_safe_top" # 需要贴顶部安全区的节点分组名（.tscn 里挂 group）
const _SAFE_BOTTOM_GROUP: StringName = &"_safe_bottom" # 需要贴底部安全区的节点分组名
const _SAFE_TOP_BASELINE_META: StringName = &"_safe_top_baseline" # 顶部节点基线 offset 的 meta 键：只记一次，避免反复叠加
const _SAFE_BOTTOM_BASELINE_META: StringName = &"_safe_bottom_baseline" # 底部节点基线 offset 的 meta 键
const _COLLAPSE_WHEN_TOP_SAFE_GROUP: StringName = &"_collapse_when_top_safe" # 顶部有刘海时应该收起来的分组名
const _COLLAPSE_BASELINE_META: StringName = &"_collapse_when_top_safe_baseline" # 这类节点 可见性 / 最小高度 / 垂直尺寸标志 的基线 meta 键

# 只对这几个页面做安全区适配，弹窗等其它页面自己处理
const _SAFE_AREA_PAGES: Array[StringName] = [
	&"home",
	&"game",
	&"daily_game",
	&"win",
	&"fail",
	&"setting",
	&"bank",
]


# 把安全区插入量加到被标记节点的 offset 上；只在 Android/iOS 且页面在白名单里时执行
func _apply_safe_area(page_name: String, node: Node) -> void:
	# 桌面平台没有安全区，直接跳过
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return
	# 页面不在白名单里就整页跳过
	if not _SAFE_AREA_PAGES.has(StringName(page_name)):
		return
	# safe.position.y 是顶部刘海高度；底部插入量＝窗口高 −（安全区顶 + 安全区高）
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win_size: Vector2i = DisplayServer.window_get_size()
	var top_inset: float = float(safe.position.y)
	var bottom_inset: float = float(win_size.y - (safe.position.y + safe.size.y))
	# 没有刘海也没有底部横条：什么都不用做
	if top_inset <= 0.0 and bottom_inset <= 0.0:
		return
	# 遍历页面上所有 Control；is_absolute 表示上下锚点相同（高度自己撑），另一条边也要同步挪
	for n in node.find_children("*", "Control", true, false):
		var c := n as Control
		var is_absolute: bool = is_equal_approx(c.anchor_top, c.anchor_bottom)
		# _safe_top 组：整体下移顶部插入量；基线只记录一次，反复显示不会累加
		if c.is_in_group(_SAFE_TOP_GROUP):
			if not c.has_meta(_SAFE_TOP_BASELINE_META):
				c.set_meta(_SAFE_TOP_BASELINE_META, Vector2(c.offset_top, c.offset_bottom))
			var baseline: Vector2 = c.get_meta(_SAFE_TOP_BASELINE_META)
			c.offset_top = baseline.x + top_inset
			if is_absolute:
				c.offset_bottom = baseline.y + top_inset
		# _safe_bottom 组：整体上移底部插入量
		if c.is_in_group(_SAFE_BOTTOM_GROUP):
			if not c.has_meta(_SAFE_BOTTOM_BASELINE_META):
				c.set_meta(_SAFE_BOTTOM_BASELINE_META, Vector2(c.offset_top, c.offset_bottom))
			var baseline: Vector2 = c.get_meta(_SAFE_BOTTOM_BASELINE_META)
			c.offset_bottom = baseline.y - bottom_inset
			if is_absolute:
				c.offset_top = baseline.x - bottom_inset
		# _collapse_when_top_safe 组：有刘海就直接隐藏并清零高度给内容腾地方，没刘海恢复基线
		if c.is_in_group(_COLLAPSE_WHEN_TOP_SAFE_GROUP):
			if not c.has_meta(_COLLAPSE_BASELINE_META):
				c.set_meta(
					_COLLAPSE_BASELINE_META,
					[c.visible, c.custom_minimum_size.y, c.size_flags_vertical]
				)
			var baseline: Array = c.get_meta(_COLLAPSE_BASELINE_META)
			if top_inset > 0.0:
				c.visible = false
				c.custom_minimum_size.y = 0.0
				c.size_flags_vertical = 0
			else:
				c.visible = bool(baseline[0])
				c.custom_minimum_size.y = float(baseline[1])
				c.size_flags_vertical = int(baseline[2])


# ================= 异步加载 / 预热 =================
var _loading: Dictionary = {} # UiName -> 正在后台加载中，用来做并发去重


# 异步版 show_ui：场景走线程加载，避免大页面同步 load 卡帧；已在加载中则等它结束
func show_ui_async(ui_name: String, params: Dictionary = {}) -> UIFrameWindow:
	# 名字校验同 show_ui
	if not _registry.has(ui_name):
		push_error("UIManager: unknown ui '%s'" % ui_name)
		return null
	# 已经实例化过：不用异步，直接走同步路径
	if _cache.has(ui_name) and is_instance_valid(_cache[ui_name]):
		return show_ui(ui_name, params)

	# 别人正在加载同一个页面：等它加载完再用缓存显示，不重复发起加载
	if _loading.has(ui_name):
		while _loading.has(ui_name):
			await get_tree().process_frame
		if _cache.has(ui_name) and is_instance_valid(_cache[ui_name]):
			return show_ui(ui_name, params)
		return null
	# 线程加载 → 实例化入缓存 → 交给同步 show_ui 完成显示
	var packed: PackedScene = await _load_scene_async(ui_name)
	if packed == null:
		return null
	_create_and_cache(ui_name, packed)
	return show_ui(ui_name, params)


# 异步预热：后台加载并实例化后保持隐藏（进游戏前先铺路）
func warm_pool_async(ui_name: String) -> void:
	# 已经有缓存、或正在加载，就不用再来一次
	if _cache.has(ui_name) or _loading.has(ui_name):
		return
	if not _registry.has(ui_name):
		return
	var packed: PackedScene = await _load_scene_async(ui_name)
	if packed == null:
		return
	var win: UIFrameWindow = _create_and_cache(ui_name, packed)
	if win != null:
		win.visible = false


# 线程加载场景并等到结束；_loading 在整个过程中占位去重
func _load_scene_async(ui_name: String) -> PackedScene:
	# 先占位，避免并发重复加载
	_loading[ui_name] = true
	var path: String = _registry[ui_name]
	# 发起线程加载并每帧轮询，直到状态不再是 IN_PROGRESS
	ResourceLoader.load_threaded_request(path)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
	# 无论成败都清掉占位；失败时报错返回 null
	_loading.erase(ui_name)
	if packed == null:
		push_error("UIManager: async load failed '%s'" % path)
	return packed


# 实例化、挂到当前场景根、写缓存、跑 _do_create 并发 window_created
func _create_and_cache(ui_name: String, packed: PackedScene) -> UIFrameWindow:
	# 根节点必须是 UIFrameWindow，否则报错并释放（注册表和场景对不上时能立刻发现）
	var node : Node = packed.instantiate()
	var win : UIFrameWindow = node as UIFrameWindow
	if win == null:
		push_error("UIManager: '%s' root must extend UIFrameWindow" % ui_name)
		node.queue_free()
		return null
	# 把自己的注册名写回窗口，窗口内部调 hide_ui 时要用
	win._ui_name = ui_name
	# 挂在 current_scene 下，而不是 UIManager 自己身上
	get_tree().current_scene.add_child(win)
	_cache[ui_name] = win
	win._do_create()
	# 创建完成事件：此时还没显示
	events.window_created.emit(ui_name, win)
	return win
