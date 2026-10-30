## 弹窗队列：按优先级排队、串行弹出——一次只弹一个，等它关掉（window_hidden）再弹下一个
## 本仓暂无调用点；flush 需要业务侧主动调用来推进队列
class_name UIPopupQueue
extends RefCounted

var _queue: Array[UIPopupEntry] = [] # 待弹队列，按优先级从高到低
var _shown_this_session: Array[String] = [] # 本次运行已弹过的 ui_name，配合 entry.once_per_session 去重
var _is_showing: bool = false # 互斥标志：正在弹时不再弹下一个，直到收到 window_hidden
var _current_ui_name: String = "" # 当前正在弹的 ui_name，用来过滤掉别的窗口的隐藏事件
var _current: Dictionary = {}
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


## 把队列里指定 ui_name 的条目全部剔除（不影响正在弹的那条）
func cancel(ui_name: String) -> void:
	_queue = _queue.filter(func(e: UIPopupEntry) -> bool: return e.ui_name != ui_name)


## 清空待弹队列（不影响正在弹的那条）
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


func _on_window_shown(ui_name: String, _win: Variant, request: Dictionary) -> void:
	if is_same(_current, request) and ui_name == request.name:
		_remember_shown(request)


func _on_window_hidden(ui_name: String, win: Variant, request: Dictionary) -> void:
	if not is_same(_current, request) or ui_name != request.name:
		return
	# shown 的其它监听者可能先同步关闭；hidden 同样证明这一条确实显示过。
	_remember_shown(request)
	_finish_current(request)
	_advance_after_close(win)


func _remember_shown(request: Dictionary) -> void:
	if request.once and request.name not in _shown_this_session:
		_shown_this_session.append(request.name)


func _on_window_show_cancelled(ui_name: String, win: Variant, request: Dictionary) -> void:
	if not is_same(_current, request) or ui_name != request.name:
		return
	_finish_current(request)
	_advance_after_close(win)


func _advance_after_close(win: Variant) -> void:
	# 外部销毁的完成通知来自 tree_exiting，此时父节点仍锁定着子节点列表。
	if not is_instance_valid(win) or win.get_window_state() == UIBaseWindow.WindowState.DESTROYED:
		flush.call_deferred()
	else:
		flush()


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
