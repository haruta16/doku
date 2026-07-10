class_name UIPopupQueue
extends RefCounted

var _queue: Array[UIPopupEntry] = []
var _shown_this_session: Array[String] = []
var _is_showing: bool = false
var _current_ui_name: String = ""

func enqueue(entry: UIPopupEntry) -> void :
    var idx: int = _queue.size()
    for i in _queue.size():
        if entry.priority > _queue[i].priority:
            idx = i
            break
    _queue.insert(idx, entry)

func enqueue_all(entries: Array[UIPopupEntry]) -> void :
    for entry in entries:
        enqueue(entry)

func insert_next(entry: UIPopupEntry) -> void :
    _queue.insert(0, entry)

func cancel(ui_name: String) -> void :
    _queue = _queue.filter( func(e: UIPopupEntry) -> bool: return e.ui_name != ui_name)

func clear() -> void :
    _queue.clear()

func flush() -> void :
    if _is_showing:
        return
    _try_show_next()

func _try_show_next() -> void :
    for i in _queue.size():
        var entry: UIPopupEntry = _queue[i]
        if entry.once_per_session and entry.ui_name in _shown_this_session:
            continue
        if entry.condition.is_valid() and not entry.condition.call():
            continue
        _queue.remove_at(i)
        _show_entry(entry)
        return

func _show_entry(entry: UIPopupEntry) -> void :
    _is_showing = true
    _current_ui_name = entry.ui_name
    if entry.once_per_session:
        _shown_this_session.append(entry.ui_name)
    var win: = UIManager.show_ui(entry.ui_name, entry.params)
    if win != null:
        UIManager.events.window_hidden.connect(_on_window_hidden)
    else:
        _is_showing = false
        _current_ui_name = ""

func _on_window_hidden(ui_name: String, _win: UIFrameWindow) -> void :
    if ui_name != _current_ui_name:
        return
    UIManager.events.window_hidden.disconnect(_on_window_hidden)
    _is_showing = false
    _current_ui_name = ""
    _try_show_next()
