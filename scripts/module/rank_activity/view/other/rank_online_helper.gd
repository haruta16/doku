## 排行榜在线展示的规则适配；读取实验窗口，用下一次得分时间决定模拟对手是否显示在线。

class_name RankOnlineHelper
extends RefCounted

const FALLBACK_SPAN: int = 2


static func window_sec_from_ab() -> int:
	return ABTestManager.rank_state.window_sec()


static func is_online(next_score_sec: int, window_sec_value: int) -> bool:
	return next_score_sec >= 0 and next_score_sec <= window_sec_value


static func should_show(player_info: PlayerInfo, window_sec_value: int) -> bool:
	return window_sec_value > 0 and player_info != null


static func apply_fallback(infos: Array, window: int) -> void:
	if window <= 0 or RankActivityManager.is_robot_stalking():
		return
	var self_index: int = -1
	for i in range(infos.size()):
		if infos[i].is_self():
			self_index = i
			break
	if self_index < 0 or infos[self_index].score <= 0:
		return

	var neighbors: Array[int] = []
	for step in range(1, FALLBACK_SPAN + 1):
		for index in [self_index - step, self_index + step]:
			if index < 0 or index >= infos.size():
				continue
			var info: RankInfo = infos[index]
			if info.player_info != null and info.player_info.is_robot:
				neighbors.append(index)
	for index in neighbors:
		if is_online(infos[index].next_score_sec, window):
			return
	if neighbors.is_empty():
		return
	var target: RankInfo = infos[neighbors[0]]

	target.next_score_sec = 0
	target.idle_sec = 0
	if target.player_info != null:
		RankActivityManager.mark_robot_active(target.player_info.player_id)
