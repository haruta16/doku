## 把 LevelRecManager 队列中的服务端推荐题转换成项目统一题目结构，并保留推荐归因字段。
class_name ServerProvider
extends LevelProvider

const _STRATEGY_TO_RANK_TIER: Dictionary = {
	1: [1, ""],
	2: [2, ""],
	3: [3, ""],
	4: [4, ""],
	5: [4, "H"],
	6: [5, ""],
	7: [5, "H"],
}


## 返回服务端推荐来源的固定标识。
func get_provider_id() -> StringName:
	return &"server"


## 检查推荐队列当前是否可取题；这里不发起网络请求。
func is_available(_ctx: LevelSelectContext) -> bool:
	return LevelRecManager.is_queue_available()


## 从推荐队列取走一题，再转换为统一 entry；取题本身会消费队列。
func next_entry(_ctx: LevelSelectContext) -> Dictionary:
	var raw: Dictionary = LevelRecManager.dequeue()
	if raw.is_empty():
		return {}
	return build_entry(raw)


## 映射棋盘字段，解析 qid 中的来源和变换，并附加推荐请求、槽位及曝光信息。
static func build_entry(raw: Dictionary) -> Dictionary:
	var entry: Dictionary = {}

	entry["regionMap"] = raw.get("region_map", [])
	entry["solution"] = raw.get("solution", [])

	entry["size"] = raw.get("size", 0)
	entry["seed"] = raw.get("seed", 0)
	entry["steps"] = raw.get("steps", 0)
	entry["r"] = raw.get("r", 0)
	entry["r1"] = raw.get("r1", 0)
	entry["r2"] = raw.get("r2", 0)
	entry["r3"] = raw.get("r3", 0)
	entry["r4"] = raw.get("r4", 0)
	entry["r5"] = raw.get("r5", 0)

	var qid: String = str(raw.get("qid", ""))
	var parsed: Dictionary = _parse_qid(qid)
	var source: String = str(parsed.get("source", "regular"))
	var strategy: int = int(parsed.get("strategy", 1))
	var idx: int = int(parsed.get("idx", 0))
	var transform: int = int(parsed.get("transform", 0))

	var rt: Array = _STRATEGY_TO_RANK_TIER.get(strategy, [1, ""])
	var rank: int = int(rt[0])
	var tier: String = str(rt[1])

	entry["_bank_source"] = source
	entry["_bank_source_main"] = source
	entry["_bank_idx"] = idx
	entry["_bank_rank"] = rank
	entry["_bank_tier"] = tier
	entry["_bank_transform"] = transform

	entry["_rec_qid"] = qid
	entry["_rec_impression_id"] = str(raw.get("impression_id", ""))
	entry["_rec_rhythm_state"] = str(raw.get("rhythm_state", ""))
	entry["_rec_selection_status"] = str(raw.get("selection_status", ""))
	entry["_rec_is_explore"] = raw.get("is_explore", false)
	entry["_rec_intended_optimal_qid"] = str(raw.get("intended_optimal_qid", ""))
	entry["_rec_slot_index"] = raw.get("_slot_index", -1)

	entry["_rec_decision_id"] = str(raw.get("_request_id", ""))

	return entry


## 按五段下划线格式拆解 qid；结构不符合约定时返回空字典。
static func _parse_qid(qid: String) -> Dictionary:
	var parts: PackedStringArray = qid.split("_")
	if parts.size() != 5:
		return {}
	return {
		"size": int(parts[0]),
		"source": parts[1],
		"strategy": int(parts[2]),
		"idx": int(parts[3]),
		"transform": int(parts[4]),
	}
