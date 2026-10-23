## 弹窗串行队列：支持追加、插队与取消，等待当前任务完成后继续下一项。
class_name UIPopupQueue
extends RefCounted

signal drained

var _queue: Array[UIPopupEntry] = [] # 待弹队列，按优先级从高到低
var _is_running: bool = false


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


func cancel(key: String) -> void:
	_queue = _queue.filter(func(e: UIPopupEntry) -> bool: return e.key != key)


## 清空待弹队列（不影响正在弹的那条）
func clear() -> void:
	_queue.clear()


func is_running() -> bool:
	return _is_running


func pending_keys() -> Array[String]:
	var keys: Array[String] = []
	for entry: UIPopupEntry in _queue:
		keys.append(entry.key)
	return keys


func is_empty() -> bool:
	return _queue.is_empty()


func flush() -> void:
	if _is_running:
		return
	_run()


func _run() -> void:
	_is_running = true
	while not _queue.is_empty():
		var entry: UIPopupEntry = _queue.pop_front()
		if not entry.callable.is_valid():
			continue
		await entry.callable.call()
	_is_running = false
	drained.emit()
