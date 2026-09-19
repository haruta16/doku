# 编辑器专用的假广告窗：只画一个框模拟激励视频/插屏，让广告流程在不接 SDK 时也能跑通
# 只在编辑器里注册（UIRegistry._EDITOR_PAGES），由 UniKitManager._mock_show_ad 拉起
extends UIFrameWindow

# ---- 子节点引用 ----
@onready var _title_label: Label = $Root/TitleLabel # 标题：reward 显示「MOCK 激励视频」，否则显示「MOCK 插屏广告」
@onready var _info_label: Label = $Root/InfoLabel # 显示 placement / position 两个参数
@onready var _reward_button: Button = $Root/ButtonRow/RewardButton # 只有激励视频才显示的「已发奖」按钮

# ---- 外部回调（由 UniKitManager._mock_show_ad 传进来） ----
var _on_close: Callable = Callable() # 关闭广告时的回调（通知上层「广告已关闭」）

var _on_reward_close: Callable = Callable() # 点发奖按钮时的回调（通知上层「已发奖 + 已关闭」）


# 显示时从 params 取参数换文案与按钮显隐；UIManager.show_ui 会调到这里
func on_show(params: Dictionary = {}) -> void:
	visible = true
	_on_close = params.get("on_close", Callable())
	_on_reward_close = params.get("on_reward_close", Callable())
	var placement_id: String = params.get("placement_id", "")
	var position: String = params.get("position", "")
	_title_label.text = "MOCK 激励视频" if placement_id == "reward" else "MOCK 插屏广告" # 只有 placement_id 为 reward 才算激励视频
	_info_label.text = "placement: %s\nposition: %s" % [placement_id, position]

	_reward_button.visible = placement_id == "reward" # 插屏没有发奖按钮


# CloseTextButton 按下：只关广告，不发奖
func _on_close_pressed() -> void:
	_fire(_on_close)


# RewardButton 按下：发奖后再关
func _on_reward_close_pressed() -> void:
	_fire(_on_reward_close)


# 先清空两个回调再调用，避免重复触发或回调里重入
func _fire(cb: Callable) -> void:
	_on_close = Callable() # 先让两个回调失效，防止重入
	_on_reward_close = Callable()
	if cb.is_valid(): # 回调无效（没传）时什么都不做
		cb.call()
