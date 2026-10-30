## 排行榜的一行数据；组合玩家身份、名次、分数和下一次得分/空闲时间，供多种界面复用。

class_name RankInfo
extends RefCounted

var player_info: PlayerInfo = null
var rank: int = 0
var score: int = 0
var award_id: int = 0

var next_score_sec: int = -1

var idle_sec: int = 0


func is_self() -> bool:
	return player_info != null and player_info.is_self()
