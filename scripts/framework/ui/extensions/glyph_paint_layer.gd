## 字形独立绘制层：在绘制回调中输出父控件分配的字形表现。
@tool
class_name GlyphPaintLayer
extends Node2D

var host: SingleLineGlyphLabel = null # 创建本层的标签节点；随宿主的内部层树一起释放

var layer_kind: int = SingleLineGlyphLabel.LayerKind.BODY # 本节点只画阴影、描边或字身中的一种


## 把当前层的绘制目标回传宿主；字形布局与样式仍由宿主统一计算，子节点只提供独立画布。
func _draw() -> void:
	if host != null:
		host.paint_layer(self, layer_kind)
