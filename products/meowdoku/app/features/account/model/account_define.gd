## 账号渠道的枚举与展示规则；按平台决定可选渠道，并提供统一的显示名称。

extends RefCounted
class_name AccountDefine

const CHANNEL_GOOGLE: String = "google"

const CHANNEL_FACEBOOK: String = "facebook"

const CHANNEL_APPLE: String = "apple"

const ALL_CHANNELS: Array = [CHANNEL_GOOGLE, CHANNEL_FACEBOOK, CHANNEL_APPLE]

const _CHANNELS_IOS: Array = [CHANNEL_FACEBOOK, CHANNEL_GOOGLE, CHANNEL_APPLE]

const _CHANNELS_ANDROID: Array = [CHANNEL_FACEBOOK, CHANNEL_GOOGLE]

const _CHANNELS_DEV: Array = [CHANNEL_FACEBOOK, CHANNEL_GOOGLE, CHANNEL_APPLE]

const _DISPLAY_NAMES: Dictionary = {
	CHANNEL_GOOGLE: "Google",
	CHANNEL_FACEBOOK: "Facebook",
	CHANNEL_APPLE: "Apple",
}


static func is_valid_channel(ch: String) -> bool:
	return ALL_CHANNELS.has(ch)


static func display_name(ch: String) -> String:
	return str(_DISPLAY_NAMES.get(ch, ""))


static func available_channels() -> Array:
	if OS.has_feature("ios"):
		return channels_for_platform("ios")
	if OS.has_feature("android"):
		return channels_for_platform("android")
	if OS.has_feature("rel"):
		return []
	return _CHANNELS_DEV.duplicate()


## 集中定义平台支持的渠道列表；页面据此生成入口，避免显示当前平台无法使用的方式。
static func channels_for_platform(platform: String) -> Array:
	match platform:
		"ios":
			return _CHANNELS_IOS.duplicate()
		"android":
			return _CHANNELS_ANDROID.duplicate()
	return []
