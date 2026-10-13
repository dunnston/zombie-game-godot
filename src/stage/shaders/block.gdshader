// A standing tile: a house wall, a roof block, a fence. One MultiMesh of unit
// boxes, each scaled to its height; the top face carries the tile's own atlas
// art (its cell arrives as INSTANCE_CUSTOM.xy) and the sides are that art's
// centre colour, darkened, so a row of walls reads as one wall.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : filter_nearest, source_color;
uniform vec2 atlas_cells = vec2(16.0, 8.0);
uniform float side_dim = 0.6;

varying vec2 wpos;
varying vec3 wnormal;
varying vec2 cell;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cell = INSTANCE_CUSTOM.xy;
}

void fragment() {
	vec2 f = fract(wpos);
	if (wnormal.y > 0.5) {
		ALBEDO = texture(atlas, (cell + f) / atlas_cells).rgb;
	} else {
		ALBEDO = texture(atlas, (cell + vec2(0.5)) / atlas_cells).rgb * side_dim;
	}
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
