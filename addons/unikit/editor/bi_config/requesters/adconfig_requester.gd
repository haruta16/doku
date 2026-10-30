## 广告配置请求器：按广告 SDK 版本、平台和环境选择接口，并生成本地广告配置。
@tool
class_name UniKitAdConfigRequester
extends UniKitBIConfigRequester


## 提供广告配置的日志名称。
func config_name() -> String:
	return "adconfig"


## 结合 SDK 主版本、平台和调试模式拼接广告配置请求地址。
func get_url(production_id: String, is_debug: bool, platform: String) -> String:
	var tag := "-test" if is_debug else ""
	var api_key := APIKEY_ADCONFIG_IOS if platform == PLATFORM_IOS else APIKEY_ADCONFIG_ANDROID
	var path := (
		"v6/production/%s/strategies"
		if ad_major_version == AD_MAJOR_6
		else "v7/production/%s/fallback/strategies"
	)
	return (
		"https://api%s.learnings.ai/adconfig/%s?apiKey=%s"
		% [tag, path % production_id.strip_edges(), api_key]
	)


## 检查响应 data 是字典后导出 JSON，异常结构返回空串让上层报告失败。
func preprocess(content: String) -> String:
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[adconfig] 响应非 JSON object: %s" % content.substr(0, 200))
		return ""
	if typeof(parsed.get("data")) != TYPE_DICTIONARY:
		push_error("[adconfig] 响应无 data object: %s" % content.substr(0, 200))
		return ""
	return JSON.stringify(parsed["data"])


## 将配置保存到 Android 原生资源或 iOS 广告资源包。
func get_save_paths(platform: String, is_debug: bool, ios_config_dir: String) -> PackedStringArray:
	if platform == PLATFORM_ANDROID:
		return PackedStringArray([_android_config_dir(is_debug).path_join("ad_config.json")])
	return PackedStringArray(
		[ios_config_dir.rstrip("/").path_join("adconfigs.bundle/ad_config.json")]
	)
