class_name StreakData
extends RefCounted

const REWARD_BASE: Dictionary = {"hint": 2, "locate": 2}

var current_streak: int = 0
var best_streak: int = 0
var last_checkin_date: String = ""

var streak_start_weekday: int = -1

var reward_cycle_day: int = 0

var last_group: int = -1

var pending_switch_page: int = 0


func to_dict() -> Dictionary:
	return {
		"current_streak": current_streak,
		"best_streak": best_streak,
		"last_checkin_date": last_checkin_date,
		"streak_start_weekday": streak_start_weekday,
		"reward_cycle_day": reward_cycle_day,
		"last_group": last_group,
		"pending_switch_page": pending_switch_page,
	}


static func from_dict(d: Dictionary) -> StreakData:
	var data := StreakData.new()
	data.current_streak = d.get("current_streak", 0)
	data.best_streak = d.get("best_streak", 0)
	data.last_checkin_date = d.get("last_checkin_date", "")
	data.streak_start_weekday = d.get("streak_start_weekday", -1)
	data.reward_cycle_day = d.get("reward_cycle_day", 0)
	data.last_group = d.get("last_group", -1)
	data.pending_switch_page = d.get("pending_switch_page", 0)
	return data
