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
| `NSView.cacheDisplay`（不上屏无边框窗口） | A 层 | **❌ 不渲染玻璃** | 09-05 `tools/qa/glass-capture-channel-probe.swift`：玻璃差异 **0/96000**，控制组 **1291 色**（通路活性自证，非整体捕获失败）|
| `NSView.displayIgnoringOpacity(_:in:)` | A 层 | **❌ 不渲染玻璃** | 同探针：差异 0/96000，控制组 613 色 |
| `CALayer.render(in:)` | A 层 | **❌ 不渲染玻璃** | 同探针：差异 0/96000，控制组 611 色（SwiftUI 内容宿主 layer 路径亦不含玻璃）|
| `dataWithPDF(inside:)` | A 层 | **❌ 不捕获 SwiftUI 内容** | 同探针含**正对照**：不透明色块与无玻璃控制组体积同为 836B（远小于编码渐变+点阵所需）→ 通道本身不产出内容，与玻璃无关 |
| 显示边界外窗口（`setFrameOrigin(-12000,-12000)` + `orderFront`）+ `screencapture -l` | 名义 A 层，**实测不可用** | ❌ 不可用 | 探针内该子进程**无限挂起**（探针已置 `HARNESS_CH5_SCREENSHOT=1` 显式开关，默认关闭）。**归因修正（09-05 自纠）**：曾写作「需屏幕录制授权 TCC」——后续实测 `screencapture -o -x -l<屏上窗>` 在 exec 会话 **rc=0 / 1s / 151KB 正常**，故 TCC 归因撤回（未证实）；现判为**目标窗口在显示边界外 → 等待永不出现的表面**。屏上真实窗口截帧仍可用（本表下方第 4 行不变）|
| `NSApplication`/建窗可用性（前置事实） | — | — | **纠正旧记录**：CLI/脚本进程在本机可创建不上屏 `NSWindow`（不再 SIGTRAP）；09-03「CLI 建窗 SIGTRAP」的真因推测为 `NSApp` 隐式解包未初始化（本轮同类错误精确复现 `EXC_BREAKPOINT` 于 `main`，标注为推测）|
| `CGWindowListCreateImage` | — | **❌ API 已从 macOS 27 SDK 移除** | 编译期报错「'CGWindowListCreateImage' is unavailable in macOS: Please use ScreenCaptureKit instead」 |
| `screencapture -o -x -l<wid>`（进程外只读） | A 层（不动焦点/不 activate） | ✅ 对**已存在的真实窗口**有效 | 本次截到 Harness 窗 3840×2100 真实像素 |
| 同上，对**离屏/其他 Space 窗口** | A 层 | ⚠️ 不可靠 | Codex 主窗（WID 554，在其他 Space）仅截回 274×318 畸变缩略 |
| ScreenCaptureKit | ❌ 需屏幕录制权限（TCC 弹窗=打扰用户） | — | 不采用 |

**结论 1（纠偏 v8 条款）**：v8 目标 G2 写的「用 ImageRenderer 像素帧判定 morph 流体融合」
**判据不成立**（上表第 1 行）。玻璃效果只能靠①结构性静态断言（A 层，能证"接线正确"）
＋②真机目检（用户 1 分钟，或用户认可"结构证据即满足该子句"）双轨核销。
此条不修正就继续执行 = 制造无效证据，故先登记再报告。

**结论 1b（09-05 增补：把 ImageRenderer 的能力边界精确化，并纠 v8 残留的第二处同类条款）**：
上表第 1 行只否证了「**玻璃/材质层**」像素，但 ImageRenderer **本身并未失效**——它对内容层像素有效，
且已有两处**在册正对照**证明其通路活性：`ThemeLiveRenderTests`（主题染色即时生效＋还原后像素逐点复原）
与 `SidebarDropHighlightRenderTests`（拖拽落位高亮）。⇒ 正确表述是能力边界而非全否：

| 取证对象 | A 层 ImageRenderer | 处置 |
|---|---|---|
| 内容层像素：染色/文字/控件态/布局间距/高亮 | **可用**（正对照在册） | before/after 正常走 A 层，铁律 6 直接满足 |
| 玻璃材质层：折射、morph 融合、液颈、blend 提前量 | **不可用**（09-02/09-03 双重否证） | 只能①结构断言（证"接线正确"）＋②真机目检/用户认可结构证据 |

⇒ **v8 残留条款**：G2 的「每轮：四门禁 + **before/after 离屏渲染取证**」未区分改动类型，若该轮是
**材质类**改动则该取证同样做不出来（与 D-1 同因，但 09-02 那次纠偏只覆盖了 morph 判据，漏了这条）。
**执行规则（自本轮生效）**：G2 每轮开工前先给该轮改动**定层**（内容层/材质层），内容层轮必须交
A 层 before/after 像素对；材质层轮改为「结构断言 + 目检（或你认可结构证据即核销）」，**不得**以
"离屏取证"名义提交一张不含玻璃的图充数。

**流程教训（本轮自纠，重要）**：本结论其实 09-02 就登记过（QUALITY ①「已按实测纠偏 §0/§4」），
但那句「故先登记再报告」的**报告**从未发生，纠偏也没有回写进你持有的目标文本 ⇒ 同一矛盾拖到
09-05 被我"重新发现"并当作新问题申报。⇒ 新规则：**纠偏若涉及的入口在用户手中（目标文本/DoD 原文），
必须当场显式上报而不是只改仓内文档**；仓内已纠偏但入口未同步＝债务，不是完成。
> **09-05 补强（同表 CH1–CH5 全普查）**：`cacheDisplay` / `displayIgnoringOpacity` / `CALayer.render` 三条位图通道均**通路活性成立但玻璃差异 0**（控制组 611–1291 色排除整体捕获失败），`dataWithPDF` 连正对照内容都不捕获，`边界外窗口+screencapture` 因 TCC 挂起不可用。**结论：A 层不存在任何可见玻璃的像素通道**——「①结构静态断言 + ②真机静态帧/用户目检」双轨是唯一可核销口径，D-1 选项 (b)「认可 A 层结构证据即满足该子句」的证据基础至此闭合（原 ❓ 未取证项已全部消除）。

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
| A2 | **容器 spacing 是融合提前量的显式调参项**（§1.1 末句 → §17 终裁） | ⚠️ GAP（09-05 精化：仅 2 处成立）| 见 §17.3 逐容器作用域实测——侧栏（多面＋跨态 morph）与设置页（≥2 面异变体共存）用 spacing=nil 未做官方建议的 customize；输入区容器单面 N/A（非 GAP）；Tab 条已显式（F1）|
| A3 | **`.matchedGeometry` 适用场景**（§1.14 原文终裁） | ✅ 达标（09-05） | 文档判据=「**玻璃效果**被加/移出视图层级」；我方 `TileFaceMode.resolve` 使非选中面无玻璃 ⇒ 选择切换即 remove+add，并非"常驻面"（原 ❓ 前提不成立），且原文第三段覆盖 identity 不变情形。真值表测试在册 L40–45 |
| A4 | **玻璃锚定内容 bounds，内容保持锐利**（§1.4） | ✅ 达标 | 08-29 已按官方模式重构（`glassEffect` 直施于内容，弃 `background` 挂法），入册 GlassMorphTabBar L110-119 注释 + 像素直方图证据 |
| A5 | **默认 shape = Capsule**（§1.4）→ 自定义形状须同型才能 union/morph（§1.5） | ✅ 达标 | 统一 `tileShape = RoundedRectangle(10, .continuous)`；union 同变体约束在 SettingsView L159 注释在册 |
| A6 | **材质参数只有 3 变体 + tint + interactive**（§1.6）→ 不存在"曲率/模糊/高光"可调 | ✅ 已知天花板 | 已在 `P1_GLASS_API_VERIFICATION.md` §四登记；残留 GAP：主题 manifest 若仍暴露"曲率/模糊"字段=**假参数**，应显式声明不支持（D-4 相关） |
| A7 | **interactive 语义/默认值**（§1.7→§1.10 原文复核） | ✅ 达标（09-05 表格跟结论） | §1.10 官方原文＝**显式开启非默认自带**；旧注释宣称已撤销并按原文补 `.interactive()`（F2 在册 §9）。**表格此前仍挂 ❓ 与 §1.10 自相矛盾，属表格漂移，非结论未定**。残余仅悬停反馈目检（归 D-2/G3 A-h） |
| A8 | **无障碍降级**（减弱透明度 → 非玻璃表面） | ✅ 达标 | `GlassSurface` 三态 `resolveMode` + 容器 `shouldWrap` 同源门控，测试在册（867 项 xcresult） |

## §3 GAP 汇总与修复方向（性价比排序，全部纯原生 API）

| GAP | 严重度 | 修复方向 | 静默判据（修复后） | 真机目检 |
|---|---|---|---|---|
| **A1 容器内单玻璃面** | **P0（D-1 根因）** | 让未选中 tile 也持玻璃面（同 variant/同型 shape），选中态改用 tint/前景强调区分 → 容器内 6 面共存，融合才有对象 | 纯函数改造后单测断言「native 态下参与 morph 的玻璃面数 == segments.count」 | 需要（切换时是否出现"液体颈"连接） |
| **A2 spacing=nil** | P1 | **范围已精化（§17.3）**：只需给 `SidebarView.swift L97` 与 `SettingsView.swift L160` 两处容器显式 spacing（取值来自集中常量，参照 `MorphTabGeometry.fullGridSpacing` 做法）；`ChatInputArea L135` 容器内单面 → 保持 nil 为正确态，勿改 | **拆两层，勿混判**：① 结构层可 A 层断言（spacing 非 nil ＋ 值来自集中常量）；② 融合提前量合适与否是像素现象，而 §0 已证 A 层无任何玻璃像素通道 ⇒ 只能真机目检，禁止用 ① 冒充 ②（与 D-1 同类边界，见 §17.4）| 需要（融合提前量）|
| A3 常驻面挂 transition | P2 | 按 A1 改造后重估：若改为"所有面常驻"，则 `.matchedGeometry` 可能应移除（文档语义=增删）。**与 §2 A3「✅ 达标」不矛盾**：✅ 指官方语义已终裁正确理解（§1.14 原文＝玻璃效果被增删，我方现态下选中切换确为 remove+add，故现状成立）；本行指 **若** A1 改常态驻玻璃，则该理解结论会反转为「应移除 matchedGeometry」，属 A1 的必做后续，非本项未决 | 结构断言（是否仍挂 transition） | 需要 |
| ~~A7 interactive 口径~~ | ~~P2~~ | **已闭环（09-05 · F2）**：按 §1.10 官方原文撤销「材质自带」未证实宣称，改为显式 `Add`——纯函数 `selectedGlass(from:isSelected:)`（源码 `GlassMorphTabBar.swift` L180–181，调用点 L231）+ `SelectedGlassTests` 3 条在册（`GlassMorphTabBarTests.swift` L119 起）。**本行原「二选一：改注释为未证实或删除宣称」是表格漂移残留，勿再作待办读**（09-05 审计发现：§2 状态列与 §9 已登记修复，唯 §3 GAP 表漏同步） | 已闭环，无判据 | 悬停观感 → 归 D-2 / G3 走查 A-h |
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

### 1.14 `GlassEffectTransition` / `.matchedGeometry` 原文（09-05 实拉文档端点，A3 终裁依据）

页 `tutorials/data/documentation/swiftui/glasseffecttransition`（HTTP 200）abstract 逐字：

> A structure that describes changes to apply when a glass effect is **added or removed from the view hierarchy**.

页 `tutorials/data/documentation/swiftui/glasseffecttransition/matchedgeometry`（HTTP 200）逐字：

> The matched geometry transition allows the geometries of glass shapes during an **appearance or disappearance phase of a transition** to be derived from the geometry of a nearby shape within the glass container.
>
> For example, if a newly appearing shape is within the spacing of any existing shape, it will use that shapes geometry to transition out of.
>
> When using the ~·~, this transition applies additional scale and offset effects to content **when the identity of the shape does not change but its content does**. Opt out of these additional animations by providing a specific animation like ~·~.
>
> （如实注：末段两处 ~·~ 是官方 JSON 中以符号链接呈现、纯文本抓取时为空的位置，**不按猜测补全**。）

**A3 终裁（❓ → ✅）**：文档判据是「**玻璃效果**被加入/移出视图层级」＋「过渡的出现/消失阶段」，
并非"容器视图增删"。我方 `GlassMorphTabBar.TileFaceMode.resolve(isSelected:isNative:)` 第一行即
`guard isSelected else { return .plain }` ⇒ **非选中面完全无玻璃**，故选中切换在视图层级上就是
「旧面玻璃被 remove、新面玻璃被 add」——正落在原文语义内；`.glassEffectID(Self.selectionID, in: morphNS)`
再以同一 ID + 同一 namespace 构成 morph 配对。机制层真值表测试在册（`GlassMorphTabBarTests` L40–45）。
第三条原文另示「identity 不变而内容变化」亦有额外 scale/offset 处理 ⇒ 两种读法均被覆盖，
A3 疑虑（常驻面是否生效）不再成立。

## §12 新审计项（A13–A19，本轮全部来自官方原文＋本机代码事实）

| 项 | 状态 | 证据 / 影响 |
|---|---|---|
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

## §17 容器 spacing 终裁（09-05：SDK 签名 + 官方原文 + 逐容器作用域实测）

> 触发：A2 原表述「容器 spacing 显式化」过于笼统。若不先定「哪些容器真有融合对象」，执行日会退化成给所有容器硬塞参数（含无对象者），反而背离官方语义。本轮先钉事实，再收窄范围。

### 17.1 本机 SDK 权威签名（27 beta，逐字）

```
# Xcode-beta.app/.../MacOSX.sdk/System/Library/Frameworks/
#   SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface:10991
@_Concurrency::MainActor @preconcurrency public struct GlassEffectContainer<Content> : SwiftUICore::View where Content : SwiftUICore::View {
  public init(spacing: CoreFoundation::CGFloat? = nil, @SwiftUICore::ContentBuilder content: () -> Content)
```

- **`spacing` 本身就是 `CGFloat? = nil`** ⇒ 我方 `GlassSurface.swift` L284 传 Optional 合法；`nil` 是 Apple 显式提供的默认值，**不是漏传参数**。
- **类型归属事实（顺带纠正一处潜在误读）**：27 beta 的 `SwiftUI.swiftinterface` 内**搜不到** `GlassEffectContainer`（该 interface 的 glass 命中仅 `GlassButtonStyle` / `GlassProminentButtonStyle` 及对 `SwiftUICore.Glass` 的引用）；玻璃类型族实体在 **SwiftUICore** framework interface 内。今后核 SDK 存在性（§1.13 同类）**必须两个 framework 都查**，只查 SwiftUI 会产生「API 不存在」的假阴性。

### 17.2 官方文档原文（09-05 实拉 `documentation/swiftui/glasseffectcontainer`）

> "Use a container with the `glassEffect(_:in:)` modifier. Each view with a Liquid Glass effect contributes a shape rendered with the effect to a set of shapes. SwiftUI renders the effects together, improving rendering performance and allowing the effects to interact with and **morph into one another**."

> "Configure how shapes interact with one another by customizing the **default spacing value** of the container. As shapes near one another, their paths start to blend into one another. **The higher the spacing, the sooner blending begins** as the shapes approach each other."

- init 页 abstract：`Creates a glass effect container with the provided spacing, extracting glass shapes from the provided content.`；**init 页无逐项参数说明**（`primaryContentSections` 仅 declarations）。
- **官方只给定性描述，未公布 default spacing 的数值** ⇒ 任何「系统默认 spacing = X pt」的写法一律禁止（铁律 1）。
- 官方措辞是「customizing the **default** spacing value」：nil→默认值合法，但**容器内多面时官方建议 customize**。⇒ A2 的正确定性是「**多面容器未做官方建议的调参**」，而非「API 用错」。

### 17.3 逐容器作用域实测（4 个容器调用点，引用链逐行核）

| 容器调用点 | 容器子树内的玻璃面（实测引用链） | spacing | 裁定 |
|---|---|---|---|
| `GlassMorphTabBar.swift` L162 | 运行时**仅 1 面**（`TileFaceMode.resolve` 非选中走 `.plain`；全仓原生 `.glassEffect` 仅 L231） | 显式 `MorphTabGeometry.fullGridSpacing`（F1）✓ | 面数问题属 **A1 根因**，与 spacing 无关 |
| `SidebarView.swift` L97 | 容器包 `Group{ isCollapsed ? collapsedBody : expandedBody }`（L87–97）；`expandedBody`(L125) 内含 L342 面 + `SidebarProjectSections(`(L307 → 该文件 3 面)；`collapsedBody`(L374) 内含 L456 面 ⇒ 展开态 **≥4 面共存且跨态 morph** | **nil** | **A2 成立（P1）**：官方语境里最该 customize 的正是这种多面＋跨态容器 |
| `SettingsView.swift` L160 | 容器包 `HStack{ sidebar, Divider, contentPane }`；sidebar 面 L198(.prominent)；`contentPane`(L203) → `GeneralPreferencesView`(L256) → `ShortcutRow`(L489/490) → 面 L510(.thin) ⇒ **≥2 面异变体共存** | **nil** | **A2 成立（P2 观感）**：异 level 成员共存合法（§六 union 语义），但提前量未调 |
| `ChatInputArea.swift` L135 | 容器内**仅 1 面**（L117 `.regular`，源码注释自证「当前唯一玻璃成员」） | nil | **非 GAP，勿改**：无交互对象，塞参数只会制造误导 |

未计入的两处（防夸大）：`ArchiveManagerView` L78 面位于 `SidebarView` L113 的 **`.sheet{}` 闭包**内 = 独立呈现，不在 L97 容器子树；其余跨文件面同理须按引用链单判，不得按「同文件」粗算。

### 17.4 判据边界（本轮新增，与 D-1 同源，务必先读）

§3-A2 原静默判据是「单测断言 spacing 非 nil ＋ 值来自集中常量」——它只保证**代码形态**，**证明不了融合提前量合适**；提前量是 blend 像素现象，而 §0 五通道普查已证 A 层不存在可捕获玻璃的像素通道。⇒ 判据拆两层：**① 结构层（A 层可断言）＋ ② 观感层（只能真机目检）**，并**禁止用 ① 的通过冒充 ② 的达标**。取值三档实验（6/12/20pt）同属 ② 的目检范围。

> **排查结论（09-05 已逐条核，先说结论：同类混淆只有 2 处，不是全表性缺陷）**：漏点仅 **① v8 目标文本的 D-1 判据**（上一轮已作废重述）**② §3-A2 旧行**（本轮已拆层）。反之，文档主体**早就**写对了这条边界——§13/§14 多处明写「无静默像素通道 ⇒ 只能真机目检」「或认可 A 层编译+测试即核销」的二选一，§3 其余各行（A1/A3/A6）的「静默判据」与「真机目检」两列本就自洽。⇒ 准确表述是：**执行入口层（目标文本＋§3 个别行）与既有文档口径脱节**，修法是让执行入口继承文档口径，而不是宣布整套判据不可信。流程要求保留并生效：**每项 G2 gap 进执行前先做判据体检**（结构可断言？必须目检？），当场拆层写入 §3，不要等到执行日造不出证据。

### 17.5 与其他待决项的耦合

- **D-1 (c) 案**：若 A1 改造让 Tab 条 6 面常驻，spacing 立刻成为决定「何时开始融合」的主参数，且应与侧栏/设置页取值口径统一（集中常量，禁止三处各写魔数）。
- **A12 效果总量/性能护栏**：A1 改造＋侧栏多面常驻会抬高运行时玻璃面数，spacing 越大融合域越宽 ⇒ 实施时须与 A12 口径、RSS/帧率护栏**同批复测**。

## §18 本机 SDK `.swiftdoc` 官方全文通道 ＋ 玻璃 API 原文全录与 D-1 根因重估（09-05，全程静默 A 层）

### 18.1 新证据通道（此前多轮漏用）＋ 入仓提取工具

Xcode 附带的 `.swiftdoc` 里含 Apple 为每个公开符号写的 **DocC 文档正文与官方示例代码原文**，
比在线文档更贴合本机 SDK，且零网络、零前台、锁屏可跑（静默铁律 A 层）。
本轮把提取动作固化为工具：`tools/qa/swiftdoc-extract.py`（已入仓，实测可用）。

```bash
# 只列命中偏移（复现本节引用位置）
tools/qa/swiftdoc-extract.py --offsets-only "A view that combines multiple glass shapes"
# 输出该处官方正文（含示例代码）
tools/qa/swiftdoc-extract.py --window 2600 "A view that combines multiple glass shapes"
# 指定 SDK（默认优先 xcrun 解析到的 SDK＝门禁实际编译用的那一个）
tools/qa/swiftdoc-extract.py --sdk /Applications/Xcode-beta.app/Contents/Developer/Platforms/\
MacOSX.platform/Developer/SDKs/MacOSX27.sdk --offsets-only "GlassEffectContainer(spacing: 10.0)"
```

**顺带钉住一条此前无人写明的环境事实（对铁律 1 很关键）**：
`xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`，
`xcrun --sdk macosx --show-sdk-path` → **MacOSX26.5.sdk** ⇒ **门禁与 `swift build` 的编译期 SDK 是 26.5**；
而 §17.1 的签名引文取自 **Xcode-beta 的 MacOSX27.sdk**，运行时 OS 才是 27 beta。
⇒ 三者要分开记：**编译期 SDK＝26.5／运行时 OS＝27 beta／在线文档＝可能已漂移**。
两 SDK 对该 API 的核对结果（本轮实测）：

| 项 | MacOSX26.5.sdk（=编译期） | MacOSX27.sdk（Xcode-beta） |
|---|---|---|
| `GlassEffectContainer.init` | `init(spacing: CoreFoundation.CGFloat? = nil, @SwiftUICore.ViewBuilder content:)` | 同语义；渲染为 `@SwiftUICore::ContentBuilder`（模块限定名写法不同） |
| 容器文档正文（39 行 `///`） | 与 27 **逐字一致**（`diff` 空，`TEXT-IDENTICAL-BOTH-SDK`） | 同左 |
| 文档 byte offset（**短语起点**，工具实测） | `A view that combines…`＝**1,556,068**／`the sooner blending begins…`＝**1,557,026**／`GlassEffectContainer(spacing: 10.0)`＝**350,596** | **1,605,077**／**1,606,035**／**367,456** |
| `.swiftdoc` 大小 | 1,771,624 B | 1,826,328 B（2026-05-30 mtime） |

⇒ 结论：**引用正文对两个 SDK 同时成立**，但 **offset 是 per-SDK 的**，故今后引用一律「正文逐字＋工具命令」，
raw offset 只作辅助；**且 offset 必须是「短语起点」**（本节统一用 27 SDK 的短语起点，由 `swiftdoc-extract.py --offsets-only` 量得）。
【09-05 自纠】本节初稿曾写 1,605,149——那是同句内 `morph` 一词的位置（早期检索脚本按词打的点），**不是短语起点**，正确值 1,605,077；教训：offset 只能现量现用，禁止从别的检索结果借数。
文件路径：`<SDK>/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftdoc`。

⚠️ 铁律 1 查证顺序据此固定为**三通道**：① 编译期 SDK 的 `.swiftinterface` 签名 → ② 同 SDK `.swiftdoc` 全文（含官方示例）→ ③ 在线文档。
（27 beta 玻璃实体仍在 **SwiftUICore**，`SwiftUI.swiftinterface` 内搜不到 ⇒ 两个 framework 都要查，否则假阴性。）

**⁽⁰⁹⁻⁰⁵ᵉ⁾ 三通道各有覆盖面，任一单通道的阴性都不构成「官方不存在 X」（§18.5 误判的直接产物）**：

| 通道 | 承载内容 | **不承载**（→ 假阴性来源） |
|---|---|---|
| ① `.swiftinterface` 签名 | 声明/可用性/默认参数 | 任何解释性文字、判据、示例 |
| ② `.swiftdoc` 全文 | **API 符号级** DocC 正文＋官方示例代码 | **教程文章**（如《Applying Liquid Glass to custom views》）、HGI/HIG 正文、WWDC 逐字稿 |
| ③ 在线 JSON（`developer.apple.com/tutorials/data/documentation/<path>.json`；HIG 走 `/design/human-interface-guidelines/<slug>`） | 教程文章、HIG、示例说明文字（本文 §1 全部引文来源） | 本机 SDK 差异（可能已相对 26.5/27 漂移） |
| ④ WWDC 逐字稿（视频页 HTML 内嵌 `<span data-start>`，§11） | 设计意图与口径 | 逐字稿是**叙述**，不可当 API 判据 |

⇒ **新固化规则（铁律 1 的操作细则）**：断言「官方**存在** X」= 任一通道逐字命中即可；
断言「官方**不存在** X」= ①全仓检索我方已入册引文（同篇官方文章可能被不同批次分节摘过）＋ ②③两通道皆阴性，二者缺一即不得下负结论。
本轮就是拿通道②的阴性去否证 §1.8 已入册的通道③引文，方向完全反了（详见 §18.5 更正）。

### 18.2 官方原文逐字（offset 取自 Xcode-beta MacOSX27.sdk，正文已实测与 26.5 逐字一致）

> 引文精度声明：`.swiftdoc` 内官方正文是**每行 ≤80 字符硬换行**存储的，本节为便于阅读按行合并成整句——**未改词、未改标点、未增删内容**；如需原始逐行形态，用 §18.1 命令去掉合并即可看到（`grep -F "///"` 输出）。

- **`GlassEffectContainer` 类型文档（offset 1,605,077）**：
  > "A view that combines multiple glass shapes into a single shape that can morph individual shapes into one another."
  > "You use a glass effect container with the `View/glassEffect(_:in)` modifier. Each view with a glass effect contributes a shape rendered with the physical glass material to a set of shapes. SwiftUI renders the glass effects together, improving rendering performance and allowing the effects to interact with and morph into one another."
  > "**Configure how the glass shapes interact with one another by customizing the default spacing value provided to the container.** As shapes near one another, their paths start to blend into one another. The higher the spacing, the sooner blending begins as glass approaches each other."
  > "In the example below, the two shapes render as if they are a single continuous shape as their geometries overlaps."
- **`GlassEffectContainer.init(spacing:content:)` 文档（offset 790,352）**：
  > "Creates a glass effect container with the provided spacing, extracting glass shapes from the provided content."
- **`glassEffectID(_:in:)`（offset 399,207）**：
  > "Associates an identity value to glass effects defined within this view. … When used together, **SwiftUI will use the provided identifier to animate shapes to and from each other during transitions.**"
- **同文档另一处（offset 403,233）**：
  > "You can combine glass effects by using a `GlassEffectContainer`, which supports morphing glass shapes into each other **based on the geometry of their associated views**."
- **`glassEffectTransition(_:)`（文档头 offset 366,575；示例内 `spacing: 10.0` 在 367,456）官方示例——逐字**：
  > "Associates a glass effect transition with any glass effects defined within this view. … In the example below, **the notepad image will transition into and out of the pencil image when the `isExpanded` variable changes.**"

```swift
// Apple 官方示例（逐字，出处 offset 366,575 起，示例容器 spacing 在 367,456）
private var namespace: Namespace.ID
var isExpanded: Bool
var body: some View {
    GlassEffectContainer(spacing: 10.0) {
        HStack(spacing: 10.0) {
            Image(systemName: "pencil")
                .frame(width: 20.0, height: 20.0)
                .glassEffect()
                .glassEffectID("pencil", in: namespace)

            if isExpanded {
                Image(systemName: "note")
                    .frame(width: 20.0, height: 20.0)
                    .glassEffect()
                    .glassEffectID("note", in: namespace)
                    .glassEffectTransition(.matchedGeometry)
            }
        }
    }
}
```

**由此得三条可核事实（不含推断）**：
- F-a 官方示例的 morph 配对形态是「**一个常驻面（pencil）＋一个条件增删面（note，带 `.matchedGeometry`）**」，且两面 **ID 不同**；
  与我方现状（唯一面随选中态跨 tile 迁移、同 ID）不是同一形态。
- F-b 官方对 spacing 的表述只有「越大越早 blend」＋示例值 `10.0`（且示例里**容器 spacing == 内部布局 spacing**）；
  仍**未公布默认值数值** ⇒ §17 的「禁写默认 = X pt」不变，但现在**有可引用的官方示例值与 1:1 比例先例**。
- F-c 官方对 morph 触发条件的表述是「based on the **geometry** of their associated views」＋身份用于
  「animate shapes **to and from each other**」⇒ 配对需要容器在同一事务里同时认得两端；官方**未写明**
  「同 ID 跨子树 remove+insert 是否仍能配对」——此点属官方空白，只能实测。

### 18.3 我方现状数值对算（A 层静态推导，非像素实测）

| 量 | 我方值 | 出处 |
|---|---|---|
| 网格 | 3 列 × `LazyVGrid`，列/行间距 6 pt | `GlassMorphTabBar.swift` L126–128、L154 |
| tile | 高 46 pt，宽上界 80 pt（实侧 ≤76） | L36–40 |
| 容器 spacing（native 态） | `MorphTabGeometry.fullGridSpacing` = `containerSpacing()` = 最坏最近边距离上取整 ≈ **179 pt** | L48–80、L162 |
| 相邻面净距 | 6 pt（网格间距） | L42 |
| 官方示例对照 | 容器 10.0 / 布局 10.0（**1:1**） | §18.2 |

**推导（标注为推导，非实测）**：我方容器 spacing 约为相邻净距的 **30 倍**，按官方「越大越早 blend」，
若配对成立，6 pt 相距的两面应「极早」融合——而实机在册观感是**淡变**（P1 注记①）。
⇒ **spacing 提前量大概率不是瓶颈，瓶颈在「配对两端未被同时认得」**（F-a/F-c）。
这**推翻了我本轮先前设想的「A2-first 便宜修法」**：显式 spacing 已存在且极为宽松，调它不构成对根因的动作。
A2 仍按原口径只对 `SidebarView` L97／`SettingsView` L160 两处未 customize 成立，与 morph 根因不同题。

### 18.4 由 F-a/F-c 得出的三架构案（补进 D-1 菜单，性价比自低到高）

| 案 | 做法 | 改动量 | 官方贴合度 | 是否连带 D-11 |
|---|---|---|---|---|
| **Ⅰ（新·最低成本，Apple 示例原型）** | 常驻一个底面（tab 条整体或首格）＋现有选中条件面（`.matchedGeometry` 保留），二者 ID 不同 | 最小（+1 个常驻玻璃面） | 与 §18.2 官方示例同形态 | 底面若抢视觉则需 tint 弱化 |
| **Ⅱ** | 选中面提为**单一常驻面**，位置随选中 tile 移动（identity 恒存，morph 由几何变化驱动） | 中（面从 tile 内提到独立层＋位移动画） | 贴合「geometry 驱动」表述 | 不需要（面本身即选中指示） |
| **Ⅲ（＝原 D-1 推荐 (c)）** | 6 面常驻，选中改 tint/前景区分 | 最大（材质常驻×6＋tint 体系＋性能护栏复测） | 贴合「多面共存」容器语义 | **必须** |

- 三案的 A 层可断言部分相同（结构断言：常驻面数/ID 关系/容器归属），**观感仍各自需 1 次目检**（§0 结论 1b 材质层边界不变）。
- 建议次序：Ⅰ → 不行再 Ⅱ → 仍不行才 Ⅲ（每步四门禁＋入册，一次只动一处）。

### 18.5 顺带纠出一处过度归属（登记，随下轮 `.swift` 改动合并修，避免为注释单跑门禁）

`GlassMorphTabBar.swift` 两处注释把「最近边 ≤ 容器 spacing」写成**官方条件**：
- L60 附近：`/// 容器 spacing = 最坏最近边距离向上取整（官方条件为「≤」，取整即覆盖全部切换距离）`
- L88 附近：`/// 判定：某对面距离是否落在 matchedGeometry 适用域（官方：最近边 ≤ 容器 spacing）`

本轮 §18.2 全量提取后确认：官方原文只有「越大越早 blend」，**不存在**「≤ 即适用 matchedGeometry」这一判据表述。
⇒ 该 `≤` 模型是**我方保守启发式**，注释应改为「我方启发式模型（非官方判据）」；`qualifiesForMatchedGeometry` 的行为不必改（保守无害），
但**不得再以「官方」名义引用**。属铁律 1 类过度归属，登记为 G2 首轮 `.swift` 批次的附带项（含 `MorphTabGeometry` 注释与同名测试用例名复核）。

**⁽⁰⁹⁻⁰⁵ᵉ⁾ 本条结论被本轮推翻——我方才是一次误判，代码注释维持「官方」名义为正确（铁律 1 反向自纠）**
本轮按 §18.5 去改注释前的最后一道核验（在线教程文章 JSON 通道实取）证明：**官方确有该判据句**。原文逐字：
> “This morphs the eraser image into the pencil image when the eraser’s nearest edge is less than or equal to the container’s spacing.”

复现（A 层，纯 curl，与键鼠无关）：
```bash
curl -sS "https://developer.apple.com/tutorials/data/documentation/swiftui/applying-liquid-glass-to-custom-views.json" \
  | python3 -c "import json,sys; t=json.dumps(json.load(sys.stdin),ensure_ascii=False); print(t.count('nearest edge'), t.count('less than or equal'))"
# 实测输出：1 1（09-05 命中）
```
**误判成因（这是本轮真正的教训）**：`.swiftdoc` 只承载**API 符号级**注释，**不覆盖教程文章与 HGI/HIG 正文**；
我拿单一通道的阴性结果去断言「官方无此表述」，且**未回检本文档 §1.8 早在 09-03 就已逐字入册的同篇引文**（同篇官方文章被两批通道各摘一次，内部一致性检查缺失）。
⇒ **固化新规则**：断言「官方不存在 X」之前必须同时满足 ① **全仓检索我方文档已入册引文**（`grep` §1 各节，含同篇不同小节）；
② **≥2 通道皆阴性**（在线教程/HIG JSON **且** `.swiftdoc`）。这与 §0「负结论须自证捕获通路活性」同族，此处形态是**负结论须自证检索覆盖面**。

**仍成立的合理内核（G2 首轮 `.swift` 附带项据此缩小）**：`GlassMorphTabBar.swift` L60 后半句「取整即覆盖全部切换距离」是**我方推论**（官方只给判据方向，未给「取整即覆盖」的保证）⇒ 该半句应标「我方保守取整」；
L32/L88/L160 以「官方」名义引用**正确，保留**；`MorphTabGeometry` 注释与同名测试用例名复核照旧。

## §19 morph 配对身份与 spacing 的双通道复核：三句缺录原文 ＋ 对 D-1/A2 的决策增益（09-05，A 层 curl＋读源码）

> 触发点：§18.5 误判自纠后，按新细则把同一篇官方文章（通道③）与 `.swiftdoc`（通道②）合读一遍，
> 发现三句与我方 D-1/A2 直接相关的原文**从未入 §1 逐字表**（其中一句其实早已写进 `GlassMorphTabBar.swift` L24 注释，属**文档缺录**而非认知缺失）。

### 19.1 逐字补录（通道③，`applying-liquid-glass-to-custom-views.json`，副本存 `~/harness-wt/evidence/apple/`）

1. spacing 与混合早晚（§1.8 已录同句的另一半，此处补全）：
   > "The larger the spacing value on the container, the sooner the Liquid Glass effects behind views blend together and merge the shapes during a transition."
2. **静止态告警（此前全仓缺录）**：
   > "A spacing value on the container that’s larger than the spacing of an interior HStack, VStack, or other layout container causes Liquid Glass effects to **blend together at rest** because the views are too close to each other."
3. **morph 的身份前提（此前全仓缺录，对 D-1 三案都关键）**：
   > "Associate each Liquid Glass effect with a unique identifier within a namespace that the … property wrapper provides. **These IDs ensure SwiftUI animates the same shapes correctly when a shape appears or disappears due to view hierarchy changes.**"
   > "This combines all effects with a **similar shape, Liquid Glass effect, and ID** into a single shape…"（union 三同条件）

⚠️ **通道③的取证注意项（新坑，已复现）**：该 JSON 的正文里**符号名以 topic 链接形式存在、纯文本位置为空**
（实测：句子读起来像 "the default transition type is ."），须回查 `references` 表还原符号。本页相关符号：
`GlassEffectContainer`／`GlassEffectTransition`／`matchedGeometry`／`materialize`／`glassEffectID(_:in:)`／`glassEffectUnion(id:namespace:)`／`Namespace`。
⇒ 从通道③摘句若不看 references，可能摘出「缺主语的假原文」。

### 19.2 我方实数对算（源码常量现取，非引用旧表）

| 量 | 值 | 来源 |
|---|---|---|
| tab 内部布局间距 | **6**（`LazyVGrid(spacing: 6)` ＋ 3 个 `GridItem(.flexible(), spacing: 6)`） | `GlassMorphTabBar.swift` L126–128／L154 |
| 容器 spacing（现值） | **179** ＝ ⌈√(178²＋6²)⌉，178＝6×3＋80×2（跨 2 列最坏最近边上界） | L38–44 常量＋`worstNearestEdgeDistance` 复算，与 §18.3 在册值吻合 |
| 已备的收敛值 | **52** ＝ `adjacentSpacing()` ＝ max(tileHeight 46, 6)＋6 | L80–86 |
| 倍数 | 现值 179/6 ＝ **29.8×**；收敛值 52/6 ＝ **8.7×** | 现算 |

⇒ 按补录句 2：容器 spacing 只需大于内部布局间距即触发 at-rest 融合，我方现值是其 **29.8 倍**，
**静止态过度融合是官方口径下的必然结果**，而非偶然风险；注释 L24 表明我方是**知情选择**（为覆盖最远切换距离而一次性支付该代价），故这不是缺陷漏看，而是**代价与收益被同一个数绑死了**。
⚠️ 官方未给「多少倍以内安全」的量化阈值 ⇒ 以上只到定性，观感仍需目检（§0 无玻璃像素通道）。

### 19.3 决策增益（三处，均可指向 D-1／A2 的拍板）

1. **句 1＋句 2 合读推翻了一个隐含假设**：matchedGeometry 只要求「**实际配对的两面**最近边 ≤ spacing」，
   而 at-rest 融合判的是「**容器 spacing vs 内部布局间距**」⇒ 两者**不必共用一个数**。
   我方 `fullGridSpacing` 用「网格内最坏距离」给 morph 兜底，顺带把静止态融合代价也一并拉满。
2. **新增一条此前未进菜单的低成本合规路径（远距对显式 `.materialize`）**：官方原话就是
   "farther from each other than the container’s assigned spacing" 时**应当**用 materialize ⇒
   「收敛 spacing 到相邻量级 ＋ 给远距切换显式声明 `.materialize`」是官方推荐的配对表达，
   改动面仅为 spacing 取值＋一个 transition 修饰符，**远小于三架构案**。
3. **D-1 三案的性价比需据此重排**：Ⅰ 案（常驻底面＋条件面）除「贴近官方示例形态」外，
   现在多一条**独立优点**——配对距离恒为相邻量级，spacing 可收敛到 52 一侧，
   同时消掉 A2 的 at-rest 过度融合；Ⅲ 案（六面常驻）在 179 下静止态必糊，与 D-11 同裁的必要性**上升**。
   ⇒ 推荐次序维持「Ⅰ → Ⅱ → Ⅲ」，但**先做 2 的 A2-fix 已不必等 D-1 拍板**（见下条）。
4. **A2 改判（口径修正，非反复）**：A2 此前被标为「D-1 的便宜路径（已作废）」——作废理由（提前量大概率非瓶颈）仍然成立；
   但据补录句 2，**收敛 spacing 的收益与 morph 成败解耦**：它修的是官方点名的「at-rest 过度融合」这一独立合规项。
   ⇒ A2 从「D-1 附属」升为**与 D-1 解耦的独立待批项**，取值建议 52 一侧（`adjacentSpacing`），
   代价＝远距切换按官方口径转 `.materialize`（不再追求远距离 morph）。**仍待你拍板，Agent 不代裁。**

## §20 「官方不存在 X」的强制检索门 ＋ 本轮固化的三件台账工具（09-05，全程静默）

§18.5 误判的机制性根因不是“知识不够”，而是**没有一道检索门**：引文分散在本文多个小节、另一份核验档、以及代码注释里，
新批次只查了新通道就下负结论。治法是把检索变成**有退出码的命令**，而不是靠自觉。

### 20.1 三件工具（同轮入仓，均实测过失败路径退出码）

| 工具 | 用途 | 退出码 |
|---|---|---|
| `tools/qa/md-table-lint.py` | 全仓 md 表格列数一致性（转义感知） | 0＝一致／1＝存在错位 |
| `tools/qa/decision-pending.sh` | 待拍板计数的**唯一口径**（本仓曾两次手抄错数） | 恒 0（查询用） |
| `tools/qa/apple-quote-index.sh` | 官方引文反向索引 ＋ 负结论前置检索门 | 列表 0；`--query` 命中 0／未命中 1；缺参 2 |

### 20.2 想写「官方没有这句话／不是官方判据」之前，按序跑完四步（缺一不得下负结论）

```bash
# ① 我方文档是否早已入册过（同篇官方文章常被不同批次分节摘走）
tools/qa/apple-quote-index.sh --query "<关键短语>"        # rc=1 才继续
# ② 代码注释里是否已有（本文与注释会脱节：at-rest 告警早写在 GlassMorphTabBar.swift L24，本文却缺录）
grep -rn "<关键短语>" Apps Packages 2>/dev/null
# ③ 编译期 SDK 的 .swiftdoc（只含 API 符号级正文＋示例，不含教程文章/HIG）
tools/qa/swiftdoc-extract.py --offsets-only "<关键短语>"
# ④ 在线教程/HIG JSON（本仓 §1 全部引文的真正来源）
curl -sS "https://developer.apple.com/tutorials/data/documentation/<path>.json" | grep -c "<关键短语>"
```
②③④**皆 0** 才可写「官方无此表述」，且须在文档里注明四个命令与各自输出（可复现）。
反方向不需要这道门：任一通道逐字命中即可写「官方有此句」。

### 20.3 现算的引文分布（`tools/qa/apple-quote-index.sh` 输出末行）

已入册官方引文 **29 条**，分布：§1.8 4／§1.9 3／§1.10 1／§1.11 3／§1.12 4／§17.2 2／§18.2 8／§19.1 4。
⇒ 一句话提醒：**同一篇文章的引文可能同时存在于 §1.8 与 §19.1 两处**，检索必须以工具为准，别按小节回忆。
