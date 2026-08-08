#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
out vec4 fragColor;

#define BRIGHTNESS 0.80

// No colour effect — just pass the colour through.
// Needed so brightness-only dimming works without a filter
vec3 effect(vec3 c, vec2 uv) {
    return c;
}

void main() {
    vec4 src = texture(tex, v_texcoord);
    vec3 c = effect(src.rgb, v_texcoord);
    c *= BRIGHTNESS;
    fragColor = vec4(c, src.a);
}
