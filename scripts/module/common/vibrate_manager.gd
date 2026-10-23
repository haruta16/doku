## 触觉反馈管理器：按业务事件和广告位置选择震动模式，适配 iOS 与 Android 原生接口。
class_name VibrateManager
extends RefCounted

enum Level {
	LEVEL1,
	LEVEL2,
	LEVEL3,
	LEVEL4,
	LEVEL5,
	LEVEL6,
	LEVEL7,
	LEVEL10,
}

enum Pos {
	START_BTN,
	SETTINGS_BTN,
	AVATAR_BTN,
	WIN_NEXT_BTN,
	OPTIONS_BTN,
	BLIND_MOD_BTN,
	CELL_MARK,
	CELL_PLACE_CAT,
	CELL_ERROR,
	HINT_CLEAR,
	TOOL_USE,
	GAME_WIN,
	GAME_FAIL,
	DAILY_WIN,
	DAILY_FAIL,
	BOARD_INTRO,
	TUTORIAL_MARK,
	TUTORIAL_CAT,
	TUTORIAL_WIN,
	SETTING_CLOSE,
	SETTING_TOGGLE,
	SETTING_VIBRATION_ON,
	PROFILE_RENAME,
	PROFILE_AVATAR_TAB,
	PROFILE_FRAME_TAB,
	PROFILE_AVATAR_SELECT,
	PROFILE_FRAME_SELECT,
	PROFILE_COSTUME_TAB,
	PROFILE_COSTUME_SELECT,
	RANK_ENTRY_CLICK,
	RANK_CHANGE_DROP,
	RANK_CELL_FLY,
	RANK_COLLECTOR_FLY,
	RANK_GIFT_BOX_APPEAR,
	RANK_GIFT_OPEN,
	STREAK_ENTRY_CLICK,
	STREAK_CHECK_IN,
	STREAK_DAY_NORMAL,
	STREAK_DAY_CHEST,
	STREAK_GIFT,
	STREAK_CONTINUE,
	STREAK_GO_PLAY,
	DAILY_ENTRY_CLICK,
	CHEAT_VIBRATE,
	STREAK_SWING,
	STREAK_FIRST_CLICK,
	STREAK_DAY_LAND,
}

enum _Cond {
	ALWAYS,
	VIBRATE_ADD,
}

static var _pos_table: Dictionary = {}
static var _pos_table_ready: bool = false


static func _ensure_pos_table() -> void:
	if _pos_table_ready:
		return
	_pos_table_ready = true
	_build_pos_table()


static func _build_pos_table() -> void:
	var add_l2: Array = [
		Pos.SETTINGS_BTN,
		Pos.AVATAR_BTN,
		Pos.WIN_NEXT_BTN,
		Pos.OPTIONS_BTN,
		Pos.BLIND_MOD_BTN,
		Pos.RANK_CELL_FLY,
		Pos.RANK_COLLECTOR_FLY,
		Pos.PROFILE_RENAME,
		Pos.PROFILE_AVATAR_TAB,
		Pos.PROFILE_FRAME_TAB,
		Pos.PROFILE_AVATAR_SELECT,
		Pos.PROFILE_FRAME_SELECT,
		Pos.PROFILE_COSTUME_TAB,
		Pos.PROFILE_COSTUME_SELECT,
		Pos.BOARD_INTRO,
	]
	for p: int in add_l2:
		_pos_table[p] = {"level": Level.LEVEL2, "cond": _Cond.VIBRATE_ADD}

	var add_l3: Array = [Pos.SETTING_TOGGLE]
	for p: int in add_l3:
		_pos_table[p] = {"level": Level.LEVEL3, "cond": _Cond.VIBRATE_ADD}

	var add_l4: Array = [Pos.RANK_GIFT_OPEN, Pos.RANK_GIFT_BOX_APPEAR]
	for p: int in add_l4:
		_pos_table[p] = {"level": Level.LEVEL4, "cond": _Cond.VIBRATE_ADD}

	var add_l5: Array = [Pos.RANK_CHANGE_DROP]
	for p: int in add_l5:
		_pos_table[p] = {"level": Level.LEVEL5, "cond": _Cond.VIBRATE_ADD}

	_pos_table[Pos.SETTING_CLOSE] = {"level": Level.LEVEL2, "cond": _Cond.VIBRATE_ADD}

	_pos_table[Pos.SETTING_VIBRATION_ON] = {"level": Level.LEVEL3, "cond": _Cond.VIBRATE_ADD}

	_pos_table[Pos.CELL_MARK] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.CELL_PLACE_CAT] = {"level": Level.LEVEL3, "cond": _Cond.ALWAYS}
	_pos_table[Pos.CELL_ERROR] = {"level": Level.LEVEL3, "cond": _Cond.ALWAYS}
	_pos_table[Pos.HINT_CLEAR] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.TOOL_USE] = {"level": Level.LEVEL4, "cond": _Cond.ALWAYS}
	_pos_table[Pos.GAME_WIN] = {"level": Level.LEVEL5, "cond": _Cond.ALWAYS}
	_pos_table[Pos.GAME_FAIL] = {"level": Level.LEVEL4, "cond": _Cond.ALWAYS}
	_pos_table[Pos.DAILY_WIN] = {"level": Level.LEVEL5, "cond": _Cond.ALWAYS}
	_pos_table[Pos.DAILY_FAIL] = {"level": Level.LEVEL4, "cond": _Cond.ALWAYS}
	_pos_table[Pos.TUTORIAL_MARK] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.TUTORIAL_CAT] = {"level": Level.LEVEL3, "cond": _Cond.ALWAYS}
	_pos_table[Pos.TUTORIAL_WIN] = {"level": Level.LEVEL5, "cond": _Cond.ALWAYS}
	_pos_table[Pos.START_BTN] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.RANK_ENTRY_CLICK] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.STREAK_ENTRY_CLICK] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.STREAK_CONTINUE] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.STREAK_GO_PLAY] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}

	_pos_table[Pos.STREAK_SWING] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.STREAK_CHECK_IN] = {"level": Level.LEVEL5, "cond": _Cond.ALWAYS}
	_pos_table[Pos.STREAK_FIRST_CLICK] = {"level": Level.LEVEL5, "cond": _Cond.ALWAYS}
	_pos_table[Pos.STREAK_DAY_NORMAL] = {"level": Level.LEVEL5, "cond": _Cond.ALWAYS}
	_pos_table[Pos.STREAK_DAY_LAND] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.STREAK_DAY_CHEST] = {"level": Level.LEVEL4, "cond": _Cond.ALWAYS}
	_pos_table[Pos.STREAK_GIFT] = {"level": Level.LEVEL4, "cond": _Cond.ALWAYS}

	_pos_table[Pos.DAILY_ENTRY_CLICK] = {"level": Level.LEVEL2, "cond": _Cond.ALWAYS}
	_pos_table[Pos.CHEAT_VIBRATE] = {"level": Level.LEVEL3, "cond": _Cond.ALWAYS}


static func play_at(pos: Pos) -> void:
	_ensure_pos_table()
	if not _pos_table.has(pos):
		return
	var entry: Dictionary = _pos_table[pos]
	var cond: int = entry.cond
	var pos_name: String = Pos.keys()[pos]

	if not _enabled:
		_log_vibrate(entry.level, "disabled", pos_name)
		return
	if cond == _Cond.VIBRATE_ADD:
		if not ABTestManager.vibrate_add.is_enabled():
			_log_vibrate(entry.level, "vibrate_add:off", pos_name)
			return
	_play_vibrate_internal(entry.level, pos_name)


static var _is_ios: bool = OS.get_name() == "iOS" # 平台判定只做一次

static var _map_low: Dictionary = {} # 低内存机的 Android 参数表（惰性构建）
static var _map_high: Dictionary = {} # 高内存机的 Android 参数表（惰性构建）
static var _maps_ready: bool = false # 参数表是否已构建过

static var _map_ios: Dictionary = {
	Level.LEVEL1: "selectionChanged",
	Level.LEVEL2: "feedbackMedium",
	Level.LEVEL3: "feedbackHeavy",
	Level.LEVEL4: "longVibrate",
	Level.LEVEL5: "notificationSuccess",
	Level.LEVEL6: "notificationSuccess",
	Level.LEVEL7: "longVibrate",
	Level.LEVEL10: "longVibrate",
}


static func _build_maps() -> void:
	if _maps_ready:
		return
	_maps_ready = true

	var ct := PackedInt32Array()
	var ca := PackedInt32Array()
	for i: int in 20:
		ct.append(50)
		ca.append(roundi(10.0 + 140.0 * (float(i) / 19.0)))
	var _charge: Dictionary = {"t": ct, "a": ca}

	_map_low = {
		Level.LEVEL1: {"d": 40, "a": 10},
		Level.LEVEL2: {"d": 40, "a": 80},
		Level.LEVEL3: {"d": 40, "a": 200},
		Level.LEVEL4: {"d": 200, "a": 50},
		Level.LEVEL5: {"d": 60, "a": 250},
		Level.LEVEL6: {"d": 60, "a": 300},
		Level.LEVEL7: {"d": 130, "a": 50},
		Level.LEVEL10: {"d": 200, "a": 50},
	}

	_map_high = {
		Level.LEVEL1: {"d": 20, "a": 10},
		Level.LEVEL2: {"d": 20, "a": 80},
		Level.LEVEL3: {"d": 20, "a": 150},
		Level.LEVEL4: {"d": 200, "a": 50},
		Level.LEVEL5: {"d": 30, "a": 250},
		Level.LEVEL6: {"d": 30, "a": 300},
		Level.LEVEL7: {"d": 130, "a": 50},
		Level.LEVEL10: {"d": 200, "a": 50},
	}


## 超过这个内存（MB）就算高内存机；只有 Android 需要区分
const _RAM_4G_MB: int = 3800
static var _ram_ready: bool = false # 内存档位是否已探测过
static var _is_high_ram: bool = false # 探测结果


## 探测一次总内存，决定用哪张 Android 参数表；iOS 不需要
static func _ensure_ram() -> void:
	if _ram_ready:
		return
	_ram_ready = true
	if _is_ios:
		return
	var p: Object = _plugin()
	if p != null:
		_is_high_ram = (p.getTotalRamMb() as int) > _RAM_4G_MB


static var _enabled: bool = true # 总开关，由设置页的震动选项驱动


static func set_enabled(on: bool) -> void:
	var changed: bool = _enabled != on
	_enabled = on
	if changed and is_instance_valid(EventBus):
		EventBus.emit_event(EventName.SETTING_TOGGLE, {"name": "vibration", "on": on})


## 当前是否允许震动
static func is_enabled() -> bool:
	return _enabled


## 取原生插件单例；没装插件就返回 null，调用方一律判空
static func _plugin() -> Object:
	if Engine.has_singleton("VibratePlugin"):
		return Engine.get_singleton("VibratePlugin")
	return null


## 设备是否有振动器
static func has_vibrator() -> bool:
	var p: Object = _plugin()
	if p == null:
		return false
	return p.hasVibrator() as bool


## 是否支持控制振幅（iOS 一律不支持，只能选固定几种反馈）
static func has_amplitude_control() -> bool:
	if _is_ios:
		return false
	var p: Object = _plugin()
	if p == null:
		return false
	return p.hasAmplitudeControl() as bool


static func play_vibrate(level: Level) -> void:
	_play_vibrate_internal(level, "")


static func _play_vibrate_internal(level: Level, pos_hint: String) -> void:
	if not _enabled:
		_log_vibrate(level, "disabled", pos_hint)
		return
	_log_vibrate(level, "", pos_hint)
	if _is_ios:
		_play_ios(level)
	else:
		_play_android(level)


## 打断当前震动
static func cancel() -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.cancel()


## iOS：按档位反射调用系统反馈方法名，表里没有的档位不震
static func _play_ios(level: Level) -> void:
	if not _map_ios.has(level):
		return
	var p: Object = _plugin()
	if p == null:
		return
	var method_name: String = _map_ios[level]
	p.call(method_name)


## Android：先定内存档位，再从对应表里取 d/a 参数执行
static func _play_android(level: Level) -> void:
	_ensure_ram()
	_build_maps()
	var map: Dictionary = _map_high if _is_high_ram else _map_low
	if not map.has(level):
		return
	var data: Dictionary = map[level] as Dictionary
	if data.has("t"):
		_vibrate_pattern(data["t"] as PackedInt32Array, data["a"] as PackedInt32Array)
	else:
		_vibrate(data["d"] as int, data["a"] as int)


## 单次震动：持续 duration_ms 毫秒，振幅 amplitude
static func _vibrate(duration_ms: int, amplitude: int) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.vibrate(duration_ms, amplitude)


## 节奏震动：timings_ms 与 amplitudes 两个数组描述「停多久 / 震多强」的交替序列
static func _vibrate_pattern(timings_ms: PackedInt32Array, amplitudes: PackedInt32Array) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.vibratePattern(timings_ms, amplitudes)


static var _debug_log: bool = not OS.has_feature("rel")


static func _log_vibrate(level: Level, skip_reason: String, pos_hint: String) -> void:
	_emit_timeline_event(level, skip_reason, pos_hint)
	if not _debug_log:
		return
	var lv_name: String = Level.keys()[level]
	var pos_tag: String = " @%s" % pos_hint if not pos_hint.is_empty() else ""
	if not skip_reason.is_empty():
		print(
			"[vibrate] %s SKIPPED(%s)%s  <- %s" % [lv_name, skip_reason, pos_tag, _debug_caller()]
		)
		return
	print("[vibrate] %s %s%s  <- %s" % [lv_name, _debug_detail(level), pos_tag, _debug_caller()])


static func _emit_timeline_event(level: Level, skip_reason: String, pos_hint: String) -> void:
	if not is_instance_valid(EventBus):
		return
	var payload: Dictionary = {"level": Level.keys()[level]}
	if not pos_hint.is_empty():
		payload["pos"] = pos_hint

	if not skip_reason.is_empty():
		payload["skip"] = skip_reason
	EventBus.emit_event(EventName.VIBRATE_PLAY, payload)


static func _debug_detail(level: Level) -> String:
	if _is_ios:
		return "iOS:%s" % str(_map_ios.get(level, "?"))
	_ensure_ram()
	_build_maps()
	var map: Dictionary = _map_high if _is_high_ram else _map_low
	if not map.has(level):
		return "android:<no data>"
	var data: Dictionary = map[level] as Dictionary
	var ram: String = "high" if _is_high_ram else "low"
	var body: String = ""
	if data.has("t"):
		body = "android(%s):波形%d段" % [ram, (data["t"] as PackedInt32Array).size()]
	else:
		body = "android(%s):%dms·振幅%d" % [ram, int(data["d"]), int(data["a"])]
	if _plugin() == null:
		body += "  [无plugin,未实际震动]"
	return body


static func _debug_caller() -> String:
	var stack: Array = get_stack()
	for i: int in stack.size():
		var src: String = str(stack[i].get("source", ""))
		if not src.ends_with("vibrate_manager.gd"):
			var f: Dictionary = stack[i]
			return (
				"%s:%d %s()"
				% [
					src.get_file(),
					int(f.get("line", 0)),
					str(f.get("function", "?")),
				]
			)
	return "?"
