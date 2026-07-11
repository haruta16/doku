class_name HintEngine
extends RefCounted


static func find_r1_hint(board: Array, size: int, regions: Array) -> Dictionary:
	var row_piece: Array[bool] = []
	row_piece.resize(size)
	row_piece.fill(false)
	var col_piece: Array[bool] = []
	col_piece.resize(size)
	col_piece.fill(false)
	var reg_piece: Array[bool] = []
	reg_piece.resize(size)
	reg_piece.fill(false)

	for r in range(size):
		for c in range(size):
			if board[r][c] == CellState.CAT:
				row_piece[r] = true
				col_piece[c] = true
				reg_piece[regions[r][c]] = true

	for r in range(size):
		if row_piece[r]:
			continue
		var row_reg: int = regions[r][0]
		var row_uniform: bool = true
		for c in range(1, size):
			if regions[r][c] != row_reg:
				row_uniform = false
				break
		if not row_uniform or reg_piece[row_reg]:
			continue
		for c in range(size):
			if not _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece):
				continue
			var col_uniform: bool = true
			for rr in range(size):
				if regions[rr][c] != row_reg:
					col_uniform = false
					break
			if col_uniform:
				var unit: Array[Vector2i] = []
				for rr in range(size):
					for cc in range(size):
						if regions[rr][cc] == row_reg:
							unit.append(Vector2i(rr, cc))
				return {
					"found": true,
					"cell": Vector2i(r, c),
					"unit_type": "full_line",
					"unit_index": row_reg,
					"unit_cells": unit
				}

	for r in range(size):
		if row_piece[r]:
			continue
		var cands: Array[Vector2i] = []
		for c in range(size):
			if _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece):
				cands.append(Vector2i(r, c))
		if cands.size() == 1:
			return {
				"found": true,
				"cell": cands[0],
				"unit_type": "row",
				"unit_index": r,
				"unit_cells": _row_cells(r, size)
			}

	for c in range(size):
		if col_piece[c]:
			continue
		var cands: Array[Vector2i] = []
		for r in range(size):
			if _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece):
				cands.append(Vector2i(r, c))
		if cands.size() == 1:
			return {
				"found": true,
				"cell": cands[0],
				"unit_type": "col",
				"unit_index": c,
				"unit_cells": _col_cells(c, size)
			}

	for reg in range(size):
		if reg_piece[reg]:
			continue
		var cands: Array[Vector2i] = []
		var unit: Array[Vector2i] = []
		for r in range(size):
			for c in range(size):
				if regions[r][c] == reg:
					unit.append(Vector2i(r, c))
					if _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece):
						cands.append(Vector2i(r, c))
		if cands.size() == 1:
			return {
				"found": true,
				"cell": cands[0],
				"unit_type": "region",
				"unit_index": reg,
				"unit_cells": unit
			}

	return {"found": false}


static func find_mark_hint(board: Array, size: int, _regions: Array) -> Dictionary:
	for r in range(size):
		for c in range(size):
			if board[r][c] != CellState.CAT:
				continue

			var to_mark: Array[Vector2i] = []

			for cc in range(size):
				if cc != c and board[r][cc] == CellState.EMPTY:
					to_mark.append(Vector2i(r, cc))

			for rr in range(size):
				if rr != r and board[rr][c] == CellState.EMPTY:
					to_mark.append(Vector2i(rr, c))

			for dr in range(-1, 2):
				for dc in range(-1, 2):
					if dr == 0 and dc == 0:
						continue
					var nr := r + dr
					var nc := c + dc
					if nr >= 0 and nr < size and nc >= 0 and nc < size:
						if board[nr][nc] == CellState.EMPTY:
							var pos := Vector2i(nr, nc)
							if not to_mark.has(pos):
								to_mark.append(pos)
			if to_mark.size() > 0:
				return {
					"found": true,
					"strategy": "R1_mark",
					"cell": to_mark[0],
					"cat_cell": Vector2i(r, c),
					"unit_cells": to_mark,
				}
	return {"found": false}


static func _can_place(
	r: int,
	c: int,
	board: Array,
	size: int,
	regions: Array,
	row_piece: Array[bool],
	col_piece: Array[bool],
	reg_piece: Array[bool]
) -> bool:
	if board[r][c] != CellState.EMPTY:
		return false
	if row_piece[r] or col_piece[c] or reg_piece[regions[r][c]]:
		return false
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var nr := r + dr
			var nc := c + dc
			if nr >= 0 and nr < size and nc >= 0 and nc < size:
				if board[nr][nc] == CellState.CAT:
					return false
	return true


static func _row_cells(r: int, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in range(size):
		cells.append(Vector2i(r, c))
	return cells


static func _col_cells(c: int, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for r in range(size):
		cells.append(Vector2i(r, c))
	return cells


static func find_r3_r4_hint(board: Array, size: int, regions: Array) -> Dictionary:
	var row_piece: Array[bool] = []
	row_piece.resize(size)
	row_piece.fill(false)
	var col_piece: Array[bool] = []
	col_piece.resize(size)
	col_piece.fill(false)
	var reg_piece: Array[bool] = []
	reg_piece.resize(size)
	reg_piece.fill(false)
	for r in range(size):
		for c in range(size):
			if board[r][c] == CellState.CAT:
				row_piece[r] = true
				col_piece[c] = true
				reg_piece[regions[r][c]] = true

	var unplaced: Array[int] = []
	var reg_rows: Dictionary = {}
	var reg_cols: Dictionary = {}
	for reg in range(size):
		if reg_piece[reg]:
			continue
		unplaced.append(reg)
		var rows: Dictionary = {}
		var cols: Dictionary = {}
		for r in range(size):
			for c in range(size):
				if (
					regions[r][c] == reg
					and _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece)
				):
					rows[r] = true
					cols[c] = true
		reg_rows[reg] = rows
		reg_cols[reg] = cols

	var max_k: int = mini(unplaced.size() - 1, 6)
	for k in range(2, max_k + 1):
		var subsets: Array = _gen_subsets(unplaced, k)
		for subset in subsets:
			var reg_set: Dictionary = {}
			for reg in subset:
				reg_set[reg] = true

			var all_rows: Dictionary = {}
			var valid_r := true
			for reg in subset:
				var rws: Dictionary = reg_rows[reg]
				if rws.size() > k:
					valid_r = false
					break
				for row in rws:
					all_rows[row] = true
			if valid_r and all_rows.size() == k:
				var has_new := false
				for row in all_rows:
					if row_piece[row]:
						continue
					for c in range(size):
						if not reg_set.has(regions[row][c]) and board[row][c] == CellState.EMPTY:
							has_new = true
							break
					if has_new:
						break
				if has_new:
					var hl_cells: Array[Vector2i] = []
					for reg in subset:
						for r in range(size):
							for c in range(size):
								if (
									regions[r][c] == reg
									and _can_place(
										r, c, board, size, regions, row_piece, col_piece, reg_piece
									)
								):
									hl_cells.append(Vector2i(r, c))
					var strat := "R3" if k <= 3 else "R4"
					return {
						"found": true,
						"strategy": strat,
						"description": TranslationServer.translate("HINT_R3_ROW") % [k, k, k],
						"regions": subset,
						"highlight_cells": hl_cells,
						"locked_rows": all_rows.keys(),
						"locked_cols": []
					}

			var all_cols: Dictionary = {}
			var valid_c := true
			for reg in subset:
				var cls: Dictionary = reg_cols[reg]
				if cls.size() > k:
					valid_c = false
					break
				for col in cls:
					all_cols[col] = true
			if valid_c and all_cols.size() == k:
				var has_new := false
				for col in all_cols:
					if col_piece[col]:
						continue
					for r in range(size):
						if not reg_set.has(regions[r][col]) and board[r][col] == CellState.EMPTY:
							has_new = true
							break
					if has_new:
						break
				if has_new:
					var hl_cells: Array[Vector2i] = []
					for reg in subset:
						for r in range(size):
							for c in range(size):
								if (
									regions[r][c] == reg
									and _can_place(
										r, c, board, size, regions, row_piece, col_piece, reg_piece
									)
								):
									hl_cells.append(Vector2i(r, c))
					var strat := "R3" if k <= 3 else "R4"
					return {
						"found": true,
						"strategy": strat,
						"description": TranslationServer.translate("HINT_R3_COL") % [k, k, k],
						"regions": subset,
						"highlight_cells": hl_cells,
						"locked_rows": [],
						"locked_cols": all_cols.keys()
					}

	return {"found": false}


static func _gen_subsets(arr: Array[int], k: int) -> Array:
	var result: Array = []
	_gen_sub_helper(arr, k, 0, [], result)
	return result


static func _gen_sub_helper(arr: Array[int], k: int, start: int, cur: Array, result: Array) -> void:
	if cur.size() == k:
		result.append(cur.duplicate())
		return
	for i in range(start, arr.size()):
		cur.append(arr[i])
		_gen_sub_helper(arr, k, i + 1, cur, result)
		cur.pop_back()


static func find_r2_hint(board: Array, size: int, regions: Array) -> Dictionary:
	var row_piece: Array[bool] = []
	row_piece.resize(size)
	row_piece.fill(false)
	var col_piece: Array[bool] = []
	col_piece.resize(size)
	col_piece.fill(false)
	var reg_piece: Array[bool] = []
	reg_piece.resize(size)
	reg_piece.fill(false)
	for r in range(size):
		for c in range(size):
			if board[r][c] == CellState.CAT:
				row_piece[r] = true
				col_piece[c] = true
				reg_piece[regions[r][c]] = true

	var reg_cands: Array = []
	for reg in range(size):
		var cands: Array = []
		if not reg_piece[reg]:
			for r in range(size):
				for c in range(size):
					if (
						regions[r][c] == reg
						and board[r][c] == CellState.EMPTY
						and _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece)
					):
						cands.append(Vector2i(r, c))
		reg_cands.append(cands)

	for reg in range(size):
		if reg_piece[reg]:
			continue
		var cands: Array = reg_cands[reg]
		if cands.size() <= 1:
			continue
		var rows: Dictionary = {}
		for cell in cands:
			rows[(cell as Vector2i).x] = true
		if rows.size() == 1:
			var row: int = (cands[0] as Vector2i).x
			var has_new := false
			for c in range(size):
				if (
					regions[row][c] != reg
					and board[row][c] == CellState.EMPTY
					and not row_piece[row]
				):
					has_new = true
					break
			if has_new:
				return {
					"found": true,
					"strategy": "R2",
					"mode": "r2a_row",
					"description": "该色候选都在第%d行，可排除该行其他颜色的格子" % (row + 1),
					"region": reg,
					"row": row,
					"col": -1,
					"highlight_cells": cands
				}

	for reg in range(size):
		if reg_piece[reg]:
			continue
		var cands: Array = reg_cands[reg]
		if cands.size() <= 1:
			continue
		var cols: Dictionary = {}
		for cell in cands:
			cols[(cell as Vector2i).y] = true
		if cols.size() == 1:
			var col: int = (cands[0] as Vector2i).y
			var has_new := false
			for r in range(size):
				if (
					regions[r][col] != reg
					and board[r][col] == CellState.EMPTY
					and not col_piece[col]
				):
					has_new = true
					break
			if has_new:
				return {
					"found": true,
					"strategy": "R2",
					"mode": "r2a_col",
					"description": "该色候选都在第%d列，可排除该列其他颜色的格子" % (col + 1),
					"region": reg,
					"row": -1,
					"col": col,
					"highlight_cells": cands
				}

	for r in range(size):
		if row_piece[r]:
			continue
		var row_cands: Array = []
		for c in range(size):
			if (
				board[r][c] == CellState.EMPTY
				and _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece)
			):
				row_cands.append(Vector2i(r, c))
		if row_cands.size() <= 1:
			continue
		var row_regs: Dictionary = {}
		for cell in row_cands:
			row_regs[regions[(cell as Vector2i).x][(cell as Vector2i).y]] = true
		if row_regs.size() == 1:
			var reg: int = row_regs.keys()[0]
			var has_new := false
			for cell in reg_cands[reg] as Array:
				if (cell as Vector2i).x != r:
					has_new = true
					break
			if has_new:
				return {
					"found": true,
					"strategy": "R2",
					"mode": "r2b_row",
					"description": "第%d行候选均属同一颜色，可排除该颜色其他行的格子" % (r + 1),
					"region": reg,
					"row": r,
					"col": -1,
					"highlight_cells": row_cands
				}

	for c in range(size):
		if col_piece[c]:
			continue
		var col_cands: Array = []
		for r in range(size):
			if (
				board[r][c] == CellState.EMPTY
				and _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece)
			):
				col_cands.append(Vector2i(r, c))
		if col_cands.size() <= 1:
			continue
		var col_regs: Dictionary = {}
		for cell in col_cands:
			col_regs[regions[(cell as Vector2i).x][(cell as Vector2i).y]] = true
		if col_regs.size() == 1:
			var reg: int = col_regs.keys()[0]
			var has_new := false
			for cell in reg_cands[reg] as Array:
				if (cell as Vector2i).y != c:
					has_new = true
					break
			if has_new:
				return {
					"found": true,
					"strategy": "R2",
					"mode": "r2b_col",
					"description": "第%d列候选均属同一颜色，可排除该颜色其他列的格子" % (c + 1),
					"region": reg,
					"row": -1,
					"col": c,
					"highlight_cells": col_cands
				}

	return {"found": false}


static func find_chain_hint(board: Array, size: int, regions: Array) -> Dictionary:
	var base: Dictionary = _chain_build_state(board, size, regions)
	var best_depth: int = 999999
	var best_r: int = -1
	var best_c: int = -1

	for r in range(size):
		if (base["placed"] as Array)[r] != -1:
			continue
		for c in range(size):
			if not (base["cands"] as Array)[r][c]:
				continue
			var depth: int = _chain_try_contradiction(r, c, size, regions, base)
			if depth >= 0 and depth < best_depth:
				best_depth = depth
				best_r = r
				best_c = c

	if best_r >= 0:
		var strategy: String = "R4_chain" if best_depth <= 2 else "R5_chain"
		var chain_cells: Array[Vector2i] = [Vector2i(best_r, best_c)]

		var chain_detail: Dictionary = _chain_try_contradiction_detail(
			best_r, best_c, size, regions, base
		)
		var desc: String = (
			TranslationServer.translate("HINT_CHAIN_DIRECT")
			if best_depth == 0
			else TranslationServer.translate("HINT_CHAIN_STEPS") % best_depth
		)
		return {
			"found": true,
			"strategy": strategy,
			"description": desc,
			"cell": Vector2i(best_r, best_c),
			"unit_cells": chain_cells,
			"chain": chain_detail
		}
	return {"found": false}


static func _chain_try_contradiction_detail(
	r0: int, c0: int, size: int, regions: Array, base: Dictionary
) -> Dictionary:
	var cands: Array = []
	for row_arr in base["cands"] as Array:
		cands.append((row_arr as Array).duplicate())
	var state: Dictionary = {
		"cands": cands,
		"placed": (base["placed"] as Array).duplicate(),
		"col_placed": (base["col_placed"] as Array).duplicate(),
		"reg_placed": (base["reg_placed"] as Array).duplicate(),
	}
	_chain_place(r0, c0, size, regions, state)

	var steps: Array[Vector2i] = []
	var extra: int = 0
	var progress: bool = true
	while progress:
		progress = false
		var cands_s: Array = state["cands"]
		var placed_s: Array = state["placed"]
		var col_s: Array = state["col_placed"]
		var reg_s: Array = state["reg_placed"]

		for r in range(size):
			if placed_s[r] != -1:
				continue
			var cnt: int = 0
			for c in range(size):
				if cands_s[r][c]:
					cnt += 1
			if cnt == 0:
				return {"depth": extra, "steps": steps, "contra_type": "row", "contra_index": r}
		for c in range(size):
			if col_s[c]:
				continue
			var cnt: int = 0
			for r in range(size):
				if cands_s[r][c]:
					cnt += 1
			if cnt == 0:
				return {"depth": extra, "steps": steps, "contra_type": "col", "contra_index": c}
		for reg in range(size):
			if reg_s[reg]:
				continue
			var cnt: int = 0
			for r in range(size):
				for c in range(size):
					if regions[r][c] == reg and cands_s[r][c]:
						cnt += 1
			if cnt == 0:
				return {
					"depth": extra, "steps": steps, "contra_type": "region", "contra_index": reg
				}

		for r in range(size):
			if placed_s[r] != -1:
				continue
			var fc: int = -1
			var cnt: int = 0
			for c in range(size):
				if cands_s[r][c]:
					cnt += 1
					fc = c
			if cnt == 1:
				_chain_place(r, fc, size, regions, state)
				steps.append(Vector2i(r, fc))
				extra += 1
				progress = true
				break
		if progress:
			continue
		for c in range(size):
			if col_s[c]:
				continue
			var fr: int = -1
			var cnt: int = 0
			for r in range(size):
				if cands_s[r][c]:
					cnt += 1
					fr = r
			if cnt == 1:
				_chain_place(fr, c, size, regions, state)
				steps.append(Vector2i(fr, c))
				extra += 1
				progress = true
				break
		if progress:
			continue
		for reg in range(size):
			if reg_s[reg]:
				continue
			var fr2: int = -1
			var fc2: int = -1
			var cnt: int = 0
			for r in range(size):
				for c in range(size):
					if regions[r][c] == reg and cands_s[r][c]:
						cnt += 1
						fr2 = r
						fc2 = c
			if cnt == 1:
				_chain_place(fr2, fc2, size, regions, state)
				steps.append(Vector2i(fr2, fc2))
				extra += 1
				progress = true
				break

	return {}


static func _chain_build_state(board: Array, size: int, regions: Array) -> Dictionary:
	var cands: Array = []
	for _r in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(true)
		cands.append(row)
	var placed: Array = []
	placed.resize(size)
	placed.fill(-1)
	var col_placed: Array = []
	col_placed.resize(size)
	col_placed.fill(false)
	var reg_placed: Array = []
	reg_placed.resize(size)
	reg_placed.fill(false)
	var state: Dictionary = {
		"cands": cands, "placed": placed, "col_placed": col_placed, "reg_placed": reg_placed
	}
	for r in range(size):
		for c in range(size):
			if board[r][c] == CellState.CAT:
				_chain_place(r, c, size, regions, state)
	for r in range(size):
		for c in range(size):
			if board[r][c] == CellState.MARK:
				(state["cands"] as Array)[r][c] = false
	return state


static func _chain_place(r: int, c: int, size: int, regions: Array, state: Dictionary) -> void:
	var cands: Array = state["cands"]
	var placed: Array = state["placed"]
	var col_placed: Array = state["col_placed"]
	var reg_placed: Array = state["reg_placed"]
	placed[r] = c
	col_placed[c] = true
	reg_placed[regions[r][c]] = true
	for cc in range(size):
		if cc != c:
			cands[r][cc] = false
	for rr in range(size):
		if rr != r:
			cands[rr][c] = false
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var nr: int = r + dr
			var nc: int = c + dc
			if nr >= 0 and nr < size and nc >= 0 and nc < size:
				cands[nr][nc] = false
	var rid: int = regions[r][c]
	for rr in range(size):
		for cc in range(size):
			if regions[rr][cc] == rid and not (rr == r and cc == c):
				cands[rr][cc] = false


static func _chain_try_contradiction(
	r0: int, c0: int, size: int, regions: Array, base: Dictionary
) -> int:
	var cands: Array = []
	for row_arr in base["cands"] as Array:
		cands.append((row_arr as Array).duplicate())
	var state: Dictionary = {
		"cands": cands,
		"placed": (base["placed"] as Array).duplicate(),
		"col_placed": (base["col_placed"] as Array).duplicate(),
		"reg_placed": (base["reg_placed"] as Array).duplicate(),
	}
	_chain_place(r0, c0, size, regions, state)

	var extra: int = 0
	var progress: bool = true
	while progress:
		progress = false
		var cands_s: Array = state["cands"]
		var placed_s: Array = state["placed"]
		var col_s: Array = state["col_placed"]
		var reg_s: Array = state["reg_placed"]

		for r in range(size):
			if placed_s[r] != -1:
				continue
			var cnt: int = 0
			for c in range(size):
				if cands_s[r][c]:
					cnt += 1
			if cnt == 0:
				return extra
		for c in range(size):
			if col_s[c]:
				continue
			var cnt: int = 0
			for r in range(size):
				if cands_s[r][c]:
					cnt += 1
			if cnt == 0:
				return extra
		for reg in range(size):
			if reg_s[reg]:
				continue
			var cnt: int = 0
			for r in range(size):
				for c in range(size):
					if regions[r][c] == reg and cands_s[r][c]:
						cnt += 1
			if cnt == 0:
				return extra

		for r in range(size):
			if placed_s[r] != -1:
				continue
			var fc: int = -1
			var cnt: int = 0
			for c in range(size):
				if cands_s[r][c]:
					cnt += 1
					fc = c
			if cnt == 1:
				_chain_place(r, fc, size, regions, state)
				extra += 1
				progress = true
				break
		if progress:
			continue
		for c in range(size):
			if col_s[c]:
				continue
			var fr: int = -1
			var cnt: int = 0
			for r in range(size):
				if cands_s[r][c]:
					cnt += 1
					fr = r
			if cnt == 1:
				_chain_place(fr, c, size, regions, state)
				extra += 1
				progress = true
				break
		if progress:
			continue
		for reg in range(size):
			if reg_s[reg]:
				continue
			var fr2: int = -1
			var fc2: int = -1
			var cnt: int = 0
			for r in range(size):
				for c in range(size):
					if regions[r][c] == reg and cands_s[r][c]:
						cnt += 1
						fr2 = r
						fc2 = c
			if cnt == 1:
				_chain_place(fr2, fc2, size, regions, state)
				extra += 1
				progress = true
				break

	return -1


static func compute_r4_plus_cells(
	board: Array, size: int, regions: Array, solution: Array
) -> Dictionary:
	var work_board: Array = []
	for r in range(size):
		var row: Array = []
		row.resize(size)
		for c in range(size):
			row[c] = board[r][c]
		work_board.append(row)

	while true:
		var mark_h: Dictionary = find_mark_hint(work_board, size, regions)
		if mark_h.get("found", false):
			for cell_v in mark_h.get("unit_cells", []) as Array:
				var cell: Vector2i = cell_v
				if work_board[cell.x][cell.y] == CellState.EMPTY:
					work_board[cell.x][cell.y] = CellState.MARK
			continue

		var r1_h: Dictionary = find_r1_hint(work_board, size, regions)
		if r1_h.get("found", false):
			var c1: Vector2i = r1_h["cell"]
			work_board[c1.x][c1.y] = CellState.CAT
			continue

		var r2_h: Dictionary = find_r2_hint(work_board, size, regions)
		if r2_h.get("found", false):
			_apply_r2_marks(work_board, r2_h, size, regions)
			continue

		var r3_h: Dictionary = find_r3_r4_hint(work_board, size, regions)
		if r3_h.get("found", false) and r3_h.get("strategy", "") == "R3":
			_apply_r3_marks(work_board, r3_h, size, regions)
			continue
		break

	var r4_plus: Dictionary = {}
	for r in range(size):
		var sol_row: Array = solution[r]
		for c in range(size):
			if bool(sol_row[c]) and work_board[r][c] != CellState.CAT:
				r4_plus[Vector2i(r, c)] = true
	return r4_plus


static func _apply_r2_marks(work_board: Array, hint: Dictionary, size: int, regions: Array) -> void:
	var mode: String = hint.get("mode", "")
	var reg: int = int(hint.get("region", -1))
	var row: int = int(hint.get("row", -1))
	var col: int = int(hint.get("col", -1))
	match mode:
		"r2a_row":
			for c in range(size):
				if regions[row][c] != reg and work_board[row][c] == CellState.EMPTY:
					work_board[row][c] = CellState.MARK
		"r2a_col":
			for r in range(size):
				if regions[r][col] != reg and work_board[r][col] == CellState.EMPTY:
					work_board[r][col] = CellState.MARK
		"r2b_row":
			for r in range(size):
				for c in range(size):
					if regions[r][c] == reg and r != row and work_board[r][c] == CellState.EMPTY:
						work_board[r][c] = CellState.MARK
		"r2b_col":
			for r in range(size):
				for c in range(size):
					if regions[r][c] == reg and c != col and work_board[r][c] == CellState.EMPTY:
						work_board[r][c] = CellState.MARK


static func _apply_r3_marks(work_board: Array, hint: Dictionary, size: int, regions: Array) -> void:
	var reg_set: Dictionary = {}
	for reg in hint.get("regions", []) as Array:
		reg_set[int(reg)] = true
	for row_v in hint.get("locked_rows", []) as Array:
		var row: int = int(row_v)
		for c in range(size):
			if reg_set.has(int(regions[row][c])):
				continue
			if work_board[row][c] == CellState.EMPTY:
				work_board[row][c] = CellState.MARK
	for col_v in hint.get("locked_cols", []) as Array:
		var col: int = int(col_v)
		for r in range(size):
			if reg_set.has(int(regions[r][col])):
				continue
			if work_board[r][col] == CellState.EMPTY:
				work_board[r][col] = CellState.MARK
