# 提示引擎：不查答案、真的在解题；R1 唯一候选 → R2 占位排除 → R3/R4 集合锁定 → R4/R5 反证法，逐级兜底
# 全部是 static 纯函数：输入 board/size/regions，输出统一的 hint 字典，found=false 表示这层推不出来
class_name HintEngine
extends RefCounted


# ================= R1：唯一候选直接落子 =================
# 找「某行 / 某列 / 某色只剩一个能放猫的格子」直接给答案
# 返回 {found, cell:Vector2i, unit_type:"full_line"/"row"/"col"/"region", unit_index, unit_cells:Array[Vector2i]}
static func find_r1_hint(board: Array, size: int, regions: Array) -> Dictionary:
	var row_piece: Array[bool] = [] # 已经放了猫的行 / 列 / 色，用来判断哪个单元还缺猫
	row_piece.resize(size)
	row_piece.fill(false)
	var col_piece: Array[bool] = []
	col_piece.resize(size)
	col_piece.fill(false)
	var reg_piece: Array[bool] = []
	reg_piece.resize(size)
	reg_piece.fill(false)

	for r in range(size): # 一次扫描把三类占位信息都填好
		for c in range(size):
			if board[r][c] == CellState.CAT:
				row_piece[r] = true
				col_piece[c] = true
				reg_piece[regions[r][c]] = true

	for r in range(size): # 特例：整行同色且该色还没猫 —— 这只猫必然落在这一行
		if row_piece[r]:
			continue
		var row_reg: int = regions[r][0] # 该行是否整行属于同一个色
		var row_uniform: bool = true
		for c in range(1, size):
			if regions[r][c] != row_reg:
				row_uniform = false
				break
		if not row_uniform or reg_piece[row_reg]:
			continue
		for c in range(size): # 行内逐格试放
			if not _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece):
				continue
			var col_uniform: bool = true # 该格所在列也整列同色时，位置唯一确定
			for rr in range(size):
				if regions[rr][c] != row_reg:
					col_uniform = false
					break
			if col_uniform:
				var unit: Array[Vector2i] = [] # unit_cells 返回该色的全部格子，给 UI 高亮整块区域
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

	for r in range(size): # 常规情形一：某行还没猫，候选格却只剩一个
		if row_piece[r]:
			continue
		var cands: Array[Vector2i] = [] # 收集该行所有还能放猫的格子
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

	for c in range(size): # 常规情形二：某列只剩一个候选
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

	for reg in range(size): # 常规情形三：某色只剩一个候选（顺手收集该色格子）
		if reg_piece[reg]:
			continue
		var cands: Array[Vector2i] = [] # 该色所有候选
		var unit: Array[Vector2i] = [] # 该色全部格子
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

	return {"found": false} # 三种情形都没有，这层推不出来


# R1 的配套动作：拿盘上第一只已确定的猫，列出它禁掉的空格，提示玩家「这些都能画叉」
# 返回 {found, strategy:"R1_mark", cell(第一个待画叉格), cat_cell(那只猫), unit_cells(全部待画叉格)}；参数 _regions 未使用
static func find_mark_hint(board: Array, size: int, _regions: Array) -> Dictionary:
	for r in range(size): # 找到第一只猫就返回，一次只教一步
		for c in range(size):
			if board[r][c] != CellState.CAT:
				continue

			var to_mark: Array[Vector2i] = []

			for cc in range(size): # 同行空格
				if cc != c and board[r][cc] == CellState.EMPTY:
					to_mark.append(Vector2i(r, cc))

			for rr in range(size): # 同列空格
				if rr != r and board[rr][c] == CellState.EMPTY:
					to_mark.append(Vector2i(rr, c))

			for dr in range(-1, 2): # 八邻接空格（用 has 去重，避免与行列重叠的格子重复出现）
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
			if to_mark.size() > 0: # 有可画叉的格子才算找到
				return {
					"found": true,
					"strategy": "R1_mark",
					"cell": to_mark[0],
					"cat_cell": Vector2i(r, c),
					"unit_cells": to_mark,
				}
	return {"found": false}


# ================= 公共判定与小工具 =================
# 判断 (r,c) 现在能不能落猫：必须空格，且本行/本列/本区域无猫、八邻接无猫
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
	if board[r][c] != CellState.EMPTY: # 已有标记（猫/叉/草稿）的格子不能放
		return false
	if row_piece[r] or col_piece[c] or reg_piece[regions[r][c]]: # 行、列、同色区域任一处已有猫即冲突
		return false
	for dr in range(-1, 2): # 八邻接有猫也不行
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var nr := r + dr
			var nc := c + dc
			if nr >= 0 and nr < size and nc >= 0 and nc < size:
				if board[nr][nc] == CellState.CAT:
					return false
	return true


# 生成整行的格子列表，供 hint 的 unit_cells 用
static func _row_cells(r: int, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in range(size):
		cells.append(Vector2i(r, c))
	return cells


# 生成整列的格子列表
static func _col_cells(c: int, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for r in range(size):
		cells.append(Vector2i(r, c))
	return cells


# ================= R3/R4：k 个色只占 k 行（列） =================
# 若 k 个未放色的候选行去重后正好 k 条，这 k 条行就被这 k 只猫占满，行内不属于这 k 个色的格子都能排除
# k<=3 命名 R3、k>=4 命名 R4（判定完全相同）；返回 {found, strategy, description, regions, highlight_cells, locked_rows, locked_cols}
static func find_r3_r4_hint(board: Array, size: int, regions: Array) -> Dictionary:
	var row_piece: Array[bool] = [] # 同 R1：先统计哪些行 / 列 / 色已经有猫
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

	var unplaced: Array[int] = [] # 对每个还没放猫的色，算出它的候选格分布在哪些行 / 哪些列
	var reg_rows: Dictionary = {}
	var reg_cols: Dictionary = {}
	for reg in range(size):
		if reg_piece[reg]:
			continue
		unplaced.append(reg)
		var rows: Dictionary = {} # 该色的候选行集合
		var cols: Dictionary = {} # 该色的候选列集合
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

	var max_k: int = mini(unplaced.size() - 1, 6) # k 从 2 枚举起（k=1 属于 R1）；上限 6 是为了压住组合数
	for k in range(2, max_k + 1):
		var subsets: Array = _gen_subsets(unplaced, k) # 枚举所有 k 个色的组合
		for subset in subsets:
			var reg_set: Dictionary = {}
			for reg in subset:
				reg_set[reg] = true

			var all_rows: Dictionary = {} # 行方向：每个色的候选行都不超过 k 条，且并起来正好 k 条
			var valid_r := true
			for reg in subset:
				var rws: Dictionary = reg_rows[reg]
				if rws.size() > k:
					valid_r = false
					break
				for row in rws:
					all_rows[row] = true
			if valid_r and all_rows.size() == k: # 这 k 条行里得真有不属于这 k 个色的空格，提示才有意义
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
					var hl_cells: Array[Vector2i] = [] # highlight_cells：这 k 个色的全部候选格，给 UI 高亮
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
					var strat := "R3" if k <= 3 else "R4" # 同一套判定，只按 k 的大小改难度命名
					return {
						"found": true,
						"strategy": strat,
						"description": TranslationServer.translate("HINT_R3_ROW") % [k, k, k],
						"regions": subset,
						"highlight_cells": hl_cells,
						"locked_rows": all_rows.keys(),
						"locked_cols": []
					}

			var all_cols: Dictionary = {} # 列方向：与上面完全对称的判定
			var valid_c := true
			for reg in subset:
				var cls: Dictionary = reg_cols[reg]
				if cls.size() > k:
					valid_c = false
					break
				for col in cls:
					all_cols[col] = true
			if valid_c and all_cols.size() == k: # 同样要求有可排除的新格子
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
					var hl_cells: Array[Vector2i] = [] # 列方向的 highlight_cells
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
					var strat := "R3" if k <= 3 else "R4" # 列方向的难度命名
					return {
						"found": true,
						"strategy": strat,
						"description": TranslationServer.translate("HINT_R3_COL") % [k, k, k],
						"regions": subset,
						"highlight_cells": hl_cells,
						"locked_rows": [],
						"locked_cols": all_cols.keys()
					}

	return {"found": false} # k 到上限都没找到


# ================= 组合枚举 =================
# 返回 arr 里所有大小为 k 的组合（数组的数组）
static func _gen_subsets(arr: Array[int], k: int) -> Array:
	var result: Array = []
	_gen_sub_helper(arr, k, 0, [], result)
	return result


# 回溯递归：cur 是当前组合，凑满 k 个就复制一份存进 result
static func _gen_sub_helper(arr: Array[int], k: int, start: int, cur: Array, result: Array) -> void:
	if cur.size() == k:
		result.append(cur.duplicate())
		return
	for i in range(start, arr.size()):
		cur.append(arr[i])
		_gen_sub_helper(arr, k, i + 1, cur, result)
		cur.pop_back()


# ================= R2：占位排除（不落子，只画叉） =================
# r2a：某色的候选全挤在一行/列 → 该行/列其他色可排除；r2b：某行/列的候选全是同一个色 → 该色在其他行/列可排除
# 返回 {found, strategy:"R2", mode:"r2a_row"/"r2a_col"/"r2b_row"/"r2b_col", description, region, row, col, highlight_cells}
# description 直接拼中文串（R3 那层用的是翻译键）；row / col 里用不上的那个填 -1
static func find_r2_hint(board: Array, size: int, regions: Array) -> Dictionary:
	var row_piece: Array[bool] = [] # 同前：先统计已有猫的行 / 列 / 色
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

	var reg_cands: Array = [] # 预计算每个未放色的候选格，下标即色号（已放色的位置留空数组）
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

	for reg in range(size): # r2a 行版本：某色的候选所在行去重后只有一行
		if reg_piece[reg]:
			continue
		var cands: Array = reg_cands[reg]
		if cands.size() <= 1: # 只剩一个候选属于 R1 的活，这层跳过
			continue
		var rows: Dictionary = {}
		for cell in cands:
			rows[(cell as Vector2i).x] = true
		if rows.size() == 1: # 确认都挤在同一行
			var row: int = (cands[0] as Vector2i).x
			var has_new := false # 该行还得真有别的颜色的空格可排除
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

	for reg in range(size): # r2a 列版本
		if reg_piece[reg]:
			continue
		var cands: Array = reg_cands[reg]
		if cands.size() <= 1:
			continue
		var cols: Dictionary = {}
		for cell in cands:
			cols[(cell as Vector2i).y] = true
		if cols.size() == 1: # 候选都挤在同一列
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

	for r in range(size): # r2b 行版本：某行剩下的候选全是同一个色
		if row_piece[r]:
			continue
		var row_cands: Array = []
		for c in range(size):
			if (
				board[r][c] == CellState.EMPTY
				and _can_place(r, c, board, size, regions, row_piece, col_piece, reg_piece)
			):
				row_cands.append(Vector2i(r, c))
		if row_cands.size() <= 1: # 只有一个候选属于 R1，跳过
			continue
		var row_regs: Dictionary = {}
		for cell in row_cands:
			row_regs[regions[(cell as Vector2i).x][(cell as Vector2i).y]] = true
		if row_regs.size() == 1: # 确认该行候选同色
			var reg: int = row_regs.keys()[0]
			var has_new := false # 该色在别的行还有候选时才值得排除
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

	for c in range(size): # r2b 列版本
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
		if col_regs.size() == 1: # 确认该列候选同色
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

	return {"found": false} # 四种模式都没命中


# ================= R4/R5：反证法（假设落子 → 推到矛盾） =================
# 假设某格放猫，再用唯一候选法往下推；若推出某行/列/色无解，就说明这格不能放猫
# 取「推到矛盾所需额外步数最少」的格子：步数<=2 记 R4_chain，更多记 R5_chain
# 返回 {found, strategy, description, cell, unit_cells:[cell], chain:{depth, steps, contra_type, contra_index}}
static func find_chain_hint(board: Array, size: int, regions: Array) -> Dictionary:
	var base: Dictionary = _chain_build_state(board, size, regions) # 由当前盘面推出初始候选状态
	var best_depth: int = 999999 # 逐个候选格试反证，挑步数最少的
	var best_r: int = -1
	var best_c: int = -1

	for r in range(size): # 这行已经放了猫就跳过
		if (base["placed"] as Array)[r] != -1:
			continue
		for c in range(size):
			if not (base["cands"] as Array)[r][c]: # 这格已经不可能放猫
				continue
			var depth: int = _chain_try_contradiction(r, c, size, regions, base) # -1 表示假设它反而推不出矛盾
			if depth >= 0 and depth < best_depth:
				best_depth = depth
				best_r = r
				best_c = c

	if best_r >= 0: # 找到可用的反证格；depth 0 表示放下去立刻矛盾
		var strategy: String = "R4_chain" if best_depth <= 2 else "R5_chain" # 短路越浅越容易被玩家看懂，浅的归 R4、深的归 R5
		var chain_cells: Array[Vector2i] = [Vector2i(best_r, best_c)] # unit_cells 只放这一格，UI 靠它聚焦

		# 再算一遍细节（推理链每一步）给提示面板展示
		var chain_detail: Dictionary = _chain_try_contradiction_detail(
			best_r, best_c, size, regions, base
		)
		# depth 0 用「直接矛盾」文案，否则报出推了几步
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
	return {"found": false} # 没有任何一格能反证出来


# 与 _chain_try_contradiction 相同的推演，但返回细节：矛盾类型/位置 + 中途被迫落子的序列
# 返回 {depth, steps:Array[Vector2i], contra_type:"row"/"col"/"region", contra_index}；推不到矛盾时返回 {}
static func _chain_try_contradiction_detail(
	r0: int, c0: int, size: int, regions: Array, base: Dictionary
) -> Dictionary:
	var cands: Array = [] # 深拷一份候选表，避免污染 base
	for row_arr in base["cands"] as Array:
		cands.append((row_arr as Array).duplicate())
	var state: Dictionary = { # 工作状态：候选表 + 每行已放猫的列号 + 已占用的列/色
		"cands": cands,
		"placed": (base["placed"] as Array).duplicate(),
		"col_placed": (base["col_placed"] as Array).duplicate(),
		"reg_placed": (base["reg_placed"] as Array).duplicate(),
	}
	_chain_place(r0, c0, size, regions, state) # 先假设 (r0,c0) 放猫，再开始推

	var steps: Array[Vector2i] = [] # steps 记录被迫落子的格子，extra 记录额外推了几步
	var extra: int = 0
	var progress: bool = true
	while progress: # 一轮轮推，直到某轮完全没有新进展
		progress = false
		var cands_s: Array = state["cands"]
		var placed_s: Array = state["placed"]
		var col_s: Array = state["col_placed"]
		var reg_s: Array = state["reg_placed"]

		for r in range(size): # 先找矛盾：某行候选被推成 0 个，按行→列→色顺序报第一个
			if placed_s[r] != -1:
				continue
			var cnt: int = 0
			for c in range(size):
				if cands_s[r][c]:
					cnt += 1
			if cnt == 0:
				return {"depth": extra, "steps": steps, "contra_type": "row", "contra_index": r}
		for c in range(size): # 再查列
			if col_s[c]:
				continue
			var cnt: int = 0
			for r in range(size):
				if cands_s[r][c]:
					cnt += 1
			if cnt == 0:
				return {"depth": extra, "steps": steps, "contra_type": "col", "contra_index": c}
		for reg in range(size): # 再查色
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

		for r in range(size): # 没有矛盾就继续用唯一候选落子；每轮只落一个再重扫，避免漏判
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
		if progress: # 这一轮落了子，重头再来
			continue
		for c in range(size): # 列方向的唯一候选
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
		if progress: # 同上，落子后重来
			continue
		for reg in range(size): # 色方向的唯一候选
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

	return {} # 推到底也没有矛盾，说明这个假设成立（返回空字典）


# 从盘面构造推演初始状态：候选全开，再按已有的猫逐只排除，最后把玩家打的叉直接判死
# 返回 {cands:Array[Array[bool]], placed:Array[int], col_placed:Array[bool], reg_placed:Array[bool]}
static func _chain_build_state(board: Array, size: int, regions: Array) -> Dictionary:
	var cands: Array = [] # cands[r][c] 表示这一格还可能是猫
	for _r in range(size):
		var row: Array = []
		row.resize(size)
		row.fill(true)
		cands.append(row)
	var placed: Array = [] # placed[r] = 该行猫所在的列号，-1 表示这行还没猫
	placed.resize(size)
	placed.fill(-1)
	var col_placed: Array = [] # 已被占用的列
	col_placed.resize(size)
	col_placed.fill(false)
	var reg_placed: Array = [] # 已被占用的色
	reg_placed.resize(size)
	reg_placed.fill(false)
	var state: Dictionary = {
		"cands": cands, "placed": placed, "col_placed": col_placed, "reg_placed": reg_placed
	}
	for r in range(size): # 盘上的猫逐只落进状态（会连带清掉它排除的候选）
		for c in range(size):
			if board[r][c] == CellState.CAT:
				_chain_place(r, c, size, regions, state)
	for r in range(size): # 玩家手打的叉直接判死
		for c in range(size):
			if board[r][c] == CellState.MARK:
				(state["cands"] as Array)[r][c] = false
	return state


# 在推演状态里落一只猫：标记行/列/色已占用，并清掉同行、同列、八邻接、同色的候选
static func _chain_place(r: int, c: int, size: int, regions: Array, state: Dictionary) -> void:
	var cands: Array = state["cands"]
	var placed: Array = state["placed"]
	var col_placed: Array = state["col_placed"]
	var reg_placed: Array = state["reg_placed"]
	placed[r] = c
	col_placed[c] = true
	reg_placed[regions[r][c]] = true
	for cc in range(size): # 同行其他格
		if cc != c:
			cands[r][cc] = false
	for rr in range(size): # 同列其他格
		if rr != r:
			cands[rr][c] = false
	for dr in range(-1, 2): # 八邻接
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var nr: int = r + dr
			var nc: int = c + dc
			if nr >= 0 and nr < size and nc >= 0 and nc < size:
				cands[nr][nc] = false
	var rid: int = regions[r][c] # 同色区域
	for rr in range(size):
		for cc in range(size):
			if regions[rr][cc] == rid and not (rr == r and cc == c):
				cands[rr][cc] = false


# 反证核心：假设 (r0,c0) 放猫后反复用唯一候选推进，返回推到矛盾所需的额外步数；推不出矛盾返回 -1
static func _chain_try_contradiction(
	r0: int, c0: int, size: int, regions: Array, base: Dictionary
) -> int:
	var cands: Array = [] # 拷一份工作状态，不影响 base
	for row_arr in base["cands"] as Array:
		cands.append((row_arr as Array).duplicate())
	var state: Dictionary = {
		"cands": cands,
		"placed": (base["placed"] as Array).duplicate(),
		"col_placed": (base["col_placed"] as Array).duplicate(),
		"reg_placed": (base["reg_placed"] as Array).duplicate(),
	}
	_chain_place(r0, c0, size, regions, state)

	var extra: int = 0 # 额外推演步数（不含假设的这一步）
	var progress: bool = true
	while progress: # 循环直到没有新进展
		progress = false
		var cands_s: Array = state["cands"]
		var placed_s: Array = state["placed"]
		var col_s: Array = state["col_placed"]
		var reg_s: Array = state["reg_placed"]

		for r in range(size): # 行/列/色任一处候选清零就是矛盾
			if placed_s[r] != -1:
				continue
			var cnt: int = 0
			for c in range(size):
				if cands_s[r][c]:
					cnt += 1
			if cnt == 0:
				return extra
		for c in range(size): # 再查列
			if col_s[c]:
				continue
			var cnt: int = 0
			for r in range(size):
				if cands_s[r][c]:
					cnt += 1
			if cnt == 0:
				return extra
		for reg in range(size): # 再查色
			if reg_s[reg]:
				continue
			var cnt: int = 0
			for r in range(size):
				for c in range(size):
					if regions[r][c] == reg and cands_s[r][c]:
						cnt += 1
			if cnt == 0:
				return extra

		for r in range(size): # 唯一候选就落子，落完立刻 break 出去重扫
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
		for c in range(size): # 列方向的唯一候选
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
		for reg in range(size): # 色方向的唯一候选
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

	return -1 # 一路推完都没矛盾


# ================= 自动解题循环 / 难度标注 =================
# 拿棋盘反复套用「画叉 + R1 + R2 + R3」把能白送的格子推完，推不动的那些答案格就是 R4 及以上难度
# 参数 solution 是二维 bool 棋盘；返回 {Vector2i: true}，只含答案里是猫、但简单策略推不出来的位置
static func compute_r4_plus_cells(
	board: Array, size: int, regions: Array, solution: Array
) -> Dictionary:
	var work_board: Array = [] # 拷贝棋盘，避免污染调用方的 board
	for r in range(size):
		var row: Array = []
		row.resize(size)
		for c in range(size):
			row[c] = board[r][c]
		work_board.append(row)

	while true: # 一直推进到四种简单手段都推不动为止
		var mark_h: Dictionary = find_mark_hint(work_board, size, regions) # 1) 给已确定的猫补叉
		if mark_h.get("found", false):
			for cell_v in mark_h.get("unit_cells", []) as Array:
				var cell: Vector2i = cell_v
				if work_board[cell.x][cell.y] == CellState.EMPTY:
					work_board[cell.x][cell.y] = CellState.MARK
			continue

		var r1_h: Dictionary = find_r1_hint(work_board, size, regions) # 2) 唯一候选直接落猫
		if r1_h.get("found", false):
			var c1: Vector2i = r1_h["cell"]
			work_board[c1.x][c1.y] = CellState.CAT
			continue

		var r2_h: Dictionary = find_r2_hint(work_board, size, regions) # 3) R2 的占位排除
		if r2_h.get("found", false):
			_apply_r2_marks(work_board, r2_h, size, regions)
			continue

		var r3_h: Dictionary = find_r3_r4_hint(work_board, size, regions) # 4) 只吃 R3，R4 正是要统计的对象
		if r3_h.get("found", false) and r3_h.get("strategy", "") == "R3":
			_apply_r3_marks(work_board, r3_h, size, regions)
			continue
		break

	var r4_plus: Dictionary = {} # 剩下的：答案里是猫、但简单策略推不出来的格子
	for r in range(size): # solution 每行是 bool 数组，true 表示答案是猫
		var sol_row: Array = solution[r]
		for c in range(size):
			if bool(sol_row[c]) and work_board[r][c] != CellState.CAT: # key 是 Vector2i，value 固定为 true
				r4_plus[Vector2i(r, c)] = true
	return r4_plus


# 把 R2 提示里该排除的格子按 mode 批量标成叉，供 compute_r4_plus_cells 内部推演用
static func _apply_r2_marks(work_board: Array, hint: Dictionary, size: int, regions: Array) -> void:
	var mode: String = hint.get("mode", "") # r2a 排除该行/列的其他色，r2b 排除该色在其他行/列的格子
	var reg: int = int(hint.get("region", -1))
	var row: int = int(hint.get("row", -1))
	var col: int = int(hint.get("col", -1))
	match mode: # 四种模式分别落叉
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


# 把 R3 锁定的行/列上、不属于这 k 个色的空格标成叉
static func _apply_r3_marks(work_board: Array, hint: Dictionary, size: int, regions: Array) -> void:
	var reg_set: Dictionary = {} # 参与锁定的色集合
	for reg in hint.get("regions", []) as Array:
		reg_set[int(reg)] = true
	for row_v in hint.get("locked_rows", []) as Array: # 锁定的行：行内非这些色的空格全部画叉
		var row: int = int(row_v)
		for c in range(size):
			if reg_set.has(int(regions[row][c])):
				continue
			if work_board[row][c] == CellState.EMPTY:
				work_board[row][c] = CellState.MARK
	for col_v in hint.get("locked_cols", []) as Array: # 锁定的列：同上
		var col: int = int(col_v)
		for r in range(size):
			if reg_set.has(int(regions[r][col])):
				continue
			if work_board[r][col] == CellState.EMPTY:
				work_board[r][col] = CellState.MARK
