# Project Commit Log

> 项目级时间轴。每次有意义的推进节点都追加一行。格式：`YYYY-MM-DD HH:MM | agent | 一句话描述 | 产出文件`

---

2026-05-12 10:50 | vibe-lead+lead-programmer+ux-lead | v0.3.1 体验迭代周：对决节奏放慢(3.5s/对)+Boss预判延后到暗出确认后公布+对决牌面显示×倍率=结果计算式+陷阱可放任意槽位+陷阱效果常驻显示+约束面板UI优化+常驻手牌扇形居中+多轮UI bug修复(card_ui._input全局吞点击/HBoxContainer强制左对齐/base_position时序) | scripts/ui/* + scripts/battle/blind_clash_scene.gd + scenes/battle/blind_clash_scene.tscn
2026-05-06 15:45 | vibe-lead+lead-programmer | 暗出对决UI全套实现：BlindSelectUI(选牌+排列+0费绑定)+TrapDeployUI(3槽位+空白牌)+ClashDisplayUI(逐张翻牌+克制动画)+ProbeDisplayUI(探针面板)+BlindClashScene场景+CardDatabase陷阱牌表 | scripts/ui/blind_select_ui.gd + trap_deploy_ui.gd + clash_display_ui.gd + probe_display_ui.gd + scripts/battle/blind_clash_scene.gd + scenes/battle/blind_clash_scene.tscn
2026-05-06 15:36 | vibe-lead+game-designer+lead-programmer | 机制重构v0.3：暗出对决系统(Blind Clash)+约束陷阱(3槽位+空白牌)+认知探针(Boss猜测+洞察+窥视/干扰/夺取)+碰撞结算引擎(三角克制×1.5/×0.5) | docs/design/gdd/04-blind-clash-revision.md + scripts/battle/blind_clash_battle.gd + clash_resolver.gd + trap_data.gd + cognitive_probe.gd + scripts/ai/blind_clash_ai.gd
2026-04-30 19:52 | vibe-lead+lead-programmer | Windows 打包完成：NULL_Protocol.exe 独立可执行(100MB，PCK内嵌) | build/NULL_Protocol.exe + export_presets.cfg
2026-04-30 19:35 | vibe-lead+lead-programmer | UI全面放大(1920×1080)+血条面板(HP/护甲/能量水晶)+飘字特效(伤害/治疗/护甲)+屏幕震动+约束生效中央提示+意图去数值 | scripts/ui/combatant_panel.gd + scripts/ui/battle_effects.gd + 各UI尺寸调整
2026-04-30 19:10 | vibe-lead+lead-programmer | Boss意图预告系统：提前决策+意图类型分析(攻/防/蓄/治/干扰)+UI脉冲预告+危险提示 | scripts/battle/boss_intent.gd + scripts/ui/intent_display.gd
2026-04-30 15:30 | vibe-lead+lead-programmer | Boss逐张出牌延迟(0.6s间隔)+约束阻止提示+层间奖励界面(三选一×2轮)+奖励流程集成 | scripts/battle/ + scripts/ui/reward_screen.gd
2026-04-30 14:25 | vibe-lead+lead-programmer | 视觉升级方案C：3D牌桌(CSG+赛博Shader)+Boss全息体(旋转+扫描线)+暗色UI主题+SubViewport分层架构 | scenes/battle/ + assets/shaders/ + scripts/ui/
2026-04-30 14:10 | vibe-lead+lead-programmer | Godot战斗原型骨架v0.1：CardData/ConstraintData Resource、Combatant状态机、BattleManager回合管理、RuleAI三层决策、CardDatabase(全牌表)、战斗场景+简易UI | scripts/ + scenes/battle/ + autoload/
2026-04-30 13:22 | vibe-lead+game-designer | 第一层卡牌数据表v1.0：玩家20张+Boss25张+约束令3枚+层间奖励6张+数值验证 | docs/design/gdd/03-card-data-layer1.md
2026-04-30 13:15 | vibe-lead+game-designer | GDD 方向修正v0.2：Boss也打牌(对称规则)、约束令重设计(限牌/限资源/幻觉三维度)、LLM接口预定义、一个AI核心+附身机制世界观 | docs/design/gdd/02-symmetric-duel-revision.md
2026-04-30 12:40 | vibe-lead+game-designer | 完成《NULL Protocol》Design Pillars(4条) + 核心循环GDD v0.1（回合结构/资源系统/Boss Rush流程/难度模型/开发模式需求） | docs/design/gdd/01-design-pillars-and-core-loop.md
2026-04-30 12:00 | vibe-lead+creative-director | 确认游戏世界观：赛博朋克"驯码师"主题，2.5D+全息几何Boss，7层深井结构，3个结局方向 | 会话记录（待正式写入worldbuilding.md）
2026-04-30 11:30 | vibe-lead+creative-director+game-designer | 卡牌游戏头脑风暴：3主题方向+10种debuff+难度曲线+Boss AI方案+经济系统+Godot实现建议 | 会话记录
2026-04-30 10:30 | vibe-lead | 修复 subagent 名称解析 bug：16 agent name 字段中文→英文 kebab-case，vibe-lead 分流表改为英文 ID | .codebuddy/agents/*.md（16 个文件）
2026-04-29 14:54 | vibe-lead+creative-director+game-designer+technical-director | AI 游戏玩法全景评估（7 种玩法 MDA 拆解+Godot 可行性）| docs/design/ai-gameplay-analysis.md
2026-04-29 10:10 | migration-script | 完成从 CCGS 迁移到 Godot-Vibe-Studio | 整仓 70+ 文件
2026-04-29 10:10 | vibe-lead | Studio 就绪，等待第一个游戏项目启动 | —

<!-- 新条目插入上方。保持倒序（最新在最上）-->
