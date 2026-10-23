## 普通关卡策略 HardRatingSelector：由选题策略解析器选择，封装该分组的候选筛选与交付规则。
class_name HardRatingSelector
extends RefCounted


static func rank_at(level: int, alternate: bool) -> int:
	var index: int = (level - 110) / 10
	for fixed_level: int in SpecialProvider.SPECIAL_LEVELS:
		if fixed_level >= 110 and fixed_level < level and fixed_level % 10 == 0:
			index -= 1
	if alternate and index % 2 == 1:
		return 5
	return 4


static func filter_pool(entries: Array, rank: int) -> Array:
	var filtered: Array = []
	for entry: Dictionary in entries:
		if int(entry.get("r", 0)) != rank or str(entry.get("tier", "")) != "N":
			continue
		var rating: int = int(entry.get("rating", -1))
		if rank == 4 and rating >= 7200 or rank == 5 and rating >= 0 and rating <= 16454:
			filtered.append(entry)
	return filtered
