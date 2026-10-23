## 动态事件总线：按域名注册信号，同时提供具名订阅和全事件观察入口。
extends Node

signal any_event(event_name: String, payload: Dictionary)

const _SIGNAL_ARGS: Array = [{"name": "payload", "type": TYPE_DICTIONARY}]

var _known: Dictionary = {}


## 确保具名信号存在后发送字典载荷，再通知全事件观察者。
func emit_event(event_name: String, payload: Dictionary = {}) -> void:
	if not _ensure_signal(event_name):
		return
	emit_signal(event_name, payload)
	any_event.emit(event_name, payload)


## 按事件名订阅回调；相同回调只连接一次。
func on(event_name: String, callable: Callable, flags: int = 0) -> void:
	if not _ensure_signal(event_name):
		return
	if is_connected(event_name, callable):
		return
	connect(event_name, callable, flags)


## 通过 Godot 的一次性连接标记实现调用后自动断开。
func once(event_name: String, callable: Callable) -> void:
	on(event_name, callable, CONNECT_ONE_SHOT)


## 只断开已有连接，重复取消订阅也安全。
func off(event_name: String, callable: Callable) -> void:
	if not _known.has(event_name):
		return
	if is_connected(event_name, callable):
		disconnect(event_name, callable)


func has_listener(event_name: String) -> bool:
	return _known.has(event_name) and get_signal_connection_list(event_name).size() > 0


## 动态信号必须包含域分隔点号，且不能覆盖节点已有信号。
func _ensure_signal(event_name: String) -> bool:
	if _known.has(event_name):
		return true
	if not event_name.contains("."):
		push_error("EventBus: 事件名 '%s' 缺少 '域.动作' 的点号,请走 EventName 常量" % event_name)
		return false
	if has_signal(event_name):
		push_error("EventBus: 事件名 '%s' 与已有信号重名,禁止使用" % event_name)
		return false
	add_user_signal(event_name, _SIGNAL_ARGS)
	_known[event_name] = true
	return true
