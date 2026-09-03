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

## §6 待你拍板（不代拍）

- **D-1（morph 翻案）判据修订**：接受 §0 结论 1（离屏像素判据作废）→ 按 §4 三轨执行？
  A1 根因修复是否批准进入 G2 头号项？
- **D-2**：A7 `interactive` 宣称——改注释口径 / 还是安排一次真机悬停目检？
- **D-4**：主题 manifest 假参数（A6）是否显式拒绝不支持字段？
- **轴2 取证方式**：§5 (a)/(b)/(c) 选一。
- 既有 D-3（C4 卡片归组）/ D-5（插件路线 A/B/C）/ D-6（空会话 24 个处置）不变。
