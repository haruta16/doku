## 近期关卡记录器：保留最近的关卡配置，供缩略图调试页回看。
class_name RecentLevelDebugTracker
extends RefCounted

const CAPACITY: int = 60

static var _entries: Array[Dictionary] = []


static func record(
	level_num: int, size: int, rank: int, region_map: Array, source: String, iso_check: String = ""
) -> void:
	(
		_entries
		. append(
			{
				"level": level_num,
				"size": size,
				"rank": rank,
				"region_map": region_map,
				"source": source,
				"iso_check": iso_check,
			}
		)
	)
	while _entries.size() > CAPACITY:
		_entries.pop_front()


static func get_recent(count: int) -> Array[Dictionary]:
	if count <= 0 or _entries.is_empty():
		return []
	var start: int = maxi(0, _entries.size() - count)
	var result: Array[Dictionary] = []
	result.assign(_entries.slice(start))
	return result
