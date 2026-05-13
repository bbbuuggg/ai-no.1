class_name AIDecisionInterface
extends RefCounted
## Boss AI 决策抽象接口
##
## 所有 Boss AI 实现（规则版、LLM 版、未来其它）都必须继承此类并实现统一的异步签名。
##
## 设计要点：
##   - 即使是同步规则 AI，也走 await 模式，调用方零分支
##   - 返回 Array[CardData]：Boss 选定的暗出牌（已排序）
##   - 失败时不抛异常，由实现自行 fallback，对外保证总是返回合法数组
##
## 调用方约定（参见 blind_clash_battle._start_blind_phase）：
##   var ai := <某个实现>.new()
##   var cards: Array[CardData] = await ai.select_blind_cards_async(boss, player, trap_slots, probe)
##
## 设计文档：docs/design/architecture/adr-001-llm-boss-ai.md

# 决策完成信号（即使同步实现也通过 emit 触发，统一异步流程）
signal decision_ready(cards: Array[CardData])


## 异步选取暗出牌
## @param boss          Boss Combatant 实例
## @param player        玩家 Combatant 实例
## @param trap_slots    玩家陷阱槽位 [TrapData|null × 3]
## @param probe         认知探针实例（用作 AI 直觉提示）
## @param peeked_cards  v0.4.3 新增：已被 peek 洞察泄露的玩家手牌（Array[CardData]，默认空）
## @return              已排序的 Array[CardData]
func select_blind_cards_async(_boss: Combatant, _player: Combatant, _trap_slots: Array, _probe: CognitiveProbe, _peeked_cards: Array = []) -> Array[CardData]:
	push_error("AIDecisionInterface.select_blind_cards_async() 必须被子类实现")
	return []


## 提前预热（DEPLOY 阶段调用，让异步实现可以提前发请求）
## 默认实现是 no-op，LLM 实现需覆盖。
## @param peeked_cards  v0.4.3 新增：已被 peek 洞察泄露的玩家手牌，规则 AI 可忽略
func warm_up(_boss: Combatant, _player: Combatant, _trap_slots: Array, _probe: CognitiveProbe, _peeked_cards: Array = []) -> void:
	pass


## 是否处于"思考中"（用于 UI 决定是否显示等待动画）
func is_thinking() -> bool:
	return false


## 取消进行中的决策（玩家退出战斗时调用）
func cancel() -> void:
	pass
