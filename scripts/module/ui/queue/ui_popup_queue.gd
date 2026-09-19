# 弹窗队列：按优先级排队、串行弹出——一次只弹一个，等它关掉（window_hidden）再弹下一个
# 本仓暂无调用点；flush 需要业务侧主动调用来推进队列
class_name UIPopupQueue
extends RefCounted

var _queue: Array[UIPopupEntry] = [] # 待弹队列，按优先级从高到低
var _shown_this_session: Array[String] = [] # 本次运行已弹过的 ui_name，配合 entry.once_per_session 去重
var _is_showing: bool = false # 互斥标志：正在弹时不再弹下一个，直到收到 window_hidden
var _current_ui_name: String = "" # 当前正在弹的 ui_name，用来过滤掉别的窗口的隐藏事件


# ================= 入队 =================
# 按优先级插入：遇到第一个优先级更低的就插到它前面，否则排到队尾
func enqueue(entry: UIPopupEntry) -> void:
	var idx: int = _queue.size()
	for i in _queue.size():
		if entry.priority > _queue[i].priority:
			idx = i
			break
	_queue.insert(idx, entry)


# 批量入队，逐条按优先级插入
func enqueue_all(entries: Array[UIPopupEntry]) -> void:
	for entry in entries:
		enqueue(entry)


# 插队到最前面（下一次 flush 优先弹它）
func insert_next(entry: UIPopupEntry) -> void:
	_queue.insert(0, entry)


# 把队列里指定 ui_name 的条目全部剔除（不影响正在弹的那条）
func cancel(ui_name: String) -> void:
	_queue = _queue.filter(func(e: UIPopupEntry) -> bool: return e.ui_name != ui_name)


# 清空待弹队列（不影响正在弹的那条）
func clear() -> void:
	_queue.clear()


# ================= 弹出调度 =================
# 请求推进队列；正在弹就直接返回（互斥），否则尝试弹下一条
func flush() -> void:
	if _is_showing:
		return
	_try_show_next()


# 从队首扫到队尾，跳过「本会话已弹过」和「条件不满足」的，弹出第一条合格的并把它移出队列
func _try_show_next() -> void:
	for i in _queue.size():
		var entry: UIPopupEntry = _queue[i]
		if entry.once_per_session and entry.ui_name in _shown_this_session: # once_per_session 且已弹过：本轮跳过（仍留在队列里）
			continue
		if entry.condition.is_valid() and not entry.condition.call(): # 条件函数返回 false：本轮跳过（仍留在队列里）
			continue
		_queue.remove_at(i) # 先摘出队列再弹，避免弹窗回调里重入 enqueue 造成错乱
		_show_entry(entry)
		return


# 真正弹出：先上锁、必要时记账，再交给 UIManager.show_ui；窗口没建出来就立刻解锁
func _show_entry(entry: UIPopupEntry) -> void:
	_is_showing = true
	_current_ui_name = entry.ui_name
	if entry.once_per_session: # 先记账再弹：防止弹窗回调里再次入队导致重复
		_shown_this_session.append(entry.ui_name)
	var win := UIManager.show_ui(entry.ui_name, entry.params)
	if win != null: # 订阅全局隐藏事件，等这扇窗关掉再放下一条
		UIManager.events.window_hidden.connect(_on_window_hidden)
	else:
		_is_showing = false
		_current_ui_name = ""


# 只在「关掉的正是自己等的那扇窗」时解锁，并继续弹下一条
func _on_window_hidden(ui_name: String, _win: UIFrameWindow) -> void:
	if ui_name != _current_ui_name: # 别人的窗口关掉不管
		return
	UIManager.events.window_hidden.disconnect(_on_window_hidden) # 只等一次，收到就退订
	_is_showing = false
	_current_ui_name = ""
	_try_show_next()
