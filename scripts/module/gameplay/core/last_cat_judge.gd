## 最后连放猫判定：检查连续落猫数，以及第一只猫落下前是否已经打出足够多的叉。
class_name LastCatJudge
extends RefCounted


## 按棋盘边长计算前置叉数阈值，非正尺寸返回零。
static func cross_threshold(board_n: int) -> int:
	if board_n <= 0:
		return 0
	return maxi(0, board_n * (board_n - 2))


## 要求有效尺寸、已记录第一只猫前的叉数，且连放猫数和叉数都达到阈值。
static func is_hit(cat_streak: int, cross_at_first_cat: int, board_n: int) -> bool:
	if board_n <= 0:
		return false
	if cross_at_first_cat < 0:
		return false
	return cat_streak >= board_n and cross_at_first_cat >= cross_threshold(board_n)
