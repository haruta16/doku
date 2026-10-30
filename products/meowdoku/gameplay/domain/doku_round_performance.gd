## 对局表现事实的纯投影：分数、连击、步数和工具次数先于动画同局提交。
## 动画只消费 events；旧未事务化手势通过 sync_runtime 同步其已完成的事实。
class_name DokuRoundPerformance
extends RefCounted

const States = preload("res://products/meowdoku/gameplay/domain/cell_state.gd")

const TIER_MAX: Dictionary = {6: [1, 2, 3, 4], 7: [1, 2, 3, 5], 8: [1, 2, 4, 6], 9: [2, 3, 5, 7], 10: [2, 3, 5, 8], 11: [2, 4, 6, 9], 12: [2, 4, 6, 10]}
const TIER_BONUS: Dictionary = {8: [768, 512, 256, 128, 0], 9: [512, 256, 128, 64, 0], 10: [256, 128, 64, 0, 0]}
const TOOL_STATS: Dictionary = {"request_hint": "hint_used", "locate": "locate_used", "mouse": "mouse_used", "activate_draft": "draft_used", "apply_hint": "hint_apply_used"}

static func initial(value: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"score": 0, "combo": 0, "max_combo": 0, "se_count": 0, "se_last_step": -1, "step_used": 0, "tool_used": {}, "draft_elapsed_ms": 0}
	result.merge(value.duplicate(true), true)
	return result

static func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "performance must be a dictionary"
	for field: String in ["score", "combo", "max_combo", "se_count", "step_used", "draft_elapsed_ms"]:
		if typeof(value.get(field)) != TYPE_INT or int(value[field]) < 0:
			return "invalid performance " + field
	if typeof(value.get("se_last_step")) != TYPE_INT or int(value.se_last_step) < -1:
		return "invalid performance se_last_step"
	if int(value.max_combo) < int(value.combo) or not value.get("tool_used") is Dictionary:
		return "invalid performance counters"
	for key: Variant in value.tool_used:
		if not key is String or typeof(value.tool_used[key]) != TYPE_INT or int(value.tool_used[key]) < 0:
			return "invalid performance tool count"
	return ""

static func gain_for_combo(count: int) -> int:
	return mini(576 + maxi(0, count - 1) * 96, 1440)

static func tier_bonus(group: int, size: int, delta: int) -> int:
	if delta <= 0 or not TIER_MAX.has(size) or not TIER_BONUS.has(group):
		return 0
	var tier: int = 4
	for index: int in 4:
		if delta <= int(TIER_MAX[size][index]):
			tier = index
			break
	return int(TIER_BONUS[group][tier])

## scoring 可提供手势在途的 consumed_step；该值不等于已结束手势的 step_used。
## 工具步数固定为一，草稿提交均摊已发生的草稿手势步数。
static func project(snapshot: Dictionary, kind: String, payload: Dictionary, result: Dictionary, changes: Array) -> Dictionary:
	var performance: Dictionary = initial(snapshot.get("performance", {}))
	var events: Array[Dictionary] = []
	var delta: Dictionary = {"step_used": 0, "tool_used": {}, "total_stats": {}}
	if bool(result.get("already_applied", false)):
		return {"performance": performance, "events": events, "delta": delta}
	var scoring: Dictionary = payload.get("scoring", {})
	if kind == "activate_draft":
		performance.draft_elapsed_ms = 0
	if kind in ["draft_clear", "draft_commit"]:
		var wrong: int = 0
		var correct: int = 0
		for row: int in snapshot.board.size():
			for col: int in snapshot.board[row].size():
				var cell: int = int(snapshot.board[row][col])
				var answer: bool = bool(snapshot.solution[row][col])
				if cell == States.DRAFT_CAT:
					if answer:
						correct += 1
					else:
						wrong += 1
				elif cell == States.DRAFT_CROSS and answer:
					wrong += 1
		if wrong > 0:
			delta.total_stats["draft_error_total"] = wrong
		elif correct > 0:
			delta.total_stats["draft_correct_total"] = correct
		if kind == "draft_clear":
			delta.total_stats["draft_stop_used_total"] = 1
		if int(performance.draft_elapsed_ms) > 0:
			delta.total_stats["draft_time_total_ms"] = int(performance.draft_elapsed_ms)
		performance.draft_elapsed_ms = 0
	var step: int = 1 if kind in ["mouse", "locate", "apply_hint"] else int(scoring.get("step_increment", 0))
	step = maxi(0, step)
	performance.step_used += step
	delta.step_used = step
	if TOOL_STATS.has(kind):
		var key: String = TOOL_STATS[kind]
		performance.tool_used[key] = int(performance.tool_used.get(key, 0)) + 1
		delta.tool_used[key] = 1
	var cats: Array[Dictionary] = []
	for change: Dictionary in changes:
		if int(change.get("after", 0)) == States.CAT and int(change.get("before", 0)) != States.CAT:
			cats.append(change)
	var consumed: int = int(scoring.get("consumed_step", performance.step_used))
	var amortized: int = -1
	if kind == "draft_commit" and not cats.is_empty():
		amortized = maxi(1, roundi((performance.step_used - int(performance.se_last_step)) / float(cats.size())))
	var group: int = int(snapshot.get("content", {}).get("gameplay_policy", {}).get("score_encourage", 2))
	for cat: Dictionary in cats:
		performance.combo += 1
		performance.max_combo = maxi(int(performance.max_combo), int(performance.combo))
		performance.se_count += 1
		var step_delta: int = amortized if amortized >= 0 else consumed - int(performance.se_last_step)
		if int(performance.se_last_step) < 0:
			step_delta = 0
		performance.se_last_step = consumed
		var gain: int = gain_for_combo(int(performance.se_count)) + tier_bonus(group, snapshot.board.size(), step_delta)
		performance.score += gain
		events.append({"row": int(cat.row), "col": int(cat.col), "gain": gain, "step_delta": step_delta, "score": performance.score, "combo": performance.combo, "max_combo": performance.max_combo, "se_count": performance.se_count, "se_last_step": performance.se_last_step})
	if not result.get("wrong_positions", []).is_empty():
		performance.combo = 0
		performance.se_count = 0
	return {"performance": performance, "events": events, "delta": delta}


## 通关附加分只按冻结规则和完成前棋盘计算，提交和演出共享同一个计划。
static func win_bonus(board: Array, policy: Dictionary, perfect: bool, full_hp: bool, draft_used: bool) -> Dictionary:
	var encourage: int = int(policy.get("win_encourage_variant", 0))
	var encouraged: bool = (encourage == 1 and perfect) or (encourage == 2 and full_hp)
	var enabled: bool = int(policy.get("auto_x_fill_variant", 0)) != 0
	var cells: Array[Vector2i] = []
	var crosses: int = 0
	if not encouraged and (not enabled or draft_used):
		return {}
	for row: int in board.size():
		for col: int in board[row].size():
			var state: int = int(board[row][col])
			if States.is_blank(state):
				cells.append(Vector2i(row, col))
			elif States.is_cross(state):
				crosses += 1
	if cells.is_empty() and not encouraged:
		return {}
	var banner: bool = encouraged or crosses == 0
	return {"cells": cells, "base_gain": cells.size() * 10, "gain": cells.size() * 10 + (100 if banner else 0),
		"banner": banner, "title": "WIN_PERFECT_WIN" if encouraged else "WIN_X_FREE_BONUS",
		"instant": int(policy.get("auto_x_fill_variant", 0)) == 1}
