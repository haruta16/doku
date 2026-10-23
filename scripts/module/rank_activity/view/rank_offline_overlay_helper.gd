## 排行入口的离线覆盖层助手；统一创建覆盖层并根据离线状态刷新显示。

class_name RankOfflineOverlayHelper
extends RefCounted

const _OVERLAY_SCENE: PackedScene = preload(
	"res://scripts/module/rank_activity/ui/other/rank_offline_overlay.tscn"
)

const _ORIG_MOD_META: StringName = &"_rank_offline_orig_mod"

const NO_DIM_META: StringName = &"_rank_offline_no_dim"


static func is_offline_mode() -> bool:
	return not UniKitManager.is_online()


static func attach(parent: Control, wifi_size: float) -> Control:
	var overlay: Control = _OVERLAY_SCENE.instantiate()
	overlay.anchor_left = 0.0
	overlay.anchor_top = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.offset_left = 0.0
	overlay.offset_top = 0.0
	overlay.offset_right = 0.0
	overlay.offset_bottom = 0.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	parent.add_child(overlay)

	var wifi: Control = overlay.get_node("WifiIcon")
	var half: float = wifi_size / 2.0
	wifi.custom_minimum_size = Vector2(wifi_size, wifi_size)
	wifi.offset_left = -half
	wifi.offset_top = -half
	wifi.offset_right = half
	wifi.offset_bottom = half
	return overlay


static func refresh(overlay: Control, is_offline: bool, dim: bool = true) -> void:
	if overlay == null:
		return
	overlay.visible = is_offline
	var parent: Node = overlay.get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child == overlay:
			continue
		if not (child is CanvasItem):
			continue
		var ci: CanvasItem = child
		if ci.has_meta(NO_DIM_META):
			continue
		if is_offline and dim:
			if not ci.has_meta(_ORIG_MOD_META):
				ci.set_meta(_ORIG_MOD_META, ci.modulate)
				ci.modulate = ci.modulate * Color(0.4, 0.4, 0.4, 1.0)
		else:
			if ci.has_meta(_ORIG_MOD_META):
				ci.modulate = ci.get_meta(_ORIG_MOD_META)
				ci.remove_meta(_ORIG_MOD_META)
