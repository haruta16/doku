extends Node2D

@export var dot_id: String = ""


func _ready() -> void:
	visible = RedDotCenter.get_count(dot_id) > 0
	RedDotCenter.count_changed.connect(_on_count_changed)


func _on_count_changed(id: String, count: int) -> void:
	if id == dot_id:
		visible = count > 0
