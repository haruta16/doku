## 排行活动周期的纯判断；计算开放条件、到期时刻、剩余秒数及全局周期编号。

class_name RankActivityPeriod
extends RefCounted


## 将解锁进度、当前阶段、上期状态和重新开放条件组合成布尔决策，不创建活动池。
static func should_open(
	period_count: int,
	level: int,
	prev_awarded: bool,
	wins_since_close: int,
	at_home: bool,
	is_new_session: bool,
	unlock_level: int,
	reopen_wins: int
) -> bool:
	if period_count == 0:
		return level >= unlock_level
	if reopen_wins == 0:
		return true
	if prev_awarded:
		return at_home or wins_since_close >= reopen_wins
	return wins_since_close >= reopen_wins or is_new_session


static func is_expired(now: int, end_unix: int) -> bool:
	return end_unix > 0 and now >= end_unix


static func compute_end(now: int, duration_sec: int) -> int:
	return now + duration_sec


static func remaining_sec(now: int, end_unix: int) -> int:
	return maxi(0, end_unix - now)


## 把本地日期/时间归入全局周期编号，使开放规则不依赖页面停留时长。
static func global_period_index(now_unix: int, tz_bias_sec: int, t0_local_day: int) -> int:
	var local_day: int = (now_unix + tz_bias_sec) / 86400
	return maxi(0, local_day - t0_local_day)
