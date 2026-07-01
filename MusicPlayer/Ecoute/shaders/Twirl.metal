#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Twirl distortion: rotates pixels around `center` by an angle that falls off
/// as (1 - dist/radius)^2 — strongest at the center, tapering to zero at the edge.
[[ stitchable ]] half4 twirl(
    float2 position,
    SwiftUI::Layer layer,
    float2 center,
    float radius,
    float angle
) {
    float2 delta = position - center;
    float dist = length(delta);

    if (dist < radius) {
        float t = 1.0 - dist / radius;
        float a = angle * t * t;
        float cosA = cos(a);
        float sinA = sin(a);
        float2 rotated = float2(
            delta.x * cosA - delta.y * sinA,
            delta.x * sinA + delta.y * cosA
        );
        return layer.sample(center + rotated);
    }

    return layer.sample(position);
}
