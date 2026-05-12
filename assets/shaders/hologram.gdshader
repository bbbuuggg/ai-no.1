shader_type spatial;
render_mode unshaded, cull_disabled;

// Boss 全息几何体 Shader — 半透明发光 + 旋转干扰
uniform vec4 holo_color : source_color = vec4(1.0, 0.4, 0.0, 0.7);
uniform float scan_speed : hint_range(0.0, 10.0) = 3.0;
uniform float scan_width : hint_range(0.01, 0.3) = 0.05;
uniform float glow_intensity : hint_range(0.0, 8.0) = 3.0;
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float edge_glow : hint_range(0.0, 5.0) = 2.0;

void fragment() {
    // 扫描线效果
    float scan = fract((UV.y + TIME * scan_speed * 0.1));
    float scan_line = smoothstep(0.0, scan_width, scan) * (1.0 - smoothstep(scan_width, scan_width * 2.0, scan));

    // 闪烁
    float flicker = 1.0 - flicker_intensity * step(0.95, fract(TIME * 13.7));

    // 边缘发光（基于法线与视角）
    float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);

    vec3 color = holo_color.rgb * glow_intensity * flicker;
    color += holo_color.rgb * fresnel * edge_glow;
    color += holo_color.rgb * scan_line * 2.0;

    ALBEDO = color;
    EMISSION = color;
    ALPHA = holo_color.a * flicker * (0.5 + fresnel * 0.5);
}
