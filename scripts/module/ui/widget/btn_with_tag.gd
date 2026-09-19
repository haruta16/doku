# 带角标的按钮：@tool 可在编辑器里实时预览；颜色 / 文字等导出属性都带 setter，改完立刻写进子节点
@tool
extends Control

signal tag_pressed # 点击信号；不叫 pressed 是为了不和内置信号重名

# ---- Inspector 可调属性（每个都带 setter，改完立即生效） ----
# 背景色：写进 normal / hover / pressed 三种状态样式盒
@export var bg_color: Color = Color(0.945, 0.576, 0.125, 1):
	set(value):
		bg_color = value
		_apply_bg_color() # 赋值后立即重新应用（编辑器里也立刻看到）

# 阴影颜色：给阴影贴图染色
@export var shadow_color: Color = Color(0.945, 0.576, 0.125, 0.7):
	set(value):
		shadow_color = value
		_apply_shadow_color()

# 按钮文字
@export var btn_text: String = "":
	set(value):
		btn_text = value
		_apply_text()

# 文字颜色
@export var text_color: Color = Color(1, 1, 1, 1):
	set(value):
		text_color = value
		_apply_text_color()

# 是否显示难度小标（场景里的节点名拼作 Diffcult）
@export var show_difficult: bool = true:
	set(value):
		show_difficult = value
		_apply_show_difficult()

# 是否显示底部阴影
@export var show_shadow: bool = true:
	set(value):
		show_shadow = value
		_apply_show_shadow()

# ---- 子节点引用 ----
@onready var _anim: AnimationPlayer = $AnimationPlayer # 按下 / 松开的位移动画


# ================= 生命周期 =================
# 进树：先复制样式盒避免多实例互相污染，再逐项应用导出属性；非编辑器环境才接输入信号
func _ready() -> void:
	_duplicate_styles() # 关键：主题里的 StyleBox 默认是共享资源，必须先 duplicate
	_apply_bg_color()
	_apply_shadow_color()
	_apply_text()
	_apply_text_color()
	_apply_show_difficult()
	_apply_show_shadow()
	if not Engine.is_editor_hint(): # 编辑器里不接信号，否则光是预览也会真的发信号
		$Root/Bg.pressed.connect(_on_bg_pressed)
		$Root/Bg.button_down.connect(_on_bg_button_down)
		$Root/Bg.button_up.connect(_on_bg_button_up)


# 语言切换后重算文字（译文可能变长，要重新缩字号）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_text()


# ================= 按钮回调 =================
# 转发成 tag_pressed
func _on_bg_pressed() -> void:
	tag_pressed.emit()


# 按下：动画播到 PressAndHold 标记（按住期间循环这一段）
func _on_bg_button_down() -> void:
	_anim.play_section_with_markers("GenericButton", &"", &"PressAndHold")


# 松开：从 PressAndHold 标记播到动画结尾
func _on_bg_button_up() -> void:
	_anim.play_section_with_markers("GenericButton", &"PressAndHold", &"")


# ================= 属性应用 =================
# 把三种状态的内置 StyleBoxFlat 各复制一份成本实例独有
func _duplicate_styles() -> void:
	var bg: Button = $Root/Bg
	for state: String in ["normal", "hover", "pressed"]:
		var style := bg.get_theme_stylebox(state) as StyleBoxFlat
		if style:
			bg.add_theme_stylebox_override(state, style.duplicate())


# 把 bg_color 写进三种状态样式盒
func _apply_bg_color() -> void:
	if not is_node_ready(): # setter 可能在 @onready 取到节点之前就被调用
		return
	var bg: Button = $Root/Bg
	for state: String in ["normal", "hover", "pressed"]:
		var style := bg.get_theme_stylebox(state) as StyleBoxFlat
		if style:
			style.bg_color = bg_color


# 给阴影染色（self_modulate 只染自身，不影响子树）
func _apply_shadow_color() -> void:
	if not is_node_ready():
		return
	var shadow: NinePatchRect = $Root/Shadow
	shadow.self_modulate = shadow_color


const _BASE_FONT_SIZE: int = 80 # 初始字号（像素）
const _MIN_FONT_SIZE: int = 40 # 最小字号（像素）


# 写文字，并从 80 起每次降 4 号，直到宽度塞得下或降到 40
func _apply_text() -> void:
	if not is_node_ready():
		return
	var label: Label = $Root/Text
	label.text = btn_text
	var fs: int = _BASE_FONT_SIZE
	label.add_theme_font_size_override("font_size", fs)
	while fs > _MIN_FONT_SIZE and label.get_minimum_size().x > label.size.x: # get_minimum_size 是文本自然宽度，label.size 是可用宽度
		fs -= 4
		label.add_theme_font_size_override("font_size", fs)


# 改文字颜色
func _apply_text_color() -> void:
	if not is_node_ready():
		return
	$Root/Text.add_theme_color_override("font_color", text_color)


# 控制难度小标显隐
func _apply_show_difficult() -> void:
	if not is_node_ready():
		return
	$Root/Diffcult.visible = show_difficult


# 控制阴影显隐
func _apply_show_shadow() -> void:
	if not is_node_ready():
		return
	$Root/Shadow.visible = show_shadow
