## 一张订阅套餐卡；呈现价格、折扣、日价、持有状态与入场动画，向购买页报告按钮动作。

extends UIChildWindow

signal buy_pressed(tier: int)

const Tier := PurchaseDefine.Tier

enum DisplayState { NORMAL, CHECKED, DISABLED }

const _DISABLED_ALPHA: float = 0.4

const _ORIG_PRICE_FONT_MAX: float = 46.0
const _STRIKE_THICKNESS: float = 4.0
const _STRIKE_Y_OFFSET_AT_MAX: float = 2.0

const ANIM_APPEAR := &"Appear"
const ANIM_LOOP := &"Loop"

var _display_state: int = DisplayState.NORMAL

const _STAR := {
	Tier.WEEK: preload("res://assets/sprites/purchase/badge_base_week.png"),
	Tier.MONTH: preload("res://assets/sprites/purchase/badge_base_month.png"),
	Tier.YEAR: preload("res://assets/sprites/purchase/badge_base_year.png"),
}

const _CARD_BASE := {
	Tier.WEEK: preload("res://assets/sprites/purchase/card_base_week.png"),
	Tier.MONTH: preload("res://assets/sprites/purchase/card_base_month.png"),
	Tier.YEAR: preload("res://assets/sprites/purchase/card_base_year.png"),
}

const _PILL_BASE := {
	Tier.WEEK: preload("res://assets/sprites/purchase/pill_base_week.png"),
	Tier.MONTH: preload("res://assets/sprites/purchase/pill_base_month.png"),
	Tier.YEAR: preload("res://assets/sprites/purchase/pill_base_year.png"),
}

const _TIER := {
	Tier.WEEK:
	{
		"day_color": Color(0.8666667, 0.50980395, 0.1254902),
		"bubble": Color(0.8576921, 0.5934019, 0.13690066),
		"badge_shadow": Color(0.09296192, 0.36644757, 0.65769196),
		"strike": Color(0.7254902, 0.3882353, 0.0),
	},
	Tier.MONTH:
	{
		"day_color": Color(0.896154, 0.46877748, 0.23954822),
		"bubble": Color(0.8115384, 0.394324, 0.18571687),
		"badge_shadow": Color(0.67692274, 0.2636293, 0.091124214),
		"strike": Color(0.8156863, 0.2784314, 0.007843138),
	},
	Tier.YEAR:
	{
		"day_color": Color(0.8576924, 0.3480248, 0.45698816),
		"bubble": Color(0.75, 0.23798077, 0.3403846),
		"badge_shadow": Color(0.59999967, 0.10846105, 0.5049688),
		"strike": Color(0.6862745, 0.1254902, 0.23921569),
	},
}

@onready var _base_img: TextureRect = $Control/Board/BaseImg
@onready var _day_txt: Label = $Control/DayTxt
@onready var _day_num_txt: Label = $Control/DayNumTxt
@onready var _price_txt: Label = $Control/PriceTxt
@onready var _day_price_txt: Label = $Control/Bubble/DayPriceTxt
@onready var _bubble_bg: TextureRect = $Control/Bubble/BubbleBg
@onready var _discount_badge: Control = $Control/DiscountBadge
@onready var _badge_star: TextureRect = $Control/DiscountBadge/StarImg
@onready var _badge_pct: DiscountPctLabel = $Control/DiscountBadge/PctTxt
@onready var _check_badge: Control = $Control/CheckBadge
@onready var _orig_price_txt: Label = $Control/OrigPriceTxt
@onready var _strike_line: TextureRect = $Control/StrikeLine

@onready var _anim: AnimationPlayer = $AnimationPlayer

@onready var _effect_star: Control = $Control/Effect_star

@onready var _glow1: TextureRect = $Control/DiscountBadge/Effect_DiscountBadge/glow1
@onready var _glow2: TextureRect = $Control/DiscountBadge/Effect_DiscountBadge/glow2

@onready var _badge_effect: TextureRect = $Control/DiscountBadge/Effect_DiscountBadge

@onready var _buy_btn: Button = $BuyBtn

@onready var _pill_visual: TextureRect = $Control/PricePill/Visual

const _VEIL_RGB := Color(1.0, 0.972549, 0.8862745)

@onready var _dim_veil: TextureRect = $Control/DimVeil
@onready var _badge_veil: TextureRect = $Control/DiscountBadge/BadgeDimVeil

var _tier: int = Tier.YEAR


func on_create() -> void:
	if _buy_btn != null:
		_buy_btn.pressed.connect(func() -> void: buy_pressed.emit(_tier))
		_buy_btn.button_down.connect(_on_buy_btn_down)
		_buy_btn.button_up.connect(_on_buy_btn_up)


func _on_buy_btn_down() -> void:
	play_press_scale(self)


func _on_buy_btn_up() -> void:
	play_release_scale(self)


func setup(
	tier: int, day_num: String, price: String, day_price: String, discount_percent: int = 0
) -> void:
	_tier = tier
	var d: Dictionary = _TIER.get(tier, _TIER[Tier.YEAR])

	if _base_img != null and _CARD_BASE.has(tier):
		_base_img.texture = _CARD_BASE[tier]

	if _pill_visual != null and _PILL_BASE.has(tier):
		_pill_visual.texture = _PILL_BASE[tier]

	if _bubble_bg != null:
		_bubble_bg.self_modulate = d["bubble"]

	if _orig_price_txt != null:
		_orig_price_txt.add_theme_color_override("font_color", d["strike"])
	if _strike_line != null:
		_strike_line.self_modulate = d["strike"]

	if _day_num_txt != null:
		_day_num_txt.add_theme_color_override("font_color", d["day_color"])
		_day_num_txt.text = day_num
	if _day_txt != null:
		_day_txt.add_theme_color_override("font_color", d["day_color"])

	if _price_txt != null:
		_price_txt.text = price
	if _day_price_txt != null:
		_day_price_txt.text = day_price

	_apply_badge(tier, maxi(discount_percent, 0))

	_refresh_effects()


func _apply_badge(tier: int, percent: int) -> void:
	var d: Dictionary = _TIER.get(tier, _TIER[Tier.YEAR])
	if _badge_star != null and _STAR.has(tier):
		_badge_star.texture = _STAR[tier]
	if _badge_pct != null:
		_badge_pct.shadow_color = d["badge_shadow"]
		_badge_pct.percent = percent
	if _discount_badge != null:
		_discount_badge.visible = percent > 0


func _refresh_effects() -> void:
	var is_year: bool = _tier == Tier.YEAR
	var sellable: bool = _display_state == DisplayState.NORMAL
	if _effect_star != null:
		_effect_star.visible = sellable and is_year
	if _badge_effect != null:
		_badge_effect.visible = sellable
	if _glow1 != null:
		_glow1.visible = sellable and is_year
	if _glow2 != null:
		_glow2.visible = sellable and not is_year


func prepare_appear() -> void:
	if _anim == null or not _anim.has_animation(ANIM_APPEAR):
		return
	_anim.play(ANIM_APPEAR)
	_anim.seek(0.0, true)
	_anim.pause()


func play_appear() -> void:
	if _anim == null or not _anim.has_animation(ANIM_APPEAR):
		return
	_anim.play(ANIM_APPEAR)


func play_loop_once() -> void:
	if _anim == null or not _anim.has_animation(ANIM_LOOP):
		return
	if _display_state != DisplayState.NORMAL:
		return
	_anim.play(ANIM_LOOP)


func set_day_price(text: String) -> void:
	if _day_price_txt != null:
		_day_price_txt.text = text


func set_original_price(show: bool, text: String = "") -> void:
	if _orig_price_txt != null:
		_orig_price_txt.visible = show
		if show and text != "":
			_orig_price_txt.text = text

			call_deferred("_sync_strike_line_y")

	if _strike_line != null:
		_strike_line.visible = show

	if _day_num_txt != null:
		_day_num_txt.offset_top = 23.0 if show else 47.0
		_day_num_txt.offset_bottom = 80.0 if show else 104.0
	if _day_txt != null:
		_day_txt.offset_top = 68.0 if show else 95.0
		_day_txt.offset_bottom = 148.0 if show else 175.0


func _sync_strike_line_y() -> void:
	if _orig_price_txt == null or _strike_line == null:
		return
	var fs: float = float(_orig_price_txt.get_theme_font_size(&"font_size"))
	if fs <= 0.0:
		return
	var box_cy: float = (_orig_price_txt.offset_top + _orig_price_txt.offset_bottom) * 0.5
	var line_cy: float = box_cy + _STRIKE_Y_OFFSET_AT_MAX * fs / _ORIG_PRICE_FONT_MAX
	_strike_line.offset_top = line_cy - _STRIKE_THICKNESS * 0.5
	_strike_line.offset_bottom = line_cy + _STRIKE_THICKNESS * 0.5


func set_display_state(state: int, keep_clickable: bool = false) -> void:
	match state:
		DisplayState.CHECKED:
			_dim(1.0)
			if _discount_badge != null:
				_discount_badge.visible = false
			if _check_badge != null:
				_check_badge.visible = true
		DisplayState.DISABLED:
			_dim(_DISABLED_ALPHA)
			if _check_badge != null:
				_check_badge.visible = false
		_:
			_dim(1.0)
			if _check_badge != null:
				_check_badge.visible = false

	if _buy_btn != null:
		_buy_btn.disabled = state != DisplayState.NORMAL and not keep_clickable

	_display_state = state
	_refresh_effects()


func _dim(a: float) -> void:
	var veil_a: float = clampf(1.0 - a, 0.0, 1.0)
	var c: Color = Color(_VEIL_RGB.r, _VEIL_RGB.g, _VEIL_RGB.b, veil_a)
	if _dim_veil != null:
		_dim_veil.self_modulate = c
		_dim_veil.visible = veil_a > 0.001
	if _badge_veil != null:
		_badge_veil.self_modulate = c
		_badge_veil.visible = veil_a > 0.001
