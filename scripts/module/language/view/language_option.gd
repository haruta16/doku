# 语言选项按钮：一行本族语 + 一行副标题，选中态换成绿底并显示勾
class_name LanguageOption
extends Button

# ---- 颜色常量：选中 / 常态两套 ----
const _C_SELECTED_BG: Color = Color(0.2784314, 0.7019608, 0.3419608, 1)  # 选中态背景（绿）
const _C_NORMAL_BG: Color = Color(0.9764706, 0.9254902, 0.88235295, 1)  # 常态背景（米白）
const _C_SELECTED_TEXT: Color = Color(1, 1, 1, 1)  # 选中态主文字（白）
const _C_NORMAL_TEXT: Color = Color(0.5769231, 0.3522559, 0.3522559, 1)  # 常态主文字（深棕）
const _C_SELECTED_SUB: Color = Color(0.5686275, 0.81960785, 0.6039216, 1)  # 选中态副标题（浅绿）
const _C_NORMAL_SUB: Color = Color(0.8156863, 0.69803923, 0.67058825, 1)  # 常态副标题（浅棕）

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready var _native_label: Label = $VBox/NativeLabel  # 本族语名
@onready var _sub_label: Label = $VBox/SubLabel  # 副标题：按当前语言显示的名字
@onready var _check_mark: Control = $CheckMark  # 右上角选中勾


# _ready 只定初始态：副标题可见、勾隐藏；选中与否由 set_selected 决定
func _ready() -> void:
	_sub_label.visible = true
	_check_mark.visible = false


# 填充文案：native_text 是本族语名，sub_text 是按当前语言翻译的名字
func setup(native_text: String, sub_text: String) -> void:
	_native_label.text = native_text
	_sub_label.text = sub_text


# 切换选中态：三种按钮状态都覆盖同一个 StyleBoxFlat，再换文字颜色和勾
func set_selected(selected: bool) -> void:
	# normal/hover/pressed 三态用同一个样式，避免悬停时视觉跳变
	for state: String in ["normal", "hover", "pressed"]:
		# 每次新建样式，不复用，省得改一处影响全部
		var style := StyleBoxFlat.new()
		style.bg_color = _C_SELECTED_BG if selected else _C_NORMAL_BG
		# 圆角 30 像素，与设计稿一致
		style.set_corner_radius_all(30)
		add_theme_stylebox_override(state, style)
	_native_label.add_theme_color_override(
		"font_color", _C_SELECTED_TEXT if selected else _C_NORMAL_TEXT
	)
	_sub_label.add_theme_color_override(
		"font_color", _C_SELECTED_SUB if selected else _C_NORMAL_SUB
	)
	_check_mark.visible = selected
