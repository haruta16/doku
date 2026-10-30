## 新版教程内容规则：定义页面顺序、消息键、高亮颜色和提示动作。
extends RefCounted

const _PAGE_SEQUENCE: Array[int] = [1, 2, 3, 4, 5]


static func page_sequence() -> Array[int]:
	return _PAGE_SEQUENCE.duplicate()


static func top_message_key_for_page(page: int) -> StringName:
	match page:
		1:
			return &"TUTORIAL_STEP1_V2_1"
		2:
			return &"TUTORIAL_STEP2_V2_1"
		3:
			return &"TUTORIAL_STEP3_V2"
		4:
			return &"TUTORIAL_STEP4_V2_1"
		5:
			return &"TUTORIAL_STEP5_V2"
		_:
			return &""


static func bottom_message_key_for_page(page: int) -> StringName:
	match page:
		1:
			return &"TUTORIAL_STEP1_V2_2"
		2:
			return &"TUTORIAL_STEP2_V2_2"
		4:
			return &"TUTORIAL_STEP4_V2_2"
		_:
			return &""


static func color_cell_for_message_key(message_key: StringName) -> Vector2i:
	match message_key:
		&"TUTORIAL_STEP1_V2_2":
			return Vector2i(0, 2)
		&"TUTORIAL_STEP3_V2":
			return Vector2i(3, 1)
		&"TUTORIAL_STEP4_V2_2":
			return Vector2i(1, 0)
		_:
			return Vector2i(-1, -1)


static func inject_color_bbcode(template: String, color_bbcode: String) -> String:
	return template.replace("%s", color_bbcode)


static func find_next_hint(
	board: Array,
	regions: Array,
	solution: Array,
	include_region: bool = false,
	include_reverse_set_locking: bool = false,
) -> Dictionary:
	var size: int = board.size()
	var hint: Dictionary = HintEngine.find_mark_hint(board, size, regions, include_region)
	if not hint.get("found", false):
		for r: int in range(size):
			for c: int in range(size):
				if (
					bool((solution[r] as Array)[c])
					and int((board[r] as Array)[c]) == CellState.MARK
				):
					hint = {
						"found": true,
						"strategy": "",
						"cell": Vector2i(r, c),
						"unit_cells": [Vector2i(r, c)],
						"description": TranslationServer.translate("HINT_WRONG_MARK"),
						"wrong_mark": true,
					}
					break
			if hint.get("found", false):
				break
	if not hint.get("found", false):
		hint = HintEngine.find_r1_hint(board, size, regions)
	if not hint.get("found", false):
		hint = HintEngine.find_r2_hint(board, size, regions)
	if not hint.get("found", false):
		hint = HintEngine.find_r3_r4_hint(board, size, regions, include_reverse_set_locking)
	if not hint.get("found", false):
		hint = HintEngine.find_chain_hint(board, size, regions)
	return hint


static func hint_actions(hint: Dictionary, board: Array, regions: Array) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var size: int = board.size()
	var strategy: String = hint.get("strategy", "")
	if strategy == "R1_mark":
		for cell_value: Variant in hint.get("unit_cells", []):
			_append_mark_action(actions, cell_value as Vector2i, board)
	elif strategy == "R2":
		var region: int = hint.get("region", -1)
		var row: int = hint.get("row", -1)
		var col: int = hint.get("col", -1)
		match hint.get("mode", ""):
			"r2a_row":
				for c: int in range(size):
					if int((regions[row] as Array)[c]) != region:
						_append_mark_action(actions, Vector2i(row, c), board)
			"r2a_col":
				for r: int in range(size):
					if int((regions[r] as Array)[col]) != region:
						_append_mark_action(actions, Vector2i(r, col), board)
			"r2b_row":
				for r: int in range(size):
					for c: int in range(size):
						if r != row and int((regions[r] as Array)[c]) == region:
							_append_mark_action(actions, Vector2i(r, c), board)
			"r2b_col":
				for r: int in range(size):
					for c: int in range(size):
						if c != col and int((regions[r] as Array)[c]) == region:
							_append_mark_action(actions, Vector2i(r, c), board)
	elif strategy == "R3" or strategy == "R4":
		var region_set: Dictionary = {}
		for region_value: Variant in hint.get("regions", []):
			region_set[int(region_value)] = true
		for row_value: Variant in hint.get("locked_rows", []):
			var row: int = int(row_value)
			for c: int in range(size):
				if not region_set.has(int((regions[row] as Array)[c])):
					_append_mark_action(actions, Vector2i(row, c), board)
		for col_value: Variant in hint.get("locked_cols", []):
			var col: int = int(col_value)
			for r: int in range(size):
				if not region_set.has(int((regions[r] as Array)[col])):
					_append_mark_action(actions, Vector2i(r, col), board)
	elif strategy == "R3b" or strategy == "R4b":
		var reverse_region_set: Dictionary = {}
		for region_value: Variant in hint.get("regions", []):
			reverse_region_set[int(region_value)] = true
		var row_set: Dictionary = {}
		for row_value: Variant in hint.get("locked_rows", []):
			row_set[int(row_value)] = true
		var col_set: Dictionary = {}
		for col_value: Variant in hint.get("locked_cols", []):
			col_set[int(col_value)] = true
		for r: int in range(size):
			for c: int in range(size):
				if not reverse_region_set.has(int((regions[r] as Array)[c])):
					continue
				if not row_set.is_empty() and row_set.has(r):
					continue
				if not col_set.is_empty() and col_set.has(c):
					continue
				_append_mark_action(actions, Vector2i(r, c), board)
	elif strategy == "R4_chain" or strategy == "R5_chain":
		_append_mark_action(actions, hint.get("cell", Vector2i(-1, -1)), board)
	else:
		var cell: Vector2i = hint.get("cell", Vector2i(-1, -1))
		if cell.x >= 0:
			(
				actions
				. append(
					{
						"cell": cell,
						"state":
						CellState.EMPTY if hint.get("wrong_mark", false) else CellState.CAT,
					}
				)
			)
	return actions


static func _append_mark_action(
	actions: Array[Dictionary],
	cell: Vector2i,
	board: Array,
) -> void:
	if cell.x < 0 or not CellState.is_blank(int((board[cell.x] as Array)[cell.y])):
		return
	for action: Dictionary in actions:
		if action.get("cell", Vector2i(-1, -1)) == cell:
			return
	actions.append({"cell": cell, "state": CellState.MARK})
