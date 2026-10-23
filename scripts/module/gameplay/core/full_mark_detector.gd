## 全标记与完成单元检测：由棋盘、区域和答案计算反馈候选，也提供动画使用的格子分组。
class_name FullMarkDetector
extends RefCounted

enum UnitKind { ROW, COL, REGION }

const MIN_BOARD_SIZE: int = 6

const NOT_APPLICABLE: int = -1

const _UNMARKED_TIERS: Array = [
	{"max_size": 7, "allowed": 2},
	{"max_size": 9, "allowed": 3},
	{"max_size": 12, "allowed": 4},
]

const _UNMARKED_FALLBACK: int = 4


## 按棋盘尺寸给出全标记允许剩余的未标格数，小于六阶返回不适用。
static func max_unmarked_allowed(size: int) -> int:
	if size < MIN_BOARD_SIZE:
		return NOT_APPLICABLE
	for tier: Dictionary in _UNMARKED_TIERS:
		if size <= int(tier["max_size"]):
			return int(tier["allowed"])
	return _UNMARKED_FALLBACK


## 正式猫或叉类状态算已标记，草稿状态不算。
static func _is_marked(state: int) -> bool:
	return CellState.is_cross(state) or state == CellState.CAT


## 同时检查当前位置有正式猫，并且答案矩阵认可该位置。
static func _is_correct_cat(board: Array, solution: Array, r: int, c: int) -> bool:
	return int(board[r][c]) == CellState.CAT and bool(solution[r][c])


## 收集尚未正式标记的位置，返回行列坐标数组。
static func unmarked_cells(board: Array, size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in size:
		for c in size:
			if not _is_marked(int(board[r][c])):
				out.append(Vector2i(r, c))
	return out


## 达到尺寸要求后，判断未标记格数是否落在允许阈值内。
static func is_full_mark(board: Array, size: int) -> bool:
	var allowed: int = max_unmarked_allowed(size)
	if allowed == NOT_APPLICABLE:
		return false
	return unmarked_cells(board, size).size() <= allowed


## 找出全格已标记且包含正确猫的行、列、区域，返回种类、索引和格子坐标。
static func completed_units(
	board: Array, size: int, regions: Array, solution: Array
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if size < MIN_BOARD_SIZE:
		return out
	if size <= 0 or regions.size() < size or solution.size() < size:
		return out

	for r in size:
		var row_cells: Array[Vector2i] = []
		var row_full: bool = true
		var row_has_cat: bool = false
		for c in size:
			if not _is_marked(int(board[r][c])):
				row_full = false
				break
			if _is_correct_cat(board, solution, r, c):
				row_has_cat = true
			row_cells.append(Vector2i(r, c))
		if row_full and row_has_cat:
			out.append({"kind": UnitKind.ROW, "index": r, "cells": row_cells})

	for c in size:
		var col_cells: Array[Vector2i] = []
		var col_full: bool = true
		var col_has_cat: bool = false
		for r in size:
			if not _is_marked(int(board[r][c])):
				col_full = false
				break
			if _is_correct_cat(board, solution, r, c):
				col_has_cat = true
			col_cells.append(Vector2i(r, c))
		if col_full and col_has_cat:
			out.append({"kind": UnitKind.COL, "index": c, "cells": col_cells})

	var region_cells: Dictionary = {}
	var region_unmarked: Dictionary = {}
	var region_has_cat: Dictionary = {}
	for r in size:
		for c in size:
			var rid: int = int(regions[r][c])
			if not region_cells.has(rid):
				region_cells[rid] = ([] as Array[Vector2i])
				region_unmarked[rid] = 0
				region_has_cat[rid] = false
			region_cells[rid].append(Vector2i(r, c))
			if not _is_marked(int(board[r][c])):
				region_unmarked[rid] += 1
			elif _is_correct_cat(board, solution, r, c):
				region_has_cat[rid] = true
	var region_ids: Array = region_cells.keys()
	region_ids.sort()
	for rid: int in region_ids:
		if int(region_unmarked[rid]) == 0 and bool(region_has_cat[rid]):
			out.append({"kind": UnitKind.REGION, "index": rid, "cells": region_cells[rid]})

	return out


## 统计面积最大的区域；面积相同按排序后的区域编号先到者保留。
static func dominant_region(size: int, regions: Array) -> int:
	if size <= 0 or regions.size() < size:
		return -1
	var counts: Dictionary = {}
	for r in size:
		for c in size:
			var rid: int = int(regions[r][c])
			counts[rid] = int(counts.get(rid, 0)) + 1
	var best_id: int = -1
	var best_count: int = 0
	var region_ids: Array = counts.keys()
	region_ids.sort()
	for rid: int in region_ids:
		var count: int = int(counts[rid])
		if count > best_count:
			best_count = count
			best_id = rid
	return best_id


## 按从左下到右上的对角层分组，供逐层播放格子反馈。
static func group_by_diagonal(cells: Array, size: int) -> Dictionary:
	var layers: Dictionary = {}
	for cell: Vector2i in cells:
		var layer: int = (size - 1 - cell.x) + cell.y
		if not layers.has(layer):
			layers[layer] = ([] as Array[Vector2i])
		layers[layer].append(cell)
	return layers


## 按距锚点的切比雪夫距离分圈，供由近到远的格子反馈。
static func group_by_ring(cells: Array, anchor: Vector2i) -> Dictionary:
	var rings: Dictionary = {}
	for cell: Vector2i in cells:
		var ring: int = maxi(absi(cell.x - anchor.x), absi(cell.y - anchor.y))
		if not rings.has(ring):
			rings[ring] = ([] as Array[Vector2i])
		rings[ring].append(cell)
	return rings


## 把行、列、区域枚举转成调试标识，未知值保留数值信息。
static func unit_kind_name(kind: int) -> String:
	match kind:
		UnitKind.ROW:
			return "row"
		UnitKind.COL:
			return "col"
		UnitKind.REGION:
			return "region"
	return "unknown(%d)" % kind
