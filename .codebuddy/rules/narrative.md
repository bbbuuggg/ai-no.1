# 叙事内容规则

- 对白、剧情、任务描述统一放 `docs/design/narrative/`
- 所有面向玩家文字走 `TranslationServer`（见 `ui-code.md`）
- 风格指南：`docs/design/narrative/style-guide.md`（项目启动时产出）
- 角色对白表：`docs/design/narrative/dialogues/[character].md`
- 剧情梗概 → 分支 → 具体对白，三层结构
- 每个对白条目需有 ID、说话人、触发条件、后续选项
- Godot 对白系统推荐用 [Dialogic](https://github.com/coppolaemilio/dialogic) addon 或自实现 `.tres` Resource 表
- 所有 NPC 名字、地名、术语在 `docs/design/narrative/glossary.md` 维护，避免游戏内叫法不一致
