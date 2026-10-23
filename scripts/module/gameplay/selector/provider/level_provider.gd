## 选题来源的最小接口：子类说明是否可用、如何给出题目，以及何时推进来源游标。
class_name LevelProvider
extends RefCounted


## 返回来源标识；基类仅给出占位名称。
func get_provider_id() -> StringName:
	return &"base"


## 基类默认不可用，实际来源按上下文实现可用性判断。
func is_available(_ctx: LevelSelectContext) -> bool:
	return false


## 基类默认给出空字典，表示没有候选题。
func next_entry(_ctx: LevelSelectContext) -> Dictionary:
	return {}


## 留给有游标的来源实现提交后的推进动作；基类不做任何事。
func advance(_ctx: LevelSelectContext) -> void:
	pass
