## 订阅业务入口；监听原生内购信号，缓存有效订阅和商品信息，并管理每日 VIP 礼包。
## 购买提交与购买完成是两件事，最终结果来自 SDK 回调；编辑器模拟路径只用于本地学习测试。

extends Node

signal products_ready

signal purchase_result(
	success: bool, product_id: String, error: UniKitPurchaseError, is_active_purchase: bool
)

signal restore_result(success: bool, error: UniKitPurchaseError)

signal _restore_settled(success: bool, error: UniKitPurchaseError)

signal vip_refreshed(is_active: bool)

signal vip_status_changed(is_active: bool)

const SAVE_PATH := "user://purchase.cfg"

var _products: Dictionary = {}

var _products_loaded: bool = false

var _last_buy_product_id: String = ""

var _purchasing: bool = false

var _data: PurchaseData = PurchaseData.new()


## 恢复本地订阅缓存并连接 SDK 的初始化、购买、订阅更新和恢复结果信号。
func _ready() -> void:
	_load()

	GameState.all_data_reset.connect(_reset_data)

	var module: UniKitPurchaseModule = UniKit.purchase_module
	if module == null:
		push_error("[Purchase (PurchaseManager)] UniKit.purchase_module 为空,内购不可用(_ready 接线)")
		return
	module.purchase_initialized.connect(_on_purchase_init_success)
	module.purchase_init_failed.connect(_on_purchase_init_failed)
	module.purchase_processing.connect(_on_purchase_processing)
	module.purchase_failed.connect(_on_purchase_failed)
	module.subscription_updated.connect(_on_subscription_updated)
	module.restore_succeed.connect(_on_restore_succeed)
	module.restore_failed.connect(_on_restore_failed)

	print(
		(
			"[Purchase (PurchaseManager)] addon 信号已接线 platform=%s subscription_ids=%d"
			% ["ios" if OS.has_feature("ios") else "android", get_sub_product_ids_cfg().size()]
		)
	)


func _save() -> void:
	var cfg := ConfigFile.new()
	var d: Dictionary = _data.to_dict()
	for k: String in d:
		cfg.set_value("purchase", k, d[k])
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(SAVE_PATH)
	if err == ERR_FILE_NOT_FOUND:
		print("[Purchase (PurchaseManager)] purchase.cfg 不存在（首次安装 / 卸载重装），订阅数据取默认值")
		return
	if err != OK:
		push_warning(
			"[Purchase (PurchaseManager)] purchase.cfg 读取失败(err=%d),订阅数据回落默认值(冷启查商店会纠正)" % err
		)
		return
	var keys: PackedStringArray = (
		cfg.get_section_keys("purchase") if cfg.has_section("purchase") else PackedStringArray()
	)
	if keys.is_empty():
		print("[Purchase (PurchaseManager)] purchase.cfg 存在但内容为空，订阅数据取默认值")
		return
	var d: Dictionary = {}
	for k: String in keys:
		d[k] = cfg.get_value("purchase", k)
	_data = PurchaseData.from_dict(d)
	print(
		(
			"[Purchase (PurchaseManager)] 订阅数据已读回: active=%s tier=%d owned=%s vip_price_lock=%d"
			% [
				_data.vip_active,
				get_vip_tier(),
				str(_data.valid_sub_product_ids),
				_data.vip_price_ab_lock
			]
		)
	)


func _reset_data() -> void:
	var was_active: bool = _data.vip_active
	_data = PurchaseData.new()
	_save()
	if was_active:
		vip_status_changed.emit(false)


func is_vip_active() -> bool:
	return _data.vip_active


func is_purchasing() -> bool:
	return _purchasing


func get_vip_daily_gift_last_claim_date() -> String:
	return _data.vip_daily_gift_last_claim_date


func set_vip_daily_gift_last_claim_date(date: String) -> void:
	_data.vip_daily_gift_last_claim_date = date
	_save()


func get_valid_sub_product_ids() -> Array:
	return _data.valid_sub_product_ids.duplicate()


func set_valid_sub_product_ids(product_ids: Array) -> void:
	if _data.valid_sub_product_ids == product_ids:
		return
	_data.valid_sub_product_ids = product_ids.duplicate()
	_save()


func get_vip_plan_product_id() -> String:
	return PurchaseDefine.highest_priced_product_id(_data.valid_sub_product_ids)


func has_multiple_subscriptions() -> bool:
	return _data.valid_sub_product_ids.size() > 1


func get_vip_tier() -> int:
	return PurchaseDefine.tier_of_product_id(get_vip_plan_product_id())


func on_vip_purchased(product_id: String) -> void:
	var was_active: bool = _data.vip_active
	_data.vip_active = true
	if not product_id.is_empty() and not _data.valid_sub_product_ids.has(product_id):
		_data.valid_sub_product_ids.append(product_id)
	_save()
	print(
		(
			"[Purchase (PurchaseManager)] on_vip_purchased product_id=%s active=%s→true owned=%s"
			% [product_id, was_active, str(_data.valid_sub_product_ids)]
		)
	)
	if not was_active:
		vip_status_changed.emit(true)


func set_vip_subscription(active: bool) -> void:
	var changed: bool = active != _data.vip_active
	_data.vip_active = active
	if not active:
		_data.valid_sub_product_ids = []
	_save()

	if changed:
		print(
			(
				"[Purchase (PurchaseManager)] VIP 翻转 active=%s%s"
				% [active, "（有效订阅列表已清空）" if not active else ""]
			)
		)
		vip_status_changed.emit(active)


func get_vip_sub_inter_last_show_date() -> String:
	return _data.vip_sub_inter_last_show_date


func mark_vip_sub_inter_shown() -> void:
	_data.vip_sub_inter_last_show_date = _today_str()
	_save()
	print(
		(
			"[Purchase (PurchaseManager)] is_vip 组2 插屏位日配额已消耗 date=%s"
			% _data.vip_sub_inter_last_show_date
		)
	)


func get_vip_price_ab_lock() -> int:
	return _data.vip_price_ab_lock


func has_vip_price_ab_lock() -> bool:
	return _data.vip_price_ab_lock >= 0


func get_effective_vip_price_group() -> int:
	if has_vip_price_ab_lock():
		return get_vip_price_ab_lock()
	return int(ABTestManager.vip_price.value())


func is_subscription_entry_enabled() -> bool:
	return (
		ABTestManager.is_vip.is_entry_enabled()
		and VipPriceConfig.entry_enabled_for(get_effective_vip_price_group())
	)


## 保存当前价格实验分组，避免购买流程中的套餐与价格因实验配置刷新而漂移。
func lock_vip_price_ab(group: int) -> void:
	if _data.vip_price_ab_lock >= 0:
		return
	if group < 0:
		push_error("[Purchase (PurchaseManager)] lock_vip_price_ab 收到非法分组 %d，忽略" % group)
		return
	_data.vip_price_ab_lock = group
	_save()

	print("[Purchase (PurchaseManager)] vip_price 分组已锁定 group=%d（此后远端改组不影响套餐列表）" % group)


func clear_vip_price_ab_lock() -> void:
	if _data.vip_price_ab_lock < 0:
		return
	var was: int = _data.vip_price_ab_lock
	_data.vip_price_ab_lock = -1
	_save()

	print(
		(
			"[Purchase (PurchaseManager)] vip_price 分组锁已解除 was=%d（恢复成功但无订阅权益，此后按实时 AB 渲染；实时若为 0 组则订阅入口消失，产品已签收）"
			% was
		)
	)


func get_sub_product_ids_cfg() -> Array:
	return (
		PurchaseDefine.SUBSCRIPTION_IDS_IOS
		if OS.has_feature("ios")
		else PurchaseDefine.SUBSCRIPTION_IDS_ANDROID
	)


func get_products() -> Dictionary:
	return _products


func is_products_loaded() -> bool:
	return _products_loaded


func _reload_products_from_app_store() -> void:
	if not _check_purchase_sdk():
		print(
			"[Purchase (PurchaseManager)] _reload_products_from_app_store 跳过：内购未 init（商品表保持原样，页面会显示 --）"
		)
		return

	var arr: Array[UniKitPurchaseProduct] = UniKit.purchase_module.get_available_products()
	_products.clear()
	for p: UniKitPurchaseProduct in arr:
		if not p.id.is_empty():
			_products[p.id] = p
	_products_loaded = true
	print(
		(
			"[Purchase (PurchaseManager)] products loaded count=%d ids=%s"
			% [_products.size(), _products.keys()]
		)
	)
	for product_id: String in _products:
		var p: UniKitPurchaseProduct = _products[product_id]
		print(
			(
				"[Purchase (PurchaseManager)]   · %s | title=%s | display_price=%s | price=%.2f | currency=%s"
				% [
					product_id,
					p.title,
					p.display_price,
					p.price,
					p.currency_code,
				]
			)
		)
	products_ready.emit()


func update_subscription() -> void:
	if not _check_purchase_sdk():
		print(
			(
				"[Purchase (PurchaseManager)] update_subscription 跳过：内购未 init（本次不重算 VIP） by=%s"
				% _caller_chain()
			)
		)
		return
	print(
		(
			"[Purchase (PurchaseManager)] update_subscription → 静默查已购（无回执，刷新成功落定即回一条 subscription_updated，含对账撤销） by=%s"
			% _caller_chain()
		)
	)
	UniKit.purchase_module.update_subscription()


## SDK 就绪后重新查询订阅，更新有效商品和 VIP 状态；尚未就绪时保留本地缓存，避免错误降级。
func _recompute_vip() -> void:
	if not _check_purchase_sdk():
		print(
			(
				"[Purchase (PurchaseManager)] VIP 重算 跳过：内购未 init（VIP 保持原值，不冲成 false） by=%s"
				% _caller_chain()
			)
		)
		return
	var was_active: bool = _data.vip_active
	var active: bool = UniKit.purchase_module.is_any_subscription_active()

	print(
		(
			"[Purchase (PurchaseManager)] recompute VIP: active=%s was=%s by=%s"
			% [active, was_active, _caller_chain()]
		)
	)

	if active:
		_resolve_owned_subscriptions()
	set_vip_subscription(active)
	vip_refreshed.emit(active)


## 逐个确认有效商品，保留多订阅事实并选择用于展示权益的套餐；重复订阅会有诊断日志。
func _resolve_owned_subscriptions() -> void:
	var mod: UniKitPurchaseModule = UniKit.purchase_module

	var owned: Array = []

	var probe: PackedStringArray = PackedStringArray()
	var all_ids: Array = get_sub_product_ids_cfg()
	for product_id: String in all_ids:
		var ok: bool = mod.is_valid_subscription(product_id)
		probe.append("%s=%s" % [product_id.trim_prefix("com.oakever.meowdoku."), ok])
		if ok:
			owned.append(product_id)
	print("[Purchase (PurchaseManager)] is_valid_subscription 逐档: %s" % " ".join(probe))
	if owned.is_empty():
		push_warning("[Purchase (PurchaseManager)] VIP 有效但 6 个商品逐档都查不出有效订阅，保持原列表不动")
		return
	if owned.size() > 1:
		push_error("[Purchase (PurchaseManager)] 检测到多笔同时生效的订阅（重复扣费）: %s" % str(owned))
	if _data.valid_sub_product_ids != owned:
		print(
			(
				"[Purchase (PurchaseManager)] 有效订阅列表更新: %s → %s（生效 %s / tier %d）"
				% [
					str(_data.valid_sub_product_ids),
					str(owned),
					PurchaseDefine.highest_priced_product_id(owned),
					PurchaseDefine.tier_of_product_id(
						PurchaseDefine.highest_priced_product_id(owned)
					)
				]
			)
		)
	set_valid_sub_product_ids(owned)


## 校验 SDK、持有状态和在途购买后提交订单；返回 true 只表示请求已提交，成功仍需等待回调。
func buy(product_id: String, force: bool = false) -> bool:
	if not _check_purchase_sdk():
		print("[Purchase (PurchaseManager)] buy() 拒绝：内购未 init / 不可用，product_id=%s" % product_id)
		return false
	if not force and is_vip_active():
		print("[Purchase (PurchaseManager)] buy() 拒绝：已是 VIP，不重复购买 product_id=%s" % product_id)
		return false
	if not force and _purchasing:
		print("[Purchase (PurchaseManager)] buy() 拒绝：上一笔购买还在飞（防重复扣费），product_id=%s" % product_id)
		return false
	print("[Purchase (PurchaseManager)] buy() product_id=%s" % product_id)

	_purchasing = true
	_last_buy_product_id = product_id
	var params := UniKitPurchaseParams.new()
	params.product_id = product_id

	UniKit.purchase_module.purchase(params)
	return true


## 异步恢复商店购买记录并等待结果；编辑器可走明确的假商店测试路径，真实恢复依赖原生 SDK。
func restore_purchase() -> void:
	if not _check_purchase_sdk():
		if OS.has_feature("editor"):
			_debug_apply_fake_store_restore()
			_finish_restore(true, null)
			return
		print("[Purchase (PurchaseManager)] restore_purchase() 跳过：内购未 init（回执直接报失败，别让 UI 干等）")

		var err := UniKitPurchaseError.local(
			UniKitPurchaseError.REASON_PURCHASING_UNAVAILABLE, "内购未初始化"
		)
		restore_result.emit(false, err)
		return
	print("[Purchase (PurchaseManager)] restore_purchase()（玩家主动）→ 查商店，等回执")
	UniKit.purchase_module.restore()

	var settled: Array = await _restore_settled
	_finish_restore(bool(settled[0]), settled[1])


func _finish_restore(success: bool, error: UniKitPurchaseError) -> void:
	if not success:
		_track_restore_purchase(Tracker.SubscriptionState.FAILED, "unknown", error_code_of(error))
		restore_result.emit(false, error)
		return
	if is_vip_active():
		_track_restore_purchase(
			Tracker.SubscriptionState.SUCCESS, PurchaseDefine.sub_type_of_tier(get_vip_tier())
		)
	else:
		_track_restore_purchase(Tracker.SubscriptionState.FAILED, "unknown", "unknown")
	restore_result.emit(true, null)


static func is_new_day(last_date: String, today: String) -> bool:
	return date_str_to_jdn(today) > date_str_to_jdn(last_date)


static func date_str_to_jdn(date_str: String) -> int:
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() < 3:
		return 0
	var year: int = parts[0].to_int()
	var month: int = parts[1].to_int()
	var day: int = parts[2].to_int()
	if year <= 0 or month <= 0 or day <= 0:
		return 0
	@warning_ignore("integer_division")
	var a: int = (14 - month) / 12
	var y: int = year + 4800 - a
	var m: int = month + 12 * a - 3

	@warning_ignore("integer_division")
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045


func _today_str() -> String:
	var dt: Dictionary = Time.get_date_dict_from_system()
	return "%d-%02d-%02d" % [dt.year, dt.month, dt.day]


func can_show_sub_inter_today() -> bool:
	return is_new_day(get_vip_sub_inter_last_show_date(), _today_str())


func can_claim_vip_daily_gift() -> bool:
	return (
		UniKitManager.is_online()
		and is_vip_active()
		and is_new_day(get_vip_daily_gift_last_claim_date(), _today_str())
	)


## 检查在线、VIP 和日期限制，交给 AwardManager 发奖；发奖请求被接受后才记下今日已领取。
func claim_vip_daily_gift() -> bool:
	if not can_claim_vip_daily_gift():
		print(
			(
				"[Purchase (PurchaseManager)] 每日赠送不可发：online=%s vip=%s last=%s today=%s by=%s"
				% [
					UniKitManager.is_online(),
					is_vip_active(),
					get_vip_daily_gift_last_claim_date(),
					_today_str(),
					_caller_chain()
				]
			)
		)
		return false

	var product_id: String = get_vip_plan_product_id()
	var n: int = PurchaseDefine.daily_gift_count(product_id)
	var uid: int = AwardManager.dispatch(
		[AwardItem.make(Tracker.Prop.HINT, n), AwardItem.make(Tracker.Prop.LOCATE, n)],
		AwardManager.DisplayType.DIRECT,
		Tracker.PropSource.VIP_DAILY_GIFT
	)
	if uid < 0:
		push_error("[Purchase (PurchaseManager)] VIP 每日赠送 dispatch 被拒，未标记已发，下个时机重试")
		_debug_toast("每日赠送失败：AwardManager 拒收")
		return false
	set_vip_daily_gift_last_claim_date(_today_str())
	print(
		(
			"[Purchase (PurchaseManager)] VIP 每日赠送已发放 (+%d hint / +%d locate) product_id=%s uid=%d"
			% [n, n, product_id if not product_id.is_empty() else "(未知,取下限)", uid]
		)
	)

	_debug_toast(
		(
			"每日赠送 +%d hint / +%d locate (%s)"
			% [
				n,
				n,
				(
					product_id.trim_prefix("com.oakever.meowdoku.")
					if not product_id.is_empty()
					else "SKU未知"
				)
			]
		)
	)
	return true


static func format_error(e: UniKitPurchaseError) -> String:
	if e == null:
		return ""
	return "%d:%s" % [e.code, e.message]


static func error_code_of(e: UniKitPurchaseError) -> String:
	if e == null:
		return ""
	return str(e.reason)


static func _caller_chain(depth: int = 2) -> String:
	var bts: Array[ScriptBacktrace] = Engine.capture_script_backtraces()
	if bts.is_empty():
		return "?"
	var bt: ScriptBacktrace = bts[0]
	var parts: PackedStringArray = []
	for i in range(1, mini(1 + depth, bt.get_frame_count())):
		parts.append(bt.get_frame_function(i))
	return " ← ".join(parts) if not parts.is_empty() else "?"


func _check_purchase_sdk() -> bool:
	var pm: UniKitPurchaseModule = UniKit.purchase_module
	if pm == null:
		push_error("[Purchase (PurchaseManager)] UniKit.purchase_module 为空,内购不可用")
		return false
	return pm.is_initialized()


func _on_purchase_init_success() -> void:
	print("[Purchase (PurchaseManager)] init 成功(商品表就绪) → 重载商品 + 静默刷订阅状态")
	_reload_products_from_app_store()
	update_subscription()


func _on_purchase_init_failed(error: UniKitPurchaseError) -> void:
	push_warning("[Purchase (PurchaseManager)] init 失败(本次会话内购不可用,不重试): %s" % format_error(error))


func _on_purchase_processing(product: UniKitPurchaseProduct) -> void:
	_purchasing = false

	var product_id: String = product.id
	var is_active: bool = product.transaction != null and product.transaction.is_active_purchase
	print(
		(
			"[Purchase (PurchaseManager)] purchase_processing product_id=%s is_active_purchase=%s"
			% [product_id, is_active]
		)
	)

	_recompute_vip()

	on_vip_purchased(product_id)

	lock_vip_price_ab(get_effective_vip_price_group())
	_track_purchase(Tracker.SubscriptionState.SUCCESS, product_id)
	purchase_result.emit(true, product_id, null, is_active)

	UniKit.purchase_module.complete_purchase(product_id, UniKitPurchaseModule.RESULT_COMPLETE)
	_debug_toast("购买成功: %s (主动=%s)" % [product_id, is_active])


func _on_purchase_failed(product_id: String, error: UniKitPurchaseError) -> void:
	_purchasing = false
	print(
		(
			"[Purchase (PurchaseManager)] purchase_failed product_id=%s error=%s reason=%d"
			% [product_id, format_error(error), error.reason if error != null else -1]
		)
	)

	var sub_state: String = (
		Tracker.SubscriptionState.CANCEL
		if error != null and error.reason == UniKitPurchaseError.REASON_USER_CANCELLED
		else Tracker.SubscriptionState.FAILED
	)
	_track_purchase(sub_state, product_id, error_code_of(error))

	purchase_result.emit(false, product_id, error, false)
	_debug_toast("购买失败: %s (%s)" % [product_id, format_error(error)])


## 接收商店订阅状态变化，重新计算本地权益并驱动购买结果及界面刷新。
func _on_subscription_updated() -> void:
	print("[Purchase (PurchaseManager)] subscription_updated（一次刷新落定 → 重查权益）")
	_recompute_vip()


func _on_restore_succeed() -> void:
	_purchasing = false
	print("[Purchase (PurchaseManager)] restore_succeed")

	_recompute_vip()

	if not is_vip_active():
		clear_vip_price_ab_lock()
	_restore_settled.emit(true, null)
	_debug_toast("恢复成功: VIP=%s" % is_vip_active())


func _on_restore_failed(error: UniKitPurchaseError) -> void:
	_purchasing = false
	print("[Purchase (PurchaseManager)] restore_failed error=%s" % format_error(error))

	_restore_settled.emit(false, error)
	_debug_toast("恢复失败: %s" % format_error(error))


func _get_track_sub_type(product_id: String) -> String:
	var pid: String = product_id if not product_id.is_empty() else _last_buy_product_id
	return PurchaseDefine.sub_type_of_tier(PurchaseDefine.tier_of_product_id(pid))


func _track_purchase(sub_state: String, product_id: String, error_code: String = "") -> void:
	Tracker.track_sub_pay(
		sub_state, UniKitManager.get_network_type(), _get_track_sub_type(product_id), error_code
	)


func _track_restore_purchase(
	sub_state: String, sub_type: String = "", error_code: String = ""
) -> void:
	Tracker.track_sub_resume(sub_state, UniKitManager.get_network_type(), sub_type, error_code)


func get_debug_fake_store_purchase() -> Dictionary:
	return _data.debug_fake_store_purchase


func set_debug_fake_store_purchase(product_id: String, tier: int) -> void:
	_data.debug_fake_store_purchase = {
		"product_id": product_id,
		"tier": tier,
	}
	_save()


## 仅供编辑器调试的购买成功模拟；写入本地假商店状态，不代表完成真实付款。
func debug_simulate_purchase_success(product_id: String) -> void:
	if not OS.has_feature("editor"):
		push_error("[Purchase (PurchaseManager)] debug_simulate_purchase_success 只允许在编辑器调用")
		return
	print("[Purchase (PurchaseManager)] 编辑器模拟购买成功 product_id=%s" % product_id)
	set_debug_fake_store_purchase(product_id, PurchaseDefine.tier_of_product_id(product_id))
	on_vip_purchased(product_id)
	lock_vip_price_ab(get_effective_vip_price_group())
	_track_purchase(Tracker.SubscriptionState.SUCCESS, product_id)

	purchase_result.emit(true, product_id, null, true)


## 把调试假商店记录恢复到本地订阅缓存，测试“恢复购买”界面流程。
func _debug_apply_fake_store_restore() -> void:
	var rec: Dictionary = get_debug_fake_store_purchase()
	if rec.is_empty():
		print("[Purchase (PurchaseManager)] 编辑器模拟恢复：模拟商店无记录（cheat vip_clear all 会清掉它）")
		return
	print("[Purchase (PurchaseManager)] 编辑器模拟恢复 product_id=%s" % str(rec.get("product_id", "")))
	on_vip_purchased(String(rec.get("product_id", "")))


func cheat_clear_vip_local(also_store: bool = false) -> void:
	var was_active: bool = _data.vip_active
	_data.vip_active = false
	_data.valid_sub_product_ids = []
	_data.vip_price_ab_lock = -1
	_data.vip_daily_gift_last_claim_date = ""
	if also_store:
		_data.debug_fake_store_purchase = {}
	_save()
	if was_active:
		vip_status_changed.emit(false)


func cheat_clear_vip_sub_inter_last_show_date() -> void:
	_data.vip_sub_inter_last_show_date = ""
	_save()


func _debug_toast(msg: String) -> void:
	return
