## 广告原生桥接：按广告位发起加载、查询和展示，并把原生事件暴露给业务层。
class_name UniKitAdModule
extends UniKitModuleBase

signal ad_loaded(placement_id: String)
signal ad_closed(placement_id: String)
signal ad_rewarded(placement_id: String)
signal ad_error_occurred(placement_id: String, msg: String)
signal ad_impression_received(data: Dictionary)
signal ad_will_show(placement_id: String)
signal ad_init_completed
signal ad_is_ready_result(placement_id: String, is_ready: bool)
signal ad_is_valid_result(placement_id: String, is_valid: bool)

var _is_ad_inited: bool = false


## 请求原生加载指定广告位，加载完成另由信号通知。
func load_ad(placement_id: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.loadAd(placement_id)


## 记录一次广告展示时机，并取得后续查询与展示使用的 show_id。
func stats_ad_show_timing(placement_id: String, position: String) -> String:
	if _host._plugin == null:
		return ""
	return _host._plugin.statsAdShowTiming(placement_id, position)


## 记录广告位在指定展示时机变为有效的埋点。
func stats_ad_became_valid(placement_id: String, position: String, ad_show_id: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.statsAdBecameValid(placement_id, position, ad_show_id)


## 请求原生检查可展示状态，等待同一广告位的异步回执。
func is_ad_ready(placement_id: String, position: String, show_id: String) -> bool:
	if _host._plugin == null:
		return false
	_host._plugin.isAdReady(placement_id, position, show_id)
	return await _await_ad_is_ready(placement_id)


## 把广告位、业务位置和展示流水标识一起提交给原生展示接口。
func show_ad(placement_id: String, position: String, show_id: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.showAd(placement_id, position, show_id)


## 记录展示时机并等待就绪检查，通过后才发起插屏展示。
func try_show_interstitial(placement_id: String, position: String) -> bool:
	if _host._plugin == null:
		return false
	var show_id: String = _host._plugin.statsAdShowTiming(placement_id, position)
	_host._plugin.isAdReady(placement_id, position, show_id)
	if not await _await_ad_is_ready(placement_id):
		return false
	_host._plugin.showAd(placement_id, position, show_id)
	return true


## 记录激励广告时机并等待就绪，奖励是否到账由后续事件决定。
func show_reward(placement_id: String, position: String) -> void:
	if _host._plugin == null:
		return
	var show_id: String = _host._plugin.statsAdShowTiming(placement_id, position)
	_host._plugin.isAdReady(placement_id, position, show_id)
	if await _await_ad_is_ready(placement_id):
		_host._plugin.showAd(placement_id, position, show_id)


## 异步查询激励广告位是否满足原生有效性条件。
func is_reward_valid(placement_id: String, position: String) -> bool:
	if _host._plugin == null:
		return false
	_host._plugin.isAdValid(placement_id, position)
	return await _await_ad_is_valid(placement_id)


## 异步查询横幅广告位是否满足原生有效性条件。
func is_banner_valid(placement_id: String, position: String) -> bool:
	if _host._plugin == null:
		return false
	_host._plugin.isAdValid(placement_id, position)
	return await _await_ad_is_valid(placement_id)


## 异步查询插屏广告位是否满足原生有效性条件。
func is_interstitial_valid(placement_id: String, position: String) -> bool:
	if _host._plugin == null:
		return false
	_host._plugin.isAdValid(placement_id, position)
	return await _await_ad_is_valid(placement_id)


## 忽略其他广告位的就绪回执，只返回本次查询广告位的结果。
func _await_ad_is_ready(placement_id: String) -> bool:
	while true:
		var r: Array = await ad_is_ready_result
		if r[0] == placement_id:
			return r[1]
	return false


## 忽略其他广告位的有效性回执，只返回目标广告位的结果。
func _await_ad_is_valid(placement_id: String) -> bool:
	while true:
		var r: Array = await ad_is_valid_result
		if r[0] == placement_id:
			return r[1]
	return false


## 把按 1080 宽设计的高度和偏移转换为窗口像素后展示原生横幅。
func show_banner(
	placement_id: String,
	position: String,
	anchor_bottom: bool = true,
	offset_base: int = 0,
	height_base: int = 180
) -> void:
	if _host._plugin == null:
		return
	var device_w_px: float = float(DisplayServer.window_get_size().x)
	var scale: float = device_w_px / 1080.0
	var offset_px: int = int(round(offset_base * scale))
	var height_px: int = int(round(height_base * scale))
	_host._plugin.showBanner(placement_id, position, anchor_bottom, offset_px, height_px)


## 请求原生暂停指定广告位。
func pause_ad(placement_id: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.pauseAd(placement_id)


## 请求原生恢复指定广告位。
func resume_ad(placement_id: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.resumeAd(placement_id)


## 请求原生销毁指定广告位占用的广告视图或资源。
func destroy_ad(placement_id: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.destroyAd(placement_id)


## 打开原生广告调试界面。
func open_ad_debug_view() -> void:
	if _host._plugin == null:
		return
	_host._plugin.openAdDebugView()


## 将广告静音开关交给原生 SDK。
func set_mute_ad(mute: bool) -> void:
	if _host._plugin == null:
		return
	_host._plugin.setMuteAd(mute)


## 将邮箱传给原生 UID2 注册接口。
func register_uid2(email: String) -> void:
	if _host._plugin == null:
		return
	_host._plugin.registerUid2(email)


## 查询是否已收到原生广告初始化成功事件。
func is_ad_inited() -> bool:
	return _is_ad_inited


## 仅在 iOS 原生插件可用时触发广告加载失败测试。
func debug_mock_ad_load_fail() -> void:
	if _host._plugin == null:
		return
	if not OS.has_feature("ios"):
		return
	_host._plugin.debugMockAdLoadFail()
