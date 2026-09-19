# V2（分档文案版）：按难度 / 重开 / 失误 / 击败率把通关文案分成多档，每档一组候选随机取
class_name PassTextStrategyV2
extends PassTextStrategy

# 困难关首次通关：5 条候选
const _HARD_FIRST: Array[Dictionary] = [
	{"title": "WIN_V2_HARD_FIRST_TITLE_0", "body": "WIN_V2_HARD_FIRST_BODY_0"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_1", "body": "WIN_V2_HARD_FIRST_BODY_1"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_2", "body": "WIN_V2_HARD_FIRST_BODY_2"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_3", "body": "WIN_V2_HARD_FIRST_BODY_3"},
	{"title": "WIN_V2_HARD_FIRST_TITLE_4", "body": "WIN_V2_HARD_FIRST_BODY_4"},
]

# 困难关重开过：5 条候选
const _HARD_RETRY: Array[Dictionary] = [
	{"title": "WIN_V2_HARD_RETRY_TITLE_0", "body": "WIN_V2_HARD_RETRY_BODY_0"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_1", "body": "WIN_V2_HARD_RETRY_BODY_1"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_2", "body": "WIN_V2_HARD_RETRY_BODY_2"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_3", "body": "WIN_V2_HARD_RETRY_BODY_3"},
	{"title": "WIN_V2_HARD_RETRY_TITLE_4", "body": "WIN_V2_HARD_RETRY_BODY_4"},
]

# 零失误且一次过：4 条候选
const _PERFECT: Array[Dictionary] = [
	{"title": "WIN_V2_PERFECT_TITLE_0", "body": "WIN_V2_PERFECT_BODY_0"},
	{"title": "WIN_V2_PERFECT_TITLE_1", "body": "WIN_V2_PERFECT_BODY_1"},
	{"title": "WIN_V2_PERFECT_TITLE_2", "body": "WIN_V2_PERFECT_BODY_2"},
	{"title": "WIN_V2_PERFECT_TITLE_3", "body": "WIN_V2_PERFECT_BODY_3"},
]

# 击败率 ≤ 75%：单条
const _STRATEGIC: Array[Dictionary] = [
	{"title": "WIN_V2_STRATEGIC_TITLE", "body": "WIN_V2_STRATEGIC_BODY"},
]

# 75% < 击败率 < 83%：正文带 {pct} 占位
const _PERCEPTIVE: Array[Dictionary] = [
	{"title": "WIN_V2_PERCEPTIVE_TITLE", "body": "WIN_V2_PERCEPTIVE_BODY"},
]

# 83% ≤ 击败率 < 91%
const _INTELLIGENT: Array[Dictionary] = [
	{"title": "WIN_V2_INTELLIGENT_TITLE", "body": "WIN_V2_INTELLIGENT_BODY"},
]

# 击败率 ≥ 91%
const _BRILLIANT: Array[Dictionary] = [
	{"title": "WIN_V2_BRILLIANT_TITLE", "body": "WIN_V2_BRILLIANT_BODY"},
]

# 比上一次通关更快：正文带 {pct} 与 {diff} 两个占位
const _AWESOME: Array[Dictionary] = [
	{"title": "WIN_V2_AWESOME_TITLE", "body": "WIN_V2_AWESOME_BODY"},
]

# 重开或复活过：3 条候选
const _RETRY: Array[Dictionary] = [
	{"title": "WIN_V2_RETRY_TITLE_0", "body": "WIN_V2_RETRY_BODY_0"},
	{"title": "WIN_V2_RETRY_TITLE_1", "body": "WIN_V2_RETRY_BODY_1"},
	{"title": "WIN_V2_RETRY_TITLE_2", "body": "WIN_V2_RETRY_BODY_2"},
]


# 选档入口：先看难度与是否重开 / 复活，再按击败率细分；每日关不出文案
func get_win_text(level_config: Dictionary) -> Dictionary:
	# 统一的空结果
	var default_result: Dictionary = {"title": "", "body": "", "shown_percent": -1.0}
	# 每日关不走这套文案
	if level_config.get("is_daily", false):
		return default_result

	# 困难关判定：遵守 rule_normal_rank 的 group_j 规则
	var lv: int = level_config.get("level", 0)
	var hard: bool = (
		lv > 0
		and (
			LevelData.is_hard_level_group_j(lv)
			if ABTestManager.rule_normal_rank.is_group_j()
			else LevelData.is_hard_level(lv)
		)
	)
	# 重开与复活次数决定后面走哪条分支
	var restart_n: int = level_config.get("restart_count", 0)
	var revive_n: int = level_config.get("revive_count", 0)

	# 困难关只看是否重开过（不计击败率、不刷新纪录）
	if hard:
		if restart_n == 0:
			return _pick_pair(_HARD_FIRST)
		return _pick_pair(_HARD_RETRY)

	# 普通关：重开或复活过就算「多把尝试」
	var multi: bool = restart_n > 0 or revive_n > 0
	# 零失误：一次都没放错猫
	var zero_miss: bool = level_config.get("mistake_count", 0) == 0

	# 零失误且一次过：给最高档文案
	if zero_miss and not multi:
		return _pick_pair(_PERFECT)

	# 一次过才谈得上击败率分档
	if not multi:
		var sz: int = level_config.get("size", 0)
		# 没尺寸就退出
		if sz <= 0:
			return default_result
		var elapsed: float = float(level_config.get("elapsed_sec", 0))
		var pct: float = PassTextStats.round_non_zero_decimal(
			PassTextStats.beat_percent_from_elapsed(elapsed, sz)
		)
		# 慢于 75% 只给「有策略」档
		if pct <= 75.0:
			return _pick_pair(_STRATEGIC)

		# 上局纪录，-1 表示没有
		var last: float = level_config.get("last_win_beat_percent", -1.0)
		if last >= 0.0 and pct > last:
			# 比上次更快：把提升幅度一起报出来
			var diff: float = PassTextStats.round_non_zero_decimal(pct - last)
			return _pick_pair_with_pct_diff(_AWESOME, pct, diff)
		# 其余按击败率往上分三档
		if pct < 83.0:
			return _pick_pair_with_pct(_PERCEPTIVE, pct)
		if pct < 91.0:
			return _pick_pair_with_pct(_INTELLIGENT, pct)
		return _pick_pair_with_pct(_BRILLIANT, pct)

	# 多把尝试：统一走「再来一次」文案
	return _pick_pair(_RETRY)


# 从池里随机取一条：标题与正文都翻译，正文居中，不产出百分比
func _pick_pair(pool: Array[Dictionary]) -> Dictionary:
	var entry: Dictionary = pool[randi() % pool.size()]
	var title: String = tr(entry["title"])
	var body: String = tr(entry["body"])
	return {"title": title, "body": "[center]%s[/center]" % body, "shown_percent": -1.0}


# 取一条并把正文里的 {pct} 换成绿色放大数字，shown_percent 回传以刷新纪录
func _pick_pair_with_pct(pool: Array[Dictionary], pct: float) -> Dictionary:
	var entry: Dictionary = pool[randi() % pool.size()]
	var title: String = tr(entry["title"])
	var pct_str: String = I18nFormat.percent(pct, 1)
	var highlight: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % pct_str
	var body: String = tr(entry["body"]).replace("{pct}", highlight)
	return {"title": title, "body": "[center]%s[/center]" % body, "shown_percent": pct}


# 同上，额外把 {diff} 也换成绿色放大数字
func _pick_pair_with_pct_diff(pool: Array[Dictionary], pct: float, diff: float) -> Dictionary:
	var entry: Dictionary = pool[randi() % pool.size()]
	var title: String = tr(entry["title"])
	var pct_str: String = I18nFormat.percent(pct, 1)
	var diff_str: String = I18nFormat.percent(diff, 1)
	var hl_pct: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % pct_str
	var hl_diff: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % diff_str
	var body: String = tr(entry["body"]).replace("{pct}", hl_pct).replace("{diff}", hl_diff)
	return {"title": title, "body": "[center]%s[/center]" % body, "shown_percent": pct}
