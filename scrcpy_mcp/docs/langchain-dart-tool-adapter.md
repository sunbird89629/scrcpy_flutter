# 备选方案：用 LangChain.dart 编排 MCP 工具

记录「如果将来要把手写的 agent 编排换成 LangChain.dart 框架」的可行性与映射方式。
**当前不实施**——现有手写编排（`autoglm_llm_client.dart` + `run_task`）已可用，本文仅作备选预研。
相关：[gui-agent-base-model-selection.md](./gui-agent-base-model-selection.md)、[hybrid-agent-routing.md](./hybrid-agent-routing.md)。

## 结论

LangChain.dart 能干净地包住现有 MCP 工具——`Tool.fromFunction` 要的 name / description / JSON Schema，`McpTool` 已全有，且**类型同为小写 JSON Schema，无需转换**（比 FunctionGemma 那条路省事）。

## 两个核心 API

### ① 定义工具：`Tool.fromFunction`

```dart
final searchTool = Tool.fromFunction<SearchInput, String>(
  name: 'search',
  description: 'Tool for searching the web.',
  inputJsonSchema: {                 // 原生 JSON Schema，小写类型
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': '...'},
      'n':     {'type': 'integer', 'description': '...'},
    },
    'required': ['query'],
  },
  func: callSearchFunction,          // 实际执行函数
  getInputFromJson: SearchInput.fromJson,
);
```

### ② 跑 agent 循环：`ToolsAgent` + `AgentExecutor`

`ToolsAgent` 用模型原生 tool-calling 决定调哪个工具、什么顺序；`AgentExecutor` 负责
「模型 → 调工具 → 结果喂回 → 再问模型」的循环与 intermediate steps 管理。

```dart
final agent = ToolsAgent.fromLLMAndTools(llm: model, tools: [tool1, tool2]);
final executor = AgentExecutor(agent: agent);
final res = await executor.invoke({'input': '帮我打开 Chrome 并截图'});
print(res['output']);
```

## McpTool → LangChain Tool 映射

| McpTool（现有） | Tool.fromFunction | 转换成本 |
|---|---|---|
| `name` | `name` | 直接搬 |
| `description` | `description` | 直接搬 |
| `inputSchema`（JsonSchema 对象） | `inputJsonSchema`（Map） | 序列化成 Map，**类型小写无需转换** |
| `execute(args, extra)` | `func` | 包一层 adapter 调 execute |

思路：写一个 `McpToolAdapter`，把 25 个 `McpTool` 批量转成 LangChain `Tool`，
agent 编排（选工具 / 循环 / scratchpad）交给 `AgentExecutor`，省掉手写循环。

## 落地前必须验证的风险

1. **tool-calling 协议兼容性**：LangChain.dart 默认走 OpenAI 风格 tool-calling。
   AutoGLM / UI-TARS 是否兼容这套 function-calling 需先验证；不兼容要自定义 output parser，反增复杂度。
2. **视觉输入**：核心场景是「喂截图」。Chat 接口支持多模态消息，但 `ToolsAgent` 的
   scratchpad 如何带图、UI-TARS 坐标动作如何解析，官方无现成例子，需自行趟。
3. **非官方移植**：langchain.dart 是社区 Dart 端口（0.8.1，更新偏慢），复杂功能完整度可能落后 Python 版。

## 何时才值得引入

- ✅ 要做「多底座切换（AutoGLM/UI-TARS/Claude）+ 复杂多步编排」时，统一接口收益明显。
- ✅ 要做 RAG / 向量检索时，可复用其 Retrieval 模块。
- ❌ 只是跑通单个 agent —— 不值得，按「简单优先」原则保持现有手写编排。

## 出处

经 ctx7 抓取 `/davidmigloz/langchain_dart` 官方文档（agents/tools_agent）整理。
