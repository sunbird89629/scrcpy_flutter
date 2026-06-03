# GUI Agent 底座选型笔记：Qwen2.5-VL vs UI-TARS

为 scrcpy_mcp 的「云端视觉 agent 线」（看截图→输出坐标动作→MCP→设备）挑选可微调的开源底座。
配套架构见 [hybrid-agent-routing.md](./hybrid-agent-routing.md)。

## 核心区别：两者不在同一层

- **Qwen2.5-VL = 通用多模态底座**：会看图、会定位，但**不懂 GUI 操作范式**。要从头教整套手机操作。
- **UI-TARS = 已成熟的 GUI agent**：本身就是在 Qwen-VL 上微调出来的，**自带 grounding + 多步规划 + 动作空间**。只需领域适配。

```
Qwen2.5-VL (通用VLM)  ──喂GUI操作数据微调──►  UI-TARS / 各家GUI agent
   ↑从这里起步：远、白纸                       ↑从这里起步：近、带既有偏好
```

## 对比表

| 维度 | Qwen2.5-VL 当底座 | UI-TARS 当底座 |
|---|---|---|
| 起点 | 通用 VLM，GUI 能力=0 | 已是成熟 GUI agent |
| 要补的活 | 整套 GUI 操作能力，**数据需求大** | 仅领域适配，**数据需求小** |
| 开箱效果 | 微调前几乎不能用 | 微调前**直接能跑**手机任务 |
| 多步规划 | 无，需自己训/搭框架 | **自带**（reasoning + 历史） |
| 动作空间 | 自由定义（最易对齐 MCP 工具） | 已有既定格式，沿用或改造 |
| 灵活度 | **高**（白纸，随意训） | 低（继承其设计取向） |
| 适合谁 | 想深度定制、有数据和算力 | 想快速拿到能用 agent、数据少 |

## UI-TARS 版本 / 底座 / License（HuggingFace 实测，ByteDance-Seed 出品）

| 版本 | 参数 | 底座 (base) | 后训练 |
|---|---|---|---|
| **UI-TARS-1.5-7B**（最新公开权重） | 7B | **Qwen2.5-VL** | RL 强化 |
| UI-TARS-2B-SFT | 2B | Qwen2-VL（初代） | SFT |
| UI-TARS-7B-SFT / 7B-DPO | 7B | Qwen2-VL | SFT / DPO |
| UI-TARS-72B-SFT / 72B-DPO | 72B | Qwen2-VL | SFT / DPO |
| UI-TARS-1.5（满血研究版） | 未公开 | — | SOTA，仅邮件申请研究访问 |

- **License：Apache 2.0** —— 可商用、可自由微调，对本项目无障碍（优于闭源的 AutoGLM）。
- **底座分代**：初代（2B/7B/72B 的 SFT/DPO）= Qwen2-VL；**UI-TARS-1.5-7B** 才换成 Qwen2.5-VL。要最新底座就用 1.5-7B。
- **尺寸**：2B / 7B / 72B 三档。**2B 仅初代（Qwen2-VL）**，1.5 目前只放了 7B → 「端侧轻量 + 最新底座」暂不可兼得。
- **本地运行**：社区有大量 GGUF 量化版（mradermacher / bartowski / lmstudio-community），可用 llama.cpp / LM Studio / Ollama 直接跑，2B 量化版可在较小显存起。

## 选型建议

| 目标 | 选择 |
|---|---|
| 跑通闭环最省力 | `ByteDance-Seed/UI-TARS-1.5-7B`，或先用社区 2B-SFT GGUF 本机试水 |
| 最新 Qwen2.5-VL 血统 + 深度定制 | UI-TARS-1.5-7B（2B 这档仍停在 Qwen2-VL） |
| 动作空间完全按 MCP 工具定制、有标注数据 | Qwen2.5-VL 白纸底座，喂自采操作轨迹重训 |

## 推荐路径（最低风险）

1. **先用 UI-TARS 跑通闭环**，拿到 baseline，验证「截图→模型→MCP→设备」整条链路 work。
   坐标型动作（`inject_touch/swipe/scroll`）正是 UI-TARS 强项。
2. **用 scrcpy 采集自己设备/app 上的真实操作轨迹**（本项目天然能采）。
3. **数据攒够后再决定**是否换 Qwen2.5-VL 从底座重训做深度定制。
   先借成品验证、再决定是否自造。

## 诚实边界

版本号、最新权重与 license 可能随上游更新；落地前建议再核对 HuggingFace 当前状态。
本笔记基于截至抓取时的 ByteDance-Seed 官方仓库信息。
