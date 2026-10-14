// The building kit's materials. One shader, a `part` per material name the
// kit exports: siding and shingle are a painted grey texture (`FacadeArt`)
// times a house's colour, brick is its own colour, trim is one of the
// style table's trim colours, glass and plaster are flat. A piece in a
// MultiMesh carries its house's colours as INSTANCE_CUSTOM (siding rgb,
// trim index in a); a roof, one mesh per house, carries them as uniforms.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// 0 siding, 1 brick, 2 trim, 3 glass, 4 plaster, 5 shingle.
uniform int part = 0;
uniform sampler2D tex : filter_nearest, repeat_enable, source_color;
uniform vec4 flat_color : source_color = vec4(1.0);
// The house's colour for a piece outside a MultiMesh (a roof's shingle, its
// gable's siding, its fascia's trim).
uniform vec4 tint : source_color = vec4(1.0);
uniform bool per_instance = false;
// The style table's trim colours, already linear.
uniform vec4 trims[8];

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 c = flat_color.rgb;
	vec3 t = per_instance ? custom.rgb : tint.rgb;
	if (part == 0 || part == 5) {
		c = texture(tex, UV).rgb * t;
	} else if (part == 1) {
		c = texture(tex, UV).rgb;
	} else if (part == 2) {
		c = per_instance ? trims[int(custom.a + 0.5)].rgb : tint.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
