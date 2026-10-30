## 近期关卡调试页：把记录的关卡配置绘制成卡片，便于回看选题与交付结果。
class_name RecentLevelsPage
extends UIFrameWindow

const _DEFAULT_COUNT: int = 30
const _CARD_W: float = 320.0
const _THUMB_SIZE: float = 280.0
const _RED: Color = Color(0.906, 0.298, 0.235)
const _GREEN: Color = Color(0.18, 0.702, 0.361)
const _BLUE: Color = Color(0.208, 0.518, 0.894)
const _GRAY: Color = Color(0.545, 0.545, 0.573)

@onready var _grid: GridContainer = $ScrollContainer/Grid
@onready var _title_label: Label = $Header/HBox/TitleLabel


func on_show(params: Dictionary = {}) -> void:
	var count: int = int(params.get("latest_count", _DEFAULT_COUNT))
	if count <= 0:
		count = _DEFAULT_COUNT
	_build(count)


func _build(count: int) -> void:
	for child: Node in _grid.get_children():
		child.queue_free()

	var records: Array[Dictionary] = RecentLevelDebugTracker.get_recent(count)
	_title_label.text = "最近关卡 · 同构检测（%d 关）" % records.size()
	if records.is_empty():
		_grid.add_child(_make_empty_label())
		return

	var sigs: Array = []
	var is_sp: Array[bool] = []
	for rec: Dictionary in records:
		is_sp.append(str(rec.get("source", "")) == "sp")
		var sz: int = int(rec.get("size", 0))
		var min_size: int = NL11504Strategy.large_cluster_min_size(sz, int(rec.get("rank", 0)))
		sigs.append(
			RegionClusterSignature.compute_signatures(rec.get("region_map", []), sz, min_size)
		)

	for i: int in range(records.size()):
		var matched_level: int = -1
		if not is_sp[i]:
			var window_sigs: Array = []
			var window_levels: Array[int] = []
			for j: int in range(records.size()):
				if j == i or is_sp[j]:
					continue
				for cluster: Array in sigs[j] as Array:
					window_sigs.append(cluster)
					window_levels.append(int(records[j].get("level", 0)))
			matched_level = RegionClusterSignature.find_isomorphic_match_group(
				sigs[i], window_sigs, window_levels, RegionClusterSignature.ISO_TOLERANCE_CELLS
			)
		_grid.add_child(_make_card(records[i], is_sp[i], matched_level))


func _make_empty_label() -> Label:
	var lbl := Label.new()
	lbl.text = "暂无记录（进入主线关卡后自动记录）"
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	return lbl


func _make_card(rec: Dictionary, is_sp: bool, matched_level: int) -> Control:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(_CARD_W, 0)
	vbox.add_theme_constant_override("separation", 10)

	var thumb := LevelThumbnail.new()
	thumb.custom_minimum_size = Vector2(_THUMB_SIZE, _THUMB_SIZE)
	thumb.setup(rec.get("region_map", []), int(rec.get("size", 0)))
	vbox.add_child(thumb)

	var sz: int = int(rec.get("size", 0))
	var info_lbl := Label.new()
	info_lbl.text = (
		"Lv%d · %d×%d · %s" % [int(rec.get("level", 0)), sz, sz, str(rec.get("source", "?"))]
	)
	info_lbl.add_theme_font_size_override("font_size", 26)
	info_lbl.add_theme_color_override("font_color", Color(0.118, 0.106, 0.294, 1))
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info_lbl)

	if is_sp:
		vbox.add_child(_make_badge("SP 关卡不检查", _BLUE))
	elif matched_level >= 0:
		vbox.add_child(_make_badge("与 Lv%d 同构" % matched_level, _RED))
	else:
		vbox.add_child(_make_badge("不同构", _GREEN))

	vbox.add_child(
		_make_badge(
			_delivery_label(str(rec.get("iso_check", ""))),
			_delivery_color(str(rec.get("iso_check", "")))
		)
	)

	return vbox


func _delivery_label(iso_check: String) -> String:
	match iso_check:
		"sp":
			return "SP 关卡不检查"
		"matched":
			return "与本关同构"
		"clear":
			return "与本关不同构"
		_:
			return "未检测（非11504分组）"


func _delivery_color(iso_check: String) -> Color:
	match iso_check:
		"sp":
			return _BLUE
		"matched":
			return _RED
		"clear":
			return _GREEN
		_:
			return _GRAY


func _make_badge(text: String, color: Color) -> PanelContainer:
	var badge_panel := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = color
	badge_style.set_corner_radius_all(10)
	badge_style.content_margin_top = 8
	badge_style.content_margin_bottom = 8
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	var badge_lbl := Label.new()
	badge_lbl.text = text
	badge_lbl.add_theme_font_size_override("font_size", 24)
	badge_lbl.add_theme_color_override("font_color", Color.WHITE)
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_panel.add_child(badge_lbl)
	return badge_panel


func _on_back_btn_pressed() -> void:
	UIManager.show_ui(UiName.HOME)
	UIManager.hide_ui(UiName.RECENT_LEVELS)
