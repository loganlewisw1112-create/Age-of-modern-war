shader_type canvas_item;
// G7 DRONE7 drone feed: greyscale or thermal (cold terrain dark; hot units are drawn on top by drone_cam.gd),
// row jitter + grain growing with link noise, vignette, and a LINK LOST static wash. Display only.

uniform int mode = 0;            // 0 greyscale, 1 thermal
uniform float noise_amt = 0.05;  // 0..1 link noise (distance + jamming)
uniform float lost = 0.0;        // 0..1 static wash (LINK LOST)
uniform float t = 0.0;           // seconds (animates grain)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float n_amt = clamp(noise_amt, 0.0, 1.0);
	float row = floor(uv.y * 180.0);
	uv.x += (hash(vec2(row, floor(t * 24.0))) - 0.5) * n_amt * n_amt * 0.06;
	vec4 c = texture(TEXTURE, uv);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 o;
	if (mode == 1) {
		float warm = smoothstep(0.55, 0.95, l);
		o = vec3(0.06 + l * 0.18 + warm * 0.25);
	} else {
		o = vec3(0.08 + l * 0.92);
	}
	float g = hash(UV * vec2(640.0, 360.0) + vec2(t * 13.0, t * 7.0));
	o = mix(o, vec3(g), 0.04 + n_amt * 0.55);
	vec2 d = UV - 0.5;
	o *= 1.0 - dot(d, d) * 0.9;
	o = mix(o, vec3(g * 0.85), clamp(lost, 0.0, 1.0));
	COLOR = vec4(o, 1.0);
}
