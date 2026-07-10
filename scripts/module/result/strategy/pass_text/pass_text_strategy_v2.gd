class_name PassTextStrategyV2
extends PassTextStrategy














const _HARD_FIRST: Array[Dictionary] = [
    {"title": "WIN_V2_HARD_FIRST_TITLE_0", "body": "WIN_V2_HARD_FIRST_BODY_0"}, 
    {"title": "WIN_V2_HARD_FIRST_TITLE_1", "body": "WIN_V2_HARD_FIRST_BODY_1"}, 
    {"title": "WIN_V2_HARD_FIRST_TITLE_2", "body": "WIN_V2_HARD_FIRST_BODY_2"}, 
    {"title": "WIN_V2_HARD_FIRST_TITLE_3", "body": "WIN_V2_HARD_FIRST_BODY_3"}, 
    {"title": "WIN_V2_HARD_FIRST_TITLE_4", "body": "WIN_V2_HARD_FIRST_BODY_4"}, 
]


const _HARD_RETRY: Array[Dictionary] = [
    {"title": "WIN_V2_HARD_RETRY_TITLE_0", "body": "WIN_V2_HARD_RETRY_BODY_0"}, 
    {"title": "WIN_V2_HARD_RETRY_TITLE_1", "body": "WIN_V2_HARD_RETRY_BODY_1"}, 
    {"title": "WIN_V2_HARD_RETRY_TITLE_2", "body": "WIN_V2_HARD_RETRY_BODY_2"}, 
    {"title": "WIN_V2_HARD_RETRY_TITLE_3", "body": "WIN_V2_HARD_RETRY_BODY_3"}, 
    {"title": "WIN_V2_HARD_RETRY_TITLE_4", "body": "WIN_V2_HARD_RETRY_BODY_4"}, 
]


const _PERFECT: Array[Dictionary] = [
    {"title": "WIN_V2_PERFECT_TITLE_0", "body": "WIN_V2_PERFECT_BODY_0"}, 
    {"title": "WIN_V2_PERFECT_TITLE_1", "body": "WIN_V2_PERFECT_BODY_1"}, 
    {"title": "WIN_V2_PERFECT_TITLE_2", "body": "WIN_V2_PERFECT_BODY_2"}, 
    {"title": "WIN_V2_PERFECT_TITLE_3", "body": "WIN_V2_PERFECT_BODY_3"}, 
]


const _STRATEGIC: Array[Dictionary] = [
    {"title": "WIN_V2_STRATEGIC_TITLE", "body": "WIN_V2_STRATEGIC_BODY"}, 
]


const _PERCEPTIVE: Array[Dictionary] = [
    {"title": "WIN_V2_PERCEPTIVE_TITLE", "body": "WIN_V2_PERCEPTIVE_BODY"}, 
]


const _INTELLIGENT: Array[Dictionary] = [
    {"title": "WIN_V2_INTELLIGENT_TITLE", "body": "WIN_V2_INTELLIGENT_BODY"}, 
]


const _BRILLIANT: Array[Dictionary] = [
    {"title": "WIN_V2_BRILLIANT_TITLE", "body": "WIN_V2_BRILLIANT_BODY"}, 
]


const _AWESOME: Array[Dictionary] = [
    {"title": "WIN_V2_AWESOME_TITLE", "body": "WIN_V2_AWESOME_BODY"}, 
]


const _RETRY: Array[Dictionary] = [
    {"title": "WIN_V2_RETRY_TITLE_0", "body": "WIN_V2_RETRY_BODY_0"}, 
    {"title": "WIN_V2_RETRY_TITLE_1", "body": "WIN_V2_RETRY_BODY_1"}, 
    {"title": "WIN_V2_RETRY_TITLE_2", "body": "WIN_V2_RETRY_BODY_2"}, 
]

func get_win_text(level_config: Dictionary) -> Dictionary:
    var default_result: Dictionary = {"title": "", "body": "", "shown_percent": -1.0}
    if level_config.get("is_daily", false):
        return default_result

    var lv: int = level_config.get("level", 0)
    var hard: bool = lv > 0 and (LevelData.is_hard_level_group_j(lv) if ABTestManager.rule_normal_rank.is_group_j() else LevelData.is_hard_level(lv))
    var restart_n: int = level_config.get("restart_count", 0)
    var revive_n: int = level_config.get("revive_count", 0)

    if hard:


        if restart_n == 0:
            return _pick_pair(_HARD_FIRST)
        return _pick_pair(_HARD_RETRY)


    var multi: bool = restart_n > 0 or revive_n > 0
    var zero_miss: bool = level_config.get("mistake_count", 0) == 0


    if zero_miss and not multi:
        return _pick_pair(_PERFECT)


    if not multi:
        var sz: int = level_config.get("size", 0)
        if sz <= 0:
            return default_result
        var elapsed: float = float(level_config.get("elapsed_sec", 0))
        var pct: float = PassTextStats.round_non_zero_decimal(
            PassTextStats.beat_percent_from_elapsed(elapsed, sz))
        if pct <= 75.0:
            return _pick_pair(_STRATEGIC)

        var last: float = level_config.get("last_win_beat_percent", -1.0)
        if last >= 0.0 and pct > last:
            var diff: float = PassTextStats.round_non_zero_decimal(pct - last)
            return _pick_pair_with_pct_diff(_AWESOME, pct, diff)
        if pct < 83.0:
            return _pick_pair_with_pct(_PERCEPTIVE, pct)
        if pct < 91.0:
            return _pick_pair_with_pct(_INTELLIGENT, pct)
        return _pick_pair_with_pct(_BRILLIANT, pct)


    return _pick_pair(_RETRY)


func _pick_pair(pool: Array[Dictionary]) -> Dictionary:
    var entry: Dictionary = pool[randi() % pool.size()]
    var title: String = tr(entry["title"])
    var body: String = tr(entry["body"])
    return {"title": title, "body": "[center]%s[/center]" % body, "shown_percent": -1.0}


func _pick_pair_with_pct(pool: Array[Dictionary], pct: float) -> Dictionary:
    var entry: Dictionary = pool[randi() % pool.size()]
    var title: String = tr(entry["title"])
    var pct_str: String = I18nFormat.percent(pct, 1)
    var highlight: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % pct_str
    var body: String = tr(entry["body"]).replace("{pct}", highlight)
    return {"title": title, "body": "[center]%s[/center]" % body, "shown_percent": pct}


func _pick_pair_with_pct_diff(pool: Array[Dictionary], pct: float, diff: float) -> Dictionary:
    var entry: Dictionary = pool[randi() % pool.size()]
    var title: String = tr(entry["title"])
    var pct_str: String = I18nFormat.percent(pct, 1)
    var diff_str: String = I18nFormat.percent(diff, 1)
    var hl_pct: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % pct_str
    var hl_diff: String = "[font_size=90][b][color=#02BE52]%s[/color][/b][/font_size]" % diff_str
    var body: String = tr(entry["body"]).replace("{pct}", hl_pct).replace("{diff}", hl_diff)
    return {"title": title, "body": "[center]%s[/center]" % body, "shown_percent": pct}
