## 红点显示节点：订阅对应计数变化，并刷新入口上的可见状态。
extends Node2D

@export var dot_ids: Array[String] = []


func _ready() -> void:
	_refresh()
	RedDotCenter.count_changed.connect(_on_count_changed)


func _on_count_changed(id: String, _count: int) -> void:
	if id in dot_ids:
		_refresh()


func _refresh() -> void:
	for id in dot_ids:
		if RedDotCenter.get_count(id) > 0:
			visible = true
			return
	visible = false
