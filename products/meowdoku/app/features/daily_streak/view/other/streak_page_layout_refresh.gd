## 打卡布局预览辅助：从编辑器触发父级页面重新计算布局。
@tool
extends Control

@export var layout_target: Control


func debug_recompute() -> void:
	if layout_target != null:
		layout_target.call("debug_recompute")
