## 每日挑战开局文案池：区分首次与重试，抽取翻译键及展示百分比范围。
class_name DcStartToastTextPool
extends RefCounted

const _FIRST: Array = [
	{key = "TOAST_TEXT_DC_FIRST_0", pct = {lo = 40.0, hi = 60.0}},
	{key = "TOAST_TEXT_DC_FIRST_1", pct = {lo = 40.0, hi = 60.0}},
	{key = "TOAST_TEXT_DC_FIRST_2", pct = null},
	{key = "TOAST_TEXT_DC_FIRST_3", pct = null},
	{key = "TOAST_TEXT_DC_FIRST_4", pct = null},
]

const _RETRY: Array = [
	{key = "TOAST_TEXT_DC_RETRY_0", pct = {lo = 70.0, hi = 90.0}},
	{key = "TOAST_TEXT_DC_RETRY_1", pct = {lo = 60.0, hi = 80.0}},
	{key = "TOAST_TEXT_DC_RETRY_2", pct = null},
	{key = "TOAST_TEXT_DC_RETRY_3", pct = null},
	{key = "TOAST_TEXT_DC_RETRY_4", pct = null},
]

const SCENE_FIRST: String = "first"
const SCENE_RETRY: String = "retry"


static func resolve(is_first: bool) -> Dictionary:
	var pool: Array = _FIRST if is_first else _RETRY
	var scene: String = SCENE_FIRST if is_first else SCENE_RETRY
	var idx: int = randi_range(0, pool.size() - 1)
	var entry: Dictionary = pool[idx]
	var pct_range: Variant = entry.get("pct", null)
	if pct_range == null:
		return {"text_key": entry.key, "pct_str": ""}
	var pct: float = _resolve_pct(scene, idx, pct_range)
	return {"text_key": entry.key, "pct_str": I18nFormat.percent(pct, 1)}


static func _resolve_pct(scene: String, idx: int, pct_range: Dictionary) -> float:
	var cached: float = GameState.get_dc_start_toast_pct(scene, idx)
	if cached >= 0.0:
		return cached
	var low: float = pct_range.lo
	var high: float = pct_range.hi
	var pct: float = low + randf() * (high - low)
	GameState.set_dc_start_toast_pct(scene, idx, pct)
	return pct
