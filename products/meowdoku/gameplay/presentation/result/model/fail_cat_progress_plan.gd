## 失败猫进度展示方案：根据实验与快照决定进度条、数量和已找到标记的排列。
class_name FailCatProgressPlan
extends RefCounted


## 根据是否有有效快照与实验组合，决定替换数量、追加进度条或保留原数量显示。
static func resolve(wants_replace: bool, wants_add: bool, snapshot: Dictionary) -> Dictionary:
	var total: int = int(snapshot.get("total", 0))

	var usable: bool = total > 0

	var show_bar: bool = usable and (wants_replace or wants_add)
	var added: bool = show_bar and not wants_replace

	var show_count: bool = added or not show_bar

	var tints: PackedColorArray = snapshot.get("tints", PackedColorArray())
	var colored: bool = not tints.is_empty()
	return {
		"show_bar": show_bar,
		"show_count": show_count,
		"bar_added": added,
		"total": total,
		"colored": colored,
		"revealed": _revealed_flags(snapshot.get("revealed", []), total, colored),
	}


## 彩色进度保留原槽位；普通进度只按已找到数量从前向后填充。
static func _revealed_flags(flags: Array, total: int, colored: bool) -> Array[bool]:
	var out: Array[bool] = []
	if total <= 0:
		return out
	out.resize(total)
	if colored:
		for i in mini(flags.size(), total):
			out[i] = bool(flags[i])
		return out
	var found: int = 0
	for i in mini(flags.size(), total):
		if bool(flags[i]):
			found += 1
	for i in found:
		out[i] = true
	return out
