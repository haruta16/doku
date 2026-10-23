## 保存进度入口行；把点击转为上层可订阅的信号，避免行组件依赖具体账号页面。

extends Control

signal row_pressed


func _on_row_pressed() -> void:
	row_pressed.emit()
