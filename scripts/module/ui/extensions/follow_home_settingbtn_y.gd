# 跟随节点：让父 Control 的纵向位置对齐首页「设置按钮」的 Y，数据来自 HomeSettingAnchor 的广播
class_name FollowHomeSettingBtnY
extends Node


# 进树：父节点必须是 Control；订阅自身可见性变化与锚点变化，并先对齐一次
func _ready() -> void:
	var host := get_parent() as Control
	if host == null:
		push_error("FollowHomeSettingBtnY: 父节点不是 Control，无法跟随")
		return
	host.visibility_changed.connect(_on_sync_requested)
	HomeSettingAnchor.anchor_changed.connect(_on_anchor_changed)
	_on_sync_requested()


# 锚点变化回调：参数用不上，统一走同步流程
func _on_anchor_changed(_y: float) -> void:
	_on_sync_requested()


# 同步：不可见或还没有锚点时跳过；等一帧布局稳定后按中心点差值平移 offset_top / offset_bottom
func _on_sync_requested() -> void:
	var host := get_parent() as Control
	if host == null or not host.is_visible_in_tree():
		return
	if not HomeSettingAnchor.has_value():
		return

	await get_tree().process_frame # 等一帧，让父容器布局算完再读 global_position
	if not is_instance_valid(host) or not host.is_visible_in_tree():
		return
	if not HomeSettingAnchor.has_value():
		return
	var cur_center_y: float = host.global_position.y + host.size.y * 0.5
	var delta: float = HomeSettingAnchor.get_settingbtn_y() - cur_center_y
	if absf(delta) < 0.5: # 差值小于 0.5 像素就不动，避免来回抖动
		return
	host.offset_top += delta # 上下偏移同时加同样的量 = 整体平移，高度不变
	host.offset_bottom += delta
