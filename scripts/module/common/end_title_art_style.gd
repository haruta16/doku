## 结算标题样式工具：缓存原始样式，并按实验切换标题美术属性。
extends RefCounted
class_name EndTitleArtStyle

const _TRACKED_PROPS: Array[String] = [
	"outline_thickness",
	"outline_color",
	"outline_gradient_enabled",
	"gradient_enabled",
	"body_color",
	"shadow_color",
	"shadow_thickness",
	"shadow_gradient_enabled",
	"letter_spacing",
]


static func snapshot(title_up: SingleLineGlyphLabel) -> Dictionary:
	var snap: Dictionary = {}
	if title_up == null:
		return snap
	for prop: String in _TRACKED_PROPS:
		snap[prop] = title_up.get(prop)
	return snap


static func apply(
	title_under: CanvasItem,
	title_up: SingleLineGlyphLabel,
	snapshot_props: Dictionary,
	legacy: Dictionary
) -> void:
	var optimized: bool = ABTestManager.art_game_end_title.is_title_quality_optimized()
	if title_under != null:
		title_under.visible = optimized
	if title_up == null:
		return

	if snapshot_props.is_empty():
		snapshot_props.merge(snapshot(title_up))
	if optimized:
		_restore(title_up, snapshot_props)
	else:
		_apply_legacy(title_up, legacy)


static func _restore(title_up: SingleLineGlyphLabel, snapshot_props: Dictionary) -> void:
	if snapshot_props.is_empty():
		push_error("EndTitleArtStyle: snapshot 为空,实验组样式无法还原(页面 _ready 漏调 snapshot?)")
		return
	for prop: String in _TRACKED_PROPS:
		if snapshot_props.has(prop):
			title_up.set(prop, snapshot_props[prop])


static func _apply_legacy(title_up: SingleLineGlyphLabel, legacy: Dictionary) -> void:
	title_up.outline_thickness = int(legacy.get("outline_thickness", 0))
	title_up.outline_color = legacy.get("outline_color", Color.BLACK)
	title_up.outline_gradient_enabled = false

	title_up.gradient_enabled = false
	title_up.body_color = Color.WHITE

	title_up.shadow_gradient_enabled = false
	title_up.shadow_color = Color(0.0, 0.0, 0.0, 0.0)
	title_up.shadow_thickness = 0

	title_up.letter_spacing = 0.0
