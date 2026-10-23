## 实验配置请求器：区分调试和发布接口，把服务端数据保存为平台的本地实验配置。
@tool
class_name UniKitABTestRequester
extends UniKitBIConfigRequester


## 提供实验配置的日志名称。
func config_name() -> String:
	return "abtest"


## 根据环境选择对应实验接口，并带上产品标识。
func get_url(production_id: String, is_debug: bool, _platform: String) -> String:
	var tag := "-test" if is_debug else ""
	return (
		"https://api%s.learnings.ai/pm/abtest/v6.1/production/%s/params?versionCode=0&expOriginType=A"
		% [tag, production_id]
	)


## 从响应中提取 data，重新编码为本地配置 JSON。
func preprocess(content: String) -> String:
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("data"):
		push_error("[abtest] 响应无 data 字段: %s" % content.substr(0, 200))
		return ""
	return JSON.stringify(parsed["data"])


## 选择 Android 配置目录或 iOS 的正式、调试实验文件名。
func get_save_paths(platform: String, is_debug: bool, ios_config_dir: String) -> PackedStringArray:
	if platform == PLATFORM_ANDROID:
		return PackedStringArray([_android_config_dir(is_debug).path_join("abtest_config.json")])
	var fname := "ABTest_Debug.json" if is_debug else "ABTest.json"
	return PackedStringArray([ios_config_dir.rstrip("/").path_join(fname)])
