// label: Reading
// emoji: 📖
// order: 45
// animated: no
// samples: no
// Paper mode for long reading. The range is remapped into ink..paper instead of
// black..white, so nothing on screen is a pure-white glare or a pure-black edge —
// the reading-mode lever that survives the evidence, unlike "dark mode is healthier".
// The paper white sits in the "eye-care green" family (#c7edcc): weighted towards
// 555 nm, where photopic sensitivity peaks, and away from blue, so the same
// perceived brightness costs less light. Chroma is calmed first, so syntax
// highlighting stops shouting over the text
vec3 effect(vec3 c, vec2 uv) {
    const vec3 paper = vec3(0.78, 0.93, 0.80);
    const vec3 ink = vec3(0.10, 0.13, 0.11);

    float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
    vec3 calm = mix(vec3(lum), c, 0.65);

    return mix(ink, paper, calm);
}
