// The 3D stage's ground: one quad over the whole town, and every tile looked
// up in `cells` — a WORLD_TILES-square RG8 texture holding each tile's atlas
// cell, built from `TerrainRenderer.cell_art` — then sampled out of the same
// atlas the 2D stage draws from (`TileArt.texture`). The world is in metres
// and a tile is a metre, so the ground position *is* the tile coordinate.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D atlas : filter_nearest, source_color;
uniform sampler2D cells : filter_nearest;
uniform vec2 atlas_cells = vec2(16.0, 8.0);
uniform float tiles = 320.0;

varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 cell = floor(wpos);
	vec2 f = fract(wpos);
	vec2 cxy = floor(texture(cells, (cell + 0.5) / tiles).rg * 255.0 + 0.5);
	ALBEDO = texture(atlas, (cxy + f) / atlas_cells).rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
