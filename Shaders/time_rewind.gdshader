shader_type canvas_item;

// Screen texture uniform (Godot 4 compatible)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Time rewind effect parameters
uniform float rewind_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float time_speed : hint_range(0.1, 5.0) = 1.0;
uniform float sepia_strength : hint_range(0.0, 1.0) = 0.7;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.4;
uniform float noise_intensity : hint_range(0.0, 0.5) = 0.15;
uniform float scan_lines : hint_range(0.0, 1.0) = 0.3;
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.005;

// Enhanced color grading for vintage look
uniform vec3 highlight_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 shadow_color : source_color = vec3(0.2, 0.15, 0.1);

// Generate noise function
float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

// Enhanced film grain with better performance
float grain(vec2 uv, float time) {
    float n = noise(uv * 10.0 + time * 0.5);
    n += noise(uv * 20.0 - time * 0.3) * 0.5;
    n += noise(uv * 40.0 + time * 0.7) * 0.25;
    return n / 1.75;
}

// Improved vignette effect
float vignette(vec2 uv) {
    vec2 center = uv - 0.5;
    float dist = length(center);
    return 1.0 - smoothstep(0.3, 0.8, dist * vignette_strength * 2.0);
}

// Sepia tone conversion
vec3 sepia(vec3 color) {
    vec3 sepia_color;
    sepia_color.r = dot(color, vec3(0.393, 0.769, 0.189));
    sepia_color.g = dot(color, vec3(0.349, 0.686, 0.168));
    sepia_color.b = dot(color, vec3(0.272, 0.534, 0.131));
    return mix(color, sepia_color, sepia_strength);
}

// Enhanced time distortion effect
vec2 time_distort(vec2 uv, float time) {
    float wave1 = sin(uv.y * 20.0 + time * 3.0) * 0.002;
    float wave2 = sin(uv.x * 15.0 - time * 2.0) * 0.001;
    // Add micro-distortions for more realism
    float micro_wave = sin(uv.y * 100.0 + time * 8.0) * 0.0003;
    return uv + vec2(wave1, wave2 + micro_wave) * rewind_intensity;
}

void fragment() {
    vec2 uv = SCREEN_UV;
    float time = TIME * time_speed;

    // Apply enhanced time distortion
    vec2 distorted_uv = time_distort(uv, time);

    // Chromatic aberration for vintage feel
    vec3 color;
    float aberration = chromatic_aberration * rewind_intensity;
    color.r = texture(screen_texture, distorted_uv + vec2(aberration, 0.0)).r;
    color.g = texture(screen_texture, distorted_uv).g;
    color.b = texture(screen_texture, distorted_uv - vec2(aberration, 0.0)).b;

    // Apply sepia tone
    color = sepia(color);

    // Add enhanced film grain
    float grain_value = grain(uv, time);
    color += (grain_value - 0.5) * noise_intensity;

    // Improved scan lines with dynamic intensity
    float scan_line_freq = 800.0 + sin(time * 0.5) * 50.0;
    float scan_line = sin(uv.y * scan_line_freq) * 0.5 + 0.5;
    color *= 1.0 - scan_lines * 0.3 * (1.0 - scan_line);

    // Apply enhanced vignette
    color *= vignette(uv);

    // Enhanced color grading for vintage atmosphere
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 graded_color = mix(shadow_color, highlight_color, luminance);
    color = mix(color, graded_color, 0.3);

    // Enhanced flickering effect for rewind ambience
    float main_flicker = 1.0 + sin(time * 10.0 + sin(time * 30.0) * 0.5) * 0.02 * rewind_intensity;
    float micro_flicker = 1.0 + sin(time * 50.0) * 0.01 * rewind_intensity;
    color *= main_flicker * micro_flicker;

    // Subtle reverse-time pulse with variation
    float pulse = 1.0 + sin(time * 2.0) * 0.05 * rewind_intensity;
    color *= pulse;

    // Enhanced desaturation for nostalgic feel
    float desaturation = 0.8 + sin(time * 0.3) * 0.1;
    float gray = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(gray), color, desaturation);

    // Temporal "hiccup" effect for rewind feeling
    float hiccup = 1.0 + step(0.98, sin(time * 25.0)) * 0.15 * rewind_intensity;
    color *= hiccup;

    // Subtle brightness boost and final adjustments
    color *= 1.05;
    color = clamp(color, 0.0, 1.0);

    COLOR = vec4(color, 1.0);
}