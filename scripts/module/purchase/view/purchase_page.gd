## 订阅购买页；结合实验分组与已持有套餐构建卡片，并协调商品加载、购买、恢复及成功提示。
## 展示价格优先来自商店；编辑器缺少商店数据时才使用本地回退价格。

extends UIFrameWindow

const CELL_SCENE: PackedScene = preload(
	"res://scripts/module/purchase/ui/purchase_package_cell.tscn"
)

const _SLOT_Y := [0.0, 345.0, 690.0]

const CELL_H := 307.0
const SCROLL_SEP := 38.0

const SCROLL_MARGIN := 48.0

const LINK_FONT_SIZE := 40

const RESTORE_FONT_SIZE := 70

const SCROLL_VIEWPORT_MIN := 850.0
const SCROLL_VIEWPORT_MAX := 992.0
const _VIEW_H_MIN := 1920.0
const _VIEW_H_MAX := 2400.0

const _PRICE_PLACEHOLDER: String = "--"

const _RESTORE_LOADING_DELAY: float = 0.5

const _ENTRY_CELL_DELAY := 0.03
const _ENTRY_CELL_STAGGER := 0.05
const _LOOP_START_DELAY := 3.5
const _LOOP_INTERVAL := 2.0

const ANIM_APPEAR := &"Appear"

@onready var _plan_group: Control = $MainVBox/PlanGroup
@onready var _container: Control = $MainVBox/PlanGroup/CellContainer
@onready var _locate_txt: Label = $"MainVBox/BenefitList/1Locate1dayTxt"
@onready var _hint_txt: Label = $"MainVBox/BenefitList/1Hint1dayTxt"
@onready
var _compliance_scroll: ScrollContainer = $MainVBox/Compliance/ComplianceMask/ComplianceScroll

@onready
var _manage_guide_txt: Label = $"MainVBox/Compliance/ComplianceMask/ComplianceScroll/ComplianceMargin/ComplianceVBox/ThePaymentWillBeDeductedViaYourAppleIDGoogleAccountUponPurchaseConfirmationTxt"
@onready
var _compliance_txt: Label = $"MainVBox/Compliance/ComplianceMask/ComplianceScroll/ComplianceMargin/ComplianceVBox/SubscriptionAutoRenewsUnlessTurnedOffAtLeast24HoursBeforeTheCurrentPeriodEndsTxt"

@onready var _offline_hint: Control = $MainVBox/OfflineHint

@onready var _scroll_container: ScrollContainer = $MainVBox/PlanGroup/ScrollCellContainer
@onready var _scroll_vbox: VBoxContainer = $MainVBox/PlanGroup/ScrollCellContainer/CellMargin/VBox
@onready var _terms_btn: UnderlineLink = $MainVBox/ServiceAndPrivacy/TermsBtn
@onready var _privacy_btn: UnderlineLink = $MainVBox/ServiceAndPrivacy/PrivacyBtn
@onready var _header: BackAndSettingHeader = $MainVBox/Header

@onready var _restore_btn: Button = $MainVBox/RestoreGroup/RestoreBtn

@onready var _anim: AnimationPlayer = $AnimationPlayer

var _cells: Array = []

var _scroll_layout: bool = false

var _plan_cfg: Dictionary = {}

var _has_real_price: bool = true

var _money_fmt: Dictionary = {}

var _buying_product_id: String = ""

var _restoring: bool = false

var _restore_loading_timer: Timer = null

var _restore_loading_shown: bool = false

var _buy_loading_shown: bool = false

var _benefit_x2: bool = false

var _from_interstitial: bool = false

var _purchase_attempted: bool = false

var _entry_played: bool = false

var _entry_timers: Array[Timer] = []

var _entry_seq: int = 0

signal interstitial_slot_dismissed(should_play_interstitial: bool)


func on_create() -> void:
	if _scroll_container != null:
		_scroll_container.get_v_scroll_bar().value_changed.connect(_on_scroll_v_changed)

		ScrollDragHelper.attach(_scroll_container, true).elastic_max_overscroll = 0.0

	if _compliance_scroll != null:
		ScrollDragHelper.attach(_compliance_scroll, true).elastic_max_overscroll = 0.0

	if _terms_btn != null:
		_terms_btn.set_font_size_cap(LINK_FONT_SIZE)
	if _privacy_btn != null:
		_privacy_btn.set_font_size_cap(LINK_FONT_SIZE)

	if _restore_btn != null:
		var restore_lbl: AutoFitLabel = _restore_btn.get_node_or_null("Root/Text") as AutoFitLabel
		if restore_lbl != null:
			restore_lbl.max_font_size = RESTORE_FONT_SIZE

	if _header != null:
		_header.register_back_btn(_on_back_pressed)

	get_viewport().size_changed.connect(_apply_scroll_viewport)

	PurchaseManager.purchase_result.connect(_on_purchase_result)
	PurchaseManager.restore_result.connect(_on_restore_result)

	PurchaseManager.products_ready.connect(_on_products_ready)

	PurchaseManager.vip_refreshed.connect(_on_vip_refreshed)


func on_show(params: Dictionary = {}) -> void:
	_buying_product_id = ""
	_restoring = false

	_from_interstitial = bool(params.get("from_interstitial", false))
	_purchase_attempted = false
	print(
		(
			"[Purchase (PurchasePage)] on_show from_interstitial=%s vip=%s products=%d"
			% [
				_from_interstitial,
				PurchaseManager.is_vip_active(),
				PurchaseManager.get_products().size()
			]
		)
	)

	_entry_played = false
	_stop_entry_anim()
	_rebuild()

	Tracker.track_sub_page_view(
		(
			Tracker.SubscriptionSource.INTERSTITIAL_AD_SLOT
			if _from_interstitial
			else Tracker.SubscriptionSource.SETTINGS_GET_PREMIUM
		),
		(
			Tracker.SubscriptionUserState.SUBSCRIBED
			if PurchaseManager.is_vip_active()
			else Tracker.SubscriptionUserState.UNSUBSCRIBED
		)
	)


func on_hide() -> void:
	_stop_entry_anim()
	_clear_cells()

	_cancel_restore_loading()
	_cancel_buy_loading()

	if _from_interstitial:
		var should_play: bool = not _purchase_attempted and not PurchaseManager.is_vip_active()

		print(
			(
				"[Purchase (PurchasePage)] 插屏位模式关闭 attempted=%s vip=%s replay_interstitial=%s"
				% [_purchase_attempted, PurchaseManager.is_vip_active(), should_play]
			)
		)

		_from_interstitial = false
		interstitial_slot_dismissed.emit(should_play)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()


func _refresh_dynamic_text() -> void:
	_apply_benefit_count(2 if _benefit_x2 else 1)
	_apply_compliance_text()

	var plans: Array = _plan_cfg.get("plans", [])
	for idx in mini(_cells.size(), plans.size()):
		var c = _cells[idx]
		if not is_instance_valid(c):
			continue
		var plan: Dictionary = plans[idx]
		var product_id: String = String(plan["product_id"])
		var amount: float = _real_amount(product_id)
		var days: int = maxi(int(plan["nominal_days"]), 1)

		var day_price: String = (
			_money_text(amount / float(days)) if amount > 0.0 else _PRICE_PLACEHOLDER
		)
		c.set_day_price(_day_price_text(day_price))


func _resolve_plan_config() -> Dictionary:
	var group: int = PurchaseManager.get_effective_vip_price_group()
	var cfg: Dictionary = _make_plan_cfg(group, _owned_force_base())

	if PurchaseManager.is_vip_active() and not PurchaseManager.has_vip_price_ab_lock():
		cfg["show_original"] = false
	return cfg


func _owned_force_base() -> int:
	if not PurchaseManager.is_vip_active():
		return -1
	var owned_pid: String = PurchaseManager.get_vip_plan_product_id()
	if owned_pid.is_empty():
		return -1
	return 1 if PurchaseDefine.is_base_product_id(owned_pid) else 0


func _make_plan_cfg(group: int, force_base: int = -1) -> Dictionary:
	var ids: Array = PurchaseManager.get_sub_product_ids_cfg()
	var scroll: bool = VipPriceConfig.uses_scroll_layout_for(group)
	var plans: Array = []
	if scroll:
		plans.append_array(_make_plans(ids, true))
		plans.append_array(_make_plans(ids, false))
	else:
		var is_base: bool = VipPriceConfig.uses_low_price_for(group)
		if force_base >= 0:
			is_base = force_base == 1
		plans = _make_plans(ids, is_base)
	return {
		"group": group,
		"scroll": scroll,
		"show_original": VipPriceConfig.show_original_price_for(group),
		"plans": plans,
	}


## 将价格实验、平台商品及已拥有套餐组合成页面展示计划，不在卡片组件内分散判断。
func _make_plans(ids: Array, is_base: bool) -> Array:
	var out: Array = []

	var offset: int = PurchaseDefine.TIER_COUNT if is_base else 0
	for t in PurchaseDefine.TIER_COUNT:
		var idx: int = offset + t
		if idx >= ids.size():
			push_error(
				(
					"[Purchase (PurchasePage)] 商品 id 列表不足（需 %d 个，实际 %d），档位 %d 无 product_id"
					% [PurchaseDefine.TIER_COUNT * 2, ids.size(), t]
				)
			)
		(
			out
			. append(
				{
					"product_id": String(ids[idx]) if idx < ids.size() else "",
					"tier": t,
					"nominal_days": int(PurchaseDefine.TIER_NOMINAL_DAYS[t]),
					"origin_price_multi": PurchaseDefine.origin_price_multi(is_base, t),
					"benefit": PurchaseDefine.daily_gift_count_by_edition(is_base),
				}
			)
		)
	return out


func _real_price(product_id: String) -> String:
	var p = _find_product(product_id)
	if p != null and not String(p.display_price).is_empty():
		return String(p.display_price)
	var fb: String = _editor_fallback_price(product_id)
	return fb if not fb.is_empty() else _PRICE_PLACEHOLDER


func _find_product(product_id: String):
	return PurchaseManager.get_products().get(product_id, null)


func _real_amount(product_id: String) -> float:
	var products: Dictionary = PurchaseManager.get_products()
	var p = products.get(product_id, null)
	if p != null:
		return float(p.price)

	return _amount_of(_editor_fallback_price(product_id))


func _amount_of(price: String) -> float:
	var re: RegEx = RegEx.create_from_string("[0-9]+(?:[.,][0-9]+)?")
	var m: RegExMatch = re.search(price)
	return float(m.get_string().replace(",", ".")) if m != null else 0.0


func _editor_fallback_price(product_id: String) -> String:
	if not OS.has_feature("editor") or product_id.is_empty():
		return ""

	var t: int = PurchaseDefine.tier_of_product_id(product_id)
	if t < 0:
		return ""
	var table: Array = (
		PurchaseDefine.EDITOR_PRICE_BASE
		if PurchaseDefine.is_base_product_id(product_id)
		else PurchaseDefine.EDITOR_PRICE_PRO
	)
	return String(table[t]) if t < table.size() else ""


func _money_text(amount: float) -> String:
	if not bool(_money_fmt.get("ok", false)):
		return _PRICE_PLACEHOLDER
	return MoneyFormat.render(amount, _money_fmt)


func _resolve_money_fmt() -> Dictionary:
	var plans: Array = _plan_cfg.get("plans", [])
	var samples: Array = []
	for plan: Dictionary in plans:
		var product_id: String = String(plan["product_id"])
		samples.append([_real_price(product_id), _real_amount(product_id)])
	return MoneyFormat.parse_many(samples)


## 从商店商品提取价格并计算展示用折算值；缺失真实价格时按现有回退规则处理。
func _apply_plan_prices(cell, plan: Dictionary) -> void:
	var product_id: String = String(plan["product_id"])
	var price: String = _real_price(product_id)
	var days: int = maxi(int(plan["nominal_days"]), 1)
	var amount: float = _real_amount(product_id)

	var day_price: String = (
		_money_text(amount / float(days)) if amount > 0.0 else _PRICE_PLACEHOLDER
	)

	var multi: float = float(plan["origin_price_multi"])
	var pct: int = PurchaseDefine.discount_percent_from_multi(multi) if amount > 0.0 else 0
	cell.setup(int(plan["tier"]), str(days), price, _day_price_text(day_price), pct)

	if bool(_plan_cfg.get("show_original", false)) and amount > 0.0 and multi > 1.0:
		cell.set_original_price(true, _money_text(amount * multi))
	else:
		cell.set_original_price(false)


func _rebuild() -> void:
	_clear_cells()
	_plan_cfg = _resolve_plan_config()
	_scroll_layout = bool(_plan_cfg.get("scroll", false))

	_has_real_price = _compute_has_real_price()

	_money_fmt = _resolve_money_fmt()
	if _scroll_layout:
		_build_scroll_cells()
	else:
		_build_fixed_cells()

	if _scroll_container != null:
		_scroll_container.visible = _scroll_layout
	if _container != null:
		_container.visible = not _scroll_layout

	_apply_compliance_text()

	_apply_offline_hint()

	var shown: PackedStringArray = PackedStringArray()
	var shown_plans: Array = _plan_cfg.get("plans", [])
	for plan in shown_plans:
		var pid: String = String(plan["product_id"])
		shown.append("%s=%s" % [pid.trim_prefix("com.oakever.meowdoku."), _real_price(pid)])
	print(
		(
			"[Purchase (PurchasePage)] rebuild group=%d(%s) scroll=%s show_original=%s owned_force_base=%d prices=%s"
			% [
				int(_plan_cfg.get("group", -1)),
				"锁定" if PurchaseManager.has_vip_price_ab_lock() else "实时AB",
				_scroll_layout,
				_plan_cfg.get("show_original", false),
				_owned_force_base(),
				" ".join(shown)
			]
		)
	)

	if not _entry_played:
		_entry_played = true
		_play_entry_anim()


func _play_entry_anim() -> void:
	_stop_entry_anim()
	_entry_seq += 1
	var seq: int = _entry_seq
	if _anim != null and _anim.has_animation(ANIM_APPEAR):
		_anim.play(ANIM_APPEAR)

	for cell in _cells:
		if cell != null:
			cell.prepare_appear()


	_entry_timers.append(create_countdown(_LOOP_START_DELAY, func() -> void:
		_play_cells_loop()
		_entry_timers.append(create_tick(_LOOP_INTERVAL, _play_cells_loop))))




	await get_tree().process_frame


	var idx: int = 0
	while idx < _cells.size():
		var wait: float = _ENTRY_CELL_DELAY if idx == 0 else _ENTRY_CELL_STAGGER
		await get_tree().create_timer(wait).timeout

		if not is_showing() or seq != _entry_seq:
			return
		if idx < _cells.size() and is_instance_valid(_cells[idx]):
			_cells[idx].play_appear()
		idx += 1


func _play_cells_loop() -> void:
	for cell in _cells:
		if is_instance_valid(cell):
			cell.play_loop_once()


func _stop_entry_anim() -> void:
	for t in _entry_timers:
		if is_instance_valid(t):
			remove_timer(t)
	_entry_timers.clear()


func _build_fixed_cells() -> void:
	var origin: Vector2 = _container.position if _container != null else Vector2(48, 48)
	var plans: Array = _plan_cfg.get("plans", [])
	for i in mini(plans.size(), _SLOT_Y.size()):
		var cell = create_child(CELL_SCENE)
		if cell == null:
			continue

		if _plan_group != null and cell.get_parent() != _plan_group:
			cell.get_parent().remove_child(cell)
			_plan_group.add_child(cell)
		cell.position = origin + Vector2(0.0, _SLOT_Y[i])
		_mount_plan_cell(cell, plans[i])

	var n: int = int(plans[0]["benefit"]) if not plans.is_empty() else 1
	_benefit_x2 = n >= 2
	_apply_benefit_count(n)


func _mount_plan_cell(cell, plan: Dictionary) -> void:
	_apply_plan_prices(cell, plan)
	_apply_cell_state(cell, plan)

	cell.buy_pressed.connect(_on_plan_buy_pressed.bind(plan))
	_cells.append(cell)


func _apply_scroll_viewport() -> void:
	if _scroll_container == null:
		return
	var view_h: float = get_viewport_rect().size.y
	var t: float = clampf((view_h - _VIEW_H_MIN) / (_VIEW_H_MAX - _VIEW_H_MIN), 0.0, 1.0)
	var vh: float = lerpf(SCROLL_VIEWPORT_MIN, SCROLL_VIEWPORT_MAX, t)

	var inset: float = (SCROLL_VIEWPORT_MAX - vh) * 0.5
	_scroll_container.offset_top = inset - SCROLL_MARGIN
	_scroll_container.offset_bottom = inset + vh + SCROLL_MARGIN


func _build_scroll_cells() -> void:
	if _scroll_vbox == null:
		return
	_apply_scroll_viewport()
	var plans: Array = _plan_cfg.get("plans", [])
	for plan in plans:
		var cell = create_child(CELL_SCENE)
		if cell == null:
			continue

		if cell.get_parent() != _scroll_vbox:
			cell.get_parent().remove_child(cell)
			_scroll_vbox.add_child(cell)
		cell.position = Vector2.ZERO
		cell.custom_minimum_size = Vector2(0.0, CELL_H)
		cell.size_flags_horizontal = Control.SIZE_FILL

		_mount_plan_cell(cell, plan)
	if _scroll_container != null:
		_scroll_container.scroll_vertical = 0
	_benefit_x2 = false

	_apply_benefit_count(1)


func _on_scroll_v_changed(v: float) -> void:
	if not _scroll_layout or _scroll_container == null:
		return

	var x2_start: float = 3.0 * (CELL_H + SCROLL_SEP)

	var show_x2: bool = (v + _scroll_container.size.y * 0.5 - SCROLL_MARGIN) >= x2_start
	if show_x2 == _benefit_x2:
		return
	_benefit_x2 = show_x2
	_apply_benefit_count(2 if show_x2 else 1)


func _apply_cell_state(cell, plan: Dictionary) -> void:
	if not PurchaseManager.is_vip_active():
		if _has_real_price:
			cell.set_display_state(0)
		else:
			cell.set_display_state(2, true)
		return
	cell.set_display_state(1 if _is_owned_plan(plan) else 2)


func _is_owned_plan(plan: Dictionary) -> bool:
	var owned_pid: String = PurchaseManager.get_vip_plan_product_id()
	return not owned_pid.is_empty() and owned_pid == String(plan["product_id"])


func _apply_compliance_text() -> void:
	if _compliance_txt != null:
		_compliance_txt.text = tr(PurchaseDefine.compliance_key())
	if _manage_guide_txt == null:
		return
	var subscribed: bool = PurchaseManager.is_vip_active()
	_manage_guide_txt.visible = subscribed
	if subscribed:
		_manage_guide_txt.text = tr(PurchaseDefine.manage_guide_key(PurchaseManager.get_vip_tier()))
	else:
		_manage_guide_txt.text = ""


func _apply_offline_hint() -> void:
	if _offline_hint == null:
		return
	_offline_hint.visible = not _has_real_price


func _compute_has_real_price() -> bool:
	var plans: Array = _plan_cfg.get("plans", [])
	for plan in plans:
		if _real_amount(String(plan["product_id"])) > 0.0:
			return true
	return false


func _apply_benefit_count(n: int) -> void:
	if _locate_txt != null:
		_locate_txt.text = tr("PURCHASE_BENEFIT_LOCATE_PER_DAY") % n
	if _hint_txt != null:
		_hint_txt.text = tr("PURCHASE_BENEFIT_HINT_PER_DAY") % n


func _day_price_text(amount: String) -> String:
	return tr("PURCHASE_CELL_PRICE_PER_DAY") % amount


func _clear_cells() -> void:
	for c in _cells:
		if is_instance_valid(c):
			destroy_child(c)
	_cells.clear()


func _is_link_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return event is InputEventScreenTouch and event.pressed


func _on_terms_btn_pressed(event: InputEvent = null) -> void:
	if event != null and not _is_link_press(event):
		return
	Tracker.track_btn_click(Tracker.Btn.TERMS, self)
	OS.shell_open(UniKitManager.get_localized_privacy_url("https://oakevergames.com/tos.html"))


func _on_privacy_btn_pressed(event: InputEvent = null) -> void:
	if event != null and not _is_link_press(event):
		return
	Tracker.track_btn_click(Tracker.Btn.PRIVACY, self)
	OS.shell_open(UniKitManager.get_localized_privacy_url("https://oakevergames.com/pp.html"))


func _on_back_pressed() -> void:
	UIManager.hide_ui(UiName.SUBSCRIPTION)


func on_escape() -> bool:
	if _restoring:
		print("[Purchase (PurchasePage)] 恢复购买进行中，吞掉返回键")
		return true
	_on_back_pressed()
	return true


## 从套餐交互进入购买流程，并设置等待反馈；成功弹窗由后续 purchase_result 决定。
func _on_plan_buy_pressed(_tier: int, plan: Dictionary) -> void:
	if not _buying_product_id.is_empty():
		print("[Purchase (PurchasePage)] 点击被防抖吞掉 buying=%s" % _buying_product_id)
		return
	print(
		(
			"[Purchase (PurchasePage)] 点击档位 tier=%d product_id=%s network=%s vip=%s"
			% [
				int(plan.get("tier", -1)),
				String(plan.get("product_id", "")),
				UniKitManager.get_network_type(),
				PurchaseManager.is_vip_active()
			]
		)
	)

	_purchase_attempted = true
	var sub_type: String = PurchaseDefine.sub_type_of_tier(int(plan.get("tier", -1)))

	Tracker.track_sub_plan_select(sub_type)

	Tracker.track_sub_pay(
		Tracker.SubscriptionState.SUBMIT, UniKitManager.get_network_type(), sub_type
	)

	var product_id: String = String(plan["product_id"])
	if product_id.is_empty():
		push_error("[Purchase (PurchasePage)] 档位缺 product_id，无法购买 plan=%s" % str(plan))
		Toast.popup("PURCHASE_TOAST_FAILED", self)
		return
	if not UniKitManager.is_online():
		print("[Purchase (PurchasePage)] 购买被拦：无网络（不白拉一次必失败的支付）")

		Toast.popup("PURCHASE_TOAST_NO_CONNECTION", self)
		return

	_buy_loading_shown = true
	UIManager.show_ui(UiName.COMMON_LOADING)

	if OS.has_feature("editor"):
		PurchaseManager.debug_simulate_purchase_success(product_id)
		return
	_buying_product_id = product_id
	if not PurchaseManager.buy(product_id):
		print("[Purchase (PurchasePage)] 购买未发起：PurchaseManager.buy() 返回 false（拒绝原因见其日志）")
		_cancel_buy_loading()
		_buying_product_id = ""

		if PurchaseManager.is_vip_active() or not PurchaseManager.is_purchasing():
			Toast.popup("PURCHASE_TOAST_FAILED", self)


## 消费 SDK 转来的最终购买结果，收起加载态并决定成功提示或失败反馈。
func _on_purchase_result(
	success: bool, product_id: String, error, is_active_purchase: bool
) -> void:
	_cancel_buy_loading()
	var was_buying: bool = not _buying_product_id.is_empty()
	var buying_product_id: String = _buying_product_id
	_buying_product_id = ""
	print(
		(
			"[Purchase (PurchasePage)] purchase_result success=%s product_id=%s is_active_purchase=%s was_buying=%s error=%s"
			% [
				success,
				product_id,
				is_active_purchase,
				was_buying,
				PurchaseManager.format_error(error)
			]
		)
	)

	var event_product_id: String = product_id if not product_id.is_empty() else buying_product_id
	if not success:
		var reason: int = int(error.reason) if error != null else -1
		if reason == UniKitPurchaseError.REASON_USER_CANCELLED:
			if was_buying:
				Toast.popup("PURCHASE_TOAST_CANCELLED", self)
			return
		if was_buying:
			Toast.popup("PURCHASE_TOAST_FAILED", self)
		return

	_show_success_ui(event_product_id, is_active_purchase or was_buying)

	print("[Purchase (PurchasePage)] 购买成功 product_id=%s" % product_id)


func _show_success_ui(product_id: String, show_success_popup: bool = true) -> void:
	print(
		(
			"[Purchase (PurchasePage)] 成功 UI 流转 product_id=%s popup=%s group=%d"
			% [product_id, show_success_popup, int(_plan_cfg.get("group", -1))]
		)
	)
	if show_success_popup:
		_show_success_popup(product_id)
	if is_showing():
		_rebuild()

	if not show_success_popup:
		return

	await UIManager.await_hidden(UiName.SUBSCRIPTION_SUCCESS)
	await VipDailyGiftFlow.run()


func _show_success_popup(product_id: String) -> void:
	(
		UIManager
		. show_ui(
			UiName.SUBSCRIPTION_SUCCESS,
			{
				"daily_gift_count": PurchaseDefine.daily_gift_count(product_id),
			}
		)
	)


func _on_products_ready() -> void:
	print(
		(
			"[Purchase (PurchasePage)] products_ready count=%d rebuild=%s"
			% [PurchaseManager.get_products().size(), is_showing()]
		)
	)
	if is_showing():
		_rebuild()


func _on_vip_refreshed(_is_active: bool) -> void:
	print(
		(
			"[Purchase (PurchasePage)] vip_refreshed active=%s plan_product_id=%s rebuild=%s"
			% [_is_active, PurchaseManager.get_vip_plan_product_id(), is_showing()]
		)
	)
	if is_showing():
		_rebuild()


## 开始恢复购买并安排延迟加载提示；结果回调负责取消提示，避免快速完成时界面闪烁。
func _on_restore_pressed() -> void:
	if _restoring:
		print("[Purchase (PurchasePage)] 恢复点击被防抖吞掉")
		return
	print(
		(
			"[Purchase (PurchasePage)] 点击恢复购买 network=%s vip=%s"
			% [UniKitManager.get_network_type(), PurchaseManager.is_vip_active()]
		)
	)

	Tracker.track_sub_resume(Tracker.SubscriptionState.SUBMIT, UniKitManager.get_network_type())

	if not UniKitManager.is_online():
		Toast.popup("NETWORK_ERROR", self)
		return

	_restoring = true

	if OS.has_feature("ios"):
		_restore_loading_shown = true
		UIManager.show_ui(UiName.COMMON_LOADING)
	else:
		UIManager.block_input_briefly(self, _RESTORE_LOADING_DELAY + 0.1)
		_restore_loading_timer = create_countdown(_RESTORE_LOADING_DELAY, _on_restore_loading_delay)

	PurchaseManager.restore_purchase()


func _on_restore_loading_delay() -> void:
	_restore_loading_timer = null
	if not _restoring:
		return
	print("[Purchase (PurchasePage)] 恢复回执 %.1fs 未到，弹 loading 遮罩" % _RESTORE_LOADING_DELAY)
	_restore_loading_shown = true
	UIManager.show_ui(UiName.COMMON_LOADING)


func _cancel_restore_loading() -> void:
	if _restore_loading_timer != null:
		if is_instance_valid(_restore_loading_timer):
			remove_timer(_restore_loading_timer)
		_restore_loading_timer = null
	if _restore_loading_shown:
		_restore_loading_shown = false
		UIManager.hide_ui(UiName.COMMON_LOADING)


func _cancel_buy_loading() -> void:
	if not _buy_loading_shown:
		return
	_buy_loading_shown = false
	UIManager.hide_ui(UiName.COMMON_LOADING)


func _on_restore_result(success: bool, error) -> void:
	print(
		(
			"[Purchase (PurchasePage)] restore_result success=%s vip=%s tier=%d error=%s"
			% [
				success,
				PurchaseManager.is_vip_active(),
				PurchaseManager.get_vip_tier(),
				PurchaseManager.format_error(error)
			]
		)
	)

	_restoring = false
	_cancel_restore_loading()
	if not success:
		print("[Purchase (PurchasePage)] 恢复失败 %s" % PurchaseManager.format_error(error))

		Toast.popup("PURCHASE_TOAST_RESTORE_FAILED", self)
		return

	if PurchaseManager.is_vip_active():
		Toast.popup("PURCHASE_TOAST_RESTORE_OK", self)
		if is_showing():
			_rebuild()
	else:
		Toast.popup("PURCHASE_TOAST_RESTORE_NONE", self)
