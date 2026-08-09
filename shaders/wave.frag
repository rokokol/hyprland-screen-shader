// label: Wave
// emoji: 🌊
// order: 110
// animated: yes
// samples: yes
// Animated "water" ripple: the screen sways gently over time
vec3 effect(vec3 c, vec2 uv) {
    vec2 o;
    o.x = 0.004 * sin(uv.y * 30.0 + time * 2.0);
    o.y = 0.004 * cos(uv.x * 30.0 + time * 2.0);
    return texture(tex, uv + o).rgb;
}
