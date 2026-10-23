## BI 配置请求器基类：约定名称、地址、预处理和保存位置，供不同配置类型覆盖。
@tool
class_name UniKitBIConfigRequester
extends RefCounted

const PLATFORM_ANDROID := "android"
const PLATFORM_IOS := "ios"

const AD_MAJOR_6 := 0
const AD_MAJOR_7 := 1

var ad_major_version: int = AD_MAJOR_7

const APIKEY_ADCONFIG_IOS := "893ea460-b845-4cad-a983-75957ce9f3c4"
const APIKEY_ADCONFIG_ANDROID := "c63cf6be-0a70-4d4c-b10f-acaafa09b3f1"
const APIKEY_USERTAG := "893ea460-b845-4cad-a983-75957ce9f3c4"

const ANDROID_CONFIG_DIR_RELEASE := "res://android/build/src/release/assets/config"
const ANDROID_CONFIG_DIR_DEBUG := "res://android/build/src/debug/assets/config"


## 提供基础名称，具体请求器覆盖后用于日志定位。
func config_name() -> String:
	return "base"


## 基础实现没有请求地址，子类按产品与环境生成接口地址。
func get_url(_production_id: String, _is_debug: bool, _platform: String) -> String:
	return ""


## 基础实现原样返回响应，子类可提取服务端数据或校验结构。
func preprocess(content: String) -> String:
	return content


## 基础实现没有保存目标，子类按平台指定原生构建需要的位置。
func get_save_paths(
	_platform: String, _is_debug: bool, _ios_config_dir: String
) -> PackedStringArray:
	return PackedStringArray()


## 基础请求器默认支持所有平台，专用配置可缩小范围。
func supports_platform(_platform: String) -> bool:
	return true


## 基础实现不附加请求头，特定接口可覆盖调用方标识。
func get_request_headers() -> Dictionary:
	return {}


## 按调试或发布模式选择 Android 原生资源配置目录。
func _android_config_dir(is_debug: bool) -> String:
	return ANDROID_CONFIG_DIR_DEBUG if is_debug else ANDROID_CONFIG_DIR_RELEASE
