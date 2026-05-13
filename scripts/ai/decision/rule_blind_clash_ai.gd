class_name RuleBlindClashAI
extends AIDecisionInterface
## 规则版 Boss AI（异步外壳）
##
## 内部委托给原 BlindClashAI（保留原文件以保持其它代码引用不破裂）。
## 对外提供与 LLMBossAI 一致的 await 接口：
##   var cards = await ai.select_blind_cards_async(...)
##
## 调用是同步完成的（规则 AI 计算瞬时），但通过 process_frame await
## 让所有 AI 调用点共享同一种代码模式。

var _impl: BlindClashAI = BlindClashAI.new()


## 暴露 BlindClashAI 的性格参数（供 LLM fallback 时复用）
var aggression: float:
	get: return _impl.aggression
	set(v): _impl.aggression = v
var defense_bias: float:
	get: return _impl.defense_bias
	set(v): _impl.defense_bias = v
var risk_tolerance: float:
	get: return _impl.risk_tolerance
	set(v): _impl.risk_tolerance = v
var clash_style: String:
	get: return _impl.clash_style
	set(v): _impl.clash_style = v


func select_blind_cards_async(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe, _peeked_cards: Array = []) -> Array[CardData]:
	# 让出一帧避免和上游主循环紧耦合（保持异步语义统一）
	# 注意：规则 AI 暂不消费 peeked_cards（v0.4.3 仅 LLM 使用泄露牌信息）
	await Engine.get_main_loop().process_frame
	var cards: Array[CardData] = _impl.select_blind_cards(boss, player, trap_slots, probe)
	decision_ready.emit(cards)
	return cards


## 同步入口（仅供 LLM fallback 直接复用，不走 await）
func select_blind_cards_sync(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe) -> Array[CardData]:
	return _impl.select_blind_cards(boss, player, trap_slots, probe)
