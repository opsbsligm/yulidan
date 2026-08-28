# P1 Liquid Glass — 阶段报告（P1.1–P1.4 全阶段：玻璃化 + Tab Morph + 动效过渡 + 主题参数打通）

> 报告时间: 2026-08-28（P1.2 轮刷新）
> HEAD: 见 §七 提交链（镜像 swift-harness-backup.git 双端同步）
> 状态: **P1.1 + P1.2 代码完成，四门禁全绿**；剩余 = 用户侧实机视觉走查（§四 P1.1 / §6.4 P1.2）
>
> ✅ **P1.1 验收口径核销**：用户 2026-08-28 回复「继续推进」（无报障/无截图异议）= P1.1 无异议通过，P1.2 解锁（与 P1 两决策同款口径：无意见按推荐执行）。实机视觉走查（§四）转为可选项：发现问题随时截图报障，回滚按单提交粒度进行。

## 一、模块完成矩阵

| 子项 | 状态 | 证据索引 |
|---|---|---|
| P1.1.0 解锁复核（铁律 1 二次核验） | ✅ | `docs/P1_GLASS_API_VERIFICATION.md` §八：签名逐字重核零漂移 / 探针重跑 PASSED / 新增按钮风格探针（5+2 族全编译级实证）/ GlassRegularEffect 负面核验 |
| P1.1.1 主题玻璃解析纯函数 | ✅ | `GlassSurface.resolvedGlass(explicitTint:themeTintHex:)`（显式 > 主题 glassTintHex > 无 tint fallback；材质档位暂固定 .regular = P1.4 决策点）+ 测试 ×4 |
| P1.1.2 容器修饰器 | ✅ | `View.glassSurfaceContainer(spacing:)` = `GlassEffectContainer` 包裹 + 降级 no-op（`shouldWrap` 纯函数 + 测试 ×1） |
| P1.1.3 C1 侧边栏容器化 | ✅ | 展开体 `SidebarView:331` + 折叠 rail `:439`（组件地图 C1；P1.2 morph 面将加入同容器） |
| P1.1.4 C2 composer 容器化 | ✅ | `ChatInputArea:135`（输入卡片为当前唯一玻璃成员） |
| P1.1.5 C3 设置 sheet 容器化 | ✅ | `SettingsView:164`（侧栏 .prominent + ShortcutRow .thin + 子页 .thin 卡共存；morph 仅同变体间发生） |
| P1.1.6 C5 玻璃强调按钮 | ✅ | borderedProminent→glassProminent ×9（导入 MCP/安装/授予并安装/密钥保存/保存参数/Apple 登录/启用 iCloud/保存/派生）+ 发送钮 `.plain`→`.glassProminent`；测试连接/冲突裁决成对按钮按地图口径保持系统原生 |
| P1.1.7 C4 卡片独立 | ✅ | 不动（逐实例独立玻璃，不强行合并 —— 组件地图 C4 决策） |
| P1.3.1 弹窗出入场 materialize | ✅ | 4 处 sheet 玻璃面补齐（归档管理/MCP 日志/重命名/删除确认；§9） |
| P1.3.2 侧边栏折叠/展开 morph | ✅ | 两面共享 @Namespace + 同 glassEffectID + 同 .regular 变体；容器上提单容器（§9） |
| P1.3.3 项目分区玻璃卡 + 拖拽/展开动效 | ✅ | thin 玻璃卡逐分区 + 4 处 withAnimation（§9） |
| P1.4.1 glassMaterial manifest 字段 + 宽容回落 | ✅ | ThemeSpec + resolveMaterial 纯函数 + 三来源 Codable（§十） |
| P1.4.2 resolvedGlass 材质档位单点 | ✅ | 容器面/morph 面/卡/sheet 全走单点；tint 优先级链不变（§十） |
| P1.4.3 设置玻璃参数明示行 + 导入校验 | ✅ | tint 色板 + 材质档位文案；glassTintHex 纳入 hex 校验（§十） |
| P1.4.4 实时切换 + fallback | ✅ | 既有 apply→Environment 管线；nil/未知 = .regular（§十） |

## 二、变更清单（12 文件，+112/−15，@949759b）

- `Styles/GlassSurface.swift`（+56）：resolvedGlass 纯函数 + native 分支 tint 单点解析 + GlassSurfaceContainerModifier + View 扩展
- `Views/SidebarView.swift`（+4）：C1a/C1b 容器
- `Views/ChatInputArea.swift`（+5）：C2 容器 + 发送钮玻璃强调
- `Views/SettingsView.swift`（+3）：C3 容器
- `Views/{PluginListView,NavLoadStateView,SettingsSubPages,AccountSyncSection,SkillView,SubagentView}.swift`：C5 按钮 ×9
- `Tests/GlassSurfaceTests.swift`（+36）：+5 测试（9/9 全绿）
- `swift-harness.xcodeproj`（+4）：xcodegen 补齐 `OllamaNativeIntegrationTests.swift` 入工程（上轮 SPM glob 已生效、xcodeproj 滞后；xcode 门禁自此覆盖该 opt-in 测试）

**不变量保持**：三层降级链（solid 最高优先级）/ reduceTransparency 行为 / 布局零改动（容器不改变 frame/padding）/ legacy 分支保留（决策②）。

## 三、四门禁基线 @949759b（全绿）

| 门禁 | 结果 | 日志 |
|---|---|---|
| PR | SwiftLint strict **0** / SwiftFormat **0/254** / 构建 0 警告 / XCTest **257**（2 skip = opt-in 集成）+ Swift Testing **815**（175 suites）合计 **1072，0 失败** | /tmp/ci_pr_p1_1_{lint,test}.log |

> P1.2 轮基线（@d43411b）：PR 门禁同口径 **1074，0 失败**（Swift Testing 817 / 176 suites；Lint 0 / 256 文件）；leaks 0；main 覆盖率 **96.12%**（持平，P1.2 未改 Packages）；xcode 双 SUCCEEDED（日志 /tmp/ci_{pr_p1_2,xcode_p1_2,leaks_p1_2,main_p1_2_cov}.log）。
| leaks | **0 leaks**（MemProbe 500 迭代） | /tmp/ci_leaks_p1_1.log |
| main | Release 构建 + 全量 815/815 + 覆盖率：**后端 90 文件 10,557 行 96.12%**（与基线 96.13% 持平，本 commit 未改 Packages；<90% 同基线 4 文件：AppleSignInService 15.86% entitlements 区 / LLMProvider 79.63% / NotificationService 82.89% / AppleCredentialStore 89.29%） | /tmp/ci_main_p1_1.log |
| xcode | **BUILD SUCCEEDED / TEST SUCCEEDED** | /tmp/ci_xcode_p1_1.log |

**验收用 bundle**：`.build/debug/HarnessApp.app` 可执行文件已 `cp` + ad-hoc 重签（ci.entitlements get-task-allow）+ nm 核验 `glassSurfaceContainer` 符号 ×39 在位；**bundle sha `137e7c7c`**（旧 5320b066 作废）。

## 四、实机视觉验收（用户侧，约 2 分钟）

打开 `.build/debug/HarnessApp.app`（直接双击/打开即当前构建；⚠️ 勿用旧窗口，先确认 Dock 无残留旧实例）：

1. **侧边栏**：展开态整体玻璃面（含底栏）/ 折叠 rail 玻璃面——无渲染异常、文字对比度正常
2. **对话页**：composer 输入卡玻璃面；发送钮玻璃强调（可发送=深色圆 / 停止=红圆状态保留）
3. **设置（⌘,）**：sheet 整体玻璃 + 子页卡片 + 快捷键 kbd 键帽（thin）
4. **强调按钮**：任一「保存/导入/安装」按钮呈玻璃质感
5. **主题 tint（可选深验）**：切带 `glassTintHex` 的主题包 → 玻璃 tint 实时变；卸载回落（社区样例 `demos/community-theme-demo/spec.json` 无该字段，需自造含 `"glassTintHex": "#7C3AED"` 的 spec 验证）
6. **无障碍回归**：系统「减弱透明度」开启 → 全部 solid 降级（不变量）

## 五、剩余项（用户侧）

1. §四 实机视觉走查（P1.1 验收判定）
2. （可选决策）AppKit `NSGlassEffectView.cornerRadius` 曲率候选——当前**不采用**（铁律 4 枚举清单外，验证文档 §七-2 在案）

## 六、P1.2 Tab 分段 Morph 流动玻璃（目标 P1 §2，核心件）

### 6.1 机制（官方语义落地，验证文档 §六在案）
- 选中玻璃面 = 唯一 morph 成员：`Color.clear.glassEffect(glass, in: tileShape).glassEffectID("harness-sidebar-selection", in: morphNS).glassEffectTransition(.matchedGeometry)`
- 切换 = 旧段玻璃面移除 + 新段同 ID 玻璃面插入（同 namespace / 同 `.regular` 变体 / 同型 shape）→ SwiftUI 原生「animate shapes to and from each other during transitions」= 流体形变（❌ 无 ZStack 滑块）
- 悬停/按压反馈 = `Glass.interactive` 材质自带（interactive 默认 true）
- 切换动画事务单一来源 = 组件内 `withAnimation(.smooth(duration: 0.3))`（目标 P1 §2「状态切换包裹 withAnimation」）
- 降级链不变量：`reduceTransparency` → solid 选中块（无 morph，对齐 P0 NavRow 基准）；容器复用 P1.1 `glassSurfaceContainer`（降级 no-op）
- 主题：Glass 经 P1.1 `resolvedGlass` 单点解析（`glassTintHex` → tint，fallback `.regular`）→ P1.4 只需扩主题管线

### 6.2 落点与交互口径
- 落点：侧边栏六分区头（实施计划推荐项）：新对话（瞬时动作）+ 对话/多Agent/插件/技能/工具（tab 选中），2×3 网格，替换原 5 行 NavRow（NavRow 死代码已删）
- 选中态：`.settings` 无分段选中（设置由底栏齿轮承载，P0 行为一致）；「新对话」无持久选中（点击后 startNewChat → 选中 glass 流向「对话」段）
- **快捷键口径变化（两态一致化）**：⌘N = 新对话（此前仅折叠 rail 注册，现展开态亦生效）；⌘1–⌘5 = 五面板切换——展开态 ⌘1 原为「新对话」，现与 rail 一致 = 切换「对话」面板
- 移除：原 .chat 行 hover「+」浮钮（P0 附加 affordance；六分区自身 + tooltip 已自明，报障可恢复）
- 折叠 rail 不动（独立表面，P0 交互保留）

### 6.3 测试与门禁
- 新增 `GlassMorphTabBarTests` ×2（selectedID 映射 6 断言 + sidebarDefault 形状/快捷键 12 断言）
- 四门禁 @P1.2 代码提交（见 §七）：全绿
- 已知 flaky 注记：`ToolsTests.ToolExecutorTests/testEventsEmittedOnSuccess`（事件时序断言）在满载全量首轮出现 1 次失败，隔离复跑 3/3 通过 + 全量复跑通过——**既有 load-sensitive flaky，非 P1.2 回归**（P1.2 未触碰 Tools 包）；留 P2 观察
### 6.4 P1.2 实机视觉走查（用户侧，约 1 分钟）

1. 打开 App（验收 bundle，先关旧实例）→ 侧边栏顶部应为 2×3 六分区（新对话/对话/多Agent/插件/技能/工具）
2. **morph 核心观察**：依次点击不同面板——选中玻璃面应**流动变形**到目标分段（非瞬间跳变、非滑块平移）；「工具」→「对话」跨行切换重点看
3. 点「新对话」：创建新会话 + 选中玻璃流向「对话」段
4. 快捷键：⌘N 新对话 / ⌘1–⌘5 面板切换（展开态均生效）
5. 折叠侧边栏 → rail 交互不变（回归）
6. 切含 `glassTintHex` 的主题 → 选中玻璃 tint 实时变（P1.4 前预埋链路验证）
7. 「减弱透明度」开启 → 选中块 solid、无 morph（降级回归）

## 七、提交链（P1 轮）

| commit | 内容 |
|---|---|
| `d64e6f5` | P0 验收通过入册（P1 解锁） |
| `1be36a4` | 铁律 1 解锁复核（签名零漂移 + 探针重跑 + 按钮风格探针） |
| `949759b` | P1.1 全局玻璃化（四门禁全绿，1072/0） |
| `07c43a4` | P1.1 阶段报告 + 组件地图刷新 |
| `d43411b` | P1.2 Tab Morph（GlassMorphTabBar 新件 + SidebarView 接入 + NavRow 死代码删除 + 测试 ×2；四门禁全绿 1074/0） |
| `562e796` | P1.2 阶段报告定稿 + 组件地图刷新 |
| `209f480` | P1.3 全局动效过渡（4 sheet materialize + 侧边栏折叠 morph + 项目卡玻璃形变 + withAnimation ×4；测试 +4；四门禁全绿 821/0 + 覆盖率 96.13% 持平） |
| `d8fcbb8` | P1.3 阶段报告入册 + 组件地图刷新 |
| `70d7567` | P1.4 主题插件玻璃参数打通（glassMaterial 字段 + resolveMaterial/materialLabel 纯函数 + resolvedGlass 扩参 + 设置明示行 + 导入校验 + 社区样例补玻璃参数；测试 +5；四门禁全绿 826/0 + 覆盖率 96.12% 持平） |
| `<本报告提交>` | 本报告 §十 定稿 + 组件地图 P1.4 状态 |

**P1.2 验收 bundle**：`.build/debug/HarnessApp.app` 可执行文件已 `cp`（@d43411b 源码构建）+ ad-hoc 重签（ci.entitlements）+ nm 核验 `GlassMorphTabBar` 符号 ×172 在位；**bundle sha `45affb72`**（P1.1 的 137e7c7c 作废）。

## 八、P1.2 解锁条件

- P1.1 验收通过（用户实机确认玻璃化正常 + 无交互回归）
- P1.2 范围（实施计划 §2）：Tab Morph 流动玻璃——侧边栏六分区头 `@Namespace` + `glassEffectID(id:in:)`（分段身份）+ `glassEffectUnion(id:namespace:)`（并集融合，**同 .regular 变体 + 同型 shape** 官方约束）+ `glassEffectTransition(.materialize)`；**禁 ZStack 滑块模拟**

## 九、P1.3 全局动效过渡（目标 P1 §3）

### 9.1 机制（全部系统原生 API，铁律 4）
- **弹窗出入场**：4 处 sheet 内容根补 `glassSurface(.regular, 12) + .glassEffectTransition(.materialize)`（补齐 P1 §1「弹窗 sheet 全 glassEffect」缺口）
- **侧边栏折叠/展开 morph**：`expandedBody` / `collapsedBody` 两面共享 SidebarView 提升的 `@Namespace` + 同 `glassEffectID("harness-sidebar-collapse")` + 同 `.regular` 变体（两态均走 `resolvedGlass` 单点，level 仅 legacy/solid fallback 参数不影响原生 Glass 值）+ 同型 shape（cornerRadius 0）→ 折叠/展开时旧面移除/新面插入 = 原生 morph；`.glassEffectTransition(.matchedGeometry)` 描述出入场
- **容器上提**：`GlassEffectContainer` 由双体各自包裹上提至 body 的 `Group`（展开/折叠两面同一容器 = 最优 morph 条件；P1.1 C1a/C1b 双容器合并为单容器）
- **项目分区玻璃卡**：每项目分区 = thin 玻璃卡（C4 式逐分区独立，`glassSurface(.thin, 8)`）；玻璃锚定 view bounds（官方语义）→ 展开/收起与行插入/移除的 frame 动画 = 玻璃原生形变（❌ 无自绘模拟）
- **动画事务**：项目 chevron/头行点按/拖放落位（项目 + 全局）四处补 `withAnimation(.smooth(0.2/0.22))`（此前无动画，列表 diff 跳变）
- **拖拽诚实口径**：`.draggable` 系统快照预览无法挂 live 玻璃（官方无此通道）→ 玻璃 `glassEffectID` 跟随在拖起态不可实现，落点形变以目标卡 frame 动画表达（调研在案，不脑补能力）
- **降级不变量**：solid/legacy 模式下 morph/transition 三参数 no-op（`resolveMorph` 纯函数门控；容器上提在降级模式同样 no-op）→ 减弱透明度行为与 P1.1 一致
- **铁律 1 注记（两处未官方实证，最坏退化不损功能）**：① 跨容器/跨视图态的 morph（折叠↔展开两面）——官方文档未明确互斥视图间 morph 行为，最坏 = 交叉淡变不 morph；② sheet 子窗口内 `glassEffect` 渲染——最坏 = 无玻璃视觉（sheet 内容本身无变化）。二者均待实机走查判定

### 9.2 落点与交互口径
- sheet 玻璃面 ×4：归档管理（380×420）/ MCP 日志（560×420）/ 重命名项目（w300）/ 删除项目确认（w340）
- 侧边栏：折叠（52pt rail，level .prominent 保持）↔ 展开（260pt，.regular）morph；⌘/按钮三入口（顶部折叠钮 / 底栏折叠钮 / rail 头像展开钮）均经既有 `withAnimation(.smooth(0.18))` 事务，无新事务源
- 项目卡：分区间距 +4pt（卡内 padding 2×2），悬停高亮/accent 落点反馈在卡内保留（P0 口径）
- 设置 pane 出入场 materialize 暂不做（P1 §3 bullet 口径 = 弹窗 + 侧边栏 + 拖拽；设置 pane 为 tab pane 非弹窗，P1.5 候选）

### 9.3 测试与门禁
- 新增 `resolveMorph` 纯函数单测 ×4（配对缺省 .matchedGeometry / 显式过渡优先 / 缺参降级 transitionOnly / 全缺 none）
- 探针 `/tmp/glassprobe3.swift`（GlassEffectTransition 可存储 + 修饰器内 ID/transition 组合）TYPECHECK PASSED，不进仓库
- 四门禁 @209f480（全绿）：PR（SwiftLint strict 0/256 文件、SwiftFormat 0/256、821 测试 176 suites 0 失败，较 P1.2 +4）+ leaks 0 + main（Release 821/821 + 覆盖率 **96.13%** 持平基线 96.12%，10,557 行，<90% 同基线 4 文件：AppleSignInService 15.86% / LLMProvider 79.63% / NotificationService 82.89% / AppleCredentialStore 89.29%）+ xcode BUILD+TEST SUCCEEDED（/tmp/ci_{pr_p1_3,leaks_p1_3,main_p1_3,xcode_p1_3}_*.log；无 flaky 复现，Tools 时序测试本轮全绿）
- 注：P1.3 变更全在 HarnessApp（app 目标），不在覆盖率 90% 基线的 Packages 后端范围内（计划 §3 测试策略：玻璃渲染本体 = 实机走查验收）

### 9.4 P1.3 实机视觉走查（用户侧，约 1.5 分钟）
1. **折叠/展开 morph**：点折叠钮（或头像）——玻璃面应从 260pt 宽**连续形变**至 52pt rail（或反向）；若仅交叉淡变无流动 = 铁律 1 注记①的最坏情形（报「淡变」即可，功能不受损）
2. **项目卡**：项目列表每分区应呈 thin 玻璃卡；点 chevron 或整行——行组显隐时卡高**连续形变**（非跳变）
3. **拖拽落位**：拖会话入项目/全局——落位时目标卡行组变更应带动画（玻璃形变）；拖起预览为系统快照（诚实口径，无 live 玻璃）
4. **弹窗出入场**：归档管理 / MCP 日志 / 重命名项目 / 删除项目——sheet 出现/消失时玻璃面应「凝结/消散」（materialize）；若 sheet 无玻璃视觉 = 注记②最坏情形（报「无玻璃」即可）
5. **减弱透明度回归**：开启 → 项目卡/弹窗 solid 降级、侧边栏折叠无 morph（降级不变量）
6. **主题 tint**（可选）：切含 `glassTintHex` 主题 → 侧边栏两面 tint 一致实时变（morph 同变体前提保持）
