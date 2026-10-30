## 内购状态机：缓存商品与交易，区分主动购买、补单和恢复，并协调发货回执与原生结单。
class_name UniKitPurchaseModule
extends UniKitModuleBase

const RESULT_COMPLETE: int = 0
const RESULT_PENDING: int = 1
const RESULT_WAITING_FOR_VERIFICATION: int = 2

const _ERR_NOT_INITIALIZED: String = "[UniKit] 内购未初始化：UniKitInitParams.is_late_init_purchase 为 true（要用内购请置 false）"

signal purchase_initialized

signal purchase_init_failed(error: UniKitPurchaseError)

signal purchase_processing(product: UniKitPurchaseProduct)
signal purchase_failed(product_id: String, error: UniKitPurchaseError)

signal subscription_updated
signal restore_succeed
signal restore_failed(error: UniKitPurchaseError)

var _is_initialized: bool = false

var _products: Dictionary = {}

var _owned: Dictionary = {}

var _pending: Dictionary = {}

var _processed_tokens: Dictionary = {}

var _pending_restore_count: int = 0

var _finish_retry: Dictionary = {}

var _inactive_pids: Dictionary = {}

var _in_flight: Dictionary = {}

var _expiration_by_pid: Dictionary = {}

var _bridge: UniKitPurchaseNativeBridge = null

var _is_purchase_custom_verify: bool = false
var _is_auto_finish_transaction_enabled: bool = true


## 接入统一原生支付桥，业务状态机不直接区分两个平台的方法名。
func _set_native_bridge(bridge: UniKitPurchaseNativeBridge) -> void:
	_bridge = bridge


## 保存校验与结单策略，并根据配置的三类商品建立占位目录。
func _snapshot_init_params(params: UniKitInitParams) -> void:
	_is_purchase_custom_verify = params.is_purchase_custom_verify
	_is_auto_finish_transaction_enabled = params.is_auto_finish_transaction_enabled
	_products.clear()

	for pid in params.consumable_product_ids:
		_products[pid] = UniKitPurchaseProduct.placeholder(
			pid, UniKitPurchaseProduct.TYPE_CONSUMABLE
		)
	for pid in params.entitled_product_ids:
		_products[pid] = UniKitPurchaseProduct.placeholder(pid, UniKitPurchaseProduct.TYPE_ENTITLED)
	for pid in params.subscription_product_ids:
		_products[pid] = UniKitPurchaseProduct.placeholder(
			pid, UniKitPurchaseProduct.TYPE_SUBSCRIPTION
		)
	print("[UniKit] 内购参数快照：%d 个商品，自定义校验=%s" % [_products.size(), _is_custom_verify()])


## 按平台解释自定义校验策略，iOS 以是否自动结束交易为依据。
func _is_custom_verify() -> bool:
	if _is_ios_platform():
		return not _is_auto_finish_transaction_enabled
	return _is_purchase_custom_verify


## 判断是否由脚本流程显式通知原生结束订单。
func _should_finish_ourselves() -> bool:
	return _is_ios_platform() or _is_custom_verify()


## 阻止初始化完成前访问内购状态，并记录调用入口。
func _require_initialized(caller: String) -> bool:
	if _is_initialized:
		return true
	push_error("%s ← %s()" % [_ERR_NOT_INITIALIZED, caller])
	return false


## 读取 Unix 毫秒时间，用于比较订阅到期时间。
func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## 合并商店商品元数据并发送初始化完成，随后静默刷新历史权益。
func _on_init_succeed(products_json: String) -> void:
	_is_initialized = true
	var arr: Variant = JSON.parse_string(products_json)
	if arr is Array:
		for e: Variant in arr:
			if e is Dictionary:
				_convert_product_metadata(UniKitPurchaseProduct.from_dict(e))
	else:
		push_warning("[UniKit] 内购商品表 JSON 解析失败：%s" % products_json)
	print(
		(
			"[UniKit] 内购初始化成功：商品表 %d 项（其中 %d 项已拿到元数据）"
			% [_products.size(), get_available_products().size()]
		)
	)
	purchase_initialized.emit()

	_query_all_purchases_async(true)


## 更新商店元数据，同时保留本地商品分类和已有交易关联。
func _convert_product_metadata(p: UniKitPurchaseProduct) -> void:
	if p.id.is_empty():
		return
	var old: UniKitPurchaseProduct = _products.get(p.id)
	if old != null:
		if old.type != UniKitPurchaseProduct.TYPE_UNKNOWN:
			p.type = old.type
		p.transaction = old.transaction
	else:
		push_warning("[UniKit] 商品 %s 不在 UniKitInitParams 的三个 ID 列表里，类型未知" % p.id)
	_products[p.id] = p


## 解析初始化失败原因并发送失败信号。
func _on_init_failed(error_json: String) -> void:
	var e := UniKitPurchaseError.from_json(error_json)
	push_warning("[UniKit] 内购初始化失败：code=%d msg=%s" % [e.code, e.message])
	purchase_init_failed.emit(e)


## 查询是否已收到原生内购初始化成功回执。
func is_initialized() -> bool:
	return _is_initialized


## 从已初始化的商品目录取得单个商品；未知商品返回空。
func get_product(product_id: String) -> UniKitPurchaseProduct:
	if not _require_initialized("get_product"):
		return null
	return _products.get(product_id)


## 返回配置目录中的全部商品，包括尚未取得商店元数据的占位项。
func get_products() -> Array[UniKitPurchaseProduct]:
	var out: Array[UniKitPurchaseProduct] = []
	if not _require_initialized("get_products"):
		return out
	for pid: Variant in _products:
		out.append(_products[pid])
	return out


## 筛选已经取得商店元数据的商品，供购买界面展示。
func get_available_products() -> Array[UniKitPurchaseProduct]:
	var out: Array[UniKitPurchaseProduct] = []
	if not _require_initialized("get_available_products"):
		return out
	for pid: Variant in _products:
		var p: UniKitPurchaseProduct = _products[pid]
		if p.is_available():
			out.append(p)
	return out


## 按商品类型判断权益；消耗品不作为持久已购权益，订阅还需检查到期与撤销。
func is_purchased(product_id: String) -> bool:
	if not _require_initialized("is_purchased"):
		return false
	var p: UniKitPurchaseProduct = _products.get(product_id)
	if p == null:
		return false
	match p.type:
		UniKitPurchaseProduct.TYPE_CONSUMABLE:
			return false
		UniKitPurchaseProduct.TYPE_SUBSCRIPTION:
			return _is_subscription_active(product_id)
		UniKitPurchaseProduct.TYPE_ENTITLED:
			var t: UniKitPurchaseTransaction = _owned.get(product_id)

			return t != null and t.revocation_time_ms <= 0 and not _inactive_pids.has(product_id)
	return false


## 复用商品权益判断，保持业务查询入口兼容。
func is_valid_subscription(product_id: String) -> bool:
	return is_purchased(product_id)


## 综合撤销、对账失效标记和毫秒到期时间判断交易是否仍有效。
func _is_transaction_active(t: UniKitPurchaseTransaction) -> bool:
	if t == null:
		return false

	if _inactive_pids.has(t.product_id):
		return false
	if t.revocation_time_ms > 0:
		return false
	if t.expiration_time_ms <= 0:
		return true
	return t.expiration_time_ms > _now_ms()


## 检查指定商品最近记录的交易是否有效。
func _is_subscription_active(product_id: String) -> bool:
	return _is_transaction_active(_owned.get(product_id))


## iOS 向原生查询购买许可，其他平台保持默认可请求状态。
func is_authorized_for_payments() -> bool:
	if not OS.has_feature("ios"):
		return true
	if _bridge == null:
		return false
	return _bridge.query_authorized_for_payments()


## 遍历已购目录，判断是否至少存在一个有效订阅。
func is_any_subscription_active() -> bool:
	if not _require_initialized("is_any_subscription_active"):
		return false
	for pid: Variant in _owned:
		var p: UniKitPurchaseProduct = _products.get(pid)
		if (
			p != null
			and p.type == UniKitPurchaseProduct.TYPE_SUBSCRIPTION
			and _is_transaction_active(_owned[pid])
		):
			return true
	return false


## 校验商品与待处理订单后记录进行中的购买，再交给原生桥发起支付。
func purchase(params: UniKitPurchaseParams) -> void:
	if params == null:
		push_error("[UniKit] purchase(null)：UniKitPurchaseParams 为空")
		return
	if params.product_id.is_empty():
		push_error("[UniKit] purchase：product_id 为空")
		return
	if not _require_initialized("purchase"):
		return

	if _pending.has(params.product_id):
		purchase_failed.emit(
			params.product_id,
			UniKitPurchaseError.local(
				UniKitPurchaseError.REASON_EXISTING_PURCHASE_PENDING,
				"商品 %s 有未完成的 pending 订单，请先调 check_pending_purchases()" % params.product_id
			)
		)
		return
	if _bridge == null:
		return
	print("[UniKit] 发起内购：%s" % params.product_id)
	_in_flight[params.product_id] = true
	_bridge.send_purchase(params)


## 仅对本次尚未完成的购买发布失败，避免重复响应同一次操作。
func _fail_in_flight(product_id: String, reason: int, message: String) -> bool:
	if not _in_flight.erase(product_id):
		return false
	push_warning("[UniKit] 本次购买未产生可交付的订单：%s —— %s" % [product_id, message])
	purchase_failed.emit(product_id, UniKitPurchaseError.local(reason, message))
	return true


## 接收业务发货回执，分别处理完成、待处理和等待服务器校验。
func complete_purchase(product_id: String, result: int) -> void:
	if not _require_initialized("complete_purchase"):
		return
	var t: UniKitPurchaseTransaction = _owned.get(product_id)
	match result:
		RESULT_COMPLETE:
			print("[UniKit] 业务回执完成：%s token=%s" % [product_id, t.token if t != null else "无交易"])
			_erase_pending(product_id, t.token if t != null else "")

			if _should_finish_ourselves():
				_finish_order_native(product_id, t)
		RESULT_PENDING:
			if t == null:
				push_warning(
					"[UniKit] complete_purchase(PENDING)：找不到 %s 的交易，未写入 pending" % product_id
				)
				return
			_put_pending(t)
			print("[UniKit] 订单转入 pending：%s" % product_id)
		RESULT_WAITING_FOR_VERIFICATION:
			print("[UniKit] 订单等待服务器校验：%s" % product_id)
		_:
			push_error(
				(
					"[UniKit] complete_purchase：未知 result=%d（应为 RESULT_COMPLETE / RESULT_PENDING / RESULT_WAITING_FOR_VERIFICATION）"
					% result
				)
			)


## 根据业务校验结果结单；校验未通过时保留交易供后续处理。
func finish_order(product_id: String, verify_success: bool) -> void:
	if not _require_initialized("finish_order"):
		return
	if not _should_finish_ourselves():
		return
	if not verify_success:
		_put_pending(_owned.get(product_id))
		print("[UniKit] 服务器校验未通过，订单留在 pending：%s" % product_id)
		return
	_finish_order_native(product_id, _owned.get(product_id))


## 向原生发送结单请求，并清理本次交易匹配的待处理状态。
func _finish_order_native(product_id: String, t: UniKitPurchaseTransaction) -> void:
	if t == null:
		push_error("[UniKit] 结束订单失败：找不到 %s 的交易记录" % product_id)
		return
	if _bridge == null:
		return
	_bridge.send_finish_order(product_id, t.token)

	_erase_finish_retry(product_id, t.token)
	_erase_pending(product_id, t.token)


## 按商品保存未完成交易，拒绝用不同令牌的新订单覆盖旧订单。
func _put_pending(t: UniKitPurchaseTransaction) -> void:
	if t == null or t.product_id.is_empty():
		return
	var old: UniKitPurchaseTransaction = _pending.get(t.product_id)
	if old != null and not old.token.is_empty() and not t.token.is_empty() and old.token != t.token:
		push_error(
			(
				"[UniKit] 商品 %s 同时存在两笔不同的 pending 订单（保留旧的 token=%s，忽略新的 token=%s）—— 请先 check_pending_purchases() 处理完再发起新购买"
				% [t.product_id, old.token, t.token]
			)
		)
		return
	_pending[t.product_id] = t


## 只删除令牌相符的待处理交易，避免误删同商品另一笔订单。
func _erase_pending(product_id: String, token: String = "") -> void:
	var old: UniKitPurchaseTransaction = _pending.get(product_id)
	if old == null:
		return
	if not token.is_empty() and not old.token.is_empty() and old.token != token:
		push_warning(
			(
				"[UniKit] 不移除 %s 的 pending：token 不匹配（缓存 %s / 本次 %s）—— 那是另一笔订单"
				% [product_id, old.token, token]
			)
		)
		return
	_pending.erase(product_id)


## 只清除与本次令牌相符的结单重试项。
func _erase_finish_retry(product_id: String, token: String = "") -> void:
	if not _finish_retry.has(product_id):
		return
	var kept: String = str(_finish_retry[product_id])
	if not token.is_empty() and not kept.is_empty() and kept != token:
		push_warning("[UniKit] 不移除 %s 的待重试结单：token 不匹配（缓存 %s / 本次 %s）" % [product_id, kept, token])
		return
	_finish_retry.erase(product_id)


## 重放待处理交易并重试结单，重试前核对当前订单令牌。
func check_pending_purchases() -> void:
	if not _require_initialized("check_pending_purchases"):
		return

	if not _pending.is_empty():
		print("[UniKit] 重放 %d 笔 pending 订单" % _pending.size())
		for product_id: Variant in _pending.keys():
			_process_purchase(_pending[product_id], true)
	if not _finish_retry.is_empty():
		print("[UniKit] 重试结单 %d 笔" % _finish_retry.size())
		for product_id: Variant in _finish_retry.keys():
			var t: UniKitPurchaseTransaction = _owned.get(product_id)

			if t == null:
				_finish_retry.erase(product_id)
				continue

			if t.token != str(_finish_retry[product_id]):
				push_warning(
					(
						"[UniKit] 跳过 %s 的重试结单：已购表里已是另一笔订单（待重试 %s / 当前 %s）"
						% [product_id, str(_finish_retry[product_id]), t.token]
					)
				)
				_finish_retry.erase(product_id)
				continue
			_finish_order_native(product_id, t)


## 按交易令牌防重复发货，把可交付商品发布给 purchase_processing 订阅者。
func _process_purchase(
	t: UniKitPurchaseTransaction, force: bool = false, may_answer_purchase: bool = true
) -> void:
	if t == null or t.product_id.is_empty():
		return

	if not force and not t.token.is_empty() and _processed_tokens.has(t.token):
		print("[UniKit] 交易 token=%s 本次运行已发货，跳过（防重复发货）" % t.token)

		if may_answer_purchase:
			_fail_in_flight(
				t.product_id,
				UniKitPurchaseError.REASON_DUPLICATE_TRANSACTION,
				"交易 %s 本次运行已发货过，本次购买未产生新订单（多为上一笔未结单被短路）" % t.token
			)
		return
	if not t.token.is_empty():
		_processed_tokens[t.token] = true
	var p: UniKitPurchaseProduct = _products.get(t.product_id)
	if p == null:
		push_warning(
			"[UniKit] 交易商品 %s 不在 UniKitInitParams 的三个 ID 列表里，按权益型兜底发货（避免误消耗）；请补全配置" % t.product_id
		)
		p = UniKitPurchaseProduct.placeholder(t.product_id, UniKitPurchaseProduct.TYPE_ENTITLED)
		_products[t.product_id] = p
	p.transaction = t

	if may_answer_purchase:
		_in_flight.erase(t.product_id)
	purchase_processing.emit(p)


## 保存本次主动购买的交易，恢复商品有效状态并进入发货流程。
func _on_process_purchase_succeed(product_id: String, purchase_json: String) -> void:
	var t := UniKitPurchaseTransaction.from_json(purchase_json)
	if t.product_id.is_empty():
		t.product_id = product_id
	t.is_active_purchase = true
	_owned[t.product_id] = t

	_inactive_pids.erase(t.product_id)

	print(
		(
			"[UniKit] 购买成功：%s token=%s order=%s purchase=%d exp=%d rev=%d now=%d"
			% [
				t.product_id,
				t.token,
				t.order_id,
				t.purchase_time_ms,
				t.expiration_time_ms,
				t.revocation_time_ms,
				_now_ms()
			]
		)
	)
	_process_purchase(t)


## 清除进行中的购买标记，向业务发布原生支付失败。
func _on_process_purchase_failed(product_id: String, error_json: String) -> void:
	var e := UniKitPurchaseError.from_json(error_json)
	push_warning("[UniKit] 购买失败：%s code=%d msg=%s" % [product_id, e.code, e.message])
	_in_flight.erase(product_id)
	purchase_failed.emit(product_id, e)


## 清除待处理和重试状态；消耗品结单后移出已购表。
func _on_finish_order_succeed(product_id: String, token: String) -> void:
	_erase_pending(product_id, token)
	_erase_finish_retry(product_id, token)
	var p: UniKitPurchaseProduct = _products.get(product_id)

	if p != null and p.type == UniKitPurchaseProduct.TYPE_CONSUMABLE:
		_owned.erase(product_id)
	print("[UniKit] 结束订单成功：%s token=%s" % [product_id, token])


## 保存当前交易令牌供后续重试结单，不重复发货。
func _on_finish_order_failed(product_id: String, error_json: String) -> void:
	var e := UniKitPurchaseError.from_json(error_json)

	var t: UniKitPurchaseTransaction = _owned.get(product_id)
	if t != null:
		_finish_retry[product_id] = t.token
	push_warning("[UniKit] 结束订单失败：%s code=%d msg=%s（已排入重试结单）" % [product_id, e.code, e.message])


## 只使用可解析的验票清单更新到期和撤销状态，再通知订阅变化。
func _on_subscription_update(receipts_json: String) -> void:
	var arr: Variant = JSON.parse_string(receipts_json)
	if not (arr is Array):
		push_warning("[UniKit] 验票未拿到权威结果（本次不对账）：%s" % receipts_json)
		return
	var n: int = 0
	var present: Dictionary = {}
	for e: Variant in arr:
		if not (e is Dictionary):
			continue
		var r: Dictionary = e
		var pid: String = str(r.get("productId", ""))
		if pid.is_empty():
			continue
		var exp_ms: int = int(r.get("expirationTime", 0))
		present[pid] = true

		var changed: bool = _inactive_pids.erase(pid)

		_expiration_by_pid[pid] = exp_ms
		var t: UniKitPurchaseTransaction = _owned.get(pid)
		if t != null:
			if exp_ms > 0 and t.expiration_time_ms != exp_ms:
				t.expiration_time_ms = exp_ms
				changed = true
			if changed:
				n += 1
			continue

		t = UniKitPurchaseTransaction.from_dict(r)
		t.is_active_purchase = false
		_owned[pid] = t
		var p: UniKitPurchaseProduct = _products.get(pid)

		if p != null and p.transaction == null:
			p.transaction = t

		n += 1

	var revoked: int = _reconcile(present, _expiration_by_pid.keys(), "验票")

	if n > 0 or revoked > 0:
		print("[UniKit] 验票结果变更了 %d 笔订阅 / 权益状态（撤销 %d 笔）" % [n, revoked])
	subscription_updated.emit()


## 把权威结果中已不存在的候选商品标记为失效，返回本次新增失效数量。
func _reconcile(present: Dictionary, candidates: Array, source: String) -> int:
	var revoked: int = 0
	for pid: Variant in candidates:
		if present.has(pid) or _inactive_pids.has(pid):
			continue
		_inactive_pids[str(pid)] = true
		revoked += 1
		print("[UniKit] 权益已失效（%s结果里不再有它，多为订阅过期 / 退款 / 取消）：%s" % [source, pid])
	return revoked


## 发起用户可感知的恢复购买流程，结果会发送恢复成功或失败信号。
func restore() -> void:
	if not _require_initialized("restore"):
		return
	if _bridge == null:
		return
	print("[UniKit] 恢复购买：查询已购商品")
	_query_all_purchases_async(false)


## 静默刷新当前权益，区别于用户主动点击恢复购买。
func update_subscription() -> void:
	if not _require_initialized("update_subscription"):
		return
	if _bridge == null:
		return
	print("[UniKit] 静默刷新权益态：查询已购商品")
	_query_all_purchases_async(true)


## 区分静默刷新和主动恢复，记录后者尚未返回的请求数量。
func _query_all_purchases_async(silent: bool) -> void:
	if _bridge == null:
		return
	if silent:
		_bridge.send_update_subscription()
		return

	if _pending_restore_count > 0:
		print(
			(
				"[UniKit] 上一次 restore() 的回执还没回来（待回执 %d 次）——通常是玩家连点，若长期不归零则说明原生未回查询结果"
				% _pending_restore_count
			)
		)
	_pending_restore_count += 1
	_bridge.send_restore()


## 处理补单与历史交易；被动订阅只更新权益，命中当前购买时按主动结果交付。
func _process_purchase_succeed_passive(
	t: UniKitPurchaseTransaction, notify: bool = true, from_buy_channel: bool = false
) -> void:
	if t == null or t.product_id.is_empty():
		return
	t.is_active_purchase = false

	if t.expiration_time_ms <= 0 and _expiration_by_pid.has(t.product_id):
		t.expiration_time_ms = int(_expiration_by_pid[t.product_id])
	_owned[t.product_id] = t

	_inactive_pids.erase(t.product_id)

	if from_buy_channel and _in_flight.has(t.product_id):
		print("[UniKit] 被动到达命中在飞的购买，按本次购买的结果交付：%s token=%s" % [t.product_id, t.token])

		t.is_active_purchase = true
		_process_purchase(t)
		return
	var p: UniKitPurchaseProduct = _products.get(t.product_id)

	var ptype: int = p.type if p != null else UniKitPurchaseProduct.TYPE_ENTITLED
	if ptype == UniKitPurchaseProduct.TYPE_SUBSCRIPTION:
		print(
			(
				"[UniKit] 被动到达的订阅交易，按 D7 不发货：%s token=%s exp=%d"
				% [t.product_id, t.token, t.expiration_time_ms]
			)
		)
		if p != null:
			p.transaction = t

		if _should_finish_ourselves():
			_finish_order_native(t.product_id, t)
		if notify:
			subscription_updated.emit()
		return
	_process_purchase(t, false, from_buy_channel)
	if notify and ptype == UniKitPurchaseProduct.TYPE_ENTITLED:
		subscription_updated.emit()


## 把原生补单回执转换为交易，再进入被动交易处理流程。
func _on_purchase_restored(purchase_json: String) -> void:
	_process_purchase_succeed_passive(
		UniKitPurchaseTransaction.from_json(purchase_json), true, true
	)


## 合并已购查询结果并对账，只有主动恢复请求才发恢复完成信号。
func _on_query_all_purchases(purchases_json: String) -> void:
	var arr: Variant = JSON.parse_string(purchases_json)

	var was_silent: bool = _pending_restore_count <= 0
	if not was_silent:
		_pending_restore_count -= 1
	if not (arr is Array):
		push_warning("[UniKit] 已购列表未拿到权威结果（本次不对账）：%s" % purchases_json)
		if not was_silent:
			restore_failed.emit(
				UniKitPurchaseError.local(UniKitPurchaseError.REASON_UNKNOWN, "拉取已购列表失败，未拿到权威结果")
			)
		return
	var n: int = 0
	var present: Dictionary = {}
	for e: Variant in arr:
		if e is Dictionary:
			var t := UniKitPurchaseTransaction.from_dict(e)
			if not t.product_id.is_empty():
				present[t.product_id] = true
			_process_purchase_succeed_passive(t, false)
			n += 1
	print("[UniKit] 查询已购完成：%d 笔（%s）" % [n, "静默刷新" if was_silent else "业务 restore"])
	_reconcile_query_result(present)

	if not _is_ios_platform():
		subscription_updated.emit()
	if not was_silent:
		restore_succeed.emit()


## 按平台查询覆盖范围选择可撤销候选，避免用不完整清单撤销订阅。
func _reconcile_query_result(present: Dictionary) -> void:
	var covers_sub: bool = _query_result_covers_subscription()
	var candidates: Array = []
	for pid: Variant in _owned:
		var p: UniKitPurchaseProduct = _products.get(pid)
		if p == null:
			continue
		if (
			p.type == UniKitPurchaseProduct.TYPE_ENTITLED
			or (p.type == UniKitPurchaseProduct.TYPE_SUBSCRIPTION and covers_sub)
		):
			candidates.append(pid)

	_reconcile(present, candidates, "查询")


## Android 查询可覆盖订阅；iOS 订阅另由验票结果确认。
func _query_result_covers_subscription() -> bool:
	return not _is_ios_platform()


## 从已接入的原生桥判断支付平台。
func _is_ios_platform() -> bool:
	return _bridge != null and _bridge._is_ios()


## Android 无历史记录按空清单成功处理，其他失败保留原权益并报告。
func _on_query_all_purchases_failed(error_json: String) -> void:
	var e := UniKitPurchaseError.from_json(error_json)
	var was_silent: bool = _pending_restore_count <= 0
	if not was_silent:
		_pending_restore_count -= 1

	if not _is_ios_platform() and e.code == UniKitPurchaseError.ANDROID_PURCHASE_LIST_EMPTY:
		print("[UniKit] 无历史购买记录（errorCode=100），按查询成功处理")

		_reconcile_query_result({})

		subscription_updated.emit()
		if not was_silent:
			restore_succeed.emit()
		return

	if was_silent:
		push_warning("[UniKit] 静默刷新权益态失败（本次不对账，权益保持原样）：code=%d msg=%s" % [e.code, e.message])
		return
	push_warning("[UniKit] 恢复购买失败：code=%d reason=%d msg=%s" % [e.code, e.reason, e.message])
	restore_failed.emit(e)
