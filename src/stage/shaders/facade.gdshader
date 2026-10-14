// The building parts' materials (`FacadeArt`). Flat colour, the Synty way:
// a part's material name says what it is, and the shader's `part` says how
// it is coloured. Siding, trim and roof take a house's style — in a
// MultiMesh from INSTANCE_CUSTOM.r (the style's index into the three
// tables), on a one-off mesh from `tint` — and everything else is the
// swatch it was exported with (`flat_color`).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// 0 siding, 1 a fixed swatch, 2 trim, 5 roof.
uniform int part = 1;
uniform vec4 flat_color : source_color = vec4(1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform bool per_instance = false;
// The style tables, already linear.
uniform vec4 sidings[8];
uniform vec4 trims[8];
uniform vec4 roofs[8];

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 c = flat_color.rgb;
	if (part == 0 || part == 2 || part == 5) {
		if (per_instance) {
			int i = int(custom.r + 0.5);
			c = part == 0 ? sidings[i].rgb : (part == 2 ? trims[i].rgb : roofs[i].rgb);
		} else {
			c = tint.rgb;
		}
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
