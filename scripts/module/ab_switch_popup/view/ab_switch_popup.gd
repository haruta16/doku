# 通用提示弹窗：标题 / 正文 / 按钮文案都可覆盖，猫头跟着背景框定位
@tool
class_name AbSwitchPopup
extends UIFrameWindow

# 猫相对背景框顶部的纵向偏移（像素），改完立刻重排
@export var cat_y_offset: float = -350:
	set(v):
		cat_y_offset = v # 写回新值
		_sync_cat() # 立即重排猫的位置

# ---- 子节点引用（@onready：进场景树后才可用） ----
@onready
var _popup_text_txt: Label = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Content/Panel/PopUpText # 正文
@onready var _title_txt: Label = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Title/Text # 标题
@onready var _btn: Control = $Content/CenterContainer/BgSizeBox/Bg/BgVBox/Btn # 确认按钮（带 btn_text 属性）
@onready var _bg: PanelContainer = $Content/CenterContainer/BgSizeBox/Bg # 背景框：尺寸变化时要重排猫
@onready var _cat_dialog: Control = $Content/CatDialog # 探头猫


# ================= 生命周期 =================
func _ready() -> void:
	# 背景框缺失就没法定位
	if not is_instance_valid(_bg):
		return
	# 背景框尺寸一变就重排猫
	_bg.item_rect_changed.connect(_sync_cat)
	# 编辑器里开每帧刷新，方便所见即所得
	if Engine.is_editor_hint():
		set_process(true)
	# 等布局算完再排第一次
	call_deferred("_sync_cat")


# 编辑器专用：每帧刷新猫的位置（运行时不需要）
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_cat()


# 把猫贴到背景框顶部：逐级累加父节点 y（各级锚点不同，不能用全局坐标）
func _sync_cat() -> void:
	# 节点未就绪时跳过（@export 的 setter 可能提前调用）
	if not is_node_ready():
		return
	# 背景框或猫缺失时跳过
	if not is_instance_valid(_bg) or not is_instance_valid(_cat_dialog):
		return

	var bgsizebox: Control = _bg.get_parent() as Control # 承载背景框的容器
	var center_container: Control = bgsizebox.get_parent() as Control # 居中容器
	var bg_top: float = center_container.position.y + bgsizebox.position.y + _bg.position.y
	# 只改 y，x 交给场景布局
	_cat_dialog.position.y = bg_top + cat_y_offset


# 打开：三个参数都可选，非空才覆盖场景里的默认文案
func on_show(params: Dictionary = {}) -> void:
	# 正文文案
	var text: String = params.get("text", "")
	if not text.is_empty():
		_popup_text_txt.text = text

	# 标题文案
	var title: String = params.get("title", "")
	if not title.is_empty():
		_title_txt.text = title

	# 按钮文案
	var btn_text: String = params.get("btn_text", "")
	if not btn_text.is_empty():
		_btn.set("btn_text", btn_text)


# 点确认按钮：关闭自己
func _on_action_pressed() -> void:
	UIManager.hide_ui(get_ui_name())


# 点关闭按钮：关闭自己
func _on_close_pressed() -> void:
	UIManager.hide_ui(get_ui_name())
