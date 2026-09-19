# 红点计数中心（autoload 单例 RedDotCenter）：按 dot_id 存计数，变了才广播
# 生产端如 HelpshiftManager，消费端如 ui/widget/red_dot.gd
extends Node

# 计数变化广播：参数是红点 id 与新计数
signal count_changed(dot_id: String, count: int)

# ---- 运行时状态 ----
var _counts: Dictionary = {} # dot_id -> 计数；没有记录的 id 视为 0


# 写入计数：id 为空忽略；与旧值相同就提前返回，不发信号
func set_count(dot_id: String, count: int) -> void:
	if dot_id == "": # 空 id 视为无效，直接忽略
		return
	var old: int = _counts.get(dot_id, 0)
	if old == count: # 值没变不广播，避免无意义的刷新
		return
	_counts[dot_id] = count
	count_changed.emit(dot_id, count) # 通知所有订阅的红点控件


# 读计数：没记录过的 dot_id 一律当 0
func get_count(dot_id: String) -> int:
	return _counts.get(dot_id, 0)
