## 一次选题请求：携带关号、强制层级、预放猫来源和跟踪对象，跨策略阶段传递。
class_name LevelSelectRequest
extends RefCounted

var level_num: int
var rank_override: int
var ignore_special: bool = false
var delivery_attempt: int = 0
var trace: LevelSelectionTrace

var pre_cat_pend: Dictionary


## 绑定调用方请求参数与跟踪对象，保留预放猫来源字典引用。
func _init(
	p_level_num: int,
	p_trace: LevelSelectionTrace,
	p_rank_override: int = 0,
	p_pre_cat_pend: Dictionary = {}
) -> void:
	level_num = p_level_num
	rank_override = p_rank_override
	trace = p_trace
	pre_cat_pend = p_pre_cat_pend
