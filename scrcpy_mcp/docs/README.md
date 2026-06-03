# scrcpy_mcp 调研笔记索引

围绕「给 scrcpy_mcp 接入 GUI agent」的一系列调研与选型笔记。
主题贯穿：端侧/云端分流、底座模型选型、agent 框架取舍、以及接入 GLM/AutoGLM 输出的具体换算。

## 笔记一览

| 笔记 | 主题 | 一句话结论 |
|---|---|---|
| [hybrid-agent-routing.md](./hybrid-agent-routing.md) | 端侧/云端分流架构 | 确定性语义动作走端侧 FunctionGemma，需看屏/坐标/多步走云端 AutoGLM |
| [functiongemma-confidence.md](./functiongemma-confidence.md) | FunctionGemma 置信度方案 | 模型不输出置信度，优先用「结构性硬门控」（JSON Schema 校验）判是否上云 |
| [gui-agent-base-model-selection.md](./gui-agent-base-model-selection.md) | 视觉 agent 底座选型 | 先用 UI-TARS-1.5-7B（Qwen2.5-VL 底座、Apache-2.0）跑通闭环，攒数据后再决定是否换 Qwen2.5-VL 重训 |
| [multi-agent-adapter-pattern.md](./multi-agent-adapter-pattern.md) | 多 agent 可插拔模式 | 参考 AutoGLM-GUI：自研 AsyncAgent 协议 + 工厂注册表，外部框架当后端 |
| [langchain-dart-tool-adapter.md](./langchain-dart-tool-adapter.md) | LangChain.dart 编排（备选） | 能干净包住 MCP 工具，但仅在「多底座切换+复杂编排」时才值得引；当前不实施 |
| [glm-action-mapping.md](./glm-action-mapping.md) | 接 GLM/AutoGLM 输出 | 坐标是 0–999 归一化需换算成像素；动作 DSL → MCP 工具映射表 |

## 阅读顺序建议

1. **想了解整体思路** → 先读 `hybrid-agent-routing.md`（全局分流架构）。
2. **要选模型/框架** → `gui-agent-base-model-selection.md` + `multi-agent-adapter-pattern.md`。
3. **要动手接入** → `glm-action-mapping.md`（坐标换算与动作映射是第一道坎）+ `functiongemma-confidence.md`（端侧路由判定）。
4. **重构评估** → `langchain-dart-tool-adapter.md`（仅备选预研）。

## 核心结论速记

- **架构哲学**：自研薄壳（McpTool / AsyncAgent）+ 外部框架当可插拔后端，优于直接套 LangChain。
- **两条感知路线**：截图视觉（需 grounding 模型，本仓现状）vs 无障碍树（纯文本 LLM 可用，DroidRun 路线）——可互补兜底。
- **接 GLM 第一坑**：输出坐标是 0–999 归一化，必须 `/1000*屏宽高` 换算，且别与 scrcpy 内部 rescale 叠错。
