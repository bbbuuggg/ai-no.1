class_name LLMConfig
extends RefCounted
## LLM 配置加载器
##
## API Key 来源优先级（由高到低）：
##   1. 环境变量 NULL_LLM_API_KEY  （CI / 临时调试）
##   2. user://llm_config.cfg     （玩家自带 Key）
##   3. res://config/llm_config.dev.cfg  （开发期内置 Key，已加入 .gitignore）
##   4. 全部失败 → active = "mock"，使用离线 Mock Provider
##
## 配置文件 schema（ConfigFile 格式）：
##   [provider]
##   active = "deepseek" | "openai" | "mock"
##
##   [deepseek]
##   api_key = "sk-xxx"
##   base_url = "https://api.deepseek.com/v1"
##   model = "deepseek-chat"
##   temperature = 0.7
##   max_tokens = 2000
##   timeout_sec = 30.0
##
##   [debug]
##   show_llm_reasoning = false
##   force_rule_ai = false
##   log_prompts = false
##   log_path = ""   ; 空 = 自动：导出版写 exe 同级目录、编辑器写 user://llm_log.txt

const USER_CONFIG_PATH := "user://llm_config.cfg"
const DEV_CONFIG_PATH := "res://config/llm_config.dev.cfg"
const ENV_KEY_NAME := "NULL_LLM_API_KEY"

# ============================================================
# 【单一真源】LLM max_tokens 全局上限
# ============================================================
# 修改这一处即可调整整个项目的 max_tokens —— 所有 provider、所有配置文件、
# 所有运行时调用都以此为准。会强制覆盖：
#   • dev.cfg / user://llm_config.cfg 中的 max_tokens 字段
#   • LLMProviderBase / OpenAICompatProvider 内部默认值
#   • OpenAICompatProvider 曾经的 1200 硬编码下限
#
# 历史背景：之前各处分散写 800 / 1200 / 2000，
# 改 dev.cfg 不生效，log 里 completion_tokens 一直卡在 1200，
# 根因即 OpenAICompatProvider 的 maxi(max_tokens, 1200) 兜底。
#
# 经验值：DeepSeek-Reasoner 等推理模型 reasoning + JSON 输出至少需要 ~1500，
# 低于此值容易触发 finish=length 截断 → fallback。建议 ≥ 2000。
const MAX_TOKENS_OVERRIDE: int = 2000
# ============================================================

# 解析后的有效配置
var active_provider: String = "mock"
var api_key: String = ""
var base_url: String = ""
var model: String = ""
var temperature: float = 0.7
# 注意：此字段会在 load() 末尾被强制覆盖为 MAX_TOKENS_OVERRIDE，cfg 中读到的值仅用于日志/调试参考。
var max_tokens: int = MAX_TOKENS_OVERRIDE
var timeout_sec: float = 30.0

# ============================================================
# 【调试开关默认值】—— 代码硬编码（不依赖任何 cfg 文件）
# ============================================================
# 这些是"出厂默认值"。任何 cfg（user 或 dev）都可以覆盖；
# 但如果两份 cfg 都不存在，依然按这里的值生效 —— 这样打包给朋友
# 试玩时，无需任何配置文件就能拿到完整 LLM 日志。
const DEFAULT_SHOW_LLM_REASONING: bool = true
const DEFAULT_FORCE_RULE_AI: bool = false
const DEFAULT_LOG_PROMPTS: bool = true
# log_path 默认值在 _resolve_log_path("") 里动态生成：
#   编辑器  → user://llm_log.txt
#   导出版  → exe 同级目录/llm_log.txt
const DEFAULT_LOG_PATH: String = ""
# ============================================================

# 调试开关（运行时值，load() 中按 默认 → cfg 顺序填充）
var show_llm_reasoning: bool = DEFAULT_SHOW_LLM_REASONING
var force_rule_ai: bool = DEFAULT_FORCE_RULE_AI
var log_prompts: bool = DEFAULT_LOG_PROMPTS
var log_path: String = "user://llm_log.txt"  # 占位，load() 中会被 _resolve_log_path 覆盖

# 来源标记（调试用）
var key_source: String = "none"


## 加载配置（按优先级链）
##
## 决定 active_provider 的逻辑（越靠后优先级越高）：
##   1. 默认 "mock"
##   2. dev.cfg 的 [provider]active（开发期接管）
##   3. user://llm_config.cfg 的 [provider]active（玩家配置；若仍是 "mock" 模板默认值则不覆盖 dev）
##
## 这样：玩家未动 user 文件时，dev 决定 provider；玩家明确选了非 mock 的 active 后，user 接管。
func load() -> void:
	# 步骤 1: 确保 user 配置文件存在（首启写模板，模板默认 active=mock）
	_ensure_user_template()

	# 步骤 2: 加载两份 cfg
	var user_cfg := ConfigFile.new()
	var has_user: bool = (user_cfg.load(USER_CONFIG_PATH) == OK)
	var dev_cfg := ConfigFile.new()
	var has_dev: bool = (dev_cfg.load(DEV_CONFIG_PATH) == OK)

	# 步骤 3: 决定 active_provider —— dev 先填，user 非 mock 才覆盖
	var dev_active: String = ""
	if has_dev:
		dev_active = String(dev_cfg.get_value("provider", "active", ""))
	var user_active: String = ""
	if has_user:
		user_active = String(user_cfg.get_value("provider", "active", "mock"))

	if user_active.length() > 0 and user_active != "mock":
		# 玩家明确选了非 mock provider，听玩家
		active_provider = user_active
	elif dev_active.length() > 0:
		# 否则看 dev（原型阶段）
		active_provider = dev_active
	elif user_active.length() > 0:
		# dev 没说 → 听 user（即使是默认 mock 也认）
		active_provider = user_active
	else:
		active_provider = "mock"

	# 步骤 4: 调试开关 —— 优先级：user cfg > dev cfg > 代码硬编码默认值。
	# 即使两份 cfg 都不存在，也按 DEFAULT_* 常量工作（试玩零配置）。
	show_llm_reasoning = _pick_debug_bool(user_cfg, dev_cfg, has_user, has_dev, "show_llm_reasoning", DEFAULT_SHOW_LLM_REASONING)
	force_rule_ai = _pick_debug_bool(user_cfg, dev_cfg, has_user, has_dev, "force_rule_ai", DEFAULT_FORCE_RULE_AI)
	log_prompts = _pick_debug_bool(user_cfg, dev_cfg, has_user, has_dev, "log_prompts", DEFAULT_LOG_PROMPTS)
	log_path = _resolve_log_path(_pick_debug_string(user_cfg, dev_cfg, has_user, has_dev, "log_path", DEFAULT_LOG_PATH))

	# 步骤 5: 如果是 mock，直接返回
	if active_provider == "mock":
		api_key = ""
		key_source = "mock"
		return

	# 步骤 6: 取参数 —— user 优先，无则 dev
	api_key = _pick_string(user_cfg, dev_cfg, has_user, has_dev, active_provider, "api_key", "")
	base_url = _pick_string(user_cfg, dev_cfg, has_user, has_dev, active_provider, "base_url", _default_base_url(active_provider))
	model = _pick_string(user_cfg, dev_cfg, has_user, has_dev, active_provider, "model", _default_model(active_provider))
	temperature = _pick_float(user_cfg, dev_cfg, has_user, has_dev, active_provider, "temperature", 0.7)
	max_tokens = int(_pick_float(user_cfg, dev_cfg, has_user, has_dev, active_provider, "max_tokens", 2000))
	timeout_sec = _pick_float(user_cfg, dev_cfg, has_user, has_dev, active_provider, "timeout_sec", 30.0)

	# 步骤 7: 环境变量覆盖 API Key（最高优先级）
	var env_key: String = OS.get_environment(ENV_KEY_NAME)
	if env_key.length() > 0:
		api_key = env_key
		key_source = "env"
	elif has_user and String(user_cfg.get_value(active_provider, "api_key", "")).length() > 0:
		key_source = "user"
	elif has_dev and String(dev_cfg.get_value(active_provider, "api_key", "")).length() > 0:
		key_source = "dev"
	elif api_key.length() > 0:
		key_source = "default"
	else:
		key_source = "none"

	# 步骤 8: 如果开启 log_prompts，每次启动游戏清空日志（方便看当前会话的完整链路）
	if log_prompts:
		_truncate_log_file()

	# 步骤 9: 【单一真源】强制覆盖 max_tokens —— 无论 cfg 写了什么，都以 MAX_TOKENS_OVERRIDE 为准。
	# 这样修改顶部那个常量就是唯一手改入口，避免分散在多个 cfg / 默认值里。
	max_tokens = MAX_TOKENS_OVERRIDE


## 清空日志文件（保留文件本身，截断到 0 长度）
func _truncate_log_file() -> void:
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	if f == null:
		push_warning("[LLMConfig] 无法清空日志文件: %s" % log_path)
		return
	var ts: String = Time.get_datetime_string_from_system()
	f.store_string("# LLM Boss AI 日志 — 会话启动 %s\n" % ts)
	f.store_string("# provider=%s  model=%s  key_source=%s\n" % [active_provider, model, key_source])
	f.close()


## 是否已正确配置（调用方据此决定走 LLM 还是 fallback）
##
## v0.4.1 起：mock 不再被视为"ready"，即 active=mock 会走规则 AI fallback。
## 这样不会误导用户以为 LLM 在跑。
func is_ready_for_llm() -> bool:
	if force_rule_ai:
		return false
	if active_provider == "mock":
		return false  # ← 禁用 mock，走规则 AI 兜底
	return api_key.length() > 0 and base_url.length() > 0 and model.length() > 0


## 创建 Provider 实例（由 LLMBossAI 调用）
## mock 模式下返回 null（调用方应检查 is_ready_for_llm() 避免走到这里）
func make_provider() -> LLMProviderBase:
	if active_provider == "mock":
		return null
	# OpenAI 兼容协议（DeepSeek/智谱/通义/Moonshot 等）
	var p := OpenAICompatProvider.new()
	p.api_key = api_key
	p.base_url = base_url
	p.model = model
	p.temperature = temperature
	# 【单一真源】Provider 的 max_tokens 永远以 MAX_TOKENS_OVERRIDE 为准，忽略 cfg。
	p.max_tokens = MAX_TOKENS_OVERRIDE
	p.timeout_sec = timeout_sec
	return p


## 把 API Key 安全打码（日志/UI 显示用）
static func mask_key(key: String) -> String:
	if key.length() <= 8:
		return "***"
	return key.substr(0, 4) + "****" + key.substr(key.length() - 4, 4)


# ------------------------------------------------------------------
# 内部工具
# ------------------------------------------------------------------
func _ensure_user_template() -> void:
	if FileAccess.file_exists(USER_CONFIG_PATH):
		return
	var f := FileAccess.open(USER_CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(_template())
	f.close()


func _template() -> String:
	return """[provider]
; active 选项: deepseek | openai | mock
active = "mock"

; ⚠️ 注意：max_tokens 字段已被 LLMConfig.MAX_TOKENS_OVERRIDE 强制覆盖（单一真源），
;    在此修改不会生效。若要调整请改 scripts/ai/config/llm_config.gd 顶部的常量。

[deepseek]
api_key = ""
base_url = "https://api.deepseek.com/v1"
model = "deepseek-chat"
temperature = 0.7
max_tokens = 2000  ; ← 已被 LLMConfig.MAX_TOKENS_OVERRIDE 覆盖
timeout_sec = 30.0

[openai]
api_key = ""
base_url = "https://api.openai.com/v1"
model = "gpt-4o-mini"
temperature = 0.7
max_tokens = 2000  ; ← 已被 LLMConfig.MAX_TOKENS_OVERRIDE 覆盖
timeout_sec = 30.0

[debug]
; 调试开关默认与 LLMConfig.DEFAULT_* 常量保持一致
; log_path = "" 表示自动：编辑器内写 user://llm_log.txt，导出版写 exe 同级目录
show_llm_reasoning = true
force_rule_ai = false
log_prompts = true
log_path = ""
"""


func _default_base_url(provider: String) -> String:
	match provider:
		"deepseek": return "https://api.deepseek.com/v1"
		"openai": return "https://api.openai.com/v1"
	return ""


func _default_model(provider: String) -> String:
	match provider:
		"deepseek": return "deepseek-chat"
		"openai": return "gpt-4o-mini"
	return ""


func _pick_string(user_cfg: ConfigFile, dev_cfg: ConfigFile, has_user: bool, has_dev: bool, section: String, key: String, default: String) -> String:
	if has_user:
		var v := String(user_cfg.get_value(section, key, ""))
		if v.length() > 0:
			return v
	if has_dev:
		var v2 := String(dev_cfg.get_value(section, key, ""))
		if v2.length() > 0:
			return v2
	return default


func _pick_float(user_cfg: ConfigFile, dev_cfg: ConfigFile, has_user: bool, has_dev: bool, section: String, key: String, default: float) -> float:
	if has_user and user_cfg.has_section_key(section, key):
		return float(user_cfg.get_value(section, key, default))
	if has_dev and dev_cfg.has_section_key(section, key):
		return float(dev_cfg.get_value(section, key, default))
	return default


## debug 段：user 优先，user 没有 key 才用 dev（与 _pick_string 对 provider 段的策略一致）
func _pick_debug_bool(user_cfg: ConfigFile, dev_cfg: ConfigFile, has_user: bool, has_dev: bool, key: String, default: bool) -> bool:
	if has_user and user_cfg.has_section_key("debug", key):
		return bool(user_cfg.get_value("debug", key, default))
	if has_dev and dev_cfg.has_section_key("debug", key):
		return bool(dev_cfg.get_value("debug", key, default))
	return default


func _pick_debug_string(user_cfg: ConfigFile, dev_cfg: ConfigFile, has_user: bool, has_dev: bool, key: String, default: String) -> String:
	if has_user and user_cfg.has_section_key("debug", key):
		var v := String(user_cfg.get_value("debug", key, ""))
		if v.length() > 0:
			return v
	if has_dev and dev_cfg.has_section_key("debug", key):
		var v2 := String(dev_cfg.get_value("debug", key, ""))
		if v2.length() > 0:
			return v2
	return default


## 解析 log_path：
##   - 空字符串 → 自动模式：导出版写 exe 同级目录的 llm_log.txt；编辑器内写 user://llm_log.txt
##   - "user://..." 或 "res://..." → 原样
##   - 绝对路径（含盘符或 /）→ 原样
##
## 设计目的：dev.cfg 里写 log_path = ""（打包默认值），让朋友打开 exe 后，
## 日志直接写在 exe 同级目录，方便他打 zip 发回来。
func _resolve_log_path(raw: String) -> String:
	if raw.length() == 0:
		# 编辑器：保持 user://（避免污染项目目录）
		if OS.has_feature("editor"):
			return "user://llm_log.txt"
		# 导出版：写到 exe 同级目录
		var exe_dir: String = OS.get_executable_path().get_base_dir()
		if exe_dir.length() > 0:
			return exe_dir.path_join("llm_log.txt")
		return "user://llm_log.txt"
	return raw
