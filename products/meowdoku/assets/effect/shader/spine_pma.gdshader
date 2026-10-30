shader_type canvas_item;
render_mode blend_premul_alpha;

// Only for premultiplied Spine atlas textures; keep fix_alpha_border disabled on import.
varying float tint_alpha;

void vertex() {
	tint_alpha = COLOR.a;
}

void fragment() {
	// Texture RGB is already premultiplied; also premultiply slot and CanvasItem opacity.
	COLOR.rgb *= tint_alpha;
}
