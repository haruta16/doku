## 带角标按钮：组合背景、文字、子文本和阴影样式，并转发按下释放事件。
@tool
extends Control

signal tag_pressed # 点击信号；不叫 pressed 是为了不和内置信号重名

# ---- Inspector 可调属性（每个都带 setter，改完立即生效） ----
## 背景色：写进 normal / hover / pressed 三种状态样式盒
@export var bg_color: Color = Color(0.945, 0.576, 0.125, 1):
	set(value):
		bg_color = value
		_apply_bg_color() # 赋值后立即重新应用（编辑器里也立刻看到）

## 阴影颜色：给阴影贴图染色
@export var shadow_color: Color = Color(0.945, 0.576, 0.125, 0.7):
	set(value):
		shadow_color = value
		_apply_shadow_color()

## 按钮文字
@export var btn_text: String = "":
	set(value):
		btn_text = value
		_apply_text()

## 文字颜色
@export var text_color: Color = Color(1, 1, 1, 1):
	set(value):
		text_color = value
		_apply_text_color()

@export var btn_icon: Texture2D = null:
	set(value):
		btn_icon = value
		_apply_text()

@export var icon_size: Vector2 = Vector2(80, 70):
	set(value):
		icon_size = value
		_apply_text()

@export var icon_gap: float = 20.0:
	set(value):
		icon_gap = value
		_apply_text()

@export var icon_at_left: bool = false:
	set(value):
		icon_at_left = value
		_apply_text()

@export var sub_text: String = "":
	set(value):
		sub_text = value
		_apply_sub_text()

@export var sub_text_shift_up: float = 19.0:
	set(value):
		sub_text_shift_up = value
		_apply_sub_text()

## 是否显示难度小标（场景里的节点名拼作 Diffcult）
@export var show_difficult: bool = true:
	set(value):
		show_difficult = value
		_apply_show_difficult()

@export var hard_effect_variant: int = 0:
	set(value):
		hard_effect_variant = value
		_apply_show_difficult()

@export var super_hard: bool = false:
	set(value):
		super_hard = value
		_apply_show_difficult()

@export var hard_text_shift_up: float = 40.0:
	set(value):
		hard_text_shift_up = value
		_apply_show_difficult()

## 是否显示底部阴影
@export var show_shadow: bool = true:
	set(value):
		show_shadow = value
		_apply_show_shadow()

@export var border_color: Color = Color(0, 0, 0, 0):
	set(value):
		border_color = value
		_apply_border()

@export var border_width: int = 0:
	set(value):
		border_width = value
		_apply_border()

# ---- 子节点引用 ----
@onready var _anim: AnimationPlayer = $AnimationPlayer # 按下 / 松开的位移动画

@onready var _hard_diffcult: Node2D = $Root/Diffcult
@onready var _hard_effect_stars1: Control = $Root/EffectStars1
@onready var _hard_combined_fire_yellow: Sprite2D = $Root/CombinedFireYellow
@onready var _hard_fire_point_yellow: CPUParticles2D = $Root/Bg/FlirePointYellow
@onready var _hard_diffcult2: Node2D = $Root/Diffcult2
@onready var _hard_diffcult2_red1: Node2D = $Root/Diffcult2/Red1
@onready var _hard_diffcult2_red2: Node2D = $Root/Diffcult2/Red2
@onready var _hard_diffcult2_red2_fire_point: CPUParticles2D = $Root/Diffcult2/Red2/Bg/FirePointRed
@onready var _hard_text_label: Label = $Root/Text
@onready var _sub_text_label: Label = $Root/SubText
@onready var _hard_text_base_offset_top: float = _hard_text_label.offset_top
@onready var _hard_text_base_offset_bottom: float = _hard_text_label.offset_bottom

@onready var _text_base_offset_left: float = _hard_text_label.offset_left
@onready var _text_base_offset_right: float = _hard_text_label.offset_right

const _SUPER_HARD_BOX_TEX: Texture2D = preload(
	"res://assets/sprites/home/difficulty_banner_super.png"
)

const _SUPER_HARD_TAG_KEY: String = "GAME_SUPER_HARD_TAG"

@onready var _hard_box: Sprite2D = $Root/Diffcult/Box
@onready var _hard_tag_label: Label = $Root/Diffcult/Label

@onready var _hard_box_base_tex: Texture2D = _hard_box.texture
@onready var _hard_tag_base_text: String = _hard_tag_label.text


func _ready() -> void:
	_duplicate_styles()
	_apply_bg_color()
	_apply_border()
	_apply_shadow_color()
	_apply_text()
	_apply_text_color()
	_apply_sub_text()
	_apply_show_difficult()
	_apply_show_shadow()
	if not Engine.is_editor_hint():
		$Root/Bg.pressed.connect(_on_bg_pressed)
		$Root/Bg.button_down.connect(_on_bg_button_down)
		$Root/Bg.button_up.connect(_on_bg_button_up)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_text()

	elif (
		what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and not Engine.is_editor_hint()
	):
		_anim.play("RESET")
		_anim.advance(0.0)


# ================= 按钮回调 =================
## 转发成 tag_pressed
func _on_bg_pressed() -> void:
	tag_pressed.emit()


func _on_bg_button_down() -> void:
	_anim.play("RESET")
	_anim.advance(0.0)
	_anim.play_section_with_markers("GenericButton", &"", &"PressAndHold")
	_anim.advance(0.0)


## 松开：从 PressAndHold 标记播到动画结尾
func _on_bg_button_up() -> void:
	_anim.play_section_with_markers("GenericButton", &"PressAndHold", &"")


# ================= 属性应用 =================
## 把三种状态的内置 StyleBoxFlat 各复制一份成本实例独有
func _duplicate_styles() -> void:
	var bg: Button = $Root/Bg
	for state: String in ["normal", "hover", "pressed"]:
		var style := bg.get_theme_stylebox(state) as StyleBoxFlat
		if style:
			bg.add_theme_stylebox_override(state, style.duplicate())


## 把 bg_color 写进三种状态样式盒
func _apply_bg_color() -> void:
	if not is_node_ready(): # setter 可能在 @onready 取到节点之前就被调用
		return
	var bg: Button = $Root/Bg
	for state: String in ["normal", "hover", "pressed"]:
		var style := bg.get_theme_stylebox(state) as StyleBoxFlat
		if style:
			style.bg_color = bg_color


func _apply_border() -> void:
	if not is_node_ready():
		return
	var bg: Button = $Root/Bg
	for state: String in ["normal", "hover", "pressed"]:
		var style := bg.get_theme_stylebox(state) as StyleBoxFlat
		if style:
			style.set_border_width_all(border_width)
			style.border_color = border_color


const _HARD_V34_SHADOW_RGB: Color = Color(0.83, 0.3, 0.3)


func _apply_shadow_color() -> void:
	if not is_node_ready():
		return
	var shadow: NinePatchRect = $Root/Shadow
	if show_difficult and hard_effect_variant in [3, 4]:
		shadow.self_modulate = Color(_HARD_V34_SHADOW_RGB, shadow_color.a)
	else:
		shadow.self_modulate = shadow_color


const _BASE_FONT_SIZE: int = 80 # 初始字号（像素）
const _MIN_FONT_SIZE: int = 40 # 最小字号（像素）

const _TEXT_AREA_LEFT: float = 53.0
const _TEXT_AREA_RIGHT: float = 739.0

const _BODY_CENTER_X: float = 394.0
const _BODY_CENTER_Y: float = 148.0


func _apply_text() -> void:
	if not is_node_ready():
		return
	var label: Label = $Root/Text
	label.text = btn_text
	var icon: TextureRect = get_node_or_null("Root/Icon")

	if btn_icon == null:
		if icon != null:
			icon.visible = false

		label.offset_left = _text_base_offset_left
		label.offset_right = _text_base_offset_right
		var fs: int = _BASE_FONT_SIZE
		label.add_theme_font_size_override("font_size", fs)
		while fs > _MIN_FONT_SIZE and label.get_minimum_size().x > label.size.x:
			fs -= 4
			label.add_theme_font_size_override("font_size", fs)
		return

	if icon != null:
		icon.visible = true
		icon.texture = btn_icon
		icon.size = icon_size

	var disp: String = tr(btn_text)
	var avail: float = (_TEXT_AREA_RIGHT - _TEXT_AREA_LEFT) - icon_size.x - icon_gap
	var font: Font = label.get_theme_font("font")
	var afs: int = _BASE_FONT_SIZE
	label.add_theme_font_size_override("font_size", afs)
	while (
		afs > _MIN_FONT_SIZE
		and font.get_string_size(disp, HORIZONTAL_ALIGNMENT_LEFT, -1, afs).x > avail
	):
		afs -= 4
		label.add_theme_font_size_override("font_size", afs)
	var text_w: float = min(font.get_string_size(disp, HORIZONTAL_ALIGNMENT_LEFT, -1, afs).x, avail)
	var group_w: float = text_w + icon_gap + icon_size.x
	var gx: float = _BODY_CENTER_X - group_w * 0.5

	var text_x: float = gx + icon_size.x + icon_gap if icon_at_left else gx
	var icon_x: float = gx if icon_at_left else gx + text_w + icon_gap
	label.offset_left = text_x
	label.offset_right = text_x + text_w

	if icon != null:
		icon.position = Vector2(icon_x, _BODY_CENTER_Y - icon_size.y * 0.5)


## 改文字颜色
func _apply_text_color() -> void:
	if not is_node_ready():
		return
	$Root/Text.add_theme_color_override("font_color", text_color)


func _apply_sub_text() -> void:
	if not is_node_ready():
		return
	_sub_text_label.visible = not sub_text.is_empty()
	_sub_text_label.text = sub_text
	_apply_text_vertical_offset()


func _apply_show_difficult() -> void:
	if not is_node_ready():
		return
	if show_difficult:
		_apply_hard_effect_variant()
	else:
		_clear_hard_effect()

	_apply_diffi_skin()


func _clear_hard_effect() -> void:
	($Root/Bg as Button).self_modulate.a = 1.0
	_apply_shadow_color()
	_hard_diffcult.visible = false
	_hard_effect_stars1.visible = false
	_hard_combined_fire_yellow.visible = false
	_hard_fire_point_yellow.visible = false
	_hard_diffcult2.visible = false
	_hard_diffcult2_red2_fire_point.visible = false
	_stop_hard_sweep_anim()
	_reset_hard_text_offset()


func _reset_hard_text_offset() -> void:
	_apply_text_vertical_offset()


func _resolved_hard_variant() -> int:
	var variant: int = hard_effect_variant if hard_effect_variant in [0, 1, 2, 3, 4] else 0
	return 0 if super_hard else variant


func _apply_text_vertical_offset() -> void:
	var shift: float = 0.0
	if not sub_text.is_empty():
		shift = sub_text_shift_up
	if show_difficult and _resolved_hard_variant() in [3, 4]:
		shift = maxf(shift, hard_text_shift_up)
	_hard_text_label.offset_top = _hard_text_base_offset_top - shift
	_hard_text_label.offset_bottom = _hard_text_base_offset_bottom - shift


func _apply_diffi_skin() -> void:
	var use_super: bool = show_difficult and super_hard
	_hard_box.texture = _SUPER_HARD_BOX_TEX if use_super else _hard_box_base_tex
	_hard_tag_label.text = _SUPER_HARD_TAG_KEY if use_super else _hard_tag_base_text


func _apply_hard_effect_variant() -> void:
	var variant: int = _resolved_hard_variant()

	($Root/Bg as Button).self_modulate.a = 0.0 if variant in [3, 4] else 1.0
	_apply_shadow_color()
	_hard_diffcult.visible = variant in [0, 1, 2]
	_hard_effect_stars1.visible = variant == 1
	_hard_combined_fire_yellow.visible = variant == 2
	_hard_fire_point_yellow.visible = variant == 2
	_hard_diffcult2.visible = variant in [3, 4]
	_hard_diffcult2_red1.visible = variant == 3
	_hard_diffcult2_red2.visible = variant == 4
	_hard_diffcult2_red2_fire_point.visible = variant == 4
	match variant:
		1:
			_play_hard_sweep_anim(&"SweepLight1")
		3:
			_play_hard_sweep_anim(&"SweepLight2")
		_:
			_stop_hard_sweep_anim()
	_apply_text_vertical_offset()


func _play_hard_sweep_anim(anim_name: StringName) -> void:
	if _anim.is_playing() and _anim.current_animation == &"GenericButton":
		return
	if _anim.current_animation != anim_name:
		_anim.play(anim_name)


func _stop_hard_sweep_anim() -> void:
	if _anim.is_playing() and _anim.current_animation == &"GenericButton":
		return

	_anim.stop()
	_anim.play(&"RESET")
	_anim.advance(0)
	_anim.stop()


## 控制阴影显隐
func _apply_show_shadow() -> void:
	if not is_node_ready():
		return
	$Root/Shadow.visible = show_shadow
