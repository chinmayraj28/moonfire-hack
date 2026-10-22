#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// The decode glitch. progress 0 leaves the bubble untouched; at 1 it is pixelated, torn,
// split into RGB, tinted and half dissolved. The app swaps the text at the peak.
[[ stitchable ]] half4 subtextDecode(float2 position, SwiftUI::Layer layer, float2 size,
                                     float progress, float time, half4 tint) {
    float p = clamp(progress, 0.0, 1.0);
    if (p <= 0.001) { return layer.sample(position); }

    float block = mix(1.0, 10.0, p * p);
    float2 cell = floor(position / block);
    float2 centre = (cell + 0.5) * block;
    float2 pos = mix(position, centre, smoothstep(0.1, 0.5, p));

    float frame = floor(time * 24.0);
    float row = floor(position.y / 4.0);
    float tearOn = step(0.55, hash21(float2(row * 1.7, frame + 3.0)));
    float tear = (hash21(float2(row, frame)) - 0.5) * 22.0 * p * tearOn;
    float wave = sin(position.y * 0.09 + time * 12.0) * 3.0 * p;
    pos.x += tear + wave;

    float split = 5.0 * p;
    half4 r = layer.sample(pos + float2(split, 0.0));
    half4 g = layer.sample(pos);
    half4 b = layer.sample(pos - float2(split, 0.0));
    half4 c = half4(r.r, g.g, b.b, max(max(r.a, g.a), b.a));

    c.rgb = mix(c.rgb, tint.rgb * c.a, half(0.6 * p));

    float keep = step(hash21(cell + 11.0), 1.0 - 0.7 * p * p);
    c *= half(keep);

    float spark = step(1.0 - 0.06 * p, hash21(cell + frame * 0.37));
    c += half4(tint.rgb, 1.0h) * half(spark * p) * g.a;
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
