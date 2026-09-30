shader_type spatial;
// Gras, Schilf und Blumen: Halme wiegen sich im Wind (stärker an der Spitze)
// und schrumpfen zum Rand der Grasfläche hin, damit kein harter Rand sichtbar
// wird. Die Farbe kommt pro Büschel aus der MultiMesh-Instanzfarbe.
render_mode world_vertex_coords, cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform float wind_strength = 0.16;
uniform float wind_speed = 1.5;
uniform vec2 wind_direction = vec2(0.85, 0.35);
uniform float fade_start = 32.0;
uniform float fade_end = 50.0;
uniform bool flowers = false;          // Blütenköpfe nehmen INSTANCE_CUSTOM als Farbe

varying float tip;
varying vec3 tint;

void vertex() {
	tip = clamp(UV.y, 0.0, 1.0);
	vec3 root = MODEL_MATRIX[3].xyz;

	// Zum Rand hin kleiner werden.
	float d = length(root - CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	VERTEX = root + (VERTEX - root) * fade;

	// Wind: langsame Böen über die Fläche plus schnelles Flattern.
	float gust = sin(TIME * wind_speed + root.x * 0.11 + root.z * 0.07) * 0.5 + 0.5;
	gust *= sin(TIME * wind_speed * 0.37 + root.z * 0.05) * 0.35 + 0.65;
	float flutter = sin(TIME * wind_speed * 3.1 + root.x * 1.7 + root.z * 1.3);
	vec2 bend = normalize(wind_direction) * (gust + flutter * 0.18) * wind_strength;
	float h = VERTEX.y - root.y;
	VERTEX.xz += bend * h * tip;
	VERTEX.y -= length(bend) * h * tip * tip * 0.3;

	// Halme wie Boden beleuchten, sonst wirken sie flach und fleckig.
	NORMAL = vec3(0.0, 1.0, 0.0);

	tint = COLOR.rgb;
	if (flowers && UV.x > 1.5) {
		tint = INSTANCE_CUSTOM.rgb;
	}
}

void fragment() {
	float shade = (flowers && UV.x > 1.5) ? 1.0 : mix(0.5, 1.1, tip);
	ALBEDO = tint * shade;
	ROUGHNESS = 0.85;
	BACKLIGHT = tint * 0.35;
}
