// Player background shaders (SwiftUI `colorEffect`).

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Noise

static float smokeHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float smokeNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = smokeHash(i);
    float b = smokeHash(i + float2(1.0, 0.0));
    float c = smokeHash(i + float2(0.0, 1.0));
    float d = smokeHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Five layers of noise, each finer and turned a little, for soft, cloudy detail.
static float smokeLayers(float2 p) {
    float value = 0.0;
    float amount = 0.5;
    float2x2 turn = float2x2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 5; i++) {
        value += amount * smokeNoise(p);
        p = turn * p * 2.0 + float2(3.1, 1.7);
        amount *= 0.5;
    }
    return value;
}

// MARK: - Pink smoke

/// Shades of pink, light and airy: a deep rose only in the deepest folds, rising through rose
/// and pink to blush and an almost-white pink on the crests.
static float3 pinkShade(float t) {
    float3 deepRose = float3(0.70, 0.22, 0.45);
    float3 rose     = float3(0.88, 0.45, 0.63);
    float3 pink     = float3(0.96, 0.64, 0.77);
    float3 blush    = float3(0.99, 0.80, 0.87);
    float3 pale     = float3(1.00, 0.93, 0.96);
    float3 c = mix(deepRose, rose, smoothstep(0.00, 0.30, t));
    c = mix(c, pink, smoothstep(0.30, 0.55, t));
    c = mix(c, blush, smoothstep(0.55, 0.78, t));
    return mix(c, pale, smoothstep(0.78, 0.97, t));
}

/// Slowly folding pink smoke, like ink swirling in milk. Noise is bent by noise, twice
/// ("domain warping"), so the shapes flow and fold into each other as `time` passes.
/// `lightness`: the lowest tone used (0.32 behind the player; higher, paler, behind pages of text).
[[ stitchable ]] half4 pinkSmoke(float2 position, half4 color, float2 size, float time, float lightness) {
    float2 uv = position / size;
    float aspect = size.x / max(size.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 1.3;
    float t = time * 0.05;

    float2 q = float2(smokeLayers(p + float2(0.0, t)),
                      smokeLayers(p + float2(5.2, 1.3) - t * 0.7));
    float2 r = float2(smokeLayers(p + 2.0 * q + float2(1.7, 9.2) + t * 0.9),
                      smokeLayers(p + 2.0 * q + float2(8.3, 2.8) - t * 0.6));
    float f = smokeLayers(p + 2.2 * r);

    // A gentle ripple through the folds, then kept to the lighter half of the range so the
    // player's dark text and icons stay easy to read.
    float ripple = 0.08 * sin(p.x * 4.0 + p.y * 3.0 + t * 6.0 + f * 4.0);
    float tone = clamp(f * 1.3 - 0.05 + ripple, 0.0, 1.0);
    tone = mix(lightness, 1.0, tone);
    float3 c = pinkShade(tone);

    // Very fine film grain.
    c *= 0.975 + 0.025 * smokeHash(position + floor(time * 24.0));
    return half4(half3(c), 1.0h);
}

// MARK: - Purple smoke (the Cosmos theme)

/// Shades of purple, light and airy: deep violet only in the deepest folds, rising through
/// violet and lavender to lilac and an almost-white lavender on the crests.
static float3 purpleShade(float t) {
    float3 deepViolet = float3(0.36, 0.22, 0.70);
    float3 violet     = float3(0.55, 0.42, 0.88);
    float3 lavender   = float3(0.72, 0.62, 0.96);
    float3 lilac      = float3(0.85, 0.79, 0.99);
    float3 pale       = float3(0.95, 0.93, 1.00);
    float3 c = mix(deepViolet, violet, smoothstep(0.00, 0.30, t));
    c = mix(c, lavender, smoothstep(0.30, 0.55, t));
    c = mix(c, lilac, smoothstep(0.55, 0.78, t));
    return mix(c, pale, smoothstep(0.78, 0.97, t));
}

/// `pinkSmoke`, in purple.
[[ stitchable ]] half4 purpleSmoke(float2 position, half4 color, float2 size, float time, float lightness) {
    float2 uv = position / size;
    float aspect = size.x / max(size.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 1.3;
    float t = time * 0.05;

    float2 q = float2(smokeLayers(p + float2(0.0, t)),
                      smokeLayers(p + float2(5.2, 1.3) - t * 0.7));
    float2 r = float2(smokeLayers(p + 2.0 * q + float2(1.7, 9.2) + t * 0.9),
                      smokeLayers(p + 2.0 * q + float2(8.3, 2.8) - t * 0.6));
    float f = smokeLayers(p + 2.2 * r);

    float ripple = 0.08 * sin(p.x * 4.0 + p.y * 3.0 + t * 6.0 + f * 4.0);
    float tone = clamp(f * 1.3 - 0.05 + ripple, 0.0, 1.0);
    tone = mix(lightness, 1.0, tone);
    float3 c = purpleShade(tone);

    c *= 0.975 + 0.025 * smokeHash(position + floor(time * 24.0));
    return half4(half3(c), 1.0h);
}

// MARK: - Cover smoke (the player under Pink smoke and Cosmos)

/// The same folding smoke, in the book cover's colours: five tones from the deepest folds (`c0`,
/// the cover's clear accent) through its pastels to an almost-white crest (`c4`).
[[ stitchable ]] half4 coverSmoke(float2 position, half4 color, float2 size, float time, float lightness,
                                  half4 c0, half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 uv = position / size;
    float aspect = size.x / max(size.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 1.3;
    float t = time * 0.05;

    float2 q = float2(smokeLayers(p + float2(0.0, t)),
                      smokeLayers(p + float2(5.2, 1.3) - t * 0.7));
    float2 r = float2(smokeLayers(p + 2.0 * q + float2(1.7, 9.2) + t * 0.9),
                      smokeLayers(p + 2.0 * q + float2(8.3, 2.8) - t * 0.6));
    float f = smokeLayers(p + 2.2 * r);

    float ripple = 0.08 * sin(p.x * 4.0 + p.y * 3.0 + t * 6.0 + f * 4.0);
    float tone = clamp(f * 1.3 - 0.05 + ripple, 0.0, 1.0);
    tone = mix(lightness, 1.0, tone);

    float3 c = mix(float3(c0.rgb), float3(c1.rgb), smoothstep(0.00, 0.30, tone));
    c = mix(c, float3(c2.rgb), smoothstep(0.30, 0.55, tone));
    c = mix(c, float3(c3.rgb), smoothstep(0.55, 0.78, tone));
    c = mix(c, float3(c4.rgb), smoothstep(0.78, 0.97, tone));

    c *= 0.975 + 0.025 * smokeHash(position + floor(time * 24.0));
    return half4(half3(c), 1.0h);
}

// MARK: - Sky smoke (the Cloud Nine theme)

/// Shades of sky blue, light and airy: a deep blue only in the deepest folds, rising through
/// sky and powder blue to an almost-white blue on the crests.
static float3 skyShade(float t) {
    float3 deepBlue = float3(0.10, 0.42, 0.80);
    float3 sky      = float3(0.33, 0.64, 0.95);
    float3 light    = float3(0.58, 0.80, 0.99);
    float3 powder   = float3(0.79, 0.90, 1.00);
    float3 pale     = float3(0.93, 0.97, 1.00);
    float3 c = mix(deepBlue, sky, smoothstep(0.00, 0.30, t));
    c = mix(c, light, smoothstep(0.30, 0.55, t));
    c = mix(c, powder, smoothstep(0.55, 0.78, t));
    return mix(c, pale, smoothstep(0.78, 0.97, t));
}

/// `pinkSmoke`, in sky blue.
[[ stitchable ]] half4 skySmoke(float2 position, half4 color, float2 size, float time, float lightness) {
    float2 uv = position / size;
    float aspect = size.x / max(size.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 1.3;
    float t = time * 0.05;

    float2 q = float2(smokeLayers(p + float2(0.0, t)),
                      smokeLayers(p + float2(5.2, 1.3) - t * 0.7));
    float2 r = float2(smokeLayers(p + 2.0 * q + float2(1.7, 9.2) + t * 0.9),
                      smokeLayers(p + 2.0 * q + float2(8.3, 2.8) - t * 0.6));
    float f = smokeLayers(p + 2.2 * r);

    float ripple = 0.08 * sin(p.x * 4.0 + p.y * 3.0 + t * 6.0 + f * 4.0);
    float tone = clamp(f * 1.3 - 0.05 + ripple, 0.0, 1.0);
    tone = mix(lightness, 1.0, tone);
    float3 c = skyShade(tone);

    c *= 0.975 + 0.025 * smokeHash(position + floor(time * 24.0));
    return half4(half3(c), 1.0h);
}

// MARK: - Cover smoke, mixed colours

/// The cover smoke with several of the cover's colours at once: a second, slower field of noise
/// blends between three hues (`h0`, `h1`, `h2`, soft but colourful tints of the cover's main
/// colours), so different folds take different colours, drifting as the smoke moves. The crests
/// stay pale (`c3`, `c4`), so the player's text reads.
[[ stitchable ]] half4 coverSmokeMix(float2 position, half4 color, float2 size, float time, float lightness,
                                     half4 h0, half4 h1, half4 h2, half4 c3, half4 c4) {
    float2 uv = position / size;
    float aspect = size.x / max(size.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0) * 1.3;
    float t = time * 0.05;

    float2 q = float2(smokeLayers(p + float2(0.0, t)),
                      smokeLayers(p + float2(5.2, 1.3) - t * 0.7));
    float2 r = float2(smokeLayers(p + 2.0 * q + float2(1.7, 9.2) + t * 0.9),
                      smokeLayers(p + 2.0 * q + float2(8.3, 2.8) - t * 0.6));
    float f = smokeLayers(p + 2.2 * r);

    float ripple = 0.08 * sin(p.x * 4.0 + p.y * 3.0 + t * 6.0 + f * 4.0);
    float tone = clamp(f * 1.3 - 0.05 + ripple, 0.0, 1.0);
    tone = mix(lightness, 1.0, tone);

    // Which of the cover's colours this fold takes: two broad, slowly drifting fields.
    float a = smoothstep(0.35, 0.65, smokeLayers(p * 0.55 + q * 0.8 + float2(2.0, -t * 0.6)));
    float b = smoothstep(0.40, 0.70, smokeLayers(p * 0.5 - r * 0.6 + float2(-3.0, t * 0.5)));
    float3 hue = mix(mix(float3(h0.rgb), float3(h1.rgb), a), float3(h2.rgb), b * 0.7);

    float3 deep = hue;
    float3 mid = mix(hue, float3(1.0), 0.45);
    float3 c = mix(deep, mid, smoothstep(0.30, 0.55, tone));
    c = mix(c, float3(c3.rgb), smoothstep(0.55, 0.78, tone));
    c = mix(c, float3(c4.rgb), smoothstep(0.78, 0.97, tone));

    c *= 0.975 + 0.025 * smokeHash(position + floor(time * 24.0));
    return half4(half3(c), 1.0h);
}
