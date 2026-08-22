# P1 Liquid Glass — SDK API 核验记录（铁律 1：先核 SDK，禁脑补）

> 核验时间：2026-08-22（P0 验收等待期，P1 前置准备；本文档不含任何视觉代码）
> 核验对象：Xcode 26.6 自带 macOS 26.5 SDK
> 证据路径（本机可复核）：
> - `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`
> - 同目录树 `SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`
> ⚠️ 注意：`xcrun --show-sdk-path` 默认指向 CommandLineTools 旧 SDK（无 Glass API），必须用 Xcode 内 SDK 核验。

## 一、结论

目标铁律 4 点名的 5 个 Liquid Glass API **全部存在于 macOS 26.5 SDK**，实际宿主模块为 **`SwiftUICore`**（SwiftUI 通过 `@_exported import SwiftUICore` 再导出 → **P1 代码只需 `import SwiftUI`**，无需额外 import；仍属第一方原生模块，不违反铁律 3）。

## 二、API 签名清单（逐字摘自 swiftinterface）

| API | 签名（macOS 26.5 SDK 原文） | availability |
|---|---|---|
| 玻璃表面 | `nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`（`extension View`） | macOS 26.0+（visionOS unavailable） |
| 同区域玻璃容器 | `@MainActor struct GlassEffectContainer<Content: View>: View { init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) }` | macOS 26.0+ |
| 玻璃动效过渡 | `@MainActor func glassEffectTransition(_ transition: GlassEffectTransition) -> some View`；`GlassEffectTransition` 预设：`.matchedGeometry` / `.materialize` / `.identity` | macOS 26.0+ |
| 玻璃身份（morph 配对） | `@MainActor func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View` | macOS 26.0+ |
| 玻璃并集（多表面 morph 融合） | `@MainActor func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View` | macOS 26.0+ |
| 玻璃材质 | `struct Glass: Equatable, Sendable`：预设 `.regular` / `.clear` / `.identity`；`func tint(_ color: Color?) -> Glass`；`func interactive(_ isEnabled: Bool = true) -> Glass` | macOS 26.0+ |
| 玻璃按钮风格（SwiftUI 模块） | `PrimitiveButtonStyle.glass` / `GlassButtonStyle(Glass)` / `PrimitiveButtonStyle.glassProminent` / `GlassProminentButtonStyle` | macOS 26.0+ |

## 三、目标 P1 需求 → 真实 API 映射

| 目标 P1 需求 | 落地 API |
|---|---|
| 全局组件玻璃表面（侧栏/面板/卡片/弹窗） | `.glassEffect(_:in:)`（shape 参数支持自定义 Shape，默认 `DefaultGlassEffectShape`） |
| 同区域光学采样一致 | `GlassEffectContainer(spacing:)` 包裹同区域玻璃组件 |
| Tab 分段 Morph 流体形变 | `@Namespace` + `glassEffectID(id:in:)`（分段身份）+ `glassEffectUnion(id:namespace:)`（并集融合）+ `withAnimation` + `glassEffectTransition(.materialize)` |
| 弹窗/侧栏/拖拽动效过渡 | `glassEffectTransition(.matchedGeometry / .materialize / .identity)` |
| 主题插件改玻璃参数 | `ThemeSpec.glassTintHex` → `Glass.regular.tint(Color(hex:))` 即时下发（无需重启） |
| 按钮玻璃 | `.buttonStyle(.glass)` / `.glassProminent` |

## 四、⚠️ 规格-SDK 差异（P1 设计决策点，验收通过后与用户确认口径）

1. **`Glass` 材质 API 不暴露「模糊强度 / 曲率 / 高光强度」数值参数**——原生只有 3 个材质预设（regular/clear/identity）+ tint + interactive。
   目标 P1 §2/§4 要求主题插件输出「模糊强度、tint 色调、曲率、高光强度」：
   - **可原生落地**：tint 色调（`Glass.tint`）、材质档位（预设选择）
   - **无原生参数**：模糊强度 / 曲率 / 高光强度 → 铁律 1/4 下不得手写模拟（禁手写模糊/透明度模拟玻璃）
   - **预案**：主题插件这三个字段保留在 `ThemeSpec`（已预留）做「语义占位」，P1 实现时按「预设档位 + tint」近似映射并在 UI 明示为「材质档位」，或等后续 SDK 开放数值参数；**禁止为凑参数而手写玻璃**
2. **部署目标口径**：目标文本「macOS Tahoe (macOS25)」按 Apple 命名 = macOS 26（Tahoe）；App 部署目标 26.0 与 Glass API availability（macOS 26.0+）完全对齐，无兼容层需求（「彻底放弃旧 macOS 兼容」成立；`GlassSurface.resolveMode` 的 legacy 分支为 P0 既有防御性降级，P1 可保留不动或简化——决策点）。

## 五、P1 开工前置条件（全部就绪）

- [x] 5+2 个 API 存在性与签名核验（本文档 §二，本机 SDK 可复核）
- [x] `import SwiftUI` 即可用（`@_exported import SwiftUICore`）
- [x] `ThemeSpec.glassTintHex/blurIntensity/highlightIntensity` 字段已预留（Theme.swift:25-29）
- [x] `GlassSurface` 三层降级链已就位（P0 资产：native/legacy/solid；reduceTransparency 最高优先级）
- [ ] P0 实机验收通过（铁律 2 解锁条件）
- [ ] §四 两个设计决策点与用户确认（模糊/曲率/高光口径；legacy 分支去留）
