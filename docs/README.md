# docs 索引

本项目（scrcpy + AutoGLM Android 自动化）的文档与参考资料。

## Midscene 系统提示词备份

从 [web-infra-dev/midscene](https://github.com/web-infra-dev/midscene) 抄录的三套 agent 提示词，commit `784ce3aab8fb6809a41f493a6ee0a3c3106dab28`，备份于 2026-06-05。本项目 `lib/src/agent/agent_config.dart` 的 `_kDefaultSystemPrompt` 即改编自其中的 AutoGLM 中文规划版。

| 文档 | Agent | 输出格式 | 坐标 | 动作示例 |
|------|-------|---------|------|---------|
| [midscene-autoglm-prompts.md](./midscene-autoglm-prompts.md) | **AutoGLM**（本项目所用）| `<think>` + `<answer>` | 0–999 归一化**点** | `do(action="Tap", element=[x,y])` |
| [midscene-uitars-prompt.md](./midscene-uitars-prompt.md) | **UI-TARS**（字节 GUI 模型）| `Thought:` / `Action:` | bbox 四元组 `[x1,y1,x2,y2]` | `click(start_box='[...]')` |
| [midscene-llm-prompts.md](./midscene-llm-prompts.md) | **通用 LLM**（GPT-4o / Qwen-VL / Gemini / Doubao）| XML 标签 + JSON | 真实像素 | `<action-type>Tap</action-type>` |

三套 agent 的职责与设计差异：

- **AutoGLM** — Python 风格 `do(...)` 伪代码，重中文 App（小红书/外卖/购物车）业务规则。本项目在其基础上**启用**了 midscene 禁用的 `Interact`/`Note`/`Call_API`/`Take_over`，并删去与 scrcpy 无关的规则。详见该文档末尾「与本项目 agent_config.dart 的差异」。
- **UI-TARS** — 纯文本 `Thought/Action`，bbox 四元组坐标，偏桌面通用 GUI（含 `hotkey`/`drag`/`left_double`）。
- **通用 LLM** — 最通用也最复杂：动作集由运行时 `actionSpace` 注入，规划提示词是代码动态拼接的大模板（含 subGoals / 记忆 / grounding 开关）。含 `定位` + `提取` + `规划` 三类职责。

> 提示词中的日期、语言、动作列表等均为运行时注入，文档内以 `{DATE}` / `{LANG}` / `{actionList}` 等占位。

## 规格与设计文档

- [specs/mcp_screen_recording_spec.md](./specs/mcp_screen_recording_spec.md) — MCP 录屏功能规格
- [superpowers/](./superpowers/) — 实现计划（`plans/`）与规格（`specs/`）
