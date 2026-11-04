## 全局模态遮罩的显示与交接。窗口选择、生命周期和层级栈由 UIWindowManager 决定。
## 只接收普通 Control 和透明度，不读取页面注册表，也不调用产品单例。
class_name UIModalMask
extends Node

var _primary: ColorRect # 当前生效的黑色遮罩节点；显示/交接时由管理器决定其目标窗口。
var _secondary: ColorRect # 交叉淡化的接班遮罩；多个模态窗口交接时可先淡入下一个目标。
var _primary_tween: Tween # 主遮罩淡出/改透明度的补间，重入交接前先停止。
var _secondary_tween: Tween # 副遮罩淡入补间；完成交接时可提升为主位。
var _requests: int = 0 # 已申请且尚未完成关闭的模态窗口数；遮罩暂时不可见不代表请求归零。


## 返回尚未释放的模态请求数；用于检查窗口开关是否成对，不等同于当前可见遮罩数量。
func request_count() -> int:
	return _requests


## 新显示增加一个请求；关闭中重开仍是原请求，只恢复被中断的遮罩。
func show_for(parent: Node, opacity: float, reopening: bool) -> void:
	if not reopening:
		_requests += 1
	_promote_secondary()
	if not is_instance_valid(_primary):
		_primary = _create_rect(parent, "_GlobalMask")
	_stop_primary_tween()
	_primary.color = Color(0, 0, 0, opacity)
	_primary.visible = true


## 关闭开始时过渡，真正隐藏完成前仍保留请求数，允许中途重开。
func begin_close(next_window: Control, next_opacity: float, duration: float) -> void:
	if not is_instance_valid(_primary) or not _primary.visible:
		return
	if _requests <= 1 or not is_instance_valid(next_window):
		_fade_out(duration)
		return
	_stop_secondary_tween()
	if not is_instance_valid(_secondary):
		_secondary = _create_rect(_primary.get_parent(), "_GlobalMask2")
	_position_below(_secondary, next_window)
	_secondary.color = Color(0, 0, 0, 0)
	_secondary.visible = true
	_fade_out(duration)
	if duration <= 0.0:
		_secondary.color.a = next_opacity
		return
	_secondary_tween = create_tween()
	_secondary_tween.tween_property(_secondary, "color:a", next_opacity, duration)


## 仅由本次关闭成功的调用方释放；旧的异步关闭不得走到这里。
func finish_close(top_window: Control, top_opacity: float) -> void:
	_requests = maxi(0, _requests - 1)
	_promote_secondary()
	# 交接期间目标可能已关闭或刚从全屏遮挡恢复，必须以完成时的目标为准。
	restack(top_window, top_opacity)


## 将显示稳定到实际目标；没有可见模态时隐藏，但仍保留被遮挡窗口的请求。
func restack(window: Control, opacity: float) -> void:
	_stop_primary_tween()
	_stop_secondary_tween()
	if is_instance_valid(_secondary):
		_secondary.visible = false
	if not is_instance_valid(_primary):
		return
	if _requests == 0 or not is_instance_valid(window):
		_primary.visible = false
		return
	_primary.color = Color(0, 0, 0, opacity)
	_position_below(_primary, window)
	_primary.visible = true


## 创建铺满父场景的黑色输入遮罩；STOP 吞掉点击，绝对 z 由后续定位设置。
func _create_rect(parent: Node, rect_name: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = rect_name
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.z_as_relative = false
	parent.add_child(rect)
	return rect


## 同时调整绘制 z 和同父节点顺序，让遮罩视觉与 GUI 命中都位于目标窗口下面。
func _position_below(rect: ColorRect, window: Control) -> void:
	rect.z_index = window.z_index - 1
	var parent: Node = rect.get_parent()
	if parent != null and window.get_parent() == parent:
		var target: int = window.get_index()
		if rect.get_index() < target:
			target -= 1
		parent.move_child(rect, target)


## 结束旧主补间后淡出当前主遮罩；完成回调持有本次 fading，避免主副交换后隐藏错对象。
func _fade_out(duration: float) -> void:
	_stop_primary_tween()
	if duration <= 0.0:
		_primary.visible = false
		return
	var fading: ColorRect = _primary
	_primary_tween = create_tween()
	_primary_tween.tween_property(fading, "color:a", 0.0, duration)
	_primary_tween.tween_callback(func() -> void:
		if is_instance_valid(fading):
			fading.visible = false
	)


## 完成或打断交叉淡化时，副遮罩接替主位；旧主位留待下一次复用。
func _promote_secondary() -> bool:
	if not is_instance_valid(_secondary) or not _secondary.visible:
		return false
	_stop_primary_tween()
	_stop_secondary_tween()
	var previous: ColorRect = _primary
	_primary = _secondary
	_secondary = previous
	if is_instance_valid(previous):
		previous.visible = false
	return true


## 停止并清空主遮罩动画句柄，防止旧动画继续覆盖新交接状态。
func _stop_primary_tween() -> void:
	if _primary_tween != null and _primary_tween.is_valid():
		_primary_tween.kill()
	_primary_tween = null


## 停止并清空副遮罩动画句柄；后续可重新分配副位或提升为主位。
func _stop_secondary_tween() -> void:
	if _secondary_tween != null and _secondary_tween.is_valid():
		_secondary_tween.kill()
	_secondary_tween = null


## 管理器退出时停两路动画并释放遮罩节点；节点可能随 current_scene 提前释放，逐一检查有效性。
func _exit_tree() -> void:
	_stop_primary_tween()
	_stop_secondary_tween()
	# current_scene 可先于管理器释放；失效引用不能先放进类型化数组再校验。
	if is_instance_valid(_primary):
		_primary.queue_free()
	if is_instance_valid(_secondary):
		_secondary.queue_free()


## 判断窗口是否在可见且有足够透明度的主遮罩下方；只是当前视觉覆盖判断，不是窗口生命周期状态。
func covers_window(window: Control) -> bool:
	return is_instance_valid(window) and is_instance_valid(_primary) and _primary.visible and _primary.color.a > 0.01 and window.z_index < _primary.z_index


## 改变当前可见遮罩透明度；先接管正在交叉淡化的副位，避免两路 tween 同时写 alpha。
func set_opacity(opacity: float, duration: float = 0.0) -> void:
	if not is_instance_valid(_primary) or not _primary.visible:
		return
	_promote_secondary()
	_stop_primary_tween()
	if duration <= 0.0:
		_primary.color.a = clampf(opacity, 0.0, 1.0)
	else:
		_primary_tween = create_tween()
		_primary_tween.tween_property(_primary, "color:a", clampf(opacity, 0.0, 1.0), duration)
