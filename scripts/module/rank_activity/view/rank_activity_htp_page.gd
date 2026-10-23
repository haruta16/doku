## 排行活动玩法说明页；展示说明内容并处理关闭输入，规则本身由活动管理器执行。

extends UIFrameWindow

@onready var _icon_fish: Control = $Root/Content/CollectVisual/IconFish
@onready var _text_fish: Control = $Root/Content/CollectTextFish
@onready var _reward_full: Control = $Root/Content/RewardFull
@onready var _anim: AnimationPlayer = $AnimationPlayer


func on_show(_params: Dictionary = {}) -> void:
	_icon_fish.visible = true
	_text_fish.visible = true
	_reward_full.visible = true
	AnimUtil.play(_anim, &"Appear2")


func _input(event: InputEvent) -> void:
	if not is_showing():
		return
	var pressed: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if pressed:
		get_viewport().set_input_as_handled()
		UIManager.hide_ui(UiName.RANK_ACTIVITY_HTP)
