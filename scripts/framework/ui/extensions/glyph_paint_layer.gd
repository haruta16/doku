## 字形独立绘制层：在绘制回调中输出父控件分配的字形表现。
@tool
class_name GlyphPaintLayer
extends Node2D

var host: SingleLineGlyphLabel = null

var layer_kind: int = SingleLineGlyphLabel.LayerKind.BODY


func _draw() -> void:
	if host != null:
		host.paint_layer(self, layer_kind)
