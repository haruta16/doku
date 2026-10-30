## 奖励条目模型：统一道具与头像框的类别、数量和有效性，并支持展示顺序调整。
extends RefCounted
class_name AwardItem

enum Category { TOOL, FRAME }

# ---- 数据字段 ----
var kind: String = "" # 道具种类（locate / hint / undo 等）
var frame_id: int = 0
var count: int = 0 # 数量
var category: int = Category.TOOL


## 构造普通道具条目，实际库存变化留给奖励管理器。
static func make(p_kind: String, p_count: int) -> AwardItem:
	var it := AwardItem.new()
	it.kind = p_kind
	it.count = p_count
	it.category = Category.TOOL
	return it


## 构造头像框条目，用 frame_id 区别于道具 kind。
static func make_frame(p_frame_id: int, p_count: int = 1) -> AwardItem:
	var it := AwardItem.new()
	it.frame_id = p_frame_id
	it.count = p_count
	it.category = Category.FRAME
	return it


## 就地交换提示与定位道具的位置，只影响展示顺序，不改奖励数量。
static func apply_prop_position(items: Array, hint_first: bool) -> void:
	var hint_idx: int = -1
	var locate_idx: int = -1
	for i in items.size():
		var it = items[i]
		if it == null or int(it.category) != Category.TOOL:
			continue
		if str(it.kind) == ToolKind.HINT and hint_idx < 0:
			hint_idx = i
		elif str(it.kind) == ToolKind.LOCATE and locate_idx < 0:
			locate_idx = i
	if hint_idx < 0 or locate_idx < 0:
		return

	var need_swap: bool = (hint_idx > locate_idx) if hint_first else (locate_idx > hint_idx)
	if not need_swap:
		return
	var tmp = items[hint_idx]
	items[hint_idx] = items[locate_idx]
	items[locate_idx] = tmp


## 数量必须为正；头像框要求有效编号，道具要求非空种类。
func is_valid() -> bool:
	if count <= 0:
		return false
	return frame_id > 0 if category == Category.FRAME else kind != ""


func to_dict() -> Dictionary:
	return {"kind": kind, "frame_id": frame_id, "count": count, "category": category}
