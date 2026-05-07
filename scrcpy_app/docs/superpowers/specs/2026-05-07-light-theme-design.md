# Design Spec: ScrcpyApp Light Theme (Soft & Accessible)

## 1. Overview
This document specifies the design for a new "Light Theme" for `ScrcpyApp`. The goal is to provide a clean, professional, and accessible alternative to the existing dark theme, maintaining brand consistency through the use of Indigo and Cyan.

## 2. Design Vision
The light theme follows a **Soft & Accessible** aesthetic. It avoids harsh contrasts by using off-white backgrounds and emphasizes depth through shaded layers rather than simple borders.

## 3. Visual Specifications

### 3.1 Color Palette
- **Background (Base)**: `#F9FAFB` (A very light gray/white for the main background)
- **Background (Sidebar)**: `#F3F4F6` (A slightly darker gray to create depth for navigation/list areas)
- **Surface (Card/Content)**: `#FFFFFF` (Pure white for cards and primary content containers)
- **Primary Accent (Indigo)**: `#3F51B5` (Used for primary buttons, active states, and branding)
- **Secondary Accent (Cyan)**: `#00BCD4` (Used for "perception" features, secondary highlights, or status indicators)
- **Text (Main)**: `#111827` (High contrast for readability)
- **Text (Muted)**: `#6B7280` (Lower contrast for secondary information)
- **Border/Divider**: `#E5E7EB` (Subtle separation)

### 3.2 Hierarchy & Depth
- **Shaded Layers**: The UI will use background color transitions (e.g., Sidebar vs. Main View) to define functional areas.
- **Soft Shadows**: Cards and floating elements will use multi-layered soft shadows to create a sense of elevation.
  - *Example Elevation 1*: `box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06);`

### 3.3 Accent Strategy: Indigo Focused
- All primary call-to-action buttons (e.g., "Connect", "Start") will use the brand Indigo.
- Selection states in lists will use a light tint of Indigo (Indigo with ~10-15% opacity) for the background, with the Indigo brand color for text or icons.

## 4. Implementation Strategy
- **Material 3**: Leverage `ColorScheme.fromSeed` with `Brightness.light` to generate the foundational theme.
- **Theme Extension**: Use `ThemeExtension` for custom colors that don't fit into the standard `ColorScheme` (e.g., specific sidebar backgrounds).
- **Dynamic Switching**: The app will support manual and system-based theme switching.

## 5. Success Criteria
- The light theme is visually consistent with the app icon.
- Text contrast meets accessibility standards (WCAG 2.1).
- The transition between dark and light modes is smooth and doesn't cause UI flickering.
