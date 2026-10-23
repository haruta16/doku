## 棋盘尺寸曲线：前十关使用固定表，第十一关起循环十个尺寸。
class_name SizeModifier
extends RefCounted

const _SIZES_1_10: Array[int] = [4, 5, 6, 6, 8, 6, 7, 8, 9, 7]
const _SIZES_11_PLUS: Array[int] = [8, 10, 10, 9, 10, 10, 9, 10, 10, 10]


## 由一基关号取得棋盘边长，非正关号返回零。
static func get_size(level_num: int) -> int:
	if level_num < 1:
		return 0
	if level_num <= 10:
		return _SIZES_1_10[level_num - 1]
	return _SIZES_11_PLUS[(level_num - 11) % 10]


## 返回棋盘尺寸修饰器标识。
func get_modifier_id() -> StringName:
	return &"size"
