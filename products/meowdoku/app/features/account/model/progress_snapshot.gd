## 进度选择页所需的最小快照，只比较关卡位置与道具数量，不复制完整存档。

class_name ProgressSnapshot
extends RefCounted

var level: int = 0

var items: int = 0


static func of(progress_level: int, item_total: int) -> ProgressSnapshot:
	var snapshot := ProgressSnapshot.new()
	snapshot.level = progress_level
	snapshot.items = item_total
	return snapshot
