## 节奏日志查找：把交付记录的一基题号转换为节奏缓存的零基索引。
class_name PaceLogSeqLookup
extends RefCounted


## 支持三类普通题库来源，返回解题策略与提示点击序列，输入无效时返回空序列。
static func lookup(source: String, sz: int, rank: int, bank_idx: int) -> Dictionary:
	if source != "regular" and source != "lkstyle" and source != "gc":
		return {"r_seq": [], "hint_click_seq": []}
	if sz <= 0 or bank_idx <= 0:
		return {"r_seq": [], "hint_click_seq": []}
	var pace: Dictionary = BankData.get_pace_entry(source, sz, rank, bank_idx - 1)
	return {
		"r_seq": pace.get("r_seq", []),
		"hint_click_seq": pace.get("hint_click_seq", []),
	}
