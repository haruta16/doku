# 提示互斥锁：同一时刻只允许一个浮动提示/引导在跑，避免多个提示叠在一起
extends RefCounted
class_name HintMutex

# ---- 当前持有者 ----
var _active_id: String = "" # 正在展示的提示 id，空串表示没人持有


# 尝试占用；已被别的提示占用则返回 false 并打日志
func try_acquire(hint_id: String) -> bool:
	# 已被占用 → 拒绝
	if _active_id != "":
		print("[HintMutex] '%s' blocked by active '%s'" % [hint_id, _active_id])
		return false
	_active_id = hint_id
	return true


# 释放；只有持有者本人才能释放
func release(hint_id: String) -> void:
	if _active_id == hint_id:
		_active_id = ""


# 是否有提示正在展示
func is_active() -> bool:
	return _active_id != ""


# 当前持有者的 id
func get_active_id() -> String:
	return _active_id
