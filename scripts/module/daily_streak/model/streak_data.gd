# 连续打卡的存档数据模型：只有字段与字典互转，读写文件由 StreakManager 负责
class_name StreakData
extends RefCounted

# 第 7 天宝箱的奖励基数（道具 kind → 个数），StreakManager 据此生成奖励
const REWARD_BASE: Dictionary = {"hint": 2, "locate": 2}

# ---- 存档字段（字段名就是 streak.cfg 里的 key） ----
var current_streak: int = 0 # 当前连续打卡天数
var best_streak: int = 0 # 历史最长连续天数
var last_checkin_date: String = "" # 最近一次打卡日期 yyyy-mm-dd，空串 = 从没打过

var streak_start_weekday: int = -1 # 本轮第 1 天是星期几（0 = 周日），-1 = 本轮还没开始

var reward_cycle_day: int = 0 # 奖励周期里的第几天（1~7 循环），0 = 还没开始

var last_group: int = -1 # 上次记录的 AB 分组；-1 = 还没记录过（控制组也记 -1）

var pending_switch_page: int = 0 # 待弹出的切组说明页编号（1/2/3），0 = 不用弹


# 转成存档字典，StreakManager 逐字段写进 streak.cfg
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


# 从存档字典还原；老存档缺字段时用默认值兜底
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
