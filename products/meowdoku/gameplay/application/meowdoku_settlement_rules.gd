## 主线结算的纯数据规则；保留原 DDA 判定顺序，不读页面、SDK 或存档。
class_name MeowdokuSettlementRules
extends RefCounted


## 原地推进主线进度，再按新手区、干净通关、累计失败、连续重试和实验策略的顺序调整 DDA。
## profile/runtime 均须来自候选，policy 由上层冻结；函数不保存状态，最后清理本局标记与重试题面。
static func main_win(profile: Dictionary, runtime: Dictionary, level_num: int, policy: Dictionary) -> void:
	var next_level: int = level_num + 1
	if next_level > profile.current_level:
		profile.current_level = next_level

	# RnR mod1 豁免局：只做清理，不参与调档
	if runtime.rnr_mod1_exempt:
		runtime.rnr_mod1_exempt = false
		runtime.current_level_retried = false
		runtime.current_level_dirty = false
		runtime.dda_tool_or_revive_used = false
		runtime.dda_revive_used = false
		runtime.is_daily_first_easy_level = false
		runtime.demoted_this_level = false
		profile.retry_puzzle_level = 0
		profile.retry_puzzle_params = {}


		return

	# 前 5 关是新手区，不调档；6 关以后才按策略层升降
	if level_num >= 6:
		# 关卡越高，允许的策略层上限越高（R2 ~ R6）
		var max_strategy: int
		if level_num >= 201:
			max_strategy = 6
		elif level_num >= 101:
			max_strategy = 5
		elif level_num >= 51:
			max_strategy = 4
		elif level_num >= 21:
			max_strategy = 3
		else:
			max_strategy = 2
		# 连续干净通关几次升一层（51 关后 1 次即可）
		var win_threshold: int = 1 if level_num >= 51 else 2
		var min_strategy: int = 2 if level_num >= 101 else 1
		var clean_win: bool = not runtime.current_level_dirty
		if clean_win:
			profile.consecutive_clean_wins += 1
			if profile.consecutive_clean_wins >= win_threshold and profile.current_strategy < max_strategy:
				profile.current_strategy += 1
				profile.consecutive_clean_wins = 0
		else:
			profile.consecutive_clean_wins = 0

		# 连续失败几次降一层
		var fail_threshold: int = 2 if level_num >= 21 else 1
		if (
			profile.consecutive_fails >= fail_threshold
			and profile.current_strategy > min_strategy
			and not runtime.demoted_this_level
		):
			profile.current_strategy -= 1
			runtime.demoted_this_level = true

		profile.consecutive_fails = 0

		# 21 关之后，重试同一关也算降档信号
		if level_num >= 21:
			if runtime.current_level_retried:
				if profile.current_strategy == profile.retry_tracking_strategy:
					profile.consecutive_retry_levels += 1
					var min_strategy_retry: int = 2 if level_num >= 101 else 1
					if (
						profile.consecutive_retry_levels >= 2
						and profile.current_strategy > min_strategy_retry
						and not runtime.demoted_this_level
					):
						profile.current_strategy -= 1
						profile.consecutive_retry_levels = 0
						profile.retry_tracking_strategy = 0
				else:
					profile.consecutive_retry_levels = 1
					profile.retry_tracking_strategy = profile.current_strategy
			else:
				profile.consecutive_retry_levels = 0
				profile.retry_tracking_strategy = 0

		# 再按 AB 实验档位补一次「用道具 / 复活 / 重试」降档判定
		_dda_apply_demote_on_won(profile, runtime, level_num, min_strategy, policy)

	# 收尾：记录本关是否干净通关，并清掉所有「本局」标记
	profile.last_level_clean_win = not runtime.current_level_dirty
	runtime.current_level_retried = false
	runtime.current_level_dirty = false
	runtime.dda_tool_or_revive_used = false
	runtime.dda_revive_used = false
	runtime.is_daily_first_easy_level = false
	runtime.rnr_mod1_exempt = false
	runtime.demoted_this_level = false
	profile.retry_puzzle_level = 0
	profile.retry_puzzle_params = {}



## 失败结算：标记重试与弄脏、清掉干净通关连击，并累计失败次数供降档
static func main_fail(profile: Dictionary, runtime: Dictionary, level_num: int, policy: Dictionary) -> void:
	runtime.current_level_retried = true
	runtime.current_level_dirty = true

	profile.last_level_clean_win = false

	# 豁免局保留上面的失败标记，不改 DDA 计数；是否写盘由外层事务决定。
	if runtime.rnr_mod1_exempt:
		return
	if level_num >= 6:
		profile.consecutive_clean_wins = 0

		profile.consecutive_fails += 1

	# 该实验档位下，本局用过道具或复活就算降档信号
	if bool(policy.any_action):
		runtime.dda_tool_or_revive_used = true


## 通关时的 AB 实验降档判定：条件满足就降一层；下一关是困难/特殊关时先挂起，等过了再降
static func _dda_apply_demote_on_won(profile: Dictionary, runtime: Dictionary, level_num: int, min_strategy: int, policy: Dictionary) -> void:
	if not (
		bool(policy.retry_once)
		or bool(policy.tool_revive)
		or bool(policy.any_action)
	):
		return

	# 已经吃过「每日首次降档」的局不再二次降档
	if runtime.is_daily_first_easy_level:
		return

	var triggered: bool = false
	if bool(policy.retry_once):
		triggered = runtime.current_level_retried or runtime.dda_revive_used
	elif bool(policy.tool_revive):
		triggered = runtime.dda_tool_or_revive_used
	else:
		triggered = runtime.dda_tool_or_revive_used

	# 下一关是困难关或特殊关时，降档往后挪（免得降完立刻又变难）
	var next_is_skip: bool = bool(policy.next_is_skip)

	# 先把上一关挂起的降档补上
	if runtime.dda_pending_demote and not runtime.demoted_this_level:
		profile.current_strategy = max(min_strategy, profile.current_strategy - 1)
		runtime.dda_pending_demote = false
		runtime.demoted_this_level = true

	# 本关触发的降档：下一关能降就立刻降，不能就挂起
	if triggered and not runtime.demoted_this_level:
		if next_is_skip:
			runtime.dda_pending_demote = true
		else:
			profile.current_strategy = max(min_strategy, profile.current_strategy - 1)
			runtime.demoted_this_level = true


## 与原日切一致，但只改候选数据；调用方决定是否提交。
static func finish_game(profile: Dictionary, today: String) -> void:
	if profile.get("today_date", "") != today:
		profile["last_day_session_count"] = profile.get("today_session_count", 0)
		profile["today_session_count"] = 0
		profile["today_played_count"] = 0
		profile["today_active_sec"] = 0
		profile["restored_today_count"] = 0
		profile["daily_auto_mark_enabled"] = false
		profile["pending_rewards"] = []
		profile["active_days"] = int(profile.get("active_days", 0)) + 1
		profile["today_date"] = today
	profile["today_played_count"] = int(profile.get("today_played_count", 0)) + 1


## 原地记录指定挑战日期的成绩，并保留历史最高击败比例；调用方负责验证数据与提交。
static func daily_win(profile: Dictionary, date: String, elapsed_sec: int, beat_percent: float) -> void:
	profile["daily_completed_date"] = date
	profile["daily_elapsed_sec"] = elapsed_sec
	profile["daily_beat_percent"] = beat_percent
	profile["daily_best_beat_percent"] = maxf(float(profile.get("daily_best_beat_percent", 0.0)), beat_percent)
