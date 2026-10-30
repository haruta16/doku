shader_type canvas_item;
render_mode unshaded;

// 火焰继续简化：将当前 3 外焰 + 3 内焰固化到一次 Shader 绘制。

/** 外焰颜色。 */
uniform vec4 outer_color : source_color = vec4(0.9647059, 0.44313726, 0.30980393, 1.0);

/** 内焰颜色。 */
uniform vec4 inner_color : source_color = vec4(1.0, 0.54999995, 0.39999998, 1.0);

/** 六份火焰的整体速度倍率。 */
uniform float global_speed : hint_range(0.0, 3.0, 0.05) = 1.0;

/** 三团外焰交界处的圆角融合宽度。0 为原始硬并集。 */
uniform float outer_join_melt : hint_range(0.0, 0.3, 0.005) = 0.06;

/** 三团内焰交界处的圆角融合宽度。 */
uniform float inner_join_melt : hint_range(0.0, 0.3, 0.005) = 0.04;

/** 最终轮廓抗锯齿宽度。 */
uniform float edge_softness : hint_range(0.0005, 0.05, 0.0005) = 0.004;

const float GROUP_ASPECT = 2.40000003576287;
const int FIRE_COUNT = 6;
const int MAX_PARTICLES = 32;
const float REFERENCE_BASE_WIDTH = 0.38;


float hash_seeded(float value, float seed_value) {
	float seeded_value = value + seed_value * 19.19;
	return fract(sin(seeded_value * 127.1 + 311.7) * 43758.5453);
}


float smooth_min_field(float first, float second, float radius) {
	if (radius <= 0.0001) {
		return min(first, second);
	}
	float factor = clamp(
		0.5 + 0.5 * (second - first) / radius,
		0.0,
		1.0
	);
	return (
		mix(second, first, factor)
		- radius * factor * (1.0 - factor)
	);
}


float ellipse_field(vec2 position, vec2 center, vec2 radius) {
	vec2 safe_radius = max(radius, vec2(0.0001));
	return (
		(length((position - center) / safe_radius) - 1.0)
		* min(safe_radius.x, safe_radius.y)
	);
}


// center.x, center.y, size.x, size.y
vec4 base_data(int index) {
	if (index == 0) return vec4(-0.84, -0.145, 0.405, 0.55);
	if (index == 1) return vec4(0.0, -0.04, 0.9, 0.49);
	if (index == 2) return vec4(0.87, 0.07, 0.35, 0.305);
	if (index == 3) return vec4(0.855, 0.0, 0.32, 0.155);
	if (index == 4) return vec4(-0.03, -0.06, 0.675, 0.39);
	return vec4(-0.84, -0.08, 0.265, 0.32);
}


// speed, seed, breathe, particle_count
vec4 timing_data(int index) {
	if (index == 0) return vec4(0.5, 529.0, 0.085, 14.0);
	if (index == 1) return vec4(0.5, 0.0, 0.035, 18.0);
	if (index == 2) return vec4(0.5, 278.0, 0.035, 18.0);
	if (index == 3) return vec4(1.0, 160.0, 0.035, 18.0);
	if (index == 4) return vec4(0.5, 160.0, 0.035, 18.0);
	return vec4(1.0, 160.0, 0.11, 18.0);
}


// particle_size, travel_height, shrink_power, edge_taper
vec4 particle_data(int index) {
	if (index == 0) return vec4(0.095, 0.91, 0.8, 0.7);
	if (index == 1) return vec4(0.16, 0.88, 0.9, 0.9);
	if (index == 2) return vec4(0.135, 0.57, 0.7, 1.1);
	if (index == 3) return vec4(0.10, 0.35, 0.8, 0.9);
	if (index == 4) return vec4(0.09, 0.66, 1.1, 0.8);
	return vec4(0.135, 0.55, 1.7, 0.9);
}


// sway, branch, wobble, melt
vec4 motion_data(int index) {
	if (index == 0) return vec4(0.06, 0.035, 0.025, 0.12);
	if (index == 1) return vec4(0.06, 0.02, 0.015, 0.105);
	if (index == 2) return vec4(0.02, 0.085, 0.025, 0.11);
	if (index == 3) return vec4(0.06, 0.035, 0.025, 0.125);
	if (index == 4) return vec4(0.06, 0.035, 0.025, 0.10);
	return vec4(0.105, 0.0, 0.01, 0.105);
}


float single_fire_field(vec2 position, int fire_index, float time_value) {
	vec4 base = base_data(fire_index);
	vec4 timing = timing_data(fire_index);
	vec4 particle = particle_data(fire_index);
	vec4 motion = motion_data(fire_index);
	float animation_time = time_value * timing.x;
	float seed_value = timing.y;

	float breathe = 1.0 + sin(
		animation_time * 0.72 + seed_value * 0.37
	) * timing.z;
	vec2 base_size = base.zw;
	vec2 animated_base_size = base_size * vec2(
		1.0 + (breathe - 1.0) * 0.55,
		breathe
	);
	float flame_field = ellipse_field(
		position,
		base.xy,
		animated_base_size
	);

	float horizontal_scale = max(
		base_size.x / REFERENCE_BASE_WIDTH,
		0.25
	);
	float size_and_count_scale = sqrt(horizontal_scale);
	float effective_particle_count = clamp(
		ceil(timing.w * size_and_count_scale),
		4.0,
		float(MAX_PARTICLES)
	);

	for (int particle_index_int = 0; particle_index_int < MAX_PARTICLES; particle_index_int++) {
		if (float(particle_index_int) >= effective_particle_count) {
			continue;
		}
		float particle_index = float(particle_index_int);
		float random_a = hash_seeded(particle_index + 3.1, seed_value);
		float random_b = hash_seeded(particle_index + 17.7, seed_value);
		float random_c = hash_seeded(particle_index + 31.9, seed_value);
		float phase = fract(
			animation_time
			* mix(0.82, 1.18, random_a)
			+ particle_index / effective_particle_count
			+ random_b * 0.25
		);

		float side = random_c < 0.5 ? -1.0 : 1.0;
		float start_width = (
			base_size.x * mix(0.05, 0.95, random_a)
		);
		float guide_width = (
			start_width
			* pow(max(1.0 - phase, 0.0), particle.w)
		);
		float sway_envelope = smoothstep(0.15, 1.0, phase);
		float whole_sway = (
			sin(
				animation_time * mix(0.55, 0.9, random_b)
				+ random_a * TAU
			)
			* motion.x
			* horizontal_scale
			* sway_envelope
		);
		float branch = (
			(random_b * 2.0 - 1.0)
			* motion.y
			* horizontal_scale
			* smoothstep(0.55, 1.0, phase)
		);
		float local_wobble = (
			sin(phase * TAU * 1.5 + random_c * TAU)
			* motion.z
			* horizontal_scale
			* sin(phase * PI)
		);
		vec2 center = vec2(
			base.x
			+ side * guide_width
			+ whole_sway
			+ branch
			+ local_wobble,
			base.y
			- base_size.y * 0.48
			+ phase * particle.y
		);
		float life_scale = pow(
			max(1.0 - phase, 0.0),
			particle.z
		);
		float radius = (
			particle.x
			* size_and_count_scale
			* mix(0.68, 1.32, random_c)
			* life_scale
		);
		float ball_field = length(position - center) - radius;
		flame_field = smooth_min_field(
			flame_field,
			ball_field,
			motion.w * size_and_count_scale
		);
	}
	return flame_field;
}


void fragment() {
	vec2 position = vec2(
		(UV.x - 0.5) * GROUP_ASPECT,
		1.0 - UV.y
	);
	float time_value = TIME * global_speed;

	float outer_field = 1000.0;
	for (int index = 0; index < 3; index++) {
		outer_field = smooth_min_field(
			outer_field,
			single_fire_field(position, index, time_value),
			outer_join_melt
		);
	}

	float inner_field = 1000.0;
	for (int index = 3; index < FIRE_COUNT; index++) {
		inner_field = smooth_min_field(
			inner_field,
			single_fire_field(position, index, time_value),
			inner_join_melt
		);
	}

	float outer_mask = 1.0 - smoothstep(
		-edge_softness,
		edge_softness,
		outer_field
	);
	float inner_mask = 1.0 - smoothstep(
		-edge_softness,
		edge_softness,
		inner_field
	);
	float final_alpha = max(outer_mask, inner_mask);
	vec3 final_color = mix(
		outer_color.rgb,
		inner_color.rgb,
		inner_mask
	);

	vec4 canvas_color = COLOR;
	COLOR = vec4(
		final_color,
		max(outer_color.a * outer_mask, inner_color.a * inner_mask)
		* canvas_color.a
	);
}
