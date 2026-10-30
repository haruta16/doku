## 第三版通关文案策略：区分难度、重试、无失误和用时表现，选择对应文案池。
class_name PassTextStrategyV3
extends PassTextStrategy

const _HARD_FIRST: Array[Dictionary] = [
	{"title": "WIN_V2_HARD_FIRST_TITLE_0", "body": "WIN_V2_HARD_FIRST_BODY_0"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_1", "body": "WIN_V2_HARD_FIRST_BODY_1"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_2", "body": "WIN_V2_HARD_FIRST_BODY_2"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_3", "body": "WIN_V2_HARD_FIRST_BODY_3"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_4", "body": "WIN_V2_HARD_FIRST_BODY_4"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_5", "body": "WIN_V3_HARD_FIRST_BODY_5"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_6", "body": "WIN_V3_HARD_FIRST_BODY_6"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_7", "body": "WIN_V3_HARD_FIRST_BODY_7"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_8", "body": "WIN_V3_HARD_FIRST_BODY_8"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_9", "body": "WIN_V3_HARD_FIRST_BODY_9"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_10", "body": "WIN_V3_HARD_FIRST_BODY_10"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_11", "body": "WIN_V3_HARD_FIRST_BODY_11"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_12", "body": "WIN_V3_HARD_FIRST_BODY_12"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_13", "body": "WIN_V3_HARD_FIRST_BODY_13"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_14", "body": "WIN_V3_HARD_FIRST_BODY_14"},
]

const _HARD_RETRY: Array[Dictionary] = [
	{"title": "WIN_V2_HARD_RETRY_TITLE_0", "body": "WIN_V2_HARD_RETRY_BODY_0"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_1", "body": "WIN_V2_HARD_RETRY_BODY_1"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_2", "body": "WIN_V2_HARD_RETRY_BODY_2"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_3", "body": "WIN_V2_HARD_RETRY_BODY_3"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_4", "body": "WIN_V2_HARD_RETRY_BODY_4"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_5", "body": "WIN_V3_HARD_RETRY_BODY_5"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_6", "body": "WIN_V3_HARD_RETRY_BODY_6"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_7", "body": "WIN_V3_HARD_RETRY_BODY_7"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_8", "body": "WIN_V3_HARD_RETRY_BODY_8"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_9", "body": "WIN_V3_HARD_RETRY_BODY_9"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_10", "body": "WIN_V3_HARD_RETRY_BODY_10"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_11", "body": "WIN_V3_HARD_RETRY_BODY_11"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_12", "body": "WIN_V3_HARD_RETRY_BODY_12"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_13", "body": "WIN_V3_HARD_RETRY_BODY_13"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_14", "body": "WIN_V3_HARD_RETRY_BODY_14"},
]

const _SH_FIRST: Array[Dictionary] = [
	{"title": "WIN_V2_HARD_FIRST_TITLE_0", "body": "WIN_SH_FIRST_BODY_0"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_1", "body": "WIN_SH_FIRST_BODY_1"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_2", "body": "WIN_SH_FIRST_BODY_2"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_3", "body": "WIN_SH_FIRST_BODY_3"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_4", "body": "WIN_SH_FIRST_BODY_4"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_5", "body": "WIN_SH_FIRST_BODY_5"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_6", "body": "WIN_SH_FIRST_BODY_6"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_7", "body": "WIN_SH_FIRST_BODY_7"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_8", "body": "WIN_SH_FIRST_BODY_8"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_9", "body": "WIN_V3_HARD_FIRST_BODY_9"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_10", "body": "WIN_V3_HARD_FIRST_BODY_10"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_11", "body": "WIN_SH_FIRST_BODY_11"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_12", "body": "WIN_V3_HARD_FIRST_BODY_12"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_13", "body": "WIN_V3_HARD_FIRST_BODY_13"},
	{"title": "WIN_V3_HARD_FIRST_TITLE_14", "body": "WIN_SH_FIRST_BODY_14"},
]

const _SH_RETRY: Array[Dictionary] = [
	{"title": "WIN_V2_HARD_RETRY_TITLE_0", "body": "WIN_V2_HARD_RETRY_BODY_0"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_1", "body": "WIN_SH_RETRY_BODY_1"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_2", "body": "WIN_V2_HARD_RETRY_BODY_2"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_3", "body": "WIN_SH_RETRY_BODY_3"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_4", "body": "WIN_V2_HARD_RETRY_BODY_4"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_5", "body": "WIN_SH_RETRY_BODY_5"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_6", "body": "WIN_V3_HARD_RETRY_BODY_6"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_7", "body": "WIN_SH_RETRY_BODY_7"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_8", "body": "WIN_V3_HARD_RETRY_BODY_8"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_9", "body": "WIN_V3_HARD_RETRY_BODY_9"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_10", "body": "WIN_V3_HARD_RETRY_BODY_10"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_11", "body": "WIN_SH_RETRY_BODY_11"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_12", "body": "WIN_SH_RETRY_BODY_12"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_13", "body": "WIN_V3_HARD_RETRY_BODY_13"},
	{"title": "WIN_V3_HARD_RETRY_TITLE_14", "body": "WIN_V3_HARD_RETRY_BODY_14"},
]

const _PERFECT: Array[Dictionary] = [
	{"title": "WIN_V2_PERFECT_TITLE_0", "body": "WIN_V2_PERFECT_BODY_0"},
	{"title": "WIN_V2_PERFECT_TITLE_1", "body": "WIN_V2_PERFECT_BODY_1"},
	{"title": "WIN_V2_PERFECT_TITLE_2", "body": "WIN_V2_PERFECT_BODY_2"},
	{"title": "WIN_V2_PERFECT_TITLE_3", "body": "WIN_V2_PERFECT_BODY_3"},
	{"title": "WIN_V3_PERFECT_TITLE_4", "body": "WIN_V3_PERFECT_BODY_4"},
	{"title": "WIN_V3_PERFECT_TITLE_5", "body": "WIN_V3_PERFECT_BODY_5"},
	{"title": "WIN_V3_PERFECT_TITLE_6", "body": "WIN_V3_PERFECT_BODY_6"},
	{"title": "WIN_V3_PERFECT_TITLE_7", "body": "WIN_V3_PERFECT_BODY_7"},
	{"title": "WIN_V3_PERFECT_TITLE_8", "body": "WIN_V3_PERFECT_BODY_8"},
	{"title": "WIN_V3_PERFECT_TITLE_9", "body": "WIN_V3_PERFECT_BODY_9"},
	{"title": "WIN_V3_PERFECT_TITLE_10", "body": "WIN_V3_PERFECT_BODY_10"},
	{"title": "WIN_V3_PERFECT_TITLE_11", "body": "WIN_V3_PERFECT_BODY_11"},
	{"title": "WIN_V3_PERFECT_TITLE_12", "body": "WIN_V3_PERFECT_BODY_12"},
	{"title": "WIN_V3_PERFECT_TITLE_13", "body": "WIN_V3_PERFECT_BODY_13"},
]

const _RETRY: Array[Dictionary] = [
	{"title": "WIN_V2_RETRY_TITLE_0", "body": "WIN_V2_RETRY_BODY_0"},
	{"title": "WIN_V2_RETRY_TITLE_1", "body": "WIN_V2_RETRY_BODY_1"},
	{"title": "WIN_V2_RETRY_TITLE_2", "body": "WIN_V2_RETRY_BODY_2"},
	{"title": "WIN_V3_RETRY_TITLE_3", "body": "WIN_V3_RETRY_BODY_3"},
	{"title": "WIN_V3_RETRY_TITLE_4", "body": "WIN_V3_RETRY_BODY_4"},
	{"title": "WIN_V3_RETRY_TITLE_5", "body": "WIN_V3_RETRY_BODY_5"},
	{"title": "WIN_V3_RETRY_TITLE_6", "body": "WIN_V3_RETRY_BODY_6"},
	{"title": "WIN_V3_RETRY_TITLE_7", "body": "WIN_V3_RETRY_BODY_7"},
	{"title": "WIN_V3_RETRY_TITLE_8", "body": "WIN_V3_RETRY_BODY_8"},
	{"title": "WIN_V3_RETRY_TITLE_9", "body": "WIN_V3_RETRY_BODY_9"},
	{"title": "WIN_V3_RETRY_TITLE_10", "body": "WIN_V3_RETRY_BODY_10"},
	{"title": "WIN_V3_RETRY_TITLE_11", "body": "WIN_V3_RETRY_BODY_11"},
	{"title": "WIN_V3_RETRY_TITLE_12", "body": "WIN_V3_RETRY_BODY_12"},
]

const _PLAIN: Array[Dictionary] = [
	{"title": "WIN_V2_STRATEGIC_TITLE", "body": "WIN_V2_STRATEGIC_BODY"},
	{"title": "WIN_V3_PLAIN_TITLE_0", "body": "WIN_V3_PLAIN_BODY_0"},
	{"title": "WIN_V3_PLAIN_TITLE_1", "body": "WIN_V3_PLAIN_BODY_1"},
	{"title": "WIN_V3_PLAIN_TITLE_2", "body": "WIN_V3_PLAIN_BODY_2"},
	{"title": "WIN_V3_PLAIN_TITLE_3", "body": "WIN_V3_PLAIN_BODY_3"},
	{"title": "WIN_V3_PLAIN_TITLE_4", "body": "WIN_V3_PLAIN_BODY_4"},
	{"title": "WIN_V3_PLAIN_TITLE_5", "body": "WIN_V3_PLAIN_BODY_5"},
	{"title": "WIN_V3_PLAIN_TITLE_6", "body": "WIN_V3_PLAIN_BODY_6"},
	{"title": "WIN_V3_PLAIN_TITLE_7", "body": "WIN_V3_PLAIN_BODY_7"},
	{"title": "WIN_V3_PLAIN_TITLE_8", "body": "WIN_V3_PLAIN_BODY_8"},
]

const _PERCEPTIVE: Array[Dictionary] = [
	{"title": "WIN_V2_PERCEPTIVE_TITLE", "body": "WIN_V2_PERCEPTIVE_BODY"}
]
const _INTELLIGENT: Array[Dictionary] = [
	{"title": "WIN_V2_INTELLIGENT_TITLE", "body": "WIN_V2_INTELLIGENT_BODY"}
]
const _BRILLIANT: Array[Dictionary] = [
	{"title": "WIN_V2_BRILLIANT_TITLE", "body": "WIN_V2_BRILLIANT_BODY"}
]
const _AWESOME: Array[Dictionary] = [
	{"title": "WIN_V2_AWESOME_TITLE", "body": "WIN_V2_AWESOME_BODY"}
]


## 先区分每日挑战和难关，再按重试、失误与用时选择文案，优先级决定只展示一个场景。
func get_win_text(level_config: Dictionary) -> Dictionary:
	var default_result: Dictionary = {
		"title": "", "body": "", "body_key": "", "shown_percent": -1.0
	}
	if level_config.get("is_daily", false):
		return default_result

	var lv: int = level_config.get("level", 0)
	var hard: bool = lv > 0 and LevelSelector.is_hard_level(lv)

	var sh: bool = lv > 0 and LevelSelector.is_super_hard_level(lv)
	var restart_n: int = level_config.get("restart_count", 0)
	var revive_n: int = level_config.get("revive_count", 0)

	if hard or sh:
		if restart_n == 0:
			return _pick_pair(_SH_FIRST if sh else _HARD_FIRST)
		return _pick_pair(_SH_RETRY if sh else _HARD_RETRY)

	var multi: bool = restart_n > 0 or revive_n > 0
	var zero_miss: bool = level_config.get("mistake_count", 0) == 0
	if zero_miss and not multi:
		return _pick_pair(_PERFECT)

	if not multi:
		var sz: int = level_config.get("size", 0)
		if sz <= 0:
			return default_result
		var elapsed: float = float(level_config.get("elapsed_sec", 0))
		var pct: float = PassTextStats.round_non_zero_decimal(_beat_percent(elapsed, sz))
		var last: float = level_config.get("last_win_beat_percent", -1.0)
		return _percent_scene(pct, last)

	return _pick_pair(_RETRY)


func _percent_scene(_pct: float, _last: float) -> Dictionary:
	push_error("PassTextStrategyV3._percent_scene 未实现，子类必须 override")
	return {"title": "", "body": "", "shown_percent": -1.0}


func _beat_percent(elapsed_sec: float, sz: int) -> float:
	return PassTextStats.beat_percent_from_elapsed(elapsed_sec, sz)


func _plain_pool() -> Array[Dictionary]:
	return _PLAIN


func _pick_pair(pool: Array[Dictionary]) -> Dictionary:
	var entry: Dictionary = pool[randi() % pool.size()]
	var title: String = tr(entry["title"])
	var body: String = _translate_body(entry["body"])
	return {
		"title": title,
		"body": "[center]%s[/center]" % body,
		"body_key": entry["body"],
		"shown_percent": -1.0
	}


func _pick_pair_with_pct(pool: Array[Dictionary], pct: float) -> Dictionary:
	var entry: Dictionary = pool[randi() % pool.size()]
	var title: String = tr(entry["title"])
	var pct_str: String = I18nFormat.percent(pct, 1)
	var highlight: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % pct_str
	var body: String = _translate_body(entry["body"]).replace("{pct}", highlight)
	return {
		"title": title,
		"body": "[center]%s[/center]" % body,
		"body_key": entry["body"],
		"shown_percent": pct
	}


func _pick_pair_with_pct_diff(pool: Array[Dictionary], pct: float, diff: float) -> Dictionary:
	var entry: Dictionary = pool[randi() % pool.size()]
	var title: String = tr(entry["title"])
	var pct_str: String = I18nFormat.percent(pct, 1)
	var diff_str: String = I18nFormat.percent(diff, 1)
	var hl_pct: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % pct_str
	var hl_diff: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % diff_str
	var body: String = _translate_body(entry["body"]).replace("{pct}", hl_pct).replace(
		"{diff}", hl_diff
	)
	return {
		"title": title,
		"body": "[center]%s[/center]" % body,
		"body_key": entry["body"],
		"shown_percent": pct
	}


func _translate_body(body_key: String) -> String:
	return TextHighlightRenderer.render(
		ABTestManager.text_highlight, body_key, tr(body_key), "#02BE52"
	)
