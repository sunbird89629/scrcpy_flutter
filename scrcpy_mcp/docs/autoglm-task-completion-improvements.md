# 提升 autoglm-phone 任务完成度

> 基于 2026-06 在真机（含 Twitter 打开、YouTube 历史汇总两类任务）上的多次实测，
> 总结 autoglm-phone 在 `run_task` 闭环里的失败模式与改进方案。

## 一句话判断

autoglm-phone 是 **9B 端到端小模型**，瓶颈在 **规划稳定性 + 视觉读取 + 任务收敛**，
而**坐标 grounding 基本够用**（见 [glm-action-mapping.md](./glm-action-mapping.md)，已验证 0–999
归一化换算正确）。所以提升要么"用 harness/外部能力补它"，要么"换更强的脑"。

## 实测到的失败模式

| 失败模式 | 现象 | 触发场景 |
|---|---|---|
| 生成复读崩溃 | 模型复读固定 user 消息直到撞满 `max_tokens=2048`（`finish_reason="length"`）→ 无可解析动作 | 每步 user 消息恒为「继续执行任务」+ 低温 0.1 |
| 无限滚动不收尾 | 同一个 Swipe 重复 ~38 次找日期边界，从不整理结果 → 耗尽 maxSteps | 长列表收集类任务 |
| 迷失进视频/广告 | 点历史条目→播放视频；点标签→开外部广告，反复绕 | YouTube 列表点条目即播放；广告污染设备 |
| 黑屏/敏感屏 | `screencap` 全黑或报敏感屏，模型对黑图瞎猜 | FLAG_SECURE 页面、页面切换中 |
| grounding 误差 | 点击落在相邻广告卡片而非目标 | 密集/含推荐位的界面 |
| TODO 幻觉 | 反复叙述"任务列表已创建/更新"（实际不存在）白烧 token | 各类任务 |

> 对照实验：同任务同设备，更强的规划模型（Claude 直接驱动 adb）4 步直达历史页、
> 全程只滑不点、准确按日期分组产出表格；autoglm-phone 三次均未产出表格。
> 差距集中在**规划容错 + 读屏 + 抗干扰**，不在坐标。

## 已落地的修复（本轮）

| 修复 | commit | 命中的失败模式 |
|---|---|---|
| 坐标按 1000×1000 归一化注入（非像素/视频分辨率） | `b4fbf30` | grounding（点全偏） |
| Type 前先清空字段（Ctrl+A+Del） | `834314d` | 输入叠加成脏文本 |
| 截图历史裁剪到最近 N 张 + 截图不变 stall | `a52f490` | 上下文爆窗 / 静态屏死循环 |
| 去 silent 兜底 + `finish_reason` 告警 | `858260c` | 把格式错/截断伪装成成功 |
| 上一步动作结果回喂下一步 prompt | `ff90a8d` | **生成复读崩溃** |
| 同一动作重复 N 次熔断 + 滚动上限提示词 | `cc1cdd3` | **无限滚动** |

效果：从「step 11 崩溃」→「进到历史页、读到真实记录」，瓶颈逐层后移。

## 改进方案（按 ROI / 成本分层）

### 第一层：harness 兜底（成本低，纯 `phone_agent.dart` 改动）

1. **`finish_reason="length"` 当可恢复**：截断 → 重试一次并提示「只输出一个动作」，而非判失败。
2. **黑屏/敏感屏检测**：`screencap` 全黑或报错 → `Wait` 重试 2 次，不要把黑图喂给模型。
3. **给一个"真" scratchpad**：模型幻觉「任务列表」说明它需要状态记忆。harness 累积 `Note`/已收集条目，
   每步回灌精简「已收集 N 条」摘要 —— **长收集类任务能否完成的关键**。
4. **历史去 `<think>`**：assistant 历史只留动作行，省上下文。

### 第二层：任务设计（成本低，立竿见影）

5. **分解 + 明确终止条件**：复杂任务拆「导航 / 收集 / 汇总」小步，每步可判定 done；范围收窄（最近 3 天而非整周）。
6. **导航走深链/intent**：`am start` 直达目标 activity，绕开最脆弱的视觉多步导航。能确定性做的别让模型猜。
7. **任务级护栏**：如「不要点列表条目（会播放视频）」。治标，per-task。

### 第三层：换/补"脑"（成本高，天花板最高）⭐

8. **混合架构（planner + executor）**：强模型做规划/读屏/状态/汇总，autoglm-phone 只做坐标 grounding/执行。
   即 AutoGLM 论文的「基础智能体解耦中间接口」。改动：`PhoneAgent` 拆 planner LLM + grounding LLM 两段。
   参考 [hybrid-agent-routing.md](./hybrid-agent-routing.md)、[multi-agent-adapter-pattern.md](./multi-agent-adapter-pattern.md)。
9. **换更大 GUI 模型**：UI-TARS-72B / Qwen-VL-72B / 更大 AutoGLM 变体端到端（接受成本与延迟）。
   见 [gui-agent-base-model-selection.md](./gui-agent-base-model-selection.md)。
10. **deepThink 两段定位**：密集界面裁剪区域再请一次提精度。

## 优先级建议

- **先做第一层 1+2+3**：成本最低、直接消掉本轮实测的失败模式，预计把简单/中等任务完成率拉上一个台阶。
- **中期上第 8（混合架构）**：让它能做「历史汇总」这类复杂任务的唯一现实路径——autoglm 单独扛不动规划+汇总。
- **环境务必干净**：无广告注入、已登录、关指针位置叠加层（`settings put system pointer_location 0`）——否则任何模型都被广告拖死。

## 相关配置入口

- `scrcpy_mcp/lib/src/agent/agent_config.dart`：`maxSteps` / `keepScreenshots` / `stallThreshold` / `repeatedActionThreshold` / `systemPrompt`
- `scrcpy_mcp/lib/src/agent/phone_agent.dart`：ReAct 主循环（stall、动作回喂、历史裁剪都在这）
- `scrcpy_mcp/lib/src/tools/run_task.dart`：动作 → 设备执行（坐标 1000×1000 注入、Type 清空）
