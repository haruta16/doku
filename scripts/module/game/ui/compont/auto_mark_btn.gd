# 自动标记按钮：两个 Sprite2D 表示标记/未标记图标，真正的点击由覆盖其上的透明 Button 接收
class_name AutoMarkBtn
extends Control

# 点击信号：带回点击前的标记状态，调用方据此决定标记还是取消
signal pressed_with_state(is_marked_before: bool)

# ---- 子节点引用（@onready） ----
@onready var _btn_mark: Sprite2D = $BtnAutoMark # 未标记状态图标
@onready var _btn_unmark: Sprite2D = $BtnAutoUnMark # 已标记状态图标
@onready var _hit: Button = $Hit # 命中区域，真正接收点击

# ---- 运行时状态 ----
var _is_marked: bool = false # 是否已标记


# 进树后同步显示并接上点击
func _ready() -> void:
	_apply_visual()
	_hit.pressed.connect(_on_hit_pressed)


# 收到点击：把点击前的状态一起发出去
func _on_hit_pressed() -> void:
	pressed_with_state.emit(_is_marked)


# 外部设置标记态；值没变就不刷新
func set_marked(marked: bool) -> void:
	if _is_marked == marked:
		return
	_is_marked = marked
	_apply_visual()


# 当前是否处于已标记态
func is_marked() -> bool:
	return _is_marked


# 左右镜像（用于镜像布局的棋盘）
func set_flip_h(flip: bool) -> void:
	if _btn_mark != null:
		_btn_mark.flip_h = flip
	if _btn_unmark != null:
		_btn_unmark.flip_h = flip


# 按 _is_marked 切换两个图标的显隐
func _apply_visual() -> void:
	if _btn_mark != null:
		_btn_mark.visible = not _is_marked
	if _btn_unmark != null:
		_btn_unmark.visible = _is_marked
