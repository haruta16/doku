# 桌面图标快捷方式（Android）：注册「反馈」「重要」两个长按快捷入口，并接收用户点了哪个
# 原生能力来自 ShortcutPlugin 单例；launcher.gd 负责调用与分发
class_name ShortcutManager
extends RefCounted

const FEEDBACK_ACTION_ID: String = "Feedback" # 快捷方式 ID：反馈
const IMPORTANT_ACTION_ID: String = "Important" # 快捷方式 ID：重要（公告/活动）


# 取原生插件单例；没装插件就返回 null，调用方一律判空
static func _plugin() -> Object:
	if Engine.has_singleton("ShortcutPlugin"):
		return Engine.get_singleton("ShortcutPlugin")
	return null


# 注册两个快捷方式，标题由调用方翻译好传进来
static func add_shortcuts(feedback_title: String, important_title: String) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.addShortcuts(feedback_title, important_title)


# 取本次启动是被哪个快捷方式拉起的；没有则返回空串
static func get_shortcut_key() -> String:
	var p: Object = _plugin()
	if p == null:
		return ""
	return p.getShortcutKey() as String


# 消费掉启动来源，避免下次冷启动重复触发
static func clear_shortcut_key() -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.clearShortcutKey()


# 订阅「运行中又点了快捷方式」的回调；重复连接会被挡掉
static func connect_shortcut_received(callable: Callable) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	if not p.has_signal("shortcut_received"):
		return
	if p.is_connected("shortcut_received", callable):
		return
	p.connect("shortcut_received", callable)
