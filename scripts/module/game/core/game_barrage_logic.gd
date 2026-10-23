## 弹幕调度状态：累计时间与玩家动作，管理尝试时机、弹幕波次和预留展示名额。
class_name GameBarrageLogic
extends RefCounted

const FIRST_ATTEMPT_DELAY_SEC: float = 60.0
const NEXT_ATTEMPT_DELAY_SEC: float = 60.0
const QUIET_PERIOD_SEC: float = 20.0

const MODE_DISABLED: int = 0
const MODE_SINGLE: int = 1
const MODE_MULTI: int = 2
const LEVEL_WAVE_LIMIT: int = 2
const FULLSCREEN_AD_PLACEMENTS: Array[String] = [AdPlacement.REWARD, AdPlacement.INTERSTITIAL]

const REGULAR_TEMPLATE_KEYS: Array[String] = [
	"GAME_PAGE_BULLET_1",
	"GAME_PAGE_BULLET_2",
	"GAME_PAGE_BULLET_3",
	"GAME_PAGE_BULLET_4",
]
const DAILY_TEMPLATE_KEYS: Array[String] = [
	"GAME_PAGE_BULLET_DAILY_1",
	"GAME_PAGE_BULLET_DAILY_2",
	"GAME_PAGE_BULLET_DAILY_3",
	"GAME_PAGE_BULLET_DAILY_4",
]
const INLINE_ICON_SIZE: int = 90
const INLINE_ICON_PATHS: Dictionary = {
	"2": "res://assets/sprites/game/bullets/icon_muscle.png",
	"3": "res://assets/sprites/game/bullets/icon_leaf.png",
	"4": "res://assets/sprites/game/bullets/icon_star.png",
	"5": "res://assets/sprites/game/bullets/icon_flash.png",
}
const TEMPLATE_ICON_TOKENS: Dictionary = {
	"GAME_PAGE_BULLET_1": "2",
	"GAME_PAGE_BULLET_2": "3",
	"GAME_PAGE_BULLET_3": "4",
	"GAME_PAGE_BULLET_4": "5",
	"GAME_PAGE_BULLET_DAILY_1": "2",
	"GAME_PAGE_BULLET_DAILY_2": "3",
	"GAME_PAGE_BULLET_DAILY_3": "4",
	"GAME_PAGE_BULLET_DAILY_4": "5",
}

var _elapsed_sec: float = 0.0
var _last_action_sec: float = 0.0
var _next_attempt_sec: float = FIRST_ATTEMPT_DELAY_SEC
var _displayed_count: int = 0
var _started_wave_count: int = 0
var _used_level_keys: Dictionary = {}
var _last_clock_msec: int = -1


static func resolve_mode(is_main_level: bool, is_single_mode: bool, is_multi_mode: bool) -> int:
	if not is_main_level:
		return MODE_DISABLED
	if is_single_mode:
		return MODE_SINGLE
	if is_multi_mode:
		return MODE_MULTI
	return MODE_DISABLED


static func is_fullscreen_ad_placement(placement_id: String) -> bool:
	return FULLSCREEN_AD_PLACEMENTS.has(placement_id)


func reset() -> void:
	_elapsed_sec = 0.0
	_last_action_sec = 0.0
	_next_attempt_sec = FIRST_ATTEMPT_DELAY_SEC
	_displayed_count = 0
	_started_wave_count = 0
	_used_level_keys.clear()
	_last_clock_msec = -1


func start_clock(now_msec: int) -> void:
	_last_clock_msec = now_msec


func sync_clock(now_msec: int, ad_active: bool) -> void:
	if _last_clock_msec < 0:
		_last_clock_msec = now_msec
		return
	var delta_sec: float = float(maxi(0, now_msec - _last_clock_msec)) / 1000.0
	_last_clock_msec = now_msec
	if not ad_active:
		advance(delta_sec)


func advance(delta_sec: float) -> void:
	_elapsed_sec += maxf(0.0, delta_sec)


func record_action() -> void:
	_last_action_sec = _elapsed_sec


func is_attempt_due() -> bool:
	return _elapsed_sec >= _next_attempt_sec and _elapsed_sec - _last_action_sec >= QUIET_PERIOD_SEC


func record_attempt() -> void:
	_next_attempt_sec = _elapsed_sec + NEXT_ATTEMPT_DELAY_SEC


func make_wave(
	mode: int, daily_shown_keys: Array, rng: RandomNumberGenerator, nicknames: Array
) -> Array[Dictionary]:
	if mode != MODE_SINGLE and mode != MODE_MULTI:
		return []
	if not has_remaining_wave_quota():
		return []
	var desired_count: int = 1
	if mode == MODE_MULTI:
		desired_count = rng.randi_range(1, 3)
	var available_keys: Array[String] = _available_keys(daily_shown_keys)
	var wave_count: int = mini(desired_count, available_keys.size())
	if wave_count <= 0:
		return []
	_started_wave_count += 1
	var wave: Array[Dictionary] = []
	for barrage_index: int in wave_count:
		var selected_index: int = rng.randi_range(0, available_keys.size() - 1)
		var key: String = available_keys.pop_at(selected_index)
		_used_level_keys[key] = true
		wave.append(make_barrage_for_key(key, rng, nicknames))
	return wave


func record_displayed(key: String) -> void:
	_displayed_count += 1
	_used_level_keys[key] = true


func release_reserved(key: String) -> void:
	_used_level_keys.erase(key)


func get_elapsed_sec() -> float:
	return _elapsed_sec


func get_next_eligible_sec() -> float:
	return maxf(_next_attempt_sec, _last_action_sec + QUIET_PERIOD_SEC)


func get_started_wave_count() -> int:
	return _started_wave_count


func has_remaining_wave_quota() -> bool:
	return _started_wave_count < LEVEL_WAVE_LIMIT


func get_displayed_count() -> int:
	return _displayed_count


func get_used_level_keys() -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in _used_level_keys.keys():
		keys.append(str(key))
	return keys


static func is_daily_key(key: String) -> bool:
	return DAILY_TEMPLATE_KEYS.has(key)


static func make_barrage_for_key(
	key: String, rng: RandomNumberGenerator, nicknames: Array
) -> Dictionary:
	var barrage: Dictionary = {
		"key": key,
		"args": [],
		"named_args": {},
		"inline_icons": {},
		"append_heart": false,
	}
	match key:
		"GAME_PAGE_BULLET_1":
			barrage.args = [rng.randi_range(10000, 1000000)]
		"GAME_PAGE_BULLET_2":
			barrage.args = [rng.randi_range(100, 999)]
		"GAME_PAGE_BULLET_3":
			barrage.args = [rng.randi_range(20, 99)]
		"GAME_PAGE_BULLET_DAILY_1":
			barrage.args = [rng.randi_range(4, 7)]
			barrage.named_args = {"name": _random_nickname(rng, nicknames)}
		"GAME_PAGE_BULLET_DAILY_2":
			barrage.args = [rng.randi_range(100, 160)]
			barrage.named_args = {"name": _random_nickname(rng, nicknames)}
		"GAME_PAGE_BULLET_DAILY_3":
			barrage.named_args = {"name": _random_nickname(rng, nicknames)}
		"GAME_PAGE_BULLET_DAILY_4":
			barrage.args = [rng.randi_range(60, 99)]
	var icon_token: String = str(TEMPLATE_ICON_TOKENS.get(key, ""))
	var icon_path: String = str(INLINE_ICON_PATHS.get(icon_token, ""))
	if not icon_token.is_empty() and not icon_path.is_empty():
		barrage.inline_icons[icon_token] = {
			"path": icon_path,
			"width": INLINE_ICON_SIZE,
			"height": INLINE_ICON_SIZE,
		}
	return barrage


func _available_keys(daily_shown_keys: Array) -> Array[String]:
	var available: Array[String] = []
	for key: String in REGULAR_TEMPLATE_KEYS:
		if not _used_level_keys.has(key):
			available.append(key)
	for key: String in DAILY_TEMPLATE_KEYS:
		if not _used_level_keys.has(key) and not daily_shown_keys.has(key):
			available.append(key)
	return available


static func _random_nickname(rng: RandomNumberGenerator, nicknames: Array) -> String:
	if nicknames.is_empty():
		return ""
	return str(nicknames[rng.randi_range(0, nicknames.size() - 1)])
