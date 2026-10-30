shader_type canvas_item;

uniform float disabled = 0.0;

void fragment() {
	float luminance = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(COLOR.rgb, vec3(luminance), disabled);
}
