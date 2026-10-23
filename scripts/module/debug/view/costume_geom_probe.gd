## 猫装扮几何探针：遍历 Spine、裁剪和批处理节点，输出布局与渲染诊断信息。
class_name CostumeGeomProbe
extends RefCounted

const _COSTUME_SPINE_NAMES: Array[StringName] = [
	&"CatSpine",
	&"CostumeCat",
	&"CatIcon",
]

const _HOST_NAMES: Array[StringName] = [
	&"CatHead",
	&"CatArea",
	&"CatHolder",
	&"CostumeCatSlot",
	&"CatSlot",
	&"CatAnchor",
	&"CatProgressSlot",
]

const _BATCH_LAYER_NAME: StringName = &"CatBatchLayer"

const _COVERAGE_WARN_RATIO: float = 0.98


static func dump(root: Node) -> String:
	if root == null or not is_instance_valid(root):
		return "[CostumeGeomProbe] root 为空，无法量测"

	var costume_spines: Array[SpineSprite] = []
	var other_spines: Array[SpineSprite] = []
	var batch_layers: Array[Node] = []
	_collect(root, costume_spines, other_spines, batch_layers)

	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		(
			"[CostumeGeomProbe] 视口=%s  外观猫头=%d  其余Spine=%d  合批层=%d"
			% [
				str(_viewport_size(root)),
				costume_spines.size(),
				other_spines.size(),
				batch_layers.size()
			]
		)
	)
	lines.append(
		"  ⚠️ 判据是**视觉中心 / 墨迹矩形**，不是节点框；若在 --headless 下跑，本段几何仍有效但 dump_perf 的 draw call 恒 0"
	)

	lines.append("── ① 外观猫头 ────────────────────────────────")
	if costume_spines.is_empty():
		lines.append("  （无）当前页面没有外观猫头。对照组下这是**预期结果**；实验组下先跑 `costume_dump` 确认分组闸")
	for i in costume_spines.size():
		lines.append_array(_describe_spine(costume_spines[i], i + 1))

	lines.append("── ② 棋盘合批层 ──────────────────────────────")
	if batch_layers.is_empty():
		lines.append(
			"  （无 `%s`）不在棋盘页 / 棋盘尚未 setup / 本盘还没放过猫（真身按需创建，共享层随第一只猫建出）" % String(_BATCH_LAYER_NAME)
		)
	for layer in batch_layers:
		lines.append(_describe_batch_layer(layer))

	lines.append("── ③ 其余 Spine（性能上下文，不做几何分析）────")
	if other_spines.is_empty():
		lines.append("  （无）")
	for spine in other_spines:
		lines.append(
			(
				"  %s  visible_in_tree=%s  batching=%s"
				% [_path_of(spine), str(spine.is_visible_in_tree()), _batching_text(spine)]
			)
		)

	return "\n".join(lines)


static func dump_perf() -> String:
	var draw_calls: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[CostumeGeomProbe] perf 单帧快照（连调 5 次取中位数）")
	lines.append(
		(
			"  draw_calls=%.0f  objects=%.0f  primitives=%.0f"
			% [
				draw_calls,
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			]
		)
	)
	lines.append(
		(
			"  fps=%.2f  process=%.3fms  physics=%.3fms"
			% [
				Performance.get_monitor(Performance.TIME_FPS),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			]
		)
	)
	lines.append(
		(
			"  static_mem=%.2fMB  video_mem=%.2fMB  texture_mem=%.2fMB  buffer_mem=%.2fMB"
			% [
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
			]
		)
	)
	lines.append(
		(
			"  nodes=%.0f  orphan_nodes=%.0f  resources=%.0f"
			% [
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
			]
		)
	)
	if draw_calls <= 0.0:
		(
			lines
			. append(
				"  ⚠️ draw_calls=0 —— 几乎必然是 dummy 渲染后端（--headless）。此时三个 RENDER_TOTAL_*、三项显存与 fps 全是假数据（headless 实测 fps 恒 1.00），换带窗口的运行方式重跑"
			)
		)
	return "\n".join(lines)


static func _batching_text(spine: SpineSprite) -> String:
	if not CellView.engine_supports_spine_batching():
		return "n/a(本引擎无合批能力)"
	return str(spine.batching_enabled)


static func set_batching(root: Node, enabled: bool) -> int:
	if root == null or not is_instance_valid(root):
		return 0
	if not CellView.engine_supports_spine_batching():
		return 0
	var costume_spines: Array[SpineSprite] = []
	var other_spines: Array[SpineSprite] = []
	var batch_layers: Array[Node] = []
	_collect(root, costume_spines, other_spines, batch_layers)
	var changed: int = 0
	for spine in costume_spines:
		spine.batching_enabled = enabled
		changed += 1
	for spine in other_spines:
		spine.batching_enabled = enabled
		changed += 1
	return changed


static func _collect(
	node: Node,
	costume_spines: Array[SpineSprite],
	other_spines: Array[SpineSprite],
	batch_layers: Array[Node]
) -> void:
	if node.name == _BATCH_LAYER_NAME:
		batch_layers.append(node)
	var spine: SpineSprite = node as SpineSprite
	if spine != null:
		if _is_costume_spine(spine):
			costume_spines.append(spine)
		else:
			other_spines.append(spine)
	var children: Array[Node] = node.get_children()
	for child in children:
		_collect(child, costume_spines, other_spines, batch_layers)


static func _is_costume_spine(spine: SpineSprite) -> bool:
	if _COSTUME_SPINE_NAMES.has(spine.name):
		return true
	var parent: Node = spine.get_parent()
	if parent == null:
		return false
	return _HOST_NAMES.has(parent.name) or parent.name == _BATCH_LAYER_NAME


static func _describe_spine(spine: SpineSprite, index: int) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("  [%d] %s" % [index, _path_of(spine)])
	lines.append(
		(
			"      visible_in_tree=%s  modulate.a=%.3f  scale=%s  batching=%s"
			% [
				str(spine.is_visible_in_tree()),
				spine.modulate.a,
				str(spine.scale),
				_batching_text(spine)
			]
		)
	)
	lines.append("      骨架原点(下巴)global_position=%s" % str(spine.global_position))

	if not spine.is_inside_tree():
		lines.append("      ⚠️ 不在场景树里，无法取 global_transform")
		return lines

	var skeleton: SpineSkeleton = spine.get_skeleton()
	if skeleton == null:
		lines.append("      ⚠️ get_skeleton() 返 null —— 骨架资源未就绪（`skeleton_data_res` 没设 / 资源缺失）")
		return lines

	var bounds_local: Rect2 = skeleton.get_bounds()
	if bounds_local.size.x <= 0.0 or bounds_local.size.y <= 0.0:
		lines.append("      ⚠️ get_bounds() 面积为 0 —— 当前姿态没有任何可见 attachment（皮肤套错 / 全 slot 被清空）")
		return lines

	var ink_global: Rect2 = spine.get_global_transform() * bounds_local
	lines.append(
		"      bounds_local=P%s S%s" % [str(bounds_local.position), str(bounds_local.size)]
	)
	lines.append("      墨迹矩形(global)=P%s S%s" % [str(ink_global.position), str(ink_global.size)])
	lines.append("      **视觉中心(global)=%s**  ← 对位就看这一个数" % str(ink_global.get_center()))

	lines.append_array(_describe_clip(spine, ink_global))
	return lines


static func _describe_clip(spine: SpineSprite, ink_global: Rect2) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var clip_window: Rect2 = Rect2()
	var has_window: bool = false
	var clip_paths: PackedStringArray = PackedStringArray()

	var ancestor: Node = spine.get_parent()
	while ancestor != null:
		var control: Control = ancestor as Control
		if control != null and control.is_clipping_contents():
			var rect: Rect2 = control.get_global_rect()
			clip_paths.append("%s S%s" % [_path_of(control), str(rect.size)])
			clip_window = rect if not has_window else clip_window.intersection(rect)
			has_window = true
		ancestor = ancestor.get_parent()

	if not has_window:
		lines.append("      裁剪窗口：无（没有 clip_contents 的 Control 祖先）→ 胡须会整条露在卡片外，确认是否漏了裁剪层")
		return lines

	lines.append(
		(
			"      裁剪窗口=P%s S%s  ← %s"
			% [str(clip_window.position), str(clip_window.size), " ∩ ".join(clip_paths)]
		)
	)

	var cut_left: float = maxf(0.0, clip_window.position.x - ink_global.position.x)
	var cut_top: float = maxf(0.0, clip_window.position.y - ink_global.position.y)
	var cut_right: float = maxf(0.0, ink_global.end.x - clip_window.end.x)
	var cut_bottom: float = maxf(0.0, ink_global.end.y - clip_window.end.y)
	var visible_rect: Rect2 = clip_window.intersection(ink_global)
	var ink_area: float = ink_global.size.x * ink_global.size.y
	var coverage: float = 0.0
	if ink_area > 0.0:
		coverage = (visible_rect.size.x * visible_rect.size.y) / ink_area

	var flag: String = ""
	if coverage < _COVERAGE_WARN_RATIO:
		flag = "  ⚠️ 被裁掉的不止胡须尖，人眼确认裁的是什么"
	lines.append(
		(
			"      被裁像素：left=%.1f right=%.1f top=%.1f bottom=%.1f  可见面积=%.1f%%%s"
			% [cut_left, cut_right, cut_top, cut_bottom, coverage * 100.0, flag]
		)
	)
	return lines


static func _describe_batch_layer(layer: Node) -> String:
	var total: int = 0
	var visible_count: int = 0
	var non_spine: int = 0
	var children: Array[Node] = layer.get_children()
	for child in children:
		var spine: SpineSprite = child as SpineSprite
		if spine == null:
			non_spine += 1
			continue
		total += 1
		if spine.is_visible_in_tree():
			visible_count += 1
	var note: String = ""
	if non_spine > 0:
		note = "  ⚠️ 混入 %d 个非 SpineSprite 子节点 —— 会打断合批 run" % non_spine
	return "  %s  SpineSprite=%d（visible=%d）%s" % [_path_of(layer), total, visible_count, note]


static func _path_of(node: Node) -> String:
	if not node.is_inside_tree():
		return "%s(不在树里)" % String(node.name)
	return String(node.get_path())


static func _viewport_size(root: Node) -> Vector2:
	if not root.is_inside_tree():
		return Vector2.ZERO
	var viewport: Viewport = root.get_viewport()
	if viewport == null:
		return Vector2.ZERO
	return viewport.get_visible_rect().size
