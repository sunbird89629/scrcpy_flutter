# scrcpy_plus 设计文档

## 概述

scrcpy_plus 是一个 macOS 系统栏应用，用于管理 Android 手机的配对、连接，并提供一键启动 scrcpy 的能力。采用"状态栏优先"设计，无主窗口，所有交互通过状态栏菜单和系统对话框完成。

## 目标

- 提供轻量级的 Android 设备管理入口
- 简化 scrcpy 的启动流程
- 支持多种设备配对方式（IP、QR、USB、ADB connect）
- 常驻后台，随时可用

## 非目标

- 不内嵌 scrcpy 逻辑，通过 CLI 调用系统已安装的 scrcpy
- 不支持 Windows / Linux（仅 macOS）
- 不实现文件管理、应用管理等功能（未来扩展）

## 架构

```
scrcpy_plus (Flutter Desktop - macOS only)
├── 无主窗口，纯状态栏应用
├── 状态栏图标（显示连接状态）
├── 平铺菜单（设备列表 + 操作项）
├── 系统对话框（配对输入、确认）
└── 外部进程（调用 scrcpy CLI）

依赖的现有包：
├── adb_tools    — ADB 客户端，设备发现/配对/连接
└── logger_utils — 日志
```

### scrcpy 启动方式

通过 `Process.start('scrcpy', ['--serial', serial, ...])` 调用系统已安装的 scrcpy。用户需自行安装 scrcpy（`brew install scrcpy`）。可传递常用参数（分辨率、码率、编码器等）。

## 状态栏菜单结构

```
┌─────────────────────────────────┐
│  scrcpy_plus                    │
├─────────────────────────────────┤
│  已连接设备                      │
│    Pixel 7 (192.168.1.100) ▸   │
│    Samsung S23 (USB) ▸         │
├─────────────────────────────────┤
│  配对新设备...                   │
│  刷新设备列表                    │
├─────────────────────────────────┤
│  设置...                        │
│  退出                            │
└─────────────────────────────────┘
```

### 菜单项说明

- **已连接设备**：显示设备名 + 连接方式（IP/USB），点击展开子菜单
  - 子菜单：启动 scrcpy / 断开连接 / 设备信息
- **配对新设备**：弹出对话框，支持 IP 配对 / QR 码 / ADB connect
- **刷新设备列表**：重新扫描已连接设备
- **设置**：scrcpy 参数配置（分辨率、码率等）
- **退出**：关闭应用

### 状态栏图标变化

- 灰色：无设备连接
- 彩色：至少一台设备已连接

## 设备配对流程

### IP 地址配对

1. 用户点击"配对新设备" → 弹出对话框
2. 输入 IP:端口（如 `192.168.1.100:5555`）
3. 调用 `adb pair <ip>:<port> <code>`（用户需先在手机上开启无线调试，获取配对码）
4. 配对成功后调用 `adb connect <ip>:<port>`
5. 设备出现在已连接列表

### ADB connect

1. 用户输入 `<ip>:<port>`（无需配对码）
2. 直接调用 `adb connect`
3. 适用于已配对过的设备

### USB 自动检测

- 应用启动时和定期轮询 `adb devices`
- USB 设备自动出现在列表，无需手动操作

### 二维码配对

- 生成包含 IP 和端口信息的 QR 码
- 用户用手机扫码完成配对（需要手机端配合）

## 设备状态与信息

菜单中每个设备展开后显示：

```
Pixel 7 (192.168.1.100)
├── 启动 scrcpy
├── 设备信息
│   ├── 电量: 85%
│   ├── Android: 14
│   ├── 连接方式: WiFi
│   └── 分辨率: 1080x2400
└── 断开连接
```

### 设备信息获取方式

- `adb -s <serial> shell dumpsys battery` → 电量
- `adb -s <serial> shell getprop ro.build.version.release` → Android 版本
- `adb -s <serial> shell wm size` → 分辨率
- 连接方式：通过 serial 格式判断（IP:端口 = WiFi，其他 = USB）

### 状态更新频率

- 设备列表：手动刷新 + 每 30 秒自动轮询
- 设备信息：每次展开子菜单时实时获取

## 设置与 scrcpy 配置

### 设置项

| 设置项 | 默认值 | 说明 |
|--------|--------|------|
| scrcpy 路径 | `scrcpy`（PATH 中） | 可自定义路径 |
| 默认分辨率 | `1024` | 最大宽度像素 |
| 默认码率 | `8M` | 视频码率 |
| 默认编码器 | `h264` | 视频编码器 |
| 自动重连 | `true` | 启动时自动连接已知设备 |
| 启动时最小化 | `true` | 启动后直接最小化到状态栏 |

### scrcpy 启动参数示例

```bash
scrcpy --serial <serial> \
  --max-size 1024 \
  --video-bit-rate 8M \
  --video-codec h264
```

### 配置持久化

使用 JSON 文件存储，保存在 `~/Library/Application Support/scrcpy_plus/`。

## 项目结构

```
scrcpy_plus/
├── lib/
│   ├── main.dart                    # 入口，初始化状态栏
│   ├── app/
│   │   ├── tray_manager.dart        # 状态栏图标和菜单管理
│   │   ├── menu_builder.dart        # 菜单构建逻辑
│   │   └── app_controller.dart      # 应用状态管理
│   ├── device/
│   │   ├── device_manager.dart      # 设备发现、连接管理
│   │   ├── device_info.dart         # 设备信息模型
│   │   └── pairing_service.dart     # 配对逻辑（IP/QR/USB）
│   ├── scrcpy/
│   │   ├── scrcpy_launcher.dart     # scrcpy 进程启动和管理
│   │   └── scrcpy_config.dart       # scrcpy 参数配置
│   ├── settings/
│   │   ├── settings_manager.dart    # 配置读写
│   │   └── settings_dialog.dart     # 设置对话框
│   └── utils/
│       ├── adb_runner.dart          # ADB 命令执行封装
│       └── process_manager.dart     # 外部进程管理
├── assets/
│   ├── tray_icon.png                # 状态栏图标（灰色）
│   └── tray_icon_connected.png      # 状态栏图标（彩色）
├── test/
└── pubspec.yaml
```

### 依赖

```yaml
dependencies:
  adb_tools:
    path: ../packages/adb_tools
  logger_utils:
    path: ../packages/logger_utils
  tray_manager: ^0.4.0
  shared_preferences: ^2.2.0
```

## 未来扩展

- 文件管理（通过 ADB push/pull）
- 应用管理（安装/卸载 APK）
- 二维码配对的完整实现
- 多设备同时镜像
- 快捷键支持
