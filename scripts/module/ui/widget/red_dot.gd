# 红点：按 dot_id 查 RedDotCenter 的计数，>0 就显示；计数变化时实时刷新
extends Node2D

@export var dot_id: String = "" # 红点编号，场景里配置，对应 RedDotCenter 的 key


# 进树：按当前计数定显隐，并订阅全局计数变化
func _ready() -> void:
	visible = RedDotCenter.get_count(dot_id) > 0
	RedDotCenter.count_changed.connect(_on_count_changed)


# 只响应自己这个 id 的计数变化
func _on_count_changed(id: String, count: int) -> void:
	if id == dot_id:
		visible = count > 0
