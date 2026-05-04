# MCP 屏幕录制功能实现文档

## 1. 目标
在现有的 `scrcpy-mcp` 服务中增加屏幕录制能力，允许 AI 代理自主控制录制的开始与结束，并将录制文件保存至本地。

## 2. 接口定义 (MCP Schema)

### 2.1 工具 (Tools)

#### `start_recording`
*   **描述**: 启动目标设备的屏幕录制（使用 `adb shell screenrecord`）。
*   **参数**:
    *   `device_id` (string, optional): 设备序列号。
    *   `bitrate` (integer, optional): 比特率，默认 4Mbps (4000000)。
    *   `max_time` (integer, optional): 最大录制时长（秒），默认 180s（安卓系统上限）。
*   **响应**: `{"status": "recording", "path_on_device": "/sdcard/mcp_record.mp4"}`

#### `stop_recording`
*   **描述**: 停止当前录制，并将文件从设备拉取到本地。
*   **参数**:
    *   `device_id` (string, optional): 设备序列号。
    *   `save_path` (string, optional): 本地保存路径。若未指定，则默认存放在 `Downloads/scrcpy_records/`。
*   **响应**: `{"status": "finished", "local_path": "/path/to/video.mp4", "size": "2.5MB"}`

### 2.2 资源 (Resources)

#### `recording://status`
*   **描述**: 返回当前录制状态。
*   **数据格式**: `application/json`
*   **示例**: `{"is_recording": true, "start_time": "2024-05-03T10:00:00Z", "device_id": "..."}`

---

## 3. 详细开发步骤

### 第一阶段：底层能力扩展 (packages/autoglm_adb)
需要在 `AdbClient` 或相关类中增加对异步进程的管理。

1.  **修改 `AdbClient`**:
    *   增加 `startProcess(List<String> args)` 方法，返回一个 `Process` 对象。
    *   实现 `startScreenrecord(String deviceId, String remotePath)`。
2.  **状态维护**:
    *   在内存中维护一个 `Map<String, Process> _recordingProcesses`，以 `deviceId` 为 Key 存储正在运行的录制进程。

### 第二阶段：业务逻辑适配 (scrcpy_view)
在 `ScrcpyAdb` 接口和实现类中增加录制接口。

1.  **更新接口**:
    ```dart
    abstract class ScrcpyAdb {
      Future<void> startRecording(String deviceId, {int bitrate});
      Future<String> stopRecording(String deviceId, String localPath);
    }
    ```
2.  **实现 `stopRecording`**:
    *   找到对应的 `Process` 对象。
    *   发送 `SIGINT` (Ctrl+C) 信号给进程（这是 `screenrecord` 正常保存视频的关键）。
    *   等待进程退出。
    *   执行 `adb pull` 将文件传回本地。
    *   执行 `adb shell rm` 删除手机上的临时文件。

### 第三阶段：MCP 服务集成 (scrcpy_mcp)
修改 `lib/src/scrcpy_mcp_server.dart`，注册工具。

1.  **注册工具**:
    在 `_registerTools()` 方法中添加 `start_recording` 和 `stop_recording`。
2.  **编写回调函数**:
    *   `_startRecording`: 调用底层接口，并更新 `_mcpServer` 的状态。
    *   `_stopRecording`: 执行停止逻辑，并向 AI 返回本地文件路径。

---

## 4. 关键技术点与注意事项

### 4.1 优雅停止录制
**警告**: 不要直接 `kill -9` 录制进程，否则生成的 MP4 文件头部会损坏导致无法播放。
*   **正确做法**: 在 Dart 中使用 `process.kill(ProcessSignal.sigint)`。

### 4.2 时长限制
Android 原生的 `screenrecord` 命令通常有 **180秒（3分钟）** 的强制时长限制。
*   **应对**: 在工具描述中告知 AI 这一限制，或者在服务端实现分段录制逻辑（进阶）。

### 4.3 文件命名冲突
为避免多次录制覆盖文件，建议在手机端和本地均使用时间戳命名：
*   设备端: `/sdcard/mcp_rec_${timestamp}.mp4`
*   本地端: `~/Downloads/record_${timestamp}.mp4`

### 4.4 权限要求
录制功能需要 Android 4.4+，且部分受保护内容（如支付界面、某些登录页）可能会录制成黑屏，这是安卓系统的安全限制，需在 `troubleshoot` 提示词中加入此说明。

---

## 5. 测试用例

1.  **冒烟测试**: 调用 `start_recording`，检查 `adb shell ps` 中是否存在 `screenrecord` 进程。
2.  **完整流测试**: 开始录制 -> 模拟点击（Home键） -> 停止录制 -> 检查本地指定文件夹是否生成了可播放的 MP4 文件。
3.  **异常测试**: 在未开始录制时调用 `stop_recording`，应返回友好的错误提示。
4.  **并发测试**: 同时对两个不同的设备开启录制，验证进程管理是否隔离。
