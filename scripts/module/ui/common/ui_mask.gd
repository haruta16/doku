# 全局输入遮罩：引用计数式的「挡点击」开关；只挡输入不做视觉（带视觉的遮罩在 UIManager 里）
# 调用方在长动画 / 异步流程前 acquire、结束后 release（如自动通关演示）
class_name UIMask
extends RefCounted

static var _ref_count: int = 0 # 引用计数；>0 期间遮罩存在
static var _blocker: Control = null # 遮罩节点（静态，全局唯一）


# 加一次引用；从 0 变 1 时才真正建出遮罩
static func acquire() -> void:
	_ref_count += 1
	if _ref_count == 1:
		_show()


# 减一次引用；减到 0 才拆遮罩，计数为负时兜底归零
static func release() -> void:
	_ref_count -= 1
	if _ref_count <= 0:
		_ref_count = 0
		_hide()


# 创建全屏透明 Control 吞掉所有输入；已存在则什么都不做
static func _show() -> void:
	if _blocker != null:
		return
	var root: Window = Engine.get_main_loop().root
	_blocker = Control.new()
	_blocker.name = "UIMask"
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # 铺满整个视口
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP # STOP：吃掉落在它身上的鼠标 / 触摸事件
	_blocker.z_index = 4095 # z_index 拉满，z_as_relative=false 表示用绝对层级、不受父节点影响
	_blocker.z_as_relative = false
	root.add_child(_blocker)


# 释放遮罩节点并清空静态引用
static func _hide() -> void:
	if _blocker != null and is_instance_valid(_blocker):
		_blocker.queue_free()
	_blocker = null
