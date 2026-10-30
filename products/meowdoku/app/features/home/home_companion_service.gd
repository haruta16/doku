## 陪伴猫业务服务：衔接模型、GameState、奖励与云同步，把胜利和喂食结果持久化。
extends RefCounted

const System: GDScript = preload("res://products/meowdoku/app/features/home/core/home_companion_system.gd")

const EDITOR_EVENT_DATE_OVERRIDE: String = "2026-10-27"

const MOUSE_REWARD_COUNT: int = 2

static var _debug_satiety_decay_scale: float = 1.0

static var _debug_event_date: String = ""

static var _session_granted: Dictionary = {}

static var _stale_settled: bool = false


static func reset_session_for_test() -> void:
	_session_granted = {}
	_stale_settled = false


var clock: Callable


func current_time() -> int:
	return int(clock.call()) if clock.is_valid() else local_now()


static func debug_satiety_decay_scale() -> float:
	if not OS.has_feature("editor") or OS.has_feature("rel"):
		return 1.0
	return _debug_satiety_decay_scale


func set_debug_satiety_decay_scale(scale: float) -> bool:
	if not OS.has_feature("editor") or OS.has_feature("rel"):
		return false
	if not is_finite(scale) or scale < 0.0 or scale > 86400.0:
		return false
	if scale == _debug_satiety_decay_scale:
		return true
	var saved: Dictionary = GameState.get_home_companion_data()
	var system: System = System.new(saved)
	if bool(saved.get("satiety_active", false)):
		system.sync_satiety_mode(System.Mode.SATIETY, current_time(), debug_satiety_decay_scale())
		saved = system.snapshot()
	_debug_satiety_decay_scale = scale
	return GameState.set_home_companion_data(saved)


static func local_now() -> int:
	var calendar: Dictionary = Time.get_datetime_dict_from_system()
	return Time.get_unix_time_from_datetime_dict(calendar)


static func debug_event_date() -> String:
	return "" if OS.has_feature("rel") else _debug_event_date


static func set_debug_event_date(date_text: String) -> bool:
	if OS.has_feature("rel"):
		return false
	if not date_text.is_empty():
		var midnight: int = Time.get_unix_time_from_datetime_string(date_text + "T00:00:00")
		if Time.get_date_string_from_unix_time(midnight) != date_text:
			return false
	_debug_event_date = date_text
	return true


## 为调试替换活动日期但保留时分秒；编辑器默认预览日期由常量指定。
static func event_date_time(local_time: int) -> int:
	var override_date: String = debug_event_date()
	if override_date.is_empty() and OS.has_feature("editor"):
		override_date = EDITOR_EVENT_DATE_OVERRIDE
	if override_date.is_empty():
		return local_time
	var midnight: int = Time.get_unix_time_from_datetime_string(override_date + "T00:00:00")
	if Time.get_date_string_from_unix_time(midnight) != override_date:
		push_error("[HomeCompanion] 活动日期覆盖无效：" + override_date)
		return local_time
	var calendar: Dictionary = Time.get_datetime_dict_from_unix_time(local_time)
	return (
		midnight
		+ int(calendar["hour"]) * 3600
		+ int(calendar["minute"]) * 60
		+ int(calendar["second"])
	)


func connect_victories() -> void:
	if not GameState.main_level_won.is_connected(_on_main_level_won):
		GameState.main_level_won.connect(_on_main_level_won)


func disconnect_victories() -> void:
	if GameState.main_level_won.is_connected(_on_main_level_won):
		GameState.main_level_won.disconnect(_on_main_level_won)


## 从 GameState 创建模型，结算模式与饱食度后存回快照，再返回对应视图策略。
func enter_home(requested: HomeCompanionCatStrategy, now: int) -> HomeCompanionCatStrategy:
	var system: System = System.new(GameState.get_home_companion_data())
	var event_now: int = now if clock.is_valid() else event_date_time(now)
	var resolved: int = system.enter_home(
		requested.business_mode(), now, event_now, debug_satiety_decay_scale()
	)
	GameState.set_home_companion_data(system.snapshot())
	return HomeCompanionCatStrategy.for_mode(resolved)


func in_game_costume_override() -> int:
	if resolve_mode(HomeCompanionCatStrategy.create()) != System.Mode.HALLOWEEN_COSMETIC:
		return 0
	return CostumeCatalog.HALLOWEEN_COSTUME_ID


func shows_unowned_event_rewards() -> bool:
	return resolve_mode(HomeCompanionCatStrategy.create()) == System.Mode.HALLOWEEN_REWARDS


static func is_halloween_dress_mode(mode: int) -> bool:
	return mode == System.Mode.HALLOWEEN_REWARDS or mode == System.Mode.HALLOWEEN_COSMETIC


func resolve_mode(requested: HomeCompanionCatStrategy) -> int:
	var system: System = System.new(GameState.get_home_companion_data())
	var now: int = current_time()
	var event_now: int = now if clock.is_valid() else event_date_time(now)
	return system.effective_mode(requested.business_mode(), event_now)


func snapshot() -> Dictionary:
	var system: System = System.new(GameState.get_home_companion_data())
	var saved: Dictionary = system.snapshot()

	if saved["satiety_active"] and saved["satiety_enabled"]:
		system.sync_satiety_mode(System.Mode.SATIETY, current_time(), debug_satiety_decay_scale())
	return system.snapshot()


func feed(strategy: HomeCompanionCatStrategy) -> bool:
	return feed_result(strategy) == System.FeedResult.ACCEPTED


## 调用模型扣除库存并写回存档，成功后记录罐头使用信息。
func feed_result(strategy: HomeCompanionCatStrategy) -> System.FeedResult:
	if not strategy.allows_feeding():
		return System.FeedResult.UNAVAILABLE
	var system: System = System.new(GameState.get_home_companion_data())
	if strategy.has_satiety():
		system.sync_satiety_mode(System.Mode.SATIETY, current_time(), debug_satiety_decay_scale())
	var result: System.FeedResult = system.feed_result(strategy.business_mode())
	if result != System.FeedResult.ACCEPTED:
		return result
	var saved: Dictionary = system.snapshot()
	if not GameState.set_home_companion_data(saved):
		return System.FeedResult.UNAVAILABLE

	if (
		strategy.business_mode() == System.Mode.DAILY_CANS
		or strategy.business_mode() == System.Mode.SATIETY
	):
		var fullness: int = roundi(float(saved["satiety"])) if strategy.has_satiety() else -1
		Tracker.track_companion_cat_item_use(
			Tracker.CompanionItem.CAN, Tracker.Scr.HOMEPAGE, 1, int(saved["cans"]), fullness
		)
	return result


func tutorial_needed(strategy: HomeCompanionCatStrategy) -> bool:
	var system: System = System.new(GameState.get_home_companion_data())
	return system.tutorial_needed(strategy.business_mode())


func complete_tutorial(strategy: HomeCompanionCatStrategy) -> void:
	var system: System = System.new(GameState.get_home_companion_data())
	system.complete_tutorial(strategy.business_mode())
	GameState.set_home_companion_data(system.snapshot())


## 首次检查时结清旧会话残留演出，只把本会话新发放的奖励交给界面展示。
func pending_presentations() -> Array[int]:
	var system: System = System.new(GameState.get_home_companion_data())
	var pending: Array[int] = system.pending_presentations()
	if not _stale_settled:
		_stale_settled = true
		for tier: int in pending:
			if not _session_granted.has(tier):
				complete_reward_presentation(tier)
	var result: Array[int] = []
	for tier: int in pending:
		if _session_granted.has(tier):
			result.append(tier)
	return result


## 标记演出完成并保存；试用装扮在此时真正开通，随后请求云同步。
func complete_reward_presentation(tier: int) -> bool:
	var candidate: Dictionary = GameState.get_core_candidate()
	var revision: int = GameState.get_core_store().revision()
	var system: System = System.new(candidate.profile.get("home_companion_data", {}))
	if not system.acknowledge_presentation(tier, current_time()):
		return false
	if System.REWARD_KINDS[tier] == "trial_costume":
		ProfileService.stage_asset(candidate, "grant_costume_trial", [CostumeCatalog.HALLOWEEN_COSTUME_ID, ProfileService.costume_now()])
	candidate.profile["home_companion_data"] = system.snapshot()
	var result: Dictionary = GameState.commit_core_candidate(candidate, revision)
	if not result.ok:
		return false
	DataSyncManager.request_sync("home_companion_presentation")
	return true


func grant_pending_rewards() -> Array[int]:
	var candidate: Dictionary = GameState.get_core_candidate()
	var revision: int = GameState.get_core_store().revision()
	var system: System = System.new(candidate.profile.get("home_companion_data", {}))
	var recorded: Array[int] = []
	for tier: int in system.pending_grants():
		var kind: String = System.REWARD_KINDS[tier]
		if kind != "mouse" and kind != "trial_costume":
			if not _stage_tier_asset(candidate, kind):
				return []
		if system.acknowledge_grant(tier):
			system.mark_presented(tier)
			recorded.append(tier)
	if recorded.is_empty():
		return recorded
	candidate.profile["home_companion_data"] = system.snapshot()
	var result: Dictionary = GameState.commit_core_candidate(candidate, revision)
	return recorded if result.ok else []


func _grant_pending_into(system: System) -> Array[int]:
	var tiers: Array[int] = system.pending_grants()
	var granted: Array[int] = []
	for tier in tiers:
		_grant_tier_asset(System.REWARD_KINDS[tier])
		if system.acknowledge_grant(tier):
			granted.append(tier)
	return granted


func _grant_tier_asset(kind: String) -> void:
	match kind:
		"avatar":
			if ProfileService.grant_avatar(ProfileCatalog.HALLOWEEN_AVATAR_ID):
				Tracker.track_avatar_get(
					ProfileCatalog.HALLOWEEN_AVATAR_ID, Tracker.PropSource.COMPANION_CAT_REWARD_DLG
				)
		"frame":
			if not ProfileService.is_frame_unlocked(ProfileCatalog.HALLOWEEN_FRAME_ID):
				AwardManager.dispatch(
					[AwardItem.make_frame(ProfileCatalog.HALLOWEEN_FRAME_ID)],
					AwardManager.DisplayType.DIRECT,
					Tracker.PropSource.COMPANION_CAT_REWARD_DLG
				)
		"mouse":
			AwardManager.dispatch(
				[AwardItem.make("mouse", MOUSE_REWARD_COUNT)],
				AwardManager.DisplayType.DIRECT,
				Tracker.PropSource.COMPANION_CAT_REWARD_DLG
			)
		"permanent_costume":
			if ProfileService.grant_costume_permanent(CostumeCatalog.HALLOWEEN_COSTUME_ID):
				Tracker.track_skin_get(
					CostumeCatalog.HALLOWEEN_COSTUME_ID,
					-1,
					Tracker.PropSource.COMPANION_CAT_REWARD_DLG
				)
		"trial_costume":
			pass
		_:
			push_error("[HomeCompanion] 未知奖励类型：" + kind)


## 忽略色彩挑战，以胜利 ID 去重后累计货币、发奖、保存，并记录获取来源。
func _on_main_level_won(game_id: String, kind: int, win_date: Variant) -> void:
	# 兼容非对局调用；新结算已在同一候选记录该 ID，此处会无修改返回。
	var candidate: Dictionary = GameState.get_core_candidate()
	var revision: int = GameState.get_core_store().revision()
	var result: Dictionary = stage_main_win(candidate, game_id, kind, win_date)
	if not result.ok or not result.get("changed", false):
		return
	if GameState.commit_core_candidate(candidate, revision).ok:
		publish_main_win(result)


func game_end_fields(won_game_id: String, kind: int) -> Dictionary:
	var system: System = System.new(GameState.get_home_companion_data())
	if not won_game_id.is_empty() and not LevelKind.is_color_challenge(kind):
		var now: int = current_time()
		var event_now: int = now if clock.is_valid() else event_date_time(now)
		system.record_win(
			HomeCompanionCatStrategy.create().business_mode(),
			now,
			won_game_id,
			true,
			event_now,
			event_now
		)
	var data: Dictionary = system.snapshot()
	return {"candy": int(data["candy_total"]), "can": int(data["cans"])}

func _stage_tier_asset(candidate: Dictionary, kind: String) -> bool:
	match kind:
		"avatar":
			ProfileService.stage_asset(candidate, "grant_avatar", [ProfileCatalog.HALLOWEEN_AVATAR_ID])
		"permanent_costume":
			ProfileService.stage_asset(candidate, "grant_costume_permanent", [CostumeCatalog.HALLOWEEN_COSTUME_ID])
		"frame", "mouse":
			var item: Dictionary = {"kind": "mouse", "count": MOUSE_REWARD_COUNT}
			if kind == "frame":
				var frames: Array = candidate.features.get("identity", {}).get("owned_frames", [])
				for frame: Dictionary in frames:
					if int(frame.get("id", 0)) == ProfileCatalog.HALLOWEEN_FRAME_ID:
						return true
				item = {"category": 1, "frame_id": ProfileCatalog.HALLOWEEN_FRAME_ID, "count": 1}
			var result: Dictionary = MeowdokuAwardPolicy.new().stage_item(candidate, item, Tracker.PropSource.COMPANION_CAT_REWARD_DLG)
			return result.ok
		"trial_costume":
			pass
		_:
			return false
	return true


func stage_main_win(candidate: Dictionary, game_id: String, kind: int, win_date: Variant) -> Dictionary:
	var before: Dictionary = candidate.profile.get("home_companion_data", {}).duplicate(true)
	if LevelKind.is_color_challenge(kind):
		return {"ok": true, "changed": false, "before": before, "granted": []}
	var strategy: HomeCompanionCatStrategy = HomeCompanionCatStrategy.create()
	var now: int = current_time()
	var event_now: int = now if clock.is_valid() else event_date_time(now)
	var event_time: int = now
	if win_date != null:
		var date_text: String = str(win_date)
		event_time = -1 if date_text.is_empty() else Time.get_unix_time_from_datetime_string(date_text + "T00:00:00")
	if event_time >= 0:
		event_time += event_now - now
	var system: System = System.new(before)
	var result: Dictionary = system.record_win(strategy.business_mode(), now, game_id, true, event_time, event_now)
	var granted: Array[int] = []
	if bool(result.get("candy_awarded", false)):
		for tier: int in system.pending_grants():
			if not _stage_tier_asset(candidate, System.REWARD_KINDS[tier]):
				return {"ok": false, "error": "companion_asset_failed"}
			if system.acknowledge_grant(tier):
				granted.append(tier)
	candidate.profile["home_companion_data"] = system.snapshot()
	return {"ok": true, "changed": not result.is_empty(), "before": before, "granted": granted, "record": result, "after": system.snapshot()}


static func publish_main_win(result: Dictionary) -> void:
	for tier: int in result.get("granted", []):
		_session_granted[tier] = true
	if not result.get("granted", []).is_empty():
		DataSyncManager.request_sync("home_companion_reward")
	var record: Dictionary = result.get("record", {})
	var saved: Dictionary = result.get("after", {})
	if bool(record.get("candy_awarded", false)):
		Tracker.track_companion_cat_item_get(Tracker.CompanionItem.CANDY, Tracker.CompanionItemSource.GAME_WIN_GET, 1, int(saved.get("candy_total", 0)))
	if bool(record.get("can_awarded", false)):
		Tracker.track_companion_cat_item_get(Tracker.CompanionItem.CAN, Tracker.CompanionItemSource.GAME_WIN_GET, 1, int(saved.get("cans", 0)))
