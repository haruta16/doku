## 排行活动总状态机；协调开放、参赛、局内收集、连胜倍率、到期结算和奖励领取。
## 对手来自本地 RobotService；活动数据写入 rank_activity.cfg，展示锁用于延后会打断动画的结算。

extends Node

const SAVE_PATH := "user://rank_activity.cfg"

const _ZERO_SCORE_TIE_UNIX: int = 253402300799

const SELF_LIKE_TARGET_ID: String = "__rank_player_self__"

signal state_changed(state: int)

signal ranking_changed

signal time_ticked(remaining_sec: int, expired: bool)

signal settle_ready(result: Dictionary)

signal period_opened(period_count: int)

var _data: RankActivityData = RankActivityData.new()
var _in_level: bool = false

var _in_presentation: bool = false
var _new_session: bool = true
var _last_settle_result: Dictionary = {}
var _last_win_advance: int = 0
var _last_win_scored: bool = false
var _last_win_increment: int = 0

var _last_win_base_increment: int = 0

var _last_commit_base: int = 0
var _last_online_advance: int = 0
var _reward_presenting: bool = false
var _reward_at_home: bool = true

var _solo_presenting: bool = false

var _cheat_pin_win_to: int = 0
var _cheat_pin_win_from: int = 0

var _first_frame_tiered: bool = false

var _online_window_sec: int = 0

var _pending_streak_table: Array = []
var _pending_boost_spec: Dictionary = {}
var _pending_x_base_rule: Dictionary = {}

var _last_win_tier_up: bool = false

var _reopen_wins: int = RankActivityConfig.REOPEN_WINS

var _in_rank_win_presentation: bool = false


## 初始化时还原活动存档，接入时钟、游戏重置和云同步，并检查跨启动到期与中断奖励。
func _ready() -> void:
	_load()

	GameState.all_data_reset.connect(_reset)

	DataSyncRegistry.register(self)

	var watch := Timer.new()
	watch.wait_time = 1.0
	watch.autostart = true
	add_child(watch)
	watch.timeout.connect(_on_watch_tick)

	_migrate_legacy_group()

	_reconcile_expiry()

	_reconcile_interrupted_reward()

	if _data.level_failed_pending:
		_log("init: 上次停在失败页被杀 → 连胜中断（原连胜 %d）" % _data.win_streak)
		_break_streak()
		_save()
	_log(
		(
			"init: state=%s period=%d joined=%s collect=%d robot_key=%s end=%d remaining=%ds group=%d"
			% [
				_state_name(_data.state),
				_data.period_count,
				_data.joined,
				_data.collect_total,
				_data.robot_key,
				_data.end_unix,
				get_remaining_sec(),
				_data.group
			]
		)
	)


func get_state() -> int:
	return _data.state


func is_running() -> bool:
	return (
		_data.state == RankActivityData.State.OPEN_NOT_JOINED
		or _data.state == RankActivityData.State.OPEN_JOINED
	)


func is_joined() -> bool:
	return _data.joined


func get_ranking() -> Array:
	if _data.robot_key.is_empty():
		return []

	return RobotService.get_ranking(_data.robot_key, _data.collect_total, _player_unix(), -1, true)


## 从 RobotService 取得当前排行并补齐头像框显示形态；获取排行可能推进本地模拟对手。
func get_rank_infos() -> Array:
	if _data.robot_key.is_empty():
		return []

	var infos: Array[RankInfo] = RobotService.get_rank_list(
		_data.robot_key,
		ProfileService.get_player_info(),
		_data.collect_total,
		_player_unix(),
		[],
		-1,
		true
	)
	infos = _apply_first_frame_form(infos)

	RankOnlineHelper.apply_fallback(infos, _online_window_sec)
	return infos


func mark_robot_active(player_id: String) -> void:
	if _data.robot_key.is_empty() or not player_id.begins_with("robot_"):
		return
	RobotService.mark_robot_active(_data.robot_key, int(player_id.trim_prefix("robot_")))


func is_robot_stalking() -> bool:
	return RobotService.is_stalking(_data.robot_key)


func _apply_first_frame_form(infos: Array[RankInfo]) -> Array[RankInfo]:
	for item in infos:
		var pi: PlayerInfo = item.player_info
		if pi == null or pi.frame == null or pi.frame.id != ProfileCatalog.FIRST_PLACE_FRAME_ID:
			continue

		if not _first_frame_tiered:
			pi.frame.form = 0
		elif pi.is_self():
			pi.frame.form = ProfileService.get_frame_form()
		else:
			pi.frame.form = maxi(0, ProfileCatalog.form_for_wins(pi.frame.acquired_count))
	return infos


func get_player_rank() -> int:
	if _data.robot_key.is_empty():
		return -1

	return RobotService.get_player_rank(
		_data.robot_key, _data.collect_total, _player_unix(), -1, true
	)


func get_rank_for_score(score: int) -> int:
	if _data.robot_key.is_empty():
		return -1
	return RobotService.get_player_rank(_data.robot_key, score, _player_unix(), -1, true)


func get_last_win_advance() -> int:
	return _last_win_advance


func get_last_online_advance() -> int:
	return _last_online_advance


func did_last_win_score() -> bool:
	return _last_win_scored


## 为当前结算准备本地点赞结果；周期序号保证同一次结算不会重复生成互动。
func prepare_rank_like_settlement(with_barrage: bool) -> Dictionary:
	var empty_result: Dictionary = _rank_like_result([], [])
	if (
		not _data.joined
		or _data.rank_like.settlement_serial <= _data.rank_like.resolved_settlement_serial
	):
		return empty_result
	var ranked_robots: Array[Dictionary] = _get_current_rank_like_robots()
	if ranked_robots.is_empty():
		return empty_result
	var skip_player_likes: bool = (
		_data.rank_like.skip_player_like_settlement_serial == _data.rank_like.settlement_serial
	)
	var new_liker_ids: Array[String] = RankLikeLogic.resolve_settlement(
		_data.rank_like, ranked_robots, _rng(), not skip_player_likes
	)
	_data.rank_like.resolved_settlement_serial = _data.rank_like.settlement_serial
	var nicknames_by_id: Dictionary = {}
	for ranked_robot: Dictionary in ranked_robots:
		nicknames_by_id[str(ranked_robot["id"])] = str(ranked_robot["nickname"])
	var barrages: Array[Dictionary] = RankLikeLogic.consume_barrage(
		_data.rank_like, nicknames_by_id, with_barrage, _rng()
	)
	_save()
	return _rank_like_result(new_liker_ids, barrages)


func get_player_received_like_count() -> int:
	return _data.rank_like.player_liker_order.size()


func get_player_self_like_state() -> Dictionary:
	if not _data.joined:
		return {"valid": false}
	return _valid_player_self_like_state()


func toggle_player_self_like() -> Dictionary:
	if not _data.joined:
		return {"valid": false}
	_data.rank_like.player_liked_self = not _data.rank_like.player_liked_self
	_save()
	return _valid_player_self_like_state()


func get_robot_like_state(robot_id: String) -> Dictionary:
	if not _is_current_rank_like_robot(robot_id):
		return {"valid": false}
	return _valid_robot_like_state(robot_id)


func get_rank_like_display_states() -> Dictionary:
	var states_by_target: Dictionary = {}
	if not _data.joined:
		return states_by_target
	states_by_target[SELF_LIKE_TARGET_ID] = _valid_player_self_like_state()
	var current_robots: Array[Dictionary] = _get_current_rank_like_robots()
	for robot: Dictionary in current_robots:
		var robot_id: String = str(robot.get("id", ""))
		if robot_id.is_empty():
			continue
		states_by_target[robot_id] = _valid_robot_like_state(robot_id)
	return states_by_target


## 更新玩家对指定机器人点赞的状态并保存；这是一项本地活动交互。
func toggle_player_like(robot_id: String) -> Dictionary:
	if not _is_current_rank_like_robot(robot_id):
		return {"valid": false}
	if _data.rank_like.player_liked_robot_ids.has(robot_id):
		_data.rank_like.player_liked_robot_ids.erase(robot_id)
	else:
		_data.rank_like.player_liked_robot_ids[robot_id] = true
	_save()
	return _valid_robot_like_state(robot_id)


func get_last_win_increment() -> int:
	return _last_win_increment


func get_last_win_base_increment() -> int:
	return _last_win_base_increment


func consume_progress_encouragement(
	max_reach_rank: int = 3, advance_override: int = -1
) -> Dictionary:
	var rank: int = get_player_rank()

	if (
		rank >= 1
		and rank <= max_reach_rank
		and (_data.best_encouraged_rank == 0 or rank < _data.best_encouraged_rank)
	):
		_data.best_encouraged_rank = rank
		_save()
		return {"kind": "reach", "rank": rank}

	var advance: int = advance_override if advance_override >= 0 else _last_win_advance
	if advance >= 3:
		return {"kind": "climb", "advance": advance}
	return {"kind": "none"}


func _rank_like_result(new_liker_ids: Array[String], barrages: Array[Dictionary]) -> Dictionary:
	return {
		"player_received_like_count": get_player_received_like_count(),
		"new_player_liker_ids": new_liker_ids.duplicate(),
		"barrages": barrages.duplicate(true),
		"settlement_serial": _data.rank_like.settlement_serial,
	}


func _get_current_rank_like_robots() -> Array[Dictionary]:
	var ranked_robots: Array[Dictionary] = []
	var rank_infos: Array = get_rank_infos()
	for rank_info: RankInfo in rank_infos:
		var player_info: PlayerInfo = rank_info.player_info
		if player_info == null or not player_info.is_robot or player_info.player_id.is_empty():
			continue
		(
			ranked_robots
			. append(
				{
					"id": player_info.player_id,
					"nickname": player_info.nickname,
					"rank": rank_info.rank,
				}
			)
		)
	return ranked_robots


func _is_current_rank_like_robot(robot_id: String) -> bool:
	if not _data.joined or robot_id.is_empty():
		return false
	for ranked_robot: Dictionary in _get_current_rank_like_robots():
		if ranked_robot["id"] == robot_id:
			return true
	return false


func _valid_robot_like_state(robot_id: String) -> Dictionary:
	var liked_by_player: bool = _data.rank_like.player_liked_robot_ids.has(robot_id)
	var self_like_count: int = maxi(0, int(_data.rank_like.robot_self_like_counts.get(robot_id, 0)))
	return {
		"valid": true,
		"liked_by_player": liked_by_player,
		"heart_count": self_like_count + (1 if liked_by_player else 0),
	}


func _valid_player_self_like_state() -> Dictionary:
	var liked_by_player: bool = _data.rank_like.player_liked_self
	return {
		"valid": true,
		"liked_by_player": liked_by_player,
		"heart_count": get_player_received_like_count() + (1 if liked_by_player else 0),
	}


func _player_unix() -> int:
	if _data.collect_total <= 0:
		return _ZERO_SCORE_TIE_UNIX
	return _data.player_score_unix if _data.player_score_unix > 0 else _data.start_unix


func get_collect_total() -> int:
	return _data.collect_total


func get_last_seen_online_rank() -> int:
	return _data.last_seen_online_rank


func record_seen_online_rank() -> void:
	if not UniKitManager.is_online():
		return
	if not _data.joined or _data.robot_key.is_empty():
		return
	var rank: int = 0 if _data.collect_total <= 0 else maxi(0, get_player_rank())
	if rank == _data.last_seen_online_rank:
		return
	_data.last_seen_online_rank = rank
	_save()


func get_remaining_sec() -> int:
	return RankActivityPeriod.remaining_sec(_now(), _data.end_unix)


func get_period_count() -> int:
	return _data.period_count


func get_group() -> int:
	return _data.group


func get_pending_reward() -> Dictionary:
	if (
		_data.state == RankActivityData.State.SETTLING
		and _data.settled
		and not _data.reward_claimed
		and RankActivityConfig.has_reward(_data.final_rank)
	):
		if not _last_settle_result.is_empty():
			return _last_settle_result.duplicate()

		return {
			"rank": _data.final_rank,
			"awarded": true,
			"is_first": RankActivityConfig.is_first_place(_data.final_rank),
			"collect_total": _data.collect_total,
			"group": _data.group,
		}
	return {}


func get_pending_end_solo_podium() -> Dictionary:
	if (
		_data.state != RankActivityData.State.SETTLING
		or not _data.settled
		or _data.reward_claimed
		or not RankActivityConfig.is_end_solo_podium_rank(_data.final_rank)
	):
		return {}
	if not _last_settle_result.is_empty():
		return _last_settle_result.duplicate()

	return {
		"rank": _data.final_rank,
		"awarded": false,
		"is_first": false,
		"collect_total": _data.collect_total,
		"group": _data.group,
	}


func begin_end_solo_podium() -> bool:
	if _solo_presenting:
		return false
	if get_pending_end_solo_podium().is_empty():
		return false
	_solo_presenting = true
	return true


func complete_end_solo_podium(at_home: bool) -> void:
	_solo_presenting = false
	if _data.state != RankActivityData.State.SETTLING or not _data.settled or _data.reward_claimed:
		return
	_data.reward_claimed = true
	_data.prev_awarded = true
	_save()
	_log("单人领奖台表现走完（rank=%d，无奖励）→ 折回未开启" % _data.final_rank)
	_fold_to_not_opened()
	if maybe_open(at_home):
		_log("单人台确认 → 下一期立刻开始")
	else:
		_log("单人台确认：state=%s，重开门槛=%d" % [_state_name(_data.state), _reopen_wins])


func has_home_entry() -> bool:
	if is_running():
		return true
	return _data.state == RankActivityData.State.SETTLING and not get_pending_reward().is_empty()


func open_home_entry() -> bool:
	if not has_home_entry():
		return false

	if not UniKitManager.is_online():
		UIManager.show_ui(UiName.RANK_ACTIVITY_OFFLINE)
		await UIManager.await_hidden(UiName.RANK_ACTIVITY_OFFLINE)
		return true
	if _data.state == RankActivityData.State.OPEN_NOT_JOINED:
		var home = UIManager.get_ui(UiName.HOME)
		if home != null and home.has_method("request_rank_open_popup"):
			home.request_rank_open_popup()
	else:
		UIManager.show_ui(UiName.RANK_ACTIVITY_PAGE)
		await UIManager.await_hidden(UiName.RANK_ACTIVITY_PAGE)

		await get_tree().process_frame
		await get_tree().process_frame

		var home = UIManager.get_ui(UiName.HOME)
		if home != null and home.has_method("request_rank_open_popup"):
			home.request_rank_open_popup()
	return true


## 只有未开启状态才评估解锁、上一期领取、重新开放所需胜场和会话条件，通过后创建新一期。
func maybe_open(at_home: bool) -> bool:
	var new_session: bool = _new_session
	_new_session = false
	if _data.state != RankActivityData.State.NOT_OPENED:
		return false
	var level: int = GameState.get_current_level()
	var ok: bool = RankActivityPeriod.should_open(
		_data.period_count,
		level,
		_data.prev_awarded,
		_data.wins_since_close,
		at_home,
		new_session,
		RankActivityConfig.UNLOCK_LEVEL,
		_reopen_wins
	)
	if not ok:
		return false

	return _open_period(RankActivityConfig.APPLIED_GROUP, _first_frame_tiered)


func notify_new_session() -> bool:
	if (
		_data.period_count <= 0
		or _data.state != RankActivityData.State.NOT_OPENED
		or _data.prev_awarded
		or _reopen_wins <= 0
	):
		return false
	_new_session = true
	return true


func set_reopen_wins(wins: int) -> void:
	_reopen_wins = maxi(0, wins)


func begin_rank_win_presentation() -> void:
	_in_rank_win_presentation = true


func end_rank_win_presentation(aborted: bool = false) -> void:
	_in_rank_win_presentation = false
	if (
		aborted
		and _data.state == RankActivityData.State.SETTLING
		and _data.settled
		and get_pending_reward().is_empty()
		and get_pending_end_solo_podium().is_empty()
	):
		notify_settlement_done()
	if (
		_reopen_wins == 0
		and _data.period_count > 0
		and _data.state == RankActivityData.State.NOT_OPENED
	):
		maybe_open(false)


## 把已开放但未参加的活动转为已参加状态，建立玩家可收集计分的资格。
func confirm_participation() -> void:
	if _data.state != RankActivityData.State.OPEN_NOT_JOINED:
		return
	_data.joined = true
	_log("participation confirmed → joined (period #%d)" % _data.period_count)
	_set_state(RankActivityData.State.OPEN_JOINED)


## 记录进入关卡并建立本局收集上下文；到期处理要知道玩家是否仍在一局之中。
func notify_level_start() -> void:
	_in_level = true

	if _data.level_failed_pending:
		_break_streak()
		_data.level_failed_pending = false
		_save()


## 更新本局待结算收集数；局内显示增长并不代表总分立即增长，提交在成功结算时进行。
func set_level_collect(count: int) -> void:
	if _data.state == RankActivityData.State.NOT_OPENED:
		return
	_data.level_cache = maxi(0, count)
	_data.level_cache_active = true
	_save()
	_log(
		(
			"level_collect cached=%d (committed_total=%d, 胜利才计入)"
			% [_data.level_cache, _data.collect_total]
		)
	)


func notify_level_restart() -> void:
	_data.level_cache = 0
	_data.level_cache_active = _data.state != RankActivityData.State.NOT_OPENED
	_break_streak()
	_data.level_failed_pending = false
	_save()


## 处理失败阶段的连胜与收集状态；后续仍需区分复活继续和最终放弃。
func notify_level_failed() -> void:
	if _data.level_failed_pending:
		return
	_data.level_failed_pending = true
	_save()


## 恢复继续本局所需状态，让失败提示之后的复活仍能接上原有收集流程。
func notify_level_revived() -> void:
	if not _data.level_failed_pending:
		return
	_data.level_failed_pending = false
	_save()


func notify_level_fail_abandon() -> void:
	_break_streak()
	_data.level_failed_pending = false
	_save()


## 推进连胜倍率并提交本局收集，计算本次名次变化；若周期已到期待结算，则接续结算。
func notify_level_win() -> void:
	_in_level = false
	_data.level_failed_pending = false
	var st: int = _data.state

	var was_settled: bool = _data.settled

	var rank_before: int = get_player_rank()
	var total_before: int = _data.collect_total

	var settling_pending: bool = st == RankActivityData.State.SETTLING and not was_settled
	_last_win_tier_up = false
	if _data.joined and (st == RankActivityData.State.OPEN_JOINED or settling_pending):
		_advance_streak()
		_commit_level_cache(_data.last_multiplier)
		_log_offline_snapshot(total_before)
	else:
		_clear_level_cache()

	if settling_pending:
		_last_win_advance = maxi(0, rank_before - get_player_rank())
		_last_win_scored = _data.collect_total > total_before
		_last_win_increment = maxi(0, _data.collect_total - total_before)
		_last_win_base_increment = _last_commit_base if _data.collect_total > total_before else 0
		var cur_rank_s: int = get_player_rank()
		if _data.last_online_rank > 0 and cur_rank_s >= 1:
			_last_online_advance = maxi(0, _data.last_online_rank - cur_rank_s)
		elif _data.last_online_rank < 0 and cur_rank_s >= 1:
			_last_online_advance = 1
		else:
			_last_online_advance = 0
		if UniKitManager.is_online():
			_data.last_online_rank = cur_rank_s
			_data.last_seen_online_rank = cur_rank_s
		_record_rank_like_settlement(total_before)
		_save()
		ranking_changed.emit()
		_settle(true)
	elif st == RankActivityData.State.SETTLING:
		_last_win_advance = 0
		_last_win_scored = false
		_last_win_increment = 0
		_last_win_base_increment = 0
		_last_online_advance = 0
	elif st == RankActivityData.State.NOT_OPENED:
		_data.wins_since_close += 1
		_save()
		maybe_open(false)
	else:
		if _cheat_pin_win_to > 0:
			_consume_cheat_pin_win(total_before)
			_record_rank_like_settlement(total_before)
			_save()
			return

		_last_win_advance = maxi(0, rank_before - get_player_rank())
		_last_win_scored = _data.collect_total > total_before
		_last_win_increment = maxi(0, _data.collect_total - total_before)
		_last_win_base_increment = _last_commit_base if _data.collect_total > total_before else 0

		var cur_rank: int = get_player_rank()
		if _data.last_online_rank > 0 and cur_rank >= 1:
			_last_online_advance = maxi(0, _data.last_online_rank - cur_rank)
		elif _data.last_online_rank < 0 and cur_rank >= 1:
			_last_online_advance = 1
		else:
			_last_online_advance = 0

		if UniKitManager.is_online():
			_data.last_online_rank = cur_rank
			_data.last_seen_online_rank = cur_rank
		_record_rank_like_settlement(total_before)
		_save()
		ranking_changed.emit()


## 退出本局时清除未提交收集；活动已进入结算阶段时尝试完成结算。
func notify_level_exit() -> void:
	_in_level = false
	_clear_level_cache()
	if _data.state == RankActivityData.State.SETTLING:
		_settle()
	else:
		_save()


## 为躲猫猫等局外来源直接增加活动分数；只有已参赛且尚未定格结果时才接受，并通知机器人响应。
func add_external_collect(amount: int) -> void:
	if amount <= 0:
		return
	var st: int = _data.state
	var settling_pending: bool = st == RankActivityData.State.SETTLING and not _data.settled
	if not (_data.joined and (st == RankActivityData.State.OPEN_JOINED or settling_pending)):
		_log(
			(
				"add_external_collect: 拒绝 +%d（state=%s joined=%s settled=%s —— 未参与 / 已定格不计分）"
				% [amount, _state_name(st), _data.joined, _data.settled]
			)
		)
		return
	_data.collect_total += amount
	_after_collect_changed(amount)

	_save()

	ranking_changed.emit()
	_log(
		(
			"add_external_collect: +%d → collect_total=%d, 上报 robot, 当前名次=%d"
			% [amount, _data.collect_total, get_player_rank()]
		)
	)


## 标记局外演出进行中，延后可能打断当前奖励飞行的结算。
func begin_external_presentation() -> void:
	_in_presentation = true


## 释放局外演出标记并再次尝试结算，补上演出期间推迟的到期处理。
func end_external_presentation() -> void:
	_in_presentation = false
	_maybe_run_settle()


func set_first_frame_tiered(enabled: bool) -> void:
	_first_frame_tiered = enabled


func set_online_window_sec(sec: int) -> void:
	_online_window_sec = maxi(0, sec)


func get_online_window_sec() -> int:
	return _online_window_sec


## 保存下一期使用的连胜与机器人响应配置；进行中的活动使用已落盘的周期配置。
func set_streak_rule(
	streak_table: Array, boost_spec: Dictionary, x_base_rule: Dictionary = {}
) -> void:
	_pending_streak_table = streak_table.duplicate()
	_pending_boost_spec = boost_spec.duplicate(true)
	_pending_x_base_rule = x_base_rule.duplicate(true)


func is_streak_enabled() -> bool:
	return not _data.streak_table.is_empty()


func get_streak_table() -> Array:
	return _data.streak_table.duplicate()


func get_win_streak() -> int:
	return _data.win_streak


func get_next_multiplier() -> int:
	return _data.multiplier_for(_data.win_streak + 1)


func get_last_win_multiplier() -> int:
	return _data.last_multiplier


func get_prev_win_multiplier() -> int:
	return _data.prev_multiplier


func did_last_win_tier_up() -> bool:
	return _last_win_tier_up


func _advance_streak() -> void:
	var prev: int = _data.last_multiplier
	_data.win_streak += 1
	var mult: int = _data.multiplier_for(_data.win_streak)
	_data.prev_multiplier = prev
	_data.last_multiplier = mult
	_last_win_tier_up = is_streak_enabled() and prev > 0 and mult > prev
	if is_streak_enabled():
		_log(
			(
				"streak: 第 %d 场连胜 → ×%d（上一局 ×%d，升档=%s）"
				% [_data.win_streak, mult, prev, _last_win_tier_up]
			)
		)


func _break_streak() -> void:
	if _data.win_streak > 0 and is_streak_enabled():
		_log("streak: 中断（原连胜 %d 场）" % _data.win_streak)
	_data.win_streak = 0


func on_home_shown(allow_end_solo_podium: bool = false) -> void:
	_maybe_run_settle()

	if (
		_data.state == RankActivityData.State.SETTLING
		and _data.settled
		and get_pending_reward().is_empty()
	):
		var hold_for_solo: bool = (
			allow_end_solo_podium and not get_pending_end_solo_podium().is_empty()
		)
		if not hold_for_solo:
			notify_settlement_done()
	maybe_open(true)


func is_open_not_joined() -> bool:
	return _data.state == RankActivityData.State.OPEN_NOT_JOINED


## 只领取已定格且尚未领取的结果；先记录领取状态再展示奖励，避免重复进入页面重复发奖。
func claim_reward(at_home: bool = true) -> void:
	if _reward_presenting:
		return
	if _data.state != RankActivityData.State.SETTLING or not _data.settled or _data.reward_claimed:
		return
	_reward_at_home = at_home
	var items: Array = RankActivityConfig.reward_items(_data.final_rank, _rng())
	if items.is_empty():
		_data.reward_claimed = true
		_fold_to_not_opened()
		return
	_reward_presenting = true

	var uid: int = AwardManager.dispatch(
		items,
		AwardManager.DisplayType.RANK_GIFT,
		Tracker.PropSource.CHALLENGE_GET_DLG,
		Tracker.PropSource.CHALLENGE_REWARD_GET_DLG
	)

	_data.reward_claimed = true
	_save()

	var top3: Array = []
	for info in get_rank_infos().slice(0, 3):
		if info != null:
			top3.append(info.player_info)

	var place: int = _data.final_rank
	var win_count: int = _place_win_count_after_claim(place)
	AwardManager.show_award(uid, {"top3_infos": top3, "place": place, "win_count": win_count})
	AwardManager.continue_when_award_end(uid, _on_reward_award_end)
	_log(
		"claim_reward: rank=%d 派 %d 项(RANK_GIFT)，等领奖表现走完落账 + 折回" % [_data.final_rank, items.size()]
	)


func _place_win_count_after_claim(place: int) -> int:
	match place:
		1:
			return maxi(0, ProfileService.get_frame_count(ProfileCatalog.FIRST_PLACE_FRAME_ID)) + 1
		2:
			_data.place2_wins += 1
			_save()
			return _data.place2_wins
		3:
			_data.place3_wins += 1
			_save()
			return _data.place3_wins
		_:
			return 0


func _on_reward_award_end(_uid: int = 0) -> void:
	_reward_presenting = false

	if _data.state != RankActivityData.State.SETTLING:
		return
	_fold_to_not_opened()

	if maybe_open(_reward_at_home):
		_log("领奖结束 → 下一期开始")
	else:
		_log("领奖结束：state=%s，重开门槛=%d" % [_state_name(_data.state), _reopen_wins])


func notify_settlement_done() -> void:
	if _data.state != RankActivityData.State.SETTLING or not _data.settled:
		return
	if RankActivityConfig.has_reward(_data.final_rank):
		return
	_log("settlement_done（无奖 rank=%d）→ 折回未开启" % _data.final_rank)
	_data.reward_claimed = true
	_fold_to_not_opened()


## 初始化新一期状态与规则快照，创建对应机器人池并保存；后续查询均使用该池。
func _open_period(group: int, tiered: bool = false) -> bool:
	var cfg: RobotConfig = RankActivityConfig.build_robot_config(_pending_x_base_rule)
	var now: int = _now()
	var end: int = RankActivityPeriod.compute_end(now, RankActivityConfig.PERIOD_DURATION_SEC)

	var open_period: int = _data.period_count + 1
	var badge_table: Array = []
	if tiered:
		var tz_bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		var period_index: int = RankActivityPeriod.global_period_index(
			now, tz_bias_sec, RankActivityConfig.GLOBAL_T0_LOCAL_DAY
		)
		badge_table = RankActivityConfig.build_first_frame_badge_table(period_index + 1, true)
	var nickname_source: Dictionary = RankActivityConfig.build_nickname_source()
	var key: String = _create_robot_pool(cfg, open_period, end, badge_table, nickname_source)
	if key.is_empty():
		_log("open period aborted: robot pool creation failed")
		return false

	_data.group = group
	_data.start_unix = now
	_data.end_unix = end
	_data.robot_key = key
	_data.joined = false
	_data.collect_total = 0
	_data.player_score_unix = 0
	_data.settled = false
	_data.final_rank = 0
	_data.reward_claimed = false
	_data.reset_rank_like_period()
	_data.wins_since_close = 0
	_data.level_cache = 0
	_data.level_cache_active = false
	_data.best_encouraged_rank = 0
	_data.last_online_rank = -1
	_data.last_seen_online_rank = -1

	_data.streak_table = _pending_streak_table.duplicate()
	_data.boost_spec = _pending_boost_spec.duplicate(true)
	_data.win_streak = 0
	_data.last_multiplier = 0
	_data.prev_multiplier = 0
	_data.level_failed_pending = false
	_last_win_tier_up = false
	_data.period_count += 1
	_last_settle_result = {}
	_solo_presenting = false
	_log(
		(
			"open period #%d: group=%d robot_key=%s end=%d(remaining=%ds) prev_score=%d prev_rank=%d robots=%d"
			% [
				_data.period_count,
				group,
				key,
				end,
				end - now,
				_data.prev_score,
				_data.prev_rank,
				cfg.robot_count
			]
		)
	)
	var alpha: float = RobotScoreGen.alpha_for_rank(_data.prev_rank, cfg)
	_log(
		(
			"X_base=%d = max(%d, min(S_prev %d × (1%+.2f), 天花板 %d×k%d=%d))  α=%+.2f(上期名次 %d)  k=%d"
			% [
				RobotService.get_x_base(key),
				cfg.base_floor,
				_data.prev_score,
				alpha,
				cfg.ceiling / cfg.ceiling_mult,
				cfg.ceiling_mult,
				cfg.ceiling,
				alpha,
				_data.prev_rank,
				cfg.ceiling_mult
			]
		)
	)
	_set_state(RankActivityData.State.OPEN_NOT_JOINED)
	period_opened.emit(_data.period_count)

	UIManager.warm_pool_async(UiName.RANK_ACTIVITY_CHANGE)

	Tracker.track_rank_start(_data.period_count)

	return true


func _create_robot_pool(
	config: RobotConfig, open_period: int, end: int, badge_table: Array, nickname_source: Dictionary
) -> String:
	return RobotService.create_pool(
		config,
		_data.prev_score,
		_data.prev_rank,
		ProfileService.get_avatar_ids(),
		ProfileService.get_frame_ids(),
		ProfileCatalog.FIRST_PLACE_FRAME_ID,
		nickname_source.pool,
		open_period,
		end,
		badge_table,
		nickname_source.buckets,
		[ProfileService.get_nickname()]
	)


## 冻结到期时的最终名次并计算奖励资格；原有离线分支直接收束本期，不产生在线结算奖励。
func _settle(defer_fold: bool = false) -> void:
	if _data.settled:
		return

	if not UniKitManager.is_online():
		var dbg_rank: int = 0
		if _data.joined and not _data.robot_key.is_empty():
			dbg_rank = RobotService.get_player_rank(
				_data.robot_key, _data.collect_total, _player_unix(), _data.end_unix
			)
		var dbg_ranking: Array = get_ranking()
		var dbg_top_scores: Array[String] = []
		for i: int in range(mini(50, dbg_ranking.size())):
			dbg_top_scores.append(str(int(dbg_ranking[i].get("score", 0))))
		var dbg_frame_level: int = maxi(
			0, ProfileService.get_frame_count(ProfileCatalog.FIRST_PLACE_FRAME_ID)
		)
		_log(
			(
				"_settle offline 包装(不发送) period=%d src=%s rank=%d collect=%d nick=%s avatar=%s frame=%s frame_lv=%d top=[%s]"
				% [
					_data.period_count,
					Tracker.get_current_source(),
					dbg_rank,
					_data.collect_total,
					ProfileService.get_nickname(),
					str(ProfileService.get_avatar_id()),
					str(ProfileService.get_frame_id()),
					dbg_frame_level,
					",".join(dbg_top_scores),
				]
			)
		)
		_log("_settle: offline → 跳过分支(奖真丢弃 + fold 到 NOT_OPENED)")
		_fold_to_not_opened()
		return
	var rank: int = 0
	var awarded: bool = false

	if _data.joined and not _data.robot_key.is_empty():
		rank = RobotService.get_player_rank(
			_data.robot_key, _data.collect_total, _player_unix(), _data.end_unix
		)
		awarded = RankActivityConfig.has_reward(rank)

	_data.final_rank = rank
	_data.settled = true

	_data.prev_score = _data.collect_total
	_data.prev_rank = rank
	_data.prev_awarded = awarded

	_save()

	var ranking: Array = get_ranking()
	var top_scores: Array[String] = []
	for i: int in range(mini(50, ranking.size())):
		top_scores.append(str(int(ranking[i].get("score", 0))))
	var frame_level: int = maxi(
		0, ProfileService.get_frame_count(ProfileCatalog.FIRST_PLACE_FRAME_ID)
	)
	(
		Tracker
		. track_rank_data(
			_data.period_count,
			Tracker.get_current_source(),
			rank,
			_data.collect_total,
			ProfileService.get_nickname(),
			ProfileService.get_avatar_id(),
			ProfileService.get_frame_id(),
			frame_level,
			",".join(top_scores),
		)
	)

	_last_settle_result = {
		"rank": rank,
		"awarded": awarded,
		"is_first": RankActivityConfig.is_first_place(rank),
		"collect_total": _data.collect_total,
		"group": _data.group,
	}
	_log(
		(
			"settle: 定格名次=%d awarded=%s collect_total=%d group=%d（快照 prev_score/rank/awarded 已存，待 UI 走领奖表现）"
			% [rank, awarded, _data.collect_total, _data.group]
		)
	)
	settle_ready.emit(_last_settle_result.duplicate())

	if not awarded:
		if RankActivityConfig.is_end_solo_podium_rank(rank):
			_log("settle 无奖（rank=%d 属单人台档）→ 留榜单等表现，由集成侧 complete/notify 折回" % rank)
		elif defer_fold or (_reopen_wins == 0 and _in_rank_win_presentation):
			_log("settle 无奖（关内情况1·defer）→ 留榜单等 change 页展示，后 notify_settlement_done 折回")
		else:
			_log("settle 无奖 → 直接折回未开启（无待结算表现，进入空白期）")
			_fold_to_not_opened()
	else:
		state_changed.emit(_data.state)


## 只有满足结算阶段且没有局内/演出阻塞时才执行真正结算，集中控制延后触发。
func _maybe_run_settle() -> void:
	if (
		_data.state == RankActivityData.State.SETTLING
		and not _data.settled
		and not _in_level
		and not _in_presentation
	):
		_settle()


## 结束当前周期并归档所需历史，回到可再次评估开放条件的状态。
func _fold_to_not_opened() -> void:
	if not _data.robot_key.is_empty():
		RobotService.discard_pool(_data.robot_key)
		_data.robot_key = ""
	_data.reset_rank_like_period()
	_data.wins_since_close = 0
	_data.level_cache = 0
	_data.level_cache_active = false
	_set_state(RankActivityData.State.NOT_OPENED)

	if _reopen_wins == 0 and not _in_rank_win_presentation:
		maybe_open(false)


## 将局内收集按倍率转为总分并清空缓存，再通知对手服务；倍率只在提交处应用一次。
func _commit_level_cache(multiplier: int = 1) -> void:
	_last_commit_base = 0
	if not _data.level_cache_active:
		return
	_last_commit_base = _data.level_cache
	var committed: int = _data.level_cache * maxi(1, multiplier)
	_data.collect_total += committed
	if not _data.boost_spec.is_empty() and committed > 0:
		var mode: String = (
			"陪伴态(只走陪伴追赶)" if RobotService.is_stalking(_data.robot_key) else "非陪伴态(先陪伴判定,再一次性加成)"
		)
		_log(
			(
				"机器人响应: 连胜第%d局 ×%d  G=基础%d×%d=%d  玩家分→%d  %s  boost_spec=%s"
				% [
					_data.win_streak,
					maxi(1, multiplier),
					_data.level_cache,
					maxi(1, multiplier),
					committed,
					_data.collect_total,
					mode,
					str(_data.boost_spec)
				]
			)
		)
	_data.level_cache = 0
	_data.level_cache_active = false
	_after_collect_changed(committed, _data.boost_spec)
	_log(
		(
			"commit collect: +%d (×%d) → collect_total=%d, 上报 robot, 当前名次=%d"
			% [committed, maxi(1, multiplier), _data.collect_total, get_player_rank()]
		)
	)


## 总分改变后的统一入口，更新机器人追赶或增分响应，供局内与局外收集共用。
func _after_collect_changed(delta: int, boost_spec: Dictionary = {}) -> void:
	if delta > 0:
		_data.player_score_unix = _now()
	if _data.robot_key.is_empty():
		return
	var stalk_extra: float = float(delta) * float(boost_spec.get("k", 0.0)) if delta > 0 else 0.0
	RobotService.on_player_score(_data.robot_key, _data.collect_total, _player_unix(), stalk_extra)
	if delta > 0 and not boost_spec.is_empty():
		RobotService.apply_player_boost(
			_data.robot_key, _data.collect_total, _player_unix(), delta, boost_spec, true
		)


func _record_rank_like_settlement(total_before: int) -> void:
	if not _last_win_scored:
		return
	_data.rank_like.settlement_serial += 1
	var became_ranked: bool = total_before == 0 and _data.collect_total > 0
	if became_ranked:
		_data.rank_like.skip_player_like_settlement_serial = _data.rank_like.settlement_serial


func _clear_level_cache() -> void:
	_data.level_cache = 0
	_data.level_cache_active = false


func _log_offline_snapshot(total_before: int) -> void:
	if UniKitManager.is_online():
		return
	_log(
		(
			"offline 快照(胜利提交后): 本局+%d → collect_total=%d 名次=%d/%d"
			% [
				maxi(0, _data.collect_total - total_before),
				_data.collect_total,
				get_player_rank(),
				get_ranking().size(),
			]
		)
	)


func _on_watch_tick() -> void:
	var st: int = _data.state
	if st != RankActivityData.State.OPEN_NOT_JOINED and st != RankActivityData.State.OPEN_JOINED:
		return
	var now: int = _now()
	if RankActivityPeriod.is_expired(now, _data.end_unix):
		var defer_why: String = (
			"（关内，延后到打完当把）" if _in_level else ("（表现中，延后到表现结束）" if _in_presentation else "（非关内，当场结算）")
		)
		_log("倒计时归零（period #%d）→ 转待结算%s" % [_data.period_count, defer_why])
		_set_state(RankActivityData.State.SETTLING)
		time_ticked.emit(0, true)
		_maybe_run_settle()
	else:
		time_ticked.emit(RankActivityPeriod.remaining_sec(now, _data.end_unix), false)


func _migrate_legacy_group() -> void:
	var g: int = _data.group
	if g <= 0 or g == RankActivityConfig.APPLIED_GROUP:
		return
	_log(
		(
			"老档迁移：历史组%d(state=%s) → 清当期数据 + 直接开固化组%d"
			% [g, _state_name(_data.state), RankActivityConfig.APPLIED_GROUP]
		)
	)
	if not _data.robot_key.is_empty():
		RobotService.discard_pool(_data.robot_key)
		_data.robot_key = ""
	_data.state = RankActivityData.State.NOT_OPENED
	_save()

	_open_period_migrated.call_deferred(RankActivityConfig.APPLIED_GROUP)


func _open_period_migrated(group: int) -> void:
	_open_period(group, _first_frame_tiered)


func _reconcile_expiry() -> void:
	var st: int = _data.state
	if (
		(st == RankActivityData.State.OPEN_NOT_JOINED or st == RankActivityData.State.OPEN_JOINED)
		and RankActivityPeriod.is_expired(_now(), _data.end_unix)
	):
		_log("冷启对账：period #%d 离线期间已到期 → 转待结算" % _data.period_count)
		_data.state = RankActivityData.State.SETTLING
		_save()
	_maybe_run_settle()


## 启动时处理上次奖励展示被中断留下的状态，避免卡在领奖中或重复展示未收尾流程。
func _reconcile_interrupted_reward() -> void:
	if _data.state == RankActivityData.State.SETTLING and _data.settled and _data.reward_claimed:
		_log("冷启对账②：奖已 dispatch 但发奖表现被打断 → 折回未开启（奖由 AwardManager sweep 补发，不重发）")
		_fold_to_not_opened()


func _set_state(s: int) -> void:
	var prev: int = _data.state
	_data.state = s
	_save()
	if prev != s:
		_log("state: %s → %s" % [_state_name(prev), _state_name(s)])
	state_changed.emit(s)


func _reset() -> void:
	_log("reset：清档（all_data_reset）→ 回首期前")
	if not _data.robot_key.is_empty():
		RobotService.discard_pool(_data.robot_key)
	_data = RankActivityData.new()
	_last_settle_result = {}
	_solo_presenting = false
	_in_rank_win_presentation = false
	_save()
	state_changed.emit(_data.state)


func cheat_open() -> void:
	if _data.state != RankActivityData.State.NOT_OPENED:
		return
	_open_period(RankActivityConfig.APPLIED_GROUP, _first_frame_tiered)


func cheat_reset_rank_likes() -> void:
	_data.reset_rank_like_period()
	_save()
	ranking_changed.emit()


func _log(msg: String) -> void:
	print("[RankActivity] " + msg)


func _state_name(s: int) -> String:
	match s:
		RankActivityData.State.NOT_OPENED:
			return "NOT_OPENED"
		RankActivityData.State.OPEN_NOT_JOINED:
			return "OPEN_NOT_JOINED"
		RankActivityData.State.OPEN_JOINED:
			return "OPEN_JOINED"
		RankActivityData.State.SETTLING:
			return "SETTLING"
		_:
			return str(s)


func cheat_end_now() -> void:
	if not is_running():
		return
	_data.end_unix = _now() - 1
	_set_state(RankActivityData.State.SETTLING)
	_maybe_run_settle()


func cheat_set_score(value: int) -> void:
	_data.collect_total = maxi(0, value)
	_data.player_score_unix = _now()
	if not _data.robot_key.is_empty():
		RobotService.on_player_score(_data.robot_key, _data.collect_total, _player_unix())
	_save()
	ranking_changed.emit()
	_log("cheat_set_score: collect_total=%d 名次=%d" % [_data.collect_total, get_player_rank()])


func cheat_set_streak(streak: int, refreeze: bool = false) -> void:
	if refreeze:
		_data.streak_table = _pending_streak_table.duplicate()
		_data.boost_spec = _pending_boost_spec.duplicate(true)
	_data.win_streak = maxi(0, streak)
	_data.last_multiplier = _data.multiplier_for(_data.win_streak) if _data.win_streak > 0 else 0
	_data.prev_multiplier = _data.last_multiplier
	_data.level_failed_pending = false
	_save()
	ranking_changed.emit()
	_log(
		(
			"cheat_set_streak: 连胜=%d 下一局 ×%d 档位表=%s"
			% [_data.win_streak, get_next_multiplier(), _data.streak_table]
		)
	)


func _cheat_calc_score_for_rank(target_rank: int, settle_view: bool) -> Dictionary:
	var now_arg: int = _data.end_unix if settle_view else -1

	var raw: Array = RobotService.get_ranking(
		_data.robot_key, _data.collect_total, _player_unix(), now_arg, not settle_view
	)
	var robots: Array = []
	for e in raw:
		if not bool(e.get("is_player", false)):
			robots.append({"score": int(e.get("score", 0)), "ts": int(e.get("ts_unix", 0))})
	var m: int = robots.size()
	var target: int = clampi(target_rank, 1, m + 1)
	var pscore: int
	var punix: int = _now()
	if m == 0 or target == 1:
		pscore = (robots[0]["score"] + 1) if m > 0 else 1
	elif target > m:
		pscore = 0
	else:
		var lo: Dictionary = robots[target - 2]
		var hi: Dictionary = robots[target - 1]
		if int(lo["score"]) - int(hi["score"]) >= 2:
			pscore = int(hi["score"]) + 1
		else:
			pscore = int(hi["score"])
			if int(lo["score"]) == int(hi["score"]):
				if int(hi["ts"]) - int(lo["ts"]) >= 2:
					punix = int((int(lo["ts"]) + int(hi["ts"])) / 2.0)
				else:
					punix = int(hi["ts"]) - 1
			else:
				punix = int(hi["ts"]) - 1
	return {"score": maxi(0, pscore), "unix": maxi(1, punix), "target": target, "robots": m}


func cheat_set_rank(target_rank: int) -> void:
	if _data.robot_key.is_empty():
		_log("cheat_set_rank: 无活动榜单(先 rank_open)")
		return

	if not _data.joined:
		confirm_participation()
	var calc: Dictionary = _cheat_calc_score_for_rank(target_rank, true)
	_data.collect_total = int(calc["score"])
	_data.player_score_unix = int(calc["unix"])
	_save()
	ranking_changed.emit()

	var actual: int = RobotService.get_player_rank(
		_data.robot_key, _data.collect_total, _player_unix(), _data.end_unix, false
	)
	_log(
		(
			"cheat_set_rank: 目标=%d 实际=%d (collect_total=%d unix=%d, 榜单机器人=%d)"
			% [
				int(calc["target"]),
				actual,
				_data.collect_total,
				_data.player_score_unix,
				int(calc["robots"])
			]
		)
	)
	if actual != int(calc["target"]):
		_log("cheat_set_rank: ⚠️ 未精确命中(同分 ts 无空隙边界)，已尽量逼近")


func cheat_spread_robot_scores(gap: int, top: int = 0) -> Dictionary:
	if _data.robot_key.is_empty():
		_log("cheat_spread_robot_scores: 无活动榜单(先 rank_open)")
		return {"ok": false}
	var r: Dictionary = RobotService.cheat_spread_scores(_data.robot_key, top, gap)
	if not bool(r.get("ok", false)):
		return r
	ranking_changed.emit()
	r["player_rank"] = get_player_rank()
	_log(
		(
			"cheat_spread_robot_scores: gap=%d top=%d x_base=%d → 前10分数=%s 玩家名次=%d"
			% [
				int(r.get("gap", 0)),
				int(r.get("top", 0)),
				int(r.get("x_base", 0)),
				str(r.get("scores", [])),
				int(r["player_rank"])
			]
		)
	)
	return r


func cheat_pin_next_win(to_rank: int, from_rank: int) -> void:
	if _data.robot_key.is_empty():
		_log("cheat_pin_next_win: 无活动榜单(先 rank_open)")
		return
	if not _data.joined:
		confirm_participation()
	var to_r: int = maxi(1, to_rank)
	var from_r: int = maxi(to_r + 1, from_rank)

	var calc: Dictionary = _cheat_calc_score_for_rank(from_r, false)
	_data.collect_total = int(calc["score"])
	_data.player_score_unix = int(calc["unix"])
	_cheat_pin_win_to = to_r
	_cheat_pin_win_from = from_r
	_save()
	ranking_changed.emit()
	_log(
		(
			"cheat_pin_next_win: 起点=%d(实际=%d) → 通关后钉到=%d (collect_total=%d)"
			% [from_r, get_player_rank(), to_r, _data.collect_total]
		)
	)


func _consume_cheat_pin_win(total_before: int) -> void:
	var to_r: int = _cheat_pin_win_to
	var from_r: int = _cheat_pin_win_from
	_cheat_pin_win_to = 0
	_cheat_pin_win_from = 0
	var real_increment: int = maxi(0, _data.collect_total - total_before)

	var from_score: int = int(_cheat_calc_score_for_rank(from_r, false)["score"])
	var calc: Dictionary = _cheat_calc_score_for_rank(to_r, false)
	var new_total: int = int(calc["score"])
	_data.collect_total = new_total
	_data.player_score_unix = int(calc["unix"])
	_last_win_increment = maxi(0, new_total - from_score)
	_last_win_base_increment = _last_win_increment
	_last_win_advance = maxi(0, from_r - to_r)

	_last_win_scored = _last_win_increment > 0
	_save()
	ranking_changed.emit()
	_log(
		(
			"cheat_pin_next_win 生效: %d → %d (advance=%d 实际名次=%d collect_total=%d 伪造增量=%d 真实增量=%d)"
			% [
				from_r,
				to_r,
				_last_win_advance,
				get_player_rank(),
				_data.collect_total,
				_last_win_increment,
				real_increment
			]
		)
	)
	if not _last_win_scored:
		_log(
			(
				"  ⚠️ 起点第%d名与终点第%d名同分(均 %d)，伪造增量为 0 → 名次钉子已生效但本局不弹结算页。先跑 rank_spread 岔开机器人分数再钉。"
				% [from_r, to_r, new_total]
			)
		)

	var probe_old: int = maxi(0, _data.collect_total - _last_win_increment)
	var probe_rank: int = get_rank_for_score(probe_old)
	var probe_adv: int = maxi(0, probe_rank - to_r) if probe_rank >= 1 else 0
	_log(
		(
			"  ↳ 结算页反推预判: old_score=%d(=%d-%d) → 旧名次=%d → 页面实际 advance=%d%s"
			% [
				probe_old,
				_data.collect_total,
				_last_win_increment,
				probe_rank,
				probe_adv,
				(
					""
					if probe_adv == _last_win_advance
					else (
						"  ⚠️ 与钉子 advance=%d 不一致，页面会按 %d→%d 演"
						% [_last_win_advance, probe_rank, to_r]
					)
				)
			]
		)
	)


func cheat_dump_robots(online_window_sec: int = 0) -> void:
	if _data.robot_key.is_empty():
		_log("cheat_dump_robots: 无活动榜单(robot_key 空，先 rank_open 开活动)")
		return
	RobotService.debug_dump(
		_data.robot_key, _data.collect_total, _player_unix(), -1, online_window_sec
	)


func cheat_end_in(sec: int = 10) -> void:
	if not is_running():
		return
	_data.end_unix = _now() + maxi(1, sec)
	_save()
	time_ticked.emit(get_remaining_sec(), false)
	_log("cheat_end_in: end→now+%ds, remaining=%d" % [sec, get_remaining_sec()])


func cloud_save_id() -> String:
	return "rank"


func export_cloud_data() -> Dictionary:
	return {"period_count": _data.period_count}


## 按合并上下文更新可同步的周期计数；当前机器人池和局内演出状态不是整份从云端覆盖。
func merge_cloud_data(cloud_data: Dictionary, ctx: MergeContext) -> void:
	if not ctx.use_cloud:
		return
	_data.period_count = int(cloud_data.get("period_count", 0))
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	var d: Dictionary = _data.to_dict()
	for k: String in d:
		cfg.set_value("rank_activity", k, d[k])
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var d: Dictionary = {}
	for k: String in cfg.get_section_keys("rank_activity"):
		d[k] = cfg.get_value("rank_activity", k)
	if not d.is_empty():
		_data = RankActivityData.from_dict(d)


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng
