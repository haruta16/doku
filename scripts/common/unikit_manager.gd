# UniKit 第三方 SDK（归因 / AB 实验 / 广告 / 推送 / Crashlytics）的 GDScript 封装，autoload 名 UniKitManager
# 原生插件不存在时自动退化成「离线适配层」：接口照样能调，只是返回保守默认值，业务无需分平台判断
extends Node

# ---- 信号：推送权限、设备标识、广告结果 ----
# 推送权限流程走完（或者判定不需要弹）
signal push_permission_done
# 原生 LUID 就绪（客服工单与 AB 上报会用到）
signal luid_ready(luid: String)
# 广告关闭，参数是广告位（interstitial / reward / banner …）
signal ad_closed(placement_id: String)
# 激励视频看完并确认发奖
signal ad_rewarded(placement_id: String)

# ---- 信号：广告播放过程与推送指令 ----
# 广告真正展示出来（SoundManager 靠它暂停 BGM，埋点也靠它）
signal ad_shown(placement_id: String)
# 广告出错（加载或展示失败）
signal ad_error_occurred(placement_id: String, msg: String)
# 收到曝光回调，data 是原生 JSON 解析后的字典
signal ad_impression_received(data: Dictionary)
# 收到推送下发的指令 JSON，由业务侧自行解析
signal push_cmd_received(cmd_json: String)

# ---- 信号：各子模块初始化完成 ----
# 统计（analyze / Crashlytics）初始化完成，缓存的异常已补报
signal analyze_init_completed
# 广告模块初始化完成
signal ad_init_completed

# ---- 信号：AB 实验 ----
# AB 参数首次就绪
signal abtest_ready(user_info: Dictionary)
# AB 参数发生变化（update_type 区分来源）
signal abtest_params_updated(update_type: String, user_info: Dictionary)
# 远端 AB 配置拉取完成
signal abtest_remote_config_ready
# 本地服务（locsrv）AB 参数拉取结束，success 为 false 时带错误串
signal abtest_locsrv_fetched(success: bool, error: String)

# ---- 信号：合规与授权 ----
# CMP（GDPR 等隐私同意）流程结束
signal cmp_completed

# iOS ATT 授权状态变化，取值见下面的 ATT_STATUS_*
signal att_status_changed(status: int)

# ATT 系统弹窗被关闭（不管用户选了什么）
signal att_dismissed

# ---- 常量：ATT 授权状态（取值与 iOS 原生一致） ----
# 尚未询问，只有这个状态下才允许调起系统弹窗
const ATT_STATUS_NOT_DETERMINED: int = 0
# 已授权
const ATT_STATUS_AUTHORIZED: int = 1
# 系统层面拒绝（如家长控制）
const ATT_STATUS_SYSTEM_DENIED: int = 2
# 用户自己点了拒绝
const ATT_STATUS_APP_DENIED: int = 3

# ---- 常量：推送权限申请方式 ----
# 只弹系统权限弹窗
const PUSH_PERMISSION_TYPE_SYSTEM: int = 1
# 系统权限 + 引导去设置页（默认值）
const PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING: int = 2
# 只引导去系统设置页
const PUSH_PERMISSION_TYPE_SETTING: int = 3

# ---- 原生插件句柄与调试开关 ----
# UniKitPlugin 原生单例；null 表示当前平台没有插件（编辑器 / 桌面），所有接口走降级分支
var _plugin: Object = null

# 编辑器里强制走 ATT 测试流程（作弊指令置位，流程结束由 AttGuideHelper 复位）
static var debug_force_editor_test: bool = false

# ---- 插屏状态与作弊开关 ----
# 上次插屏关闭的 unix 秒，用来算冷却
var _last_interstitial_close_unix: int = 0

# 广告位 → 本次展示用的 position，曝光回调取走后删除
var _pending_ad_positions: Dictionary = {}

# 调试总开关（默认 true）；false 时 show_interstitial 直接不展示
var _debug_ad_enabled: bool = true

# 三个作弊开关：编辑器默认关（= false），真机包默认开，由作弊面板切换
# 是否允许展示插屏
var cheat_show_interstitial: bool = not OS.has_feature("editor")
# 是否允许展示激励视频（关掉则直接发奖）
var cheat_show_reward: bool = not OS.has_feature("editor")
# 是否允许展示 banner
var cheat_show_banner: bool = not OS.has_feature("editor")

# 作弊：模拟「视频看完却不发奖」，用于验证发奖兜底
var _debug_reward_miss: bool = false

# 是否正在等推送权限弹窗的结果（回前台时用它兜底收尾）
var _push_permission_pending: bool = false

# ---- Crashlytics 异常缓存 ----
# 统计未初始化时最多缓存多少条异常，超出丢最旧的
const _CRASHLYTICS_LOG_CACHE_MAX: int = 20
# 初始化前攒下的异常，元素形如 {message, stack}
var _crashlytics_log_cache: Array[Dictionary] = []
# 统计模块是否已初始化
var _is_analyze_inited: bool = false
# 广告模块是否已初始化
var _is_ad_inited: bool = false

# ---- 激励视频发奖兜底 ----
# 关广告后等这么久（秒）还没收到发奖回调，就记一笔待补发
const _REWARD_GRANT_TIMEOUT_SEC: float = 30.0

# 本次激励视频的 show_id（空串 = 没有进行中的会话）
var _reward_active_show_id: String = ""

# 本次激励视频的 position，补发时用来说明来源
var _reward_active_position: String = ""

# 本次会话是否已收到发奖回调
var _reward_received: bool = false

# 本次广告是否真的展示过（没展示就不该发奖）
var _reward_shown: bool = false

# 等待发奖的看门狗：show_id → {position, ts}
var _pending_watchdogs: Dictionary = {}


# ================= 生命周期 =================
# autoload 启动：抓原生单例、把原生信号逐个接到转发回调，并用 SDK 数据补齐首开时间与安装版本
func _ready() -> void:
	if Engine.has_singleton("UniKitPlugin"):
		_plugin = Engine.get_singleton("UniKitPlugin")

		# 统计模块初始化成功
		_plugin.analyze_init_success.connect(_on_analyze_init_success)
		# 广告模块初始化成功
		_plugin.ad_init_success.connect(_on_ad_init_success)
		# 广告模块初始化失败
		_plugin.ad_init_error.connect(_on_ad_init_error)
		# GRT 模块初始化成功
		_plugin.grt_init_success.connect(_on_grt_init_success)
		# 推送模块初始化成功
		_plugin.push_init_success.connect(_on_push_init_success)
		# 用户标签模块初始化成功
		_plugin.usertag_init_success.connect(_on_usertag_init_success)
		# 内购初始化成功
		_plugin.purchase_init_success.connect(_on_purchase_init_success)
		# 内购初始化失败
		_plugin.purchase_init_fail.connect(_on_purchase_init_fail)
		# AB 参数首次就绪
		_plugin.abtest_init.connect(_on_abtest_init)
		# AB 参数更新
		_plugin.abtest_updated.connect(_on_abtest_updated)
		# 远端 AB 配置就绪
		_plugin.abtest_remote_config_ready.connect(_on_abtest_remote_config_ready)
		# 本地服务 AB 结果
		_plugin.abtest_locsrv_result.connect(_on_abtest_locsrv_result)
		# 归因（AF）回调成功
		_plugin.af_callback_success.connect(_on_af_callback_success)
		# 归因（AF）回调失败
		_plugin.af_callback_fail.connect(_on_af_callback_fail)
		# LUID 就绪
		_plugin.luid_ready.connect(_on_luid_ready)
		# 广告关闭
		_plugin.ad_closed.connect(_on_ad_closed)
		# 激励视频发奖
		_plugin.ad_rewarded.connect(_on_ad_rewarded)

		# ad_shown 是可选信号：某些插件版本没有，先探测再连
		if _plugin.has_signal("ad_shown"):
			_plugin.ad_shown.connect(_on_ad_shown)
		# 广告出错
		_plugin.ad_error.connect(_on_ad_error)
		# 广告曝光
		_plugin.ad_impression.connect(_on_ad_impression)
		# 推送权限结果
		_plugin.push_permission_result.connect(_on_push_permission_result)
		# 推送下发的指令
		_plugin.push_cmd_received.connect(_on_push_cmd_received)

		# 隐私合规（CMP）流程结束
		_plugin.cmp_completed.connect(_on_cmp_completed)

		# ATT 相关信号只有 iOS 原生提供
		if OS.has_feature("ios"):
			_plugin.att_status_changed.connect(_on_att_status_changed)
			_plugin.att_dismissed.connect(_on_att_dismissed)
	# 没有原生插件：打印一行提示，之后所有接口都走离线降级实现
	else:
		print("UniKitPlugin not available; offline adapter active")

	# 用 SDK 的首开时间补本地存档（本地已有值就不动）
	GameState.ensure_first_open_time(get_first_open_time_ms())
	# 同上：补齐安装版本号，客服工单会带上它
	GameState.ensure_install_version(get_version_name())


# ================= 基础能力查询（在线 / 隐私 / CMP） =================
# 原生插件是否可用（编辑器与桌面端为 false）
func is_available() -> bool:
	return _plugin != null


# 是否在线；没有插件时按「在线」处理，避免单机流程被网络判断拦住
func is_online() -> bool:
	if _plugin == null:
		return true
	return _plugin.isOnline()


# 是否需要弹隐私政策同意；无插件时返回 false
func check_privacy_required() -> bool:
	if _plugin == null:
		return false
	return _plugin.checkPrivacyUiRequired()


# 同意隐私政策（写进原生 SDK）
func agree_privacy() -> void:
	if _plugin == null:
		return
	_plugin.agreePrivacyPolicy()


# 是否已同意隐私政策
func is_privacy_agreed() -> bool:
	if _plugin == null:
		return false
	return _plugin.isPrivacyPolicyAgreed()


# 触发 CMP 检查；on_done 会在流程结束时一次性回调（无插件时用 call_deferred 立即回调，保证调用方走到同一条路）
func check_cmp(on_done: Callable = Callable()) -> void:
	# 调用方给了回调就挂一次性连接
	if on_done.is_valid():
		cmp_completed.connect(on_done, CONNECT_ONE_SHOT)
	# 没有原生插件也必须发信号，否则 await 的调用方会永远等下去
	if _plugin == null:
		cmp_completed.emit.call_deferred()
		return
	_plugin.checkCMP()


# 是否必须展示 CMP 弹窗
func check_cmp_required() -> bool:
	if _plugin == null:
		return false
	return _plugin.checkCMPUiRequired()


# 弹出 CMP 同意界面
func show_cmp_ui() -> void:
	if _plugin == null:
		return
	_plugin.showCMPUi()


# ================= ATT（iOS 广告跟踪授权） =================
# 现在能不能调起 ATT 弹窗：仅 iOS，且原生说可以（编辑器测试开关下直接放行）
func can_show_att() -> bool:
	# 编辑器测试模式：绕过平台与原生判断
	if OS.has_feature("editor") and debug_force_editor_test:
		return true
	if not OS.has_feature("ios"):
		return false
	if _plugin == null:
		return false
	return _plugin.canShowATT()


# 初始化 ATT（仅 iOS 原生有）
func init_att() -> void:
	if _plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_plugin.initATT()


# 弹系统 ATT 弹窗；编辑器测试模式下不碰原生，用 2 秒定时器模拟「已授权 + 弹窗关闭」
func show_att_alert(source: String) -> void:
	if OS.has_feature("editor") and debug_force_editor_test:
		# 编辑器模拟分支
		print("[UniKit] (editor mock) showATTAlert source=%s,2 秒后模拟用户授权 + dismissed" % source)
		var timer: SceneTreeTimer = Engine.get_main_loop().create_timer(2.0)
		timer.timeout.connect(
			func() -> void:
				att_status_changed.emit(ATT_STATUS_AUTHORIZED)
				att_dismissed.emit()
		)
		return
	# 无插件或非 iOS：静默返回
	if _plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_plugin.showATTAlert(source)


# 读当前 ATT 授权状态；非 iOS 或无插件时返回 NOT_DETERMINED
func get_att_status() -> int:
	if _plugin == null:
		return ATT_STATUS_NOT_DETERMINED
	if not OS.has_feature("ios"):
		return ATT_STATUS_NOT_DETERMINED
	return _plugin.getATTStatus()


# ================= 账号与杂项 =================
# 调试：让原生侧模拟一次广告加载失败（仅 iOS）
func debug_mock_ad_load_fail() -> void:
	if _plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_plugin.debugMockAdLoadFail()


# 设置账号 ID（登录后关联统计与归因）
func set_account_id(account_id: String) -> void:
	if _plugin == null:
		return
	_plugin.setAccountId(account_id)


# 把隐私政策链接换成本地化版本；无插件时原样返回
func get_localized_privacy_url(url: String) -> String:
	if _plugin == null:
		return url
	return _plugin.getLocalizedPrivacyUrl(url)


# ================= 推送与本地通知 =================
# 开局申请推送权限的快捷入口：固定「只弹系统权限」，来源标记 app_start
func request_push_permission() -> void:
	request_notification_permission(PUSH_PERMISSION_TYPE_SYSTEM, "app_start")


# 申请通知权限：type 见 PUSH_PERMISSION_TYPE_*，position 只用于埋点
func request_notification_permission(
	type: int = PUSH_PERMISSION_TYPE_SYSTEM_AND_SETTING, position: String = "default"
) -> void:
	# 没有插件直接回调，别让调用方 await 卡住
	if _plugin == null:
		push_permission_done.emit.call_deferred()
		return
	# Android 13 以下没有通知运行时权限，「只弹系统权限」这种类型直接算完成
	if (
		type == PUSH_PERMISSION_TYPE_SYSTEM
		and OS.has_feature("android")
		and not _is_android_13_or_above()
	):
		push_permission_done.emit.call_deferred()
		return
	# 打上等待标记：弹窗期间切回前台也能收尾（见 _notification）
	_push_permission_pending = true
	_plugin.requestPushPermission(type, position)


# 判断是否 Android 13 及以上（13 起才有通知运行时权限）
static func _is_android_13_or_above() -> bool:
	if not OS.has_feature("android"):
		return false
	var v: String = OS.get_version()
	if v.is_empty():
		return false
	# 取主版本号（形如 "13" / "14.0"）
	return v.split(".")[0].to_int() >= 13


# 加一条每日重复的本地推送：本地时间 hour_local 点触发，contents 里每项会拆成一份多语言文案
func add_daily_push(
	push_id: String, hour_local: float, contents: Array[Dictionary], disturb_type: int = 1
) -> void:
	if _plugin == null:
		return
	# 把小数小时拆成「时 + 分」
	var target_hour: int = int(hour_local)
	var target_minute: int = int(round((hour_local - float(target_hour)) * 60.0))

	# 当前本地时间
	var local: Dictionary = Time.get_datetime_dict_from_system()

	# 今天这个点已经过了（或正好到点）：首次触发顺延到明天
	var advance_one_day: bool = (
		local["hour"] > target_hour
		or (local["hour"] == target_hour and local["minute"] >= target_minute)
	)
	# 原生要求 contents 是字典，key 形如 <push_id>_c<序号>
	var contents_dict: Dictionary = {}
	for i: int in range(contents.size()):
		contents_dict["%s_c%d" % [push_id, i]] = contents[i]
	# 推送体：每 86400000 毫秒（24 小时）重复一次，不限次数
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
		"contents": contents_dict
	}
	print(
		(
			"[UniKit] add_daily_push: push_id=%s hour=%.1f contents_count=%d disturb=%d"
			% [push_id, hour_local, contents.size(), disturb_type]
		)
	)
	_plugin.saveLocalPush(JSON.stringify(push_data))


# 删掉指定 id 的本地推送
func remove_push(push_id: String) -> void:
	if _plugin == null:
		return
	print("[UniKit] remove_push: push_id=%s" % push_id)
	_plugin.removeLocalPush(push_id)


# 清空所有本地推送
func remove_all_pushes() -> void:
	if _plugin == null:
		return
	print("[UniKit] remove_all_pushes")
	_plugin.removeAllLocalPush()


# 打开 / 关闭推送总开关
func set_push_enabled(enabled: bool) -> void:
	if _plugin == null:
		return
	_plugin.enablePush(enabled)


# 推送总开关当前是否打开
func is_push_enabled() -> bool:
	if _plugin == null:
		return false
	return _plugin.isEnablePush()


# 系统通知权限是否已开
func is_notification_permission_enabled() -> bool:
	if _plugin == null:
		return false
	return _plugin.isNotificationPermissionEnabled()


# 是否允许跳系统设置页引导（部分商店包会禁用）
func is_goto_setting_enabled() -> bool:
	if _plugin == null:
		return false
	return _plugin.isGotoSettingEnabled()


# 调试用：安排一条 5 秒后立刻触发的测试推送
func trigger_test_push(push_id: String, title: String, content: String) -> void:
	if _plugin == null:
		return
	# 先删同 id，保证能反复触发
	_plugin.removeLocalPush(push_id)
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000)
	# 5 秒后触发一次，不重复
	var push_data: Dictionary = {
		"push_id": push_id,
		"push_time_ms": now_ms + 5000,
		"repeat_interval_ms": 0,
		"is_infinite_repeat": false,
		"disturb_type": 0,
		"contents": {"c0": {"title": title, "content": content}}
	}
	_plugin.saveLocalPush(JSON.stringify(push_data))


# 注册推送指令回调（推送下发 JSON 时会发 push_cmd_received）
func register_cmd_callback() -> void:
	if _plugin == null:
		return
	_plugin.registerCmdCallback()


# ================= 用户标签与设备标识 =================
# 读内置标签（媒体来源、流程域等），客服工单与埋点会用到
func get_inner_tags() -> Dictionary:
	if _plugin == null:
		return {}
	return JSON.parse_string(_plugin.getInnerTagJson())


# 读本地标签（业务自己写进去的 KV）
func get_local_tags() -> Dictionary:
	if _plugin == null:
		return {}
	return JSON.parse_string(_plugin.getLocalTagJson())


# 读远端下发的标签
func get_remote_tags() -> Dictionary:
	if _plugin == null:
		return {}
	return JSON.parse_string(_plugin.getRemoteTagJson())


# 写一个本地标签
func add_local_tag(key: String, value: String) -> void:
	if _plugin == null:
		return
	_plugin.addLocalTag(key, value)


# 写一个列表型本地标签（数组序列化成 JSON 存）
func add_local_list_tag(key: String, values: Array) -> void:
	if _plugin == null:
		return
	_plugin.addLocalListTag(key, JSON.stringify(values))


# 删掉一个本地标签
func remove_local_tag(key: String) -> void:
	if _plugin == null:
		return
	_plugin.removeLocalTag(key)


# 读 LUID（SDK 侧用户标识，客服与 AB 上报用）
func get_luid() -> String:
	if _plugin == null:
		return ""
	return _plugin.getLuid()


# 注册 LUID 监听，就绪后触发 luid_ready
func add_luid_listener() -> void:
	if _plugin == null:
		return
	_plugin.addLuidListener()


# ================= 广告（插屏 / 激励 / Banner） =================
# 预加载某类广告（placement_id：reward / interstitial / banner）
func load_ad(placement_id: String) -> void:
	if _plugin == null:
		return
	_plugin.loadAd(placement_id)


# 展示插屏：调试开关关闭或首局新手流程时不打扰；先埋点登记，再判断是否已就绪
func show_interstitial(placement_id: String, position: String) -> void:
	if _plugin == null:
		return
	# 调试总开关关掉：完全不展示
	if not _debug_ad_enabled:
		return
	# 首次会话（新手）不弹插屏
	if GameState.is_first_session():
		return
	# 每次展示生成唯一 show_id，用来串起埋点与曝光回调
	var show_id: String = _plugin.createShowId()

	# 先埋点并登记 show_id / position，曝光回来才认得出来
	Tracker.track_ad_show_timing(show_id, placement_id, placement_id, position)
	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	# 已就绪才真正交给原生展示
	if _plugin.isAdReady(placement_id, position, show_id):
		_plugin.showAd(placement_id, position, show_id)


# 用现成的 show_id 展示插屏；返回值表示是否走了展示分支（含 Mock）
func try_show_interstitial(placement_id: String, position: String, show_id: String) -> bool:
	# 作弊开关关掉（编辑器默认）：不展示
	if not cheat_show_interstitial:
		return false
	# 编辑器里改用 Mock 界面模拟
	if _is_ad_mock_enabled():
		_mock_show_ad(placement_id, position)
		return true
	if _plugin == null:
		return false
	_plugin.showAd(placement_id, position, show_id)

	return true


# 插屏冷却秒数（由 AB 实验 inter_cd_lc 决定）
func get_interstitial_cd_sec() -> int:
	return ABTestManager.inter_cd_lc.get_cd_sec()


# 是否还在插屏冷却期内
func is_interstitial_in_cd() -> bool:
	var cd_sec: int = get_interstitial_cd_sec()
	var now: int = int(Time.get_unix_time_from_system())
	return now - _last_interstitial_close_unix < cd_sec


# 展示激励视频：作弊开关关掉时直接发奖；reward 位会开一次发奖会话用于超时兜底
func show_reward(placement_id: String, position: String, show_id: String) -> void:
	# 作弊开关关掉：不播广告，直接当成看完发奖
	if not cheat_show_reward:
		_grant_reward_directly(placement_id)
		return
	# 编辑器里改用 Mock 界面模拟
	if _is_ad_mock_enabled():
		_mock_show_ad(placement_id, position)
		return
	if _plugin == null:
		return

	# 只有 reward 位需要发奖兜底会话
	if placement_id == "reward":
		_start_reward_session(show_id, position)
	_plugin.showAd(placement_id, position, show_id)


# 生成原生认可的 show_id；无插件时返回空串
func gen_show_id() -> String:
	if _plugin == null:
		return ""
	return _plugin.createShowId()


# 激励视频是否已加载好；顺带登记 show_id / position 与埋点
func is_reward_ready(placement_id: String, position: String, show_id: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false

	Tracker.track_ad_show_timing(show_id, placement_id, placement_id, position)
	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	return _plugin.isAdReady(placement_id, position, show_id)


# 插屏是否已加载好；同样会登记埋点信息
func is_interstitial_ready(placement_id: String, position: String, show_id: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false
	Tracker.track_ad_show_timing(show_id, placement_id, placement_id, position)
	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	return _plugin.isAdReady(placement_id, position, show_id)


# 激励视频是否仍然有效（展示前校验，防止过期）
func is_reward_valid(placement_id: String, position: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false
	return _plugin.isAdValid(placement_id, position)


# Banner 是否有效
func is_banner_valid(placement_id: String, position: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false
	return _plugin.isAdValid(placement_id, position)


# 插屏是否有效
func is_interstitial_valid(placement_id: String, position: String) -> bool:
	if _is_ad_mock_enabled():
		return true
	if _plugin == null:
		return false
	return _plugin.isAdValid(placement_id, position)


# ================= 广告模拟（仅编辑器，用 Mock UI 顶替原生广告） =================
# 是否走 Mock：编辑器构建下恒为真
func _is_ad_mock_enabled() -> bool:
	return OS.has_feature("editor")


# 用 MockAd 界面模拟一次广告：照样发 shown / impression / closed 回调，业务逻辑与真机保持一致
func _mock_show_ad(placement_id: String, position: String) -> void:
	var show_id: String = "mock_%d" % Time.get_ticks_usec()
	Tracker.track_ad_show_timing(show_id, placement_id, placement_id, position)
	Tracker.remember_ad_show_id(placement_id, show_id)
	_pending_ad_positions[placement_id] = position
	# 激励位先开一次会话，超时兜底才会生效
	if placement_id == "reward":
		_start_reward_session(show_id, position)

	_on_ad_shown(placement_id)
	_on_ad_impression(JSON.stringify({"placement_id": placement_id, "position": position}))

	# 交给 Mock UI 的两个关闭回调：普通关闭与「看完激励」
	var on_close := func() -> void:
		_on_ad_closed(placement_id)
		UIManager.hide_ui(UiName.MOCK_AD)
	# 激励回调按「发奖 → 关闭」的顺序，和真机一致
	var on_reward_close := func() -> void:
		_on_ad_rewarded(placement_id)
		_on_ad_closed(placement_id)
		UIManager.hide_ui(UiName.MOCK_AD)
	# 弹出 Mock 广告界面，并附上定位信息与回调
	(
		UIManager
		. show_ui(
			UiName.MOCK_AD,
			{
				"placement_id": placement_id,
				"position": position,
				"on_close": on_close,
				"on_reward_close": on_reward_close,
			}
		)
	)


# 用 MockBanner 界面模拟 banner（偏移与高度按 1080 基准缩放，和真机一致）
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


# 关掉 Mock banner
func _mock_destroy_banner() -> void:
	UIManager.hide_ui(UiName.MOCK_BANNER)


# 不发广告直接发奖：补一次「发奖 + 关闭」回调
func _grant_reward_directly(placement_id: String) -> void:
	_on_ad_rewarded(placement_id)
	_on_ad_closed(placement_id)


# 调试：开启后激励视频回调被吞掉，用来验证发奖兜底
func set_debug_reward_miss(enabled: bool) -> void:
	_debug_reward_miss = enabled


# 展示 banner：编辑器走 Mock；真机把 1080 基准的偏移 / 高度按屏宽缩放后交给原生
func show_banner(
	placement_id: String,
	position: String,
	anchor_bottom: bool = true,
	offset_base: int = 0,
	height_base: int = 180
) -> void:
	# 作弊开关关掉：不展示
	if not cheat_show_banner:
		return
	if _is_ad_mock_enabled():
		_mock_show_banner(placement_id, position, anchor_bottom, offset_base, height_base)
		return
	if _plugin == null:
		return
	# 以 1080 为设计基准换算到实际像素
	var device_w_px: float = float(DisplayServer.window_get_size().x)
	var scale: float = device_w_px / 1080.0
	var offset_px: int = int(round(offset_base * scale))
	var height_px: int = int(round(height_base * scale))
	_plugin.showBanner(placement_id, position, anchor_bottom, offset_px, height_px)


# 销毁某类广告（编辑器里只处理 Mock banner）
func destroy_ad(placement_id: String) -> void:
	if _is_ad_mock_enabled():
		if placement_id == "banner":
			_mock_destroy_banner()
		return
	if _plugin == null:
		return
	_plugin.destroyAd(placement_id)


# 打开原生广告调试面板
func open_ad_debug_view() -> void:
	if _plugin == null:
		return
	_plugin.openAdDebugView()


# ================= 埋点、标识与异常上报 =================
# 上报自定义事件（params / platforms 会序列化成 JSON，platforms 默认 ["learnings"]）
func send_event(
	event_name: String, params: Dictionary = {}, platforms: Array = [], value_to_sum: float = 0.0
) -> void:
	if _plugin == null:
		return
	var _platforms: Array = platforms if not platforms.is_empty() else ["learnings"]
	_plugin.sendEvent(event_name, JSON.stringify(params), JSON.stringify(_platforms), value_to_sum)


# 读 learnings 渠道 ID
func get_learnings_id() -> String:
	if _plugin == null:
		return ""
	return _plugin.getLearningsId()


# 读设备 UUID
func get_uuid() -> String:
	if _plugin == null:
		return ""
	return _plugin.getUUID()


# 读版本名；没有插件时回退到 project.godot 的 config/version
func get_version_name() -> String:
	if _plugin == null:
		return ProjectSettings.get_setting("application/config/version", "") as String
	return _plugin.getVersionName() as String


# 读版本号（build 号）
func get_version_code() -> int:
	if _plugin == null:
		return 0
	return int(_plugin.getVersionCode())


# 读首次打开时间（毫秒时间戳，由 SDK 侧持久化）
func get_first_open_time_ms() -> int:
	if _plugin == null:
		return 0
	return int(_plugin.getFirstOpenTimeMs())


# 设置用户属性（统计维度）
func set_user_property(key: String, value: String) -> void:
	if _plugin == null:
		return
	_plugin.setUserProperty(key, value)


# 设置事件属性（会附到之后上报的事件上）
func set_event_property(key: String, value: String) -> void:
	if _plugin == null:
		return
	_plugin.setEventProperty(key, value)


# 设置 Crashlytics 用户 ID，方便按用户排查崩溃
func set_crashlytics_user_id(user_id: String) -> void:
	if _plugin == null:
		return
	_plugin.setCrashlyticsUserId(user_id)


# 上报一条异常：没给 stack 就现场抓；统计未初始化时先入缓存（上限 _CRASHLYTICS_LOG_CACHE_MAX）
func log_exception(message: String, stack: String = "") -> void:
	if _plugin == null:
		return

	# 调用方没给调用栈：现场抓一份，并跳过本函数自己的栈帧
	if stack.is_empty():
		stack = _format_gd_backtraces(Engine.capture_script_backtraces(), 1)
	# 统计已就绪：直接上报
	if _is_analyze_inited:
		_plugin.logCrashlyticsException(message, stack)
		return

	# 还没就绪：入缓存，满了丢最旧的一条
	if _crashlytics_log_cache.size() >= _CRASHLYTICS_LOG_CACHE_MAX:
		_crashlytics_log_cache.pop_front()
	_crashlytics_log_cache.append({"message": message, "stack": stack})


# 把引擎的 ScriptBacktrace 数组拼成多行文本；skip_frames 用来跳过封装层自己的栈帧
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


# 请求应用商店评分弹窗
func request_store_review() -> void:
	if _plugin == null:
		return
	_plugin.requestStoreReview()


# 统计模块是否已初始化
func is_analyze_inited() -> bool:
	return _is_analyze_inited


# 广告模块是否已初始化
func is_ad_inited() -> bool:
	return _is_ad_inited


# ================= 原生回调：初始化 =================
# 统计初始化完成：把缓存里的异常补报出去，再通知业务；Cache 清空
func _on_analyze_init_success() -> void:
	_is_analyze_inited = true

	for entry in _crashlytics_log_cache:
		_plugin.logCrashlyticsException(entry["message"], entry["stack"])
	_crashlytics_log_cache.clear()
	analyze_init_completed.emit()


# 广告初始化完成：开启曝光监听，然后按 reward → interstitial → banner 顺序懒预加载
func _on_ad_init_success() -> void:
	if _plugin == null:
		push_warning("UniKit AD init_success but plugin is null")
		return
	# 让原生在曝光时回调（部分版本需要显式开启）
	_plugin.setAdImpressionListener()
	_is_ad_inited = true
	ad_init_completed.emit()

	# 三类广告依次预加载，每个间隔 2 秒，避免开局把网络和原生线程打满
	load_ad("reward")
	await get_tree().create_timer(2.0).timeout
	load_ad("interstitial")
	await get_tree().create_timer(2.0).timeout
	load_ad("banner")


# 广告初始化失败：只告警，不阻塞游戏
func _on_ad_init_error(error: String) -> void:
	push_warning("UniKit AD init error: %s" % error)


# GRT 模块初始化成功（当前无需处理，空实现）
func _on_grt_init_success() -> void:
	# 暂无动作
	pass


# 推送初始化成功 → 注册推送指令回调
func _on_push_init_success() -> void:
	register_cmd_callback()


# 用户标签初始化成功 → 注册 LUID 监听
func _on_usertag_init_success() -> void:
	add_luid_listener()


# 内购初始化成功（当前无需处理）
func _on_purchase_init_success() -> void:
	# 暂无动作
	pass


# 内购初始化失败：告警
func _on_purchase_init_fail(error: String) -> void:
	push_warning("UniKit Purchase init fail: %s" % error)


# AB 参数首次就绪：JSON 解析成字典后转发（解析失败给空字典）
func _on_abtest_init(params_json: String) -> void:
	var d: Variant = JSON.parse_string(params_json)
	abtest_ready.emit(d if d is Dictionary else {})


# AB 参数更新：解析 user_info 后转发
func _on_abtest_updated(update_type: String, user_info_json: String) -> void:
	var d: Variant = JSON.parse_string(user_info_json)
	abtest_params_updated.emit(update_type, d if d is Dictionary else {})


# 远端 AB 配置就绪：原样转发
func _on_abtest_remote_config_ready() -> void:
	abtest_remote_config_ready.emit()


# 本地服务 AB 结果：转发成功标志与错误串
func _on_abtest_locsrv_result(success: bool, error: String) -> void:
	abtest_locsrv_fetched.emit(success, error)


# 归因回调成功：只打日志（数据由原生侧自行上报）
func _on_af_callback_success(data_json: String) -> void:
	print("[UniKit] AF 归因回调成功: ", data_json)


# 归因回调失败：告警
func _on_af_callback_fail(msg: String) -> void:
	push_warning("UniKit AF callback fail: %s" % msg)


# ================= 原生回调：权限与合规 =================
# 推送权限结果：清等待标记并通知业务（_status 未使用）
func _on_push_permission_result(_status: int) -> void:
	_push_permission_pending = false
	push_permission_done.emit()


# 引擎通知：权限弹窗期间回到前台却还没结果，就主动收尾（有些系统不给回调）
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _push_permission_pending:
		_resolve_push_permission_on_focus.call_deferred()


# 回前台兜底：判定权限流程已结束并补发信号
func _resolve_push_permission_on_focus() -> void:
	if not _push_permission_pending:
		return
	_push_permission_pending = false
	push_permission_done.emit()


# 推送指令：转发给业务
func _on_push_cmd_received(cmd_json: String) -> void:
	push_cmd_received.emit(cmd_json)


# CMP 流程结束：转发
func _on_cmp_completed() -> void:
	cmp_completed.emit()


# ATT 状态变化：转发
func _on_att_status_changed(status: int) -> void:
	att_status_changed.emit(status)


# ATT 弹窗关闭：转发
func _on_att_dismissed() -> void:
	att_dismissed.emit()


# LUID 就绪：转发
func _on_luid_ready(luid: String) -> void:
	luid_ready.emit(luid)


# ================= 原生回调：广告 =================
# 广告关闭：记录关闭时刻（插屏冷却以最近一次关闭为起点）、转发信号；reward 位还要统计观看次数并启动发奖兜底
func _on_ad_closed(placement_id: String) -> void:
	print("[UniKit] ad_closed: placement=%s reward_shown=%s" % [placement_id, _reward_shown])

	_last_interstitial_close_unix = int(Time.get_unix_time_from_system())
	ad_closed.emit(placement_id)

	# 激励位额外收尾
	if placement_id == "reward":
	# 真展示过才计入本局观看次数
		if _reward_shown:
			GameState.increment_session_reward_view_count()
		_maybe_start_reward_grant_watchdog()


# 激励视频发奖回调：调试开关可以吞掉它；reward 位记发奖并写一条普通奖励记录
func _on_ad_rewarded(placement_id: String) -> void:
	# 作弊开关：模拟「看完不发奖」
	if _debug_reward_miss and placement_id == "reward":
		print(
			"[UniKit] ad_rewarded SKIPPED by cheat _debug_reward_miss: placement=%s" % placement_id
		)
		return
	print("[UniKit] ad_rewarded: placement=%s" % placement_id)
	ad_rewarded.emit(placement_id)

	# 标记本次会话已发奖，并写入奖励流水（首页据此补发道具）
	if placement_id == "reward":
		_mark_reward_received()

		GameState.record_normal_reward(int(Time.get_unix_time_from_system()))


# 广告展示回调：转发；reward 位借此确认「确实播过」
func _on_ad_shown(placement_id: String) -> void:
	ad_shown.emit(placement_id)
	if placement_id == "reward" and _reward_active_show_id != "":
		_reward_shown = true


# 开一次激励视频会话：记住 show_id / position 并清空发奖标记
func _start_reward_session(show_id: String, position: String) -> void:
	_reward_active_show_id = show_id
	_reward_active_position = position
	_reward_received = false
	_reward_shown = false


# 标记发奖：没有活跃会话时（多见于恢复流程），从看门狗里挑最早的一条消掉
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


# 广告关闭后判断要不要启动发奖兜底：已发奖或压根没展示就直接收尾，否则登记看门狗并起 30 秒定时器
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


# 发奖超时：仅当 AB 允许补发时，把这次奖励写进 GameState 的待补发列表（首页会弹）
func _on_reward_grant_timeout(show_id: String, position: String) -> void:
	if not _pending_watchdogs.has(show_id):
		return
	_pending_watchdogs.erase(show_id)

	# AB 开关：只有允许补发的分组才记这笔账
	if not ABTestManager.common_rewardad_logic.should_grant_reward_restore():
		return

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


# 把广告位 position 映射回它该给的奖励：提示 / 定位 / 撤销各 1 个，连胜翻倍给一整份基础奖励，其余返回空数组
func restore_items_for_position(position: String) -> Array:
	if position == Tracker.AdPos.PROPS_NORMAL_HINT or position == Tracker.AdPos.PROPS_DAILY_HINT:
		return [{"kind": "hint", "count": 1}]
	if (
		position == Tracker.AdPos.PROPS_NORMAL_LOCATE
		or position == Tracker.AdPos.PROPS_DAILY_LOCATE
	):
		return [{"kind": "locate", "count": 1}]

	if position == "props_normal_undo":
		return [{"kind": "undo", "count": 1}]

	if position == Tracker.AdPos.STREAK_X2_REWARD:
		var items: Array = []
		for kind: String in StreakData.REWARD_BASE:
			items.append({"kind": kind, "count": int(StreakData.REWARD_BASE[kind])})
		return items
	return []


# 清空激励视频会话状态
func _reset_reward_session() -> void:
	_reward_active_show_id = ""
	_reward_active_position = ""
	_reward_received = false
	_reward_shown = false


# 广告出错：告警并转发
func _on_ad_error(placement_id: String, msg: String) -> void:
	push_warning("UniKit AD error: placement=%s, msg=%s" % [placement_id, msg])
	ad_error_occurred.emit(placement_id, msg)


# 曝光回调：转发原始数据，并按广告位类型补埋点（interstitial / reward）
func _on_ad_impression(data_json: String) -> void:
	var data: Dictionary = JSON.parse_string(data_json)
	ad_impression_received.emit(data)

	var placement_id: String = data.get("placement_id", "")
	if placement_id == "":
		push_warning("UniKit AD impression: placement_id 为空, raw=%s" % data_json)
		return
	# 取出展示前登记的 show_id 与 position（消费即删除）
	var ad_show_id: String = Tracker.consume_ad_show_id(placement_id)
	var position: String = _pending_ad_positions.get(placement_id, data.get("position", ""))
	_pending_ad_positions.erase(placement_id)
	# 按广告位类型补曝光埋点
	if placement_id == "interstitial":
		Tracker.track_interstitial_ad_show(ad_show_id, GameState.get_current_level(), position)
	elif placement_id == "reward":
		Tracker.track_rewarded_ad_show(ad_show_id, GameState.get_current_level(), position)


# 调试总开关：值有变化才处理，关掉时顺手销毁 banner
func set_debug_ad_enabled(enabled: bool) -> void:
	if _debug_ad_enabled == enabled:
		return
	_debug_ad_enabled = enabled
	# 关掉广告时把 banner 一起销毁
	if not enabled:
		destroy_ad("banner")


# 读调试总开关
func is_debug_ad_enabled() -> bool:
	return _debug_ad_enabled


# ================= AB 实验 =================
# 读字符串型 AB 参数（无插件时返回默认值）
func get_ab_string(key: String, default_value: String = "") -> String:
	if _plugin == null:
		return default_value
	return _plugin.getAbString(key, default_value)


# 读整型 AB 参数
func get_ab_int(key: String, default_value: int = 0) -> int:
	if _plugin == null:
		return default_value
	return _plugin.getAbInt(key, default_value)


# 读浮点型 AB 参数
func get_ab_float(key: String, default_value: float = 0.0) -> float:
	if _plugin == null:
		return default_value
	return _plugin.getAbFloat(key, default_value)


# 把当前设备「染色」进指定 AB 实验组（调试用）
func dye_ab(key: String) -> void:
	if _plugin == null:
		return
	_plugin.dyeAbTest(key)


# 读全部 AB 实验的当前取值
func get_all_ab_experiments() -> Dictionary:
	if _plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_plugin.getAllAbExperimentsJson())
	return d if d is Dictionary else {}


# 读已发布的 AB 实验配置
func get_all_publish_ab_experiments() -> Dictionary:
	if _plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_plugin.getAllPublishAbExperimentsJson())
	return d if d is Dictionary else {}


# 读全部 AB 标签串
func get_ab_all_tag() -> String:
	if _plugin == null:
		return ""
	return _plugin.getAbAllTag()


# 读染色标签（上报「命中实验组」用）
func get_ab_dyeing_tag() -> String:
	if _plugin == null:
		return ""
	return _plugin.getAbDyeingTag()


# 读 AB 分组 ID
func get_ab_group_id() -> String:
	if _plugin == null:
		return ""
	return _plugin.getAbGroupId()


# 读 AB 用户信息字典
func get_ab_user_info() -> Dictionary:
	if _plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_plugin.getAbUserInfoJson())
	return d if d is Dictionary else {}


# 主动拉取远端 AB 结果
func fetch_remote_ab_result() -> void:
	if _plugin == null:
		return
	_plugin.fetchRemoteAbResult()


# 读本地服务 AB 参数（原生返回空串时回退默认值）
func get_ab_locsrv_param(key: String, default_value: String = "") -> String:
	if _plugin == null:
		return default_value
	var v: String = _plugin.getAbLocSrvParam(key)
	return v if v != "" else default_value


# 读全部本地服务 AB 参数
func get_all_ab_locsrv_params() -> Dictionary:
	if _plugin == null:
		return {}
	var d: Variant = JSON.parse_string(_plugin.getAllAbLocSrvParamsJson())
	return d if d is Dictionary else {}


# 本地服务 AB 染色（调试用）
func dye_ab_locsrv(key: String) -> void:
	if _plugin == null:
		return
	_plugin.dyeAbLocSrvTest(key)


# 写入本地服务 AB 的全部标签
func set_ab_locsrv_all_tag(tags: Array[String]) -> void:
	if _plugin == null:
		return
	_plugin.setAbLocSrvAllTag(JSON.stringify(tags))


# 按标签染色本地服务 AB
func dye_ab_locsrv_tag(tag: String) -> void:
	if _plugin == null:
		return
	_plugin.dyeAbLocSrvTag(tag)


# 读 AB 判定的国家 / 地区
func get_ab_country() -> String:
	if _plugin == null:
		return ""
	return _plugin.getAbCountry()


# 覆盖 AB 分组 ID（调试用）
func set_ab_group_id(group_id: String) -> void:
	if _plugin == null:
		return
	_plugin.setAbGroupId(group_id)


# 覆盖 AB 国家 / 地区（调试用）
func set_ab_country(country: String) -> void:
	if _plugin == null:
		return
	_plugin.setAbCountry(country)
