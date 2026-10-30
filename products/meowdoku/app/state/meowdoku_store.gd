## Meowdoku 的存档结构和一次性旧档导入；旧文件只读保留，新业务只写 core_a/core_b。
class_name MeowdokuStore
extends RefCounted

const Result = preload("res://scripts/framework/operation_result.gd")
const FileStore = preload("res://scripts/framework/storage/save_store.gd")
const CoreStore = preload("res://scripts/framework/storage/local_core_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const StateFields = preload("res://products/meowdoku/app/state/meowdoku_state_fields.gd")
const AwardPolicy = preload("res://products/meowdoku/app/state/meowdoku_award_policy.gd")
const SCHEMA: int = 2
const PROFILE_TYPES: Dictionary = StateFields.PROFILE_TYPES
const INVENTORY_DEFAULTS := {"locate": 5, "hint": 5, "undo": 3, "mouse": 2, "draft": 5}
const FEATURE_IDS := ["streak", "identity", "purchase", "rank_activity", "robots", "account", "recommendation", "data_sync", "peekaboo"]
const STREAK_TYPES := {"current_streak": TYPE_INT, "best_streak": TYPE_INT, "last_checkin_date": TYPE_STRING, "streak_start_weekday": TYPE_INT, "reward_cycle_day": TYPE_INT, "last_group": TYPE_INT, "pending_switch_page": TYPE_INT}
const ENDGAME_KEYS := {
	"main_game_total_stats": "main_total", "daily_game_total_stats": "daily_total",
	"main_game_round_stats": "main_round", "daily_game_round_stats": "daily_round",
	"main_game_id": "main_id", "daily_game_id": "daily_id",
	"main_solution_steps": "main_steps", "daily_solution_steps": "daily_steps",
}

var core: RefCounted
var _password: String
var files: RefCounted


func _init(directory: String, password: String) -> void:
	_password = password
	files = FileStore.new(password, directory, true, directory.path_join("core_a.cfg"), directory.path_join("core_b.cfg"), directory.path_join("core_flag.txt"))
	core = CoreStore.new(files, SCHEMA, validate_state, migrate_schema)


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
	var imported := _read_legacy_features(legacy_streak_path.get_base_dir())
	if not imported.get("ok", false):
		return imported
	initial.features.merge(imported.features, true)
	initial["legacy_extensions"] = imported.extensions
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
	var inventory: Dictionary = {}
	for kind: String in INVENTORY_DEFAULTS:
		inventory[kind] = profile.get("tool_" + kind, INVENTORY_DEFAULTS[kind])
	for kind in inventory:
		profile.erase("tool_" + kind)
	profile.erase("endgame_snapshot")
	profile.erase("daily_endgame_snapshot")
	for key in ENDGAME_KEYS:
		profile.erase(key)
	profile.erase("in_flight_awards")
	# ConfigFile 保留数组/字典引用；候选必须拥有自己的嵌套容器，业务暂存失败才不会污染活字段。
	return {"profile": profile.duplicate(true), "inventory": inventory}


## 只在核心存档不存在时使用：将旧文件及其独立残局、签到合并成初始核心状态。
static func from_legacy(profile_cfg: ConfigFile, endgame_cfg: ConfigFile, streak: Dictionary) -> Dictionary:
	var fields: Dictionary = capture_profile(profile_cfg)
	_migrate_color_challenge_quiet_rule(fields.profile)
	var snapshot: Dictionary = profile_cfg.get_value("progress", "endgame_snapshot", {})
	var daily_snapshot: Dictionary = profile_cfg.get_value("progress", "daily_endgame_snapshot", {})
	var stats: Dictionary = {}
	for key in ENDGAME_KEYS:
		stats[ENDGAME_KEYS[key]] = profile_cfg.get_value("progress", key, "" if key.ends_with("_id") else {})
	if endgame_cfg != null:
		snapshot = endgame_cfg.get_value("snapshot", "data", {})
		daily_snapshot = endgame_cfg.get_value("daily_snapshot", "data", {})
		for key in ENDGAME_KEYS:
			var stat_key: String = ENDGAME_KEYS[key]
			stats[stat_key] = endgame_cfg.get_value("stats", stat_key, stats[stat_key])
	var awards: Array = profile_cfg.get_value("progress", "in_flight_awards", []).duplicate(true)
	var sequence: int = 0
	for entry: Dictionary in awards:
		sequence = maxi(sequence, int(entry.get("uid", 0)))
	return {
		"product": "meowdoku", "profile": fields.profile, "inventory": fields.inventory,
		"endgame": {"snapshot": snapshot, "daily_snapshot": daily_snapshot, "stats": stats}, "features": _feature_defaults(streak),
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
	cfg.set_value("progress", "daily_endgame_snapshot", endgame.get("daily_snapshot", {}).duplicate(true))
	for key in ENDGAME_KEYS:
		cfg.set_value("progress", key, endgame.get("stats", {}).get(ENDGAME_KEYS[key], "" if key.ends_with("_id") else {}))
	return cfg


static func validate_state(state: Dictionary) -> String:
	if state.get("product") != "meowdoku":
		return "存档 product 不匹配"
	for key in ["profile", "inventory", "endgame", "features", "claims", "round_services"]:
		if not state.get(key) is Dictionary:
			return "存档缺少字典: " + key
	for kind: String in INVENTORY_DEFAULTS:
		if typeof(state.inventory.get(kind)) != TYPE_INT or state.inventory[kind] < 0:
			return "库存无效: " + kind
	if typeof(state.get("award_sequence")) != TYPE_INT or state.award_sequence < 0:
		return "奖励序号无效"
	if not state.get("pending_awards") is Array:
		return "奖励队列无效"
	for key in state.profile:
		if PROFILE_TYPES.has(key) and not _matches_type(state.profile[key], PROFILE_TYPES.get(key, TYPE_DICTIONARY)):
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
		var error := AwardPolicy.validate_award(entry.items, state)
		if not error.is_empty():
			return error
	if not state.endgame.get("snapshot") is Dictionary or not state.endgame.get("stats") is Dictionary or not state.endgame.get("daily_snapshot", {}) is Dictionary:
		return "残局结构无效"
	if not state.features.get("streak") is Dictionary:
		return "签到结构无效"
	for feature: String in FEATURE_IDS:
		if state.features.has(feature) and not state.features[feature] is Dictionary:
			return "业务存档结构无效: " + feature
	if state.has("round_runtime"):
		if not state.round_runtime is Dictionary:
			return "局内 DDA 状态无效"
		for key in state.round_runtime:
			if StateFields.RUNTIME_TYPES.has(key) and not _matches_type(state.round_runtime[key], StateFields.RUNTIME_TYPES[key]):
				return "局内状态类型不符: " + str(key)
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
		if not _matches_type(state.endgame.stats.get(stat_key, "" if key.ends_with("_id") else {}), PROFILE_TYPES.get(key, TYPE_DICTIONARY)):
			return "统计字段类型不符: " + key
	return ""


static func validate_legacy(profile_cfg: ConfigFile, endgame_cfg: ConfigFile, streak: Dictionary) -> String:
	if profile_cfg.has_section("progress"):
		for key in profile_cfg.get_section_keys("progress"):
			if PROFILE_TYPES.has(key) and not _matches_type(profile_cfg.get_value("progress", key), PROFILE_TYPES.get(key, TYPE_DICTIONARY)):
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
			if not _matches_type(endgame_cfg.get_value("stats", stat_key, "" if key.ends_with("_id") else {}), PROFILE_TYPES.get(key, TYPE_DICTIONARY)):
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


static func _feature_defaults(streak: Dictionary = {}) -> Dictionary:
	var features: Dictionary = {}
	for id: String in FEATURE_IDS:
		features[id] = {}
	features["streak"] = streak.duplicate(true)
	return features


## 只接受已知的 1 -> 2 升级。旧核心权威状态、对局与幂等凭证全部保留。
static func migrate_schema(source_schema: int, target_schema: int, source: Dictionary) -> Dictionary:
	if source_schema != 1 or target_schema != SCHEMA:
		return Result.failure("schema_mismatch", "没有该 schema 的显式迁移")
	var state: Dictionary = source.duplicate(true)
	if state.get("profile") is Dictionary:
		_migrate_color_challenge_quiet_rule(state.profile)
	if state.get("inventory") is Dictionary:
		for kind: String in INVENTORY_DEFAULTS:
			if not state.inventory.has(kind):
				state.inventory[kind] = INVENTORY_DEFAULTS[kind]
	if state.get("endgame") is Dictionary:
		if not state.endgame.has("daily_snapshot"):
			state.endgame["daily_snapshot"] = {}
		if state.endgame.get("stats") is Dictionary:
			for key: String in ["main_steps", "daily_steps"]:
				if not state.endgame.stats.has(key):
					state.endgame.stats[key] = {}
	if state.get("features") is Dictionary:
		for id: String in FEATURE_IDS:
			if not state.features.has(id):
				state.features[id] = {}
	var previous_migration: Variant = state.get("migration", {})
	if not previous_migration is Dictionary:
		return Result.failure("invalid_state", "迁移记录必须为字典")
	state["migration"] = previous_migration.duplicate(true)
	state.migration["core_schema_from"] = source_schema
	return Result.success({"state": state})


## 旧模块文件只读导入；损坏存在的文件必须中止，不能冒充首次安装丢弃。
func _read_legacy_features(root_path: String) -> Dictionary:
	var features: Dictionary = {}
	var extensions: Dictionary = {}
	var specs := {
		"identity": ["profile.cfg", "profile"],
		"purchase": ["purchase.cfg", "purchase"],
		"rank_activity": ["rank_activity.cfg", "rank_activity"],
		"account": ["account.cfg", "account"],
		"peekaboo": ["peekaboo.cfg", "peekaboo"],
		"robots": ["robots.cfg", ""],
		"recommendation": ["save_store/rec_state.cfg", ""],
		"data_sync": ["data_sync_state.cfg", "sync"],
	}
	for id: String in specs:
		var spec: Array = specs[id]
		var path: String = root_path.path_join(spec[0])
		if not FileAccess.file_exists(path):
			continue
		var cfg := ConfigFile.new()
		var error: int = cfg.load_encrypted_pass(path, _password) if id == "recommendation" else cfg.load(path)
		if error != OK:
			return Result.failure("corrupt_legacy_feature", "旧业务存档无法读取: " + id, {"status": "corrupt_legacy_feature"})
		var sections: Dictionary = {}
		for section: String in cfg.get_sections():
			sections[section] = {}
			for key: String in cfg.get_section_keys(section):
				sections[section][key] = cfg.get_value(section, key)
		extensions[id] = sections.duplicate(true)
		if id == "identity":
			var data: Variant = sections.get("profile", {}).get("data", {})
			if not data is Dictionary:
				return Result.failure("invalid_legacy_feature", "旧资料不是字典", {"status": "invalid_legacy_feature"})
			features[id] = data.duplicate(true)
		elif id == "robots":
			var pools: Dictionary = {}
			for section: String in sections:
				var data: Variant = sections[section].get("data", {})
				if not data is Dictionary:
					return Result.failure("invalid_legacy_feature", "旧机器人池不是字典", {"status": "invalid_legacy_feature"})
				pools[section] = data.duplicate(true)
			features[id] = {"pools": pools}
		elif id == "recommendation":
			features[id] = {"history": sections.get("history", {}).duplicate(true), "queue": sections.get("queue", {}).duplicate(true)}
		else:
			features[id] = sections.get(spec[1], {}).duplicate(true)
	return Result.success({"features": features, "extensions": extensions})


## 1.22 弃用旧颜色挑战防打扰锁；仅显式导入/升级时迁移，不在每次发布时改写候选。
static func _migrate_color_challenge_quiet_rule(profile: Dictionary) -> void:
	if bool(profile.get("cc_deferred_used", false)) or bool(profile.get("cc_disabled", false)):
		profile["cc_deferred_used"] = false
		profile["cc_disabled"] = false
		profile["cc_defer_until"] = 0
