## 单局分数模型：保存总分、当前连击和最高连击，可导出为残局字典。
class_name GameScoreModel
extends RefCounted

var score: int = 0
var combo: int = 0
var max_combo: int = 0


## 增加连击并更新本局最高连击。
func add_combo() -> void:
	combo += 1
	if combo > max_combo:
		max_combo = combo


## 只中断当前连击，保留最高连击和总分。
func reset_combo() -> void:
	combo = 0


## 把本次获得的分数累计到总分。
func add_score(gain: int) -> void:
	score += gain


## 新局开始时清除分数及两项连击状态。
func reset_all() -> void:
	score = 0
	combo = 0
	max_combo = 0


## 把分数状态转成独立字典，供快照序列化。
func to_dict() -> Dictionary:
	return {"score": score, "combo": combo, "max_combo": max_combo}


## 从字典恢复分数，旧快照缺最高连击时使用当前连击。
func restore(d: Dictionary) -> void:
	score = int(d.get("score", 0))
	combo = int(d.get("combo", 0))
	max_combo = int(d.get("max_combo", combo))
