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
> **⁽⁰⁹⁻⁰⁶ᵉ⁾ 一条环境前提被本机实测修正：`screencapture -o -x -l<windowID>` 在锁屏下同样可取真实窗帧**
> （上方表格与本仓多处沿用的「27 beta 窗帧仅解锁有效」，至少对 **`-l<windowID>` 这条通道不成立**）。
> 实测四数据点（`lockprobe2` 先报 `ScreenIsLocked: 1`）：① 目标窗 `WID=17269` ⇒ rc=0、2498×1586；
> ② 同法取另一 App 窗 ⇒ 274×266、唯一色 1465/标准差 54.6，与目标窗（唯一色 244/标准差 15.8）**明显不同**；
> ③ 两窗逐像素平均绝对差 **52.2** ⇒ 不是同一张底图／桌面壁纸；④ 不存在的 WID ⇒ `could not create image from window` rc=1（诚实失败，不产出空图）。
> ⇒ **轴2（Codex 界面取证）从此可在锁屏态纯 A 层进行**，不再需要等用户解锁或择时。
> ⚠️ **本条只覆盖 `-l<windowID>`**：全屏／区域截图是否同样可用**本轮未实测**，不得据此外推「锁屏下一切截图可用」（阴性口径见 `tools/qa/apple-quote-index.sh` 的提示行）。
> **取证 SOP（三步，缺一不算取证）**：`tools/r1walk/bin/lockprobe2` 记录锁态 → `tools/r1walk/bin/wl` 只读枚举取 WID
> → `screencapture -o -x -l<WID>`；**截后必须做「内容活性自证」**（唯一色数＋标准差＋与另一窗口对比），
> 否则「截到了」可能是一张空图——与 09-05 位图通道「通路活性自证」同一条原则（同一原则第二次救场，已升为通用规范，见 QUALITY ㊷）。

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
| A6 | **材质参数只有 3 变体 + tint + interactive**（§1.6）→ 不存在"曲率/模糊/高光"可调 | ✅ 已知天花板，**假参数风险已于 08-29 `17e9f22` 诚实闭环**⁽⁰⁹⁻⁰⁵ᶠ⁾ | `P1_GLASS_API_VERIFICATION.md` §四登记 ＋ 代码实据：`ThemeSpec.blurIntensity/highlightIntensity` 为**预留提示字段**（渲染层零消费），`ThemePackageImporter.validate` 对两字段做 0…1 有限值校验（nil 合法，1.5/−0.1/NaN 拒绝，错误携带字段名），MCP 主题路径同口径校验且**非法 spec 直接回落系统基准不半生效**，设置页 `glassParamRow` 明示「已声明（0.80/0.60）· 原生 API 无数值参数，渲染由平台托管」（`FileThemePackage.swift:137-142`／`SettingsView.swift:389,395,412`，测试 `FileThemePackageTests.swift:121-136` ＋ MCP e2e 在册）。**本行原「残留 GAP＝若仍暴露则应显式声明不支持」属表格漂移残留，勿再作待办读**；仍开放的是 D-4 的取舍（保留声明 vs 直接拒绝），非缺陷。 |
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
  ↳ **09-05 补反向原文（§23）**：API 页 `accessibilityReduceTransparency` 的 Discussion 是**给开发者的指令**——"UI (mainly window) backgrounds should **not be semi-transparent; they should be opaque.**" ⇒ 我方 solid 与这条明文同向；WWDC 那句描述的是**系统自家玻璃**的观感，两者不是同一层的口径，故 A14 的正确问法是「要不要为观感放弃 API 明文指令」而非「我方是否违规」。
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

**⁽⁰⁹⁻⁰⁶ᶜ⁾ 上述两处 `~·~` 空位由本机 SDK 通道补全（09-05 当时明示「不按猜测补全」，今日有权威离线来源）**：本机归档 `SwiftUICore-26.5-arm64e-apple-macos.swiftdoc` 同一文档正文完整，逐字如下（`.swiftdoc` 通道，offset＝短语起点）：

> "Returns the matched geometry glass effect transition."〔offset 685,122〕
> "The matched geometry transition allows the geometries of glass shapes during an appearance or disappearance phase of a transition to be derived from the geometry of a nearby shape within the glass container."〔offset 685,269〕
> "For example, if a newly appearing shape is within the spacing of any existing shape, it will use that shapes geometry to transition out of."〔offset 685,537〕
> "When using the `Animation/default`, this transition applies additional scale and offset effects to content when the identity of the shape does not change but its content does. Opt out of these additional animations by providing a specific animation like `Animation/spring`."〔offset 685,725〕

**offset 口径注记（本轮实测，防后人误抄）**：本节 offset 采 `tools/qa/quote-verify.py` 的台账口径＝其「正文投影→原始字节」映射的回落值；同一短语在 26.5 语料里用 `python str.find` 直取字节位会得到 659,893／660,040／660,321／660,496，**与台账口径恒差 25,229**（跨硬换行的三条差 25,216），且该句在 27 语料另有位置（`str.find`＝684,647）⇒ **两套口径不可互抄**，以核验器实测为准（本文件其余 41 条 `.swiftdoc` 引文同此口径）。（逐字声明：官方此处 `that shapes geometry` **无撇号**，照录不补；`Animation/default`／`Animation/spring` 在 `.swiftdoc` 内为 DocC 链接标记 `\`\`Animation/default\`\``，本节按本文件既有风格写单反引号，非改词。**两条通道措辞一致性**：在线通道（§1.14 上引）与本机 `.swiftdoc` 除硬换行外逐字相同 ⇒ 空位补全不改变任何已核结论的文本。）

**⚠️ 据补全后的原文，A3 终裁的推论强度需下调一格（改判据不改结论主体）**：A3 主判据**仍成立且不依赖该句**——官方判据是「玻璃效果被加入/移出视图层级」＋「appearance or disappearance phase」，我方 `TileFaceMode.resolve` 非选中即 `.plain`（完全无玻璃）⇒ 选中切换在层级上确为「旧面 remove、新面 add」，落在原文语义内。但上文那句「identity 不变而内容变化 ⇒ 有额外 scale/offset」带一个在册时**丢失的前提**：**「When using the `Animation/default`」**。我方 morph 事务用的是 `withAnimation(.smooth(duration: 0.3))`（`GlassMorphTabBar.swift:196`），**不在该句适用域内** ⇒ 因此「**两种读法均被覆盖**」这句**过头了**，正确表述是：**读法一（appearance/disappearance）有官方文本支撑；读法二（identity 不变内容变）的前提在我方不成立，既不能作为「我方也生效」的依据，也不能反过来当作「我方被官方排除」的依据**（官方对「同 ID 且 identity 不变」情形下 matchedGeometry 会否几何派生**未作声明**，不得下负结论）。
**可执行副产物（不改代码，仅登记为待裁实验）**：官方明文给出一个开关——「给具体动画可 opt out 这些额外动画」。⇒ 建议在 D-1 三架构案**之前**先跑一个更便宜的最小实验矩阵：**变量①`glassEffectID` 策略**（现状 `static let selectionID`＝全 tile 共用一枚，`:141`）／**变量②morph 事务动画**（`.smooth` vs `.default` vs `.spring`）。⚠️ 但 A 层无玻璃像素通道（§0 在册实测），**观感判定必须由你目检**，Agent 不得自动截玻璃帧下结论。

## §12 新审计项（A13–A19，本轮全部来自官方原文＋本机代码事实）

| 项 | 状态 | 证据 / 影响 |
|---|---|---|
| **A13 装饰性全局 tint** | ⚠️ **冲突（需裁决）**⁽⁰⁹⁻⁰⁵ᶠ⁾ 出处已核：引文真实但**不在 HIG Materials 页**——"But **use them selectively**. When items or elements serve a **distinct functional purpose**, you can tint them" ＋ "If you want to imbue color into your app, **do it in the content layer instead**." ＝ WWDC25 Session 219 逐字稿（本轮归档 `wwdc2025-219.0905.html`，整句命中；HIG Materials 页 `tint`/`selectively` 均 **0 命中** ⇒ 拿错页面就会误判「官方无此表述」，属 §18.5 同族地理条件） | 我方 P1.4 把主题 `glassTintHex` 铺到**所有**玻璃面（纯装饰性全局染色）→ 与官方口径冲突，且影响"主题插件"卖点定义（主题该染什么） ⁽⁰⁹⁻⁰⁶ᵉ⁾｜**09-06 基数精确化（给 D-11 一个准确分母）**：按「类型名 ∪ 小写方法名」双模式重搜，`glassSurface(`/`glassEffect(` 共 **17 处**，其中 `Styles/HarnessTheme.swift` 内 4 处是便捷 helper 定义（L102/169/173/177）⇒ **真实视图落点 13 处**；档位分布 regular 8／thin 4／prominent 3／`GlassMorphTabBar.swift:242` 直用 `glassEffect` 1 处（含 helper 计）。统一解析入口 `GlassSurface.resolvedGlass(explicitTint:themeTintHex:themeMaterial:)`（L142）对所有走 `.glassSurface` 的面生效：材质档位取主题 manifest、tint 优先级「显式 > 主题 > 无」⇒ **「所有玻璃面」＝这 13 处，且不含顶栏/Toast**（见 D-19，二者用 `.ultraThinMaterial` 绕过体系）。故本项冲突面精确为 13，D-11 裁「tint 作用域」时按此分母权衡。 |
| **A14 减弱透明度语义** | ⚠️ 需裁决（**09-05 改判口径：两条官方原文并列**，不再是「我方无明文」单边） | 原文①（观感描述，WWDC25-219 逐字，本轮已归档并整句复核）："Reduced Transparency, makes Liquid Glass **frostier and obscures more of the content** behind it."；原文②（**对开发者的指令**，本机在线 API 页 `environmentvalues/accessibilityreducetransparency` Discussion 逐字，此前全仓缺录）："If this property’s value is true, UI (mainly window) backgrounds should **not be semi-transparent; they should be opaque.**" ⇒ 我方 reduceTransparency → **solid 不透明**＝与原文②同向；「frosted 中间态」＝向原文①的系统自家观感靠。二选一仍由你裁，但**保 solid 一侧现已有 API 级明文支持** ⁽⁰⁹⁻⁰⁵ᶠ⁾ |
| **A15 玻璃折射源缺失** | ◐ **09-06 实测改判：根因链第一条已被 D-10(a) 修掉，残余仅在观感面** ⁽⁰⁹⁻⁰⁶ᵃ⁾〔历史判定：❌根因级＋下列代码事实链，其中两条已失真，见更正〕 | **① 更正·窗底（原列第一条根因，实测已反转）**：在册文字称 `HarnessApp.swift:136` `window.backgroundColor = NSColor.windowBackgroundColor`（不透明窗底）——当前 HEAD 实测 `HarnessApp.swift:125-128` `applyGlassSampling(to:)` 置 `window.isOpaque=false` + `backgroundColor = .clear`，调用点 `makeWindow()` L147（启动与重建共用），即 **D-10(a) 已把「玻璃无窗后采样源」这条根因消除**；判别性单测在册（`WindowGlassSamplingTests`：装配前 `isOpaque=true`/alpha>0 → 装配后 `false`/alpha==0）。**② 行号漂移（原文两处已失效）**：`GlassSurface.swift:224/229` 现为 **L234/L239**（L224 现属「防御分支」），文件实际路径也已迁至 `Sources/Styles/`；`HarnessTheme.swift:8` 的 `bgPrimary = Color(NSColor.windowBackgroundColor)` 现为 **L7**，属**内容层**底色而非窗底，是否遮挡玻璃需单独审（未审，不在此下结论）。**③ 仍成立**：`ContentView.swift:11` `HStack(spacing: 0)` 侧栏与内容**并排**（非「侧栏浮于内容之上」）⇒ 官方「sidebar floats above your content / refracting against the sidebar」的形态前提仍未满足。**④ native 路径事实**：`GlassSurface.swift:198` `content.glassEffect(glass, in: shape)` 为唯一原生玻璃落点；`VisualEffectMaterial(blendingMode: .behindWindow)` 仅存在于 `.legacy`（macOS 15–25 降级）与防御分支 ⇒ 基线 Tahoe 常态下不走它，在册「legacy 采样能力反而强于原生态路径」**已不构成常态事实**（窗底透明后二者均有采样源）。**⑤ 判定边界**：本项残余（并排布局是否致观感扁平）按 §0 通道表**无 A 层像素证据可取**⇒ 归 G3 目检，且需与 D-1 三架构案一并裁（折射源与 morph 配对互为前提），本轮不改代码。 |
| **A16 滚动边缘效果** | ✅ 已审·结构性 N/A（§15） | 侧栏会话列表/消息滚动进入玻璃下方时是否有 dissolve 效果；`scrollEdgeEffectStyle` 本 SDK 可用（§1.13），我们未使用 |
| **A17 静止态内容交叠** | ◐ **09-06 结构侧审毕：静态无交叠；运行时项归 G3 目检** ⁽⁰⁹⁻⁰⁶ᶜ⁾ | **结构事实（实测）**：`ChatAreaView.swift:11` 根容器是 `VStack(spacing: 0)`，自上而下**顺序排布**——顶栏 `ChatTopBar`（L14）→ 消息区 `MessageScrollView`/`EmptyChatPrompt`（L18-26）→ 输入区 `ChatInputArea`（L28），**无 `ZStack`/`overlay` 承载这三个主体** ⇒ composer 玻璃面（`ChatInputArea.swift:117` `.glassSurface(.regular, cornerRadius: 16)`）与消息流各自占位，不存在「静止态内容压在玻璃下方」的结构前提。`ChatAreaView.swift:192` 的 `.overlay(alignment: .bottomTrailing)` 仅承载悬浮滚动按钮（非玻璃、非主体内容）。**残余**：首帧消息与玻璃下沿的实际像素间距属运行时量，按 §0 无像素通道 ⇒ 归 G3 目检（27 beta 幻影坐标口径下以 AX pos 为权威）。**本项审计的意外产出＝ D-19**：拉材质清单时发现顶栏用的是 `.ultraThinMaterial` 而非玻璃体系入口 `.glassSurface(...)` ⇒ 主题插件与减弱透明度降级链都管不到它，已另立卡交你裁（非本项结论）。 |
| **A18 sheet 自铺背景反模式** | ◐ **09-06 逐 sheet 审毕：1/5 命中，残余唯一且已定位** ⁽⁰⁹⁻⁰⁶ᵇ⁾ | **官方口径落点先审清**：`presentationBackground` 全仓 **0 命中**（`grep -rn` 于 Apps+Packages） ⇒ 反模式若存在只能来自 sheet 内容视图自填 `.background(...)`。**全部 5 个 sheet 逐个实测**：① `SettingsView.swift:247` → `SettingsCompletePage` **其根视图 `SettingsCompletePage.swift:63` `.background(HarnessTheme.surface)` 自铺底，且该文件无 `glassEffect` ⇒ 唯一命中**；② `PluginListView.swift:216` → `MCPServerLogSheet` 有 `glassEffect`（`MCPServerViews.swift:115` P1.3 补齐），其内 `.background(...surface.opacity(0.5))` 属**子项**背景非根铺底；③ `SidebarView.swift:112` → `ArchiveManagerView` 有 `glassEffect`（`SidebarSupportViews.swift:76-77`，并带「sheet 子窗口内 glassEffect 未官方实证，最坏＝无玻璃视觉」注记）；④⑤ `SidebarProjectSections.swift:182/204`（重命名／删除确认）为内联 `VStack`，仅 `.padding(20).frame(width:)` **无自铺底**＝F5 撤底已生效的实证。**判定**：残余＝`SettingsCompletePage` 一处（P2 新增页，未纳入 F5 批次）；撤它属观感变更且与 D-12（F5 撤 sheet 自铺底批次）同源 ⇒ **归 D-12 一并裁，本轮不改代码**。 |
| **A19 圆角同心** | ❌ **不支持（09-06 编译判据确证，附对照组）** ⁽⁰⁹⁻⁰⁶ᵈ⁾ | **确证方式（不是 grep）**：`swiftc -typecheck` 一段 `Glass.regular.containerConcentric` ⇒ `error: value of type 'Glass' has no member 'containerConcentric'`；**对照组**同法编译 `Glass.regular.interactive().tint(.red)` 无 error ⇒ 证明工具链与探针方法本身有效，排除「环境坏了导致假阴性」。**⚠️ 方法论**：曾先试 `grep containerConcentric "$(xcrun --show-sdk-path)"/…SwiftUI.swiftmodule/`，得空——但那台机器上 `xcrun --show-sdk-path` 返回的是 CommandLineTools 的 `MacOSX.sdk` 且自报 `cannot be located`/`unable to lookup SDKVersion` ⇒ **在无效路径里搜不到毫无证明力**；「本 SDK 无此 API」一类结论一律走编译判据＋对照组。**后果不变**：本 SDK 无同心圆角 API ⇒ 只能手设各层圆角，存在视觉不同心风险；❌不得宣称已支持该最佳实践。 |

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

> 引文精度声明：`.swiftdoc` 内官方正文是**每行 ≤80 字符硬换行**存储的，本节为便于阅读按行合并成整句——**未改词、未改标点、未增删内容**；如需原始逐行形态，用 §18.1 命令去掉合并即可看到（`grep -F "///"` 输出）。〔09-05 逐字复核轮对该声明的执行纠偏：§18.2 曾有 1 处在硬换行处补了逗号（已改回），声明本身成立但当时**未经机器核验**；现由 `tools/qa/quote-verify.py` 逐句核到归档语料的字节偏移，该声明自此可机器复跑，见 §24。〕

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
  > "You can combine glass effects by using a `GlassEffectContainer` which supports morphing glass shapes into each other **based on the geometry of their associated views**."〔09-05 逐字复核：官方此处**无逗号**（硬换行正落在 `GlassEffectContainer` 之后），此前多写一个逗号违反本节「未改标点」声明，已改回官方形态，见 §24.4〕
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

## §26 morph 身份/union 语义的 references 还原与一条根因假设的排除（09-06，A 层：本机归档 JSON＋SDK 语料＋grep 实据）

> 动机＝㊱-2 规矩的执行动作：回扫全部 `~·~` 空位（全仓实测 6 处：BENCHMARK×3／DECISION_INDEX×1（我上轮注记）／QUALITY×2（叙述）），
> 真实依赖空位的结论只有 §1.14 A3 一处（已改判）。回扫时顺 §19.1 的「缺主语假原文」警示把整段还原，得到三条**分析层**增量。
> **原文层增量只有 1 条**（先过 `apple-quote-index.sh` 门：`which appropriate shapes`／`determine when and which`／
> `the default transition type is` 三条**已在册** @`:161`/`:167`——长句查询会因正文 `**加粗**` 而假 MISS，须用裸片段查）。

### 26.1 逐字补录 1 条（通道③ `applying-liquid-glass-to-custom-views.json`，09-05 归档副本）

> "modifiers only affect their content during view hierarchy transitions or animations."
>（句首两个符号位在归档 JSON 中是 **codeVoice run**、正文投影里不占位 ⇒ 不并入逐字串；按 `references` 表还原整句为：「The `glassEffectID(_:in:)` and `glassEffectTransition(_:)` modifiers only affect their content during view hierarchy transitions or animations.」）

**对我方的意义（不是装饰）**：官方把这两个 modifier 的生效域明文限定在「层级过渡或动画中」⇒ 我方 morph 必须处在动画事务内，
`GlassMorphTabBar.swift:196` `withAnimation(.smooth(duration: 0.3))` 满足该域（此前「必须在动画事务里」是经验说法，现在有原文锚点）。

### 26.2 空位主语还原（三处，全部由 JSON `references` 表还原，❌非猜测）

| 在册原句（空位处） | 还原结果 | 还原依据 |
|---|---|---|
| 「Use ⟦?⟧ modifier to specify that a view contributes to a unified effect… **This combines all effects with a similar shape, Liquid Glass effect, and ID into a single shape**」 | **`View/glassEffectUnion(id:namespace:)`** | 该 paragraph 前置 codeVoice/reference run 的 identifier＝`doc://com.apple.SwiftUI/documentation/SwiftUI/View/glassEffectUnion(id:namespace:)` |
| 「Associate each Liquid Glass effect with a **unique identifier** within a namespace that ⟦?⟧ property wrapper provides」 | **`Namespace`**（`@Namespace`），祈使句主语＝`glassEffectID(_:in:)` 用法步骤 | 同区 identifiers＝`GlassEffectTransition`／`Namespace`／`withAnimation(_:_:)` |
| 「…the default transition type is ⟦?⟧」 | **`matchedGeometry`**（已在册 @:161，本节仅确认还原链一致） | 同区 `GlassEffectTransition` 的 case 引用 |

### 26.3 排除一条根因假设（价值＝防止往错误方向修，等价于一条真实进展）
§19.1 曾把「combines all effects with a similar shape, Liquid Glass effect, and ID into a single shape」记为「union 三同条件」，
**当时未记主语**。26.2 还原后主语是**显式 modifier `glassEffectUnion(id:namespace:)`** ⇒ 该合并**不是 `GlassEffectContainer` 的自动行为**。
**我方实据**：`grep -rn glassEffectUnion --include=*.swift .` 全仓命中 **1 处，且是注释**（`SettingsView.swift:159`，讲「验证文档 §六 glassEffectUnion 语义」），**无任何实际调用**
⇒ **「我方六 tile 同 ID＋同 tileShape＋同 Glass 变体 ⇒ 被自动 union 成一枚形状 ⇒ 于是只见淡变不见 morph」这条假设被排除**，不得作为 D-1 的修复方向。

### 26.4 但我方存在一处**有据可依的与官方实操指引的偏差**（精确表述，含不下负结论的边界）
- 教程通道明文：**「Associate each Liquid Glass effect with a unique identifier within a namespace that the `Namespace` property wrapper provides.
  These IDs ensure SwiftUI animates the same shapes correctly when a shape appears or disappears due to view hierarchy changes.」**
- 我方现状：`GlassMorphTabBar.swift:141` `static let selectionID = "harness-sidebar-selection"` ＋ `:243` 全部 tile 共用该一枚 ID
  ⇒ **不满足「unique identifier」的字面指引**（六 tile 若要各自成 shape，ID 无法区分彼此）。
- **边界（必须与上条同读）**：本机 SDK 通道 `glassEffectID(_:in:)` 文档全文只说「SwiftUI will use the provided identifier to animate shapes to and from each other
  during transitions」，**通篇无 unique 字样** ⇒ 因此只能说「教程实操指引要求 unique，我方不符」，
  **不得**写成「官方禁止同 ID」或「同 ID 必然导致不 morph」（官方对「同 ID 且 identity 不变」时 matchedGeometry 会否几何派生**未作声明**，见 §1.14⁽⁰⁹⁻⁰⁶ᶜ⁾）。
- **对 D-1 的净效果**：前置实验的**变量①（ID 策略：每 tile 独立 ID）从「便宜的尝试」升格为「有教程明文支撑、且与官方示例（pencil/note 两枚不同 ID）一致的偏差纠正」**；
  变量②（动画选择）维持原级别。两案的最终判定仍须你目检（§0 无玻璃像素通道）。
- **⚠️ 09-06 改判（本小节的「偏差」不成立，且变量①方向是反向的）**：上面「我方现状」里
  「`:243` **全部 tile 共用**该一枚 ID」这句代码事实**经装配点核验后不实**——
  `:243` 的 `.glassEffectID` 位于 `tileContent` 的 `.glassMorph` 分支内，而 `TileFaceMode.resolve`
  （`:180-183`）第一行就是 `guard isSelected else { return .plain }` ⇒ **未选中 tile 走 `.plain`，
  既不挂玻璃也不挂 ID**。⇒ 真实装配是「**任一时刻仅一枚玻璃面持有该 ID**」，六 tile 并不并发
  共享六枚玻璃面；教程示例里的 `pencil`／`note` 之所以是两枚 ID，因为那是**两个不同逻辑元素**，
  而我方选中高亮是**同一个逻辑元素在六个位置之间移动**——按本节边界条所引 SDK 原文
  （animate shapes to and from each other during transitions），旧面与新面**必须共享同一身份**
  才可能互为动画对象。⇒ 三条结论：
  ①「不满足 unique 字面指引」的**前提**不成立 ⇒ 本小节「有据可依的偏差」作废（就地标注，原文保留作沿革）；
  ②「每 tile 独立 ID」不是偏差纠正，而是**会让旧面 ID≠新面 ID、按官方语义恰好破坏 morph**
  ⇒ **变量①整维排除**（省掉一整轮反向尝试，并避免一次产品回归）；
  ③ D-1 前置实验矩阵由「ID 策略 × 动画」缩为**只剩动画维**（`.smooth(duration:0.3)` vs `.default`
  vs `.spring`，另加 §25.3 那个官方 opt-out 开关）⇒ 你目检从 4 格降到 3 格。
  ⚠️ 边界照旧：本次改判只否定「改 ID 能修它」这一条修法方向，**不改判观感**——morph 实况仍须你目检终裁。


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

## §21 代码注释「官方」引用全量审计（09-05，A 层静默；§20.2 检索门首次全仓执行）

> 动机：§18.5 那种「注释里写官方、实际无原文」的过度归属已发生过一次。本轮不再抽查，改为**全量**：
> `grep -rn "官方" --include='*.swift' Apps Packages` ＝ **54 行**，按目录现算三分（口径闭合，脚本可复跑）：
> **玻璃类源码 29 行**（`Styles/`＋`Views/`＋`HarnessApp.swift`）＝本审计主体｜**LLM／提供商语境 15 行**（`Packages/`＋`LLMConfigStore.swift`＋`ViewModels/`）｜**测试代码 10 行**。
> ⇒ §21.2 的 11 条 B/C 档全部落在玻璃类源码内；玻璃类**测试**注释只有 1 行（`GlassMorphTabBarTests.swift:116`「interactive 需 Add 非默认自带」）＝A 档，与 §1.10 逐字原文相符，**摘要里欠的「同名测试用例名复核」就此结**（该用例与注释均有原文支撑，无需改名）。

### 21.1 判定口径（三档）

| 档 | 含义 | 处置 |
|---|---|---|
| **A 有原文** | 能在 §1/§17/§18/§19 逐字表或 `.swiftdoc`/SDK 签名中找到支撑 | 保留，注上锚点 |
| **B 归纳冒充** | 方向对，但把「我方推论／不完整条件」写成官方判据 | 加限定语（`.swift` 注释批次） |
| **C 负结论无门** | 写「官方无 X」但未走 §20.2 四步 | 补跑门并挂证据，或撤销 |

### 21.2 B/C 档清单（＝G2 首轮 `.swift` 注释批次，idle 时一次跑完门禁）

| # | 位置 | 现状表述 | 问题 | 改法 |
|---|---|---|---|---|
| 1 | `GlassSurface.swift:16` | 官方 `Glass` **仅两变体**（regular/clear） | **签名层实测有三个静态成员**：26.5 SDK `SwiftUICore.swiftinterface` L5753–5762 依次 `regular`／`clear`／**`identity`** | 「HIG 明文材质变体＝regular/clear（§1.9）；SDK 另有 `Glass.identity` 单位值（签名实测在册，HIG 未描述）」 |
| 2 | `GlassSurface.swift:112` | 「官方 Glass 变体；仅开放两档」 | 同上；「仅开放两档」是我方策略 | 拆成「官方变体（HIG 两个）＋我方仅开放两档＝策略」 |
| 3 | `GlassMorphTabBar.swift:136` | 「morph/union 官方约束：同变体 ＋ 同型 shape」 | **合并归因＋漏条件**：官方 union 三同是 similar shape／Liquid Glass effect／**and ID**（§1.8），且 union 与 morph 是两套机制 | 拆开写：union 三同（挂原文）／morph 判据＝最近边 ≤ spacing（挂 §1.8） |
| 4 | `GlassMorphTabBar.swift:132` | 「官方 morph 语义＝同 identity 面在不同位置间形变」 | 官方 ID 原文只保证「同一 shape 在**层级增删**时被正确动画」（§19.1-3），**无「位移形变」明文**；官方示例反而是两面**不同** ID（§18.2） | 标「我方构造：借官方 ID 语义推得；位移形变未官方明文」 |
| 5 | `GlassMorphTabBar.swift:133` | 「❌不得改为每段一个 ID——那会让官方示例式双胶囊形态取代流体高亮」 | 后果是**我方预测且未实测**，却挂在「官方示例」名下 | 标「我方预测（未实测）」；反例证据＝§18.2 示例形态 |
| 6 | `GlassMorphTabBar.swift:28` | 「已被官方原文证否（补面反而制造静止态融合与噪声）」 | 官方只说明 add/remove 即可 morph；「补面→at-rest 融合」是我方依 §19.1-2 的**推论** | 拆两半并各挂锚点（官方说明／我方推论） |
| 7 | `GlassMorphTabBar.swift:23` | 「正是官方 morph 构造」 | 官方描述触发方式，未规定唯一构造 | 改「符合官方描述的 morph 触发方式」 |
| 8 | `GlassMorphTabBar.swift:60` | 「取整即覆盖全部切换距离」 | 我方保守取整，官方无此保证（§18.5 更正后仍成立） | 标「我方保守取整」 |
| 9 | `SidebarView.swift:455` | 「满足官方 morph 约束」 | 只提变体，官方还要求同 shape 与同 ID | 补全三同或改「满足官方 union 的变体条件」 |
| 10 | `GlassMorphTabBar.swift:205`／`:226` | 「官方文档模式」「官方模式」 | 轻度归纳、无锚点 | 挂 §1.8 具体句（glassEffect 施加顺序／容器内 behind it） |
| 11 | `HarnessApp.swift:143` | 「官方无透窗采样明文」（C 档） | 结论**成立但零证据在册** | 已补门（§21.3），注释改挂 §21.3 与新补录原文 §21.5 |

### 21.3 负结论检索门首次完整执行（对象＝`HarnessApp.swift:143`「官方无透窗采样明文」）

| 步 | 命令／通道 | 结果 | 自证（防「检索失败冒充阴性」） |
|---|---|---|---|
| ① | `tools/qa/apple-quote-index.sh --query` | 「透窗／behindWindow／sampling」命中项**全是我方自己的表述**（NSWindow 能力在册），非官方明文 | 命中行逐条读过 |
| ② | `grep -rn` 于 Sources | 仅该注释本身 | — |
| ③ | `.swiftdoc`（26.5） | `behindWindow`=**0**；`backdrop` 7 处均属私有 `_backdropEffect`；`sampl` 73 处经逐条抽检**全属 `GraphicsContext.BlendMode` 等无关符号**；`behind` 51 处属 background/shadow 类 | 命中项内容已打印并归类 ⇒ 非通路失效 |
| ④ | 在线 JSON 四页（container／Glass／教程页副本） | `sampl` 命中经 key 路径定位为 `…Landmarks-Building-an-app-with-Liquid-Glass.role = "sampleCode"` 与图片 alt 文本 ⇒ **全部是「示例代码」不是「采样」**；`behind` 命中全为「玻璃位于内容／其他面背后」 | 用 key 路径打印，非全文 grep |

⇒ **判定：C 档负结论成立**，且现在有可复现的四步证据。官方对此的正面明文见 §21.5 第 1 句（只说 blurs content behind it）。

### 21.4 另一语境（不入本批次）

`AppViewModel.swift:1564`／`LLMConfigStore.swift:12,30,135`／`SettingsSubPages.swift:402,411` 的「官方」＝**提供商**默认地址语境，非 Apple 断言 ⇒ 无需原文。
⚠️ 但 `SettingsSubPages.swift:424,426` 是 **Ollama API 语义**断言（同语境总量按现算＝**23 行**：源码 15 ＋ 测试 8，含 `/api/ps` 的 `context_length`、`tool_calls.arguments` 为 JSON 对象、`tool_name`、`done_reason` 取值集、非推理模型不下发 `reasoning_effort` 否则 400）（「官方：medium 映射 high，默认 high」「官方：仅思考模型生效」）⇒ 属跨领域铁律 1，需 Ollama 官方文档支撑 ⇒ 本轮已完成**首轮核验**（结论见 §21.6：关键断言全部准确，不新增 B/C 档，也不占拍板位）。其中两行已挂**实测**日期（`ConfigPersistenceIntegrationTests.swift:66`、`OllamaNativeIntegrationTests.swift:34` 标「2026-08-27 实证」）＝证据强于文档转述；优先审的是**无实证日期**的那批（如「medium 映射 high，默认 high」「官方会 400」）。

### 21.5 审计过程中新补录的官方明文（此前缺录，直接关联 A15「折射源缺失」）

1. 教程页开篇：
   > "Liquid Glass is a material that **blurs content behind it**, reflects color and light of surrounding content, and reacts to touch and pointer interactions in real time."
2. 同页 `glassEffect` 用法：
   > "By default, the modifier uses the [regular] variant of [Glass] and applies the given effect **within a [Capsule] shape behind the view's content**."
3. 容器内渲染次序：
   > "Inside a container, each view with the [glassEffect(_:in:)] modifier renders with the effects **behind it**."〔09-05 占位精确化：官方 references title 为 `glassEffect(_:in:)`〕

⇒ 三句共同的官方口径上限是「**blurs content behind it**」——即玻璃采样的是**其身后内容**；**没有任何一句**授权采样「窗口之外的内容」⇒ 与 A15 现有结论（透窗采样非官方明文、`window.backgroundColor` 置清空是双刃剑）一致，且首次有了逐字锚点。
⚠️ 引用提醒（§19.1 同款坑）：以上方括号内符号名在 JSON 里是 topic 链接，正文文本位置为空，须回查 `references` 还原（regular／Glass／Capsule／glassEffect(_:in:)）。

### 21.6 跨领域断言首轮核验（DeepSeek ＋ Ollama，均为在线文档通道，A 层静默）

| 我方断言（位置） | 官方原文（逐字） | 出处 | 判定 |
|---|---|---|---|
| 「官方：medium 映射 high，默认 high」（`SettingsSubPages.swift:424`；同义注释 `LLMProvider.swift:14-15`） | "Thinking mode is enabled by default, with the **default effort being high**" ＋ 映射表 "Requested effort / Actual mapped effort：low→low、**medium→high**、high→high、xhigh→high、max→max"；参数集 "{\"reasoning_effort\": \"low/high/max\"}" | DeepSeek `api-docs.deepseek.com/guides/thinking_mode`（本轮实拉） | **A 准确** |
| 「官方：仅思考模型生效，如 qwen3 系」＋原生字段取值（`SettingsSubPages.swift:426`、`LocalAdapter.swift:77`、`OllamaNativeChat.swift:14`） | "`think`: (for **thinking models**) should the model think before responding? Can be a boolean or a thinking level (`\"low\"`, `\"medium\"`, `\"high\"`, or `\"max\"`)." | Ollama 官方 `docs/api.md` L48（`docs.ollama.com/api/chat.md` 同文；`reasoning` 一词全文 **0 命中**） | **A 准确**（字段名 `think` 与取值集均与官方一致） |

⚠️ **顺带查出的产品级观察（不是缺陷，但需你知情）**：两家官方都支持 **`max`** 档（DeepSeek 参数集 low/high/**max**；Ollama think 取值含 **max**），
而我方 `ThinkingLevel` 只有 `off/low/medium/high` ⇒ ① **缺 max 档**；② 在 DeepSeek 侧我方「中」经官方映射实际得到**「高」**（UI 文案已如实告知，用户不会误解为更弱）。
⇒ 是否补 max 档属**产品决策**，登记为 G2 候选（与玻璃批次无关，`.swift` 一行枚举＋文案），**不占拍板位**，等你一句话即可做或永久不做。

**审计净产出诚实申报**：本轮全量审计 54 行，**跨领域部分未抓出新 B/C 档**（4 条关键断言全部有原文支撑，此前只是没把原文挂上）；
玻璃类新增 B 档 10 条＋C 档 1 条（§21.2）。同时补入三段此前缺录的官方原文（§21.5 三段 ＋ 本节两段）。

## §22 把 §21 的人工审计做成有退出码的门（09-05，A 层静默；含机器能力边界的显式申报）

> 动机：§21 是**一次性人工审计**，代码继续写就会再次漂移（§18.5 那类过度归属已发生过）。
> 本轮把它的**形态判据**固化成可复跑的门，同时把**机器判不了的部分**明确留在人工账上——不假装门覆盖了全部。

### 22.1 两件新工具（均实测过失败路径的退出码）

| 工具 | 判据 | 退出码 |
|---|---|---|
| `tools/qa/official-claim-lint.py` | **R1 正断言**（含「官方」）须挂锚点（`§数字/中文数字`、`docs/*.md`、BENCHMARK、swiftdoc、swiftinterface、SDK、HIG、apple.com）或行内逐字原文或明示我方属性（我方/推论/推断/预测/未实测/保守/…）；**R2 负断言**（官方无/无官方/官方未…）额外须挂检索门锚（§20／§21.3／swiftdoc／在线） | 0 全合规／1 有违规／2 口径不闭合或 `--expect` 不符（＝新增删除了「官方」断言 ⇒ 强制重审） |
| `tools/qa/comment-only-verify.sh` | diff 内每条新增/删除行 strip 后必须是 `//` 注释或空行 | 0 仅注释（逻辑字节零变更）／1 含逻辑行（**门禁沿用论证前提不成立**）／2 git diff 失败 |

`comment-only-verify.sh` 的存在理由：QUALITY 长期用「注释改动不改逻辑」论证四门禁可否沿用，但这句话此前**只能靠人眼看 diff**。现在它是退出码。
本轮实测：`扫描：hunk 15，新增行 37，删除行 17 ⇒ 非注释行 0 条`。

### 22.2 门与 §21.2 人工账的对账（HEAD `b44ada8` 快照，`git archive` 解出后跑）

- 门的三分现算与 §21 完全一致：`总 54 ＝ 玻璃类 29 ＋ LLM/提供商语境 15 ＋ 测试 10`（口径闭合）。
- 门报玻璃类 **14 条违规** ＝ 合规 11 ＋ 跨领域另计 4。
- **对 §21.2 的 12 行：抓到 9 条**（#2 #3 #4 #5 #8 #9 #10×2 #11），**边界 3 条**（#1 #6 #7，见 §22.3）。
- **门新抓 5 行 §21.2 从未登记**（同一份人工审计的漏网，形态＝「官方语义/官方：…」零锚点）：
  `GlassSurface.swift:268`、`:271`、`GlassMorphTabBar.swift:88`、`:131`、`:210`。
- 5 行已随本轮注释批次挂**真实**锚点（逐条回查在册原文后才指认，非随便指一章）：
  `:268`→union 三同「combines … into a single shape」＝§19.1-3 ＋ 容器价值句＝§1.8；
  `:271`→"The larger the spacing value on the container, the sooner … blend together" ＝ **§19.1-1 逐字命中**；
  `:88`→"nearest edge is less than or equal to the container's spacing" ＝ §1.8；
  `:131`→**本行文本未改写**（现为 `WT:135`「触发原生 morph（官方文档语义）」），它现在过门是**靠 ±1 行取证**——
  即 §22.3 边界第 3 条的活样本；内容上它确有官方依据（§1.8 首句 "For effects you want to add or remove that are
  positioned within the container's assigned spacing, the default transition type is matchedGeometry."），
  真正无官方明文的是**下一行的「位移即形变」**，该行已由批次改为「我方构造＋观感待目检」（`WT:136-138` 挂 §19.1-3／§18.2）；
  `:219`（＝HEAD `:210` 的批次后位置）→**改判**：官方口径只到「同 ID 保证形状**增删**时正确动画」（§19.1-3），
  「位移即流体融合」标注为**我方构造、实况待 D-1 终裁**（与 §21.2 第 4 条同口径，❌不再挂官方名）。
- 另有 2 处是**本轮补丁自己引入**、被门当场抓住并修正：`:24` 把「官方只描述触发条件，未规定唯一构造」标为**我方解读**（挂 §18.2）；
  `:64` 原写「官方无此保证」＝负断言未挂门 ⇒ 改为「**我方保守取整**，非官方承诺」（同一事实，去掉对官方文本的阴性宣称）。
- **修正后（工作区）现算**：`总 59 ＝ 玻璃类 34 ＋ LLM 15 ＋ 测试 10`；玻璃类 `合规 30 ＋ 违规 0 ＋ 跨领域 4` ⇒ **门 rc=0**。

### 22.3 机器不可判的边界（三条，必须与「门已绿」同时申报）

1. **有锚点 ≠ 锚点支撑该断言**。§21.2 #1（`GlassSurface.swift:16`「官方 `Glass` 仅两变体」）行内本就有 `HIG`＋`§1.9`，
   形态门判它合规，而人工审计抓的是**内容**（SDK 签名层实有第三个静态成员 `Glass.identity`）。⇒ 此类只能靠人工，门不可替代。
2. **断言行内混排真原文与我方定性**。`GlassMorphTabBar.swift:23` 一行里既有官方逐字引文（区间覆盖）又有「正是官方 morph 构造」的过度归属 ⇒ 形态门放行，人工结论（§21.2 #7）继续有效。
3. **锚点允许 ±1 行取证**，故「上一行放 §、下一行写断言」这种松散挂法也能过门；它保证的是「附近有出处」，不保证「指对了出处」。

### 22.4 引文区间状态机的三条硬约束（每条都有实测反例，勿放宽）

| 约束 | 反例（实测踩到） |
|---|---|
| 引号须在**注释行内**配对 | `static let selectionID = "harness-sidebar-selection"` 曾把 `:133` 洗白 |
| 区间**不得跨越代码行** | 防「注释引文＋下方代码串」拼成假区间 |
| 区间须 **≥4 个含字母的词** | 短标识符冒充引文 |
| （非放宽）须容忍 markdown 强调 `**` | 官方原文在本仓注释里带 `**`，字符类漏 `*` 曾把合法折行引文判成无锚 |

### 22.5 基线与复跑口径（供门禁与后续轮次直接消费）

```bash
# 批次落地后（HEAD 含注释批次）：期望三分＝34,15,10，且门须 rc=0
python3 tools/qa/official-claim-lint.py --root . --expect 34,15,10
# 批次落地前（HEAD b44ada8 对照）：期望 29,15,10 且门 rc=1（14 条违规＝待修清单，非缺陷数）
bash tools/qa/comment-only-verify.sh          # 注释批次提交前必跑，rc=0 才谈沿用
```

⚠️ **不得用本门绿来宣称「注释内容全部准确」**：§22.3 三条边界即其失效面；跨领域 4 行（§21.4）走提供商文档通道（§21.6 已核验），不在本门口径内。

### 22.6 门已接入常驻门禁 ＋ 落批就绪检查器（同日补）

| 落点 | 内容 |
|---|---|
| `tools/ci-local.sh` run_pr 新增 **PR-0** | `python3 tools/qa/official-claim-lint.py --root .` 排在 SwiftLint 之前（最便宜的检查先跑，且不改动既有 PR-1…PR-4 编号 ⇒ 历史文档引用零失效）。⇒ 今后「注释里挂官方名」的回归会在门禁处直接 rc≠0。 |
| `tools/qa/batch-landing-readiness.sh` | 把「现在能不能跑重门禁／能不能落这批注释」变成退出码：0 就绪／3 空闲不足／4 含逻辑行／5 断言门未过／6 轻门禁未过／7 工作区改动面异常。**只判定只报告，绝不提交、绝不启动 App**（成功路径实测 rc=0，未就绪路径实测 rc=3）。 |

⚠️ 本轮写这两件时**再次踩中本仓已登记的两条坑**（登记过≠不会再犯，故复述）：
① `cd "$(dirname "$0")/.."` 对 `tools/qa/` 下的脚本**只上跳一级会停在 `tools/`**（照抄 `tools/ci-local.sh` 的单级写法即错，须 `/../..`）——表现为一堆「No such file or directory」；
② bash 里 `$rc_cmt）` 这种**变量后紧跟全角字符**会把该字符首字节并入变量名 ⇒ `unbound variable`，一律写 `${rc_cmt}`。
另两条本轮新坑：③ 校验器若不限定路径就扫整个工作区 diff，会把同期未提交的 `tools/` 改动误报成「非注释行」⇒ 必须 `comment-only-verify.sh -- Apps`；
④ `cmd | tail -2` 之后取 `$?` 取到的是 `tail` 的码（本仓第 N 次撞上，已在检查器里改成先落文件再取码，并在注释里点名防复发）。

## §23 证据加固轮：三条通道首次入档 ＋ A13/A14 原文复核 ＋ 台账漏计纠偏（09-05，全程 A 层 curl/只读）

> 动机：G1a 在 v8 里被明确写成「原文复核用浏览器/文档通道，与键鼠无关」＝静默可跑，是本轮唯一不需你出场的轨道。
> 结果分三类：**复核通过**（不改变结论但补上可复现锚）、**新入册原文**（改变 A14 取舍权重）、**纠出我方台账与工具缺陷**。

### 23.1 三条通道首次归档（此前只有 1 份副本，§1.9/§1.11 的引文一直**无归档、无通道记录**）

| 归档文件（`~/harness-wt/evidence/apple/`） | 可复现通道 | 复核结果 |
|---|---|---|
| `hig-materials.0905.json`／`.txt`（76,600B） | `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/materials.json`（**HIG 有 JSON 通道**；HTML 页是 JS 壳，四条在册句在 HTML 里全 0 命中） | §1.9 **五句全部逐字命中**；⚠️ 其中一句须用**全角撇号** `Don’t use Liquid Glass…` 才命中，写成直引号 `Don't` ＝ 0 命中（假阴性的现实来源之一）。该页 `tint`／`selectively`／`frost*` **均 0 命中** |
| `wwdc2025-219.0905.html`／`.txt`（157,439B；正文 18,030 字符／323 句块） | `https://developer.apple.com/videos/play/wwdc2025/219/`，正文在 `<span class="sentence"><span data-start="…">` 内（页面顶层同样是 "This page requires JavaScript" 壳 ⇒ **必须按 raw 偏移定位**） | §1.11 抽 5 句做**整句**复核＝**5/5 逐字命中**（含 A13 的 "use them selectively…"、A14 的 "frostier…"、A17 的 "avoid intersections…"、F1 的 "Instead of fading,"） |
| `environmentvalues-accessibilityreducetransparency.0905.json`（8,298B）＋`glass-tint.0905.json`（5,435B） | `…/tutorials/data/documentation/swiftui/environmentvalues/accessibilityreducetransparency.json` 等 | 见 §23.2；`Glass.tint(_:)` API 页**只有声明与 abstract，无任何「用途/克制」表述** ⇒ A13 的权威只能是设计指南（WWDC219），不得冒充 API 约束 |

### 23.2 新入册官方原文（此前全仓缺录，直接改变 A14 取舍权重）

> "If this property’s value is true, UI (mainly window) backgrounds should **not be semi-transparent; they should be opaque.**"
> — `accessibilityReduceTransparency` 的 Discussion 全文（该页 Discussion 仅此一句，已整页归档）

⇒ 这是**对开发者的指令**；而 §1.11 引用的 "makes Liquid Glass frostier" 描述的是**系统自家玻璃**的观感。两者不同层，故 A14 的正确问法是
「要不要为了向系统观感靠而放弃 API 明文指令」，**不是**「我方 solid 是否违规」。**A14 仍由你裁决**，但保 solid 一侧现已有明文支持（§12/§1.11/DECISION_INDEX/DECISION_CARDS 四处同步改口径）。

### 23.3 A13 复核结论：引文真、行内未标出处 ⇒ 已补（含一条差点发生的误判）

本轮一度以为 `"use them selectively"` 无官方原文（HIG Materials 与 Color 两页均 0 命中），
**动手前跑了 §20.2 步骤①**，`apple-quote-index.sh --query selectively` 命中 **BENCHMARK §1.11 L277 早已入册该句更长版本**（出处 WWDC219）⇒
**这是 §18.5 型误判的第二次**，且这次被门在**落笔之前**拦住（上次是写完之后才推翻）。教训固化：
**「引文在哪个页面」与「引文是否存在」是两个独立问题**，检索门第一步查我方已入册引文之所以强制，正因为它同时防这两类错。

### 23.4 台账纠偏：`decision-pending.sh` 旧口径漏计非 D 段（**对外曾报 10 项，实为 13 项**）

同一张总账表里 `A14`、`轴2`、`RSS 可见态组` 三项状态也是 ☐，而旧工具只匹配 `^| **D-` ⇒ 少报 3 项。
现工具同时输出 D 段／非 D 段／合计，并加**两条防空转守卫**：文件缺失 rc=2、表内零 ID 行 rc=2（**拒绝把「读不到」读成「0 项」**）。
本轮独立交叉核对（不经工具）：`ID 行 19 ＝ ☐13 ＋ ◐1 ＋ ✅5` ✓ 与工具输出逐位一致。
⇒ 你的拍板清单实际是 **13 项**：D 段 10 项 ＋ A14 ＋ 轴2 取证方式 ＋ RSS 可见态组基线。

### 23.5 本轮为「同类错误」新增的两道机械防线 ＋ 三条环境坑

- **防线①** `$VAR` 紧跟全角字符：本仓第三次撞上（本轮在 `decision-pending.sh` 又犯一次，表现为 `unbound variable` 把 rc=2 降级成 rc=1）。
  改为**全仓扫描**而非逐个修：`tools/**/*.sh` 扫出 **4 个脚本 13 处**（含 `ci-local.sh` 的未知模式分支、`rebuild-app.sh` 的 bundle 落后失败路径、`r1walk4.sh` 三条日志行）——
  这些恰好都长在「最需要在失败时正确说话」的位置。已全部加花括号，并复测两条退出码路径（0/2 正确）。
- **防线②** 语法检查必须**按 shebang 选解释器**：`r1walk4.sh` 与 `rebuild-app.sh` 是 `#!/bin/zsh`，
  用 `bash -n` 检查时**HEAD 原版同样报 `unexpected end of file`（rc=2）**——本轮差点据此判定「我的改动改坏了脚本」并回掉好改动。
  正确做法：`zsh -n` 现版 rc=0；全量 `git ls-files '*.sh'` 按 shebang 复检零 FAIL。
- **环境坑（新）** 多条 curl 在同一个循环里写**同一个临时文件** ⇒ 后一个响应覆盖前一个证据：
  本轮实际把 219 页的 404 页（15,658B）当成逐字稿归档，靠「归档后 `ls -l` ＋ 关键词回检」才暴露（真实页 157,439B，抓取当时五项关键词各命中 1 次是**真实观测**，未被推翻）。
  ⇒ 取证规则：**一名一 URL，归档后必须回验字节数＋关键词**；`grep` 计数与整句命中是两件事，后者才算逐字复核。

### 23.6 附记：第 4 条通道 ＋ 一条被标记的取证残骸（同日补）

- 新增归档 `view-glasseffect-in.0905.json`（21,681B，`…/documentation/swiftui/view/glasseffect(_:in:)`）——
  其中一句直接支撑本轮给 `GlassSurface.swift:273` 挂的锚（union 后合并为单一 shape）：
  > "You typically use this modifier with a [GlassEffectContainer] to combine multiple Liquid Glass shapes into a **single shape that can morph into one another**."〔09-05 逐字复核：官方此处链接是 `GlassEffectContainer`，我方错填 `glassEffectUnion`——**这句是「容器价值句」而不是 union 句**，union 三同条件的逐字锚点仍是 §19.1-3，勿混用，见 §24.4〕
  ⚠️ 同页复现 §19.1 已知坑：正文里符号名是 topic 链接、**纯文本位置为空**（该页摘要读起来是 "to add this effect to a :SwiftUI uses the  variant by default along with a  shape"），
  摘句必须回查 `references` 还原（此处三者为 `Text`／`regular`／`Capsule`），否则会摘出缺主语的假原文。
  同页 `blend`／`transparen`／`frost` **0 命中** ⇒ A14 的 API 侧明文只有 `accessibilityReduceTransparency` 那一处，勿以为玻璃 API 页也写过。
- **残骸处理示范（§23.5 第三条坑的自我执行）**：首轮误把 404 响应存成 `glasseffect.0905.json`（15,658B），
  已改名 `REJECTED-glasseffect-404.0905.json` 保留现场（不删，防「删了就没人知道错在哪」），正确页另行归档。

### 23.7 A6 假参数复核：结论＝已闭环，原「残留 GAP」是表格漂移（09-05 静默审）

本轮按 §2-A6 行留下的那句「残留 GAP：主题 manifest 若仍暴露曲率/模糊字段＝假参数」去做静态审计（A 层，零前台），
逐字段现算 `blurIntensity` / `highlightIntensity` 的全部出现处（`grep` 限定 `--include='*.swift' Apps Packages`，命中清单已核），
结论：**该 GAP 早在 2026-08-29 `17e9f22`（P2.3）闭环**，且闭环强度高于 A6 行所要求的「显式声明不支持」——
除声明之外还做了范围校验、MCP 路径同口径校验、非法 spec 整体回落基准（不半生效）、设置页文案明示、测试矩阵＋e2e。
⇒ A6 行与 D-4 行同日按实据改写（§2 表格漂移第 N 次复现：**行内「残留」字样必须与代码现状同步，否则会把已闭环项当待办重复劳动**）。
D-4 仍然开放，但它的性质从「危险缺口要不要修」降为「已诚实声明的预留字段要不要进一步拒绝」的体验取向选择。

⚠️ 顺带一条环境坑（本轮实付学费）：`grep -rn … --include='*.json' .` 会灌进 `.build/**.json`（单个覆盖率文件 10MB＋，一次把输出预算打爆）。
静态审计一律用 `git ls-files` 或显式排除 `.build`；跨大仓检索请优先 `git grep`。

## §24 官方引文逐字复核器 ＋ 两份权威档引文台账全量核销（09-05 静默轮，A 层全程）

### 24.1 起点：「逐字在案」这四个字此前从未被机器核过

§21 审的是**代码注释**有没有挂锚点；而注释所引用的**权威档本身**（`P1_GLASS_API_VERIFICATION.md` §六
的「原文摘录」表 ＋ 本文 §1/§18.2/§19.1/§21.5 引文表）里的引文，从未有人把它们逐字回核到官方语料——
「归档」在 09-05 之前也只是 `~/harness-wt/evidence/apple/` 里 8 个文件，且**没有任何清单**：
`.swiftdoc` 只有路径引用（文件随 Xcode 升级就会漂移，等于不可复证），P1 档 §六 的 5 个 API 页从未归档。
⇒ 本轮不再「再人工核一遍」，而是把逐字复核做成**有退出码、可复跑**的门，顺带补齐归档。

### 24.2 归档扩展（一名一 URL ＋ sha256 入 `evidence/MANIFEST.txt`，共 18 件）

| 新归档 | 字节 | 通道与来源 | 为什么必须补 |
|---|---|---|---|
| `apple/glasseffect-glass.0905.json` | 22,762 | ③ `…/swiftui/glass` | P1 §六 `Glass` 行的引文页 |
| `apple/view-glasseffectid-in.0905.json` | 20,948 | ③ `…/swiftui/view/glassEffectID(_:in:)` | P1 §六 `glassEffectID` 行的引文页 |
| `apple/view-glasseffectunion-id-namespace.0905.json` | 21,890 | ③ `…/view/glassEffectUnion(id:namespace:)` | P1 §六 union 行的引文页（slug 两次试错才对，404 页 15,658B 是识别特征） |
| `apple/glasseffecttransition.0905.json` | 19,197 | ③ `…/swiftui/glasseffecttransition` | 同上，transition 行 |
| `apple/hig-materials.0905.html` | 17,748 | ③ HIG `/design/human-interface-guidelines/materials`（HTML 壳） | 承载 §23 那句「This page requires JavaScript」——不归档就永远核不到 |
| `apple/wwdc2025-323.0905.html` | 184,857 | ④ WWDC25 Session 323 视频页（逐字稿内嵌） | §1.12 整节 4 条引文此前只有 Session 219 归档，323 一条都没有 |
| `sdk/SwiftUICore-26.5-…swiftdoc` | 1,771,624 | ② 编译期 SDK（`xcrun` 解析） | §18 整节 offset 声明的权威源，此前只有路径 |
| `sdk/SwiftUICore-27-…swiftdoc` | 1,826,328 | ② Xcode-beta（＝运行时 27 beta 同版） | §18.2 offset 声明约定取 27 的短语起点 |

### 24.3 `tools/qa/quote-verify.py` 与十二条匹配口径（每条都是本轮实测踩出来的）

归因 → 逐字 → 偏移 三段判定，语料缺失一律 `rc=2`（拒绝把「读不到」读成判定）。十二条口径：

1. **分通道归因**：先判定引文自称来自 ②`.swiftdoc` 还是 ③在线 JSON，再要求命中**声明的那条**；只在另一条命中＝归因错（`CHANNEL`），不算通过（§18.5 误判的机制化）。
2. **归因取最近标记**：把上文 12 行拼成一坨再判，会让同时讨论两条通道的章节里所有在线引文被判成 ②（本轮实测造出 11 条假 `CHANNEL`）。
3. **〔…〕旁注不参与归因**：给引文追加更正注记（注记里必然提到 `.swiftdoc`）后，出处行被旁注带偏，凭空造出 6 条假 `CHANNEL`；旁注**内部**的引文则改按注记自己的出处归因。
4. **在线 JSON 是逐 run 存的**：一句官方正文常跨两个 paragraph、链接两侧空白自带 ⇒ run 用空格拼会得到 `HStack , VStack`，直接拼会得到 `HStack,VStack`，两者都不等于官方正文 ⇒ `docc_prose()` 的拼接规则（后段以标点开头不补空格／前段以开括号结尾不补），改动必须过 `--self-test`。
5. **跨段整句降级为 `SENTS`**：我方把两段官方正文拼成一句时逐句核，不冒充「一整句逐字」。
6. **② 的字节结构**（逐字节量得，非推测）：每行文档正文前置 `\n`＋节类型字节＋3×NUL＋长度字节＋3×NUL＋`/// `，两种变体（首字节 `0x01` 与 `0x05`）在同一文件里并存 ⇒ 对原始字节 `find` 整句必然假阴性。解法＝**正文投影 ＋ 投影下标→原始字节 offset 映射**：包含判定在可读正文上做，offset 仍报原始字节。⚠️ 折叠空白必须在建映射时做，事后 `re.sub` 会让映射整体错位（本轮实测：`context()` 输出与所报 offset 完全不相干）。
7. **弯引号在字节通道同样要归一**（§23.1 同款）：官方 `’`＝UTF-8 三字节，latin-1 视图下是三个字符，整段替换、偏移记到首字节。
8. **`[符号]` 占位必须按位置反取官方渲染**：占位是我方照 `references` 手工填的，只核碎片段永远核不到它；而「逐个试配官方 title」也不够——同一句里两个占位同时写错时，改任一个都不能让整句配通（P1 §六 `glassEffectID` 行正是这样漏了 12 天）。解法＝在正文里定位引文，取「相邻字面片段之间」的官方渲染与我方写法直接比对。
9. **反引号内、中文自述、非 swift 围栏块**内的引号 ＝ 我方代码/命令/自述，不计门禁（但 `swift` 块标注「Apple 官方示例（逐字…）」的照审）。
10. **offset 作用域**：声明与引文**同行**＝该短语起点，严格核（容差 16B）；声明在**上方小标题**＝整块文档区起点，只能核「引文是否落在区内」（默认 6,000B）。同一句在 ② 里常多处出现（abstract 表＋符号文档区），必须取**离声明最近**的命中——取首个会凭空量出 20 万字节的假偏差。
11. **历史留档区显式豁免**：专存「我方曾写错的原句」的表（§24.4）按定义必然逐字不命中；若让它判红，作者让它变绿的最省事办法就是**篡改历史**——与本仓「保留历史＋追加更正」的规矩直接对撞 ⇒ 工具反过来逼作者毁台账。解法＝只认精确的 HTML 注释标记 `<!-- quote-verify:archive -->`，**遇第二个 `##`/`###` 小标题自动关闭**，再加 240 行硬上限，超限部分**照常判定**（宁可多报不可假绿）。⚠️ 豁免必须自证不丢判定：本轮用工具自己的函数做了差分审计（§24.7 第 3 段），确认区内 3 条全是错句存档、官方形态在 P1 §六 与本文 L72/L975 处各自照判。
12. **跳过类绝不占用判定去重键**：分类按**出现位置**判，去重只去**计数**。旧写法一句进 `seen` 就永久免检，于是同一句先出现在中文自述／bash 围栏／留档表里，就把后文真正的官方引文一起放过了（本轮 self-test 当场抓出）。

<!-- quote-verify:archive -->
<!-- 本节「我方原写法」列是**写错时的原文存档**，逐字复核器按口径 11 豁免；遇下一个 ### 自动关闭。 -->
### 24.4 本轮查出并修正的 7 处引文缺陷（原句留档于此，正文已改回官方形态）

| # | 位置 | 我方原写法 | 官方实际（逐字） | 性质 |
|---|---|---|---|---|
| 1 | P1 §六 L61 | `"anchored to a view's bounds"` | `SwiftUI anchors the Liquid Glass to a view's bounds.` ＋ `…fills the entirety of the frame, which includes the padding.` | 摘句改写（官方无此短语） |
| 2 | P1 §六 L61 | `"typically used with [glassEffectID] to combine…"` | `You typically use this modifier with a ``GlassEffectContainer`` to combine…` | **改写 ＋ 占位错填符号名**（把容器句说成 ID 句） |
| 3 | P1 §六 L62 | `"multiple views' geometries to contribute to…"` | `You may want the geometries of multiple views to contribute to a single Liquid Glass effect shape.` | 语序改写 |
| 4 | P1 §六 L63 | `with the [glassEffect] … and a [Namespace] view` | `with the ``glassEffect(_:in:)`` … and a ``GlassEffectContainer`` view` | **两个占位均还原错**（官方从不要求 `Namespace` 出现在这句） |
| 5 | 本文 L599 | `using a \`GlassEffectContainer\`, which supports` | 官方此处**无逗号**（硬换行正落在符号名之后） | 加标点，违反本节「未改标点」声明 |
| 6 | 本文 L829 | `the [glassEffect] modifier` | references title ＝ `glassEffect(_:in:)` | 占位不精确（同页 L832 自己已列正确写法） |
| 7 | 本文 L975 | `with a [glassEffectUnion] to combine…` | `with a ``GlassEffectContainer`` to combine…` | **占位错填**：该句是「容器价值句」而非 union 句，union 三同锚点仍是 §19.1-3 |

⇒ 影响面复核：#2/#4/#7 都是**符号名层面的错**，但三处由此得出的设计结论（Tab 分段用 `glassEffectID` 挂身份 ＋ 同区域放同一 `GlassEffectContainer` ＋ union 需三同）各自另有独立逐字锚点（§1.8／§19.1-1／§19.1-3），**结论不变**；改的是引文的正确性，不是决策。代码注释 `GlassSurface.swift:272-273` 挂的是 §19.1-3 与 §1.8，未受 #7 牵连（现算复核）。

### 24.5 新登记：② `.swiftdoc` 与 ③ 在线文档**措辞已漂移**（两处实例）

| 句子 | ② 26.5／27 `.swiftdoc` | ③ 在线页（09-05 归档） |
|---|---|---|
| union 合并条件 | `All glass effects with the same shape and glass will be combined into a single shape.` | `All Liquid Glass effects with the same shape and Liquid Glass variant will be combined into a single shape.` |
| ID 动画 | `SwiftUI will use the provided identifier to animate shapes…` | `SwiftUI uses the identifier to animate shapes…` |

⇒ 这是 §18.1「三者要分开记（编译期 SDK／运行时 OS／在线文档）」的**首个带原文的实证**：断言官方语义时，凡②③措辞不一致的，引用处必须写清引的是哪一条，否则「逐字」二字无定义。工具按**声明通道**判定的理由就在这里。

### 24.6 复跑命令与现算结果

```bash
python3 tools/qa/quote-verify.py --self-test   # 6 条匹配口径回归用例，先于一切
python3 tools/qa/quote-verify.py               # 两份权威档全量；rc=0 才算核销
```

现算（本文件与 `P1_GLASS_API_VERIFICATION.md` 两份，去重后进入判定 **52 条**；另有历史留档区豁免 3 条）：
**整句逐字 41／跨段拼接整句可核 1／仅碎片段可核 7**（碎片段＝引文含省略或占位，其占位已 5/5 经 `references` 反取核验）
**／MISS 0／CHANNEL 0／OFFSET 0／占位还原错 0**；不计门禁 3（未声明官方出处）＋ 围栏命令 2 ＋ 中文自述 0 ＋ 留档区 3；
② 偏移跨硬换行量取 7 条，声明 offset 全部落在容差/区域内；语料＝在线 16 份＋`.swiftdoc` 2 份。

⚠️ 本工具**不进 PR 门禁**：它依赖仓外归档 `~/harness-wt/evidence/`（含 1.7MB×2 的 Apple 二进制，不宜入库）。
归档缺失时它 `rc=2` 报错而非静默通过；引文归档清单与取法在 `evidence/MANIFEST.txt`。

### 24.7 复核器自身的两处判定缺陷（同一轮自查发现，全部固化为 `--self-test` 用例）

**缺陷一：把「写错时的原句」判成 MISS（→ 口径 11）**。§24.4 落盘后首跑，工具报出
`docs/BENCHMARK_CHECKLIST.md:1036/1037/1038` 三条 MISS——正是那张表「我方原写法」列。
性质不是文档错，而是**审计器与历史存档天然冲突**：留档的错句按定义逐字不命中，
而本仓规矩是「保留历史＋追加更正」。此时若把错句改写或删表让工具变绿，等于用工具逼作者销毁审计痕迹，
比漏判严重 ⇒ 新增口径 11 的显式留档标记（三条防泄漏边界见 §24.3 第 11 条）。

**缺陷二：跳过类占用判定去重键（→ 口径 12）**。读 `scan()` 时发现更隐蔽的一条放行路径：
去重 `seen` 在 CJK 自述／bash 围栏判定**之前**就写入，于是同一句只要先出现在留档位置，
后文正文里自称官方的同一句就永远不会被核。第一版补丁我用 `if key in skip_seen: continue`
「修」它，**新写的两条 self-test 当场把这一版判成 FAIL**（实测 `(1, 0)`、期望 `(1, 1)`）——
那把它复刻成了同一个漏洞。最终形态＝分类按出现位置判、去重只去计数、判定只看 `judged`；
改完 6/6 PASS。**这条同时是「工具改动必须先有反例用例」的又一次实证（同 §22.4 一族）。**

**第三段：豁免不丢判定的差分审计**（现算，用工具自身的 `attribute()`/`archive_flags()` 复算，非人工断言）：
留档区内「本可判定」的引文共 **3 条**，全部是 §24.4 的错句存档（L1038 `anchored to a view's bounds`、
L1039 `typically used with [glassEffectID] to combine…`、L1040 `multiple views' geometries to contribute to…`），
**区外判不到的＝0 条**——三条官方形态各自另有在册判定处：`SwiftUI anchors the Liquid Glass to a view…` 与
`You may want the geometries of multiple views…` 在 `P1_GLASS_API_VERIFICATION.md:61/62`，
`You typically use this modifier with a …` 在 P1:61 与本文 L72、L975 三处照判。
⇒ 本轮 `MISS 0` 不是靠豁免换来的：豁免前后进入判定的条数同为 52，被移出的 3 条全是错句。

**净收益**：一台「核官方引文」的机器，先被自己的用例抓到两处**只会漏判不会误判**的缺陷——
这类缺陷比误判更危险，因为它让门禁绿得没有依据。现在两条都带回归用例，改豁免规则或去重顺序都会先红。
