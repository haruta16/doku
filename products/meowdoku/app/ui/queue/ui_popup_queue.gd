## 弹窗队列：按优先级串行调度；窗口隐藏/取消或业务 callable 返回后，才推进下一条。
## 业务任务可使用 callable；窗口任务使用事件交接，保留同步取消与缓存刷新语义。
class_name UIPopupQueue
extends RefCounted

signal drained # 当前没有正在执行且找不到可执行条目；条件不满足的条目仍可能留在队列中。

var _queue: Array[UIPopupEntry] = [] # 待弹队列，按优先级从高到低
var _shown_this_session: Array[String] = [] # 此队列实例已展示过的 ui_name；clear 不清此记录，配合 once_per_session 去重。
var _is_showing: bool = false # 当前有窗口或 callable 占位；未结束前不能并行执行下一条。
var _current_ui_name: String = "" # 当前正在弹的 ui_name，用来过滤掉别的窗口的隐藏事件
var _current: Dictionary = {} # 当前请求身份字典，同时持有窗口信号回调；完成时必须解除 Callable 对字典的自引用。
var _draining: bool = false # 同步关闭/取消由当前循环推进，不递归弹出下一条。


# ================= 入队 =================
## 按优先级插入：遇到第一个优先级更低的就插到它前面，否则排到队尾
func enqueue(entry: UIPopupEntry) -> void:
	var idx: int = _queue.size()
	for i in _queue.size():
		if entry.priority > _queue[i].priority:
			idx = i
			break
	_queue.insert(idx, entry)


## 批量入队，逐条按优先级插入
func enqueue_all(entries: Array[UIPopupEntry]) -> void:
	for entry in entries:
		enqueue(entry)


## 插队到最前面（下一次 flush 优先弹它）
func insert_next(entry: UIPopupEntry) -> void:
	_queue.insert(0, entry)


## 剔除 ui_name 或业务 key 匹配的待办；不影响当前正在展示/await 的任务。
func cancel(ui_name: String) -> void:
	_queue = _queue.filter(func(e: UIPopupEntry) -> bool: return e.ui_name != ui_name and e.key != ui_name)


## 只清空待办，不关闭当前窗口、不取消正在 await 的 callable，也不重置本会话展示记录。
## 所属页面离开时须另行使业务等待退出，否则当前任务仍会占着队列。
func clear() -> void:
	_queue.clear()


# ================= 弹出调度 =================
## 请求推进队列；正在弹就直接返回（互斥），否则尝试弹下一条
func flush() -> void:
	if _is_showing or _draining:
		return
	_draining = true
	while not _is_showing:
		var entry: UIPopupEntry = _take_next()
		if entry == null:
			break
		_show_entry(entry)
	_draining = false
	if not _is_showing:
		drained.emit()


## 从队首扫到队尾，跳过「本会话已弹过」和「条件不满足」的，弹出第一条合格的并把它移出队列
func _take_next() -> UIPopupEntry:
	for entry: UIPopupEntry in _queue.duplicate():
		if entry.once_per_session and entry.ui_name in _shown_this_session: # once_per_session 且已弹过：本轮跳过（仍留在队列里）
			continue
		if entry.condition.is_valid() and not entry.condition.call(): # 条件函数返回 false：本轮跳过（仍留在队列里）
			continue
		# 条件回调也允许取消队列；按条目归属删除，避免索引已经改变。
		if not _queue.has(entry):
			continue
		_queue.erase(entry)
		return entry
	return null


## 先监听再显示；取消显示可能没有 hidden，返回后还要核对实际生命周期。
func _show_entry(entry: UIPopupEntry) -> void:
	if entry.callable.is_valid():
		_show_callable(entry.callable)
		return
	_is_showing = true
	_current_ui_name = entry.ui_name
	var request := {"name": entry.ui_name, "once": entry.once_per_session}
	request["shown"] = _on_window_shown.bind(request)
	request["hidden"] = _on_window_hidden.bind(request)
	request["cancelled"] = _on_window_show_cancelled.bind(request)
	_current = request
	UIManager.events.window_shown.connect(request.shown)
	UIManager.events.window_hidden.connect(request.hidden)
	UIManager.events.window_show_cancelled.connect(request.cancelled)
	var win := UIManager.show_ui(entry.ui_name, entry.params)
	if not is_same(_current, request):
		return
	if not is_instance_valid(win) or win.is_queued_for_deletion() \
		or (not win.is_showing() and win.get_window_state() != UIBaseWindow.WindowState.CLOSING):
		_finish_current(request)
	elif win.is_showing():
		_remember_shown(request) # 已显示缓存窗口的刷新不会再次发布 shown。


## 只接受当前请求对应的窗口展示通知，登记 once_per_session 身份；旧请求监听不能更新新任务。
func _on_window_shown(ui_name: String, _win: Variant, request: Dictionary) -> void:
	if is_same(_current, request) and ui_name == request.name:
		_remember_shown(request)


## 相同请求的窗口隐藏后先记已展示、解除当前连接，再继续队列；同步重入隐藏也走此路径。
func _on_window_hidden(ui_name: String, win: Variant, request: Dictionary) -> void:
	if not is_same(_current, request) or ui_name != request.name:
		return
	# shown 的其它监听者可能先同步关闭；hidden 同样证明这一条确实显示过。
	_remember_shown(request)
	_finish_current(request)
	_advance_after_close(win)


## 为启用 once_per_session 的窗口按注册名记录一次，缓存刷新也能补登记。
func _remember_shown(request: Dictionary) -> void:
	if request.once and request.name not in _shown_this_session:
		_shown_this_session.append(request.name)


## 首次展示被取消时结束对应请求并推进；取消不记为已展示，之后仍可再次安排。
func _on_window_show_cancelled(ui_name: String, win: Variant, request: Dictionary) -> void:
	if not is_same(_current, request) or ui_name != request.name:
		return
	_finish_current(request)
	_advance_after_close(win)


## 正常关闭可同步推进；销毁通知期间延后到安全时点，避免在 tree_exiting 中修改受锁的子节点列表。
func _advance_after_close(win: Variant) -> void:
	# 外部销毁的完成通知来自 tree_exiting，此时父节点仍锁定着子节点列表。
	if not is_instance_valid(win) or win.get_window_state() == UIBaseWindow.WindowState.DESTROYED:
		flush.call_deferred()
	else:
		flush()


## 断开本请求三类监听并拆掉回调绑定的字典引用；只有身份仍匹配才释放当前任务占位。
func _finish_current(request: Dictionary) -> void:
	for pair: Array in [[UIManager.events.window_shown, request.shown], [UIManager.events.window_hidden, request.hidden], [UIManager.events.window_show_cancelled, request.cancelled]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
	# Callable 绑定了 request；完成后断开自引用，不能只丢掉 _current。
	request.erase("shown")
	request.erase("hidden")
	request.erase("cancelled")
	if not is_same(_current, request):
		return
	_current = {}
	_is_showing = false
	_current_ui_name = ""


## 等待业务函数完整返回，再释放占位并推进；函数须自行管理页面归属、取消与资源清理。
## 队列不会替任意 callable 中止外部信号等待；clear 也只移除尚未开始的条目。
func _show_callable(task: Callable) -> void:
	_is_showing = true
	var request := {"callable": true}
	_current = request
	await task.call()
	if not is_same(_current, request):
		return
	_current = {}
	_is_showing = false
	if not _draining:
		flush()

## 当前任务占位或同步推进循环任一存在即返回 true，与待办队列是否为空无关。
func is_running() -> bool:
	return _is_showing or _draining

## 只查询待办数组；true 不意味着当前窗口/业务任务已经结束。
func is_empty() -> bool:
	return _queue.is_empty()

## 返回待办业务键的独立数组，不包括当前任务，也不按条件过滤。
func pending_keys() -> Array[String]:
	var result: Array[String] = []
	for entry: UIPopupEntry in _queue:
		result.append(entry.key)
	return result
