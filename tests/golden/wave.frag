#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
out vec4 fragColor;

#define BRIGHTNESS 0.80

// Animated "water" ripple: the screen sways gently over time
vec3 effect(vec3 c, vec2 uv) {
    vec2 o;
    o.x = 0.004 * sin(uv.y * 30.0 + time * 2.0);
    o.y = 0.004 * cos(uv.x * 30.0 + time * 2.0);
    return texture(tex, uv + o).rgb;
}

void main() {
    vec4 src = texture(tex, v_texcoord);
    vec3 c = effect(src.rgb, v_texcoord);
    c *= BRIGHTNESS;
    fragColor = vec4(c, src.a);
}
