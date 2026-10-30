extends SceneTree

const FileStore = preload("res://scripts/framework/storage/save_store.gd")
const Core = preload("res://scripts/framework/storage/local_core_store.gd")
const Store = preload("res://products/meowdoku/app/state/meowdoku_store.gd")
const Economy = preload("res://scripts/framework/application/economy_service.gd")
const Policy = preload("res://products/meowdoku/app/state/meowdoku_award_policy.gd")
const PASSWORD := "isolated-test-password"
var checks: int = 0
var failures: int = 0
var test_root: String

func _initialize() -> void:
	if not ProjectSettings.globalize_path("res://").contains("/doku-validation-"):
		quit(2)
		return
	test_root = ProjectSettings.globalize_path("res://fixtures")
	DirAccess.make_dir_recursive_absolute(test_root)
	_test_migration()
	_test_mixed_awards()
	_test_profile_roundtrip()
	_test_all_fields()
	_test_legacy_features()
	_test_plain_store()
	print("122 BUSINESS STORAGE TESTS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_migration() -> void:
	var directory := test_root.path_join("migration")
	DirAccess.make_dir_recursive_absolute(directory)
	var files := FileStore.new(PASSWORD, directory, true, directory.path_join("a"), directory.path_join("b"), directory.path_join("flag"))
	var source := _state()
	source.inventory.erase("mouse")
	source.inventory.erase("draft")
	source.endgame.erase("daily_snapshot")
	source.features = {"streak": {"last_checkin_date": "2026-10-30"}}
	source.profile["unknown_extension"] = {"retained": [1, 2]}
	source.claims["old_claim"] = 0
	var cfg := ConfigFile.new()
	cfg.set_value("core", "schema_version", 1)
	cfg.set_value("core", "state", source)
	_check(files.commit_config(cfg, 0).ok, "prepare schema 1")
	var upgraded := Core.new(files, Store.SCHEMA, Store.validate_state, Store.migrate_schema)
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not upgraded.open().ok and not upgraded.is_open(), "failed migration does not open or publish")
	_check(files.load_result().revision == 1, "failed migration preserves revision")
	files.set_fault_injector_for_tests(Callable())
	_check(upgraded.open().ok and upgraded.revision() == 2, "migration retries once")
	var saved: Dictionary = upgraded.snapshot()
	_check(saved.profile.unknown_extension.retained == [1, 2] and saved.claims.has("old_claim"), "migration keeps unknown fields and claims")
	_check(saved.inventory.mouse == 2 and saved.inventory.draft == 5, "adds new tools")
	_check(saved.features.streak.last_checkin_date == "2026-10-30" and saved.features.has("identity"), "adds features without losing old streak")
	var reopened := Core.new(files, Store.SCHEMA, Store.validate_state, Store.migrate_schema)
	_check(reopened.open().ok and reopened.revision() == 2, "mixed old/new schema slots reopen without migration replay")
	cfg.set_value("core", "schema_version", 99)
	_check(files.commit_config(cfg, 2).ok, "prepare unknown future schema")
	var refused := Core.new(files, Store.SCHEMA, Store.validate_state, Store.migrate_schema)
	_check(not refused.open().ok and not refused.is_open(), "unknown future schema cannot fall back and overwrite")

func _test_mixed_awards() -> void:
	var directory := test_root.path_join("awards")
	DirAccess.make_dir_recursive_absolute(directory)
	var files := FileStore.new(PASSWORD, directory, true, directory.path_join("a"), directory.path_join("b"), directory.path_join("flag"))
	var core := Core.new(files, Store.SCHEMA, Store.validate_state, Store.migrate_schema)
	_check(core.open(_state(), true).ok, "open award core")
	var economy := Economy.new(core, Policy.new())
	var award: Dictionary = economy.register_award([{"kind": "mouse", "count": 2}, {"category": 1, "frame_id": 100, "count": 1}], 2, "rank", "rank_bonus", "rank/1")
	_check(award.ok, "mixed tool/frame registers")
	_check(economy.double_award(award.uid).ok, "doubling entitlement persists")
	var before: Dictionary = core.snapshot()
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	_check(not economy.claim_award(award.uid).ok and core.snapshot() == before, "failure leaves pending and both assets untouched")
	files.set_fault_injector_for_tests(Callable())
	_check(economy.claim_award(award.uid).ok, "mixed award retries atomically")
	var after: Dictionary = core.snapshot()
	_check(after.inventory.mouse == 6 and after.features.identity.owned_frames[0].acquired_count == 1, "tools double and frame grants once")
	_check(after.pending_awards.is_empty(), "pending removed with both grants")
	_check(economy.claim_award(award.uid).status == "already_applied", "reward replay is idempotent")
	_check(economy.register_award([{"kind": "mouse", "count": 2}], 2, "rank", "", "rank/1").duplicate, "business claim identity rejects re-registration")

func _test_profile_roundtrip() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "current_level", 31)
	cfg.set_value("progress", "home_companion_data", {"wins": {"test-game": true}, "candy_total": 20})
	cfg.set_value("progress", "elo_v2_attempt", {"puzzle_id": "fixture"})
	cfg.set_value("progress", "future_field", {"nested": [1, 2, 3]})
	cfg.set_value("progress", "tool_draft", 7)
	var endgame := ConfigFile.new()
	endgame.set_value("snapshot", "data", {"main": true})
	endgame.set_value("daily_snapshot", "data", {"daily": true})
	endgame.set_value("stats", "main_steps", {"step": 1})
	endgame.set_value("stats", "daily_steps", {"step": 2})
	var state := Store.from_legacy(cfg, endgame, {})
	_check(Store.validate_state(state).is_empty(), "complete additive legacy structure validates")
	var roundtrip := Store.profile_config(state)
	_check(roundtrip.get_value("progress", "future_field") == {"nested": [1, 2, 3]}, "unknown profile field round-trips")
	_check(state.endgame.daily_snapshot.daily and state.endgame.stats.daily_steps.step == 2, "daily board and solution steps preserved")
	_check(state.inventory.draft == 7 and state.profile.home_companion_data.candy_total == 20, "new inventory and companion state survive")

func _state() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "current_level", 1)
	return Store.from_legacy(cfg, null, {})

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _test_all_fields() -> void:
	var cfg := ConfigFile.new()
	var samples: Dictionary = {TYPE_INT: 3, TYPE_FLOAT: 1.25, TYPE_BOOL: true, TYPE_STRING: "fixture", TYPE_DICTIONARY: {"sentinel": [1, 2]}, TYPE_ARRAY: ["sentinel"], TYPE_PACKED_STRING_ARRAY: PackedStringArray(["sentinel"]), TYPE_VECTOR2I: Vector2i(2, 3)}
	for key: String in Store.PROFILE_TYPES:
		cfg.set_value("progress", key, samples[Store.PROFILE_TYPES[key]])
	cfg.set_value("progress", "in_flight_awards", [])
	var state: Dictionary = Store.from_legacy(cfg, null, {})
	# 旧 quiet 锁按 1.22 规则仅在导入时清除；schema2 的完整字段仍需逐项保真。
	_check(not state.profile.cc_deferred_used and not state.profile.cc_disabled and state.profile.cc_defer_until == 0, "legacy color quiet state migrates before first publication")
	for key: String in ["cc_deferred_used", "cc_disabled", "cc_defer_until"]:
		state.profile[key] = cfg.get_value("progress", key)
	_check(Store.PROFILE_TYPES.size() == 211, "source manifest contains all 211 persistent progress fields")
	_check(Store.validate_state(state).is_empty(), "all source typed fields validate together")
	var roundtrip: ConfigFile = Store.profile_config(state)
	for key: String in Store.PROFILE_TYPES:
		_check(roundtrip.get_value("progress", key, null) == cfg.get_value("progress", key), "complete field roundtrip: " + key)

func _test_legacy_features() -> void:
	var directory: String = test_root.path_join("legacy")
	DirAccess.make_dir_recursive_absolute(directory)
	var plain: Dictionary = {"profile.cfg": ["profile", {"data": {"nickname": "fixture", "owned_avatars": [101]}}], "purchase.cfg": ["purchase", {"vip_active": true, "daily_gift_date": "2026-10-29"}], "rank_activity.cfg": ["rank_activity", {"period_count": 7, "collect_total": 123}], "account.cfg": ["account", {"guest_reset_pending": true}], "peekaboo.cfg": ["peekaboo", {"claimed_date": "2026-10-29"}], "robots.cfg": ["pool_fixture", {"data": {"key": "pool_fixture", "future": [1, 2]}}], "data_sync_state.cfg": ["sync", {"remote_root": "{\"future\":42}"}]}
	for file: String in plain:
		var cfg := ConfigFile.new()
		var spec: Array = plain[file]
		for key: String in spec[1]:
			cfg.set_value(spec[0], key, spec[1][key])
		_check(cfg.save(directory.path_join(file)) == OK, "prepare legacy " + file)
	var product := Store.new(directory.path_join("save_store"), PASSWORD)
	var imported: Dictionary = product._read_legacy_features(directory)
	_check(imported.ok, "all scattered legacy features import")
	_check(imported.features.identity.nickname == "fixture" and imported.features.rank_activity.collect_total == 123, "identity and leaderboard preserve source values")
	_check(imported.features.account.guest_reset_pending and imported.features.peekaboo.claimed_date == "2026-10-29", "account and peekaboo preserve source values")
	_check(imported.features.robots.pools.pool_fixture.future == [1, 2], "robot pool extension retained")
	_check(FileAccess.file_exists(directory.path_join("profile.cfg")), "legacy import never removes source")
	var bad := FileAccess.open(directory.path_join("purchase.cfg"), FileAccess.WRITE)
	bad.store_string("[unclosed")
	bad.close()
	_check(not product._read_legacy_features(directory).ok, "corrupt existing legacy feature refuses empty defaults")

func _test_plain_store() -> void:
	var path: String = test_root.path_join("plain.cfg")
	var files := FileStore.plain_file(path)
	var cfg := ConfigFile.new()
	cfg.set_value("fixture", "value", 1)
	_check(files.save_config(cfg), "explicit plain adapter commits")
	var raw := ConfigFile.new()
	_check(raw.load(path) == OK and raw.get_value("fixture", "value") == 1, "plain adapter remains compatible with legacy ConfigFile reader")
	files.set_fault_injector_for_tests(func(phase: String) -> bool: return phase == "before_replace")
	cfg.set_value("fixture", "value", 2)
	_check(not files.save_config(cfg) and files.load_config().get_value("fixture", "value") == 1, "plain adapter failure preserves previous file")
