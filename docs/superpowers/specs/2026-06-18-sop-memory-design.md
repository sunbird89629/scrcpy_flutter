# App 操作经验库（SOP Memory）设计

- 日期：2026-06-18
- 状态：已批准，待实现
- 范围：`scrcpy_mcp`（`run_task` agent）

## 背景与动机

`run_task` 由小型视觉模型（AutoGLM / AgentCPM）驱动，靠截图 + 视觉定位操作 app。小模型的弱点是缺乏"先验经验"——不知道某个 app 里完成某任务该走哪几步、有哪些坑。

参考 AutoDroid 的"探索→知识→注入"范式，但做两点务实裁剪以贴合现有纯视觉架构：

1. **纯视觉路线**：不引入无障碍树 / `uiautomator dump`。页面与控件不做结构化建模。
2. **任务级 SOP**：不建 UTG 页面转移图，存意图级的操作流程（SOP），对小模型增益最直接、纯视觉也能稳定产出。

知识来源采用**执行回写**：复用现有 `run_task` agent，任务结束后把本次轨迹总结成 SOP。成功存正例，失败存"避坑"反例。知识随真实使用自然增长，并天然具备一定抗腐烂能力（UI 变化会产生新轨迹）。

## 目标

- 执行前：按 `(包名, 任务意图)` 检索相关 SOP，注入 agent prompt。
- 执行后：把本次轨迹回写成一条 SOP（正例 / 反例）。
- 全程 best-effort：经验库任何环节失败都不得影响 `run_task` 主流程。
- 零新增运行时依赖；内建进 `run_task`，不新增对外 MCP 工具。
- 测试不碰真机、不调真实 LLM（`dart test -x real-device` 可全过）。

## 非目标（YAGNI）

以下全部留到闭环验证有效后再评估：

- 向量 / embedding 检索
- UTG / 页面级导航图 / 页面提示卡
- 主动探索器（autonomous exploration）
- 人工演示采集
- UI 改版的自动失效检测与淘汰

## 数据模型

一条 SOP 记录（JSON）：

```json
{
  "id": "uuid",
  "package": "com.tencent.mm",
  "intent": "给联系人转账",
  "polarity": "positive",
  "steps": ["进入聊天", "点右下 +", "点转账", "输入金额", "确认"],
  "pitfall": "首次会弹隐私引导蒙层，需先点同意",
  "source_task": "给张三转 100 元",
  "created_at": "2026-06-18T10:00:00Z",
  "device_hint": "1080x2340 zh-CN"
}
```

字段说明：

- `package`：前台包名，主 key。
- `intent`：任务意图标题，供检索匹配。
- `polarity`：`positive`（成功正例）/ `negative`（失败避坑反例）。
- `steps`：意图级步骤序列（非坐标、非控件 id）。
- `pitfall`：反例填写关键坑点；正例可空。
- `device_hint`：可选，记录分辨率 / 语言区域，便于将来按设备过滤。

### 存储

- 按包名分文件：`<storage>/sop/<package>.jsonl`，一行一条记录。
- 选 JSONL：追加成本低、无需读改写整文件、坏行可单行跳过。
- `<storage>` 路径由 session / config 指定的数据目录提供。

## 组件（单一职责，可独立测试）

### SopStore
纯读写，无业务逻辑。

- `Future<List<SopRecord>> load(String package)` — 读取并解析该包名的 jsonl；坏行记 WARNING 跳过。
- `Future<void> append(SopRecord record)` — 追加一行。
- 测试：喂临时目录，验证读写 / 追加 / 坏行容错。

### SopRetriever
检索。复用现有 `AgentModelClient`。

- 输入 `(package, taskText, List<SopRecord> candidates)` → 输出待注入的若干条（上限如 3）。
- 起步实现：取候选 SOP 的 `intent` 列表，用 LLM 或简单文本匹配挑相关项。
- 测试：给定候选集 + 任务，断言召回（LLM 调用 mock）。

### SopWriter
回写。

- 输入 `(package, taskText, AgentResult, 动作轨迹)` → 让 LLM 总结成一条 `SopRecord` → `SopStore.append`。
- `AgentResult.success` 决定 `polarity`。
- 测试：给定成功 / 失败 `AgentResult`，断言生成 record 的 polarity 与字段（LLM 调用 mock）。

## 数据流（在 `run_task` 内）

```
run_task 开始
  ├─ 抓前台包名 (adb)
  ├─ SopStore.load(package)
  ├─ SopRetriever 选相关 SOP（≤ 3 条）
  └─ 注入 PhoneAgent 的参考经验段
PhoneAgent.run(...) → AgentResult(success, 轨迹)
  └─ SopWriter: 成功→正例 / 失败→避坑反例 → SopStore.append
```

### 前台包名获取

任务开始时 `adb shell` 解析当前 resumed activity 的包名（如 `dumpsys activity activities` 的 `mResumedActivity`）。拿不到则降级用任务文本中的 app 名——仍可执行，只是检索 / 回写的 key 精度下降。

### 注入方式

把检索到的 SOP 拼成一段简短"参考经验"文本，加入 `PhoneAgent` 的 prompt（旁路于现有 run 内 `memoryBlock`，两者互不干扰）：

- 正例："可参考以下成功流程：…"
- 反例："注意避免以下坑：…"

注入条数上限（≤ 3）防止 prompt 膨胀。

## 错误处理

经验库为纯增强项，全程 **best-effort**：

- 抓包名失败、检索失败、回写失败 → 只记 WARNING，不抛、不影响 `run_task`。
- 库为空（冷启动）= 正常，照常执行。

## 测试策略

- `SopStore` / `SopRetriever` / `SopWriter` 各自单测，LLM 与 adb 通过 mock / fake 注入。
- 用现有 `ScrcpyAdb` 接口的 fake 跑端到端，验证"检索→注入→回写"闭环。
- 不碰真机、不调真实 LLM；`dart test -x real-device` 全过。

## 日志

沿用 `package:logger_utils`：新建模块各自 `final _log = Logger('scrcpy.mcp.sop.*')`。检索命中、回写条目走 INFO；best-effort 失败走 WARNING。
