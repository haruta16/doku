## 开局提示文案选择：按关卡类型与难度挑选文本，并格式化百分比参数。
class_name StartToastTextPool
extends RefCounted

const _G1_FIRST: Array = [
	{key = "TOAST_TEXT_G1_FIRST_0", pct = null},
	{key = "TOAST_TEXT_G1_FIRST_1", pct = null},
	{key = "TOAST_TEXT_G1_FIRST_2", pct = null},
	{key = "TOAST_TEXT_G1_FIRST_3", pct = null},
	{key = "TOAST_TEXT_G1_FIRST_4", pct = null},
	{key = "TOAST_TEXT_G1_FIRST_5", pct = null},
]
const _G1_HARD: Array = [
	{key = "TOAST_TEXT_G1_HARD_0", pct = null},
	{key = "TOAST_TEXT_G1_HARD_1", pct = null},
]
const _G1_RETRY: Array = [
	{key = "TOAST_TEXT_G1_RETRY_0", pct = null},
	{key = "TOAST_TEXT_G1_RETRY_1", pct = null},
	{key = "TOAST_TEXT_G1_RETRY_2", pct = null},
	{key = "TOAST_TEXT_G1_RETRY_3", pct = null},
	{key = "TOAST_TEXT_G1_RETRY_4", pct = null},
	{key = "TOAST_TEXT_G1_RETRY_5", pct = null},
]
const _G1_SPECIAL: Array = [
	{key = "TOAST_TEXT_G1_SPECIAL_0", pct = null},
	{key = "TOAST_TEXT_G1_SPECIAL_1", pct = null},
	{key = "TOAST_TEXT_G1_SPECIAL_2", pct = null},
	{key = "TOAST_TEXT_G1_SPECIAL_3", pct = null},
	{key = "TOAST_TEXT_G1_SPECIAL_4", pct = null},
	{key = "TOAST_TEXT_G1_SPECIAL_5", pct = null},
	{key = "TOAST_TEXT_G1_SPECIAL_6", pct = null},
	{key = "TOAST_TEXT_G1_SPECIAL_7", pct = null},
	{key = "TOAST_TEXT_G1_SPECIAL_8", pct = null},
	{key = "TOAST_TEXT_G1_SPECIAL_9", pct = null},
]

const _G2_FIRST: Array = [
	{
		key = "TOAST_TEXT_G2_FIRST_0",
		pct = {normal = Vector2(60, 80), hard = Vector2(40, 60), format = "xx.x%"}
	},
	{
		key = "TOAST_TEXT_G2_FIRST_1",
		pct = {normal = Vector2(55, 75), hard = Vector2(35, 55), format = "xx.x%"}
	},
	{
		key = "TOAST_TEXT_G2_FIRST_2",
		pct = {normal = Vector2(1.5, 2.8), hard = Vector2(1.5, 2.8), format = "x.x"}
	},
	{
		key = "TOAST_TEXT_G2_FIRST_3",
		pct = {normal = Vector2(20, 40), hard = Vector2(10, 25), format = "xx.x%"}
	},
]
const _G2_RETRY: Array = [
	{
		key = "TOAST_TEXT_G2_RETRY_0",
		pct = {normal = Vector2(70, 90), hard = Vector2(50, 70), format = "xx.x%"}
	},
	{key = "TOAST_TEXT_G2_RETRY_1", pct = {normal = Vector2(30, 50), format = "xx.x%"}},
	{key = "TOAST_TEXT_G2_RETRY_2", pct = {normal = Vector2(75, 90), format = "xx.x%"}},
	{key = "TOAST_TEXT_G2_RETRY_3", pct = {normal = Vector2(1.8, 3.0), format = "x.x"}},
]
const _G2_SPECIAL: Array = [
	{key = "TOAST_TEXT_G2_SPECIAL_0", pct = {normal = Vector2(15, 35), format = "xx.x%"}},
	{key = "TOAST_TEXT_G2_SPECIAL_1", pct = {normal = Vector2(5, 20), format = "xx.x%"}},
	{key = "TOAST_TEXT_G2_SPECIAL_2", pct = {normal = Vector2(60, 80), format = "xx.x%"}},
	{key = "TOAST_TEXT_G2_SPECIAL_3", pct = {normal = Vector2(40, 65), format = "xx.x%"}},
	{key = "TOAST_TEXT_G2_SPECIAL_4", pct = {normal = Vector2(30, 50), format = "xx.x%"}},
	{key = "TOAST_TEXT_G2_SPECIAL_5", pct = {normal = Vector2(10, 25), format = "xx.x%"}},
	{key = "TOAST_TEXT_G2_SPECIAL_6", pct = {normal = Vector2(3, 15), format = "xx.x%"}},
]

const _G3_FIRST: Array = [
	{
		key = "TOAST_TEXT_G3_FIRST_0",
		pct = {normal = Vector2(60, 80), hard = Vector2(40, 60), format = "xx.x%"}
	},
	{
		key = "TOAST_TEXT_G3_FIRST_1",
		pct = {normal = Vector2(25, 45), hard = Vector2(45, 65), format = "xx.x%"}
	},
	{
		key = "TOAST_TEXT_G3_FIRST_2",
		pct = {normal = Vector2(20, 40), hard = Vector2(10, 25), format = "xx.x%"}
	},
	{
		key = "TOAST_TEXT_G3_FIRST_3",
		pct = {normal = Vector2(1.5, 2.8), hard = Vector2(1.5, 2.8), format = "x.x"}
	},
]
const _G3_HARD: Array = [
	{
		key = "TOAST_TEXT_G3_HARD_0",
		pct = {hard = Vector2(40, 60), normal = Vector2(40, 60), format = "xx.x%"}
	},
]
const _G3_RETRY: Array = [
	{key = "TOAST_TEXT_G3_RETRY_0", pct = {normal = Vector2(30, 50), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_RETRY_1", pct = {normal = Vector2(75, 90), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_RETRY_2", pct = {normal = Vector2(45, 65), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_RETRY_3", pct = {normal = Vector2(30, 50), format = "xx.x%"}},
]
const _G3_SPECIAL: Array = [
	{key = "TOAST_TEXT_G3_SPECIAL_0", pct = {normal = Vector2(15, 35), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_SPECIAL_1", pct = {normal = Vector2(40, 65), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_SPECIAL_2", pct = {normal = Vector2(5, 20), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_SPECIAL_3", pct = {normal = Vector2(30, 50), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_SPECIAL_4", pct = {normal = Vector2(20, 40), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_SPECIAL_5", pct = {normal = Vector2(40, 60), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_SPECIAL_6", pct = {normal = Vector2(25, 45), format = "xx.x%"}},
	{key = "TOAST_TEXT_G3_SPECIAL_7", pct = {normal = Vector2(55, 75), format = "xx.x%"}},
]

const _G4_FIRST: Array = [
	{key = "TOAST_TEXT_G4_FIRST_0", pct = null},
	{key = "TOAST_TEXT_G4_FIRST_1", pct = null},
	{key = "TOAST_TEXT_G4_FIRST_2", pct = null},
	{key = "TOAST_TEXT_G4_FIRST_3", pct = null},
	{key = "TOAST_TEXT_G4_FIRST_4", pct = null},
	{key = "TOAST_TEXT_G4_FIRST_5", pct = null},
]
const _G4_HARD: Array = [
	{key = "TOAST_TEXT_G4_HARD_0", pct = null},
	{key = "TOAST_TEXT_G4_HARD_1", pct = null},
]
const _G4_RETRY: Array = [
	{key = "TOAST_TEXT_G4_RETRY_0", pct = null},
	{key = "TOAST_TEXT_G4_RETRY_1", pct = null},
	{key = "TOAST_TEXT_G4_RETRY_2", pct = null},
	{key = "TOAST_TEXT_G4_RETRY_3", pct = null},
	{key = "TOAST_TEXT_G4_RETRY_4", pct = null},
	{key = "TOAST_TEXT_G4_RETRY_5", pct = null},
]
const _G4_SPECIAL: Array = [
	{key = "TOAST_TEXT_G4_SPECIAL_0", pct = null},
	{key = "TOAST_TEXT_G4_SPECIAL_1", pct = null},
	{key = "TOAST_TEXT_G4_SPECIAL_2", pct = null},
	{key = "TOAST_TEXT_G4_SPECIAL_3", pct = null},
	{key = "TOAST_TEXT_G4_SPECIAL_4", pct = null},
	{key = "TOAST_TEXT_G4_SPECIAL_5", pct = null},
	{key = "TOAST_TEXT_G4_SPECIAL_6", pct = null},
	{key = "TOAST_TEXT_G4_SPECIAL_7", pct = null},
	{key = "TOAST_TEXT_G4_SPECIAL_8", pct = null},
	{key = "TOAST_TEXT_G4_SPECIAL_9", pct = null},
]


static func _get_pool(group: int, kind: String, is_hard: bool) -> Array:
	match group:
		1:
			match kind:
				"first":
					return (_G1_FIRST + _G1_HARD) if is_hard else _G1_FIRST
				"retry":
					return _G1_RETRY
				"special":
					return _G1_SPECIAL
		2:
			match kind:
				"first":
					return _G2_FIRST
				"retry":
					return _G2_RETRY
				"special":
					return _G2_SPECIAL
		3:
			match kind:
				"first":
					return (_G3_FIRST + _G3_HARD) if is_hard else _G3_FIRST
				"retry":
					return _G3_RETRY
				"special":
					return _G3_SPECIAL
		4:
			match kind:
				"first":
					return (_G4_FIRST + _G4_HARD) if is_hard else _G4_FIRST
				"retry":
					return _G4_RETRY
				"special":
					return _G4_SPECIAL
	push_error("StartToastTextPool: unknown group/kind %d/%s" % [group, kind])
	return []


static func _kind_h(kind: String, is_hard: bool, has_hard_pool: bool) -> String:
	if kind == "first" and is_hard and has_hard_pool:
		return "first_h"
	return kind


static func _has_hard_pool(group: int) -> bool:
	return group == 1 or group == 3 or group == 4


static func resolve(group: int, kind: String, is_hard: bool, lv: int) -> Dictionary:
	var pool: Array = _get_pool(group, kind, is_hard)
	if pool.is_empty():
		return {"text_key": "", "pct_str": ""}

	var kind_h: String = _kind_h(kind, is_hard, _has_hard_pool(group))
	var gs: Node = _get_game_state()

	var idx: int = gs.get_start_toast_variant_idx(lv, group, kind_h) if gs != null else -1
	if idx < 0 or idx >= pool.size():
		idx = randi_range(0, pool.size() - 1)
		if gs != null:
			gs.set_start_toast_variant_idx(lv, group, kind_h, idx)

	var entry: Dictionary = pool[idx]
	if entry.pct == null:
		return {"text_key": entry.key, "pct_str": ""}

	var range_vec: Vector2
	if is_hard:
		range_vec = entry.pct.get("hard", entry.pct.normal)
	else:
		range_vec = entry.pct.normal
	var pct: float = gs.get_start_toast_variant_pct(lv, group, kind_h, idx) if gs != null else -1.0
	if pct < 0.0:
		pct = randf_range(range_vec.x, range_vec.y)
		if gs != null:
			gs.set_start_toast_variant_pct(lv, group, kind_h, idx, pct)

	var pct_str: String = _format_pct(pct, entry.pct.format)
	return {"text_key": entry.key, "pct_str": pct_str}


static func _get_game_state() -> Node:
	var loop: MainLoop = Engine.get_main_loop()
	var tree: SceneTree = loop as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameState")


static func _format_pct(pct: float, format: String) -> String:
	if format == "xx.x%":
		return I18nFormat.percent(pct, 1)
	return I18nFormat.decimal(pct, 1)
