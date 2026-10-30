## Meowdoku 的存档结构和一次性旧档导入；旧文件只读保留，新业务只写 core_a/core_b。
class_name MeowdokuStore
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
const FileStore = preload("res://scripts/framework/storage/save_store.gd")
const CoreStore = preload("res://scripts/framework/storage/local_core_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const SCHEMA: int = 1
const PROFILE_TYPES := {
	"current_level": TYPE_INT,
	"tutorial_done": TYPE_BOOL,
	"current_strategy": TYPE_INT,
	"consecutive_clean_wins": TYPE_INT,
	"last_level_clean_win": TYPE_BOOL,
	"consecutive_fails": TYPE_INT,
	"consecutive_retry_levels": TYPE_INT,
	"retry_tracking_strategy": TYPE_INT,
	"bank_progress": TYPE_DICTIONARY,
	"main_bank_progress": TYPE_DICTIONARY,
	"lkmod_progress": TYPE_DICTIONARY,
	"has_shown_rate_us": TYPE_BOOL,
	"has_used_revive_free": TYPE_BOOL,
	"warn_life_shown": TYPE_BOOL,
	"life_plus_first_done": TYPE_BOOL,
	"daily_index": TYPE_INT,
	"daily_completed_date": TYPE_STRING,
	"max_daily_date": TYPE_STRING,
	"daily_elapsed_sec": TYPE_INT,
	"daily_beat_percent": TYPE_FLOAT,
	"daily_best_beat_percent": TYPE_FLOAT,
	"daily_started_date": TYPE_STRING,
	"daily_first_easy_date": TYPE_STRING,
	"game_total_stats": TYPE_DICTIONARY,
	"main_game_total_stats": TYPE_DICTIONARY,
	"daily_game_total_stats": TYPE_DICTIONARY,
	"main_game_round_stats": TYPE_DICTIONARY,
	"daily_game_round_stats": TYPE_DICTIONARY,
	"main_game_id": TYPE_STRING,
	"daily_game_id": TYPE_STRING,
	"tool_locate": TYPE_INT,
	"tool_hint": TYPE_INT,
	"tool_undo": TYPE_INT,
	"last_splash_date": TYPE_STRING,
	"apply_locale": TYPE_STRING,
	"is_first_session": TYPE_BOOL,
	"last_first_level_date": TYPE_STRING,
	"music_on": TYPE_BOOL,
	"music_user_modified": TYPE_BOOL,
	"sound_on": TYPE_BOOL,
	"vibration_on": TYPE_BOOL,
	"people_on": TYPE_BOOL,
	"has_used_tool": TYPE_BOOL,
	"prop_highlight_shown": TYPE_BOOL,
	"push_ask_count": TYPE_INT,
	"retry_puzzle_level": TYPE_INT,
	"retry_puzzle_params": TYPE_DICTIONARY,
	"has_shown_att_guide": TYPE_BOOL,
	"interstitial_unlocked": TYPE_BOOL,
	"banner_unlocked": TYPE_BOOL,
	"has_shown_draft_onboarding": TYPE_BOOL,
	"auto_mark_tutorial_done": TYPE_BOOL,
	"rule_info_bar_collapsed": TYPE_BOOL,
	"grt_level_d90_reported": TYPE_ARRAY,
	"grt_reported_events": TYPE_ARRAY,
	"first_open_time_ms": TYPE_INT,
	"recent_puzzles": TYPE_ARRAY,
	"endgame_snapshot": TYPE_DICTIONARY,
	"session_count": TYPE_INT,
	"today_session_count": TYPE_INT,
	"last_day_session_count": TYPE_INT,
	"active_days": TYPE_INT,
	"today_played_count": TYPE_INT,
	"today_active_sec": TYPE_INT,
	"total_active_sec": TYPE_INT,
	"today_date": TYPE_STRING,
	"pending_rewards": TYPE_ARRAY,
	"in_flight_awards": TYPE_ARRAY,
	"reward_history_ts": TYPE_ARRAY,
	"restored_today_count": TYPE_INT,
	"daily_auto_mark_enabled": TYPE_BOOL,
	"daily_auto_mark_free_consumed": TYPE_BOOL,
	"saved_game_auto_mark": TYPE_INT,
	"last_win_beat_percent": TYPE_FLOAT,
	"help_last_open_time": TYPE_INT,
	"install_version": TYPE_STRING,
}
const STREAK_TYPES := {"current_streak": TYPE_INT, "best_streak": TYPE_INT, "last_checkin_date": TYPE_STRING, "streak_start_weekday": TYPE_INT, "reward_cycle_day": TYPE_INT, "last_group": TYPE_INT, "pending_switch_page": TYPE_INT}
const ENDGAME_KEYS := {
	"main_game_total_stats": "main_total", "daily_game_total_stats": "daily_total",
	"main_game_round_stats": "main_round", "daily_game_round_stats": "daily_round",
	"main_game_id": "main_id", "daily_game_id": "daily_id",
}

var core: RefCounted
var files: RefCounted


func _init(directory: String, password: String) -> void:
	files = FileStore.new(password, directory, true, directory.path_join("core_a.cfg"), directory.path_join("core_b.cfg"), directory.path_join("core_flag.txt"))
	core = CoreStore.new(files, SCHEMA, validate_state)


func open(default_profile: ConfigFile, legacy_player: RefCounted, legacy_endgame: RefCounted, legacy_streak_path: String) -> Dictionary:
	var existing: Dictionary = files.load_result()
	if existing.get("status") != "missing":
		return core.open()
	var player: Dictionary = legacy_player.load_result()
	var endgame: Dictionary = legacy_endgame.load_result()
	for result in [player, endgame]:
		if not result.get("ok", false) and result.get("status") != "missing":
			return result
	var streak: Dictionary = {}
	if FileAccess.file_exists(legacy_streak_path):
		var cfg := ConfigFile.new()
		if cfg.load(legacy_streak_path) != OK:
			return Result.failure("corrupt_legacy_streak", "旧签到存档损坏，未创建新档", {"status": "corrupt_legacy_streak"})
		if cfg.has_section("streak"):
			for key in cfg.get_section_keys("streak"):
				streak[key] = cfg.get_value("streak", key)
	var source: ConfigFile = player.get("config", default_profile)
	var legacy_error := validate_legacy(source, endgame.get("config") as ConfigFile, streak)
	if not legacy_error.is_empty():
		return Result.failure("invalid_legacy", legacy_error, {"status": "invalid_legacy"})
	var initial := from_legacy(source, endgame.get("config") as ConfigFile, streak)
	# 已有的旧切组弹窗也保留礼包资格，之后只按此 uid 领取。
	if int(streak.get("pending_switch_page", 0)) == 1:
		initial.award_sequence += 1
		var uid: int = int(initial.award_sequence)
		initial.pending_awards.append({"uid": uid, "items": [{"kind": "hint", "count": 2}, {"kind": "locate", "count": 2}], "display_type": 0, "reason": "switch_group", "bonus_reason": "", "doubled": false})
		initial.features.streak["switch_award_uid"] = uid
	initial["migration"] = {"legacy_imported": player.get("ok", false) or endgame.get("ok", false) or not streak.is_empty()}
	return core.open(initial, true)


## 当前产品字段的编码边界；不创建新存档、不迁移奖励，也不重置其他核心分区。
static func capture_profile(profile_cfg: ConfigFile) -> Dictionary:
	var profile: Dictionary = {}
	if profile_cfg.has_section("progress"):
		for key in profile_cfg.get_section_keys("progress"):
			profile[key] = profile_cfg.get_value("progress", key)
	var inventory := {"locate": profile.get("tool_locate", 5), "hint": profile.get("tool_hint", 5), "undo": profile.get("tool_undo", 3)}
	for kind in inventory:
		profile.erase("tool_" + kind)
	profile.erase("endgame_snapshot")
	for key in ENDGAME_KEYS:
		profile.erase(key)
	profile.erase("in_flight_awards")
	# ConfigFile 保留数组/字典引用；候选必须拥有自己的嵌套容器，业务暂存失败才不会污染活字段。
	return {"profile": profile.duplicate(true), "inventory": inventory}


## 只在核心存档不存在时使用：将旧文件及其独立残局、签到合并成初始核心状态。
static func from_legacy(profile_cfg: ConfigFile, endgame_cfg: ConfigFile, streak: Dictionary) -> Dictionary:
	var fields: Dictionary = capture_profile(profile_cfg)
	var snapshot: Dictionary = profile_cfg.get_value("progress", "endgame_snapshot", {})
	var stats: Dictionary = {}
	for key in ENDGAME_KEYS:
		stats[ENDGAME_KEYS[key]] = profile_cfg.get_value("progress", key, "" if key.ends_with("_id") else {})
	if endgame_cfg != null:
		snapshot = endgame_cfg.get_value("snapshot", "data", {})
		for key in ENDGAME_KEYS:
			var stat_key: String = ENDGAME_KEYS[key]
			stats[stat_key] = endgame_cfg.get_value("stats", stat_key, stats[stat_key])
	var awards: Array = profile_cfg.get_value("progress", "in_flight_awards", []).duplicate(true)
	var sequence: int = 0
	for entry: Dictionary in awards:
		sequence = maxi(sequence, int(entry.get("uid", 0)))
	return {
		"product": "meowdoku", "profile": fields.profile, "inventory": fields.inventory,
		"endgame": {"snapshot": snapshot, "stats": stats}, "features": {"streak": streak.duplicate(true)},
		"award_sequence": sequence, "pending_awards": awards, "claims": {}, "round_services": {},
	}


static func profile_config(state: Dictionary) -> ConfigFile:
	var cfg := ConfigFile.new()
	var profile: Dictionary = state.get("profile", {})
	for key in profile:
		cfg.set_value("progress", key, profile[key])
	for kind in state.get("inventory", {}):
		cfg.set_value("progress", "tool_" + kind, state.inventory[kind])
	cfg.set_value("progress", "in_flight_awards", state.get("pending_awards", []).duplicate(true))
	var endgame: Dictionary = state.get("endgame", {})
	cfg.set_value("progress", "endgame_snapshot", endgame.get("snapshot", {}).duplicate(true))
	for key in ENDGAME_KEYS:
		cfg.set_value("progress", key, endgame.get("stats", {}).get(ENDGAME_KEYS[key], "" if key.ends_with("_id") else {}))
	return cfg


static func validate_state(state: Dictionary) -> String:
	if state.get("product") != "meowdoku":
		return "存档 product 不匹配"
	for key in ["profile", "inventory", "endgame", "features", "claims", "round_services"]:
		if not state.get(key) is Dictionary:
			return "存档缺少字典: " + key
	for kind in ["locate", "hint", "undo"]:
		if typeof(state.inventory.get(kind)) != TYPE_INT or state.inventory[kind] < 0:
			return "库存无效: " + kind
	if typeof(state.get("award_sequence")) != TYPE_INT or state.award_sequence < 0:
		return "奖励序号无效"
	if not state.get("pending_awards") is Array:
		return "奖励队列无效"
	for key in state.profile:
		if PROFILE_TYPES.has(key) and not _matches_type(state.profile[key], PROFILE_TYPES[key]):
			return "玩家字段类型不符: " + key
	for key in state.claims:
		if typeof(state.claims[key]) != TYPE_INT or state.claims[key] < 0 or state.claims[key] > state.award_sequence:
			return "奖励业务凭证无效"
	var seen: Dictionary = {}
	for entry in state.pending_awards:
		if not entry is Dictionary or typeof(entry.get("uid")) != TYPE_INT:
			return "奖励流水无效"
		if entry.uid <= 0 or entry.uid > state.award_sequence or seen.has(entry.uid):
			return "奖励流水重复或越界"
		seen[entry.uid] = true
		if not entry.get("items") is Array:
			return "奖励条目数组无效"
		var error := Economy.validate_items(entry.items, state.inventory)
		if not error.is_empty():
			return error
	if not state.endgame.get("snapshot") is Dictionary or not state.endgame.get("stats") is Dictionary:
		return "残局结构无效"
	if not state.features.get("streak") is Dictionary:
		return "签到结构无效"
	if state.has("round_runtime"):
		if not state.round_runtime is Dictionary:
			return "局内 DDA 状态无效"
		for key in state.round_runtime:
			if typeof(state.round_runtime[key]) != TYPE_BOOL:
				return "局内 DDA 标记必须为布尔值"
	# 清档与产品结算在玩法模块验证之前读取这些外壳，必须先保证可安全消费的基础形状。
	for key: Variant in state.round_services:
		var record: Variant = state.round_services[key]
		if not key is String or not record is Dictionary:
			return "对局记录必须为命名字典"
		var record_error := _validate_present_fields(record, {
			"snapshot": TYPE_DICTIONARY, "start_context": TYPE_DICTIONARY,
			"last_receipt": TYPE_DICTIONARY, "settlement": TYPE_DICTIONARY,
			"module_id": TYPE_STRING, "mode_id": TYPE_STRING, "round_id": TYPE_STRING,
			"status": TYPE_STRING, "start_sequence": TYPE_INT, "last_sequence": TYPE_INT,
		})
		if not record_error.is_empty():
			return "对局记录 " + str(key) + "/" + record_error
		if key.begins_with("doku/"):
			var snapshot: Dictionary = record.get("snapshot", {})
			var snapshot_error := _validate_present_fields(snapshot, {"content": TYPE_DICTIONARY, "attempt_sequence": TYPE_INT})
			if not snapshot_error.is_empty():
				return "Doku 快照字段类型不符: " + snapshot_error
			var content_error := _validate_present_fields(snapshot.get("content", {}), {"level": TYPE_INT, "gameplay_policy": TYPE_DICTIONARY, "level_definition": TYPE_DICTIONARY})
			if not content_error.is_empty():
				return "Doku 冻结内容类型不符: " + content_error
	if state.has("product_settlements"):
		if not state.product_settlements is Dictionary:
			return "结算记录结构无效"
		for key: Variant in state.product_settlements:
			var record: Variant = state.product_settlements[key]
			if not key is String or not record is Dictionary:
				return "结算条目必须为命名字典"
			var receipt_error := _validate_present_fields(record, {"round_id": TYPE_STRING, "last_attempt": TYPE_INT, "receipt": TYPE_DICTIONARY, "level": TYPE_INT})
			if not receipt_error.is_empty():
				return "结算记录 " + str(key) + "/" + receipt_error
	for key in state.features.streak:
		if STREAK_TYPES.has(key) and not _matches_type(state.features.streak[key], STREAK_TYPES[key]):
			return "签到字段类型不符: " + key
	for key in ENDGAME_KEYS:
		var stat_key: String = ENDGAME_KEYS[key]
		if not _matches_type(state.endgame.stats.get(stat_key, "" if key.ends_with("_id") else {}), PROFILE_TYPES[key]):
			return "统计字段类型不符: " + key
	return ""


static func validate_legacy(profile_cfg: ConfigFile, endgame_cfg: ConfigFile, streak: Dictionary) -> String:
	if profile_cfg.has_section("progress"):
		for key in profile_cfg.get_section_keys("progress"):
			if PROFILE_TYPES.has(key) and not _matches_type(profile_cfg.get_value("progress", key), PROFILE_TYPES[key]):
				return "旧玩家字段类型不符: " + key
	# from_legacy 需要先读取 uid 计算发号水位；必须在类型化投影之前拒绝坏元素。
	for entry: Variant in profile_cfg.get_value("progress", "in_flight_awards", []):
		if not entry is Dictionary or typeof(entry.get("uid")) != TYPE_INT:
			return "旧奖励流水或序号类型无效"
	if endgame_cfg != null:
		if not endgame_cfg.get_value("snapshot", "data", {}) is Dictionary:
			return "旧残局快照无效"
		for key in ENDGAME_KEYS:
			var stat_key: String = ENDGAME_KEYS[key]
			if not _matches_type(endgame_cfg.get_value("stats", stat_key, "" if key.ends_with("_id") else {}), PROFILE_TYPES[key]):
				return "旧统计字段类型不符: " + key
	for key in streak:
		if STREAK_TYPES.has(key) and not _matches_type(streak[key], STREAK_TYPES[key]):
			return "旧签到字段类型不符: " + key
	return ""


## 只检查消费者直接读取的已存在字段；完整玩法与业务有效性仍由各自服务判断。
static func _validate_present_fields(values: Dictionary, types: Dictionary) -> String:
	for field: String in types:
		if values.has(field) and not _matches_type(values[field], int(types[field])):
			return field
	return ""


static func _matches_type(value: Variant, expected: int) -> bool:
	return typeof(value) == expected or (expected == TYPE_FLOAT and typeof(value) == TYPE_INT)
