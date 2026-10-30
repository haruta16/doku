## 每日订阅礼包的展示流程；先检查领取条件，再经 PurchaseManager 发奖并展示奖励页面。

class_name VipDailyGiftFlow
extends RefCounted


## 检查今日领取资格后打开领取弹窗，把实际 claim 回调交给弹窗；只有用户领取才由管理器发奖并记日期。
static func run() -> void:
	if not PurchaseManager.can_claim_vip_daily_gift():
		print(
			(
				"[Purchase (VipDailyGiftFlow)] 不弹每日赠送: online=%s vip=%s last=%s"
				% [
					UniKitManager.is_online(),
					PurchaseManager.is_vip_active(),
					PurchaseManager.get_vip_daily_gift_last_claim_date()
				]
			)
		)
		return

	var n: int = PurchaseDefine.daily_gift_count(PurchaseManager.get_vip_plan_product_id())
	var popup := (
		(
			UIManager
			. show_ui(
				UiName.REWARD_CLAIM_POPUP,
				{
					"items": _gift_items(n),
					"claim": PurchaseManager.claim_vip_daily_gift,
					"title": "VIP_DAILY_REWARD_TITLE",
					"text": "VIP_DAILY_REWARD_DESC",
				}
			)
		)
		as RewardClaimPopup
	)
	if popup == null:
		push_error("[Purchase (VipDailyGiftFlow)] 领取弹窗打开失败，本次跳过（未发未记，下个时机重试）")
		return
	print("[Purchase (VipDailyGiftFlow)] 弹出每日赠送领取弹窗 x%d" % n)

	await UIManager.await_hidden(UiName.REWARD_CLAIM_POPUP)


static func _gift_items(n: int) -> Array:
	return [
		AwardItem.make(Tracker.Prop.HINT, n),
		AwardItem.make(Tracker.Prop.LOCATE, n),
	]
