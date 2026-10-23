## 模拟广告页：按按钮触发奖励、关闭或先关闭再奖励等回调次序。
extends UIFrameWindow

# ---- 子节点引用 ----
@onready var _title_label: Label = $Root/TitleLabel # 标题：reward 显示「MOCK 激励视频」，否则显示「MOCK 插屏广告」
@onready var _info_label: Label = $Root/InfoLabel # 显示 placement / position 两个参数
@onready var _reward_button: Button = $Root/ButtonRow/RewardButton # 只有激励视频才显示的「已发奖」按钮
@onready var _closed_first_button: Button = $Root/ButtonRow/ClosedFirstButton

# ---- 外部回调（由 UniKitManager._mock_show_ad 传进来） ----
var _on_close: Callable = Callable() # 关闭广告时的回调（通知上层「广告已关闭」）

var _on_reward_close: Callable = Callable() # 点发奖按钮时的回调（通知上层「已发奖 + 已关闭」）

var _on_closed_first: Callable = Callable()


func on_show(params: Dictionary = {}) -> void:
	visible = true
	_on_close = params.get("on_close", Callable())
	_on_reward_close = params.get("on_reward_close", Callable())
	_on_closed_first = params.get("on_closed_first", Callable())
	var placement_id: String = params.get("placement_id", "")
	var position: String = params.get("position", "")
	_title_label.text = "MOCK 激励视频" if placement_id == AdPlacement.REWARD else "MOCK 插屏广告"
	_info_label.text = "placement: %s\nposition: %s" % [placement_id, position]

	_reward_button.visible = placement_id == AdPlacement.REWARD
	_closed_first_button.visible = placement_id == AdPlacement.REWARD


## CloseTextButton 按下：只关广告，不发奖
func _on_close_pressed() -> void:
	_fire(_on_close)


## RewardButton 按下：发奖后再关
func _on_reward_close_pressed() -> void:
	_fire(_on_reward_close)


func _on_closed_first_pressed() -> void:
	_fire(_on_closed_first)


## 先清空本页保存的所有回调再调用所选项，避免同一模拟广告重复发送结果。
func _fire(cb: Callable) -> void:
	_on_close = Callable()
	_on_reward_close = Callable()
	_on_closed_first = Callable()
	if cb.is_valid():
		cb.call()
