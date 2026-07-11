class_name VibrateManager
extends RefCounted

enum Level {
	LEVEL1,
	LEVEL2,
	LEVEL3,
	LEVEL4,
	LEVEL5,
	LEVEL7,
	LEVEL10,
}

static var _is_ios: bool = OS.get_name() == "iOS"

static var _map_low: Dictionary = {}
static var _map_high: Dictionary = {}
static var _maps_ready: bool = false

static var _map_ios: Dictionary = {
	Level.LEVEL1: "selectionChanged",
	Level.LEVEL2: "feedbackMedium",
	Level.LEVEL3: "feedbackHeavy",
	Level.LEVEL4: "longVibrate",
	Level.LEVEL5: "notificationSuccess",
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
		Level.LEVEL7: {"d": 130, "a": 50},
		Level.LEVEL10: {"d": 200, "a": 50},
	}

	_map_high = {
		Level.LEVEL1: {"d": 20, "a": 10},
		Level.LEVEL2: {"d": 20, "a": 80},
		Level.LEVEL3: {"d": 20, "a": 150},
		Level.LEVEL4: {"d": 200, "a": 50},
		Level.LEVEL5: {"d": 30, "a": 250},
		Level.LEVEL7: {"d": 130, "a": 50},
		Level.LEVEL10: {"d": 200, "a": 50},
	}


const _RAM_4G_MB: int = 3800
static var _ram_ready: bool = false
static var _is_high_ram: bool = false


static func _ensure_ram() -> void:
	if _ram_ready:
		return
	_ram_ready = true
	if _is_ios:
		return
	var p: Object = _plugin()
	if p != null:
		_is_high_ram = (p.getTotalRamMb() as int) > _RAM_4G_MB


static var _enabled: bool = true


static func set_enabled(on: bool) -> void:
	_enabled = on


static func is_enabled() -> bool:
	return _enabled


static func _plugin() -> Object:
	if Engine.has_singleton("VibratePlugin"):
		return Engine.get_singleton("VibratePlugin")
	return null


static func has_vibrator() -> bool:
	var p: Object = _plugin()
	if p == null:
		return false
	return p.hasVibrator() as bool


static func has_amplitude_control() -> bool:
	if _is_ios:
		return false
	var p: Object = _plugin()
	if p == null:
		return false
	return p.hasAmplitudeControl() as bool


static func play_vibrate(level: Level) -> void:
	if not _enabled:
		return
	if _is_ios:
		_play_ios(level)
	else:
		_play_android(level)


static func cancel() -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.cancel()


static func _play_ios(level: Level) -> void:
	if not _map_ios.has(level):
		return
	var p: Object = _plugin()
	if p == null:
		return
	var method_name: String = _map_ios[level]
	p.call(method_name)


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


static func _vibrate(duration_ms: int, amplitude: int) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.vibrate(duration_ms, amplitude)


static func _vibrate_pattern(timings_ms: PackedInt32Array, amplitudes: PackedInt32Array) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.vibratePattern(timings_ms, amplitudes)
