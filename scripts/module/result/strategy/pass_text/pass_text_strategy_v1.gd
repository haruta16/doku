# V1（击败百分比版）：用通关用时算「击败了 X% 玩家」，只出正文，标题仍走默认池
class_name PassTextStrategyV1
extends PassTextStrategy


# 每日关或尺寸非法时不出文案；否则算百分比 → 保留 1 位小数 → 套模板
func get_win_text(level_config: Dictionary) -> Dictionary:
	# 统一的空结果
	var default_result: Dictionary = {"title": "", "body": "", "shown_percent": -1.0}
	# 每日关不走这套文案
	if level_config.get("is_daily", false):
		return default_result
	# size 非法就没法算基准
	var sz: int = level_config.get("size", 0)
	if sz <= 0:
		return default_result
	var elapsed: float = float(level_config.get("elapsed_sec", 0))
	# 用时 → 击败百分比（内部已带随机抖动）
	var pct: float = PassTextStats.beat_percent_from_elapsed(elapsed, sz)
	# 收敛到 1 位小数，避免展示成整数
	var rounded: float = PassTextStats.round_non_zero_decimal(pct)
	var template: String = tr("WIN_BEAT_PERCENT_TIP")
	# 绿色放大后的百分数，用来替换正文里的 {pct}
	var pct_str: String = I18nFormat.percent(rounded, 1)
	var highlight: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % pct_str
	# {br} 是模板里的换行占位
	var body: String = template.replace("{pct}", highlight).replace("{br}", "\n")
	return {"title": "", "body": "[center]%s[/center]" % body, "shown_percent": rounded} # shown_percent 回传出去，非每日关会记进「上局纪录」
