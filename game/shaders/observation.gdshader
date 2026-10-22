shader_type spatial;
// Single fog pass: one full-screen quad, drawn after the opaque pass, multiplies the
// frame. It rebuilds each opaque pixel's TRUE world XZ from the depth buffer, so walls,
// props, doors and elevated decks sample the fog at their real position (as the old
// per-mesh overlay did). Revealing simply hides the quad.
render_mode unshaded, blend_mul, depth_draw_never, depth_test_disabled, cull_disabled;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D observation : filter_linear, repeat_disable;
uniform sampler2D exploration : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(24.0, 20.0);
// Displayed actors (x, z, floor y, unused): visible actors are always seen, but the sight cone only
// starts at the unit, so their disc/shoulders would otherwise fall outside it. Only pixels
// above the floor (disc sits +0.225 over the actor root, floor +0.2) are lifted, so the
// surrounding floor gets no glow here. An enemy the polygons do not cover gets a small wall-clipped
// sight fan drawn on the CPU into the CurrentSight viewport instead (world_view._update_sight_pools).
uniform vec4 actors[24];
uniform int actor_count = 0;
void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
void fragment() {
    float depth = texture(depth_tex, SCREEN_UV).x;
    // Compatibility depth is OpenGL [0,1] -> NDC z = depth * 2 - 1.
    vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
    vec2 uv = world.xz / map_size;
    // GPU-rasterized polygon coverage, antialiased at texture resolution.
    // Neither current sight nor exploration comes from square world cells.
    // Four subpixel samples work in WebGL/Compatibility (2D MSAA does not).
    // Reconstructed positions jump at depth edges, so the tap spread is capped
    // to ~2 texels instead of trusting the raw derivatives.
    vec2 limit = 2.0 / vec2(textureSize(observation, 0));
    vec2 dx = clamp(dFdx(uv) * 0.25, -limit, limit);
    vec2 dy = clamp(dFdy(uv) * 0.25, -limit, limit);
    float sight = (texture(observation, uv - dx - dy).a + texture(observation, uv + dx - dy).a
        + texture(observation, uv - dx + dy).a + texture(observation, uv + dx + dy).a) * 0.25;
    float memory = (texture(exploration, uv - dx - dy).a + texture(exploration, uv + dx - dy).a
        + texture(exploration, uv - dx + dy).a + texture(exploration, uv + dx + dy).a) * 0.25;
    for (int i = 0; i < 24; i++) {
        if (i >= actor_count) break;
        if (world.y - actors[i].z > 0.212) sight = max(sight, 1.0 - smoothstep(0.54, 0.64, distance(world.xz, actors[i].xy)));
    }
    vec2 known = vec2(sight, memory);
    // Multiply the rendered environment: retain surface detail and lighting
    // while separating unobserved terrain from the live observation.
    // Door Kickers feel: unseen is near-black (luminance ~0.22, slightly cool,
    // low saturation) so room structure is only faintly readable; explored
    // ground is ~0.47 and live sight is untouched (1.0). The gap is in
    // BRIGHTNESS, not just hue, so unseen vs remembered stays legible for
    // colour-blind players (the L5 fix this layout descends from).
    vec3 unseen_tint = vec3(0.20, 0.22, 0.26);
    vec3 remembered_tint = vec3(0.38, 0.49, 0.58);
    vec3 hidden_tint = mix(unseen_tint, remembered_tint, known.g);
    vec3 fogged = mix(hidden_tint, vec3(1.0), known.r);
    // Pixels with no geometry (clear colour) are never fogged.
    ALBEDO = depth >= 0.99999 ? vec3(1.0) : fogged;
    ALPHA = 1.0;
}
