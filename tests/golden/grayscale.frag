#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
out vec4 fragColor;

#define BRIGHTNESS 0.80

// Grayscale (Rec. 709 luminance coefficients)
vec3 effect(vec3 c, vec2 uv) {
    float g = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return vec3(g);
}

void main() {
    vec4 src = texture(tex, v_texcoord);
    vec3 c = effect(src.rgb, v_texcoord);
    c *= BRIGHTNESS;
    fragColor = vec4(c, src.a);
}
