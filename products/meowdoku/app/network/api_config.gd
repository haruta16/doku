## 网络协议配置：统一业务接口、推荐接口、平台标识与业务错误码。
class_name ApiConfig
extends RefCounted

const APP_ID: String = "com.oakever.meowdoku"


## 把当前构建映射到服务端平台名；非 iOS 构建使用 Android 标识。
static func platform() -> String:
	return "ios" if OS.has_feature("ios") else "android"


const _BASE_URL_DEV: String = "https://meowdoku-api-dev.dailyinnovation.biz"
const _BASE_URL_PROD: String = "https://meowdoku-api.dailyinnovation.biz"


## 按发布特性选择业务 API 地址，开发构建使用开发环境。
static func base_url() -> String:
	return _BASE_URL_PROD if _is_production() else _BASE_URL_DEV


## rel 和 pre 特性共用生产地址，判断依据是构建特性而非编辑器开关。
static func _is_production() -> bool:
	return OS.has_feature("rel") or OS.has_feature("pre")


const _REC_BASE_URL_DEV: String = "https://meowdoku-rec-api-dev.dailyinnovation.biz"
const _REC_BASE_URL_PROD: String = "https://meowdoku-rec-api.dailyinnovation.biz"


## 按同一环境规则选择题目推荐服务地址。
static func rec_base_url() -> String:
	return _REC_BASE_URL_PROD if _is_production() else _REC_BASE_URL_DEV


const _SIGN_SECRET: String = "htqcuibn9AFeG8LGZqmSvWzaATJB7r"


## 向请求签名流程提供发布包内的协议常量。
static func sign_secret() -> String:
	return _SIGN_SECRET


## 读取 UniKit 分配的用户标识，供请求头与认证初始化共用。
static func luid() -> String:
	return UniKitManager.get_luid()


## 读取登录 SDK 的设备标识，与统计用户标识分别传给服务端。
static func device_id() -> String:
	return AuthManager.get_device_id()


const PATH_SYNC_GAMEDATA: String = "/sync/v1/gamedata"
const PATH_SYNC_GAMEDATA_META: String = "/sync/v1/gamedata/meta"
const PATH_ACCOUNT_INFO: String = "/account/v1/info"

const PATH_REC_QUESTION_NEXT: String = "/meowdoku/v1/dispatch/rec/question/next"

const CODE_OK: int = 0
const CODE_ACCOUNT_DELETED: int = 1003
const CODE_ACCESS_TOKEN_INVALID: int = 1004
const CODE_ACCESS_TOKEN_EXPIRED: int = 1005
const CODE_SIGN_INVALID: int = 1006
const CODE_TIMESTAMP_EXPIRED: int = 1007
const CODE_REFRESH_TOKEN_INVALID: int = 1008
const CODE_REFRESH_TOKEN_EXPIRED: int = 1009
const CODE_NO_SAVE: int = 2001
const CODE_SCHEMA_TOO_LOW: int = 2002
const CODE_SYNC_CODE_TOO_LOW: int = 2003
