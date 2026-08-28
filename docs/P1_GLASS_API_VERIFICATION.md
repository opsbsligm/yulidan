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
- [x] **P0 实机验收通过**（2026-08-28 用户回复「P0 验收通过」，已入册 `P0_ACCEPTANCE_CHECKLIST.md` 顶部 + `P0_STAGE_REPORT.md` 状态刷新，@d64e6f5）
- [x] §四 两个设计决策点**按推荐执行**（2026-08-28 用户未提异议，P1 两决策入册于验收清单横幅）：① 主题插件玻璃参数 = 材质档位 + tint（模糊/曲率/高光无数值参数，UI 明示「材质档位」；AppKit `NSGlassEffectView.cornerRadius` 候选保留但非默认）② 保留 GlassSurface legacy 降级链（渐进迁移）

## 六、官方文档行为语义核验（铁律 1：developer.apple.com 实拉，2026-08-22）

来源：`https://developer.apple.com/tutorials/data/documentation/swiftui/<page>.json`（官方文档数据端点，本机实拉成功；`Glass`/`GlassEffectContainer`/`GlassEffectTransition` 文档挂在 `swiftui` 命名空间下，类型宿主模块虽为 SwiftUICore）

| API | 官方语义（原文摘录） | 对 P1 的约束 |
|---|---|---|
| `glassEffect(_:in:)` | "Renders a shape anchored behind a view with the Liquid Glass material. Applies the foreground effects of Liquid Glass over a view."；默认 `.regular` + `DefaultGlassEffectShape`；"anchored to a view's bounds"（含 padding）；"typically used with [glassEffectID] to combine multiple Liquid Glass shapes into a single shape that can morph into one another" | 玻璃锚定 view bounds（改 frame 即改玻璃）；morph 必须配 glassEffectID |
| `glassEffectUnion(id:namespace:)` | "multiple views' geometries to contribute to a single Liquid Glass effect shape... All Liquid Glass effects with the same shape and Liquid Glass variant will be combined into a single shape" | 并集融合要求同 shape + 同材质变体——**Tab 分段与 morph 目标面必须用同一 Glass 变体与同型 shape** |
| `glassEffectID(_:in:)` | "You use this modifier with the [glassEffect] view modifier and a [Namespace] view. When used together, SwiftUI uses the identifier to animate shapes to and from each other during transitions" | 官方确认 = 目标 P1 §2 的 morph 机制（非模拟） |
| `GlassEffectContainer` | "combines multiple Liquid Glass shapes into a single shape that can morph individual shapes into one another... SwiftUI renders the effects together, improving rendering performance and allowing the effects to interact with and morph into one another... The higher the spacing, the sooner blending begins" | 官方确认 = 目标 P1 §1「同区域光学采样一致 + 性能」；`spacing:` 控制融合提前量（可调参项） |
| `GlassEffectTransition` | "describes changes to apply when a glass effect is added or removed from the view hierarchy"；预设 `.matchedGeometry`/`.materialize`/`.identity` | 弹窗/侧栏出入场挂 `.glassEffectTransition`（配 withAnimation） |
| `Glass` | "defines the configuration of the Liquid Glass material... combine Liquid Glass effects using a [GlassEffectContainer], which supports morphing views... based on the geometry of their associated views" | 材质配置入口 = 预设 + tint + interactive（与 §四 差异点一致：无数值模糊/曲率/高光参数） |

**悬停/交互反馈**：SDK 签名 `Glass.interactive(_:)` 存在（交互开关，默认 true）+ 官方「foreground effects」措辞 → 悬停/按压反馈属材质自带行为，P1 验收以实机观察为准（文档未单列 hover 小节）。

## 七、2026-08-26 锁屏复核（补充证据 + 1 项新发现）

> 背景：P0 验收等待期（机器锁屏，用户离席），对本文档结论做独立复核并补强证据。未写任何 P1 视觉代码（铁律 2）。

1. **编译探针实锤（强于签名核验）**：以本机工具链（Xcode 26.6 (17F113) / MacOSX26.5 SDK / target `arm64-apple-macos26.0`）对 §二 全族 API 做 `swiftc -typecheck` 探针——`GlassEffectContainer(spacing:)` 包裹 + `.glassEffect(.regular.tint(.blue).interactive(true), in: RoundedRectangle(...))` + `.glassEffectID("tab-a", in: ns)` + `.glassEffect(.clear, in: .rect(cornerRadius: 8))` + `.glassEffectUnion(id: "group-1", namespace: ns)` + `.glassEffectTransition(.materialize/.matchedGeometry/.identity)` + `Glass` 三预设/`tint`/`interactive` 全部编译通过 ✅（探针 /tmp/glassprobe.swift，仅 typecheck 未运行，不进仓库）。结论：§五「P1 开工前置条件」的 API 可用性从「签名在 interface」升级为「实编译通过」。
2. **⚠️ 新发现——AppKit 侧玻璃 API（§四.1 曲率决策点获得原生候选）**：macOS 26.5 SDK AppKit 含 `NSGlassEffectView`（`contentView` / `cornerRadius` / `tintColor` / `style`：regular/clear）与 `NSGlassEffectContainerView`（`contentView` / `spacing`，邻近合并语义与 SwiftUI 容器一致），均 `@API_AVAILABLE(macos(26.0))`（`NSGlassEffectView.h` 逐字在案）。**主题插件「曲率」参数**存在原生 AppKit 映射候选（`NSGlassEffectView.cornerRadius`，可经 `NSViewRepresentable` 嵌入）；但铁律 4 枚举清单未含此 API，**仍属设计决策点，待 P0 验收后与用户确认口径，不作默认**。模糊/高光仍无公开数值参数（结论不变）。
3. **官方文档复核（2026-08-26 重拉）**：`glassEffect(_:in:)` / `GlassEffectContainer` / `glassEffectTransition(_:)` 官方文档页平台可用性均仍为 **macOS 26.0+**（与 SDK availability 注解一致，无漂移）；`glassEffectID` 文档页拉取未返回平台行（接口文件 availability 已实锤 macOS 26.0+，以 SDK 为准）。
4. **工具链环境注记**：本机 OS = macOS 27.0 beta（26A5416b），Xcode = 26.6，已装 SDK 仅 MacOSX26.5（无 27 SDK）→ 编译面以 26.5 SDK 为准；文档头 ⚠️「xcrun 指向 CLT 旧 SDK」现象本轮未复现（`xcrun --show-sdk-path` = Xcode 26.5 SDK）。另：macOS 27 运行时下 `UUID().uuidString` 实测输出大写（与 Glass API 无关，P0 数据卫生轮发现，见 P0 验收清单 22:0x 条目）。


## 八、2026-08-28 P1 解锁复核（独立二次核验，非重复引用）

> 背景：P0 验收通过 → P1 解锁（@d64e6f5）。开工前按铁律 1 对 §二 签名做独立复核 + 探针重跑，确认与当前工具链零漂移。

1. **签名独立重核（本机 MacOSX26 SDK，`MacOSX26.sdk/.../SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface`，target `arm64e-apple-macos26.5`）**：
   - `glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`（`extension View`，nonisolated）——与 §二 逐字一致
   - `GlassEffectContainer<Content: View>`：`init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content)`——一致
   - `GlassEffectTransition`：`.matchedGeometry` / `.materialize` / `.identity` + `glassEffectTransition(_:)`（MainActor）——一致
   - `glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID)`（nonisolated）——一致
   - `glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID)`（MainActor）——一致
   - `Glass`：`.regular` / `.clear` / `.identity` + `tint(_ color: Color?) -> Glass` + `interactive(_ isEnabled: Bool = true) -> Glass`（Equatable & Sendable）——一致
   - 全部 `@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)` + visionOS unavailable；App 部署目标 `.macOS(.v26)` 对齐 → **无需 availability 守卫**
2. **`@_exported import SwiftUICore` 复核**：SwiftUI arm64e interface 第 17 行（`import SwiftUI` 即可用，§一 结论不变）
3. **编译探针重跑（当前工具链 Xcode 26.6，`xcrun --show-sdk-path` = MacOSX26.5.sdk，target `arm64-apple-macos26.0`）**：
   - `/tmp/glassprobe.swift`（§七-1 原探针：container + glassEffect 三变体 + tint/interactive + glassEffectID + glassEffectUnion + 三种 transition）→ **TYPECHECK PASSED**
   - `/tmp/glassprobe2.swift`（**本轮新增**：`.buttonStyle(.glass)` / `.glassProminent` / `.glass(Glass.regular.tint(.teal))`）→ **TYPECHECK PASSED**——§二 表末行按钮风格由「interface 核验」升级为「实编译通过」，5+2 族 API 全部编译级实证
4. **负面核验**：全框架 swiftinterface 范围 grep `GlassRegularEffect` → **不存在**（本 SDK 材质模型即 `Glass` 值类型，非 WWDC25 早期会话口径的 protocol 模型；签名以本文为准）
5. **结论**：§一~§七 全部结论有效，P1 开工前置条件 6/6 就绪（§五），可开工 P1.1。
