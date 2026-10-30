## 已冻结关卡定义的纯数据契约；不读取当前内容、场景绑定、题库或 Autoload。
## 当前发布包能否兑现题目与媒体引用，仍由 DokuLevelCatalog 校验。
class_name DokuLevelDefinition
extends RefCounted

const Manifest = preload("res://scripts/framework/content/content_manifest.gd")
# 逐关别名只作用于棋盘子树；目录与表现注册共用这一份允许槽位。
const BOARD_MEDIA_SLOTS: Array[String] = ["game/mark", "game/mark_alt", "game/mark_lock", "game/hint_cat", "game/cat"]


static func validate(value: Variant) -> bool:
	return bool(inspect(value).ok)


static func inspect(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _invalid("$", "expected a level definition object")
	for key: Variant in value:
		if key not in ["puzzle", "prefill", "rules", "media", "reward"]:
			return _invalid("$[" + JSON.stringify(key) + "]", "unsupported level definition field")
	var puzzle: Variant = value.get("puzzle")
	if not puzzle is Dictionary:
		return _invalid("$.puzzle", "expected a puzzle reference object")
	for key: Variant in puzzle:
		if key not in ["bank", "rank", "index"]:
			return _invalid("$.puzzle[" + JSON.stringify(key) + "]", "unsupported puzzle reference field")
	if not puzzle.get("bank") is String or not puzzle.bank.begins_with("doku/levels/bankdata"):
		return _invalid("$.puzzle.bank", "expected a Doku bank logical id")
	if not _integer(puzzle.get("index")) or int(puzzle.index) < 1:
		return _invalid("$.puzzle.index", "expected a positive one-based index")
	if puzzle.has("rank") and (not _integer(puzzle.rank) or int(puzzle.rank) not in [1, 2, 3, 4, 5]):
		return _invalid("$.puzzle.rank", "expected an integer rank from 1 to 5")
	if value.has("prefill"):
		if not value.prefill is Array or value.prefill.size() > 12:
			return _invalid("$.prefill", "expected at most 12 prefilled cells")
		var seen: Dictionary = {}
		for index: int in value.prefill.size():
			var cell: Variant = value.prefill[index]
			var path: String = "$.prefill[%d]" % index
			if not cell is Array or cell.size() != 2 or not _integer(cell[0]) or not _integer(cell[1]) or int(cell[0]) < 0 or int(cell[1]) < 0:
				return _invalid(path, "expected a pair of nonnegative integer coordinates")
			var cell_key: String = "%d:%d" % [int(cell[0]), int(cell[1])]
			if seen.has(cell_key):
				return _invalid(path, "duplicate prefilled cell")
			seen[cell_key] = true
	var rules: Variant = value.get("rules", {})
	if not rules is Dictionary:
		return _invalid("$.rules", "expected a rules object")
	for key: Variant in rules:
		if key not in ["initial_lives", "draft_unlock_level"] or not _integer(rules[key]):
			return _invalid("$.rules[" + JSON.stringify(key) + "]", "expected a supported rule with an integer value")
	if int(rules.get("initial_lives", 3)) not in [1, 2, 3]:
		return _invalid("$.rules.initial_lives", "expected 1 to 3 lives")
	if int(rules.get("draft_unlock_level", 21)) < 1 or int(rules.get("draft_unlock_level", 21)) > 10000:
		return _invalid("$.rules.draft_unlock_level", "expected a level from 1 to 10000")
	var reward: Variant = value.get("reward", {})
	if not reward is Dictionary:
		return _invalid("$.reward", "expected a reward object")
	for item: Variant in reward:
		if item not in ["hint", "locate", "undo"] or not _integer(reward[item]) or int(reward[item]) < 1 or int(reward[item]) > 10000:
			return _invalid("$.reward[" + JSON.stringify(item) + "]", "expected a supported inventory item with an integer count from 1 to 10000")
	var media: Variant = value.get("media", {})
	if not media is Dictionary:
		return _invalid("$.media", "expected a media alias object")
	for slot: Variant in media:
		if not slot is String or slot not in BOARD_MEDIA_SLOTS or not media[slot] is String or not Manifest.safe_relative_path(media[slot]):
			return _invalid("$.media[" + JSON.stringify(slot) + "]", "expected a supported board slot mapped to a safe logical media id")
	return {"ok": true, "error": ""}


static func _invalid(path: String, detail: String) -> Dictionary:
	return {"ok": false, "path": path, "detail": detail}


static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and floor(value) == value)

