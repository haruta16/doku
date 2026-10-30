## 产品把规则相关 AB 值收集为普通数据；存档与规则模块不持有 AB 对象。
## 视觉实验仍按各自时机读取。每日广告解锁是业务资格变化，不冻结成 AB 值。
class_name MeowdokuGameplayPolicy
extends RefCounted

const ADDED_SCHEMA_ONE_FIELDS: Array[String] = ["dda", "swipe_guard_variant", "revive_free_variant", "normal_endgame_save", "rules_revision", "hint_func", "prop_mouse", "auto_x_fill_variant", "doubletap_protect", "swipe_logic", "pass_text", "health_points_rule", "multi_touch", "score_encourage", "win_encourage_variant"]


static func capture(ab: Node, level: int = 0) -> Dictionary:
	var dda: int = _value(ab, "dda_rank", 1)
	var swipe: int = _value(ab, "swipe_protect", 1)
	var complete: int = _value(ab, "auto_complete", 0)
	var undo: int = _value(ab, "undo_btn", 0)
	return {
		"schema": 1, "rules_revision": 122, "draft_variant": _value(ab, "draft_mode", 0),
		"undo_enabled": undo != 0, "undo_free": undo == 2, "undo_mode": "highlight" if undo == 3 else "revert",
		"auto_complete_enabled": complete != 0, "auto_complete_marks": complete == 1,
		"auto_mark_variant": _value(ab, "game_auto_mark", 0),
		"auto_x_fill_variant": _value(ab, "auto_x_fill_mode", 0),
		"reward_unlock_level": _value(ab, "reward_unlock_level", 0),
		"revive_lives": 1 if _value(ab, "revive_life", 0) == 0 else 3,
		"revive_free_variant": _value(ab, "revive_free_logic", 0),
		"normal_endgame_save": _value(ab, "normal_endgame_save", 0) != 0,
		"life_plus_enabled": _value(ab, "game_life_rule", 0) == 1,
		"swipe_guard": swipe != 0, "swipe_guard_variant": swipe,
		"tap_allow_error_start": false, "tap_split": false,
		"hint_func": _value(ab, "hint_func", 0), "prop_mouse": _value(ab, "prop_mouse", 0),
		"doubletap_protect": _value(ab, "doubletap_protect", 0),
		"swipe_logic": _value(ab, "swipe_logic", 0),
		"pass_text": _value(ab, "pass_text", 3),
		"health_points_rule": str(_raw_value(ab, "health_points_rule", "{1,end,3}")),
		"multi_touch": _value(ab, "multi_touch", 0),
		"score_encourage": _value(ab, "score_encourage", 2),
		"win_encourage_variant": _value(ab, "win_encourage", 0),
		"dda": {"retry_once": dda == 1, "tool_revive": dda == 2, "any_action": dda == 3,
			"next_is_skip": LevelData.is_hard_level(level + 1) or LevelData.is_special_level(level + 1)},
	}


static func _value(ab: Object, name: String, fallback: int) -> int:
	for property: Dictionary in ab.get_property_list():
		if str(property.name) == name:
			var config: Variant = ab.get(name)
			return int(config.value()) if config != null and config.has_method("value") else fallback
	return fallback


## 完整恢复快照不接触当前 AB/内容；只有旧快照缺字段时才捕获兼容值。
static func resolve(saved: Variant, ab: Node, level: int = 0) -> Dictionary:
	if is_complete(saved):
		return saved.duplicate(true)
	return restore(saved, capture(ab, level))


static func is_complete(value: Variant) -> bool:
	if not value is Dictionary or not validate(value):
		return false
	for key: String in ADDED_SCHEMA_ONE_FIELDS:
		if not value.has(key):
			return false
	return int(value.get("rules_revision", 0)) == 122


## 老残局没有此字段时，以本次启动 AB 生成一次兼容快照；已有完整快照不重新染色。
static func restore(saved: Variant, fallback: Dictionary) -> Dictionary:
	if not saved is Dictionary or not validate(saved):
		return fallback.duplicate(true)
	var restored: Dictionary = fallback.duplicate(true)
	restored.merge(saved.duplicate(true), true)
	restored["rules_revision"] = int(fallback.get("rules_revision", 122))
	return restored


static func validate(value: Dictionary) -> bool:
	if typeof(value.get("schema")) != TYPE_INT or value.schema != 1:
		return false
	for key: String in ["undo_enabled", "undo_free", "auto_complete_enabled", "auto_complete_marks", "life_plus_enabled", "swipe_guard", "tap_allow_error_start", "tap_split"]:
		if typeof(value.get(key)) != TYPE_BOOL:
			return false
	for key: String in ["draft_variant", "auto_mark_variant", "reward_unlock_level", "revive_lives"]:
		if typeof(value.get(key)) != TYPE_INT:
			return false
	if typeof(value.get("undo_mode")) != TYPE_STRING:
		return false
	if value.has("swipe_guard_variant") and (typeof(value.swipe_guard_variant) != TYPE_INT or value.swipe_guard_variant < 0 or value.swipe_guard_variant > 11):
		return false
	if value.has("dda") and not validate_dda(value.dda):
		return false
	if value.has("revive_free_variant") and (typeof(value.revive_free_variant) != TYPE_INT or value.revive_free_variant not in [0, 1, 2]):
		return false
	if value.has("normal_endgame_save") and typeof(value.normal_endgame_save) != TYPE_BOOL:
		return false
	return value.draft_variant in [0, 1, 2, 3, 4, 5] and value.auto_mark_variant in [0, 1, 2, 3, 4, 5] and value.revive_lives in [1, 2, 3] and value.undo_mode in ["revert", "highlight"]


static func validate_dda(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: String in ["retry_once", "tool_revive", "any_action", "next_is_skip"]:
		if typeof(value.get(key)) != TYPE_BOOL:
			return false
	return true


static func swipe_guard_parameters(policy: Dictionary, size: int) -> Dictionary:
	var variant: int = int(policy.get("swipe_guard_variant", 0))
	return {
		"enabled": bool(policy.get("swipe_guard", false)),
		"min_size": 7 if variant == SwipeProtectConfig.VALUE_HOTZONE_RAISED else 0,
		"threshold": ceili(size * 0.6) if variant == SwipeProtectConfig.VALUE_HOTZONE_RAISED else 4,
		"tolerance_pct": 0.1 if variant == SwipeProtectConfig.VALUE_HOTZONE_10 else 0.4,
	}


## 实验值冻结，终身首次资格由产品当前状态提供；保留低关卡/调试免费的覆盖顺序。
static func revive_offer(policy: Dictionary, level: int, once_used: bool, force_free: bool = false) -> Dictionary:
	var variant: int = int(policy.get("revive_free_variant", 0))
	var consume_once: bool = variant == 2 and not once_used
	var free: bool = force_free or level < int(policy.get("reward_unlock_level", 0)) or (variant == 1 and level == 1) or consume_once
	return {"free": free, "consume_free_once": free and consume_once}


static func auto_mark_after_cat(policy: Dictionary, level: int) -> bool:
	return policy.get("auto_mark_variant", 0) == 1 or (policy.get("auto_mark_variant", 0) == 3 and level <= 6)


static func auto_mark_prefill(policy: Dictionary, level: int) -> bool:
	return (policy.get("auto_mark_variant", 0) == 1 and level <= 10) or (policy.get("auto_mark_variant", 0) == 3 and level <= 6)


static func dot_toggle(policy: Dictionary, level: int) -> bool:
	return policy.get("auto_mark_variant", 0) == 2 and level > 30


static func _raw_value(ab: Object, name: String, fallback: Variant) -> Variant:
	for property: Dictionary in ab.get_property_list():
		if str(property.name) == name:
			var config: Variant = ab.get(name)
			return config.value() if config != null and config.has_method("value") else fallback
	return fallback
