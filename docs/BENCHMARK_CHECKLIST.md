# G1 双轴对标审计清单（轴1 Apple 最佳实践 / 轴2 Codex 设计语言）

> 建档：2026-09-03（v8 目标 G1 轮）。状态口径：`✅达标 / ⚠️GAP / ❓未证实 / ⏳待取证`
> 铁律 8（静默验收）凌驾全篇：本档所有取证均为 A 层（零前台/零键鼠/锁屏可跑），
> 唯一例外见 §5「轴2 取证」——受 27 beta 窗口捕获限制，需用户择时。
> 引文规则（铁律 1/5）：Apple 口径 = 官方文档逐字摘录 + 可复核 URL；
> 「Codex 有 X」必须挂本机截图路径，无截图即不写结论。

## §0 取证通道能力实测表（09-03 本机 macOS 27.0 + Xcode 26.6 SDK 实测）★ 影响判据设计

| 通道 | 静默级别 | 玻璃/morph 像素可见性 | 实测证据 |
|---|---|---|---|
| `ImageRenderer` 离屏位图 | A 层 | **❌ 完全不渲染玻璃** | `tools/qa/glass-fidelity-probe.swift`：spacing 10/30/60 × 间隙 8/10/40 三组，「有玻璃 vs 无玻璃」**24000 像素逐点差异 = 0** |
| `NSView.cacheDisplay` | A 层（真窗口） | ❓ 未取证（CLI 建窗在本机 SIGTRAP，需在测试宿主内重试） | 探针未跑通，不下结论 |
| `CGWindowListCreateImage` | — | **❌ API 已从 macOS 27 SDK 移除** | 编译期报错「'CGWindowListCreateImage' is unavailable in macOS: Please use ScreenCaptureKit instead」 |
| `screencapture -o -x -l<wid>`（进程外只读） | A 层（不动焦点/不 activate） | ✅ 对**已存在的真实窗口**有效 | 本次截到 Harness 窗 3840×2100 真实像素 |
| 同上，对**离屏/其他 Space 窗口** | A 层 | ⚠️ 不可靠 | Codex 主窗（WID 554，在其他 Space）仅截回 274×318 畸变缩略 |
| ScreenCaptureKit | ❌ 需屏幕录制权限（TCC 弹窗=打扰用户） | — | 不采用 |

**结论 1（纠偏 v8 条款）**：v8 目标 G2 写的「用 ImageRenderer 像素帧判定 morph 流体融合」
**判据不成立**（上表第 1 行）。玻璃效果只能靠①结构性静态断言（A 层，能证"接线正确"）
＋②真机目检（用户 1 分钟，或用户认可"结构证据即满足该子句"）双轨核销。
此条不修正就继续执行 = 制造无效证据，故先登记再报告。

## §1 轴1 官方口径基线（逐字摘录，全部经 `tutorials/data/documentation/**.json` 通道复核）

1. **GlassEffectContainer** — "A view that combines multiple Liquid Glass shapes into a single
   shape that can morph individual shapes into one another."
   "Each view with a Liquid Glass effect contributes a shape ... SwiftUI renders the effects
   together, ... allowing the effects to interact with and morph into one another."
   "As shapes near one another, their paths start to blend into one another. **The higher the
   spacing, the sooner blending begins** as the shapes approach each other."
   — https://developer.apple.com/documentation/swiftui/glasseffectcontainer
2. **glassEffectID(_:in:)** — "Associates an identity value to Liquid Glass effects defined within
   this view." / "When used together [with glassEffect + GlassEffectContainer], SwiftUI uses the
   identifier to **animate shapes to and from each other during transitions**."
   — https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
3. **glassEffectTransition(_:)** — "... SwiftUI will use the provided transition to apply changes to
   the glass effect **when you add or remove views** with these effects from the view hierarchy."
   官方示例：`GlassEffectContainer(spacing: 10.0)` + `HStack(spacing: 10.0)`，`isExpanded`
   控制第二面**存在与否**，新面带 `.glassEffectTransition(.matchedGeometry)`。
   — https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)
4. **glassEffect(_:in:)** — "Renders a shape anchored behind a view with the Liquid Glass material.
   Applies the foreground effects of Liquid Glass over a view." / "SwiftUI uses the regular variant
   by default along with a **Capsule** shape." / "You typically use this modifier with a
   GlassEffectContainer to combine multiple Liquid Glass shapes into a single shape that can morph
   into one another." — https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
5. **glassEffectUnion(id:namespace:)** — "... specify that a view should contribute to a union of
   Liquid Glass effects with a particular identifier. All Liquid Glass effects with **the same shape
   and Liquid Glass variant** will be combined into a single shape."
   — https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)
6. **Glass** — "You can combine Liquid Glass effects using a GlassEffectContainer, which supports
   **morphing views with this effect into each other based on the geometry of their associated
   views**." 变体仅 `regular` / `clear` / `identity`（+ `tint(_:)` / `interactive(_:)`）。
   — https://developer.apple.com/documentation/swiftui/glass
7. **interactive(_:)** — 官方仅一句 "Returns a copy of the structure configured to be interactive."
   **未记载默认值** — https://developer.apple.com/documentation/swiftui/glass/interactive(_:)

⚠️ 撤销一条既有嫌疑（自我纠偏）：早前审计怀疑「`withAnimation(.smooth)` 不是官方 morph 触发
方式，需换 spring」。**官方文档对 morph 未规定任何动画类型**（§1.2 只讲 identifier），
该嫌疑属脑补，现撤销（铁律 1）。

## §2 轴1 审计项（a–g 原文未入册 → 本轮按公开最佳实践重建 8 项，口径不同请以你的为准）

| # | 审计项（官方最佳实践） | 状态 | 证据 / GAP 定位 |
|---|---|---|---|
| A1 | **参与 morph 的玻璃面需 ≥2 且同处一个容器**（§1.1 语义前提） | ❌ **GAP（根因级）** | `GlassMorphTabBar.swift` L132-138：仅**选中** tile 走 `glassEffect`，`TileFaceMode.resolve` 未选中 → `.plain`（无玻璃）。容器内**恒为 1 个玻璃面** → 官方"形状靠近时路径融合"无对象，视觉上只能是淡变。这解释 P1.2 实机"交叉淡变"（注记①），且与动画曲线无关 |
| A2 | **容器 spacing 是融合提前量的显式调参项**（§1.1 末句） | ⚠️ GAP | 全仓 4 处 `.glassSurfaceContainer()`（GlassMorphTabBar L76 / SidebarView L97 / SettingsView L160 / ChatInputArea L135）**均传 nil**=系统默认（官方未公布默认值，❌不猜数值） |
| A3 | **`.matchedGeometry` 面向"视图增删"场景**（§1.3） | ❓ 未证实 | 我们把 `.glassEffectTransition(.matchedGeometry)` 挂在**常驻**选中面上（L138）。文档语义针对增删；常驻面是否生效无文档保证 → 需真机目检，不下结论 |
| A4 | **玻璃锚定内容 bounds，内容保持锐利**（§1.4） | ✅ 达标 | 08-29 已按官方模式重构（`glassEffect` 直施于内容，弃 `background` 挂法），入册 GlassMorphTabBar L110-119 注释 + 像素直方图证据 |
| A5 | **默认 shape = Capsule**（§1.4）→ 自定义形状须同型才能 union/morph（§1.5） | ✅ 达标 | 统一 `tileShape = RoundedRectangle(10, .continuous)`；union 同变体约束在 SettingsView L159 注释在册 |
| A6 | **材质参数只有 3 变体 + tint + interactive**（§1.6）→ 不存在"曲率/模糊/高光"可调 | ✅ 已知天花板 | 已在 `P1_GLASS_API_VERIFICATION.md` §四登记；残留 GAP：主题 manifest 若仍暴露"曲率/模糊"字段=**假参数**，应显式声明不支持（D-4 相关） |
| A7 | **interactive 语义/默认值**（§1.7 未记载） | ❓ 未证实 | 代码注释声称「悬停/按压反馈 = Glass.interactive 材质自带」**无官方依据** → 要么实测，要么改注释口径（D-2） |
| A8 | **无障碍降级**（减弱透明度 → 非玻璃表面） | ✅ 达标 | `GlassSurface` 三态 `resolveMode` + 容器 `shouldWrap` 同源门控，测试在册（867 项 xcresult） |

## §3 GAP 汇总与修复方向（性价比排序，全部纯原生 API）

| GAP | 严重度 | 修复方向 | 静默判据（修复后） | 真机目检 |
|---|---|---|---|---|
| **A1 容器内单玻璃面** | **P0（D-1 根因）** | 让未选中 tile 也持玻璃面（同 variant/同型 shape），选中态改用 tint/前景强调区分 → 容器内 6 面共存，融合才有对象 | 纯函数改造后单测断言「native 态下参与 morph 的玻璃面数 == segments.count」 | 需要（切换时是否出现"液体颈"连接） |
| **A2 spacing=nil** | P1 | 容器 spacing 显式化，取值 ≥ 网格间距并做 3 档对比（6 / 12 / 20pt） | 单测断言 spacing 非 nil + 值来自集中常量 | 需要（融合提前量） |
| A3 常驻面挂 transition | P2 | 按 A1 改造后重估：若改为"所有面常驻"，则 `.matchedGeometry` 可能应移除（文档语义=增删） | 结构断言（是否仍挂 transition） | 需要 |
| A7 interactive 口径 | P2 | 二选一：改注释为"未证实"或删除该宣称 | 文档一致性 | 悬停需目检 |
| A6 manifest 假参数 | P3 | manifest 未支持字段显式拒绝 + 提示 | 单测：未知/不支持 key 不产生效果 | 不需要 |

## §4 取证判据（修订版，替代 v8 G2 的离屏像素判据）

1. **A 层结构判据**：玻璃面数量 / 容器存在性 / spacing 值 / 同型 shape / 同变体 / 降级门控
   —— 全部单测可断言，锁屏可跑，作为**每次修复的默认回归**。
2. **A 层真机静态帧**：`screencapture -o -x -l<wid>` 截**已存在**的 Harness 窗口（不 activate、
   不动键鼠）→ 判定静态玻璃呈现（如 6 面是否都可见玻璃）。仅解锁有效。
3. **过渡态判据（morph 流体感）**：⚠️ 无静默通道（§0 结论 1）→ 归 D-1 用户裁决：
   (a) 用户顺手 1 分钟手动切换并目检；或 (b) 认可"A 层结构判据 + 静态帧"即满足该子句。

## §5 轴2 Codex 设计语言取证现状（本轮：仅登记，不下界面结论）

- 本机实装 Codex 桌面端窗口枚举（只读，含其他 Space）：`WID=554 owner=ChatGPT 1250×793`（主窗，
  位于其他 Space）、`WID=4724 owner=ChatGPT 772×1815`（宠物浮层，截回 1544×4138 白底+宠物）、
  另有若干 1470×33 菜单栏级窗口与权限类浮窗。
- 截图尝试：主窗 554 → `/tmp/g1b/codex_554.png` **274×318 畸变缩略**（其他 Space 窗口捕获受限）；
  宠物窗 `/tmp/g1b/codex_main_4724.png` 非界面内容。
- **本轮结论：轴2 界面级证据源当前不可静默获取**（与 §0 第 5 行一致）。需你择时其一：
  (a) 把 Codex 窗口切到前台并保持可见，我只 `screencapture -l` 只读取证（不点击、不 activate）；
  (b) 你手动丢几张 Codex 截图（含设置页）给我，我以文件路径入册；
  (c) 轴2 延后到 G2 中段。
- 在拿到截图前，**不写任何"Codex 有 X"的条款**（铁律 5）。
- ⚠️ **旧档取证口径不合规需重取（诚实登记）**：`docs/UI_CODEX_ALIGNMENT.md`（F7，@17a0fd8）
  「二、差距清单」的 **Codex 行为列全部无截图取证**（方法自述为"逐文件读当前实现 + 与 Codex
  桌面端布局/交互范式对照"），且 B1–B8 闭环项多数标注"视觉验收待实机"。
  按 v8 铁律 5（"Codex 有 X"必须挂本机截图），F7 的**对标依据在 v8 口径下不成立**，
  其**代码改动本身**（有 commit/测试）不受影响、无需回退，但**结论列需在你提供截图后重判**。
- 轴2 差距条目登记模板（证据到位即按此填，四件套缺一不登记）：
  `Codex 截图绝对路径` ＋ `我方文件:行号` ＋ `原生适配表达（具体 API/修饰符）` ＋ `性价比评级(★1-5)`。

## §6 待你拍板（不代拍）

- **D-1（morph 翻案）判据修订**：接受 §0 结论 1（离屏像素判据作废）→ 按 §4 三轨执行？
  A1 根因修复是否批准进入 G2 头号项？
- **D-2**：A7 `interactive` 宣称——改注释口径 / 还是安排一次真机悬停目检？
- **D-4**：主题 manifest 假参数（A6）是否显式拒绝不支持字段？
- **轴2 取证方式**：§5 (a)/(b)/(c) 选一。
- 既有 D-3（C4 卡片归组）/ D-5（插件路线 A/B/C）/ D-6（空会话 24 个处置）不变。

---

## §7 轴1 补强：官方**指南级**原文（09-03 第二轮，HIG + SwiftUI 指南页）

> 通道打通：HIG 与 SwiftUI 指南页正文可经 `https://developer.apple.com/tutorials/data/documentation/<path>.json`
> 与 `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json` 直取
> （页面本体是 SPA 壳，curl HTML 拿不到正文——早前"HGI 拉不到"已解决）。

### 1.8 《Applying Liquid Glass to custom views》— morph 触发条件（判据级）
- "For effects you want to add or remove that are **positioned within the container's assigned
  spacing**, the default transition type is matchedGeometry."
- "Use the `materialize` transition for effects you want to add or remove that are **farther from
  each other than the container's assigned spacing**."
- 判据尺寸 = **最近边**："This morphs the eraser image into the pencil image when the eraser's
  **nearest edge is less than or equal to the container's spacing**."
- "SwiftUI uses **the spacing provided to the effect container along with the geometry of the shapes
  themselves** to determine when and which appropriate shapes to morph into and out of."
- "**Animating views in or out causes the shapes to morph apart or together as the space in the
  container changes.**"
- 容器价值："allows views with Liquid Glass effects to **blend their shapes together and to morph in
  and out of each other during transitions**"；"Creating **too many** Liquid Glass effect containers
  and applying too many effects to views outside of containers **can degrade performance**. Limit the
  use of Liquid Glass effects onscreen at the same time."
- 修饰符顺序（新审计项 A9）："The `glassEffect(_:in:)` modifier captures the content to send to the
  container to render. **Apply the `glassEffect(_:in:)` modifier after other modifiers that affect
  the appearance of the view.**"
- union 前提："combines all effects with a **similar shape, Liquid Glass effect, and ID**"。
  — https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views

### 1.9 HIG《Materials》— 层级与克制（设计合规级）
- "Liquid Glass forms a distinct **functional layer** for controls and navigation elements — like
  **tab bars and sidebars** — that floats above the content layer."
- "**Don't use Liquid Glass in the content layer.** ... using Standard materials for elements in the
  content layer, such as app backgrounds."（例外：内容层中瞬时交互件如 Slider/Toggle）
- "**Use Liquid Glass effects sparingly.** ... Limit these effects to the most important functional
  elements in your app."
- 变体口径："The **regular** variant blurs and adjusts the luminosity of background content to
  maintain legibility ... such as alerts, sidebars, or popovers." / "**clear** ... for components that
  float above media backgrounds"；亮背景上 clear 需 "a dark dimming layer of **35% opacity**"。
- 系统开关联动："The appearance of these variants can differ in response to certain system settings,
  like ... **reduce transparency** or increase contrast."
- — https://developer.apple.com/design/human-interface-guidelines/materials

### 1.10 `interactive` 语义（**纠偏既有宣称**）
- "**Add** interactive(_:) to custom components to make them react to touch and pointer interactions.
  This applies the same responsive and fluid reactions that glass provides to standard buttons."
  官方示例：`.glassEffect(.regular.tint(.orange).interactive())`
  → **显式开启，非默认自带**。我方 `GlassMorphTabBar` 旧注释「悬停/按压反馈 = Glass.interactive
  材质自带」属未证实宣称 → 本轮按官方补齐 `.interactive()`（F2），A7 由 ❓ 转 ✅（有原文）。

## §8 结论修正（自我纠偏，铁律 1/6）

| 上轮结论 | 修正后（官方原文为据） |
|---|---|
| A1「容器内单玻璃面 → 必须给未选中面补玻璃才有融合对象」 | **撤销**。官方 morph 构造恰恰是"**add or remove**"（"Animating views in or out causes the shapes to morph apart or together"），单选中面移除+插入是正确形态；**补 6 面反而制造静止态融合（官方警告 "blend together at rest"）＋违反 HIG "sparingly"** |
| A2「spacing=nil 只是未调参」 | **升级为根因**：官方判据 = 最近边 ≤ 容器 spacing 才走 matchedGeometry；我们 spacing=nil（系统默认值官方未公布），而最远切换对的最近边距离 ≈ 88pt → 大概率**超出**默认 spacing → 远距离切换**静默退回淡变**。这就是 P1.2 实机「交叉淡变」的可解释根因，且与动画曲线无关 |
| A7「interactive 可能材质自带」 | 官方为**显式 Add**（§1.10）→ 已按官方补齐，宣称有据 |

## §9 本轮已执行修复（G2 头号项 F1/F2，@本轮提交）

| 项 | 改动 | 静默判据（A 层，已跑绿） | 真机目检 |
|---|---|---|---|
| **F1 morph 覆盖度** | `GlassMorphTabBar` 容器 `spacing` 由 nil → `MorphTabGeometry.fullGridSpacing`（= 最坏最近边距离向上取整；静止态恒单面 → 官方"静止即融合"代价结构性不可达）；`selectionID` 由 private 提级为 internal 供判据引用 | 新增 5 条 `MorphTabGeometryTests`：容器 spacing ≥ 最坏最近边距离、同列/相邻列/最远切换全部落入 `qualifiesForMatchedGeometry`、列数退化防御、间距单调性、全网格 ⊃ 相邻 | **待你 1 分钟**：切 tab 看是否出现"液体颈"连接而非淡变 |
| **F2 指针反馈** | 选中面材质 `.interactive()`（官方显式开启），经纯函数 `selectedGlass(from:isSelected:)` 单点 | 新增 3 条 `SelectedGlassTests`：选中面==`base.interactive()` 且≠裸材质；未选中面原样；主题 tint 叠加不丢失 | 悬停/按压反馈需目检 |
| 注释纠偏 | 撤销「材质自带」宣称；文件头写入官方判据逐字 + 撤销 A1 推断的说明 | 文档一致性（本节） | 不需要 |

## §10 新增审计项（下轮 G2 待办）

### A9 修饰符顺序（§1.8 末）→ ✅ 本轮已审，无违规
12 个 `.glassSurface(` 调用点 + Tab 栏 1 处 `glassEffect` 全量核查 `.glassSurface` **之后**的外观修饰符：
- `.overlay(stroke)` ×2（`SettingsSubPages.swift:216`、`ChatInputArea.swift:118`）→ 描边画在玻璃**之上**、
  不参与玻璃捕获，属预期（solid 降级态也需要同一描边）；**无** padding/background/opacity 后置。
- `.frame(width:110, alignment:.leading)` ×1（`SettingsView.swift:511`）→ 玻璃面先按内容尺寸成形，
  再进入 110pt 列内左对齐 = **刻意且正确**（快捷键 chip 贴合文字），非缺陷。
- 结论：官方「`glassEffect` 应在影响外观的修饰符**之后**施加」满足——我方所有影响尺寸/外观的修饰
  （font/padding）均在 `.glassSurface` **之前**，玻璃捕获的是最终内容 ✓。

### A10 内容层玻璃合规（§1.9）→ ✅ 本轮已审，无违规
全 `Sources/` grep `glassSurface|glassEffect`：命中文件仅 8 个，**全部属功能层**
（Sidebar×2 / TabBar / Settings×2 / SettingsSubPages / MCPServerViews / ChatInputArea /
SidebarProjectSections / SidebarSupportViews / Styles 收口层）；
**聊天消息与滚动内容区 0 处玻璃** → 符合 "Don't use Liquid Glass in the content layer"。
残留：`GlassLevel.thin` 旧注释自称"气泡、内联行、chip"与实际用法不符（气泡并不用玻璃）→ 本轮已随
A11 一并改写注释，消除误导。

### A11 `GlassLevel` 三档原生态真实性 → ✅ 注释口径本轮已纠偏
代码事实（`GlassSurface.swift`）：三档在 macOS 26 原生态**不改变 `Glass`**（统一走 `resolvedGlass`），
仅影响 legacy 材质映射（hudWindow/popover/sidebar）与 solid 实色。Apple 只有 regular/clear 两变体
（§1.9）。→ 本轮把枚举注释改为「**语义层级/用途分层**，非玻璃厚度」并写明生效路径；
是否进一步改名 `SurfaceRole` 属可选美化（不影响行为），**留你定**（并入 D-4 类美化项）。

### A12 效果总量与容器数（§1.8 性能段）→ ✅ 静默护栏已入册（@3d66ba0）+ RSS 平台期成立
静态部分已由可执行守卫接管：`GlassSurfaceRegistryTests`（注册表双向比对 12+4 调用点、
原生 API 白名单、反向验证红绿闭环，㉜在册）；RSS 侧三点平台期见 PERFORMANCE.md 正式判定节。
静态计数在册：容器 4 个、`.glassSurface` 调用点 12 个、Tab 栏玻璃面 1 个（选中态）。
同屏面数运行时统计 = G3 走查 `axdump` 快照（已写入 G3_MVP_WALKTHROUGH 手册前置），
护栏口径 = "Limit the use of Liquid Glass effects onscreen at the same time" + PERFORMANCE.md。

## §11 轴1 再补强：WWDC25 逐字稿原文（09-03 第三轮，文档通道）

> 通道：视频页 HTML 内嵌 `<span data-start="…">` 逐字稿可 curl 直取（219 全文 18,030 字、
> 323 全文 16,361 字，本机留存 `/tmp/ww219_transcript.txt`、`/tmp/ww323_transcript.txt`，
> 版权所限仅摘录短句入册，不整篇入库）。

### 1.11 WWDC25 Session 219《Meet Liquid Glass》——设计意图（对 D-1 直接相关）
- "**Instead of fading**, Liquid Glass objects materialize in and out by gradually modulating the
  light bending and lensing, ensuring a graceful transition that preserves the optical integrity
  of the material." → **官方明确以「不淡变」为设计底线**；我们的「交叉淡变」不是风格差异，
  是官方点名避免的形态 → F1 必要性升级为合规项。
- "As you go between states in an app, Liquid Glass dynamically **morphs between the controls** in
  each context. This maintains the concept of having a **singular floating plane** that the controls
  live on."
- "The **sidebar and tab bar**, together, form a cohesive … **single navigational element** that
  fluidly scales as the canvas of the app grows."
- 材质随尺寸变化："When glass **flexes and morphs to larger sizes** – like when presenting a menu
  from a toolbar button – its material characteristics change to simulate a **thicker, more
  substantial material**. It casts deeper, richer shadows, has more pronounced lensing…"
- **无障碍语义（⚠️ 与我方实现有差异）**："**Reduced Transparency**, makes Liquid Glass **frostier
  and obscures more of the content** behind it. **Increased contrast**, makes elements predominantly
  black or white and **highlights them with a contrasting border**."
  → 系统语义 = 玻璃「更霜」；我方 `GlassSurface` 在 reduceTransparency 下走 **solid 纯色**。
  不是 bug（可读性更强、已实机验收），但**与系统语义不同轨** → 登记 A14，交你裁决。
- 静止态交叠："In **steady states**, such as when an app first launches, **avoid intersections
  between content and Liquid Glass**. Instead, reposition or scale the content to maintain
  separation."（→ 审计项 A17）
- tint 语义（⚠️ 直接触及我们主题插件的定位）："You can also use custom colors. But **use them
  selectively**. When items or elements serve a **distinct functional purpose**, you can tint them…"
  / "If you want to imbue color into your app, **do it in the content layer instead**."
- 滚动边缘："As content begins to scroll underneath a glass element, the effect **gently dissolves
  the content into the background**, lifting the glass visually…"（→ A16）

### 1.12 WWDC25 Session 323《Build a SwiftUI app with the new design》——实现口径
- "Add these transitions to your own glass container by using the **glassEffectID** modifier…
  I associate the namespace with **each** of the glassEffect elements … **and with my toolbar
  button**." → 官方实践是**每面各自一个 ID**（与我们 tab 栏「共享单一 selectionID」构造不同，
  见 §12 F3 讨论；两者各有官方出处，需以视觉结果裁决）。
- "for custom controls or for containers with interactive elements, **add the interactive modifier**…
  Glass reacts to user interaction by **scaling, bouncing, and shimmering**"（F2 互证 ✓）
- "To combine multiple glass elements, use the **GlassEffectContainer**. **This grouping is essential
  for visual correctness.**"
- "If you've used the `presentationBackground` modifier to apply a custom background to your sheets,
  **consider removing that and let the new material shine**."（→ 我们 sheet 若自铺背景即同类反模式）
- 玻璃之上有内容可折射的前提（侧栏案例）："They now have a Liquid Glass sidebar that **floats above
  your content** … with the pink blossoms **refracting against the sidebar**." ＋
  "With the new **`backgroundExtensionEffect`** modifier, views can extend outside the safe area…"

### 1.13 本机 SDK 存在性核验（铁律 1：先核 SDK 再下结论）
`SwiftUI.framework` arm64e-apple-macos.swiftinterface（Xcode 内 macOS 26.5 SDK）grep 计数：
| WWDC25 提到的 API | 本 SDK | 结论 |
|---|---|---|
| `backgroundExtensionEffect` | **命中 2** | 可用（内容延伸到安全区外 → 玻璃有东西可折射） |
| `scrollEdgeEffectStyle` | **命中 1** | 可用（滚动边缘效果） |
| `containerConcentric` / `ConcentricRectangle` | **命中 0** | **本 SDK 无** → 圆角同心（corner concentricity）暂不可落地，❌不得宣称支持 |

## §12 新审计项（A13–A19，本轮全部来自官方原文＋本机代码事实）

| # | 项 | 状态 | 证据 / 影响 |
|---|---|---|---|
| **A13 装饰性全局 tint** | ⚠️ **冲突（需裁决）** | 官方：tint 用于**功能性强调**、"use them selectively"、色彩应放内容层。我方 P1.4 把主题 `glassTintHex` 铺到**所有**玻璃面（纯装饰性全局染色）→ 与官方口径冲突，且影响"主题插件"卖点定义（主题该染什么） |
| **A14 减弱透明度语义** | ⚠️ 不同轨（需裁决） | 系统 = frostier glass（仍折射）；我方 = solid 纯色（可读性更强、已实机验收）。二选一：保 solid / 或新增「frosted」中间态 |
| **A15 玻璃折射源缺失** | ❌ **根因级（比 morph 更根本）** | 代码事实链：`HarnessApp.swift:136` `window.backgroundColor = NSColor.windowBackgroundColor`（**不透明窗底**）＋ `ContentView.swift:11` `HStack(spacing:0)`（侧栏与内容**并排**，非浮于其上）＋ `HarnessTheme.swift:8` surface=不透明窗口色 → 侧栏玻璃**身后既无内容也无桌面**，按 §1.12「sidebar floats above your content / refracting against the sidebar」的材质前提，**必然呈现扁平灰片**。讽刺点：legacy 降级分支用 `VisualEffectMaterial(blendingMode: .behindWindow)` 真采桌面，**采样能力反而强于原生态路径**（`GlassSurface.swift:224/229`） |
| **A16 滚动边缘效果** | ✅ 已审·结构性 N/A（§15） | 侧栏会话列表/消息滚动进入玻璃下方时是否有 dissolve 效果；`scrollEdgeEffectStyle` 本 SDK 可用（§1.13），我们未使用 |
| **A17 静止态内容交叠** | ⚠️ 折叠 rail 命中（§15） | 官方要求启动静止态避免内容与玻璃交叠（§1.11）；需审 composer/顶栏与消息流初始位置 |
| **A18 sheet 自铺背景反模式** | ⚠️ 1/5 命中（§15） | 官方建议移除 `presentationBackground` 类自铺背景；需审设置 sheet/概览 sheet 是否自填底色（`SettingsView.swift:158-160` 附近有 prominent 面） |
| **A19 圆角同心** | ❌ 不支持 | 本 SDK 无 `containerConcentric`（§1.13）→ 只能手设各层圆角，存在视觉不同心风险；❌不得宣称已支持最佳实践 |

## §13 新增提案（F3/F4，等你拍板后实施）

- **F3｜tab 栏玻璃形态二选一**：
  (a) **现状＋F1**：单一选中面在 6 格间 morph（"流动的选中块"），未选中面素净；
  (b) **官方 segmented 形态**：6 面常驻 + `glassEffectUnion` 合成**单一形状**（§1.5 "even when your
  content is at rest"＋§1.11 "singular floating plane"），选中态用 tint/前景强调 → 更像系统分段控件。
  两者都有官方出处，**只有真机目检能裁决**（无静默像素通道，§0）。
- **F4｜让玻璃有东西可折射（A15 修法，二选一或并用）**： **〔执行态 09-04：用户拍板 (a) 已实施 @`ee1da43`，实况终裁 G3 A-d〕**
  (a) **窗口透明底**：`window.isOpaque=false` + `backgroundColor=.clear`（AppKit 层，改动小、可回退）
  → 侧栏玻璃采**桌面**，恢复 macOS 侧栏传统；可读性由 regular 变体的 blur/luminosity 调整负责（§1.9 原文）。
  ⚠️ 风险：窗口内文字对比度与"内容区是否也变透"需目检；`NSWindow` 行为改动属可见状态变化，验收需你 1 分钟。
  (b) **内容延伸到玻璃之下**：用本 SDK 已有的 `backgroundExtensionEffect`（§1.13 实证存在）把内容/背景
  铺到侧栏后方 → 折射源来自 App 自身内容（Apple 侧栏案例正是此法）。改动面大于 (a)。
  **我的建议**：先做 (a)（小、可回退、直接决定玻璃是否"活"），(b) 视 (a) 的目检结果再定。


- **F5｜设置完整页 sheet 撤自铺底（A18 修法，单行）**：删除 `SettingsCompletePage.swift:63`
  `.background(HarnessTheme.surface)` → 让系统 sheet 材质透出（WWDC323 原文口径）。
  改动极小可回退；⚠️ 可见状态变化，验收走「用户目检」或「A 层编译+测试满足即核销」二选一。
  建议与 D-10 材质议题同批裁决（透明底窗口下，sheet 自铺不透明底同样挡折射）。
- **F6｜折叠 rail 顶部避让红绿灯 + overlay 展开按钮错位（A17 修法，两个小改动）**：
  (a) `collapsedBody` 顶部加 ≈38pt 避让带（rail 宽 52 < 红绿灯带宽 62，x 避让不可行，只能 y 下沉，
      与 Codex 等应用 rail 顶部留空一致）；
  (b) `ContentView.swift:64-79` 折叠 overlay 展开按钮从 `.padding(10)` 改为顶部避让带之下起算。
  官方配套事实：`fullSizeContentView` 头文件原文「contentView will consume the full size of the
  window… Utilize the contentLayoutRect or auto-layout contentLayoutGuide to layout views
  underneath the titlebar/toolbar area」（NSWindow.h L48，macOS 10.10+ 双 API 本机 SDK 在头中实证）。
  ⚠️ 属可见状态变化，且与 R1② 已核销证据存在一个待对齐点（见 §15 A17-2），以真机目检为准。

## §14 【待确认】新增两项

- **D-10**：F4 折射源修法 → **(a) ✅ 拍板并实施 @09-04 `ee1da43`**（透明窗底；(b) backgroundExtensionEffect 未选、(c) 未选——账本 DECISION_INDEX）。
  不选 (c) 的话，玻璃质感提升的上限基本由此决定 —— 这是本轮最重要的单项。
- **D-10 拍板材料加固（09-03 补记㊹·官方原文双项，A 层静默）**：
  - **(a) 窗口透明底**：官方**无**「glassEffect 透过透明窗底采样桌面」明文——该因果属机制推断；
    推断的可信锚 = 我方 legacy 分支 `VisualEffectView.material=.hudWindow / blendingMode=.behindWindow`
    （`GlassSurface.swift:224/229` 在册）+ NSVisualEffect blendingMode 官方语义「采窗后桌面」。
    ⚠️ 风险标注：实施小可回退，但**成败判定只能 G3 A-d 目检**（无静默像素通道，§4 口径）。
  - **(b) backgroundExtensionEffect（本轮新取三重实证）**：
    ① 本机 SDK 注解逐字（arm64e swiftinterface）`@available(…, macOS 26.0, *)`（§1.13 存在性→精确化）；
    ② 官方文档页 data JSON **全文首次入档**："The view will be duplicated into mirrored copies which
    will be placed around the view **on any edge with available safe area**… a blur effect will be
    applied on top… Use this modifier when you want to extend the view beyond its bounds so the copies
    can function as backgrounds for other elements on top. The most common use case is… the **detail
    column of a navigation split view** so it can **extend under the sidebar**… **Apply this modifier
    with discretion**… often used with **only a single instance** of background content with consideration
    of **visual clarity and performance**… will **clip the view** to prevent copies from overlapping…"
    ③ **结构性前提在册**：生效需目标边「available safe area」；我方现状布局 `ContentView.swift:11`
    `HStack(spacing:0)` 并排、无 leading 安全区，官方用例是 NavigationSplitView 体系 → 选 (b) 需
    布局改造+安全区实测，改动面显著大于 (a)；且官方明示性能/单例约束（A12 口径联动）。
  - **建议不变**：(a) 先行（小、可回退），(a) 目检不达预期再评估 (b)；(c) 为放弃质感上限项。
- **D-11**：A13 主题 tint 定位 → 全局装饰染色（现状，卖点直观）/ 仅功能件染色（官方口径）/ 二者兼容（主题可声明 tint 作用域，默认仅功能件）。

- **D-12**：F5（设置完整页撤自铺底）+ F6（折叠 rail 避让带 + overlay 错位）执行批次。
  两者均为可见状态变化、无静默视觉通道 → 修前/修后各需你顺手 1 分钟目检，或认可静态几何证据直接修+编译测试核销。

## §15 A16/A17/A18 审计结论（09-03 第四轮·全程静默 A 层）

**事实基座（本轮新增，先立地基再下结论）**
- 官方（本机 SDK ObjC 头逐字，NSWindow.h L48/L314-318）：
  `NSWindowStyleMaskFullSizeContentView`「contentView will consume the full size of the window;
  … only respected for windows with a titlebar. Utilize the \c contentLayoutRect or auto-layout
  \c contentLayoutGuide to layout views underneath the titlebar/toolbar area.」；
  `contentLayoutRect`「returns the portion of the layout that is not obscured under the toolbar…
  in window coordinates. KVO compliant」（macOS 10.10+）→ **官方口径：内容延伸进标题栏区是设计使然，
  避让靠显式工具，系统不会自动 inset**。
- 本 App 实证（仓内既有事实，非本轮推测）：`SidebarView.swift:155-157` P1.5 注释记录红绿灯实测带
  **x∈[10,62] / y∈[8,28]**（内容坐标），且当时仅 x 避让（leading 56）即通过实机验收
  → **内容原点 == 窗口原点（无顶 inset）**，与上条官方口径一致。
- 窗口事实：`HarnessApp.swift:128-133` fullSizeContentView + titlebarAppearsTransparent +
  titleVisibility hidden。

### A16 滚动边缘效果 → ✅ 已审：**当前结构性 N/A**
逐区核查（代码事实）：① 聊天区 `ChatAreaView.swift:11-49` 纯 `VStack(spacing:0)`——顶栏/消息流/
composer 三段并排，**消息永不从任何玻璃面下滑经过**；顶栏 `ChatAreaView.swift:14`
`.background(.ultraThinMaterial)`（legacy 材质，非 glassEffect，本就不具备 scrollEdge 行为）；
② 侧栏为**单一整面玻璃**（`SidebarView.swift:95/97`），会话列表滚动**在玻璃面之上**（内容是玻璃的
子内容，非玻璃之下）；③ tab 栏玻璃在侧栏底部，其下无滚动内容。
→ `scrollEdgeEffectStyle`（SDK 存在性 §1.13 在册）**当前无适用对象**；若 D-10 走 F4(b)
（内容延伸到玻璃之下），侧栏/列表即成为适用区。顺带登记材质口径观察：聊天顶栏 ultraThinMaterial
与玻璃体系不同轨，统一决策挂 F4/D-10 批次。

### A17 静止态内容交叠 → ⚠️ 折叠 rail 左上角静态命中（三方交叠）
- ✅ 聊天区（VStack 并排，顶栏/输入区与消息流静止零交叠）；✅ Toast（瞬态件，非静止态条款对象，
  且 bottom 70 已避 composer）。
- ⚠️ **折叠态 rail 左上角交叠簇**（静态几何，Y 基准=上节实证）：
  ① rail 首个图标「新对话」28×28：x∈[12,40]、y∈[0,28]（`SidebarView.swift:371-381` VStack 无顶 padding）；
  ② ContentView 折叠 overlay 展开按钮 26×26 `.padding(10)`：x∈[10,36]、y∈[10,36]
  （`ContentView.swift:64-79`，SwiftUI overlay 绘制于侧栏之上）；
  ③ 红绿灯带 x∈[10,62]、y∈[8,28]（实测在册）。
  三者两两相交（①∩② ≈24×18pt；①②均落在③带内）。**潜在功能后果分级**：②盖①（overlay 抢点击，
  「新对话」图标点不中，⌘N/品牌菜单不受影响）；若红绿灯层序高于内容则近旁点击误触窗口按钮——
  此半点为机制推断。**09-03 静态复核（补记㊷·A 层零占用）**：
  (a) 几何断言**复核成立**（三锚点现行代码在位：rail 首图标 VStack 无顶 padding=现 L371-381、
  overlay `.padding(10)`=现 ContentView.swift:56-71、红绿灯带实测在册）；
  (b) 功能后果**A 层不可判定——官方双沉默实证**：
  ①`overlay(alignment:content:)` 官方文档页正文（data JSON 通道原文 2343 字符）对 safe area inset
  行为**零提及**→「overlay 按钮落入红绿灯带」不能当官方保证的断言；
  ②`standardWindowButton:`（本机 SDK NSWindow.h L605-606）仅声明无 z 序注释→
  「红绿灯层序高于 contentView」无官方原文，属 AppKit 实现层经验，禁按铁律 1 定为缺陷；
  (c) R1② 张力**定性为口径不同非矛盾**：AX press 不经 hit-test 遮挡；且 R1② 含你实机手动
  折叠/展开往返未见异常报告→实机侧本就更接近「无功能缺陷」。
  **定级收敛**：几何交叠成立、功能缺陷无实机反证，终裁归 G3 A-b 目检一眼；F6 维持 D-12 待批，不擅动。
- 附注：rail 宽 52 < 红绿灯带宽 62 → 折叠态 **x 避让不可行**，只能 y 下沉（与 Codex/VSCode 类
  rail 顶部留空同型）。展开态品牌行已按 x=70 避让（在册，不受影响）。

### A18 sheet 自铺背景 → ⚠️ 5 处 sheet 命中 1
- ❌ `SettingsCompletePage.swift:63` `.background(HarnessTheme.surface)`：sheet 根视图自铺**不透明底**
  ——正是 WWDC323 点名的反模式（「consider removing that and let the new material shine」）。
- ✅ 合规 4：重命名 sheet（`SidebarProjectSections.swift:201` glassSurface(.regular) 无自铺底）、
  删除确认 sheet（同 231）、归档管理 sheet（`SidebarSupportViews.swift:78` glassSurface(.regular)）、
  MCP 日志 sheet（`MCPServerViews.swift:116` 玻璃面 + 内部 0.5 透明度**内容层**底色，属内容层着色可接受）。
- 修法 F5（单行撤底）。建议与 D-10 材质议题同批（透明底窗口方案下，sheet 不透明底同样阻断折射源）。

### A12 附产（顺带登记）
`SidebarProjectSections.swift:339` 会话行 `.glassSurface(.thin)` → **运行时玻璃面数随会话列表行数线性增长**，
G2 的运行时面数护栏必须把此调用点列入统计口径（静态计数 12 处掩盖了这一点）。

## §16 轴2 取证工作单（G1b 我方侧预备，09-03）

**取证通道现状（本轮实测登记）**：Codex 桌面端主窗口在册（`axdump 12432`：AXWindow 1250×793 @191,78），
但不在当前屏 CG on-screen 列表（他 Space/隐藏态），`screencapture -l` 仅剩 137×139 幻影行——
静默截窗通道受 27beta 环境限制（同补记㉔②条款）。取证因此二选一：
**R1 你丢截图**（任一窗口，聊天粘贴即可，我落盘 `~/harness-wt/evidence/codex/`）；
**R2 择时**：你把本对话窗口切到主屏亮着的瞬间，我做一次 `screencapture -l` 只读截窗（不动焦点键鼠）。

**观察窗清单**（截图到达即填「Codex 侧观察」列 → 差距四件套当轮产出）：
| # | 观察窗 | 我方实现锚点 | 若截图显示差距 → 候选原生表达（条件式，取证前不作断言） | 性价比预估 |
|---|---|---|---|---|
| W1 | 主窗全貌（侧栏+会话+composer） | ContentView / SidebarView / ChatAreaView / ChatInputArea | 布局比例/间距→SwiftUI 原生参数调整 | 高（定全局基调） |
| W2 | 折叠 rail 态 | SidebarView.collapsedBody | 顶部避让带（=F6 同题合并）| 高（与 F6 合并裁决） |
| W3 | 设置（入口+全页） | SettingsView / SettingsCompletePage（D-7/8/9 材料） | 左 sidebar+pane（IA 提案已备） | 中（D-7/8/9 待拍） |
| W4 | 标题右键/溢出菜单 | ChatAreaView.sessionMenuActions | 动作集增删（A 层结构恒等保证两入口同步改） | 低 |
| W5 | 新任务/欢迎页 | WelcomeAreaView | hero/chips 结构 | 中 |
| W6 | 会话悬停/生成中态 | SessionListItem / generatingSessionId | 指示器形态 | 中 |
| W7 | 项目/归档管理 | SidebarProjectSections / ArchiveManagerView | 归档面层级 | 低 |
| W8 | 主题/外观设置呈现 | Theme.swift + 主题插件链（D-11 关联） | tint 作用域展示位 | 中（挂 D-11） |

规则重申：取证前本文任何行**不得**写「Codex 有 X」为事实（铁律 5）；截图到达后逐行四件套
（截图路径+我方行号+原生适配表达+性价比评级）入本节续表。旧 F7 对标断言已按铁律 5 降级，
见 `docs/UI_CODEX_ALIGNMENT.md` v8 重判节。
