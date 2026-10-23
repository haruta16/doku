## 排行活动的可存档状态；含参与阶段、得分缓存、连胜、周期、奖励领取及点赞数据。

class_name RankActivityData
extends RefCounted

enum State {
	NOT_OPENED = 0,
	OPEN_NOT_JOINED = 1,
	OPEN_JOINED = 2,
	SETTLING = 3,
}

var period_count: int = 0
var prev_score: int = 0
var prev_rank: int = 0
var prev_awarded: bool = false

var state: int = State.NOT_OPENED
var group: int = 0
var start_unix: int = 0
var end_unix: int = 0
var robot_key: String = ""
var joined: bool = false
var collect_total: int = 0
var player_score_unix: int = 0
var settled: bool = false
var final_rank: int = 0
var reward_claimed: bool = false

var rank_like: RankLikePeriodData = RankLikePeriodData.new()

var wins_since_close: int = 0

var level_cache: int = 0
var level_cache_active: bool = false

var best_encouraged_rank: int = 0

var last_online_rank: int = -1

var last_seen_online_rank: int = -1

var streak_table: Array = []

var boost_spec: Dictionary = {}

var win_streak: int = 0

var last_multiplier: int = 0
var prev_multiplier: int = 0

var level_failed_pending: bool = false

var place2_wins: int = 0
var place3_wins: int = 0


func reset_rank_like_period() -> void:
	rank_like.reset()


## 将当前模型转换为字典，供保存或传输层使用；本方法本身不写磁盘。
func to_dict() -> Dictionary:
	return {
		"period_count": period_count,
		"prev_score": prev_score,
		"prev_rank": prev_rank,
		"prev_awarded": prev_awarded,
		"state": state,
		"group": group,
		"start_unix": start_unix,
		"end_unix": end_unix,
		"robot_key": robot_key,
		"joined": joined,
		"collect_total": collect_total,
		"player_score_unix": player_score_unix,
		"settled": settled,
		"final_rank": final_rank,
		"reward_claimed": reward_claimed,
		"rank_like": rank_like.to_dict(),
		"wins_since_close": wins_since_close,
		"level_cache": level_cache,
		"level_cache_active": level_cache_active,
		"best_encouraged_rank": best_encouraged_rank,
		"last_online_rank": last_online_rank,
		"last_seen_online_rank": last_seen_online_rank,
		"place2_wins": place2_wins,
		"place3_wins": place3_wins,
		"streak_table": streak_table,
		"boost_spec": boost_spec,
		"win_streak": win_streak,
		"last_multiplier": last_multiplier,
		"prev_multiplier": prev_multiplier,
		"level_failed_pending": level_failed_pending,
	}


## 从字典恢复模型，并按这里定义的默认值兼容缺失字段；返回对象尚未自动写回存档。
static func from_dict(d: Dictionary) -> RankActivityData:
	var o := RankActivityData.new()
	o.period_count = int(d.get("period_count", o.period_count))
	o.prev_score = int(d.get("prev_score", o.prev_score))
	o.prev_rank = int(d.get("prev_rank", o.prev_rank))
	o.prev_awarded = bool(d.get("prev_awarded", o.prev_awarded))
	o.state = int(d.get("state", o.state))
	o.group = int(d.get("group", o.group))
	o.start_unix = int(d.get("start_unix", o.start_unix))
	o.end_unix = int(d.get("end_unix", o.end_unix))
	o.robot_key = str(d.get("robot_key", o.robot_key))
	o.joined = bool(d.get("joined", o.joined))
	o.collect_total = int(d.get("collect_total", o.collect_total))
	o.player_score_unix = int(d.get("player_score_unix", o.player_score_unix))
	o.settled = bool(d.get("settled", o.settled))
	o.final_rank = int(d.get("final_rank", o.final_rank))
	o.reward_claimed = bool(d.get("reward_claimed", o.reward_claimed))
	var raw_rank_like: Variant = d.get("rank_like", {})
	if raw_rank_like is Dictionary:
		o.rank_like = RankLikePeriodData.from_dict(raw_rank_like)
	o.wins_since_close = int(d.get("wins_since_close", o.wins_since_close))
	o.level_cache = int(d.get("level_cache", o.level_cache))
	o.level_cache_active = bool(d.get("level_cache_active", o.level_cache_active))
	o.best_encouraged_rank = int(d.get("best_encouraged_rank", o.best_encouraged_rank))
	o.last_online_rank = int(d.get("last_online_rank", o.last_online_rank))
	o.last_seen_online_rank = int(d.get("last_seen_online_rank", o.last_seen_online_rank))
	o.place2_wins = int(d.get("place2_wins", o.place2_wins))
	o.place3_wins = int(d.get("place3_wins", o.place3_wins))
	var raw_table: Variant = d.get("streak_table", [])
	o.streak_table = []
	if raw_table is Array:
		for tier in raw_table:
			o.streak_table.append(maxi(1, int(tier)))
	var raw_spec: Variant = d.get("boost_spec", {})
	o.boost_spec = (raw_spec as Dictionary).duplicate(true) if raw_spec is Dictionary else {}
	o.win_streak = maxi(0, int(d.get("win_streak", o.win_streak)))
	o.last_multiplier = int(d.get("last_multiplier", o.last_multiplier))
	o.prev_multiplier = int(d.get("prev_multiplier", o.prev_multiplier))
	o.level_failed_pending = bool(d.get("level_failed_pending", o.level_failed_pending))
	return o


func multiplier_for(streak: int) -> int:
	if streak_table.is_empty() or streak <= 0:
		return 1
	return int(streak_table[mini(streak, streak_table.size()) - 1])
