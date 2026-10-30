## 猜测倾向标签：根据普通关结算表现更新持久化状态，并向业务提供当前判定。
class_name GambleUserTag
extends RefCounted

const LOCAL_TAG_KEY: String = "is_gamble_user"
const UPDATE_LEVEL_TAG_KEY: String = "gamble_update_level"
const VALUE_UNTAGGED: int = -1
const VALUE_REASONING: int = 0
const VALUE_GAMBLE: int = 1
const _UPDATE_LEVEL_UNSET: String = "-1"
const _EARLY_WINDOW_SIZE: int = 20
const _NON_EASY_WINDOW_SIZE: int = 5
const _NON_EASY_BATCH_VERSION: int = 2


static func get_value() -> int:
	var value: int = GameState.get_gamble_user_value()
	return value if is_valid_value(value) else VALUE_UNTAGGED


static func get_update_level() -> String:
	var value: String = GameState.get_persisted_user_tag(UPDATE_LEVEL_TAG_KEY)
	return value if not value.is_empty() else _UPDATE_LEVEL_UNSET


static func is_tagged() -> bool:
	return get_value() != VALUE_UNTAGGED


static func is_reasoning() -> bool:
	return get_value() == VALUE_REASONING


static func is_gamble() -> bool:
	return get_value() == VALUE_GAMBLE


static func is_valid_value(value: int) -> bool:
	return value == VALUE_UNTAGGED or value == VALUE_REASONING or value == VALUE_GAMBLE


static func set_value(value: int) -> bool:
	if not is_valid_value(value):
		push_warning("[gamble_user] invalid tag value=%d, ignore" % value)
		return false
	GameState.set_gamble_user_value(value)
	_write_value(value)
	return true


static func update_after_main_level_won(
	level_num: int, this_session_rank: int, this_session_diffi: int, invalid_sign_total: int
) -> void:
	var state: Dictionary = _get_persisted_state()
	var result: Dictionary = resolve_state_after_main_level_won(
		state,
		level_num,
		this_session_rank,
		this_session_diffi,
		invalid_sign_total,
		ABTestManager.normal_level.is_super_hard_harder_active(),
	)
	if bool(result["batch_reset"]):
		push_warning("[gamble_user] non-easy batch mismatch, reset partial batch")
	_set_persisted_state(result, false)
	if bool(result["tag_changed"]):
		_write_value(int(result["value"]))
	if bool(result["judgment_completed"]):
		_write_update_level(str(result["gamble_update_level"]))
	_log_update(result, level_num, this_session_rank, this_session_diffi, invalid_sign_total)


static func resolve_state_after_main_level_won(
	current_state: Dictionary,
	level_num: int,
	this_session_rank: int,
	this_session_diffi: int,
	invalid_sign_total: int,
	include_diffi_two: bool = false
) -> Dictionary:
	var current_value: int = int(current_state.get("value", VALUE_UNTAGGED))
	var value: int = current_value if is_valid_value(current_value) else VALUE_UNTAGGED
	var update_level: String = str(current_state.get("gamble_update_level", _UPDATE_LEVEL_UNSET))
	var early_bits: Array = _duplicate_array(current_state.get("early_l1_l20_bits", []))
	var non_easy_bits: Array = _duplicate_array(
		current_state.get("recent_non_easy_invalid_bits", [])
	)
	var non_easy_levels: Array = _duplicate_array(current_state.get("recent_non_easy_levels", []))
	var batch_reset: bool = non_easy_bits.size() != non_easy_levels.size()
	if batch_reset:
		non_easy_bits.clear()
		non_easy_levels.clear()

	var early_before_size: int = early_bits.size()
	var non_easy_before_bits: Array = non_easy_bits.duplicate()
	var non_easy_before_levels: Array = non_easy_levels.duplicate()
	var pushed_early: bool = false
	var pushed_non_easy: bool = false
	if level_num >= 1 and level_num <= _EARLY_WINDOW_SIZE:
		pushed_early = true
		early_bits.push_back(this_session_rank != 2 or invalid_sign_total > 0)
		while early_bits.size() > _EARLY_WINDOW_SIZE:
			early_bits.pop_front()
	var is_non_easy: bool = (
		this_session_diffi == 1 or (this_session_diffi == 2 and include_diffi_two)
	)
	if level_num >= 21 and is_non_easy:
		pushed_non_easy = true
		non_easy_bits.push_back(invalid_sign_total > 0)
		non_easy_levels.push_back(level_num)
		while non_easy_bits.size() > _NON_EASY_WINDOW_SIZE:
			non_easy_bits.pop_front()
		while non_easy_levels.size() > _NON_EASY_WINDOW_SIZE:
			non_easy_levels.pop_front()

	var early_post_size: int = early_bits.size()
	var non_easy_post_bits: Array = non_easy_bits.duplicate()
	var non_easy_post_levels: Array = non_easy_levels.duplicate()
	var trigger: String = "none"
	var skipped_reason: String = ""
	var buffer_cleared: bool = false
	var judgment_completed: bool = false
	var is_trigger: bool = (
		level_num == 20
		or (level_num >= 21 and pushed_non_easy and non_easy_bits.size() == _NON_EASY_WINDOW_SIZE)
	)
	if is_trigger:
		var target_bits: Array
		var required_size: int
		if level_num == 20:
			trigger = "L20"
			target_bits = early_bits
			required_size = _EARLY_WINDOW_SIZE
		else:
			trigger = "non_easy_batch"
			target_bits = non_easy_bits
			required_size = _NON_EASY_WINDOW_SIZE
		if target_bits.size() < required_size:
			skipped_reason = "buffer_not_full(size=%d/%d)" % [target_bits.size(), required_size]
		else:
			value = VALUE_GAMBLE if _all_true(target_bits) else VALUE_REASONING
			update_level = "20" if level_num == 20 else JSON.stringify(non_easy_levels)
			target_bits.clear()
			if level_num != 20:
				non_easy_levels.clear()
			buffer_cleared = true
			judgment_completed = true

	return {
		"value": value,
		"gamble_update_level": update_level,
		"early_l1_l20_bits": early_bits,
		"recent_non_easy_invalid_bits": non_easy_bits,
		"recent_non_easy_levels": non_easy_levels,
		"tag_changed": judgment_completed and value != current_value,
		"judgment_completed": judgment_completed,
		"batch_reset": batch_reset,
		"early_before_size": early_before_size,
		"early_post_size": early_post_size,
		"non_easy_before_bits": non_easy_before_bits,
		"non_easy_before_levels": non_easy_before_levels,
		"non_easy_post_bits": non_easy_post_bits,
		"non_easy_post_levels": non_easy_post_levels,
		"pushed_early": pushed_early,
		"pushed_non_easy": pushed_non_easy,
		"trigger": trigger,
		"skipped_reason": skipped_reason,
		"buffer_cleared": buffer_cleared,
	}


static func debug_snapshot() -> Dictionary:
	var state: Dictionary = _get_persisted_state()
	return {
		"is_gamble_user": get_value(),
		"gamble_update_level": get_update_level(),
		"early_l1_l20_bits": state["early_l1_l20_bits"],
		"recent_hard_invalid_bits": state["recent_hard_invalid_bits"],
		"recent_non_easy_invalid_bits": state["recent_non_easy_invalid_bits"],
		"recent_non_easy_levels": state["recent_non_easy_levels"],
	}


static func reset(persist: bool = true) -> void:
	_set_persisted_state(
		{
			"value": VALUE_UNTAGGED,
			"gamble_update_level": _UPDATE_LEVEL_UNSET,
			"early_l1_l20_bits": [],
			"recent_non_easy_invalid_bits": [],
			"recent_non_easy_levels": [],
		},
		persist
	)
	UniKitManager.remove_local_tag(LOCAL_TAG_KEY)
	UniKitManager.remove_local_tag(UPDATE_LEVEL_TAG_KEY)


static func _get_persisted_state() -> Dictionary:
	var stored_batch: Array = GameState.get_gamble_user_recent_hard_invalid_bits()
	var decoded_batch: Dictionary = _decode_non_easy_batch(stored_batch)
	return {
		"value": GameState.get_gamble_user_value(),
		"gamble_update_level": get_update_level(),
		"early_l1_l20_bits": GameState.get_gamble_user_early_l1_l20_bits(),
		"recent_hard_invalid_bits": decoded_batch["legacy_hard_invalid_bits"],
		"recent_non_easy_invalid_bits": decoded_batch["invalid_bits"],
		"recent_non_easy_levels": decoded_batch["levels"],
	}


static func _set_persisted_state(state: Dictionary, persist: bool) -> void:
	GameState.set_gamble_user_value(int(state["value"]), false)
	GameState.set_gamble_user_early_l1_l20_bits(state["early_l1_l20_bits"], false)
	var encoded_batch: Array = _encode_non_easy_batch(
		state["recent_non_easy_invalid_bits"], state["recent_non_easy_levels"]
	)
	GameState.set_gamble_user_recent_hard_invalid_bits(encoded_batch, false)
	var update_level: String = str(state["gamble_update_level"])
	(
		GameState
		. set_persisted_user_tag(
			UPDATE_LEVEL_TAG_KEY,
			"" if update_level == _UPDATE_LEVEL_UNSET else update_level,
			false,
		)
	)
	if persist:
		GameState.persist_user_tag_state()


static func _decode_non_easy_batch(stored_batch: Array) -> Dictionary:
	var invalid_bits: Array = []
	var levels: Array = []
	if stored_batch.is_empty():
		return {
			"invalid_bits": invalid_bits,
			"levels": levels,
			"legacy_hard_invalid_bits": [],
		}
	for entry: Variant in stored_batch:
		if not (entry is Dictionary):
			return {
				"invalid_bits": [],
				"levels": [],
				"legacy_hard_invalid_bits": stored_batch.duplicate(),
			}
		var item: Dictionary = entry
		if (
			int(item.get("version", 0)) != _NON_EASY_BATCH_VERSION
			or not item.has("invalid")
			or not (item["invalid"] is bool)
			or not item.has("level")
			or not (item["level"] is int)
		):
			push_warning("[gamble_user] invalid persisted non-easy batch, reset")
			return {
				"invalid_bits": [],
				"levels": [],
				"legacy_hard_invalid_bits": [],
			}
		invalid_bits.append(bool(item["invalid"]))
		levels.append(int(item["level"]))
	return {
		"invalid_bits": invalid_bits,
		"levels": levels,
		"legacy_hard_invalid_bits": [],
	}


static func _encode_non_easy_batch(invalid_bits: Array, levels: Array) -> Array:
	if invalid_bits.size() != levels.size():
		push_warning("[gamble_user] refuse to persist mismatched non-easy batch")
		return []
	var encoded_batch: Array = []
	for index: int in invalid_bits.size():
		(
			encoded_batch
			. append(
				{
					"version": _NON_EASY_BATCH_VERSION,
					"invalid": bool(invalid_bits[index]),
					"level": int(levels[index]),
				}
			)
		)
	return encoded_batch


static func _duplicate_array(value: Variant) -> Array:
	return value.duplicate() if value is Array else []


static func _write_value(value: int) -> void:
	UniKitManager.add_local_tag(LOCAL_TAG_KEY, str(value))
	print("[is_gamble_user] write value=%d" % value)


static func _write_update_level(value: String) -> void:
	UniKitManager.add_local_tag(UPDATE_LEVEL_TAG_KEY, value)
	print("[gamble_update_level] write value=%s" % value)


static func _all_true(values: Array) -> bool:
	for value: Variant in values:
		if not bool(value):
			return false
	return true


static func _log_update(
	result: Dictionary,
	level_num: int,
	this_session_rank: int,
	this_session_diffi: int,
	invalid_sign_total: int
) -> void:
	var early_bits_log: String = ""
	if bool(result["pushed_early"]):
		var early_cleared_suffix: String = (
			" → CLEARED" if bool(result["buffer_cleared"]) and level_num == 20 else ""
		)
		early_bits_log = (
			" | l1_l20: size=%d→%d%s"
			% [
				int(result["early_before_size"]),
				int(result["early_post_size"]),
				early_cleared_suffix,
			]
		)
	var non_easy_bits_log: String = ""
	if bool(result["pushed_non_easy"]):
		var non_easy_cleared_suffix: String = (
			" → CLEARED" if bool(result["buffer_cleared"]) and level_num != 20 else ""
		)
		non_easy_bits_log = (
			" | non_easy: %s/%s → %s/%s%s"
			% [
				str(result["non_easy_before_bits"]),
				str(result["non_easy_before_levels"]),
				str(result["non_easy_post_bits"]),
				str(result["non_easy_post_levels"]),
				non_easy_cleared_suffix,
			]
		)
	var batch_reset_log: String = " | RESET_MISMATCH" if bool(result["batch_reset"]) else ""
	var skipped_log: String = ""
	var skipped_reason: String = str(result["skipped_reason"])
	if not skipped_reason.is_empty():
		skipped_log = " | SKIPPED: %s" % skipped_reason
	print(
		(
			"[LEVEL.diff_difficulty] pipeline lv=%d rank=%d diffi=%d invalid_sign_total=%d%s%s%s | tag_trigger=%s%s tag=%d update_level=%s"
			% [
				level_num,
				this_session_rank,
				this_session_diffi,
				invalid_sign_total,
				early_bits_log,
				non_easy_bits_log,
				batch_reset_log,
				str(result["trigger"]),
				skipped_log,
				int(result["value"]),
				str(result["gamble_update_level"]),
			]
		)
	)
