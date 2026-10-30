## 棋盘单元状态枚举与分类判断，格子数组保存的整数都以此表解释。
class_name CellState
extends Object

# 格子状态，取值就是存在棋盘里的那个数字
# EMPTY 空 / CAT 猫（正式落子）/ MARK 玩家手打的叉 / ERROR 冲突错标
# DRAFT_CROSS 草稿叉 / DRAFT_CAT 草稿猫 / LOCKED_MARK 锁定叉（不可再改）
enum { EMPTY, CAT, MARK, ERROR, DRAFT_CROSS, DRAFT_CAT, LOCKED_MARK }


## 是否空白：空着，或者只画了草稿
static func is_blank(s: int) -> bool:
	return s == EMPTY or s == DRAFT_CROSS or s == DRAFT_CAT


## 是否草稿：草稿只是玩家的临时推演，不算正式落子
static func is_draft(s: int) -> bool:
	return s == DRAFT_CROSS or s == DRAFT_CAT


## 是否叉类标记：含义都是「这里不能放猫」
static func is_cross(s: int) -> bool:
	return s == MARK or s == ERROR or s == LOCKED_MARK


## 将状态值转成日志标识，未知值仍保留数值便于定位异常。
static func name_of(s: int) -> String:
	match s:
		EMPTY:
			return "empty"
		CAT:
			return "cat"
		MARK:
			return "mark"
		ERROR:
			return "error"
		DRAFT_CROSS:
			return "draft_cross"
		DRAFT_CAT:
			return "draft_cat"
		LOCKED_MARK:
			return "locked_mark"
	return "unknown(%d)" % s
