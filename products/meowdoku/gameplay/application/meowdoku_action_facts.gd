## 产品动作的纯候选统计；只接收值，不访问页面、选题服务或 Autoload。
## today 可由调用者冻结；未传时取系统日期，不触发任何持久化或信号。
class_name MeowdokuActionFacts
extends RefCounted

const LevelKind = preload("res://products/meowdoku/gameplay/application/models/level_kind.gd")

## 午夜轮换只改变候选；未来/未识别的补偿条目不会被日期轮换删除。
static func stage_activity(candidate: Dictionary, kind: String, _mode: String = "", _policy: Dictionary = {}, today: String = "") -> Dictionary:
	var profile: Dictionary = candidate.profile
	if today.is_empty():
		today = Time.get_date_string_from_system()
	if str(profile.get("today_date", "")) != today:
		profile["last_day_session_count"] = int(profile.get("today_session_count", 0))
		for key: String in ["today_session_count", "today_played_count", "today_active_sec", "today_cat_found", "today_mark_placed", "today_tool_consumed", "today_revive_count", "restored_today_count"]:
			profile[key] = 0
		profile["game_barrage_daily_keys"] = PackedStringArray()
		profile["daily_auto_mark_enabled"] = false
		candidate.round_runtime["dc_start_toast_pct"] = {}
		profile["active_days"] = int(profile.get("active_days", 0)) + 1
		var wins: Dictionary = profile.get("recent_win_counts_by_day", {}).duplicate(true)
		var cutoff: int = Time.get_unix_time_from_datetime_string(today + "T00:00:00") - 172800
		for key: String in wins.keys():
			if Time.get_unix_time_from_datetime_string(key + "T00:00:00") < cutoff:
				wins.erase(key)
		profile["recent_win_counts_by_day"] = wins
		profile["today_date"] = today
	if kind == "tool":
		profile["today_tool_consumed"] = int(profile.get("today_tool_consumed", 0)) + 1
	elif kind == "revive":
		profile["today_revive_count"] = int(profile.get("today_revive_count", 0)) + 1
	elif kind == "finished":
		profile["today_played_count"] = int(profile.get("today_played_count", 0)) + 1
	return {"ok": true}

## 棋盘已裁决的错误结果才计数；动画回调不再写统计或评分事实。
static func stage_action_facts(candidate: Dictionary, mode: String, receipt: Dictionary, snapshot: Dictionary) -> Dictionary:
	if receipt.get("kind", "") == "revive" and mode == "main":
		var rank: Dictionary = candidate.features.get("rank_activity", {}).duplicate(true)
		rank["level_failed_pending"] = false
		candidate.features["rank_activity"] = rank
	var result: Dictionary = receipt.get("result", {})
	var wrong: Array = result.get("wrong_positions", [])
	if wrong.is_empty():
		return {"ok": true}
	var count: int = wrong.size()
	var p: Dictionary = candidate.profile
	var stats_key: String = "daily_total" if mode == "daily" else "main_total"
	var stats: Dictionary = candidate.endgame.stats.get(stats_key, {})
	stats["invalid_sign_total"] = int(stats.get("invalid_sign_total", 0)) + count
	candidate.endgame.stats[stats_key] = stats
	var kind: int = int(snapshot.get("kind", snapshot.get("content", {}).get("kind", LevelKind.MAIN)))
	if not bool(snapshot.get("lives_inf", false)):
		p["elo_fish_consumed"] = int(p.get("elo_fish_consumed", 0)) + count
		var attempt: Dictionary = p.get("elo_v2_attempt", {})
		var content: Dictionary = snapshot.get("content", {})
		if mode == "main" and kind == LevelKind.MAIN and not attempt.is_empty() and int(attempt.get("level", 0)) == int(content.get("level", 0)):
			attempt["fish_consumed"] = int(attempt.get("fish_consumed", 0)) + count
			p["elo_v2_attempt"] = attempt
	if mode != "daily":
		var key: String = "insert_golden_fish_wrong_cat_num" if LevelKind.is_insert_golden_fish(kind) else "current_wrong_cat_num"
		p[key] = int(p.get(key, 0)) + count
	return {"ok": true}
