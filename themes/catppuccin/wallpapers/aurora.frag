#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec3 colorMauve;
    vec3 colorLavender;
    vec3 colorBlue;
    float intensity;
};

layout(binding = 1) uniform sampler2D baseSource;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        v += amp * noise(p);
        p *= 2.02;
        amp *= 0.5;
    }
    return v;
}

void main() {
    vec4 base = texture(baseSource, qt_TexCoord0);

    vec2 p = vec2(qt_TexCoord0.x * 3.0, qt_TexCoord0.y * 6.0) + vec2(time * 0.12, -time * 0.07);
    float n = fbm(p);
    float band = smoothstep(0.15, 0.85, n) * smoothstep(1.0, 0.6, qt_TexCoord0.y);

    vec3 glow = mix(colorBlue, colorMauve, qt_TexCoord0.x);
    glow = mix(glow, colorLavender, n);

    vec3 result = mix(base.rgb, glow, clamp(band * intensity, 0.0, 1.0));
    fragColor = vec4(result, base.a) * qt_Opacity;
}
