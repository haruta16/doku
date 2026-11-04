## 字形绘制批次：收集排版后的字形信息，再统一提交绘制。
class_name GlyphBatch
extends RefCounted

enum Layer { SHADOW_OUTLINE, SHADOW, OUTLINE, BODY } # 枚举数值即前后顺序：阴影描边最底，字身最上


## 把 shaped 排版结果展开并追加到 out，origin 是首字基线坐标；仅收集数据，不立即绘制。
## 空白/无有效图形的字仍推进画笔，repeat 表示同一字形需要重复出现的次数。
static func append_shaped(
	out: Array, shaped: RID, origin: Vector2, color: Color, layer: int, outline: int = 0
) -> void:
	var ts: TextServer = TextServerManager.get_primary_interface()
	var x: float = origin.x
	for g: Dictionary in ts.shaped_text_get_glyphs(shaped):
		var rid: RID = g["font_rid"]
		var index: int = g["index"]
		var advance: float = g["advance"]
		for r in int(g["repeat"]):
			if rid.is_valid() and index != 0:
				(
					out
					. append(
						{
							"rid": rid,
							"index": index,
							"pos": Vector2(x, origin.y) + (g["offset"] as Vector2),
							"size": int(g["font_size"]),
							"color": color,
							"layer": layer,
							"outline": outline,
						}
					)
				)
			x += advance


## 按视觉层与字体纹理分组，再逐字形提交绘制命令；不会将整段文字合成一次绘制。
## oversampling 控制栅格精度，unify_raster 大于 0 时统一测栅格字号，逻辑尺寸仍由每项 size 保持。
static func draw(ci: RID, items: Array, oversampling: float, unify_raster: int = 0) -> void:
	if items.is_empty():
		return
	var ts: TextServer = TextServerManager.get_primary_interface()
	var f: float = maxf(oversampling, 0.01)
	# 两级索引：视觉层 → 字体/栅格字号/描边/纹理页；既保持层顺序，又把相同纹理的字聚在一起。
	var layers: Dictionary = {}
	for it: Dictionary in items:
		var logical: int = unify_raster if unify_raster > 0 else int(it["size"])
		# 栅格字号决定图集清晰度；稍后通过画布缩放抵消放大，最终位置和大小仍是逻辑像素。
		var raster: int = maxi(1, roundi(float(logical) * f))
		var outline: int = 0
		if int(it["outline"]) > 0:
			outline = maxi(1, roundi(float(it["outline"]) * float(raster) / float(it["size"])))
		var rid: RID = it["rid"]
		var tex: int = ts.font_get_glyph_texture_idx(rid, Vector2i(raster, outline), it["index"])
		if tex < 0:
			continue
		var layer: int = it["layer"]
		if not layers.has(layer):
			layers[layer] = {}
		var buckets: Dictionary = layers[layer]
		var key := "%d|%d|%d|%d" % [rid.get_id(), raster, outline, tex]
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append([it, raster, outline])
	var layer_keys: Array = layers.keys()
	layer_keys.sort()
	var current_k: float = -1.0
	for layer: int in layer_keys:
		var buckets: Dictionary = layers[layer]
		for key: String in buckets:
			for entry: Array in buckets[key]:
				var it: Dictionary = entry[0]
				var raster: int = entry[1]
				var outline: int = entry[2]
				var k: float = float(it["size"]) / float(raster)
				if not is_equal_approx(k, current_k):
					RenderingServer.canvas_item_add_set_transform(
						ci, Transform2D().scaled(Vector2(k, k))
					)
					current_k = k
				# 画布已经乘了 k；先把位置除以 k，避免提高栅格精度时连排版位置也跟着变化。
				var pos: Vector2 = (it["pos"] as Vector2) / k
				if outline > 0:
					ts.font_draw_glyph_outline(
						it["rid"], ci, raster, outline, pos, it["index"], it["color"], 1.0
					)
				else:
					ts.font_draw_glyph(it["rid"], ci, raster, pos, it["index"], it["color"], 1.0)
	# 恢复单位变换，后续 CanvasItem 绘制不能继承最后一个字形的栅格缩放。
	RenderingServer.canvas_item_add_set_transform(ci, Transform2D())
