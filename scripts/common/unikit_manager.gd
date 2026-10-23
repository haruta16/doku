## 游戏侧 SDK 门面：协调广告会话、奖励补偿、通知、统计与实验，并保留编辑器模拟入口。
extends Node

# ---- 信号：推送权限、设备标识、广告结果 ----
## 推送权限流程走完（或者判定不需要弹）
signal push_permission_done
## 原生 LUID 就绪（客服工单与 AB 上报会用到）
signal luid_ready(luid: String)
signal usertag_ready(data: Dictionary)
## 广告关闭，参数是广告位（interstitial / reward / banner …）
signal ad_closed(placement_id: String)
## 激励视频看完并确认发奖
signal ad_rewarded(placement_id: String)

# ---- 信号：广告播放过程与推送指令 ----
## 广告真正展示出来（SoundManager 靠它暂停 BGM，埋点也靠它）
signal ad_shown(placement_id: String)
## 广告出错（加载或展示失败）
signal ad_error_occurred(placement_id: String, msg: String)
## 收到曝光回调，data 是原生 JSON 解析后的字典
signal ad_impression_received(data: Dictionary)

signal ad_loaded(placement_id: String)
## 收到推送下发的指令 JSON，由业务侧自行解析
signal push_cmd_received(cmd_json: String)

# ---- 信号：各子模块初始化完成 ----
## 统计（analyze / Crashlytics）初始化完成，缓存的异常已补报
signal analyze_init_completed
## 广告模块初始化完成
signal ad_init_completed

# ---- 信号：AB 实验 ----
## AB 参数首次就绪
signal abtest_ready(user_info: Dictionary)
## AB 参数发生变化（update_type 区分来源）
signal abtest_params_updated(update_type: String, user_info: Dictionary)
## 远端 AB 配置拉取完成
signal abtest_remote_config_ready

signal abtest_locsrv_fetched(success: bool)

# ---- 信号：合规与授权 ----
## CMP（GDPR 等隐私同意）流程结束
signal cmp_completed

## iOS ATT 授权状态变化，取值见下面的 ATT_STATUS_*
signal att_status_changed(status: int)

## ATT 系统弹窗被关闭（不管用户选了什么）
signal att_dismissed

# ---- 常量：ATT 授权状态（取值与 iOS 原生一致） ----
## 尚未询问，只有这个状态下才允许调起系统弹窗
const ATT_STATUS_NOT_DETERMINED: int = 0
## 已授权
const ATT_STATUS_AUTHORIZED: int = 1
## 系统层面拒绝（如家长控制）
const ATT_STATUS_SYSTEM_DENIED: int = 2
## 用户自己点了拒绝
const ATT_STATUS_APP_DENIED: int = 3

# ---- 常量：推送权限申请方式 ----
## 只弹系统权限弹窗
const PUSH_PERMISSION_TYPE_SYSTEM: int = 1
## 系统权限 + 引导去设置页（默认值）
const PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING: int = 2
## 只引导去系统设置页
const PUSH_PERMISSION_TYPE_SETTING: int = 3

const _AD_QUERY_TIMEOUT_SEC: float = 3.0

## 编辑器里强制走 ATT 测试流程（作弊指令置位，流程结束由 AttGuideHelper 复位）
static var debug_force_editor_test: bool = false

# ---- 插屏状态与作弊开关 ----
## 上次插屏关闭的 unix 秒，用来算冷却
var _last_interstitial_close_unix: int = 0

## 广告位 → 本次展示用的 position，曝光回调取走后删除
var _pending_ad_positions: Dictionary = {}

## 调试总开关（默认 true）；false 时 show_interstitial 直接不展示
var _debug_ad_enabled: bool = true

## 三个作弊开关：编辑器默认关（= false），真机包默认开，由作弊面板切换
## 是否允许展示插屏
var cheat_show_interstitial: bool = not OS.has_feature("editor")
## 是否允许展示激励视频（关掉则直接发奖）
var cheat_show_reward: bool = not OS.has_feature("editor")
## 是否允许展示 banner
var cheat_show_banner: bool = not OS.has_feature("editor")

## 作弊：模拟「视频看完却不发奖」，用于验证发奖兜底
var _debug_reward_miss: bool = false

# ---- Crashlytics 异常缓存 ----
## 统计未初始化时最多缓存多少条异常，超出丢最旧的
const _CRASHLYTICS_LOG_CACHE_MAX: int = 20
## 初始化前攒下的异常，元素形如 {message, stack}
var _crashlytics_log_cache: Array[Dictionary] = []
## 统计模块是否已初始化
var _is_analyze_inited: bool = false
## 广告模块是否已初始化
var _is_ad_inited: bool = false

var _banner_load_requested: bool = false

var _banner_show_requested: bool = false

# ---- 激励视频发奖兜底 ----
## 关广告后等这么久（秒）还没收到发奖回调，就记一笔待补发
const _REWARD_GRANT_TIMEOUT_SEC: float = 30.0

## 本次激励视频的 show_id（空串 = 没有进行中的会话）
var _reward_active_show_id: String = ""

## 本次激励视频的 position，补发时用来说明来源
var _reward_active_position: String = ""

## 本次会话是否已收到发奖回调
var _reward_received: bool = false

## 本次广告是否真的展示过（没展示就不该发奖）
var _reward_shown: bool = false

## 等待发奖的看门狗：show_id → {position, ts}
var _pending_watchdogs: Dictionary = {}


## 连接 UniKit 子模块事件、配置音频恢复，并更新首次安装与版本迁移状态。
func _ready() -> void:
	_is_analyze_inited = true
	_flush_crashlytics_cache()

	if UniKit.ad_module.is_ad_inited():
		_on_ad_init_success()
	else:
		UniKit.ad_module.ad_init_completed.connect(_on_ad_init_success)

	UniKit.ad_module.ad_closed.connect(_on_ad_closed)
	UniKit.ad_module.ad_rewarded.connect(_on_ad_rewarded)
	UniKit.ad_module.ad_will_show.connect(_on_ad_shown)
	UniKit.ad_module.ad_error_occurred.connect(_on_ad_error)
	UniKit.ad_module.ad_impression_received.connect(_on_ad_impression)

	NativeUtilManager.setup_audio_io_buffer_recovery()

	UniKit.ad_module.ad_loaded.connect(
		func(placement_id: String) -> void: ad_loaded.emit(placement_id)
	)

	UniKit.abtest_module.abtest_ready.connect(abtest_ready.emit)
	UniKit.abtest_module.abtest_params_updated.connect(abtest_params_updated.emit)
	UniKit.abtest_module.abtest_remote_config_ready.connect(abtest_remote_config_ready.emit)
	UniKit.abtest_module.abtest_locsrv_fetched.connect(abtest_locsrv_fetched.emit)

	UniKit.push_module.push_cmd_received.connect(push_cmd_received.emit)
	UniKit.push_module.push_permission_done.connect(push_permission_done.emit)

	UniKit.usertag_module.luid_ready.connect(luid_ready.emit)
	UniKit.usertag_module.usertag_ready.connect(usertag_ready.emit)

	UniKit.cmp_completed.connect(cmp_completed.emit)
	UniKit.att_status_changed.connect(att_status_changed.emit)
	UniKit.att_dismissed.connect(att_dismissed.emit)

	GameState.ensure_first_open_time(get_first_open_time_ms())
	var current_version: String = get_version_name()
	GameState.ensure_install_version(current_version)

	NormalLevelGroupTag.update_missing_tag_on_startup(
		GameState.get_current_level(), GameState.is_first_session()
	)

	GameState.resolve_version_upgrade(current_version)


## 退出场景树时清理原生单例保存的自定义回调引用。
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		_disconnect_native_lambda_callables()


## 断开原生信号中的自定义 Callable，避免退出后继续持有脚本闭包。
func _disconnect_native_lambda_callables() -> void:
	if not Engine.has_singleton("UniKitPlugin"):
		return
	var plugin: Object = Engine.get_singleton("UniKitPlugin")
	var sig_list: Array = plugin.get_signal_list()
	for sig: Dictionary in sig_list:
		var sig_name: String = sig["name"]
		var conns: Array = plugin.get_signal_connection_list(sig_name)
		for conn: Dictionary in conns:
			var cb: Callable = conn["callable"]
			if cb.is_custom():
				plugin.disconnect(sig_name, cb)


## 查询底层原生 UniKit 是否可用，供游戏选择原生或回退路径。
func is_available() -> bool:
	return UniKit.is_available()


var _mock_offline: bool = false

var _mock_no_fill: bool = false


## 优先采用调试离线开关，否则查询平台网络状态。
func is_online() -> bool:
	if _mock_offline:
		return false
	return NativeUtilManager.is_online()


## 读取原生网络类型；没有插件时返回 unknown。
func get_network_type() -> String:
	return NativeUtilManager.get_network_type()


## 查询原生 SDK 是否要求展示隐私界面，插件缺失时返回 false。
func check_privacy_required() -> bool:
	return UniKit.check_privacy_required()


## 通知原生 SDK 用户已同意隐私条款。
func agree_privacy() -> void:
	UniKit.agree_privacy()


## 查询原生持久化的隐私同意状态。
func is_privacy_agreed() -> bool:
	return UniKit.is_privacy_agreed()


## 注册一次性业务回调，完成转化报告注册后发起 CMP 检查。
func check_cmp(on_done: Callable = Callable()) -> void:
	if on_done.is_valid():
		cmp_completed.connect(on_done, CONNECT_ONE_SHOT)

	UniKit.register_icm_conversion_report()
	UniKit.check_cmp()


## 查询是否需要展示 CMP 隐私同意界面。
func check_cmp_required() -> bool:
	return UniKit.check_cmp_required()


## 请求原生显示 CMP 界面。
func show_cmp_ui() -> void:
	UniKit.show_cmp_ui()


## 编辑器强制测试时允许展示模拟流程，否则采用原生判断。
func can_show_att() -> bool:
	if OS.has_feature("editor") and debug_force_editor_test:
		return true
	return UniKit.can_show_att()


## 仅在 iOS 初始化 ATT 相关原生状态。
func init_att() -> void:
	UniKit.init_att()


## 编辑器测试时用 2 秒定时器模拟授权与关闭，真机交给原生接口。
func show_att_alert(source: String) -> void:
	if OS.has_feature("editor") and debug_force_editor_test:
		print("[UniKit] (editor mock) showATTAlert source=%s,2 秒后模拟用户授权 + dismissed" % source)
		var timer: SceneTreeTimer = Engine.get_main_loop().create_timer(2.0)
		timer.timeout.connect(
			func() -> void:
				att_status_changed.emit(ATT_STATUS_AUTHORIZED)
				att_dismissed.emit()
		)
		return
	UniKit.show_att_alert(source)


## 读取 iOS ATT 状态，其他环境回退到尚未询问。
func get_att_status() -> int:
	return UniKit.get_att_status()


## 仅在 iOS 原生插件可用时触发广告加载失败测试。
func debug_mock_ad_load_fail() -> void:
	UniKit.ad_module.debug_mock_ad_load_fail()


## 把业务账号标识交给原生 SDK，以关联统计和实验身份。
func set_account_id(account_id: String) -> void:
	UniKit.set_account_id(account_id)


## 请求原生按地区处理隐私链接；无插件时保留原链接。
func get_localized_privacy_url(url: String) -> String:
	return UniKit.get_localized_privacy_url(url)


# ================= 推送与本地通知 =================
## 开局申请推送权限的快捷入口：固定「只弹系统权限」，来源标记 app_start
func request_push_permission() -> void:
	request_notification_permission(PUSH_PERMISSION_TYPE_SYSTEM, "app_start")


## 检查平台能力后发起权限流程，无法申请时也延迟发完成信号。
func request_notification_permission(
	type: int = PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING, position: String = "default"
) -> void:
	UniKit.push_module.request_notification_permission(type, position)


## 把本地小时数转换为下一次提醒日期，并建立 24 小时重复通知。
func add_daily_push(
	push_id: String, hour_local: float, contents: Array[Dictionary], disturb_type: int = 1
) -> void:
	UniKit.push_module.add_daily_push(push_id, hour_local, contents, disturb_type)


## 按本地日历偏移指定天数建立每日通知，避免只用秒数推算日期。
func add_daily_push_from_offset(
	push_id: String,
	day_offset: int,
	hour_local: float,
	contents: Array[Dictionary],
	disturb_type: int = 1
) -> void:
	var plugin: Object = Engine.get_singleton("UniKitPlugin")
	if plugin == null:
		return
	var target_hour: int = int(hour_local)
	var target_minute: int = int(round((hour_local - float(target_hour)) * 60.0))
	var local: Dictionary = Time.get_datetime_dict_from_system()
	if day_offset > 0:
		var shifted: Dictionary = _local_date_offset(
			int(local["year"]), int(local["month"]), int(local["day"]), day_offset
		)
		local["year"] = shifted["year"]
		local["month"] = shifted["month"]
		local["day"] = shifted["day"]

	var advance_one_day: bool = (
		day_offset == 0
		and (
			local["hour"] > target_hour
			or (local["hour"] == target_hour and local["minute"] >= target_minute)
		)
	)
	var normalized: Array[Dictionary] = _normalize_push_contents(contents, OS.has_feature("ios"))
	var contents_dict: Dictionary = {}
	for i: int in range(normalized.size()):
		contents_dict["%s_c%d" % [push_id, i]] = normalized[i]
	var push_data: Dictionary = {
		"push_id": push_id,
		"local_year": local["year"],
		"local_month": local["month"],
		"local_day": local["day"],
		"local_hour": target_hour,
		"local_minute": target_minute,
		"advance_one_day": advance_one_day,
		"push_time_ms": 0,
		"repeat_interval_ms": 86400000,
		"is_infinite_repeat": true,
		"disturb_type": disturb_type,
		"contents": contents_dict,
	}

	print(
		"[UniKitManager] add_daily_push_from_offset: %s" % JSON.stringify(push_data).substr(0, 300)
	)
	plugin.saveLocalPush(JSON.stringify(push_data))


const _PUSH_CONTENT_FIELDS: Dictionary = {
	"title": {"ios": true, "type": TYPE_STRING},
	"content": {"ios": true, "type": TYPE_STRING},
	"large_icon": {"ios": true, "type": TYPE_STRING},
	"content_image": {"ios": true, "type": TYPE_STRING},
	"sound": {"ios": true, "type": TYPE_STRING},
	"bg_color": {"ios": false, "type": TYPE_STRING},
	"btn_bg_color": {"ios": false, "type": TYPE_STRING},
	"btn_content": {"ios": false, "type": TYPE_STRING},
	"bg_image": {"ios": false, "type": TYPE_STRING},
	"vibrate": {"ios": false, "type": TYPE_BOOL},
	"title_night": {"ios": false, "type": TYPE_STRING},
	"content_night": {"ios": false, "type": TYPE_STRING},
	"large_icon_night": {"ios": false, "type": TYPE_STRING},
}


## 按字段白名单、平台与类型过滤通知内容，保留原业务的候选内容顺序。
static func _normalize_push_contents(
	contents: Array[Dictionary], is_ios: bool
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Dictionary in contents:
		var item: Dictionary = {}
		for content_key: Variant in raw:
			var key: String = str(content_key)
			if not _PUSH_CONTENT_FIELDS.has(key):
				push_warning("[UniKitManager] push content 未知字段「%s」,剔除" % key)
				continue
			var field: Dictionary = _PUSH_CONTENT_FIELDS[key]
			if is_ios and not field["ios"]:
				continue
			var value_type: int = typeof(raw[content_key])
			if value_type != int(field["type"]):
				push_warning(
					(
						"[UniKitManager] push content 字段「%s」类型不符(%d != %d),剔除"
						% [key, value_type, int(field["type"])]
					)
				)
				continue
			item[key] = raw[content_key]
		out.append(item)
	return out


## 把日历日期转为连续日数后偏移，再转回年月日。
static func _local_date_offset(year: int, month: int, day: int, days: int) -> Dictionary:
	var jdn: int = _date_to_jdn(year, month, day) + days
	return _jdn_to_date(jdn)


## 将公历日期转换为儒略日编号，便于跨月跨年加减整天。
static func _date_to_jdn(year: int, month: int, day: int) -> int:
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045


## 将连续日编号还原为公历年月日。
static func _jdn_to_date(jdn: int) -> Dictionary:
	var a: int = jdn + 32044
	var b: int = (4 * a + 3) / 146097
	var c: int = a - (146097 * b) / 4
	var d: int = (4 * c + 3) / 1461
	var e: int = c - (1461 * d) / 4
	var m: int = (5 * e + 2) / 153
	return {
		"year": 100 * b + d - 4800 + m / 10,
		"month": m + 3 - 12 * (m / 10),
		"day": e - (153 * m + 2) / 5 + 1,
	}


## 取消原生层保存的指定通知。
func remove_push(push_id: String) -> void:
	UniKit.push_module.remove_push(push_id)


## 清除原生层保存的全部本地通知。
func remove_all_pushes() -> void:
	UniKit.push_module.remove_all_pushes()


## 设置 SDK 的通知总开关，独立于系统授权状态。
func set_push_enabled(enabled: bool) -> void:
	UniKit.push_module.set_push_enabled(enabled)


## 查询 SDK 的通知总开关。
func is_push_enabled() -> bool:
	return UniKit.push_module.is_push_enabled()


## 读取系统通知许可，iOS 临时授权也视为可通知。
func is_notification_permission_enabled() -> bool:
	return await UniKit.push_module.is_notification_permission_enabled()


## 查询原生层是否允许引导用户前往通知设置。
func is_goto_setting_enabled() -> bool:
	return UniKit.push_module.is_goto_setting_enabled()


## 按 Android 版本或 iOS 授权状态判断当前申请入口是否可用。
func can_request_permission(type: int = PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING) -> bool:
	return await UniKit.push_module.can_request_permission(type)


## 先移除同名通知，再建立 5 秒后触发的单次测试提醒。
func trigger_test_push(
	push_id: String, title: String, content: String, extra: Dictionary = {}
) -> void:
	UniKit.push_module.trigger_test_push(push_id, title, content, extra)


## 注册原生命令回调，使通知携带的命令进入模块信号。
func register_cmd_callback() -> void:
	UniKit.push_module.register_cmd_callback()


## 查询标签模块是否已收到首份有效原生数据。
func is_usertag_inited() -> bool:
	return UniKit.usertag_module._is_usertag_data_ready


## 读取缓存中的 SDK 内部标签，不触发新的原生查询。
func get_inner_tags() -> Dictionary:
	return await UniKit.usertag_module.get_inner_tags()


## 读取缓存中的本地单值标签。
func get_local_tags() -> Dictionary:
	return await UniKit.usertag_module.get_local_tags()


## 读取缓存中的远端单值标签。
func get_remote_tags() -> Dictionary:
	return await UniKit.usertag_module.get_remote_tags()


## 向原生标签系统写入一个本地单值标签。
func add_local_tag(key: String, value: String) -> void:
	UniKit.usertag_module.add_local_tag(key, value)


## 把列表序列化为 JSON 后写入原生本地标签。
func add_local_list_tag(key: String, values: Array) -> void:
	UniKit.usertag_module.add_local_list_tag(key, values)


## 请求原生移除指定本地标签。
func remove_local_tag(key: String) -> void:
	UniKit.usertag_module.remove_local_tag(key)


## 读取原生用户标识；尚无插件时返回空串。
func get_luid() -> String:
	return UniKit.usertag_module.get_luid()


## 注册原生用户标识就绪监听，结果由宿主转发。
func set_luid_listener() -> void:
	UniKit.usertag_module.set_luid_listener()


var _ad_query_channels: Dictionary = {}


## 同通道查询串行执行，并限制实际异步查询等待 3 秒，超时按未就绪处理。
func _query_with_timeout(coro: Callable, channel: String = "") -> bool:
	while not channel.is_empty() and _ad_query_channels.has(channel):
		await get_tree().process_frame
	if not channel.is_empty():
		_ad_query_channels[channel] = true
	var state: Dictionary = {"done": false, "result": false}
	var runner := func() -> void:
		var result: bool = await coro.call()
		state.result = result
		state.done = true
	runner.call()
	var start_ms: int = Time.get_ticks_msec()
	while (
		not state.done and (Time.get_ticks_msec() - start_ms) < int(_AD_QUERY_TIMEOUT_SEC * 1000.0)
	):
		await get_tree().process_frame
	if not channel.is_empty():
		_ad_query_channels.erase(channel)
	return state.result if state.done else false


## 请求原生加载指定广告位，加载完成另由信号通知。
func load_ad(placement_id: String) -> void:
	print("[UniKit-DEBUG] load_ad called: placement=%s" % placement_id)
	UniKit.ad_module.load_ad(placement_id)


## 检查调试开关后选择模拟或原生展示；就绪检查由调用链其他阶段负责。
func try_show_interstitial(placement_id: String, position: String, show_id: String) -> bool:
	if not cheat_show_interstitial:
		return false
	if _is_ad_mock_enabled():
		_mock_show_ad(placement_id, position)
		return true
	UniKit.ad_module.show_ad(placement_id, position, show_id)

	return true


## 插屏冷却秒数（由 AB 实验 inter_cd_lc 决定）
func get_interstitial_cd_sec() -> int:
	return ABTestManager.inter_cd_lc.get_cd_sec()


## 记录当前 Unix 秒时间，作为下一次插屏冷却计算起点。
func reset_interstitial_cd() -> void:
	_last_interstitial_close_unix = int(Time.get_unix_time_from_system())


## 是否还在插屏冷却期内
func is_interstitial_in_cd() -> bool:
	var cd_sec: int = get_interstitial_cd_sec()
	var now: int = int(Time.get_unix_time_from_system())
	return now - _last_interstitial_close_unix < cd_sec


## 按调试开关选择直接发奖或模拟广告，真机展示前登记激励会话。
func show_reward(placement_id: String, position: String, show_id: String) -> void:
	if not cheat_show_reward:
		_grant_reward_directly(placement_id)
		return
	if _is_ad_mock_enabled():
		_mock_show_ad(placement_id, position)
		return

	if placement_id == AdPlacement.REWARD:
		_start_reward_session(show_id, position)
	UniKit.ad_module.show_ad(placement_id, position, show_id)


## 记录一次广告展示时机，并取得后续查询与展示使用的 show_id。
func stats_ad_show_timing(placement_id: String, position: String) -> String:
	return UniKit.ad_module.stats_ad_show_timing(placement_id, position)


## 记录广告位在指定展示时机变为有效的埋点。
func stats_ad_became_valid(placement_id: String, position: String, show_id: String) -> void:
	UniKit.ad_module.stats_ad_became_valid(placement_id, position, show_id)


## 记录展示流水并限时查询激励广告就绪状态，失败时发布不可展示原因。
func is_reward_ready(placement_id: String, position: String, show_id: String) -> bool:
	if _mock_no_fill:
		return false
	if _is_ad_mock_enabled():
		return true
	if not UniKit.is_available():
		_emit_ad_not_ready(AdPlacement.REWARD, placement_id, position, "not_available")
		return false

	var query: Callable = func() -> bool:
		Tracker.remember_ad_show_id(placement_id, show_id)
		_pending_ad_positions[placement_id] = position
		return await UniKit.ad_module.is_ad_ready(placement_id, position, show_id)
	var ready: bool = await _query_with_timeout(query, "ready:%s" % placement_id)
	if not ready:
		_emit_ad_not_ready(AdPlacement.REWARD, placement_id, position, "no_fill")
	return ready


## 记录插屏流水并限时查询就绪状态，原生不可用时发布失败事件。
func is_interstitial_ready(placement_id: String, position: String, show_id: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if not UniKit.is_available():
		_emit_ad_not_ready(AdPlacement.INTERSTITIAL, placement_id, position, "not_available")
		return false

	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	var ready: bool = await _query_with_timeout(
		func() -> bool: return await UniKit.ad_module.is_ad_ready(placement_id, position, show_id)
	)
	if not ready:
		_emit_ad_not_ready(AdPlacement.INTERSTITIAL, placement_id, position, "no_fill")
	return ready


## 通过 EventBus 发布广告位、业务位置和不可展示原因，供诊断与埋点消费。
func _emit_ad_not_ready(
	kind: String, placement_id: String, position: String, reason: String
) -> void:
	if not is_instance_valid(EventBus):
		return
	(
		EventBus
		. emit_event(
			EventName.AD_NOT_READY,
			{
				"kind": kind,
				"placement": placement_id,
				"pos": position,
				"reason": reason,
			}
		)
	)


## 在编辑器与无填充测试之外，按广告位串行执行 3 秒限时有效性查询。
func is_reward_valid(placement_id: String, position: String) -> bool:
	if _mock_no_fill:
		return false
	if _is_ad_mock_enabled():
		return true
	var query: Callable = func() -> bool:
		return await UniKit.ad_module.is_reward_valid(placement_id, position)
	return await _query_with_timeout(query, "valid:%s" % placement_id)


## 模拟环境直接通过，真机执行带超时的横幅有效性查询。
func is_banner_valid(placement_id: String, position: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	return await _query_with_timeout(
		func() -> bool: return await UniKit.ad_module.is_banner_valid(placement_id, position)
	)


## 模拟环境直接通过，真机执行带超时的插屏有效性查询。
func is_interstitial_valid(placement_id: String, position: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	return await _query_with_timeout(
		func() -> bool: return await UniKit.ad_module.is_interstitial_valid(placement_id, position)
	)


## 声明本适配层提供广告展示信号，供调用方检测接口能力。
func is_ad_shown_signal_available() -> bool:
	return true


## 声明本适配层提供曝光信号，供调用方检测接口能力。
func is_ad_impression_signal_available() -> bool:
	return true


# ================= 广告模拟（仅编辑器，用 Mock UI 顶替原生广告） =================
## 是否走 Mock：编辑器构建下恒为真
func _is_ad_mock_enabled() -> bool:
	return OS.has_feature("editor")


## 创建模拟展示会话并打开调试广告页，通过回调复现关闭和发奖顺序。
func _mock_show_ad(placement_id: String, position: String) -> void:
	var show_id: String = "mock_%d" % Time.get_ticks_usec()
	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	if placement_id == AdPlacement.REWARD:
		_start_reward_session(show_id, position)

	_on_ad_shown(placement_id)

	_on_ad_impression.call_deferred({"placement_id": placement_id, "position": position})

	var on_close := func() -> void:
		_on_ad_closed(placement_id)
		UIManager.hide_ui(UiName.MOCK_AD)
	var on_reward_close := func() -> void:
		_on_ad_rewarded(placement_id)
		_on_ad_closed(placement_id)
		UIManager.hide_ui(UiName.MOCK_AD)

	var on_closed_first := func() -> void: _mock_emit_closed_first(placement_id)
	(
		UIManager
		. show_ui(
			UiName.MOCK_AD,
			{
				"placement_id": placement_id,
				"position": position,
				"on_close": on_close,
				"on_reward_close": on_reward_close,
				"on_closed_first": on_closed_first,
			}
		)
	)


const _MOCK_CLOSED_FIRST_DELAY_SEC: float = 0.3


## 先发送关闭事件，延迟 0.3 秒再发奖励，用于覆盖回调乱序场景。
func _mock_emit_closed_first(placement_id: String) -> void:
	UIManager.hide_ui(UiName.MOCK_AD)
	print(
		(
			"[UniKit-MOCK] closed-first: emit ad_closed → %.1fs 后再 emit ad_rewarded"
			% _MOCK_CLOSED_FIRST_DELAY_SEC
		)
	)
	_on_ad_closed(placement_id)
	await get_tree().create_timer(_MOCK_CLOSED_FIRST_DELAY_SEC).timeout
	_on_ad_rewarded(placement_id)


## 用 MockBanner 界面模拟 banner（偏移与高度按 1080 基准缩放，和真机一致）
func _mock_show_banner(
	placement_id: String, position: String, anchor_bottom: bool, offset_base: int, height_base: int
) -> void:
	(
		UIManager
		. show_ui(
			UiName.MOCK_BANNER,
			{
				"placement_id": placement_id,
				"position": position,
				"anchor_bottom": anchor_bottom,
				"offset_base": offset_base,
				"height_base": height_base,
			}
		)
	)


## 关掉 Mock banner
func _mock_destroy_banner() -> void:
	UIManager.hide_ui(UiName.MOCK_BANNER)


## 不发广告直接发奖：补一次「发奖 + 关闭」回调
func _grant_reward_directly(placement_id: String) -> void:
	_on_ad_rewarded(placement_id)
	_on_ad_closed(placement_id)


## 调试：开启后激励视频回调被吞掉，用来验证发奖兜底
func set_debug_reward_miss(enabled: bool) -> void:
	_debug_reward_miss = enabled


## 查询本层是否已发出横幅展示请求，用于避免重复展示。
func is_banner_show_requested() -> bool:
	return _banner_show_requested


## 仅 iOS 对横幅展示请求去重，保留平台行为差异。
func _should_dedupe_banner_show() -> bool:
	return OS.has_feature("ios")


## 结合调试开关、初始化状态与 iOS 去重策略展示横幅，按需触发首次加载。
func show_banner(
	placement_id: String,
	position: String,
	anchor_bottom: bool = true,
	offset_base: int = 0,
	height_base: int = 180
) -> void:
	if not cheat_show_banner:
		print(
			(
				"[Banner] show skip placement=%s position=%s reason=cheat_show_banner=false"
				% [placement_id, position]
			)
		)
		return
	var dedupe_banner_show: bool = (
		placement_id == AdPlacement.BANNER and _should_dedupe_banner_show()
	)
	if dedupe_banner_show and _banner_show_requested:
		print(
			(
				"[Banner] show skip placement=%s position=%s reason=already_requested"
				% [placement_id, position]
			)
		)
		return
	if _is_ad_mock_enabled():
		if placement_id == AdPlacement.BANNER:
			_banner_show_requested = true
		print(
			(
				"[Banner] show route=mock placement=%s position=%s anchor_bottom=%s offset_base=%d height_base=%d"
				% [placement_id, position, str(anchor_bottom), offset_base, height_base]
			)
		)
		_mock_show_banner(placement_id, position, anchor_bottom, offset_base, height_base)
		return

	if not _banner_load_requested:
		if not _is_ad_inited:
			print(
				(
					"[Banner] show skip placement=%s position=%s reason=ad_not_inited"
					% [placement_id, position]
				)
			)
			return
		load_ad(AdPlacement.BANNER)
		_banner_load_requested = true
	if placement_id == AdPlacement.BANNER:
		_banner_show_requested = true
	print(
		(
			"[Banner] show route=addon placement=%s position=%s anchor_bottom=%s offset_base=%d height_base=%d"
			% [placement_id, position, str(anchor_bottom), offset_base, height_base]
		)
	)
	UniKit.ad_module.show_banner(placement_id, position, anchor_bottom, offset_base, height_base)


## 清理横幅请求状态，并按运行环境关闭模拟页或销毁原生广告。
func destroy_ad(placement_id: String) -> void:
	if placement_id == AdPlacement.BANNER:
		_banner_show_requested = false
	if _is_ad_mock_enabled():
		if placement_id == AdPlacement.BANNER:
			print("[Banner] destroy route=mock placement=%s" % placement_id)
			_mock_destroy_banner()
		return
	if placement_id == AdPlacement.BANNER:
		print("[Banner] destroy route=addon placement=%s" % placement_id)
	UniKit.ad_module.destroy_ad(placement_id)


## 打开原生广告调试界面。
func open_ad_debug_view() -> void:
	UniKit.ad_module.open_ad_debug_view()


## 发送统计事件，未指定平台时默认投递到 learnings。
func send_event(
	event_name: String, params: Dictionary = {}, platforms: Array = [], value_to_sum: float = 0.0
) -> void:
	UniKit.analyze_module.send_event(event_name, params, platforms, value_to_sum)


## 读取原生分析 SDK 分配的用户标识。
func get_learnings_id() -> String:
	return UniKit.analyze_module.get_learnings_id()


## 读取原生统计 UUID；插件缺失时返回空串。
func get_uuid() -> String:
	return UniKit.analyze_module.get_uuid()


## 通过 NativeUtilManager 读取安装包版本名。
func get_version_name() -> String:
	return NativeUtilManager.get_version_name()


## 通过 NativeUtilManager 读取安装包版本号。
func get_version_code() -> int:
	return NativeUtilManager.get_version_code()


## 通过平台工具读取首次打开应用的毫秒时间戳。
func get_first_open_time_ms() -> int:
	return NativeUtilManager.get_first_open_time_ms()


## 设置原生统计系统的用户级属性。
func set_user_property(key: String, value: String) -> void:
	UniKit.analyze_module.set_user_property(key, value)


## 设置原生统计系统附加到事件上的公共属性。
func set_event_property(key: String, value: String) -> void:
	UniKit.analyze_module.set_event_property(key, value)


## 将业务用户标识交给原生崩溃统计，便于关联同一用户的异常。
func set_crashlytics_user_id(user_id: String) -> void:
	NativeUtilManager.set_crashlytics_user_id(user_id)


## 补齐缺失的脚本调用栈；分析未就绪时先缓存，原生工具不可用时跳过。
func log_exception(message: String, stack: String = "") -> void:
	if not NativeUtilManager.is_available():
		return

	if stack.is_empty():
		stack = _format_gd_backtraces(Engine.capture_script_backtraces(), 1)
	if _is_analyze_inited:
		NativeUtilManager.log_crashlytics_exception(message, stack)
		return

	if _crashlytics_log_cache.size() >= _CRASHLYTICS_LOG_CACHE_MAX:
		_crashlytics_log_cache.pop_front()
	_crashlytics_log_cache.append({"message": message, "stack": stack})


## 补发初始化前积累的异常，并清空本地缓存。
func _flush_crashlytics_cache() -> void:
	for entry in _crashlytics_log_cache:
		NativeUtilManager.log_crashlytics_exception(entry["message"], entry["stack"])
	_crashlytics_log_cache.clear()


## 把引擎的 ScriptBacktrace 数组拼成多行文本；skip_frames 用来跳过封装层自己的栈帧
func _format_gd_backtraces(backtraces: Array, skip_frames: int) -> String:
	var lines: PackedStringArray = []
	for bt in backtraces:
		var count: int = bt.get_frame_count()
		for i in range(skip_frames, count):
			lines.append(
				(
					"[%d] %s (%s:%d)"
					% [
						lines.size(),
						bt.get_frame_function(i),
						bt.get_frame_file(i),
						bt.get_frame_line(i)
					]
				)
			)
	return "\n".join(lines)


## 仅在 iOS 原生插件可用时请求系统评分界面。
func request_store_review() -> void:
	NativeUtilManager.request_store_review()


## 统计模块是否已初始化
func is_analyze_inited() -> bool:
	return _is_analyze_inited


## 广告模块是否已初始化
func is_ad_inited() -> bool:
	return _is_ad_inited


## 标记广告就绪并发信号，立即预加载激励广告，2 秒后预加载插屏。
func _on_ad_init_success() -> void:
	_is_ad_inited = true
	ad_init_completed.emit()
	load_ad(AdPlacement.REWARD)
	await get_tree().create_timer(2.0).timeout
	load_ad(AdPlacement.INTERSTITIAL)


## 恢复全屏广告音频管理、刷新冷却，并为已展示的激励广告检查发奖兜底。
func _on_ad_closed(placement_id: String) -> void:
	print("[UniKit] ad_closed: placement=%s reward_shown=%s" % [placement_id, _reward_shown])

	if _is_fullscreen_audio_ad(placement_id):
		NativeUtilManager.resume_audio_io_buffer_recovery()

	reset_interstitial_cd()
	ad_closed.emit(placement_id)

	if placement_id == AdPlacement.REWARD:
		if _reward_shown:
			GameState.increment_session_reward_view_count()
		_maybe_start_reward_grant_watchdog()


## 转发奖励事件并记录正常激励时间，调试漏奖开关可故意吞掉回执。
func _on_ad_rewarded(placement_id: String) -> void:
	if _debug_reward_miss and placement_id == AdPlacement.REWARD:
		print(
			"[UniKit] ad_rewarded SKIPPED by cheat _debug_reward_miss: placement=%s" % placement_id
		)
		return
	print("[UniKit] ad_rewarded: placement=%s" % placement_id)
	ad_rewarded.emit(placement_id)

	if placement_id == AdPlacement.REWARD:
		_mark_reward_received()

		GameState.record_normal_reward(int(Time.get_unix_time_from_system()))


## 暂停全屏广告期间的音频恢复，发布展示事件并标记激励确已展示。
func _on_ad_shown(placement_id: String) -> void:
	print("[UniKit-DEBUG] _on_ad_shown emit ad_shown: placement=%s" % placement_id)

	if _is_fullscreen_audio_ad(placement_id):
		NativeUtilManager.pause_audio_io_buffer_recovery()

	ad_shown.emit(placement_id)
	if placement_id == AdPlacement.REWARD and _reward_active_show_id != "":
		_reward_shown = true


## 只把激励与插屏视为需要切换原生音频恢复的全屏广告。
func _is_fullscreen_audio_ad(placement_id: String) -> bool:
	return placement_id == AdPlacement.REWARD or placement_id == AdPlacement.INTERSTITIAL


## 开一次激励视频会话：记住 show_id / position 并清空发奖标记
func _start_reward_session(show_id: String, position: String) -> void:
	_reward_active_show_id = show_id
	_reward_active_position = position
	_reward_received = false
	_reward_shown = false


## 标记发奖：没有活跃会话时（多见于恢复流程），从看门狗里挑最早的一条消掉
func _mark_reward_received() -> void:
	if _reward_active_show_id != "":
		_reward_received = true
		return

	# 没有进行中的会话：消掉最早的一条待补发记录
	if _pending_watchdogs.is_empty():
		return
	var earliest_key: String = ""
	var earliest_ts: int = 0
	for key in _pending_watchdogs:
		var ts: int = int(_pending_watchdogs[key].get("ts", 0))
		if earliest_key == "" or ts < earliest_ts:
			earliest_key = key
			earliest_ts = ts
	_pending_watchdogs.erase(earliest_key)


## 广告关闭后判断要不要启动发奖兜底：已发奖或压根没展示就直接收尾，否则登记看门狗并起 30 秒定时器
func _maybe_start_reward_grant_watchdog() -> void:
	if _reward_active_show_id == "":
		return
	# 已经发过奖：会话直接收尾
	if _reward_received:
		_reset_reward_session()
		return
	# 广告没真正展示（用户秒退）：不算有效观看，收尾
	if not _reward_shown:
		_reset_reward_session()
		return
	var show_id: String = _reward_active_show_id
	var position: String = _reward_active_position
	# 登记待发奖，超时后按 AB 开关决定是否补发
	_pending_watchdogs[show_id] = {
		"position": position,
		"ts": int(Time.get_unix_time_from_system()),
	}
	get_tree().create_timer(_REWARD_GRANT_TIMEOUT_SEC).timeout.connect(
		func() -> void: _on_reward_grant_timeout(show_id, position), CONNECT_ONE_SHOT
	)

	# 会话状态立即清空，超时判定改由 _pending_watchdogs 负责
	_reset_reward_session()


## 超过看门狗期限仍未发奖时，将补偿条目写入 GameState 待处理奖励。
func _on_reward_grant_timeout(show_id: String, position: String) -> void:
	if not _pending_watchdogs.has(show_id):
		return
	_pending_watchdogs.erase(show_id)

	(
		GameState
		. add_pending_reward(
			{
				"show_id": show_id,
				"source": position,
				"ts": int(Time.get_unix_time_from_system()),
			}
		)
	)


## 依据广告来源恢复相应道具或连续奖励基础份额，未知来源返回空列表。
func restore_items_for_position(position: String) -> Array:
	if position == Tracker.AdPos.PROPS_NORMAL_HINT or position == Tracker.AdPos.PROPS_DAILY_HINT:
		return [{"kind": "hint", "count": 1}]
	if (
		position == Tracker.AdPos.PROPS_NORMAL_LOCATE
		or position == Tracker.AdPos.PROPS_DAILY_LOCATE
	):
		return [{"kind": "locate", "count": 1}]

	if position == Tracker.AdPos.PROPS_NORMAL_DRAFT or position == Tracker.AdPos.PROPS_DAILY_DRAFT:
		return [{"kind": "draft", "count": 1}]

	if position == Tracker.AdPos.STREAK_X2_REWARD:
		var items: Array = []
		for kind: String in StreakData.REWARD_BASE:
			items.append({"kind": kind, "count": int(StreakData.REWARD_BASE[kind])})
		return items
	return []


## 清空激励视频会话状态
func _reset_reward_session() -> void:
	_reward_active_show_id = ""
	_reward_active_position = ""
	_reward_received = false
	_reward_shown = false


## 恢复全屏广告音频管理，并把原生错误转发给业务。
func _on_ad_error(placement_id: String, msg: String) -> void:
	push_warning("UniKit AD error: placement=%s, msg=%s" % [placement_id, msg])

	if _is_fullscreen_audio_ad(placement_id):
		NativeUtilManager.resume_audio_io_buffer_recovery()
	ad_error_occurred.emit(placement_id, msg)


## 先发布曝光数据，再消费展示流水并清理该广告位的待关联位置。
func _on_ad_impression(data: Dictionary) -> void:
	ad_impression_received.emit(data)
	var placement_id: String = data.get("placement_id", "")
	if placement_id == "":
		push_warning("UniKit AD impression: placement_id 为空, raw=%s" % JSON.stringify(data))
		return

	Tracker.consume_ad_show_id(placement_id)
	_pending_ad_positions.erase(placement_id)


## 更新广告调试总开关，关闭时立即销毁横幅。
func set_debug_ad_enabled(enabled: bool) -> void:
	if _debug_ad_enabled == enabled:
		return
	_debug_ad_enabled = enabled
	if not enabled:
		destroy_ad(AdPlacement.BANNER)


## 读调试总开关
func is_debug_ad_enabled() -> bool:
	return _debug_ad_enabled


## 读取字符串实验值；原生插件缺失时使用调用方默认值。
func get_ab_string(key: String, default_value: String = "") -> String:
	return UniKit.abtest_module.get_ab_string(key, default_value)


## 读取整数实验值；原生插件缺失时使用调用方默认值。
func get_ab_int(key: String, default_value: int = 0) -> int:
	return UniKit.abtest_module.get_ab_int(key, default_value)


## 读取浮点实验值；原生插件缺失时使用调用方默认值。
func get_ab_float(key: String, default_value: float = 0.0) -> float:
	return UniKit.abtest_module.get_ab_float(key, default_value)


## 通知原生层为指定实验染色，标记该实验已实际参与业务。
func dye_ab(key: String) -> void:
	UniKit.abtest_module.dye_ab(key)


## 解析原生返回的全部实验字典，异常数据回退为空字典。
func get_all_ab_experiments() -> Dictionary:
	return UniKit.abtest_module.get_all_ab_experiments()


## 读取已发布实验的原生快照，供配置和调试使用。
func get_all_publish_ab_experiments() -> Dictionary:
	return UniKit.abtest_module.get_all_publish_ab_experiments()


## 通过实验模块查询指定实验是否已染色。
func is_ab_dyeing(key: String) -> bool:
	return UniKit.abtest_module.is_dyeing(key)


## 通过实验模块读取指定实验的分组状态。
func get_ab_group_status(key: String) -> String:
	return UniKit.abtest_module.get_group_status(key)


## 通过实验模块读取指定实验染色时间。
func get_ab_dyeing_time(key: String) -> String:
	return UniKit.abtest_module.get_dyeing_time(key)


## 取得实验模块保存的全部染色时间快照。
func get_all_ab_dyeing_times() -> Dictionary:
	return UniKit.abtest_module.get_all_dyeing_times()


## 读取原生聚合的全部实验标签字符串。
func get_ab_all_tag() -> String:
	return UniKit.abtest_module.get_ab_all_tag()


## 读取已经染色的实验标签字符串。
func get_ab_dyeing_tag() -> String:
	return UniKit.abtest_module.get_ab_dyeing_tag()


## 读取原生实验分组标识。
func get_ab_group_id() -> String:
	return UniKit.abtest_module.get_ab_group_id()


## 解析原生实验用户信息，保留字典形式供业务消费。
func get_ab_user_info() -> Dictionary:
	return UniKit.abtest_module.get_ab_user_info()


## 发起远端实验结果刷新，完成状态通过模块信号返回。
func fetch_remote_ab_result() -> void:
	UniKit.abtest_module.fetch_remote_ab_result()


## 读取远端实验参数，空串或插件缺失时使用默认值。
func get_ab_locsrv_param(key: String, default_value: String = "") -> String:
	return UniKit.abtest_module.get_ab_locsrv_param(key, default_value)


## 取得远端实验参数快照，异常 JSON 回退为空字典。
func get_all_ab_locsrv_params() -> Dictionary:
	return UniKit.abtest_module.get_all_ab_locsrv_params()


## 通知原生层染色指定本地服务实验参数。
func dye_ab_locsrv(key: String) -> void:
	UniKit.abtest_module.dye_ab_locsrv(key)


## 以 JSON 数组提交有效标签和空标签，保持原生接口的数据格式。
func set_ab_locsrv_all_tag(all_tags: Array[String], empty_tags: Array[String] = []) -> void:
	UniKit.abtest_module.set_ab_locsrv_all_tag(all_tags, empty_tags)


## 向原生层提交服务端实验标签染色。
func dye_ab_locsrv_tag(tag: String) -> void:
	UniKit.abtest_module.dye_ab_locsrv_tag(tag)


## 读取实验系统采用的国家或地区标识。
func get_ab_country() -> String:
	return UniKit.abtest_module.get_ab_country()


## 覆盖原生实验分组标识，供指定分组或调试流程使用。
func set_ab_group_id(group_id: String) -> void:
	UniKit.abtest_module.set_ab_group_id(group_id)


## 覆盖原生实验地区标识，后续实验读取由原生层处理。
func set_ab_country(country: String) -> void:
	UniKit.abtest_module.set_ab_country(country)
