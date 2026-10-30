## 测试专用：加载门由用例控制，实际生命周期仍执行 UIManager/UIBaseWindow。
extends "res://products/meowdoku/app/ui/ui_manager.gd"

class Gate extends RefCounted:
	signal released

class DelayedWindow extends UIFrameWindow:
	var close_gates: Array[Gate] = []
	var hide_gates: Array[Gate] = []
	var delay_close: bool = true
	var delay_hide: bool = false
	var hide_calls: int = 0
	var dialog_name: String = ""
	var hide_duration: float = 0.0

	func get_dlg_name() -> String:
		return dialog_name

	func get_hide_anim_duration() -> float:
		return hide_duration

	func _play_close_animation() -> void:
		if delay_close:
			var gate := Gate.new()
			close_gates.append(gate)
			await gate.released

	func on_hide() -> void:
		hide_calls += 1
		if delay_hide:
			var gate := Gate.new()
			hide_gates.append(gate)
			await gate.released

signal load_ready
var packed_fixture: PackedScene

func _load_scene_async(ui_name: String) -> PackedScene:
	_loading[ui_name] = true
	await load_ready
	_loading.erase(ui_name)
	return packed_fixture

func new_window() -> UIFrameWindow:
	return DelayedWindow.new()
