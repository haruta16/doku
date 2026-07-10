class_name FollowHomeSettingBtnY
extends Node












func _ready() -> void :
    var host: = get_parent() as Control
    if host == null:
        push_error("FollowHomeSettingBtnY: 父节点不是 Control，无法跟随")
        return
    host.visibility_changed.connect(_on_sync_requested)
    HomeSettingAnchor.anchor_changed.connect(_on_anchor_changed)
    _on_sync_requested()


func _on_anchor_changed(_y: float) -> void :
    _on_sync_requested()


func _on_sync_requested() -> void :
    var host: = get_parent() as Control
    if host == null or not host.is_visible_in_tree():
        return
    if not HomeSettingAnchor.has_value():
        return

    await get_tree().process_frame
    if not is_instance_valid(host) or not host.is_visible_in_tree():
        return
    if not HomeSettingAnchor.has_value():
        return
    var cur_center_y: float = host.global_position.y + host.size.y * 0.5
    var delta: float = HomeSettingAnchor.get_settingbtn_y() - cur_center_y
    if absf(delta) < 0.5:
        return
    host.offset_top += delta
    host.offset_bottom += delta
