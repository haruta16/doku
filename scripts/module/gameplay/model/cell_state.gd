class_name CellState
extends Object

enum { EMPTY, CAT, MARK, ERROR, DRAFT_CROSS, DRAFT_CAT, LOCKED_MARK }


static func is_draft(s: int) -> bool:
	return s == DRAFT_CROSS or s == DRAFT_CAT


static func is_blank(s: int) -> bool:
	return s == EMPTY or s == DRAFT_CROSS or s == DRAFT_CAT


static func is_cross(s: int) -> bool:
	return s == MARK or s == ERROR or s == LOCKED_MARK
