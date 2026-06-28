# midscene planning 架构 + 与本仓 PhoneAgent 对照

> 调研对象：[web-infra-dev/midscene](https://github.com/web-infra-dev/midscene) commit `784ce3a`。
> 关键文件：`packages/core/src/agent/tasks.ts`（外层循环）、
> `packages/core/src/ai-model/llm-planning.ts`（一次决策）、
> `packages/core/src/ai-model/conversation-history.ts`（历史/记忆）、
> `packages/core/src/ai-model/models/auto-glm/planning.ts`（AutoGLM 专用）。
> 本仓对照对象：`lib/src/agent/phone_agent.dart`、`lib/src/tools/run_task.dart`。
> 相关：[glm-action-mapping.md](./glm-action-mapping.md)、[midscene-autoglm-prompts.md](../../docs/midscene-autoglm-prompts.md)。

## 0. planning 是什么

planning = agent 的「大脑」：**看一眼当前截图，决定下一个要在屏幕上执行的动作**（或宣布完成）。
它是闭环、逐步的——不是开头排好整条路径，而是「看截图 → 决定下一步 → 执行 → 再看新截图 → 再决定」（ReAct）。
高层指令（"查观看历史"）→ 具体动作（点 (969,2197)、向上滑）的现场翻译，就靠 planning。

一步里通常有三类 AI 能力，planning 只是其一：

| 能力 | 干什么 |
|------|--------|
| **planning** | 决定**做什么动作** |
| **locate** | 找元素**在哪**（坐标） |
| **extract / assert** | 读屏幕**内容** / 判断 |

VL 模型（AutoGLM）planning 与 locate 合一（直接吐坐标）；普通 LLM 两段式（先决策再单独定位）。

## 1. midscene 的两层架构

```
agent/tasks.ts  TaskExecutor.action()        ← 外层驱动循环（while true，反复问）
        │ 每轮调用 planImpl
        ▼
adapter.planning.kind === 'custom' ? planFn : genericXmlPlan
        ├── 通用 LLM：plan() @ llm-planning.ts        （XML 协议，功能全）
        └── AutoGLM / UI-TARS：各自 planning.ts        （自有格式，简单）
        │ 共享
        ▼
ConversationHistory（messages + subGoals + memories + logs）
```

**AutoGLM 走 custom 分支**（`tasks.ts:442`），用 `<think>/<answer>` + `do()` 解析，不走通用 XML planning；但与通用 LLM **共用同一个外层循环**。

### 外层循环（`tasks.ts` `while(true)`，行号真实）

```ts
while (true) {                                    // :396
  planResult = await planImpl(userInstruction, {  // :450  问助手：下一步？
    context, conversationHistory, actionSpace, … });
  const plans = planResult?.actions || [];        // :540  ≤1 个动作
  executables = await convertPlanToExecutable(plans, …);  // :545  翻成可执行（含 locate）
  await session.appendAndRun(executables.tasks);  // :575  照做
  if (!planResult?.shouldContinuePlanning) break; // :601  "搞定了" → 退出
  ++replanCount;                                  // :615
  if (replanCount > replanningCycleLimit) …       // :617  问太多次 → 放弃
}
```

附带：每轮检查 `abortSignal`；单轮执行错误累加 `errorCountInOnePlanningLoop`，超阈值才停；
replan 前把命中缓存的 locate 标记失效（避免错误元素被下次优先命中，issue #2529）。

### 一次决策（`plan()` @ `llm-planning.ts`）

1. 建 system prompt（`systemPromptToTaskPlanning`：actionSpace、是否 subgoals、是否 planning 内定位）
2. `prepareModelImage` 预处理截图
3. 组装 `system + <user_instruction> + history`；history 含 **memories + 进度(subgoals/historical logs) + 最新截图**
4. `compressHistory(50, 20)` 压缩超长历史
5. `callAI` →（解析失败**自动重试一次**）→ `parseXMLPlanningResponse`
6. **locate 归一化**：VL 模式把模型坐标 → 像素 bbox；prompt-only 模式丢坐标只留 prompt
7. 更新 ConversationHistory（subgoals/memory/log + assistant 原文），返回 `{actions, shouldContinuePlanning, …}`

### XML 响应协议（通用 planning）

`<thought>`（必出）、`<action-type>`+`<action-param-json>`、`<complete success>`（→ 停）、
`<log>`、`<memory>`、`<error>`、`<update-plan-content>`/`<mark-sub-goal-done>`（仅 deepThink）。

### 两个开关

- **deepThink**：开 → 子目标状态机（拆任务、prompt 含 subgoals）；关 → 只累积 historical logs。
- **includeLocateInPlanning**：planning 时直接出坐标（VL 端到端）vs 只出描述、再单独 locate（省 grounding token）。

### ConversationHistory（状态容器）

- `snapshot(maxImages)`：从尾部数图，超量旧图换成 `(image ignored…)` 文本（省 token）。
- `compressHistory(threshold, keep)`：消息条数超阈值 → 「省略占位 + 最近 keep 条」。
- `memories`：`<memory>` 累积，每轮拼回 prompt。
- `subGoals`：deepThink 待办状态机（pending→running→finished）。
- `pendingFeedbackMessage`：下一轮补给模型的反馈（时间/结果/错误）。

### AutoGLM 的 custom planning（`models/auto-glm/planning.ts`）

很简单：system = 固定提示词 + `<high_priority_knowledge>`；喂截图；解析 `<think>/<answer>`；
`shouldContinuePlanning = !content.startsWith('finish(')`（没 finish 就继续）。
再交 `transformAutoGLMAction` 转成 PlanningAction，回外层循环。

## 2. 与本仓 PhoneAgent 逐项对照

本仓 `PhoneAgent.run()` ≈ midscene `tasks.ts 循环 + auto-glm/planning.ts` 的**合并精简版**（单 for 循环，~300 行，只接 AutoGLM）。合理取舍，非缺陷。

### 循环结构

- **本仓**：plan 与 execute 一一对应（问一次 → 执行一个 action → 拿结果）。
- **midscene**：plan/execute 解耦（一次 plan 可出一批 executables 跑完再 replan）。对 AutoGLM（每轮单 action）等价。

### 终止与防护

| 机制 | 本仓 | midscene |
|---|---|---|
| 完成信号 | `FinishAction`→`success=true` | `<complete>` / `!startsWith('finish(')` |
| 步数上限 | `maxSteps`(15) | `replanningCycleLimit` |
| **画面卡死检测** | ✅ `stallThreshold`（截图字节相同） | ❌ 无 |
| **动作重复检测** | ✅ `repeatedActionThreshold` | ❌ 无 |
| 单轮错误容忍 | 每 action try/catch 继续 | ✅ `errorCountInOnePlanningLoop` 超阈值才停 |
| 需人工拦截 | ✅ `Take_over`/`Interact` 中止待人工 | ❌ 直接 throw not-supported |

→ **本仓在"防呆兜底"更强**（stall/repeat/人工拦截都是 midscene 没有的，针对手机长任务做的专门防护）。

### 历史与记忆（midscene 真正多出来的部分）

| | 本仓 | midscene |
|---|---|---|
| 截图裁剪 | ✅ `keepScreenshots`(3) | ✅ `snapshot(maxImages)` 同思路 |
| **消息条数压缩** | ❌ 无 | ✅ `compressHistory(50,20)` |
| **结构化记忆** | ❌ 无（整段 reply 塞 assistant） | ✅ `<memory>` 显式攒跨步信息 |
| **子目标拆解** | ❌ 无 | ✅ deepThink 的 subGoals |
| 反馈消息 | 「上一步结果：X」 | `pendingFeedbackMessage` + **时间戳** |

→ 长任务（如 40 步 YouTube 历史收集）软肋：无 `compressHistory`，message 条数会一直涨（图被裁了文字还在）；
无 `<memory>`，攒数据只能靠模型把内容写进每轮 reply 滚雪球，易丢、易超窗。

### 坐标与执行

| | 本仓 | midscene |
|---|---|---|
| 坐标换算 | 设备端缩放 / ADB `round(c·size/1000)` | TS 侧 `round(c/1000·size)` —— **等价** |
| Back/Home | 直接发固定消息 | 查 actionSpace（适配鸿蒙） |
| **Swipe** | 滚轮消息(production) / 原始拖拽(ADB) | 转 `Scroll(方向,像素距离)` |

详见 [glm-action-mapping.md](./glm-action-mapping.md)。坐标无实质误差；production swipe 走滚轮语义是待查点。

### 解析协议

| | 本仓 | midscene 通用 LLM |
|---|---|---|
| 格式 | `<think>/<answer>` + `do()` | `<thought>/<action-type>/<action-param-json>` |
| 失败处理 | sealed `ParseFailure` | 抛 `AIResponseParseError`，**自动重试一次** |
| 容错 | indexOf 容忍未转义引号 | `split('<')[0]` 去尾部漏标签 |

→ midscene 有、本仓没有的小细节：**解析失败自动重试一次**（本仓只在 `finishReason=='length'` 截断时重试）。

## 3. 可借鉴清单（按性价比）

midscene 有、对本仓长任务有用的，建议优先级：

1. **`<memory>` 结构化记忆** —— 对滚动收集类任务收益最大。
2. **`compressHistory` 条数压缩** —— 防长任务 message 爆窗（本仓只裁了图）。
3. **反馈带时间戳** —— 对"等加载"判断有帮助，成本极低。
4. （可选）**解析失败自动重试一次**。

**不需要抄的**（对单模型手机 agent 属过度设计）：分层 adapter 体系、子目标(deepThink)、replan/execute 解耦。
本仓的 stall/repeat/人工拦截反而是应保留的优势。

## 出处

midscene commit `784ce3a`，文件见顶部。本仓实现见 `phone_agent.dart` / `run_task.dart` / `response_parser.dart`。
