# 接 GLM/AutoGLM 输出：坐标换算 + 动作 DSL → MCP 工具映射

> **状态：已落地（基础版）**。scrcpy_mcp 的 `run_task` 已内置一份完整的 GLM 系统提示词
> 并实现了动作执行。本文记录提示词、坐标约定与动作映射的现状。

涉及两件事：**(1) 0–999 归一化坐标 → scrcpy 真实像素；(2) GLM 动作 DSL → MCP 工具调用。**
来源：AutoGLM-GUI `agents/glm/prompts_zh.py` 系统提示词，已集成到本仓
`lib/src/agent/agent_config.dart`（提示词）+ `lib/src/agent/response_parser.dart`（解析）
+ `lib/src/tools/run_task.dart`（执行）。
相关：[multi-agent-adapter-pattern.md](./multi-agent-adapter-pattern.md)、[hybrid-agent-routing.md](./hybrid-agent-routing.md)。

## GLM agent 输出格式

ReAct 风格、每步单动作、截图驱动循环：

```
<think>{简短推理}</think>
<answer>do(action="Tap", element=[x,y])</answer>
```

## ⭐ 核心坑：坐标是 0–999 归一化，不是像素

GLM 提示词明确：「坐标系统从左上角 (0,0) 到右下角 (999,999)」。
即一个 **1000×1000 归一化网格**，与真实分辨率无关。

**本仓的实现方式**（`run_task.dart`，`_kCoordSpace = 1000`）：不手算像素，而是把
GLM 的原始坐标直接传给 scrcpy，并把 `width/height` 都设为 **1000**。scrcpy 的触摸协议
按 `x / frameWidth * deviceWidth` 缩放，于是 `glm_x / 1000 * deviceWidth` 自动落到正确像素，
与真实分辨率无关。等价公式：

```
真实x = glm_x / 1000 * deviceWidth   （由 scrcpy 内部完成，无需手算）
```

注意：
- 分母是 **1000**（坐标域 0–999），不是屏宽。
- 这条路径与独立工具 `inject_swipe.dart` 的 `rescale`（按视频分辨率缩放）是**两套缩放**：
  `run_task` 走 1000 网格；裸 `inject_*` 工具走真实像素。两者不要混用同一组坐标。
- ⚠️ 历史坑：旧的简化提示词曾写「使用实际分辨率坐标」，与执行层的 1000 网格矛盾，
  靠 autoglm-phone 模型训练成输出 0–999 才没出事。现已换成明确写「0–999」的提示词，二者一致。

## 动作 DSL → 执行映射（`run_task.dart` 现状）

| GLM 动作 | 实际处理 | 备注 |
|---|---|---|
| `Launch(app)` | `adb monkey -p <pkg>` 启动 | app 名经 `_appNameToPackage` 映射，未命中则按原值当包名 |
| `Tap(element)` | 触摸 down+up，width/height=1000 | 0–999 坐标交 scrcpy 缩放 |
| `Tap(…, message="重要操作")` | 同 Tap，`message` 当前**被忽略** | headless 无确认通道；保留字段，未来可挂确认 |
| `Long Press(element)` | down → 保持 1s → up | — |
| `Double Tap(element)` | 两次 Tap（间隔 100ms） | — |
| `Swipe(start, end)` | `ScrcpyInjectScrollMessage`，1000 网格 | 起点 + 位移向量 |
| `Type(text)` | 先 Ctrl+A 全选 + Del 清空，再注入文本 | 见下「ADB 键盘自动清除」 |
| `Type_Name(text)` | **同 Type** | parser+runner 已补 |
| `Back()` | `ScrcpyBackOrScreenOnMessage` | — |
| `Home()` | `inject_key(keycode=3)` | KEYCODE_HOME |
| `Wait(duration)` | runner 内 `sleep` 秒数 | 默认 2s |
| `Interact()` | **中止任务**，返回「需人工」 | 在 `phone_agent.dart` 拦截，不进 runner |
| `Take_over(message)` | **中止任务**，返回「需人工」 | 同上 |
| `Note(message)` | 无设备副作用，返回 `Noted` | 让循环继续 |
| `Call_API(instruction)` | 无设备副作用，返回 `Acknowledged: …` | `instruction` 由 parser 折叠进 `message` |
| `finish(message)` | 结束循环，`success=true`，返回 message | 终止信号 |

> 注：`run_task` 是**自带循环的一体化 agent**，动作直接走 `ScrcpySession` 控制消息，
> 并非逐个调用独立的 MCP 工具（`inject_touch` 等）。两者底层都是同一套 scrcpy 控制协议。

## 两个已知行为对齐

1. **Type 自动清除**：GLM 提示词说明 Type 会自动清空输入框（含占位符）。
   本仓已在代码层做了同样的事（提交 `fix: clear the field before Type so it replaces, not appends`）。
   接 GLM 时确认两边不重复清除/不冲突即可。
2. **敏感操作 / 接管需回调**：`message="重要操作"` 与 `Take_over` 必须由编排层接住
   （对应 AutoGLM-GUI 的 `confirmation_callback` / `takeover_callback`）。
   若不实现，这两类动作将静默失去保护。

## 与 midscene 实现对照

[web-infra-dev/midscene](https://github.com/web-infra-dev/midscene) 同样接 AutoGLM（其提示词改编自智谱 Open-AutoGLM，与本仓同源），其坐标换算 + 动作映射在
`packages/core/src/ai-model/models/auto-glm/actions.ts` 的 `transformAutoGLMAction`（commit `784ce3a`）。
对照备份见 [midscene-autoglm-prompts.md](../../docs/midscene-autoglm-prompts.md)。结论：**架构一致，两处实现策略不同**。

### 坐标换算：等价

midscene：`AUTO_GLM_COORDINATE_MAX = 1000`，`round(coord / 1000 * size)`（在 TS 侧算出像素）。
本仓：`_kCoordSpace = 1000`，把 `x,y` + `width=height=1000` 交 scrcpy server **在设备端**做同样的线性缩放；
ADB runner（测试）则用同一公式 `round(e * size / 1000)`。**数学上一致**，只差 ≤1px 的取整。

关于「提示词写 0–999、却 `÷1000`」的疑问——**不是 bug**：

- 两种算法（`÷1000` vs `÷999`）最大差 ~1px（高值端），中部亚像素，可忽略。
- `÷1000` 反而**边界安全**：`round(999×1080/1000)=1079` 正好落在 1080 宽屏最后一个有效像素；
  `÷999` 会得 1080 → 越界。
- `÷1000` 是 GLM/AutoGLM 的**训练约定**（midscene `normalizedBy: 1000` 一致）。提示词的「999」是在描述
  模型吐出的整数取值范围，不是断言「999 = 最后一个物理像素」。改成 `÷999` 反而偏离训练语义。
- 结论：**代码 `÷1000` 保持不变**；若只想让提示词文案自洽可改措辞为「0–1000」，但属可选、且有让模型偏离分布的风险。

### 动作映射：多数固定，仅 Back/Home 查 actionSpace

midscene 把动作映射到**固定**的 midscene 动作类型，与 actionSpace 无关：Tap→`Tap`、Double Tap→`DoubleClick`、
Type→`Input`、Long Press→`LongPress`、Wait→`Sleep`、Launch→`Launch`、finish→`Finished`。
**只有 Back/Home 查 actionSpace**（`findActionName`，在 `AndroidBackButton`/`HarmonyBackButton` 等里选），
用于同一份输出在 **Android / 鸿蒙**上自动选对动作名——若本仓将来要支持鸿蒙，可参考这套查名做法。

`Interact` / `Call_API` / `Take_over` / `Note`：midscene **直接 `throw "not supported"`**（提示词禁用 + transform 抛异常）。
本仓相反：解析层启用了这 4 个，并各自给了处理（`Interact`/`Take_over` 中止待人工，`Note`/`Call_API` 回执续跑）。

### Swipe：两边都不是「原始触摸拖拽」，但机制不同 ⚠️

- midscene：把 Swipe 换算成 `Scroll(direction, distance)`——按 `|dy|>|dx|` 判方向，
  `distance = round(|delta| * size / 1000)`（像素距离），方向是「内容滚入屏幕的方向」语义。
- 本仓 ADB runner（测试）：`input swipe x1 y1 x2 y2 300`，**真实像素手指拖拽**（你日志里看到的那种）。
- 本仓 production（`run_task.dart`）：`ScrcpyInjectScrollMessage`，**鼠标滚轮语义** + 把 0–1000 的 delta
  直接当 `hScroll/vScroll`（未按像素缩放）。滚轮事件与手指拖拽在某些列表/应用里行为不同——
  production 滑动若不灵，根因可能在此（待查项）。

## 实现位置与测试

- 提示词：`lib/src/agent/agent_config.dart`（`_kDefaultSystemPrompt`，`{DATE}` 占位）。
- 解析：`lib/src/agent/response_parser.dart`（`ResponseParser` → `ParsedResponse`；`<think>`/`<answer>` 抽取，仅支持 `do(...)` / `finish(...)`）。
- 执行：`lib/src/tools/run_task.dart`（动作 → `ScrcpySession` 控制消息）。
- 循环/拦截：`lib/src/agent/phone_agent.dart`（ReAct 循环、stall 兜底、`Interact`/`Take_over` 拦截）。
- 测试：`test/response_parser_test.dart` 覆盖解析（do/finish、think/content 分离、未转义引号、各 `ParseFailure` 原因）；`test/phone_agent_test.dart` 覆盖循环编排 + `Interact` 中止行为。

## 仍可改进（按需）

- 敏感 `Tap` 的 `message` 目前被忽略——若要做「危险操作确认」，需引入确认通道（参考
  AutoGLM-GUI 的 `confirmation_callback`）。
- `Note` / `Call_API` 仅回执，未真正做页面记录/总结；如需总结能力要接一个 summarizer。
- 中文 app 专属规则较多，提示词偏长；用不上的可精简。

## 出处

基于 AutoGLM-GUI `agents/glm/prompts_zh.py` 动作定义，及本仓 agent 实现整理。
