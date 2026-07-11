class_name PassTextStrategyV1
extends PassTextStrategy


func get_win_text(level_config: Dictionary) -> Dictionary:
	var default_result: Dictionary = {"title": "", "body": "", "shown_percent": -1.0}
	if level_config.get("is_daily", false):
		return default_result
	var sz: int = level_config.get("size", 0)
	if sz <= 0:
		return default_result
	var elapsed: float = float(level_config.get("elapsed_sec", 0))
	var pct: float = PassTextStats.beat_percent_from_elapsed(elapsed, sz)
	var rounded: float = PassTextStats.round_non_zero_decimal(pct)
	var template: String = tr("WIN_BEAT_PERCENT_TIP")
	var pct_str: String = I18nFormat.percent(rounded, 1)
	var highlight: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % pct_str
	var body: String = template.replace("{pct}", highlight).replace("{br}", "\n")
	return {"title": "", "body": "[center]%s[/center]" % body, "shown_percent": rounded}
