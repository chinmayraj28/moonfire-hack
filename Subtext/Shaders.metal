#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// The decode burst. The bubble breaks into small tiles that fly outward around a glowing core,
// tinted and twinkling; at progress 1 it is fully blown apart and the app swaps the text, then the
// same mapping runs backwards so the new bubble reassembles. The view is padded so tiles have room.
[[ stitchable ]] half4 subtextShatter(float2 position, SwiftUI::Layer layer, float2 size,
                                      float progress, float time, half4 tint) {
    float p = clamp(progress, 0.0, 1.0);
    if (p <= 0.001) { return layer.sample(position); }
    float e = p * p * (3.0 - 2.0 * p);
    float2 centre = size * 0.5;
    float push = 90.0 * e;                                   // every tile flies this far outward
    float turn = 0.3 * e + 0.06 * sin(time * 5.0) * e;      // and the whole cloud swirls
    const float cell = 6.0;

    // Undo the swirl so the outward push can be inverted per pixel.
    float2 rel = position - centre;
    float c0 = cos(-turn), s0 = sin(-turn);
    rel = float2(rel.x * c0 - rel.y * s0, rel.x * s0 + rel.y * c0);
    float r = length(rel);

    // A pulsing core where the bubble blew open.
    float core = (1.0 - smoothstep(0.0, push + 10.0, r)) * e;
    half4 glow = half4(tint.rgb, 1.0h) * half(core * (0.32 + 0.14 * sin(time * 14.0)));
    if (r <= push) { return glow; }

    // Which tile lands here: pull the pixel back in by the push, find its tile, then check the
    // tile's own (shrunken) landing square actually covers this pixel.
    float2 src = centre + rel * ((r - push) / r);
    float2 id = floor(src / cell);
    float2 tileCentre = (id + 0.5) * cell;
    float2 fromCentre = tileCentre - centre;
    float rc = max(length(fromCentre), 0.001);
    float2 landed = centre + fromCentre * ((rc + push) / rc);
    float n = hash21(id), m = hash21(id + 17.0);
    float2 local = (centre + rel - landed) / (1.0 - 0.55 * e * n);
    if (abs(local.x) > cell * 0.5 || abs(local.y) > cell * 0.5) { return glow; }

    half4 c = layer.sample(tileCentre + local);
    c.rgb = mix(c.rgb, tint.rgb * c.a, half(0.75 * e));
    float twinkle = step(0.82, m) * (0.5 + 0.5 * sin(time * 30.0 + n * 6.28));
    c.rgb += half3(1.0h) * c.a * half(0.6 * e * twinkle);
    c *= half(1.0 - 0.7 * e * m);
    return c + glow * (1.0h - c.a);
}

// A shockwave that rolls through the whole conversation from where you clicked.
[[ stitchable ]] half4 subtextRipple(float2 position, SwiftUI::Layer layer, float2 origin, float time,
                                     float amplitude, float frequency, float decay, float speed, half4 tint) {
    float distance = length(position - origin);
    float t = max(0.0, time - distance / speed);
    float wave = amplitude * sin(frequency * t) * exp(-decay * t);
    float2 n = distance > 0.001 ? (position - origin) / distance : float2(0.0);
    float2 p = position + wave * n;
    half4 r = layer.sample(p + n * wave * 0.25);
    half4 g = layer.sample(p);
    half4 b = layer.sample(p - n * wave * 0.25);
    half4 c = half4(r.r, g.g, b.b, g.a);
    half crest = half(wave / amplitude);
    c.rgb += (half3(0.25h) + tint.rgb * 0.3h) * crest * c.a;
    return c;
}

// A slow diagonal sheen that keeps decoded purple bubbles feeling alive.
[[ stitchable ]] half4 subtextSheen(float2 position, half4 color, float2 size, float time) {
    if (color.a < 0.01h) { return color; }
    float d = (position.x + position.y * 0.5) / max(size.x, 1.0);
    float band = fract(d * 0.6 - time * 0.22);
    float glow = smoothstep(0.0, 0.06, band) * (1.0 - smoothstep(0.06, 0.18, band));
    return half4(color.rgb + half3(glow * 0.22) * color.a, color.a);
}
