#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
out vec4 fragColor;

#define BRIGHTNESS 0.80

// Animated glitch: jittering RGB split + occasional row shifts
float hash(float n) { return fract(sin(n) * 43758.5453); }

vec3 effect(vec3 c, vec2 uv) {
    float t = time;
    // Horizontal shift by row bands, triggers rarely
    float band = floor(uv.y * 40.0);
    float jitter = (hash(band + floor(t * 12.0)) - 0.5) * 0.03;
    jitter *= step(0.92, hash(floor(t * 8.0) + band));
    vec2 suv = vec2(uv.x + jitter, uv.y);
    // RGB split that pulses over time
    float amt = 0.004 + 0.003 * sin(t * 6.0);
    float r = texture(tex, suv + vec2(amt, 0.0)).r;
    float g = texture(tex, suv).g;
    float b = texture(tex, suv - vec2(amt, 0.0)).b;
    return vec3(r, g, b);
}

// Retro CRT: tube curvature + shadow RGB mask + scanlines + vignette.
// The curvature resamples the image along bowed coordinates, which makes the
// straight edges of windows/text jaggy (that very artefact). So we SMOOTH the
// sampling with 2x2 supersampling based on screen-space derivatives (dFdx/dFdy).
// Scanlines are computed in curved space (wuv) — they bend together with the
// screen. The mask is tied to physical pixels (gl_FragCoord) so its 3px
// frequency doesn't "drift" and produce colour moiré
vec3 effect_1(vec3 c, vec2 uv) {
    // Tube curvature
    vec2 cc = uv - 0.5;
    vec2 wuv = uv + cc * dot(cc, cc) * 0.18;

    // Pixel size in wuv coordinates — for supersampling (computed BEFORE branching,
    // derivatives must live in uniform control flow)
    vec2 dx = dFdx(wuv);
    vec2 dy = dFdy(wuv);

    // Beyond the edge of the rounded tube — a black border
    if (any(lessThan(wuv, vec2(0.0))) || any(greaterThan(wuv, vec2(1.0)))) {
        return vec3(0.0);
    }

    // 2x2 supersampling (rotated grid) — smooths the jaggies from the curvature
    vec3 col = 0.25 * (
        texture(tex, wuv + 0.25 * dx + 0.25 * dy).rgb +
        texture(tex, wuv - 0.25 * dx + 0.25 * dy).rgb +
        texture(tex, wuv + 0.25 * dx - 0.25 * dy).rgb +
        texture(tex, wuv - 0.25 * dx - 0.25 * dy).rgb
    );

    // Line density in pixels via derivatives — resolution-independent
    float H = 1.0 / max(fwidth(uv.y), 1e-6);
    // Scanlines are computed in CURVED space (wuv), not along physical rows —
    // so they bow together with the tube (period ~9px in the centre)
    float scan = 0.85 + 0.15 * sin(wuv.y * H * 0.7);

    // Shadow RGB mask with a 3px period, along physical pixels
    float ph = mod(gl_FragCoord.x, 3.0);
    vec3 mask = vec3(0.8);
    if (ph < 1.0) {
        mask.r = 1.0;
    } else if (ph < 2.0) {
        mask.g = 1.0;
    } else {
        mask.b = 1.0;
    }

    // Vignette at the edges
    float vig = smoothstep(0.95, 0.4, length(cc));

    col *= scan * mask * mix(0.7, 1.0, vig);
    return col * 1.3; // compensates for the dimming from the mask and scanlines
}

// Vignette — soft darkening toward the screen edges, focus in the centre
vec3 effect_2(vec3 c, vec2 uv) {
    vec2 d = uv - 0.5;
    float v = smoothstep(0.85, 0.35, length(d));
    return c * mix(0.45, 1.0, v);
}

void main() {
    vec4 src = texture(tex, v_texcoord);
    vec3 c = effect(src.rgb, v_texcoord);
    c = effect_1(c, v_texcoord);
    c = effect_2(c, v_texcoord);
    c *= BRIGHTNESS;
    fragColor = vec4(c, src.a);
}
