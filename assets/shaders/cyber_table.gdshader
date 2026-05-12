shader_type spatial;
render_mode unshaded;

// 赛博朋克牌桌表面 Shader — 发光网格线
uniform vec4 base_color : source_color = vec4(0.02, 0.03, 0.05, 1.0);
uniform vec4 line_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float line_width : hint_range(0.001, 0.05) = 0.01;
uniform float grid_size : hint_range(0.1, 5.0) = 1.0;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.5;
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;

void fragment() {
    vec2 uv = UV * grid_size;
    vec2 grid = abs(fract(uv - 0.5) - 0.5);
    float line = min(grid.x, grid.y);
    float mask = 1.0 - smoothstep(0.0, line_width, line);

    // 脉冲动画
    float pulse = sin(TIME * pulse_speed) * 0.3 + 0.7;
    vec3 final_color = mix(base_color.rgb, line_color.rgb * glow_intensity * pulse, mask);

    ALBEDO = final_color;
    EMISSION = final_color * mask * glow_intensity * pulse;
}
