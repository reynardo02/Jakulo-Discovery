shader_type spatial;
// Wasser: zwei gegeneinander laufende Normal-Maps für Wellen, Farbe und
// Durchsichtigkeit je nach Wassertiefe, Schaum an der Uferlinie.
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.20, 0.52, 0.56);
uniform vec3 deep_color : source_color = vec3(0.03, 0.14, 0.27);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.96);
uniform float depth_fade = 7.0;         // ab dieser Tiefe (m) volle Tiefenfarbe
uniform float foam_width = 0.7;         // Schaumstreifen am Ufer (m)
uniform float wave_scale_a = 0.035;
uniform float wave_scale_b = 0.09;
uniform vec2 wave_dir_a = vec2(0.012, 0.006);
uniform vec2 wave_dir_b = vec2(-0.010, 0.014);
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz;
	vec3 na = texture(normal_a, uv * wave_scale_a + TIME * wave_dir_a).rgb;
	vec3 nb = texture(normal_b, uv * wave_scale_b + TIME * wave_dir_b).rgb;
	float dist = length(VERTEX);
	// In der Ferne ruhiger, sonst flimmert es.
	NORMAL_MAP = mix(na, nb, 0.5);
	NORMAL_MAP_DEPTH = mix(0.9, 0.25, smoothstep(40.0, 400.0, dist));

	// Wassertiefe entlang des Sichtstrahls aus dem Tiefenpuffer.
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float depth = max(VERTEX.z - view.z, 0.0);

	float t = clamp(depth / depth_fade, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, sqrt(t));

	float fn = texture(foam_noise, uv * 0.18 + TIME * vec2(0.02, 0.01)).r;
	float foam = 1.0 - smoothstep(0.0, foam_width, depth);
	foam *= smoothstep(0.35, 0.65, fn + foam * 0.35);
	col = mix(col, foam_color, foam * 0.85);

	ALBEDO = col;
	ALPHA = clamp(mix(0.35, 0.96, t) + foam * 0.6, 0.0, 1.0);
	ROUGHNESS = mix(0.04, 0.6, foam);
	SPECULAR = 0.55;
	METALLIC = 0.0;
}
