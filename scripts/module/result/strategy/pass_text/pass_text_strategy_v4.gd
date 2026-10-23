## 第四版通关文案策略：优先展示当日放猫或画叉达到的里程碑，否则复用常规文案。
class_name PassTextStrategyV4
extends PassTextStrategyV3G1

const _CAT_MILESTONE: int = 50

const _MARK_MILESTONE: int = 500

const _TODAY_CAT: Array[Dictionary] = [
	{"title": "WIN_V4_CAT_TITLE_0", "body": "WIN_V4_CAT_BODY_0"},
	{"title": "WIN_V4_CAT_TITLE_1", "body": "WIN_V4_CAT_BODY_1"},
	{"title": "WIN_V4_CAT_TITLE_2", "body": "WIN_V4_CAT_BODY_2"},
	{"title": "WIN_V4_CAT_TITLE_3", "body": "WIN_V4_CAT_BODY_3"},
	{"title": "WIN_V4_CAT_TITLE_4", "body": "WIN_V4_CAT_BODY_4"},
	{"title": "WIN_V4_CAT_TITLE_5", "body": "WIN_V4_CAT_BODY_5"},
	{"title": "WIN_V4_CAT_TITLE_6", "body": "WIN_V4_CAT_BODY_6"},
	{"title": "WIN_V4_CAT_TITLE_7", "body": "WIN_V4_CAT_BODY_7"},
	{"title": "WIN_V4_CAT_TITLE_8", "body": "WIN_V4_CAT_BODY_8"},
	{"title": "WIN_V4_CAT_TITLE_9", "body": "WIN_V4_CAT_BODY_9"},
]

const _TODAY_MARK: Array[Dictionary] = [
	{"title": "WIN_V4_MARK_TITLE_0", "body": "WIN_V4_MARK_BODY_0"},
	{"title": "WIN_V4_MARK_TITLE_1", "body": "WIN_V4_MARK_BODY_1"},
	{"title": "WIN_V4_MARK_TITLE_2", "body": "WIN_V4_MARK_BODY_2"},
	{"title": "WIN_V4_MARK_TITLE_3", "body": "WIN_V4_MARK_BODY_3"},
	{"title": "WIN_V4_MARK_TITLE_4", "body": "WIN_V4_MARK_BODY_4"},
	{"title": "WIN_V4_MARK_TITLE_5", "body": "WIN_V4_MARK_BODY_5"},
	{"title": "WIN_V4_MARK_TITLE_6", "body": "WIN_V4_MARK_BODY_6"},
	{"title": "WIN_V4_MARK_TITLE_7", "body": "WIN_V4_MARK_BODY_7"},
	{"title": "WIN_V4_MARK_TITLE_8", "body": "WIN_V4_MARK_BODY_8"},
	{"title": "WIN_V4_MARK_TITLE_9", "body": "WIN_V4_MARK_BODY_9"},
]


func _wants_cat_scene() -> bool:
	return false


func _wants_mark_scene() -> bool:
	return false


## 检查本局是否跨过当日放猫或画叉门槛，命中多个时随机挑一个，未命中复用基础策略。
func get_win_text(level_config: Dictionary) -> Dictionary:
	if level_config.get("is_daily", false):
		return super.get_win_text(level_config)
	var hits: Array[Dictionary] = []
	if _wants_cat_scene():
		var cat_hit: Dictionary = _milestone_scene(
			level_config, "today_cat_before", "today_cat_after", _CAT_MILESTONE, _TODAY_CAT
		)
		if not cat_hit.is_empty():
			hits.append(cat_hit)
	if _wants_mark_scene():
		var mark_hit: Dictionary = _milestone_scene(
			level_config, "today_mark_before", "today_mark_after", _MARK_MILESTONE, _TODAY_MARK
		)
		if not mark_hit.is_empty():
			hits.append(mark_hit)
	if hits.is_empty():
		return super.get_win_text(level_config)

	return hits[randi() % hits.size()]


## 从本局前后累计量判断是否跨门槛，再把里程碑数值填入文案。
func _milestone_scene(
	level_config: Dictionary,
	before_key: String,
	after_key: String,
	step: int,
	pool: Array[Dictionary]
) -> Dictionary:
	if step <= 0:
		return {}
	var before: int = int(level_config.get(before_key, 0))
	var after: int = int(level_config.get(after_key, 0))
	var milestone: int = _crossed_milestone(before, after, step)
	if milestone <= 0:
		return {}
	return _pick_pair_with_count(pool, milestone)


static func _crossed_milestone(before: int, after: int, step: int) -> int:
	if step <= 0:
		return -1
	@warning_ignore("integer_division")
	var before_tier: int = before / step
	@warning_ignore("integer_division")
	var after_tier: int = after / step
	if after_tier <= before_tier:
		return -1
	return after_tier * step


func _pick_pair_with_count(pool: Array[Dictionary], count: int) -> Dictionary:
	var entry: Dictionary = pool[randi() % pool.size()]
	var title: String = tr(entry["title"])
	var body: String = _translate_body(entry["body"]).replace("{count}", str(count))
	return {
		"title": title,
		"body": "[center]%s[/center]" % body,
		"body_key": entry["body"],
		"shown_percent": -1.0
	}
