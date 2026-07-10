extends UIFrameWindow









@onready var _title_label: Label = $Root / TitleLabel
@onready var _info_label: Label = $Root / InfoLabel
@onready var _reward_button: Button = $Root / ButtonRow / RewardButton


var _on_close: Callable = Callable()

var _on_reward_close: Callable = Callable()

func on_show(params: Dictionary = {}) -> void :
    visible = true
    _on_close = params.get("on_close", Callable())
    _on_reward_close = params.get("on_reward_close", Callable())
    var placement_id: String = params.get("placement_id", "")
    var position: String = params.get("position", "")
    _title_label.text = "MOCK 激励视频" if placement_id == "reward" else "MOCK 插屏广告"
    _info_label.text = "placement: %s\nposition: %s" % [placement_id, position]

    _reward_button.visible = placement_id == "reward"


func _on_close_pressed() -> void :
    _fire(_on_close)


func _on_reward_close_pressed() -> void :
    _fire(_on_reward_close)


func _fire(cb: Callable) -> void :
    _on_close = Callable()
    _on_reward_close = Callable()
    if cb.is_valid():
        cb.call()
