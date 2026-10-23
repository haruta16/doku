## 设置里的订阅入口；按订阅状态切换推广标题和已订阅提示，并响应语言变化。

extends UIChildWindow

signal card_pressed

enum State { ENTRY, WEEK, MONTH, YEAR }

const _KEY_ENTRY_TITLE: String = "PURCHASE_GET_PREMIUM"

const _KEY_PREMIUM_TITLE: String = "PURCHASE_PREMIUM_TITLE"

const _KEY_PREMIUM_PLUS_TITLE: String = "PURCHASE_PREMIUM_PLUS_TITLE"

const _STATE_STYLE: Dictionary = {
	State.ENTRY:
	{
		"bg": preload("res://assets/sprites/purchase/settings_card_entry.png"),
	},
	State.WEEK:
	{
		"bg": preload("res://assets/sprites/purchase/settings_card_week.png"),
		"title": Color(0.5882353, 0.3176471, 0.0, 1.0),
	},
	State.MONTH:
	{
		"bg": preload("res://assets/sprites/purchase/settings_card_month.png"),
		"title": Color(0.5215687, 0.1764706, 0.0039216, 1.0),
	},
	State.YEAR:
	{
		"bg": preload("res://assets/sprites/purchase/settings_card_year.png"),
		"title": Color(0.5764706, 0.0666667, 0.1607843, 1.0),
	},
}

@onready var _card_bg: TextureRect = $CardBg
@onready var _state_entry: Control = $StateEntry
@onready var _state_subscribed: Control = $StateSubscribed
@onready var _entry_title: Label = $StateEntry/TitleTxt
@onready var _premium_title: Label = $StateSubscribed/TitleTxt
@onready var _click_btn: Button = $ClickBtn

var _state: int = State.ENTRY

var _is_base: bool = true


func on_create() -> void:
	_click_btn.pressed.connect(_on_click_btn_pressed)
	_click_btn.button_down.connect(func() -> void: play_press_scale(self))
	_click_btn.button_up.connect(func() -> void: play_release_scale(self))


func on_show(params: Dictionary = {}) -> void:
	_apply_titles()
	var st: int = int(params.get("state", State.ENTRY))
	if st == State.ENTRY:
		show_entry()
	else:
		show_subscribed(st, bool(params.get("is_base", true)))


func show_entry() -> void:
	_apply_state(State.ENTRY)


func show_subscribed(tier: int, is_base: bool = true) -> void:
	if tier == State.ENTRY or not _STATE_STYLE.has(tier):
		push_error("[Purchase (PurchaseSettingsCell)] show_subscribed 收到非法档位 tier=%d，回退周档" % tier)
		tier = State.WEEK
	_is_base = is_base
	_apply_state(tier)


func get_state() -> int:
	return _state


func _apply_state(st: int) -> void:
	_state = st
	var is_entry: bool = st == State.ENTRY
	_state_entry.visible = is_entry
	_state_subscribed.visible = not is_entry

	var style: Dictionary = _STATE_STYLE[st]
	_card_bg.texture = style["bg"]
	if is_entry:
		return
	_premium_title.add_theme_color_override("font_color", style["title"])

	_premium_title.text = tr(_premium_title_key())


func _premium_title_key() -> String:
	return _KEY_PREMIUM_TITLE if _is_base else _KEY_PREMIUM_PLUS_TITLE


func _apply_titles() -> void:
	_entry_title.text = tr(_KEY_ENTRY_TITLE)
	_premium_title.text = tr(_premium_title_key())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_titles()


func _on_click_btn_pressed() -> void:
	card_pressed.emit()
