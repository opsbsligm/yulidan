# P1.1 玻璃容器化组件地图（2026-08-24 无人值守准备稿，纯文档，铁律 2 前不写视觉代码）

> 目的：P0 验收通过后 P1.1 开工即执行，无需再盘点。
> ✅ **2026-08-28 P1.1 已执行（@949759b）**：容器落点 C1/C2/C3 已落地 + C5 按钮已玻璃化 + C4 保持独立；行号刷新至当前 HEAD（原 08-24 基线行号因 08-26/27 设置页重构有漂移，已核正；原「#2 侧边栏头部」实测为折叠 rail，非展开态头部——分组结论不变）。
> 官方语义（已核验，见 P1_GLASS_API_VERIFICATION.md §六）：同区域玻璃组件放同一 `GlassEffectContainer` → 光学采样一致 + 渲染性能；`spacing:` 控制融合提前量。

## 一、现状盘点（P0 既有玻璃接入点，10 调用点 / 5 文件）

| # | 位置 | level | cornerRadius | 角色 |
|---|------|-------|--------------|------|
| 1 | `SidebarView.swift:329`（容器 :331） | .regular | 0 | 侧边栏展开主体表面（P1.1 已容器化 C1a） |
| 2 | `SidebarView.swift:437`（容器 :439） | .prominent | 0 | 折叠 rail 表面（08-28 核正：原「头部」实为折叠态 rail；P1.1 已容器化 C1b） |
| 3 | `ChatInputArea.swift:117`（容器 :135） | .regular | 16 | composer 输入面板（P1.1 已容器化 C2） |
| 4 | `SettingsView.swift:202`（容器 :164 整体包裹） | .prominent | 0 | 设置 sheet 侧栏面（P1.1 已容器化 C3） |
| 5 | `SettingsView.swift:477` | .thin | 4 | 设置项卡片（ShortcutRow kbd 键帽，C3 成员） |
| 6 | `SettingsSubPages.swift:215` | .thin | 6 | 设置子页卡片（系统提示词 TextEditor，C3 成员） |
| 7-9 | `HarnessTheme.swift:169/173/177` | .thin/.regular/.prominent | — | 三个 level 的样式 helper（被上列与未来按钮复用） |
| 10 | `HarnessTheme.swift:102` | .regular | radiusLarge | 卡片样式（会话气泡/消息卡；C4 逐实例独立，P1.1 不动） |

`GlassSurface.swift`（Styles/）：`GlassLevel`（thin/regular/prominent）× `Mode`（native/legacy/solid）三层降级链已就位；native 分支 `glassEffect(.regular[.tint(t)], in: shape)`；`resolveMode(osAtLeast26:reduceTransparency:)` 纯函数（reduceTransparency 最高优先级 → solid）。

## 二、容器化分组决策（P1.1 执行口径）

新增 `glassSurfaceContainer(spacing:)` 修饰器（内部 = `GlassEffectContainer` + 降级时 no-op），按区域分组：

| 容器 | 成员（file:line） | 说明 |
|---|---|---|
| **C1 侧边栏容器** ✅P1.1 已落地 | #1 主体 + #2 折叠 rail + P1.2 六分区 Tab Morph 面（预留） | 最大同区域组；P1.2 Morph 的分段面必须与侧边栏同容器（官方：并集融合要求同 shape + 同 Glass 变体） |
| **C2 Composer 容器** ✅P1.1 已落地 | #3 输入面板（加号/模型下拉在卡内，chips 为 .thin） | 输入区同区域；当前唯一玻璃成员 = 输入卡 |
| **C3 设置容器** ✅P1.1 已落地 | #4 sheet 面 + #5 设置项卡 + #6 子页卡 | sheet 生命周期内一个容器；.prominent 面与 .thin 卡异 level 共存合法（morph 仅同变体间发生，见验证文档 §六 glassEffectUnion 语义） |
| **C4 卡片独立** ✅P1.1 确认不动 | #10 消息卡等 | 逐实例独立玻璃（跨区域，不强行合并；合并会扩大采样区影响性能） |
| **C5 按钮** ✅P1.1 已落地 | 强调按钮 → `.glassProminent` ×10（发送 + 9 处 borderedProminent 主操作/确认类） | 次要/成对选择按钮保持系统原生（测试连接、冲突裁决双钮） |

**spacing 调参策略**：初值用系统默认（不显式传参）；P1.5 走查时按视觉需要逐容器调 `spacing:`（融合提前量），调参记录入 QUALITY_REPORT P1 阶段段。spacing 是布局级参数，**不进 ThemeSpec**（非材质参数）。

## 三、降级链不变量（P1.1 不得破坏）
1. `reduceTransparency` → container 内全部成员 solid 表面（resolveMode 已保证；container 修饰器在 solid 模式 no-op 不包裹）
2. legacy 分支保留（决策点 ② 推荐默认，等用户拍板）
3. 零警告 / SwiftLint / 全量测试（当前基线 660/660，139 suites）每阶段门禁

## 四、主题参数下发点（P1.4 预埋位，P1.1 仅预留接口）
- `ThemeSpec.glassTintHex` → `Color` → `Glass.regular.tint(...)`：唯一转换点收敛在 `GlassSurface` 内（从主题上下文取 Glass，不散落 10 个调用点）
- P1.1 的 `glassSurfaceContainer` 与现有 `glassSurface` 同样从同一主题上下文取 Glass → P1.4 打通时只改一处
- fallback：tint 解析失败 → 无 tint 的 `.regular`（目标已要求）

## 五、与 P1.2 的接口约定
- C1 容器内预留 `@Namespace` 传递位（P1.2 的 `glassEffectID(id:in:)` 需要）
- Tab Morph 分段面 shape 与变体：统一 `.regular` + 同型 shape（官方并集约束）
- 落点：优先「侧边栏六分区头」（新对话/对话/多Agent/插件/技能/工具）；设置子页 segmented 两处（PluginListView:89 / SettingsView:385）P1 不动（系统控件合规）
