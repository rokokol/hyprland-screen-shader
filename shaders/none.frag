// label: Normal
// emoji: 🌈
// order: 0
// animated: no
// samples: no
// No colour effect — just pass the colour through.
// Needed so brightness-only dimming works without a filter
vec3 effect(vec3 c, vec2 uv) {
    return c;
}
