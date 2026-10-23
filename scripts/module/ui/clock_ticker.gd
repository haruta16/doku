## 共享时钟节点：提供统一计时触发，避免每个界面各自建立重复计时器。
extends Node

signal second_tick


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.one_shot = false
	timer.timeout.connect(func() -> void: second_tick.emit())
	add_child(timer)

	var now: float = Time.get_unix_time_from_system()
	await get_tree().create_timer(ceilf(now + 0.001) - now).timeout
	second_tick.emit()
	timer.start()
