#version 440
// haseen.background's wallpaper transition (plan 161), the one shader in the
// shell (architecture 6). ShaderView.qml draws it on a GPU scene graph only,
// for the length of one background change. Every value is worked out here,
// per pixel, from the two images and a seed: no map is prepared beforehand.
//
// mode 0, contagion: colonies start at random places and moments and eat
// through the old image along a noise field, in square cells of `cell`
// device pixels. A cell lights up in `ember` for a moment as it turns.
// mode 1, outline: a thin line in `ink` traces the new image's strong edges
// (a Sobel filter on its luminance), the cells near those edges turn first,
// and the rest follows outwards in the same cells.
//
// progress 0 is exactly the old image and 1 exactly the new one, so the
// cover can hand over to swaybg without a visible step at either end.
//
// Compiled into transition-1.frag.qsb with
//   /usr/lib/qt6/bin/qsb --qt6 -o transition-1.frag.qsb transition.frag
// (qt6-shadertools 6.12). Change the number in the file name with the
// shader: Qt caches a compiled shader by its URL.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float seed;
    float mode;
    float cell;
    vec2 resolution;
    vec2 oldScale;
    vec2 newScale;
    vec4 ember;
    vec4 ink;
};

layout(binding = 1) uniform sampler2D oldTex;
layout(binding = 2) uniform sampler2D newTex;

// A pseudo-random value in 0..1 for a point.
float rand2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise, and three octaves of it.
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 w = f * f * (3.0 - 2.0 * f);
    float a = rand2(i);
    float b = rand2(i + vec2(1.0, 0.0));
    float c = rand2(i + vec2(0.0, 1.0));
    float d = rand2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

float field(vec2 p) {
    float v = 0.5 * noise(p);
    v += 0.25 * noise(p * 2.1 + vec2(5.3, 1.7));
    v += 0.125 * noise(p * 4.3 + vec2(2.9, 8.1));
    return v / 0.875;
}

// Texture coordinates of a screen point in an image shown like swaybg's
// fill: covering the screen, centred.
vec2 cover(vec2 uv, vec2 s) {
    return vec2(0.5) + (uv - vec2(0.5)) * s;
}

// The new image's luminance at uv, `blur` mip levels softer: the image is
// decoded with mipmaps, so a coarse level is a blurred copy for free.
float luma(vec2 uv, float blur) {
    return dot(texture(newTex, uv, blur).rgb, vec3(0.299, 0.587, 0.114));
}

// The new image's edge strength around uv, `d` texture units apart.
float sobel(vec2 uv, vec2 d, float blur) {
    float tl = luma(uv + vec2(-d.x, -d.y), blur);
    float t = luma(uv + vec2(0.0, -d.y), blur);
    float tr = luma(uv + vec2(d.x, -d.y), blur);
    float l = luma(uv + vec2(-d.x, 0.0), blur);
    float r = luma(uv + vec2(d.x, 0.0), blur);
    float bl = luma(uv + vec2(-d.x, d.y), blur);
    float b = luma(uv + vec2(0.0, d.y), blur);
    float br = luma(uv + vec2(d.x, d.y), blur);
    float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
    return length(vec2(gx, gy));
}

// A cheaper gradient, for the coarse scales.
float gradient(vec2 uv, vec2 d, float blur) {
    float gx = luma(uv + vec2(d.x, 0.0), blur) - luma(uv - vec2(d.x, 0.0), blur);
    float gy = luma(uv + vec2(0.0, d.y), blur) - luma(uv - vec2(0.0, d.y), blur);
    return length(vec2(gx, gy));
}

// How much the new image's large shapes differ in brightness: the spread of
// 16 samples of a heavily blurred copy. A soft, misty picture has weak
// edges everywhere, so the outline scales its edges up by this.
float boost() {
    float sum = 0.0;
    float sum2 = 0.0;
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            float l = luma(vec2((float(i) + 0.5) / 4.0, (float(j) + 0.5) / 4.0), 6.0);
            sum += l;
            sum2 += l * l;
        }
    }
    float mean = sum / 16.0;
    float spread = sqrt(max(sum2 / 16.0 - mean * mean, 0.0));
    return clamp(0.18 / max(spread, 0.03), 1.0, 4.0);
}

// When a contagion cell turns, in 0..1 of the change.
float contagionTime(vec2 cellCentre) {
    float aspect = resolution.x / resolution.y;
    // Cell centre in screen heights, so a colony spreads at the same speed
    // across and down.
    vec2 p = vec2(cellCentre.x / resolution.y, cellCentre.y / resolution.y);
    // The noise field bends the space the colonies grow through, so their
    // fronts wander instead of growing as circles, and a finer noise
    // roughens them into fingers.
    vec2 s = vec2(seed * 0.37, seed * 0.11);
    vec2 q = p + 0.3 * vec2(field(p * 2.3 + s) - 0.5, field(p * 2.3 + s + vec2(19.1, 7.7)) - 0.5);
    float rough = field(p * 11.0 + s.yx);
    float best = 2.0;
    for (int k = 0; k < 6; k++) {
        float fk = float(k);
        // One colony somewhere in each sixth of the screen (three across,
        // two down), so no corner is left far from all of them.
        float column = mod(fk, 3.0);
        float row = floor(fk / 3.0);
        vec2 at = vec2((column + 0.1 + 0.8 * rand2(vec2(fk, seed))) / 3.0 * aspect,
                       (row + 0.1 + 0.8 * rand2(vec2(seed, fk + 7.0))) / 2.0);
        // One colony starts at once, the others within the first half.
        float first = floor(mod(seed, 6.0));
        float start = abs(fk - first) < 0.5 ? 0.02 : 0.06 + 0.42 * rand2(vec2(fk * 3.1, seed + 1.7));
        float speed = 0.75 + 0.5 * rand2(vec2(seed + 4.2, fk * 1.9));
        float reach = length(q - at) / speed;
        best = min(best, start + reach * (0.75 + 0.7 * rough));
    }
    // A little scatter per cell keeps the front ragged and crisp.
    best += (rand2(cellCentre + vec2(seed)) - 0.5) * 0.02;
    // Squeeze the late part of the timeline so the last cells turn by 0.93
    // without breaking the fronts up: the curve keeps their order.
    best = 0.93 * (1.0 - exp(-1.6 * best)) / (1.0 - exp(-2.56));
    return clamp(best, 0.02, 0.95);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 uvOld = cover(uv, oldScale);
    vec2 uvNew = cover(uv, newScale);
    vec4 before = texture(oldTex, uvOld);
    vec4 after = texture(newTex, uvNew);

    if (progress <= 0.0) {
        fragColor = before * qt_Opacity;
        return;
    }
    if (progress >= 1.0) {
        fragColor = after * qt_Opacity;
        return;
    }

    vec2 px = uv * resolution;
    vec2 cellCentre = (floor(px / cell) + 0.5) * cell;
    vec4 colour;

    if (mode < 0.5) {
        float turn = contagionTime(cellCentre);
        float age = (progress - turn) / 0.04;
        if (age < 0.0) {
            colour = before;
        } else if (age < 1.0) {
            // The burning edge: lit at once, cooling into the new image.
            float heat = pow(1.0 - age, 2.0);
            vec3 lit = mix(ember.rgb, vec3(1.0), 0.3 * heat);
            colour = vec4(mix(after.rgb, lit, 0.9 * heat), 1.0);
        } else {
            colour = after;
        }
    } else {
        // One device pixel in the new image's texture units.
        vec2 onePx = newScale / resolution;
        // How much structure lies near the cell, read from blurred copies
        // at three scales: a cell by a strong edge turns first, a cell in a
        // flat sky last. A slow noise loosens the order so the fill spreads
        // in fronts rather than in rings.
        vec2 cellUv = cover(cellCentre / resolution, newScale);
        float gain = boost();
        float structure = gain * (0.45 * gradient(cellUv, onePx * 12.0, 3.5)
            + 0.35 * gradient(cellUv, onePx * 32.0, 5.0)
            + 0.2 * gradient(cellUv, onePx * 80.0, 6.5));
        float near = smoothstep(0.02, 0.3, structure);
        float drift = field(cellCentre / resolution.y * 2.2 + vec2(seed * 0.23));
        float turn = 0.34 + 0.56 * mix(1.0 - near, drift, 0.55);
        turn += (rand2(cellCentre + vec2(seed)) - 0.5) * 0.01;
        // The old image settles back a little while the line draws.
        vec3 base = progress < turn ? before.rgb * (1.0 - 0.1 * smoothstep(0.0, 0.3, progress)) : after.rgb;
        colour = vec4(base, 1.0);

        // The line: the new image's strong edges, from a slightly blurred
        // copy so texture does not count, drawn in over the first 40 %
        // along a slow noise and faded out once the image has filled in.
        float edge = smoothstep(0.35, 0.75, gain * sobel(uvNew, onePx, 1.0));
        float order = field(px / resolution.y * 2.5 + vec2(seed * 0.71, 3.0));
        float drawn = smoothstep(0.03 + order * 0.36, 0.07 + order * 0.36, progress);
        float fade = 1.0 - smoothstep(0.72, 0.95, progress);
        float line = edge * drawn * fade * ink.a;
        colour.rgb = mix(colour.rgb, ink.rgb, line);
    }
    fragColor = colour * qt_Opacity;
}
