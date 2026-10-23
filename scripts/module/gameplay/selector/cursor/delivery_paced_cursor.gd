## 按实际交付计 LK 间隔的主线游标：候选扫描与最终交付分别更新不同计数。
class_name DeliveryPacedCursor
extends MainBankCursor


## 扫描候选时只推进题目索引，不增加普通题交付间隔。
func advance(entry: Dictionary) -> void:
	if str(entry.get("_bank_source_main", "")) == "lk_mod":
		var lk_prog: Dictionary = GameState.get_lkmod_progress(_sz, _rank)
		lk_prog["idx"] = int(lk_prog.get("idx", 0)) + 1
		GameState.set_lkmod_progress(_sz, _rank, lk_prog, false)
		return
	var prog: Dictionary = GameState.get_main_progress(_sz, _rank, _tier)
	prog["idx"] = int(prog.get("idx", 0)) + 1
	GameState.set_main_progress(_sz, _rank, _tier, prog, false)


## 确认交付后更新 since_lk；Elo 排序的 LK 交付还补进独立游标。
static func count_delivery(
	level_num: int, sz: int, rank: int, tier: String, entry: Dictionary
) -> void:
	if level_num < 51:
		return
	var src: String = str(entry.get("_bank_source_main", entry.get("_bank_source", "")))
	if src == "lk_mod":
		if bool(entry.get("_elo_sorted_pick", false)):
			var lk_prog: Dictionary = GameState.get_lkmod_progress(sz, rank)
			lk_prog["idx"] = int(lk_prog.get("idx", 0)) + 1
			GameState.set_lkmod_progress(sz, rank, lk_prog, false)
		var lk_main: Dictionary = GameState.get_main_progress(sz, rank, tier)
		lk_main["since_lk"] = 0
		GameState.set_main_progress(sz, rank, tier, lk_main, false)
	elif src in ["regular", "lkstyle", "gc"]:
		var prog: Dictionary = GameState.get_main_progress(sz, rank, tier)
		prog["since_lk"] = int(prog.get("since_lk", 0)) + 1
		GameState.set_main_progress(sz, rank, tier, prog, false)
