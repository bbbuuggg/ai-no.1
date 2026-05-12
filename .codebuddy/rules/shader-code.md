---
paths:
  - "assets/shaders/**"
  - "res://assets/shaders/**"
---

# 着色器代码规范（Godot 4.6 `.gdshader`）

本项目仅用 Godot 着色语言（`.gdshader`），不再涉及 Unity Shader Graph 或 Unreal Material。

## 命名规范

- 文件：`[type]_[category]_[name].gdshader`
  - `spatial_env_water.gdshader`（3D 环境水）
  - `canvas_ui_healthbar.gdshader`（2D UI）
  - `particles_combat_sparks.gdshader`（粒子）
- 用描述性名字，表明材质用途
- 着色器类型前缀：`spatial_`、`canvas_`、`particles_`、`fog_`、`sky_`

## 代码质量

- 所有 uniform 必须有描述性名字和合适的 hint（`source_color`、`hint_range`、`hint_normal`）
- 相关参数用 `group_uniforms` 分组
- 非显而易见的计算加注释（特别是数学密集段）
- **禁止**魔术数——用命名常量或文档化 uniform 值
- 每个着色器文件头部注释：作者、用途、目标平台

## 性能要求

- 记录每个着色器的目标平台和复杂度预算
- 移动端在不需全精度处用 `mediump` / `lowp`
- 最小化 fragment 着色器纹理采样
- 避免 fragment 动态分支——用 `step()`、`mix()`、`smoothstep()`
- **禁止**循环内纹理读取
- 模糊效果用两 pass（横 → 纵）

## 渲染管线

- 明确记录着色器目标渲染器：Forward+（桌面）/ Mobile / Compatibility
- 不同渲染管线的着色器不要混在同一目录

## 变体管理

- 最小化着色器变体——每个变体是独立编译
- 记录所有 define / 变体及其用途
- 尽可能用 feature stripping 减小构建体积
- 监控每着色器的总变体数

## 示例

**正确**：

```glsl
shader_type spatial;
// 作者: GodotVibeStudio team
// 用途: 水面材质 - 支持反射与扭曲
// 目标: Forward+ (桌面), 预算 2ms

group_uniforms surface;
uniform vec4 albedo_color : source_color = vec4(0.2, 0.5, 0.8, 0.8);
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform sampler2D normal_texture : hint_normal;
group_uniforms;

group_uniforms motion;
uniform vec2 scroll_speed = vec2(0.1, 0.05);
group_uniforms;

void fragment() {
    vec2 scrolled_uv = UV + TIME * scroll_speed;
    vec3 n = texture(normal_texture, scrolled_uv).rgb * 2.0 - 1.0;
    NORMAL_MAP = n;
    ALBEDO = albedo_color.rgb;
    ROUGHNESS = roughness;
}
```
