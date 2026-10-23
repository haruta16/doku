## UniKit 插件宿主：组装各子模块、连接原生事件，并提供隐私与初始化入口。
extends Node

signal cmp_completed

signal att_status_changed(status: int)

signal att_dismissed

const ATT_STATUS_NOT_DETERMINED: int = 0
const ATT_STATUS_AUTHORIZED: int = 1
const ATT_STATUS_SYSTEM_DENIED: int = 2
const ATT_STATUS_APP_DENIED: int = 3

var _plugin: Object = null

var analyze_module: UniKitAnalyzeModule
var ad_module: UniKitAdModule
var abtest_module: UniKitAbTestModule
var push_module: UniKitPushModule
var usertag_module: UniKitUserTagModule
var grt_module: UniKitGrtModule
var purchase_module: UniKitPurchaseModule

var _purchase_bridge: UniKitPurchaseNativeBridge


## 创建子模块并连接原生单例事件，支付模块另经跨平台交易桥适配。
func _ready() -> void:
	analyze_module = UniKitAnalyzeModule.new(self)
	ad_module = UniKitAdModule.new(self)
	abtest_module = UniKitAbTestModule.new(self)
	push_module = UniKitPushModule.new(self)
	usertag_module = UniKitUserTagModule.new(self)
	grt_module = UniKitGrtModule.new(self)
	purchase_module = UniKitPurchaseModule.new(self)
	if Engine.has_singleton("UniKitPlugin"):
		_plugin = Engine.get_singleton("UniKitPlugin")

		_plugin.ad_init_success.connect(_on_ad_init_success)
		_plugin.ad_init_error.connect(_on_ad_init_error)
		_plugin.abtest_init.connect(_on_abtest_init)
		_plugin.abtest_updated.connect(_on_abtest_updated)
		_plugin.abtest_locsrv_result.connect(_on_abtest_locsrv_result)
		_plugin.af_callback_success.connect(_on_af_callback_success)
		_plugin.af_callback_fail.connect(_on_af_callback_fail)
		_plugin.luid_ready.connect(_on_luid_ready)
		_plugin.ad_closed.connect(_on_ad_closed)
		_plugin.ad_rewarded.connect(_on_ad_rewarded)
		_plugin.ad_error.connect(_on_ad_error)
		_plugin.ad_impression.connect(_on_ad_impression)
		_plugin.push_permission_result.connect(_on_push_permission_result)
		_plugin.push_cmd_received.connect(_on_push_cmd_received)

		if _plugin.has_signal("push_authorization_status"):
			_plugin.push_authorization_status.connect(_on_push_authorization_status)

		_plugin.cmp_completed.connect(_on_cmp_completed)

		if OS.has_feature("ios"):
			_plugin.att_status_changed.connect(_on_att_status_changed)
			_plugin.att_dismissed.connect(_on_att_dismissed)

		_connect_required("ad_will_show", _on_ad_will_show)
		_connect_required("ad_loaded", _on_ad_loaded)
		_connect_required("abtest_remote_config_ready", _on_abtest_remote_config_ready)
		_plugin.ad_is_ready.connect(_on_ad_is_ready)
		_plugin.ad_is_valid.connect(_on_ad_is_valid)
		_plugin.af_data_result.connect(_on_af_data_result)
		_plugin.deep_link_data_result.connect(_on_deep_link_data_result)
		_plugin.usertag_data_updated.connect(_on_usertag_data_updated)

		_connect_required("ltv_received", _on_ltv_received)
	else:
		# 恢复工程在编辑器和桌面端没有原生 SDK；移动端缺插件仍保留警告。
		if OS.has_feature("editor") or not (OS.has_feature("android") or OS.has_feature("ios")):
			print("[学习工程] UniKitPlugin 不可用，继续使用脚本端回退行为")
		else:
			push_warning("UniKitPlugin not available (non-Android platform)")

	_purchase_bridge = UniKitPurchaseNativeBridge.new(self)
	purchase_module._set_native_bridge(_purchase_bridge)
	_purchase_bridge.native_init_success.connect(_on_purchase_init_success)
	_purchase_bridge.native_init_fail.connect(_on_purchase_init_fail)
	_purchase_bridge.native_restored.connect(_on_purchase_restored)
	_purchase_bridge.native_purchase_success.connect(_on_purchase_success)
	_purchase_bridge.native_purchase_fail.connect(_on_purchase_fail)
	_purchase_bridge.native_query_success.connect(_on_purchase_query_success)
	_purchase_bridge.native_query_fail.connect(_on_purchase_query_fail)
	_purchase_bridge.native_finish_order_success.connect(_on_purchase_finish_order_success)
	_purchase_bridge.native_finish_order_fail.connect(_on_purchase_finish_order_fail)
	_purchase_bridge.native_receipt_verified.connect(_on_purchase_receipt_verified)


## 判断原生 UniKitPlugin 单例是否存在，脚本模块存在不代表原生服务可用。
func is_available() -> bool:
	return _plugin != null


## 连接协议必需的原生信号，缺失时报告桥接版本不匹配。
func _connect_required(sig: String, cb: Callable) -> void:
	if _plugin != null and _plugin.has_signal(sig):
		_plugin.connect(sig, cb)
	else:
		push_error("[UniKit] plugin 未声明信号 '%s'——原生 bridge 版本过旧，该事件将丢失，请重新同步 addon" % sig)


## 保存商品和校验策略后提交原生初始化参数，iOS 同时传入隐私同意状态。
func initialize(params: UniKitInitParams) -> void:
	if params == null:
		push_error("[UniKit] initialize(null)：UniKitInitParams 为空")
		return

	purchase_module._snapshot_init_params(params)

	if _purchase_bridge != null:
		var all_ids := PackedStringArray()
		all_ids.append_array(params.consumable_product_ids)
		all_ids.append_array(params.entitled_product_ids)
		all_ids.append_array(params.subscription_product_ids)
		_purchase_bridge.set_product_ids(all_ids)
	if _plugin == null:
		return
	var json: String = JSON.stringify(params.to_json_dict())
	print(
		(
			"[UniKit][initialize] begin productionId=%s isDebug=%s firstOpenTime=%d"
			% [params.production_id, params.is_debug, params.first_open_time_ms]
		)
	)
	if OS.has_feature("android"):
		_plugin.initialize(json)
	elif OS.has_feature("ios"):
		_plugin.initialize(json, is_privacy_agreed())


## 查询原生 SDK 是否要求展示隐私界面，插件缺失时返回 false。
func check_privacy_required() -> bool:
	if _plugin == null:
		return false
	return _plugin.checkPrivacyUiRequired()


## 通知原生 SDK 用户已同意隐私条款。
func agree_privacy() -> void:
	if _plugin == null:
		return
	_plugin.agreePrivacyPolicy()


## 查询原生持久化的隐私同意状态。
func is_privacy_agreed() -> bool:
	if _plugin == null:
		return false
	return _plugin.isPrivacyPolicyAgreed()


## 仅在 iOS 向原生注册转化报告接口。
func register_icm_conversion_report() -> void:
	if _plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_plugin.registerICMConversionReport()


## 连接一次性完成回调并发起隐私同意检查；无插件时延迟结束流程。
func check_cmp(on_done: Callable = Callable()) -> void:
	if on_done.is_valid():
		cmp_completed.connect(on_done, CONNECT_ONE_SHOT)
	if _plugin == null:
		cmp_completed.emit.call_deferred()
		return
	_plugin.checkCMP()


## 查询是否需要展示 CMP 隐私同意界面。
func check_cmp_required() -> bool:
	if _plugin == null:
		return false
	return _plugin.checkCMPUiRequired()


## 请求原生显示 CMP 界面。
func show_cmp_ui() -> void:
	if _plugin == null:
		return
	_plugin.showCMPUi()


## 只有 iOS 原生插件可用时才查询 ATT 弹窗是否可显示。
func can_show_att() -> bool:
	if not OS.has_feature("ios"):
		return false
	if _plugin == null:
		return false
	return _plugin.canShowATT()


## 仅在 iOS 初始化 ATT 相关原生状态。
func init_att() -> void:
	if _plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_plugin.initATT()


## 在 iOS 显示带来源标识的 ATT 请求。
func show_att_alert(source: String) -> void:
	if _plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_plugin.showATTAlert(source)


## 读取 iOS ATT 状态，其他环境回退到尚未询问。
func get_att_status() -> int:
	if _plugin == null:
		return ATT_STATUS_NOT_DETERMINED
	if not OS.has_feature("ios"):
		return ATT_STATUS_NOT_DETERMINED
	return _plugin.getATTStatus()


## 把业务账号标识交给原生 SDK，以关联统计和实验身份。
func set_account_id(account_id: String) -> void:
	if _plugin == null:
		return
	_plugin.setAccountId(account_id)


## 请求原生按地区处理隐私链接；无插件时保留原链接。
func get_localized_privacy_url(url: String) -> String:
	if _plugin == null:
		return url
	return _plugin.getLocalizedPrivacyUrl(url)


## 注册曝光监听，标记广告子模块初始化完成并发信号。
func _on_ad_init_success() -> void:
	if _plugin == null:
		push_warning("UniKit AD init_success but plugin is null")
		return
	_plugin.setAdImpressionListener()
	ad_module._is_ad_inited = true
	ad_module.ad_init_completed.emit()


## 记录原生广告初始化失败原因。
func _on_ad_init_error(error: String) -> void:
	push_warning("UniKit AD init error: %s" % error)


## 把商品初始化结果交给内购状态机。
func _on_purchase_init_success(products_json: String) -> void:
	purchase_module._on_init_succeed(products_json)


## 把支付初始化错误交给内购状态机。
func _on_purchase_init_fail(error_json: String) -> void:
	purchase_module._on_init_failed(error_json)


## 把原生补单交易交给内购模块的被动交易流程。
func _on_purchase_restored(purchase_json: String) -> void:
	purchase_module._on_purchase_restored(purchase_json)


## 把主动购买成功交给内购模块，继续发货和结单流程。
func _on_purchase_success(product_id: String, purchase_json: String) -> void:
	purchase_module._on_process_purchase_succeed(product_id, purchase_json)


## 把商品购买失败转交内购模块。
func _on_purchase_fail(product_id: String, error_json: String) -> void:
	purchase_module._on_process_purchase_failed(product_id, error_json)


## 把已购清单交给内购模块做权益对账。
func _on_purchase_query_success(purchases_json: String) -> void:
	purchase_module._on_query_all_purchases(purchases_json)


## 把已购查询失败交给内购模块，保留平台错误语义。
func _on_purchase_query_fail(error_json: String) -> void:
	purchase_module._on_query_all_purchases_failed(error_json)


## 通知内购模块清理已完成订单的待处理状态。
func _on_purchase_finish_order_success(product_id: String, token: String) -> void:
	purchase_module._on_finish_order_succeed(product_id, token)


## 通知内购模块记录结单失败并安排后续重试。
func _on_purchase_finish_order_fail(product_id: String, error_json: String) -> void:
	purchase_module._on_finish_order_failed(product_id, error_json)


## 把验票结果交给内购模块更新订阅和权益状态。
func _on_purchase_receipt_verified(receipts_json: String) -> void:
	purchase_module._on_subscription_update(receipts_json)


## 解析实验用户信息后发出实验就绪信号。
func _on_abtest_init(params_json: String) -> void:
	var d: Variant = JSON.parse_string(params_json)
	abtest_module.abtest_ready.emit(d if d is Dictionary else {})


## 解析实验更新数据并保留更新类型。
func _on_abtest_updated(update_type: String, user_info_json: String) -> void:
	var d: Variant = JSON.parse_string(user_info_json)
	abtest_module.abtest_params_updated.emit(update_type, d if d is Dictionary else {})


## 把远端实验拉取成功标志转为模块信号。
func _on_abtest_locsrv_result(success: bool) -> void:
	abtest_module.abtest_locsrv_fetched.emit(success)


## 转发原生远端实验配置就绪事件。
func _on_abtest_remote_config_ready() -> void:
	abtest_module.abtest_remote_config_ready.emit()


## 解析归因数据并转发给统计模块订阅者。
func _on_af_callback_success(data_json: String) -> void:
	var d: Variant = JSON.parse_string(data_json)
	analyze_module.af_conversion_success.emit(d if d is Dictionary else {})


## 记录原生归因错误并发送失败信号。
func _on_af_callback_fail(msg: String) -> void:
	push_warning("UniKit AF callback fail: %s" % msg)
	analyze_module.af_conversion_fail.emit(msg)


## 通知推送模块结束待完成的权限流程。
func _on_push_permission_result(_status: int) -> void:
	push_module._resolve_permission()


## 应用回到前台时，让推送模块补结束从系统设置返回的权限流程。
func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_FOCUS_IN
		and push_module != null
		and push_module._push_permission_pending
	):
		push_module._on_focus_in.call_deferred()


## 转发原生命令 JSON，由推送业务自行解释。
func _on_push_cmd_received(cmd_json: String) -> void:
	push_module.push_cmd_received.emit(cmd_json)


## 转发 CMP 隐私流程完成信号。
func _on_cmp_completed() -> void:
	cmp_completed.emit()


## 转发 iOS ATT 状态变化。
func _on_att_status_changed(status: int) -> void:
	att_status_changed.emit(status)


## 转发 ATT 系统弹窗关闭事件。
func _on_att_dismissed() -> void:
	att_dismissed.emit()


## 通知广告模块该广告位即将展示。
func _on_ad_will_show(placement_id: String) -> void:
	ad_module.ad_will_show.emit(placement_id)


## 通知广告模块该广告位已加载完成。
func _on_ad_loaded(placement_id: String) -> void:
	ad_module.ad_loaded.emit(placement_id)


## 把原生用户标识交给标签模块的就绪信号。
func _on_luid_ready(luid: String) -> void:
	usertag_module.luid_ready.emit(luid)


## 转发广告位关闭事件。
func _on_ad_closed(placement_id: String) -> void:
	ad_module.ad_closed.emit(placement_id)


## 转发原生确认的激励广告奖励事件。
func _on_ad_rewarded(placement_id: String) -> void:
	ad_module.ad_rewarded.emit(placement_id)


## 记录广告错误并携带广告位发送错误信号。
func _on_ad_error(placement_id: String, msg: String) -> void:
	push_warning("UniKit AD error: placement=%s, msg=%s" % [placement_id, msg])
	ad_module.ad_error_occurred.emit(placement_id, msg)


## 把原生曝光 JSON 转换为字典后发布。
func _on_ad_impression(data_json: String) -> void:
	var data: Dictionary = JSON.parse_string(data_json)
	ad_module.ad_impression_received.emit(data)


## 将广告位就绪查询回执交给等待该结果的模块协程。
func _on_ad_is_ready(placement_id: String, is_ready: bool) -> void:
	ad_module.ad_is_ready_result.emit(placement_id, is_ready)


## 将广告位有效性查询回执交给等待该结果的模块协程。
func _on_ad_is_valid(placement_id: String, is_valid: bool) -> void:
	ad_module.ad_is_valid_result.emit(placement_id, is_valid)


## 转发系统通知授权状态查询结果。
func _on_push_authorization_status(status: int) -> void:
	push_module.push_authorization_status.emit(status)


## 向用户价值模块转发原生 LTV 查询结果。
func _on_ltv_received(ltv: float) -> void:
	grt_module.ltv_received.emit(ltv)


## 把原生归因 JSON 转成标签模块使用的字典事件。
func _on_af_data_result(af_data_json: String) -> void:
	var d: Variant = JSON.parse_string(af_data_json)
	usertag_module.af_data_result.emit(d if d is Dictionary else {})


## 把原生深度链接 JSON 转成字典后发布。
func _on_deep_link_data_result(data_json: String) -> void:
	var d: Variant = JSON.parse_string(data_json)
	usertag_module.deep_link_data_result.emit(d if d is Dictionary else {})


## 让标签模块统一更新缓存并通知订阅者。
func _on_usertag_data_updated(json: String) -> void:
	usertag_module._on_usertag_data_updated(json)
