## 需要玩家选择的进度冲突：同时保留本地、云端快照及建议选项，供选择页展示。

class_name ProgressConflict
extends RefCounted

var local: ProgressSnapshot = null

var cloud: ProgressSnapshot = null

var suggested: String = ""


static func of(
	local_side: ProgressSnapshot, cloud_side: ProgressSnapshot, suggested_side: String
) -> ProgressConflict:
	var conflict := ProgressConflict.new()
	conflict.local = local_side
	conflict.cloud = cloud_side
	conflict.suggested = suggested_side
	return conflict
