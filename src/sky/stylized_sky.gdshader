shader_type sky;

uniform vec3 top_color    : source_color = vec3(0.2, 0.5, 0.9); // zenith
uniform vec3 bottom_color : source_color = vec3(0.6, 0.8, 1.0); // horizon

void sky() {
    // EYEDIR.y goes from -1 (down) to +1 (up)
    float t = clamp(EYEDIR.y, 0.0, 1.0);
    COLOR.rgb = mix(bottom_color, top_color, t);
}
