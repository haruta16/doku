## LK 改题库节奏采集：沿用题池的尺寸、层级和特殊预留排除规则，保持索引对齐。
class_name PaceLkModPaceCollector
extends RefCounted


## 遍历原始 LK 改题库，过滤后按原索引收集节奏记录。
static func collect(sz: int, rank: int, strict_rank: bool) -> Array:
	var result: Array = []
	var lk_mod_all: Array = BankData.get_lk_modified_levels()
	for i: int in range(lk_mod_all.size()):
		if (i + 1) in LevelData.LK_MOD_RESERVED:
			continue
		var e: Dictionary = lk_mod_all[i]
		if int(e.get("size", 0)) != sz:
			continue
		var e_rank: int = int(e.get("r", 1)) if strict_rank else int(e.get("maxR", e.get("r", 1)))
		if e_rank != rank:
			continue
		result.append(BankData.get_lkmod_pace_by_original_idx(i))
	return result
