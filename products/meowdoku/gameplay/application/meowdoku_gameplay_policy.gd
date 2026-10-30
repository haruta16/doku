## 产品把规则相关 AB 值收集为普通数据；存档与规则模块不持有 AB 对象。
## 视觉实验仍按各自时机读取。每日广告解锁是业务资格变化，不冻结成 AB 值。
class_name MeowdokuGameplayPolicy
extends RefCounted

const ADDED_SCHEMA_ONE_FIELDS: Array[String] = ["dda", "swipe_guard_variant", "revive_free_variant", "normal_endgame_save"]


static func capture(ab: Node, level: int = 0) -> Dictionary:
	var next_level: int = level + 1
	var next_is_hard: bool = LevelData.is_hard_level_group_j(next_level) if ab.rule_normal_rank.is_group_j() else LevelData.is_hard_level(next_level)
	return {
		"schema": 1,
		"draft_variant": int(ab.draft_mode.value()),
		"undo_enabled": bool(ab.undo_btn.is_enabled()),
		"undo_free": bool(ab.undo_btn.is_free()),
		"undo_mode": "revert" if ab.undo_btn.is_undo_mode() else "highlight",
		"auto_complete_enabled": bool(ab.auto_complete.is_enabled()),
		"auto_complete_marks": bool(ab.auto_complete.should_auto_mark_crosses()),
		"auto_mark_variant": int(ab.game_auto_mark.value()),
		"reward_unlock_level": int(ab.reward_unlock_level.value()),
		"revive_lives": int(ab.revive_life.get_lives_to_restore()),
		"revive_free_variant": int(ab.revive_free_logic.value()),
		"normal_endgame_save": bool(ab.normal_endgame_save.is_enabled()),
		"life_plus_enabled": bool(ab.game_life_rule.is_life_plus_enabled()),
		"swipe_guard": bool(ab.swipe_protect.is_enabled()),
		"swipe_guard_variant": int(ab.swipe_protect.value()),
		"tap_allow_error_start": bool(ab.tap_feedback.allows_mark_from_error_start()),
		"tap_split": bool(ab.tap_feedback.is_press_release_split()),
		"dda": {
			"retry_once": bool(ab.dda_rank.is_retry_once_demote()),
			"tool_revive": bool(ab.dda_rank.is_tool_revive_demote()),
			"any_action": bool(ab.dda_rank.is_any_action_demote()),
			"next_is_skip": next_is_hard or LevelData.is_special_level(next_level),
		},
	}


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
	return true


## 老残局没有此字段时，以本次启动 AB 生成一次兼容快照；已有完整快照不重新染色。
static func restore(saved: Variant, fallback: Dictionary) -> Dictionary:
	if not saved is Dictionary or not validate(saved):
		return fallback.duplicate(true)
	var restored: Dictionary = fallback.duplicate(true)
	restored.merge(saved.duplicate(true), true)
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
	if value.has("swipe_guard_variant") and (typeof(value.swipe_guard_variant) != TYPE_INT or value.swipe_guard_variant not in [0, 1, 2, 3]):
		return false
	if value.has("dda") and not validate_dda(value.dda):
		return false
	if value.has("revive_free_variant") and (typeof(value.revive_free_variant) != TYPE_INT or value.revive_free_variant not in [0, 1, 2]):
		return false
	if value.has("normal_endgame_save") and typeof(value.normal_endgame_save) != TYPE_BOOL:
		return false
	return value.draft_variant in [0, 1, 2, 3, 4] and value.auto_mark_variant in [0, 1, 2, 3, 4, 5] and value.revive_lives in [1, 2, 3] and value.undo_mode in ["revert", "highlight"]


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
