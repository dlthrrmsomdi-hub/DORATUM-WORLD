#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 color    [[attribute(2)]];
    float2 uv       [[attribute(3)]];
};

struct FrameUniforms {
    float4x4 viewProjectionMatrix;
    float4 cameraPosition;   // xyz = camera world pos, w = elapsed time
    float4 sunDirection;     // xyz = direction toward sun, w = sun intensity
    float4 sunColor;         // rgb = sun color, w = ambient intensity
    float4 ambientColor;     // rgb = ambient color, w = fog density
    float4 fogColor;         // rgb = fog color, w = fog start
    float4 fogParams;        // x = fog end, y = water level, z = quality tier, w = unused
};

struct ModelUniforms {
    float4x4 modelMatrix;
    float4x4 normalMatrix;
    float4 tintColor;        // rgb = tint, a = opacity
    float4 materialParams;   // x = specular, y = shininess, z = roughness, w = emissive
};

struct InstanceData {
    float4x4 modelMatrix;
    float4 tintColor;
    float4 materialParams;
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float4 vertexColor;
    float2 uv;
    float4 materialParams;
};

// MARK: - Standard World Vertex & Fragment Shaders

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant FrameUniforms &frame [[buffer(1)]],
    constant ModelUniforms &model [[buffer(2)]]
) {
    VertexOut out;
    float4 worldPos = model.modelMatrix * float4(in.position, 1.0);
    out.position = frame.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    out.worldNormal = normalize((model.normalMatrix * float4(in.normal, 0.0)).xyz);
    out.vertexColor = float4(in.color.rgb * model.tintColor.rgb, in.color.a * model.tintColor.a);
    out.uv = in.uv;
    out.materialParams = model.materialParams;
    return out;
}

vertex VertexOut vertex_instanced(
    VertexIn in [[stage_in]],
    constant FrameUniforms &frame [[buffer(1)]],
    const device InstanceData *instances [[buffer(3)]],
    uint instanceID [[instance_id]]
) {
    InstanceData inst = instances[instanceID];
    VertexOut out;
    float4 worldPos = inst.modelMatrix * float4(in.position, 1.0);
    out.position = frame.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;

    float3x3 upper = float3x3(
        inst.modelMatrix[0].xyz,
        inst.modelMatrix[1].xyz,
        inst.modelMatrix[2].xyz
    );
    out.worldNormal = normalize(upper * in.normal);
    out.vertexColor = float4(in.color.rgb * inst.tintColor.rgb, in.color.a * inst.tintColor.a);
    out.uv = in.uv;
    out.materialParams = inst.materialParams;
    return out;
}

static float3 applyFog(float3 color, float3 worldPos, constant FrameUniforms &frame) {
    float dist = length(worldPos - frame.cameraPosition.xyz);
    float fogStart = frame.fogColor.w;
    float fogEnd = max(frame.fogParams.x, fogStart + 1.0);
    float linearFactor = saturate((dist - fogStart) / (fogEnd - fogStart));
    float expFactor = 1.0 - exp(-pow(max(dist - fogStart * 0.4, 0.0) * frame.ambientColor.w, 1.5));
    float fogFactor = saturate(mix(linearFactor, expFactor, 0.35));
    return mix(color, frame.fogColor.rgb, fogFactor);
}

fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(1)]]
) {
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(frame.sunDirection.xyz);
    float3 V = normalize(frame.cameraPosition.xyz - in.worldPosition);
    float3 H = normalize(L + V);

    float sunIntensity = frame.sunDirection.w;
    float ambientIntensity = frame.sunColor.w;
    float specularStrength = in.materialParams.x;
    float shininess = max(in.materialParams.y, 2.0);
    float emissive = in.materialParams.w;

    // Hemisphere ambient lighting for natural sky/ground bounce
    float hemiMix = N.y * 0.5 + 0.5;
    float3 groundBounce = frame.ambientColor.rgb * 0.55;
    float3 skyAmbient = frame.ambientColor.rgb * 1.15;
    float3 ambient = mix(groundBounce, skyAmbient, hemiMix) * ambientIntensity;

    // Diffuse lighting
    float nDotL = max(dot(N, L), 0.0);
    float3 diffuse = frame.sunColor.rgb * (nDotL * sunIntensity);

    // Subtle back-fill rim light so shadowed building faces remain legible
    float backFill = max(dot(N, -L), 0.0) * 0.12;
    diffuse += frame.ambientColor.rgb * backFill;

    // Blinn-Phong specular lighting
    float spec = pow(max(dot(N, H), 0.0), shininess) * specularStrength * step(0.01, nDotL);
    float3 specular = frame.sunColor.rgb * spec * sunIntensity;

    // Subtle procedural micro-detail variation to prevent flat plastic look
    float checker = sin(in.worldPosition.x * 1.3) * sin(in.worldPosition.z * 1.3);
    float microTint = 1.0 + checker * 0.025 * in.materialParams.z;

    float3 baseColor = in.vertexColor.rgb * microTint;
    float3 litColor = baseColor * (ambient + diffuse) + specular + baseColor * emissive;

    // Distance atmospheric fog
    float3 finalColor = applyFog(litColor, in.worldPosition, frame);
    return float4(finalColor, in.vertexColor.a);
}

// MARK: - Animated 3D Water Shader

vertex VertexOut vertex_water(
    VertexIn in [[stage_in]],
    constant FrameUniforms &frame [[buffer(1)]],
    constant ModelUniforms &model [[buffer(2)]]
) {
    VertexOut out;
    float t = frame.cameraPosition.w;
    float4 worldPos = model.modelMatrix * float4(in.position, 1.0);

    // Multi-layered Gerstner-inspired wave displacement
    float w1 = sin(worldPos.x * 0.18 + t * 1.45 + worldPos.z * 0.07) * 0.14;
    float w2 = cos(worldPos.z * 0.24 - t * 1.15 + worldPos.x * 0.09) * 0.10;
    float w3 = sin((worldPos.x - worldPos.z) * 0.35 + t * 2.1) * 0.05;
    worldPos.y += (w1 + w2 + w3);

    // Analytic wave normal perturbation
    float dx = cos(worldPos.x * 0.18 + t * 1.45 + worldPos.z * 0.07) * 0.18 * 0.14
             - sin(worldPos.z * 0.24 - t * 1.15 + worldPos.x * 0.09) * 0.09 * 0.10
             + cos((worldPos.x - worldPos.z) * 0.35 + t * 2.1) * 0.35 * 0.05;
    float dz = cos(worldPos.x * 0.18 + t * 1.45 + worldPos.z * 0.07) * 0.07 * 0.14
             - sin(worldPos.z * 0.24 - t * 1.15 + worldPos.x * 0.09) * 0.24 * 0.10
             - cos((worldPos.x - worldPos.z) * 0.35 + t * 2.1) * 0.35 * 0.05;

    out.position = frame.viewProjectionMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    out.worldNormal = normalize(float3(-dx, 1.0, -dz));
    out.vertexColor = float4(in.color.rgb * model.tintColor.rgb, in.color.a * model.tintColor.a);
    out.uv = in.uv;
    out.materialParams = model.materialParams;
    return out;
}

fragment float4 fragment_water(
    VertexOut in [[stage_in]],
    constant FrameUniforms &frame [[buffer(1)]]
) {
    float t = frame.cameraPosition.w;
    float3 N = normalize(in.worldNormal);

    // Fine animated ripple normal perturbation
    float rippleX = sin(in.worldPosition.x * 1.1 + t * 2.2) * cos(in.worldPosition.z * 0.9 - t * 1.7) * 0.08;
    float rippleZ = cos(in.worldPosition.x * 0.8 - t * 1.9) * sin(in.worldPosition.z * 1.2 + t * 2.4) * 0.08;
    N = normalize(N + float3(rippleX, 0.0, rippleZ));

    float3 L = normalize(frame.sunDirection.xyz);
    float3 V = normalize(frame.cameraPosition.xyz - in.worldPosition);
    float3 H = normalize(L + V);

    // Fresnel sky reflection
    float fresnel = pow(1.0 - max(dot(N, V), 0.0), 3.0);
    float3 deepColor = float3(0.05, 0.26, 0.44);
    float3 shallowColor = float3(0.10, 0.48, 0.62);
    float3 waterBase = mix(deepColor, shallowColor, saturate(in.vertexColor.g));

    float nDotL = max(dot(N, L), 0.0);
    float3 diffuse = waterBase * (frame.ambientColor.rgb * frame.sunColor.w + frame.sunColor.rgb * nDotL * frame.sunDirection.w);

    // Crisp sun specular sparkle on waves
    float spec = pow(max(dot(N, H), 0.0), 96.0) * 1.15 * frame.sunDirection.w;
    float3 reflection = frame.fogColor.rgb * (0.28 + 0.55 * fresnel);

    // Subtle wave crest foam
    float foam = smoothstep(0.18, 0.28, in.worldPosition.y - frame.fogParams.y) * 0.22;
    float3 waterColor = mix(diffuse, reflection, saturate(fresnel * 0.65)) + frame.sunColor.rgb * spec + float3(foam);

    float3 finalColor = applyFog(waterColor, in.worldPosition, frame);
    return float4(finalColor, 0.86);
}
