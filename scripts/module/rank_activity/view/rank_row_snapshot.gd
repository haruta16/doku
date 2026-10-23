## 排行榜行的展示快照；将排名资料转成可比较的字段，并携带命名空间和修订号供列表判断是否重绑。

class_name RankRowSnapshot
extends RefCounted


static func from_info(info: RankInfo, window_sec: int, period_namespace: String) -> Dictionary:
	var player: Dictionary = info.player_info.to_dict()
	var frame: Dictionary = player.frame
	frame.make_read_only()
	player.make_read_only()
	var result: Dictionary = {
		"key": "%s/%s" % [period_namespace, info.player_info.player_id],
		"player": player,
		"rank": info.rank,
		"score": info.score,
		"award_id": info.award_id,
		"shown_rank": 0 if info.is_self() and info.score <= 0 else info.rank,
		"is_self": info.is_self(),
		"online_shown": RankOnlineHelper.should_show(info.player_info, window_sec),
		"online": RankOnlineHelper.is_online(info.next_score_sec, window_sec),
		"idle_sec": info.idle_sec,
		"revision": 0,
	}
	result.make_read_only()
	return result


static func with_player(snapshot: Dictionary, player: PlayerInfo) -> Dictionary:
	var result: Dictionary = snapshot.duplicate()
	var identity: Dictionary = player.to_dict()
	if snapshot.player == identity:
		return snapshot
	var frame: Dictionary = identity.frame
	frame.make_read_only()
	identity.make_read_only()
	result.player = identity
	result.revision = int(snapshot.revision) + 1
	result.make_read_only()
	return result


## 比较展示数据是否真的变化；相同内容可沿用修订号，减少虚拟列表不必要的重新绑定。
static func same_payload(left: Dictionary, right: Dictionary) -> bool:
	var left_payload: Dictionary = left.duplicate()
	var right_payload: Dictionary = right.duplicate()
	left_payload.erase("revision")
	right_payload.erase("revision")
	return left_payload == right_payload


## 生成带指定修订号的快照，保持数据内容与列表更新版本的职责分开。
static func with_revision(snapshot: Dictionary, revision: int) -> Dictionary:
	var result: Dictionary = snapshot.duplicate()
	result.revision = revision
	result.make_read_only()
	return result


## 把快照一次性应用到排行行，避免不同字段来自不同时间的排行查询。
static func apply(cell: RankCell, snapshot: Dictionary, highlighted: bool = false) -> void:
	cell.set_player(PlayerInfo.from_dict(snapshot.player))
	cell.set_show_chest(true)
	cell.apply_score_icon()
	cell.set_entry(snapshot.shown_rank, highlighted, snapshot.player.nickname, snapshot.score)
	cell.set_meta(&"is_self", snapshot.is_self)
	cell.set_online(snapshot.online_shown, snapshot.online, snapshot.idle_sec, snapshot.is_self)
	cell.set_like_display(false)
