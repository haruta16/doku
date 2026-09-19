# 震动总控：把游戏里的抽象档位 Level 翻译成 iOS / Android 各自的原生震动调用
# 原生能力来自 VibratePlugin 单例，插件不存在时所有调用静默跳过
class_name VibrateManager
extends RefCounted

# 震动档位：枚举值就是档位号，6/8/9 故意没定义
enum Level {
	LEVEL1,
	LEVEL2,
	LEVEL3,
	LEVEL4,
	LEVEL5,
	LEVEL7,
	LEVEL10,
}

static var _is_ios: bool = OS.get_name() == "iOS" # 平台判定只做一次

static var _map_low: Dictionary = {} # 低内存机的 Android 参数表（惰性构建）
static var _map_high: Dictionary = {} # 高内存机的 Android 参数表（惰性构建）
static var _maps_ready: bool = false # 参数表是否已构建过

# iOS 档位 → 系统震动反馈的方法名，直接反射调用
static var _map_ios: Dictionary = {
	Level.LEVEL1: "selectionChanged",
	Level.LEVEL2: "feedbackMedium",
	Level.LEVEL3: "feedbackHeavy",
	Level.LEVEL4: "longVibrate",
	Level.LEVEL5: "notificationSuccess",
	Level.LEVEL7: "longVibrate",
	Level.LEVEL10: "longVibrate",
}


# 构建 Android 的两张参数表：d = 持续毫秒，a = 振幅（0~255）
static func _build_maps() -> void:
	if _maps_ready:
		return
	_maps_ready = true

	var ct := PackedInt32Array()
	var ca := PackedInt32Array()
	for i: int in 20:
		ct.append(50)
		ca.append(roundi(10.0 + 140.0 * (float(i) / 19.0)))
	# 20 段渐强图案，当前两张表都没引用它（历史遗留，_play_android 里仍留着 "t" 分支）
	var _charge: Dictionary = {"t": ct, "a": ca}

	# 低内存机：震动时间略长、振幅偏小
	_map_low = {
		Level.LEVEL1: {"d": 40, "a": 10},
		Level.LEVEL2: {"d": 40, "a": 80},
		Level.LEVEL3: {"d": 40, "a": 200},
		Level.LEVEL4: {"d": 200, "a": 50},
		Level.LEVEL5: {"d": 60, "a": 250},
		Level.LEVEL7: {"d": 130, "a": 50},
		Level.LEVEL10: {"d": 200, "a": 50},
	}

	# 高内存机：同样的档位改为「更短更脆」的手感
	_map_high = {
		Level.LEVEL1: {"d": 20, "a": 10},
		Level.LEVEL2: {"d": 20, "a": 80},
		Level.LEVEL3: {"d": 20, "a": 150},
		Level.LEVEL4: {"d": 200, "a": 50},
		Level.LEVEL5: {"d": 30, "a": 250},
		Level.LEVEL7: {"d": 130, "a": 50},
		Level.LEVEL10: {"d": 200, "a": 50},
	}


# 超过这个内存（MB）就算高内存机；只有 Android 需要区分
const _RAM_4G_MB: int = 3800
static var _ram_ready: bool = false # 内存档位是否已探测过
static var _is_high_ram: bool = false # 探测结果


# 探测一次总内存，决定用哪张 Android 参数表；iOS 不需要
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


# 开关震动（设置页里改）
static func set_enabled(on: bool) -> void:
	_enabled = on


# 当前是否允许震动
static func is_enabled() -> bool:
	return _enabled


# 取原生插件单例；没装插件就返回 null，调用方一律判空
static func _plugin() -> Object:
	if Engine.has_singleton("VibratePlugin"):
		return Engine.get_singleton("VibratePlugin")
	return null


# 设备是否有振动器
static func has_vibrator() -> bool:
	var p: Object = _plugin()
	if p == null:
		return false
	return p.hasVibrator() as bool


# 是否支持控制振幅（iOS 一律不支持，只能选固定几种反馈）
static func has_amplitude_control() -> bool:
	if _is_ios:
		return false
	var p: Object = _plugin()
	if p == null:
		return false
	return p.hasAmplitudeControl() as bool


# 对外主入口：按档位震一下，按平台分派
static func play_vibrate(level: Level) -> void:
	if not _enabled:
		return
	if _is_ios:
		_play_ios(level)
	else:
		_play_android(level)


# 打断当前震动
static func cancel() -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.cancel()


# iOS：按档位反射调用系统反馈方法名，表里没有的档位不震
static func _play_ios(level: Level) -> void:
	if not _map_ios.has(level):
		return
	var p: Object = _plugin()
	if p == null:
		return
	var method_name: String = _map_ios[level]
	p.call(method_name)


# Android：先定内存档位，再从对应表里取 d/a 参数执行
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


# 单次震动：持续 duration_ms 毫秒，振幅 amplitude
static func _vibrate(duration_ms: int, amplitude: int) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.vibrate(duration_ms, amplitude)


# 节奏震动：timings_ms 与 amplitudes 两个数组描述「停多久 / 震多强」的交替序列
static func _vibrate_pattern(timings_ms: PackedInt32Array, amplitudes: PackedInt32Array) -> void:
	var p: Object = _plugin()
	if p == null:
		return
	p.vibratePattern(timings_ms, amplitudes)
