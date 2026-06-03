# 参考架构：AsyncAgent 协议 + 工厂注册表（多 agent 可插拔）

提炼自姊妹项目 **AutoGLM-GUI**（Python，Apache-2.0，作者 suyiiyii）的 agent 层设计，
作为 scrcpy_mcp 将来需要「多底座/多后端切换」时的参考模式。
相关：[gui-agent-base-model-selection.md](./gui-agent-base-model-selection.md)、[langchain-dart-tool-adapter.md](./langchain-dart-tool-adapter.md)。

## 核心结论

AutoGLM-GUI **没有套用任何现成 agent 框架**（无 LangChain / LlamaIndex），而是：

1. 自研一个统一接口 `AsyncAgent`（Protocol）；
2. 用工厂 + 注册表按字符串名创建 agent；
3. 把外部框架（DroidRun、Midscene）降级为**可插拔后端**，写适配器接入。

这与 scrcpy_mcp 自研 `McpTool` 抽象的哲学一致——是「要不要上 LangChain」的现成反例：**选自研薄壳，外部框架当后端**。

## 模式结构

```
AsyncAgent (自研统一接口: stream / run / cancel / reset / step)
        ▲  各实现/适配它，事件统一为 {type, data}
┌───────┼───────┬───────┬─────────┬──────────┐
glm    mai   gemini  droidrun  midscene
(自研) (自研) (自研)  (适配)    (适配)
```

## 两个关键文件的职责

### `protocols.py` — 统一接口

`AsyncAgent` Protocol 规定所有 agent 实现：
- `stream(task) -> AsyncIterator[dict]`：核心，流式产出事件
- `run / cancel / reset / step` + `step_count / context / is_running` 属性
- 统一事件类型：`thinking` / `step` / `done` / `cancelled` / `error`，格式 `{"type": str, "data": dict}`

### `factory.py` — 工厂 + 注册表

```python
AGENT_REGISTRY: dict[str, Callable[..., AsyncAgent]] = {}

def register_agent(agent_type, creator): ...
def create_agent(agent_type, model_config, agent_config, ..., device): ...

# 注册即插拔，加新 agent 不动现有代码
register_agent("glm-async", _create_async_glm_agent)
register_agent("droidrun", _create_droidrun_agent)
register_agent("midscene", _create_midscene_agent)
```

统一的 creator 签名：`(model_config, agent_config, agent_specific_config, device, takeover_callback, confirmation_callback) -> AsyncAgent`。

## 已接入的 6 类 agent

| 注册名 | 实现 | 性质 / 路线 |
|---|---|---|
| `glm-async` / `async-glm` | AsyncGLMAgent | 自研，原生 GLM/AutoGLM 视觉 |
| `mai` | AsyncMAIAgent | 自研，带轨迹记忆 traj_memory |
| `gemini` / `general-vision` | AsyncGeminiAgent | 自研，OpenAI 兼容 function-calling，通用视觉模型 |
| `droidrun` | DroidRunAgent | 适配 DroidRun（无障碍树 + index 路线） |
| `midscene` | AsyncMidsceneAgent | 适配 Midscene.js CLI（需 Node/npx，视觉路线） |

自研三个直接用 `openai` SDK 写 prompt/parser/action_mapper，不靠框架。
`droidrun` 为可选依赖（`optional-dependencies`）。

## 值得借鉴的点（对 scrcpy_mcp）

1. **工厂注册表 = 多底座切换的干净解法**：将来接 UI-TARS / Qwen2.5-VL / AutoGLM，各写一个 adapter 注册进去，调用方只认字符串名，符合「不过度设计」。
2. **统一事件流**：把不同后端的内部事件归一成 `{type, data}`，上层 UI/日志只对接一种格式。
3. **外部框架当后端**：DroidRun/Midscene 作为适配器接入而非项目地基，可选依赖、坏了不影响主线。
4. **两条感知路线并存**：DroidRun 走无障碍树（纯文本 LLM 可用），其余走截图视觉——多路线互补兜底，与本仓「端侧/云端分流」同思路。

## 适配器实现注意（来自 droidrun adapter 的教训）

- `is_running` / `context` 等属性若只写桩（返回 False/[]），会让依赖它的上层 UI 状态错乱——实现 adapter 时别漏。
- `takeover_callback` / `confirmation_callback` 若忽略，则该后端不支持人工接管/确认，应在 UI 标注能力差异。
- 协作式取消（检查 cancel flag）在后端长阻塞时有延迟，需知悉。

## 出处

基于 AutoGLM-GUI 源码 `AutoGLM_GUI/agents/{protocols,factory}.py` 及各 adapter 阅读整理。
