## 平台工具入口：统一版本、网络、启动参数、崩溃上报和 iOS 音频恢复能力。
extends Node

var _native: Object = null


## 打印 Autoload 初始化前的毫秒时间点，用于分析冷启动耗时。
func _init() -> void:
	print("[BootProbe] before_autoloads=%dms" % Time.get_ticks_msec())


## 取得 NativeUtilPlugin 单例；没有原生插件时保留脚本端默认行为。
func _ready() -> void:
	if Engine.has_singleton("NativeUtilPlugin"):
		_native = Engine.get_singleton("NativeUtilPlugin")
	else:
		push_warning("NativeUtilPlugin not available (editor / 非移动端)")


## 判断原生工具单例是否已取得。
func is_available() -> bool:
	return _native != null


## 读取安装包版本名；原生插件缺失时回退到工程配置。
func get_version_name() -> String:
	if _native == null:
		return ProjectSettings.get_setting("application/config/version", "") as String
	return _native.getVersionName() as String


## 读取安装包版本号；缺少原生插件时返回 0。
func get_version_code() -> int:
	if _native == null:
		return 0
	return int(_native.getVersionCode())


## 向原生层查询联网状态；没有插件时按可联网处理。
func is_online() -> bool:
	if _native == null:
		return true
	return _native.isOnline()


## 读取原生网络类型；没有插件时返回 unknown。
func get_network_type() -> String:
	if _native == null:
		return "unknown"
	return _native.getNetworkType()


## 读取首次打开应用的毫秒时间戳；没有插件时返回 0。
func get_first_open_time_ms() -> int:
	if _native == null:
		return 0
	return int(_native.getFirstOpenTimeMs())


## 将业务用户标识交给原生崩溃统计，便于关联同一用户的异常。
func set_crashlytics_user_id(user_id: String) -> void:
	if _native == null:
		return
	_native.setCrashlyticsUserId(user_id)


## 把消息与格式化调用栈交给原生异常上报入口。
func log_crashlytics_exception(message: String, stack: String) -> void:
	if _native == null:
		return
	_native.logCrashlyticsException(message, stack)


## 读取本次启动携带的通知参数；没有插件时返回空串。
func get_launch_push_extras() -> String:
	if _native == null:
		return ""
	return _native.getLaunchPushExtras() as String


## 仅在 iOS 原生插件可用时请求系统评分界面。
func request_store_review() -> void:
	if not OS.has_feature("ios"):
		return
	if _native == null:
		return
	_native.requestStoreReview()


## 通知 iOS 原生启动屏按指定毫秒时长淡出。
func hide_native_splash(fade_ms: int) -> void:
	if not OS.has_feature("ios"):
		return
	if _native == null:
		return
	_native.hideSplash(fade_ms)


## 在 iOS 注册音频缓冲恢复逻辑，处理原生音频会话变化。
func setup_audio_io_buffer_recovery() -> void:
	if not OS.has_feature("ios"):
		return
	if _native == null:
		return
	_native.setupAudioIOBufferRecovery()


## 临时暂停 iOS 音频恢复逻辑，交由当前原生流程管理音频。
func pause_audio_io_buffer_recovery() -> void:
	if not OS.has_feature("ios"):
		return
	if _native == null:
		return
	_native.pauseAudioIOBufferRecovery()


## 恢复先前暂停的 iOS 音频缓冲管理。
func resume_audio_io_buffer_recovery() -> void:
	if not OS.has_feature("ios"):
		return
	if _native == null:
		return
	_native.resumeAudioIOBufferRecovery()
