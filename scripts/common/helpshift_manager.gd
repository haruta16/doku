# 客服工单（Helpshift）封装：autoload 名 HelpshiftManager，负责安装插件、打开 FAQ、拉未读数
extends Node

# 未读消息数变化信号（UI 目前实际走 RedDotCenter，本仓暂无订阅者）
signal unread_count_changed(count: int)

# ---- Helpshift 后台凭据与常量（iOS 侧初始化用，本文件不引用这两个 iOS 常量） ----
# Android 应用 ID，install() 时传入
const ANDROID_APP_ID: String = "arsenal-support_platform_20260610074440920-419e5d01b34cf98"
# iOS platformId（本文件未使用，给原生侧初始化）
const IOS_PLATFORM_ID: String = "arsenal-support_platform_20260610074440901-cc1ce66e7ed9026"
# iOS apiKey（本文件未使用，给原生侧初始化）
const IOS_API_KEY: String = "f6e712714ec70365ca39e75ec59799f2"
# Helpshift 后台域名，install() 时传入
const DOMAIN: String = "arsenal-support.helpshift.com"

# 活跃窗口 2 天（秒）：距上次打开帮助页超过这个时间就不再预热
const ACTIVE_WINDOW_SEC: int = 2 * 86400

# 红点 ID，与 setting_page.tscn / settings_btn.tscn 里的 dot_id 对应
const DOT_HELPSHIFT_UNREAD: String = "helpshift_unread"

# ---- 运行时状态 ----
# 插件是否已安装且信号已接好；false 时所有对外接口直接返回
var _is_active: bool = false
# 最近一次原生回调的未读消息数
var _unread_count: int = 0


# 取 Helpshift 原生插件单例；插件不存在（编辑器 / 桌面端）返回 null
func _plugin() -> Object:
	if Engine.has_singleton("HelpshiftPlugin"):
		return Engine.get_singleton("HelpshiftPlugin")
	return null


# 引擎通知回调：从后台回到前台时刷新未读数
func _notification(what: int) -> void:
	# 只在获得焦点时动作
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		request_unread()


# 预热：仅当 2 天内打开过帮助页才安装插件并拉未读数，避免冷启动浪费（本仓暂无调用点）
func preheat() -> void:
	if _is_active:
		return
	# 取上次打开帮助页的 unix 秒时间戳；0 表示从未打开
	var last: int = GameState.get_help_last_open_time()
	# 从未打开或已超过 2 天窗口：直接不预热
	if last <= 0 or (_now() - last) > ACTIVE_WINDOW_SEC:
		return
	_install()
	if _is_active:
		request_unread()


# 打开 FAQ 帮助页：未安装先安装，顺手记录本次打开时间并刷新未读数
func open_faq() -> void:
	# 懒安装：真正要用的时候才装
	if not _is_active:
		_install()
	var p: Object = _plugin()
	if p == null:
		return
	# 记录打开时刻并落盘，用于下次判断是否预热
	GameState.set_help_last_open_time(_now())
	p.showFAQs("ALWAYS", _build_metadata(), _build_cifs())

	request_unread()


# 拉取未读消息数：结果通过原生的 unread_message_count 信号异步回来
func request_unread() -> void:
	# 没装插件就不要请求
	if not _is_active:
		return
	var p: Object = _plugin()
	if p == null:
		return
	p.requestUnreadMessageCount(true)


# 读未读数（只反映最近一次原生回调的值，不触发网络请求）
func get_unread_count() -> int:
	return _unread_count


# 安装插件并接上原生信号；只在 Android 调 install（iOS 由原生侧初始化）
func _install() -> void:
	var p: Object = _plugin()
	if p == null:
		return
	# iOS 不从这里 install，走原生初始化
	if OS.has_feature("ios"):
		pass
	else:
		p.install(ANDROID_APP_ID, DOMAIN, false, false)
	# 幂等：重复安装时避免信号被接两次
	if not p.is_connected("unread_message_count", _on_native_unread):
		p.connect("unread_message_count", _on_native_unread)
	if not p.is_connected("auth_failure", _on_native_auth_failure):
		p.connect("auth_failure", _on_native_auth_failure)
	_is_active = true


# 原生未读数回调：更新缓存、发信号、同步到红点中心
func _on_native_unread(count: int) -> void:
	_unread_count = count
	unread_count_changed.emit(count)

	RedDotCenter.set_count(DOT_HELPSHIFT_UNREAD, count)


# 原生鉴权失败回调：只打警告，不影响游戏流程
func _on_native_auth_failure(reason: String) -> void:
	push_warning("[Helpshift] auth failure: %s" % reason)


# 组装随工单上报的用户资料（uuid、关卡数、渠道等）
func _build_metadata() -> Dictionary:
	var inner: Dictionary = UniKitManager.get_inner_tags()
	return {
		"uuid": UniKitManager.get_uuid(),
		"luid": UniKitManager.get_luid(),
		"hit_the_experimental_group": UniKitManager.get_ab_dyeing_tag(),
		"country": UniKitManager.get_ab_country(),
		"number_of_levels": GameState.get_current_level(),
		"living_day": GameState.get_active_days(),
		"locate_count": GameState.get_tool_count("locate"),
		"hint_count": GameState.get_tool_count("hint"),
		"install_version": GameState.get_install_version(),
		"source_of_channels": inner.get("media_source", ""),
		"flow_domain": inner.get("pm_flow_domain", ""),
	}


# 组装自定义工单字段（CIF）：Helpshift 要求每项带 type 和 value
func _build_cifs() -> Dictionary:
	var inner: Dictionary = UniKitManager.get_inner_tags()
	return {
		"uuid": {"type": "singleline", "value": UniKitManager.get_uuid()},
		"living_day": {"type": "singleline", "value": str(GameState.get_active_days())},
		"number_of_levels": {"type": "singleline", "value": str(GameState.get_current_level())},
		"hit_the_experimental_group":
		{"type": "multiline", "value": UniKitManager.get_ab_dyeing_tag()},
		"source_of_channels": {"type": "singleline", "value": str(inner.get("media_source", ""))},
		"install_version": {"type": "singleline", "value": GameState.get_install_version()},
	}


# 当前 unix 秒时间戳（系统时钟）
func _now() -> int:
	return int(Time.get_unix_time_from_system())
