#include <metal_stdlib>
using namespace metal;

// MARK: - Shared

struct BackgroundUniforms {
    float time;
    float width;
    float height;
    float speed;
    float saturation;
    float displayScale;        // backing scale factor (1.0 on 1x, 2.0 on Retina) — normalises to point space
    float samplePosMultiplier; // scales blur sample offsets — larger = wider blur per level
    float highlightCap;        // output levels highlight ceiling (1.0 = normal, ~0.39 = night mode)
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Full-screen quad — no vertex buffer needed, positions derived from vertex ID
vertex VertexOut vertex_passthrough(uint vid [[vertex_id]]) {
    const float2 positions[4] = {
        {-1, -1}, {1, -1}, {-1, 1}, {1, 1}
    };
    const float2 uvs[4] = {
        {0, 1}, {1, 1}, {0, 0}, {1, 0}
    };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv = uvs[vid];
    return out;
}

// MARK: - Sprite helpers

// Returns UV into the album art for a given screen position,
// given a sprite centered at (cx, cy) with half-size hs, rotated by angle.
// Returns (-1,-1) if the position is outside the sprite.
static float2 spriteUV(float2 pos, float cx, float cy, float hs, float angle) {
    float2 d = pos - float2(cx, cy);
    float c = cos(-angle);
    float s = sin(-angle);
    float2 local = float2(d.x * c - d.y * s, d.x * s + d.y * c);
    float2 uv = (local + hs) / (2.0 * hs);
    if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1) return float2(-1);
    return uv;
}

// MARK: - Pass 1: composite sprites + twirl

fragment half4 fragment_composite_twirl(
    VertexOut in [[stage_in]],
    texture2d<half> art [[texture(0)]],
    constant BackgroundUniforms &u [[buffer(0)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float w = u.width;
    float h = u.height;
    float t = u.time * u.speed;
    float cx = w * 0.5;
    float cy = h * 0.5;
    float orbitR = w * 0.25;

    // Sprite sizes (half-size in pixels)
    float maxDim = max(w, h);
    float hs0 = maxDim * 1.25 ;  // t — 125%
    float hs1 = maxDim * 0.80 ;  // s — 80%
    float hs2 = maxDim * 0.50 ;  // i — 50%
    float hs3 = maxDim * 0.25 ;  // r — 25%

    // Rotations
    float rot0 =  t * 1.000 + 0.6;
    float rot1 = -t * 2.670 + 3.14159;  // starts inverted
    float rot2 = -t * 2.000 + 1.85;
    float rot3 =  t * 1.330 + 4.71;     // starts ~270°

    // Centers
    float2 c0 = float2(cx, cy);
    float2 c1 = float2(w / 2.5, h / 2.5);
    float2 c2 = float2(cx + cos(rot2 * 0.75) * orbitR,
                       cy + sin(rot2 * 0.75) * orbitR);
    float2 c3 = float2(cx + w * 0.05 + cos(rot3 * 0.75) * orbitR,
                       cy + w * 0.05 + sin(rot3 * 0.75) * orbitR);

    // Screen position of this pixel
    float2 pos = float2(in.uv.x * w, in.uv.y * h);

    // Shear — rows slide horizontally, columns slide vertically, both oscillate slowly
    float shearX = 0.40 * sin(t * 0.27);
    float shearY = 0.25 * cos(t * 0.19);
    pos.x += (pos.y - cy) * shearX;
    pos.y += (pos.x - cx) * shearY;

    // Ripple — low-frequency sine wave across both axes
    float ripple = maxDim * 0.018;
    pos.x += sin((pos.y / maxDim) * 5.0 + t * 0.6) * ripple;
    pos.y += sin((pos.x / maxDim) * 5.0 + t * 0.4) * ripple;

    // Twirl — rotational warp strongest at centre, fading out toward the edge
    float2 delta = pos - float2(cx, cy);
    float dist = length(delta);
    float radius = max(w, h) * 0.75;
    if (dist < radius) {
        float ratio = (radius - dist) / radius;
        float a = -2.0 * ratio * ratio;
        float cosA = cos(a), sinA = sin(a);
        delta = float2(delta.x * cosA - delta.y * sinA,
                       delta.x * sinA + delta.y * cosA);
        pos = float2(cx, cy) + delta;
    }

    // Sample front-to-back: r (smallest/front) first
    float2 uv;

    uv = spriteUV(pos, c3.x, c3.y, hs3, rot3);
    if (uv.x >= 0) return art.sample(s, uv);

    uv = spriteUV(pos, c2.x, c2.y, hs2, rot2);
    if (uv.x >= 0) return art.sample(s, uv);

    uv = spriteUV(pos, c1.x, c1.y, hs1, rot1);
    if (uv.x >= 0) return art.sample(s, uv);

    uv = spriteUV(pos, c0.x, c0.y, hs0, rot0);
    if (uv.x >= 0) return art.sample(s, uv);

    // Fallback — sample the large sprite with clamped coords
    uv = clamp(spriteUV(float2(cx, cy), c0.x, c0.y, hs0, rot0), 0.0, 1.0);
    return art.sample(s, uv);
}

// MARK: - Dual Kawase blur (Marius Bjørge, SIGGRAPH 2015)
//
// Downsample: renders to half the source resolution.
// 5 bilinear taps — center (weight 4) + 4 diagonal corners (weight 1 each) — sum / 8.
// Each level doubles the effective blur radius at constant tap cost.
//
// Upsample: renders back to double the source resolution.
// 8 bilinear taps — 4 axis-aligned (weight 2) + 4 diagonal (weight 1) — sum / 12.
// Reconstructs a smooth Gaussian-like footprint from the downsampled chain.

fragment half4 fragment_dual_kawase_down(
    VertexOut in [[stage_in]],
    texture2d<half> tex [[texture(0)]],
    constant BackgroundUniforms &u [[buffer(0)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 texel = float2(1.0 / float(tex.get_width()), 1.0 / float(tex.get_height())) * u.samplePosMultiplier;
    float2 uv = in.uv;

    half4 sum = tex.sample(s, uv) * 4.0h;
    sum += tex.sample(s, uv + float2(-texel.x, -texel.y));
    sum += tex.sample(s, uv + float2(-texel.x,  texel.y));
    sum += tex.sample(s, uv + float2( texel.x, -texel.y));
    sum += tex.sample(s, uv + float2( texel.x,  texel.y));
    return sum / 8.0h;
}

fragment half4 fragment_dual_kawase_up(
    VertexOut in [[stage_in]],
    texture2d<half> tex [[texture(0)]],
    constant BackgroundUniforms &u [[buffer(0)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 t = float2(1.0 / float(tex.get_width()), 1.0 / float(tex.get_height())) * u.samplePosMultiplier;
    float2 uv = in.uv;

    half4 sum;
    sum  = tex.sample(s, uv + float2(-2.0 * t.x,        0)) * 1.0h;
    sum += tex.sample(s, uv + float2(      -t.x,       t.y)) * 2.0h;
    sum += tex.sample(s, uv + float2(         0, 2.0 * t.y)) * 1.0h;
    sum += tex.sample(s, uv + float2(       t.x,       t.y)) * 2.0h;
    sum += tex.sample(s, uv + float2( 2.0 * t.x,        0)) * 1.0h;
    sum += tex.sample(s, uv + float2(       t.x,      -t.y)) * 2.0h;
    sum += tex.sample(s, uv + float2(         0,-2.0 * t.y)) * 1.0h;
    sum += tex.sample(s, uv + float2(      -t.x,      -t.y)) * 2.0h;
    return sum / 12.0h;
}

// MARK: - Finalize (saturation + darken + grain)

static float hash1(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

// True 3D value noise — trilinear interpolation across all 8 lattice corners.
// Walking along z gives smooth continuous evolution with no directional drift.
static float noise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);  // smoothstep per axis
    return mix(mix(mix(hash1(i+float3(0,0,0)), hash1(i+float3(1,0,0)), u.x),
                   mix(hash1(i+float3(0,1,0)), hash1(i+float3(1,1,0)), u.x), u.y),
               mix(mix(hash1(i+float3(0,0,1)), hash1(i+float3(1,0,1)), u.x),
                   mix(hash1(i+float3(0,1,1)), hash1(i+float3(1,1,1)), u.x), u.y), u.z);
}

fragment half4 fragment_finalize(
    VertexOut in [[stage_in]],
    texture2d<half> tex [[texture(0)]],
    constant BackgroundUniforms &u [[buffer(0)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    half4 color = tex.sample(s, in.uv);

    // Saturation
    half luma = dot(color.rgb, half3(0.2126h, 0.7152h, 0.0722h));
    color.rgb = mix(half3(luma), color.rgb, half(u.saturation));

    // Darken overlay — highlightCap controls output ceiling (1.0 = normal, ~0.39 = night mode)
    color.rgb *= half(u.highlightCap);

    // Film grain — work in point space so density is display-independent
    float2 grainCoord = in.uv * float2(u.width, u.height) / u.displayScale;
    half g = half(noise3(float3(grainCoord, sin(u.time)))) * 0.08h - 0.04h;
    color.rgb = clamp(color.rgb + g, 0.0h, 1.0h);

    return half4(color.rgb, 1.0h);
}
