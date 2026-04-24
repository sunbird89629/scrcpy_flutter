---
# YAML Front Matter: 机器可读的设计令牌 (Design Tokens)
tokens:
  color:
    seed: { value: "#3F51B5", type: "color" } # Colors.indigo
    primary: { value: "{color.seed}", type: "color" }
    schemes:
      light:
        brightness: "light"
        use-material-3: true
      dark:
        brightness: "dark"
        use-material-3: true
  
  # 预设间距（符合 Material 3 规范）
  spacing:
    none: { value: "0px" }
    xs: { value: "4px" }
    sm: { value: "8px" }
    md: { value: "16px" }
    lg: { value: "24px" }
    xl: { value: "32px" }

  # 预设圆角
  radius:
    none: { value: "0px" }
    sm: { value: "4px" }
    md: { value: "8px" }
    lg: { value: "12px" }
    full: { value: "9999px" }

---

# AutoGLM 设计规范 (DESIGN.md)

## 概述 (Overview)
AutoGLM 是一个跨平台的自动化桌面/移动端工具。其视觉语言应传达**效率、精准与可靠**。
UI 应保持极简，避免过度装饰，强调内容的层级关系和操作的直观性。

## 视觉原则 (Design Principles)
- **极简主义 (Minimalism):** 除非必要，否则不增加多余的视觉元素。
- **高对比度 (Contrast):** 核心操作和状态反馈必须具备清晰的视觉对比。
- **一致性 (Consistency):** 在 macOS, Windows 和移动端保持逻辑一致，但遵循各自平台的交互惯例。

## 核心组件指导 (Component Guidance)

### 侧边栏与导航 (Sidebar & Navigation)
- 使用 `NavigationRail` 或自定义侧边栏。
- 在桌面端，侧边栏应使用半透明（Glassmorphism）或纯色背景，视系统风格而定。

### 状态卡片 (Status Cards)
- 运行中的任务使用 `primary` 色调的微弱外发光或阴影。
- 失败的任务使用标准的 `error` 红色。

### 按钮与交互 (Buttons)
- 默认使用 Material 3 的 `FilledButton`。
- 危险操作（如删除历史）应使用 `TextButton` 或显眼的红色警示色。

## 无障碍与兼容性 (Accessibility)
- 必须遵循 WCAG AA 标准，确保文本在背景上的对比度至少为 4.5:1。
- 支持动态字体缩放 (Dynamic Type)。
