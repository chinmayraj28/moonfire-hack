#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// The decode morph: mid-flip the bubble turns to jelly. amount 0 leaves it alone; at 1 it ripples
// side to side, swells from the middle and wobbles. Returns where each pixel samples from.
[[ stitchable ]] float2 subtextMorph(float2 position, float2 size, float amount, float time) {
    if (amount <= 0.001) { return position; }
    float2 uv = position / size;
    float2 c = uv - 0.5;
    float2 wave = float2(sin(uv.y * 10.0 + time * 13.0) * 7.0, sin(uv.x * 8.0 - time * 10.0) * 5.0);
    float swell = 1.0 - 0.2 * amount * (1.0 - 4.0 * dot(c, c));
    return 0.5 * size + (position - 0.5 * size) * swell + amount * wave;
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
