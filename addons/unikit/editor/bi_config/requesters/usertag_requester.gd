## iOS 用户标签配置请求器：下载设备性能分组配置，供原生 SDK 启动时读取。
@tool
class_name UniKitUserTagRequester
extends UniKitBIConfigRequester


## 提供用户标签配置的日志名称。
func config_name() -> String:
	return "usertag"


## 这份本地设备标签配置只用于 iOS 平台。
func supports_platform(platform: String) -> bool:
	return platform == PLATFORM_IOS


## 按产品标识生成配置地址，调试与发布共用此接口。
func get_url(production_id: String, _is_debug: bool, _platform: String) -> String:
	return (
		"https://api.learnings.ai/usertag/low_perf_devices/%s?apiKey=%s"
		% [production_id, APIKEY_USERTAG]
	)


## 附加工程名称和版本组成的调用方标识。
func get_request_headers() -> Dictionary:
	var app_name := str(ProjectSettings.get_setting("application/config/name", "godot"))
	var app_ver := str(ProjectSettings.get_setting("application/config/version", "0"))
	return {"x-learnings-caller": "%s-%s" % [app_name, app_ver]}


## 指定 iOS 原生资源需要的设备标签配置文件。
func get_save_paths(platform: String, _is_debug: bool, ios_config_dir: String) -> PackedStringArray:
	if platform != PLATFORM_IOS:
		return PackedStringArray()
	return PackedStringArray([ios_config_dir.rstrip("/").path_join("UserTagLowPerfDevice.json")])
