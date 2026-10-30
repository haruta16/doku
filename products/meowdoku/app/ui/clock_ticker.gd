## 共享秒时钟：首次对齐系统秒边界；节点销毁同步撤销所有等待。
extends Node

signal second_tick

var _ticker: Timer

func _ready() -> void:
	_ticker = Timer.new()
	_ticker.one_shot = true
	_ticker.timeout.connect(_on_tick)
	add_child(_ticker)
	var now: float = Time.get_unix_time_from_system()
	_ticker.start(maxf(0.001, ceilf(now + 0.001) - now))

func _on_tick() -> void:
	second_tick.emit()
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_ticker.one_shot = false
	_ticker.start(1.0)
