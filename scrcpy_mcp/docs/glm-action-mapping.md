# 接 GLM/AutoGLM 输出：坐标换算 + 动作 DSL → MCP 工具映射

> **状态：已落地（基础版）**。scrcpy_mcp 的 `run_task` 已内置一份完整的 GLM 系统提示词
> 并实现了动作执行。本文记录提示词、坐标约定与动作映射的现状。

涉及两件事：**(1) 0–999 归一化坐标 → scrcpy 真实像素；(2) GLM 动作 DSL → MCP 工具调用。**
来源：AutoGLM-GUI `agents/glm/prompts_zh.py` 系统提示词，已集成到本仓
`lib/src/agent/agent_config.dart`（提示词）+ `lib/src/agent/action_parser.dart`（解析）
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
