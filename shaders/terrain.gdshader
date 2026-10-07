shader_type spatial;
// Gelände: Grundfarbe aus den Vertexfarben (bereits linear), darüber feine
// Bodenstruktur aus einer Rauschtextur. An steilen Hängen wird die Textur
// seitlich projiziert, damit sie nicht in Streifen verzerrt.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform float micro_scale = 0.35;      // feine Körnung (pro Meter)
uniform float macro_scale = 0.011;     // großflächige Helligkeitsflecken
uniform float micro_strength = 0.32;
uniform float micro_fade = 110.0;      // ab dieser Entfernung keine Körnung mehr

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 n = abs(world_normal);

	float top = texture(detail_noise, world_pos.xz * micro_scale).r;
	float side_x = texture(detail_noise, world_pos.zy * micro_scale * 0.6).r;
	float side_z = texture(detail_noise, world_pos.xy * micro_scale * 0.6).r;
	float steep = 1.0 - smoothstep(0.55, 0.85, n.y);
	float side = (side_x * n.x + side_z * n.z) / max(n.x + n.z, 0.001);
	float micro = mix(top, side, steep);

	float macro = texture(detail_noise, world_pos.xz * macro_scale).r;

	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(micro_fade * 0.35, micro_fade, dist);
	float shade = 1.0 + (micro - 0.5) * 2.0 * micro_strength * near;
	shade *= 0.86 + macro * 0.28;
	// Fels bekommt etwas mehr Kontrast
	shade = mix(shade, shade * (0.8 + side * 0.4), steep * near);

	ALBEDO = base * shade;
	// Schnee (sehr hell) glänzt leicht, alles andere ist stumpf.
	float bright = smoothstep(0.6, 0.85, dot(base, vec3(0.333)));
	ROUGHNESS = mix(0.94, 0.6, bright);
	SPECULAR = mix(0.2, 0.45, bright);
}
