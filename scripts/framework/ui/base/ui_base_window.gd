## UI 窗口基类：一个 6 态状态机 + 4 个生命周期钩子，并统一托管信号连接、定时器、每帧回调与子窗口
class_name UIBaseWindow
extends Control

enum WindowState { INVALID, CREATING, SHOWING, HIDDEN, CLOSING, DESTROYED } # 窗口状态：INVALID 未创建 / CREATING 创建中 / SHOWING 显示中 / HIDDEN 已创建未显示 / CLOSING 关闭动画中 / DESTROYED 已销毁

var _window_state: int = WindowState.INVALID # 当前状态；只由 UIWindowManager 和本类的 _do_* 改写，外部用下面三个查询函数读
var _show_revision: int = 0 # 每次显示递增；旧的异步关闭不能收尾到后来显示的同一实例

# 声音提示是窗口语义；具体音频资源与开关由宿主决定。
const SOUND_BUTTON_CLICK: StringName = &"button_click"
const SOUND_WINDOW_OPEN: StringName = &"window_open"
var _sound_player: Callable
var _scene_preparer: Callable


## 由创建窗口的管理器配置；子窗口自动沿用同一组可选回调。
func configure_ui(sound_player: Callable = Callable(), scene_preparer: Callable = Callable()) -> void:
	_sound_player = sound_player
	_scene_preparer = scene_preparer


func _play_ui_sound(cue: StringName) -> void:
	if _sound_player.is_valid():
		_sound_player.call(cue)


## 读原始状态值（需要区分 CLOSING 这类中间态时用）
func get_window_state() -> int:
	return _window_state


## 是否处于已打开生命周期；被全屏窗口遮挡时仍为 true，实际可见性另看 visible。
func is_showing() -> bool:
	return _window_state == WindowState.SHOWING


## 是否已创建但隐藏着
func is_hidden() -> bool:
	return _window_state == WindowState.HIDDEN


## 创建流程（UIWindowManager 首次取窗口时调）：先进 CREATING，给整棵子树的按钮挂点击音效，转 HIDDEN 再回调 on_create
func _do_create() -> void:
	_window_state = WindowState.CREATING
	_attach_button_sounds(self) # 递归给所有 BaseButton 挂 BTN_CLICK，已挂过的会跳过
	_window_state = WindowState.HIDDEN
	var revision: int = _show_revision
	visible = false
	# visibility_changed 同步回调可以关闭/销毁窗口，不能继续调用已失效的创建钩子。
	if not is_instance_valid(self) or is_queued_for_deletion() \
		or _window_state != WindowState.HIDDEN or _show_revision != revision:
		return
	on_create()


## 显示流程：置 SHOWING、显示节点、恢复被隐藏时暂停的定时器，有监听者才开 _process，最后回调 on_show
func _do_show(params: Dictionary = {}) -> void:
	_show_revision += 1
	var revision: int = _show_revision
	_window_state = WindowState.SHOWING
	visible = true
	if not is_instance_valid(self) or is_queued_for_deletion() \
		or _window_state != WindowState.SHOWING or _show_revision != revision:
		return
	_resume_all_timers() # 把 _do_hide 里暂停的托管定时器续跑起来
	if not _update_listeners.is_empty() or not _per_second_listeners.is_empty(): # 没有任何监听者就不开 _process，省掉每帧空转
		set_process(true)
	on_show(params)


## 隐藏流程：先 await 子类 on_hide（通常在这里播退场动画），再复查状态、断连接、停处理、隐藏
func _do_hide() -> void:
	var revision: int = _show_revision
	# @warning_ignore：子类 on_hide 里可能没有 await，这里的 await 会被判成多余
	@warning_ignore("redundant_await")
	await on_hide() # 等子类退场逻辑跑完；期间它若又被 show，会把自己置回 SHOWING

	if revision != _show_revision or _window_state == WindowState.DESTROYED:
		return
	_window_state = WindowState.HIDDEN
	_disconnect_all_managed() # 断开本窗口登记过的所有信号，避免隐藏后还被回调
	_pause_all_timers() # 暂停而不是销毁定时器，下次显示可以接着走
	set_process(false)
	visible = false


## 销毁不等待退场动画：先标记终止并同步销毁子窗口，再回调自身 on_destroy。
func _do_destroy() -> void:
	if _window_state == WindowState.DESTROYED:
		return
	_show_revision += 1
	_window_state = WindowState.DESTROYED
	destroy_all_children()
	on_destroy()
	_disconnect_all_managed()
	_destroy_all_timers()
	_clear_all_listeners()


## 生命周期钩子①：节点已进树、还没显示；子类在这里取子节点、连信号
func on_create() -> void:
	pass


## 生命周期钩子②：每次显示都会调；对已显示的窗口重复 show，UIWindowManager 只调它不走 _do_show
func on_show(params: Dictionary = {}) -> void:
	pass


## 生命周期钩子③：隐藏前调用，可以 await；若期间被重新显示，本次隐藏会被放弃
func on_hide() -> void:
	pass


## 生命周期钩子④：销毁前最后回调，此时子窗口已全拆掉，连接与定时器马上被清理
func on_destroy() -> void:
	pass


# ---- 托管信号连接 ----
var _managed_connections: Array[Dictionary] = [] # 连接登记表：窗口隐藏 / 销毁时统一断开，避免野连接


## 连一个信号并登记，断开时机交给窗口生命周期
func connect_managed(sig: Signal, callable: Callable, flags: int = 0) -> void:
	sig.connect(callable, flags)
	_managed_connections.append({"signal": sig, "callable": callable})


## 同上，但只触发一次（CONNECT_ONE_SHOT）
func connect_managed_once(sig: Signal, callable: Callable) -> void:
	sig.connect(callable, CONNECT_ONE_SHOT)
	_managed_connections.append({"signal": sig, "callable": callable, "one_shot": true})


## 手动断开一个信号并把它从登记表里移除
func disconnect_managed(sig: Signal, callable: Callable) -> void:
	if is_instance_valid(sig.get_object()) and sig.is_connected(callable):
		sig.disconnect(callable)
	_managed_connections = _managed_connections.filter(
		func(c: Dictionary) -> bool: return not (c.signal == sig and c.callable == callable)
	)


## 全部断开并清空登记表（_do_hide 与 _do_destroy 都会调）
func _disconnect_all_managed() -> void:
	for conn in _managed_connections:
		if is_instance_valid(conn.signal.get_object()) and conn.signal.is_connected(conn.callable):
			conn.signal.disconnect(conn.callable)
	_managed_connections.clear()


# ---- 托管定时器 ----
var _managed_timers: Array[Timer] = [] # 本窗口创建并托管的 Timer，随窗口隐藏 / 销毁自动暂停或释放


## 建一个一次性倒计时（单位：秒），挂到本窗口下并立即启动，返回 Timer 供外部取消
func create_countdown(sec: float, callable: Callable) -> Timer:
	var t := Timer.new()
	t.wait_time = sec
	t.one_shot = true
	t.timeout.connect(callable)
	t.timeout.connect(_on_managed_timer_done.bind(t))
	add_child(t)
	t.start()
	_managed_timers.append(t)
	return t


## 建一个循环计时器（单位：秒），用于周期性刷新
func create_tick(interval: float, callable: Callable) -> Timer:
	var t := Timer.new()
	t.wait_time = interval
	t.one_shot = false
	t.timeout.connect(callable)
	add_child(t)
	t.start()
	_managed_timers.append(t)
	return t


## 停止、释放并从托管表移除某个定时器
func remove_timer(timer: Timer) -> void:
	if is_instance_valid(timer):
		timer.stop()
		timer.queue_free()
	_managed_timers.erase(timer)


## 全部暂停（隐藏时调）
func _pause_all_timers() -> void:
	for t in _managed_timers:
		if is_instance_valid(t):
			t.paused = true


## 全部恢复（显示时调）
func _resume_all_timers() -> void:
	for t in _managed_timers:
		if is_instance_valid(t):
			t.paused = false


## 全部停止并 queue_free（销毁时调）
func _destroy_all_timers() -> void:
	for t in _managed_timers:
		if is_instance_valid(t):
			t.stop()
			t.queue_free()
	_managed_timers.clear()


## 一次性倒计时响完后的自动清理：出表并释放
func _on_managed_timer_done(timer: Timer) -> void:
	_managed_timers.erase(timer)
	if is_instance_valid(timer):
		timer.queue_free()


# ---- 每帧 / 每秒监听 ----
var _update_listeners: Array[Callable] = [] # 每帧回调列表
var _per_second_listeners: Array[Callable] = [] # 每秒回调列表（由 _process 用累加器驱动，不依赖系统定时器）
var _per_second_accumulator: float = 0.0 # 秒累加器：攒够 1.0 触发一轮每秒回调并减 1


## 注册每帧回调，并自动打开 _process
func add_update_listener(callable: Callable) -> void:
	_update_listeners.append(callable)
	set_process(true)


## 注册每秒回调，并自动打开 _process
func add_per_second_listener(callable: Callable) -> void:
	_per_second_listeners.append(callable)
	set_process(true)


## 注销每帧回调；两类监听都空了就关 _process
func remove_update_listener(callable: Callable) -> void:
	_update_listeners.erase(callable)
	_check_process_needed()


## 注销每秒回调；两类监听都空了就关 _process
func remove_per_second_listener(callable: Callable) -> void:
	_per_second_listeners.erase(callable)
	_check_process_needed()


## 引擎每帧回调：先跑完所有每帧监听，再按累加器跑每秒监听
func _process(delta: float) -> void:
	for cb in _update_listeners:
		cb.call()
	if not _per_second_listeners.is_empty():
		_per_second_accumulator += delta
		if _per_second_accumulator >= 1.0:
			_per_second_accumulator -= 1.0
			for cb in _per_second_listeners:
				cb.call()


## 没有任何监听者时关掉 _process
func _check_process_needed() -> void:
	if _update_listeners.is_empty() and _per_second_listeners.is_empty():
		set_process(false)


## 清空全部监听并关 _process（销毁时调）
func _clear_all_listeners() -> void:
	_update_listeners.clear()
	_per_second_listeners.clear()
	_per_second_accumulator = 0.0
	set_process(false)


# ---- 子窗口管理 ----
var _managed_children: Array[UIChildWindow] = [] # 本窗口创建的子窗口，窗口被销毁时一并拆掉


## 回调前登记所有权；准备/ready/create/show 可以关闭窗口，已关闭或正在关闭时返回 null。
func create_child(scene: PackedScene, params: Dictionary = {}) -> UIChildWindow:
	if _window_state == WindowState.DESTROYED or is_queued_for_deletion():
		return null
	var node := scene.instantiate()
	var child := node as UIChildWindow
	if child == null:
		push_error("UIBaseWindow: create_child scene root must extend UIChildWindow") # 根节点必须继承 UIChildWindow，否则报错并释放实例
		if node != null:
			node.queue_free()
		return null
	child.configure_ui(_sound_player, _scene_preparer)
	_managed_children.append(child)
	if _scene_preparer.is_valid():
		_scene_preparer.call(child)
	if not _accept_child_creation_step(child):
		return null
	add_child(child)
	if not _accept_child_creation_step(child):
		return null
	child._do_create()
	if not _accept_child_creation_step(child):
		return null
	child._do_show(params)
	return child if _accept_child_creation_step(child) else null


## 回调可能直接释放节点或销毁父窗口；清理失效所有权，异步关闭则沿原退场路径收尾。
func _accept_child_creation_step(child: Variant) -> bool:
	if not is_instance_valid(child):
		# 已释放对象不能再作为 typed Array.erase 的参数，按索引清除失效记录。
		for index: int in range(_managed_children.size() - 1, -1, -1):
			if not is_instance_valid(_managed_children[index]):
				_managed_children.remove_at(index)
		return false
	if child not in _managed_children:
		return false
	if _window_state == WindowState.DESTROYED or is_queued_for_deletion() \
		or child.is_queued_for_deletion() or child.get_window_state() == WindowState.DESTROYED:
		_destroy_child_now(child)
		return false
	return child.get_window_state() != WindowState.CLOSING


## 单独关闭子窗口可以等待退场；期间重新显示会取消这次关闭，父窗口销毁则立即收尾。
func destroy_child(child: UIChildWindow) -> void:
	if not is_instance_valid(child) or child not in _managed_children:
		return
	if child._window_state == WindowState.CLOSING:
		return
	if child._window_state == WindowState.SHOWING: # 只有正在显示的才需要先走隐藏流程
		var revision: int = child._show_revision
		child._window_state = WindowState.CLOSING
		await child._do_hide()
		if not is_instance_valid(child) or child not in _managed_children:
			return
		if child._show_revision != revision or not child.is_hidden():
			return
	_destroy_child_now(child)


func _destroy_child_now(child: UIChildWindow) -> void:
	_managed_children.erase(child)
	if not is_instance_valid(child):
		return
	child._do_destroy()
	child.queue_free()


## 批量销毁同步完成所有 on_destroy，不等待 on_hide；节点内存由 queue_free 在帧末释放。
func destroy_all_children() -> void:
	var children: Array[UIChildWindow] = _managed_children.duplicate()
	_managed_children.clear() # 子窗口的销毁回调重入时不再找到待销毁对象。
	for child in children:
		_destroy_child_now(child)


## 按节点名找托管中的子窗口，找不到返回 null
func get_child_window(child_name: String) -> UIChildWindow:
	for child in _managed_children:
		if is_instance_valid(child) and child.name == child_name:
			return child
	return null


# ---- 按钮点击音效 ----
const _BTN_SOUND_BOUND_META: StringName = &"_btn_click_sound_bound" # 元数据键：标记按钮已挂过点击音效，避免重复连接同一实例


## 递归整棵子树，给每个 BaseButton 的按下动作接一声 BTN_CLICK
func _attach_button_sounds(node: Node) -> void:
	if node is BaseButton:
		var b := node as BaseButton
		if not b.has_meta(_BTN_SOUND_BOUND_META):
			b.set_meta(_BTN_SOUND_BOUND_META, true)
			b.button_down.connect(_play_ui_sound.bind(SOUND_BUTTON_CLICK))
	for child in node.get_children():
		_attach_button_sounds(child)


## 外部已自行处理音效的按钮调它打标，免得被自动再挂一次
func claim_button_sound(button: BaseButton) -> void:
	if is_instance_valid(button):
		button.set_meta(_BTN_SOUND_BOUND_META, true)


# ---- 缩放反馈 / 节点查找 ----
## 按下缩放反馈，转发给 UIHelper（手感参数统一在那边）
func play_press_scale(node: CanvasItem, base_scale: Vector2 = Vector2.ONE) -> void:
	UIHelper.play_press_scale(node, base_scale)


## 松开回弹，转发给 UIHelper
func play_release_scale(node: CanvasItem, base_scale: Vector2 = Vector2.ONE) -> void:
	UIHelper.play_release_scale(node, base_scale)


## 给按钮一次性绑定按下 / 松开缩放
func bind_press_release_scale(button: BaseButton, base_scale: Vector2 = Vector2.ONE) -> void:
	UIHelper.bind_press_release_scale(button, base_scale)


## 递归按名字找节点（不限定 owner）
func find_node_by_name(node_name: String) -> Node:
	return find_child(node_name, true, false)


# ---- 引擎回调 ----
## 进树后先关掉 _process：等有监听者注册时再开
func _ready() -> void:
	set_process(false)


## 节点被删除时兜底拆掉所有子窗口，防止子窗口泄漏
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		destroy_all_children()
