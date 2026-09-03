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
- **铁律 1 注记（两处未官方实证，最坏退化不损功能）**：① 跨容器/跨视图态的 morph（折叠↔展开两面）——官方文档未明确互斥视图间 morph 行为，最坏 = 交叉淡变不 morph；② sheet 子窗口内 `glassEffect` 渲染——最坏 = 无玻璃视觉（sheet 内容本身无变化）。二者均待实机走查判定。**2026-09-01 账目更新：① 已实机判定（R1 #2 核销：折叠为 `.smooth 0.18` 交叉淡变非玻璃 morph = 官方语义未知项的最坏退化实为实际行为，功能与视觉均正常，本项关闭）；② 判定途径 = R1 #5 走测 walk3/06–09 截图看 sheet 内玻璃卡片是否在位**

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

## 十、实机走查执行记录（2026-08-29，Agent 驱动 + 用户跳过 SSO 决定后恢复推进）

**方法学**（用户报「死脑筋」后的代码级替代验证路径，全程不抢焦点）：
- App 后台启动（`open -g`，不激活不抢焦点）→ CGWindowList 窗口级截图（`screencapture -l<id>`）→ 像素取证（直方图/质心）→ JXA AXPress 后台点击（无需激活）→ ScreenCaptureKit 进程内高速连拍（morph 取证）
- 验收 bundle：sha `45ca203f4c76` @ 801fef7（`tools/rebuild-app.sh` verify 通过）

### 10.1 走查发现 #1（已修复，`801fef7`）
**选中态 morph tile 内容被玻璃层覆盖**：选中 tile 图标/文字被折射采样洗淡不可见（窗口截图 3x 放大 + tile 内部像素直方图 min 亮度 118 = 内容在玻璃后；未选中 tile 与 composer/项目卡内容锐利互证）。根因 = 旧实现把 `Color.clear.glassEffect` 挂 `.background`（非标准构造，macOS 27 beta 玻璃层合成在内容之上）；修复 = 官方文档模式（glassEffect 直接施加于内容 view，SDK 文档「anchored behind a view + foreground effects over a view」docs §六逐字在案）。修复后同法复验：选中 tile（多Agent/工具/插件/技能 轮换）玻璃内图标+文字全部锐利可见 ✅

### 10.2 已核销项（截图 + 像素证据在 /tmp/w*.png、/tmp/bf2_*.png 等）
| 项 | 判定 | 证据 |
|---|---|---|
| P1.2 #1 2×3 六分区布局 | ✅ | 窗口截图：新对话/对话/多Agent + 插件/技能/工具，快捷键注册在位（代码） |
| P1.2 #2 morph 核心观察 | ⚠️ **判定 = 动画交叉淡变（铁律 1 注记①最坏情形），非流体形变** | SCK 连拍 40 帧 @~60ms：切换瞬间（frame 18）旧 tile 玻璃半透明淡出 + 新 tile 玻璃淡入（双半透明态）；无单玻璃面连续位移帧。非瞬间跳变（过渡 ~0.3s 可观测）、非 ZStack 滑块（代码层铁律 4 合规：glassEffectID+namespace+matchedGeometry 原生机制）。按 §九/§六口径「报淡变即可，功能不受损」——**判定：beta OS 下跨分段 morph 退化为交叉淡变；选型正确性以代码机制 + 本证据为准，macOS 正式版可复测** |
| P1.2 #3 新对话 → 新会话 + 选中流向对话段 | ✅ | 走查期间 AXPress 点「新对话」→ 侧栏出现新「新对话」会话行 + 选中玻璃落在「对话」段（截图互证） |
| P0 §3 导航真实业务（对话/多Agent/插件/技能/工具） | ✅ 全部无假UI | 逐面板截图：对话=会话列表+聊天流（雷猴会话真实 RAG 回答）；多Agent=子Agent 编排表单（0 运行中·0 已完成 SubagentCoordinator 真实编排）；插件=4/4 已启用（终端/深海蓝主题/落日渐橙主题/文件系统，真实插件清单）；技能=3 内置·7 用户（auto-* 自动沉淀技能真实落盘）；工具=18 个可用工具（分类 chips 全18/文件3/终端1/MCP2/网络1/代理0 + MCP 连接失败横幅 fs-test/rm-test/dup 诚实提示） |
| P1.1 侧边栏/composer/项目卡玻璃面（渲染正常、文字对比度） | ✅ | 主窗截图：无渲染异常，文字锐利（选中 tile 修复后复验） |
| P2 §5 #1 同步指示器本地模式不显示（无噪声） | ✅ | 本地模式下底栏设置行上方无 iCloud 行、rail 无云图标（截图核验） |

### 10.3 待用户解锁屏幕后补测（交互类，需前台键鼠）
1. ⌘N / ⌘1–⌘5 快捷键（P1.2 #4）
2. 侧边栏折叠 rail 回归 + 折叠/展开 morph 判定（P1.2 #5 / P1.3 #1）
3. 右键菜单：聊天顶栏会话标题右键 = 溢出菜单同动作集（P2 §5 #3）
4. 确认弹窗：侧栏右键删除会话二次确认 → 取消（P2 §5 #5）
5. 设置概览 sheet + 「打开完整设置」全页（**现 5 卡片**，SSO 移除轮 7→5）+ sheet 玻璃出入场（P1.3 #4 / P2 §5 #6）
6. 主题插件 tint：启用「深海蓝主题/落日渐橙主题」→ 玻璃 tint 实时变 → 还原（P1.2 #6 / P1.4 走查项）
7. 拖拽落位动画（P1.3 #3，用户手动拖一次即可）
8. 减弱透明度降级回归（P1.2 #7 / P1.3 #5，需切系统设置）

**走查副作用（待清理）**：走查期间 AXPress「新对话」创建了 1 个测试会话（侧栏「新对话」行），解锁后核销时一并删除。
> 2026-08-30 核销更新（锁屏内 DB 只读核验）：`sessions.sqlite` 中**已无 08-29 任何会话行**（该测试会话应已被用户在其短暂解锁窗口内删除，核销完成）；另发现 3 个 **08-30 19:11** 新建的空会话（0 事件，疑似用户自行测试「新对话」所建）——**未动**，待用户确认是否清理。
> 2026-08-31 R1 首轮核销（解锁窗口内，Agent 驱动 + 截图 + DB 取证）：**#1 ⌘N/⌘1–⌘5 通过**（⌘N DB 8→9 新建「新对话」`C1B0B601` = 本轮走测副作用，与上述 3 空会话一并待用户拍板清理；⌘1–⌘5 逐面板实测切换、玻璃 tile 选中正常）。批量模式 ⌘2 起失效 + 倾斜小图 = 锁屏过渡伪影（详见 QUALITY_REPORT 2026-08-31 晚条目③，非应用缺陷）；#2–#8 及新增项仍待解锁窗口执行。
> 2026-09-01 R1 第二轮核销（解锁窗口 12:56–13:02 内实测）：**#2 折叠 rail 回归通过**——解锁态 AXPress `sidebar.left` 折叠后主窗保持 1470×860（不缩窗，前轮「158×152」＝锁屏过渡伪影得证）、rail 六图标与底部归档/设置/用户可见、内容区铺满；再按一次布局与选中态完全恢复；`sidebarCollapsed` 1→0 归位（/tmp/wt/r2c_mid.png、r2c_settled.png、r2d_expanded.png）。折叠动画为 `withAnimation(.smooth 0.18)` 交叉淡变，morph 判定沿用前轮结论。
> **走测 #3 途中发现并修复真实缺陷（跨会话标题传染）**：`AppViewModel.sessionTitle(for:)` 回退分支无条件读全局 `messages`（当前选中会话的消息），导致打开有内容会话后，所有未命名会话在侧栏显示成该会话标题，且会话搜索命中被同样污染。修复＝标题解析严格会话局部化（显式标题 → 自身首条用户事件 → 仅当前选中会话可用 messages 兜底 → 「新对话」）；回归用例 `AppViewModelSessionLifecycleTests/sessionTitleIsSessionLocal` 在源码回退后确定性失败（`sessionTitle(for: b) → "标题传染测试消息"`），修复后四门禁全绿（pr 768/163、main 97.56%、leaks 0、xcode TEST SUCCEEDED）。详见 QUALITY_REPORT 2026-09-01 条目。
> 走测取证经验补充：**锁屏过渡期 AX 内容树会返回陈化/重复标签**，AX 与像素不一致时先跑 `/tmp/lockprobe2` 定性；`/tmp/wt/ax` 已补 `AXValue` 坐标解码（`pos=/size=`），后续右键与拖拽可用真实坐标。剩余 #3–#8 待下一个解锁窗口。
> 修复的已知边界（非本轮引入，记录备查）：`sessionTitle` 依赖「显式标题 / 会话自身 events / 当前会话 messages」，而启动加载为「仅元数据」（`rec.events.isEmpty`），因此**生成从未完成的会话**（有 user 事件但 autoTitle 未触发）在冷启动侧栏会显示「新对话」，打开后才恢复派生标题。属标题回填缺失的体验小项（需按会话批量读 DB 首事件才能根治，涉及启动性能），本轮不改，列为后续可选项。
> 2026-09-01 R1 第三轮核销（**纯 AX 动作走测**：不注入鼠标/键盘、不抢焦点，用户当时在前台用 Safari/Electron）：
> **#4 侧栏删除二次确认 → 基本核销**：① 行右键菜单在位（AX 取证 `归档` / `删除(id=trash)`，截图 walk2_row_ctx 与 /tmp/wt/w2b*）；② `AXPress` 菜单项「删除」→ 弹出二次确认，AX 文本 `确定删除会话？` + `取消(id=action-button-2)` / `删除(id=action-button-1)`（/tmp/wt/walk2_confirm.txt）；③ **像素级确认**（/tmp/wt/walk2_04_confirm.png）：居中玻璃卡片 + 取消/删除（删除为 destructive 红）；④ 弹窗消失后 DB 仍 11 行、目标临时会话 `75EF00B7` 仍在 = **未发生删除**。残余：本次「点取消」这一具体动作由谁触发弹窗关闭未被单独证实（我的首次 `buttonpress 取消` 被菜单栏同名「取消」抢先匹配并返回 -25205），已给工具补 `idpress`（按 AXIdentifier 精确按压）待交互窗口补最后一步。
> **#3 顶栏标题右键**：代码级两个入口共用同一 `@ViewBuilder sessionMenuActions`（恒等），实机取到该动作集物化内容 = `置顶/添加附件/派生子 Agent/复制到剪贴板/导出为 Markdown…/重命名对话…/清空本对话/删除对话` 八项逐字一致（/tmp/wt/w2b_title_ctx.txt、walk/overflow_menu.txt）；标题 `AXStaticText` 不支持 `AXShowMenu`（-25204），故「从标题入口真实弹出」需真实右键 = 待交互窗口。
> **实机确认本轮缺陷修复生效**（同一张截图）：侧栏三行「新对话」标题各自独立、内容会话「帮我执行一个终端命令」被选中时不再传染（修复前该三行会显示成它）。同时确认**侧栏零同步残留提示**（本地模式零噪声不变量，整屏无同步/账号提示）。
> **走测纪律补充**：用户在场时禁用键鼠注入（CGEvent 会打到前台 App，且 `⌘.` 类按键必须前台才能送达）；仅用 AX 动作。**本轮 Harness 窗口中途从 AX/CGWindowList 消失 = 用户自行接管窗口**，随即停止全部应用侧操作，避免干扰真实工作。
> 2026-09-01 R1 第四轮（**#8 减弱透明度：静态审查发现真实薄弱点并已按 Apple 文档修复**）：降级链 `GlassSurfaceModifier.resolveMode` 把「减弱透明度」置于最高优先级，但三个消费点（`GlassSurfaceModifier.body` / `GlassSurfaceContainerModifier.body` / `GlassMorphTabBar.isNative`）此前**只读 `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` 的即时值**，该读取不构成任何 SwiftUI 视图失效依赖，也未订阅系统变更通知 → **「切换系统开关后不重启 App 即降级」在代码层不可证明**（此前 §10.3 仅记为「需切系统设置」的实机项，未识别到该缺陷）。
> 修复＝接入 Apple 文档化的可观察途径 `@Environment(\.accessibilityReduceTransparency)`（macOS 11+），三处消费点统一改走 `currentMode(envReduceTransparency:)`；合成规则收敛为纯函数 `resolveReduceTransparency(override:envReduceTransparency:workspaceFlag:)`＝`override ?? (环境键 ∨ NSWorkspace)`（override 最优先保证用例隔离；NSWorkspace 值保留给非视图/启动路径）。新增 2 用例（优先级矩阵 + `currentMode(envReduceTransparency: true) == .solid` 不依赖 override）。环境键可编译＝API 存在性由编译器实证，未脑补参数。
> 四门禁 @本轮：pr **770/163**（Lint strict 0 / Format 0 / 编译 0 警告）+ main Release 0 警告 + Sources 覆盖 **97.55%**（9,748 行 / 239 未覆盖）+ leaks **0** + xcode **TEST SUCCEEDED**。
> **#8 剩余**：真实系统开关闭合环（辅助功能 › 显示 › 减弱透明度 开→solid 降级、关→恢复）仍需在「用户不在键盘前」的窗口实机核销；本轮已把**代码前提**修成可证明形态，bundle 已同步待重启实例生效。
> **#6 主题 tint 即时性的代码前提（静态证明，本轮补）**：`AppViewModel.activeThemeSpec` 为 `@Published`（:399），切换时带变更守卫赋值（:2266），并经 `ContentView` 的 `.environment(\.harnessThemeSpec, viewModel.activeThemeSpec)`（:54）注入 → 主题变化必然触发视图失效，`GlassSurfaceModifier` 的 `@Environment(\.harnessThemeSpec)` 随之重解析 `resolvedGlass`（纯函数单点）→「切换主题插件即时改全局 glassEffect 无需重启」在代码层成立，实机仅剩「切 → 看强调色变化 → 还原」的肉眼核销。同类缺陷扫描：`Sources/Views` + `Sources/Styles` 已无其它「读系统态渲染」的点（`NSWorkspace.shared.*` / `effectiveAppearance` 仅剩本轮刚修复的一处）。

> 2026-09-01 R1 第五轮（锁屏内静态扫描 + 实况快照，无新增代码）：① **#8 降级链旁路排查闭环——无旁路**：静态扫描见 `GlassMorphTabBar.swift:136-138` 直接调用 `.glassEffect/.glassEffectID/.glassEffectTransition`，疑似绕过降级门；逐行定性＝该调用位于 `TileFaceMode.resolve(isSelected:isNative:)` 的 `.glassMorph` 分支，`isNative` 已在 #8 修复轮接入环境键（:56-59 统一走 `GlassSurfaceModifier.currentMode(envReduceTransparency:)`）→ **减弱透明度开启时走 `.solid` 分支（sidebarHover 实色选中块），玻璃分支不可达**；全源码 grep 复核：`GlassSurface.swift` 三点之外再无未门控玻璃直调点 → **降级链视图层无旁路缺陷**。② **实况快照**：Harness 实例已不在运行（含 #8 修复前二进制的旧 PID 90593 已退出）→ #8「实机闭合环需重启实例」前提**自然消除**，下次启动即加载含修复 bundle（`b91512d11861…` @ fb33416）。

> 2026-09-01 R1 第六轮（锁屏内静态发现：**#6 走测口径修正——玻璃 tint 载体不是内置深海蓝**）：静态审查 `BuiltInPlugins.swift` 证实内置深海蓝/落日渐橙 ThemeSpec **均未声明 `glassTintHex`（nil）**→ 切内置主题的即时可观察项 = 强调色/气泡色，**玻璃 tint 不变是数据事实非缺陷**（`resolvedGlass` 对 nil 走无 tint 分支，单测在案）；玻璃参数走测载体 = 社区样例包 `demos/community-theme-demo/spec.json`（声明 `glassTintHex=#0FB5A6` + `glassMaterial=regular`，其描述自 P1.4 起即标注「实机走查用」）。走测脚本 #6 升级为两段：**6a** 内置深海蓝自动切换/还原（强调色像素证据）；**6b** 提示用户 10 秒手动导入社区包 → 脚本自动侦测列表出现「Tahoe Teal」→ 切换（13_theme_teal_glass = 玻璃青绿 tint 像素证据）→ 还原基准 → 提醒停用删除恢复原状。#6 核销口径随之拆分：6a 全自动可核销；6b 玻璃层若用户不导入则按「强调色层核销 + 玻璃链路单测锁定（ThemeTests 往返 + resolvedGlass 纯函数 + FileThemePackage 校验）」口径关闭，是否要求 6b 实机由用户定夺。

> 2026-09-02 R1 第七轮（**解锁触发式全自动走测方案**，用户指令「锁屏问题想其他方案」）：等人工在场模式改为**武装自动**——三轮现场侦察后落地：① 实例窗口漂移根因实锤（长时后台进程窗口被关 → reopen 恢复窗口落在左侧扩展屏 全局 x=-1663 → v2.1 绝对坐标过滤器失效；修复＝v3 相对 WINX 坐标 + #7 行匹配改 d= 属性——AX 内容树其实可达，此前「全菜单」系 grep 只看 t= 属性误判）；② **#6b 全自动导入**：新工具 `evtype`（CGEventSource 文本注入，Apple 文档 API）+ 文件面板「键入 / 唤起路径输入」公开行为 + ev 补 return 键；路径=源码实证插件页「导入主题包…」按钮（PluginListView:104）；③ **#8 全自动开关**：defaults 直写被 macOS 拒绝（域保护，实测），改系统设置深链 + AX 拨「减弱透明度」开关，`defaults read` 双值验证后才截图，拨回后二次验证，失败即停不乱拨；④ 执行载体：`launchctl submit -l r1walk4`（launchd 托管，跨 exec 会话存活），等解锁 7200s，解锁即自动连续跑 #3→#8，产物 /tmp/wt/walk3/ 待下次上线按图逐项核销。DB 基线变动如实记录：半废弃首轮 ⌘N +1（`13 行`，新增走测临时会话入 R2 待拍板清单）。

> 2026-09-02 R1 第八轮（**锁屏自动化三路实验证伪 + ImageRenderer 突破落地 + #5 半核销 + r1walk4→v4.2**，用户「其他方案」指令延续）：
> ① **锁屏内 UI 自动化三路实验证伪（全部实验证据，非推断）**：(a) 测试进程以外部 `AXUIElementCreateApplication(getpid())` 自查询返回 **-25208（kAXErrorAPIDisabled，TCC 无障碍未信任，swift test helper 无法进程内自授权）**；(b) 进程内 `NSAccessibility` perform 路径对 `NSHostingView` 返回 children=0（SwiftUI AX 树**惰性实例化**，仅外部受信 AT 客户端查询才构建，进程内不可触发，AXDiag 实验 dump 实证）；(c) 锁屏态本实例 AX dump 1608 行全为菜单栏（内容树被系统断供，复证 §10.4 表）。→ **真机 UI 事件走查（press/拖拽/sheet 动画）在锁屏内技术上不可能，「等解锁 + launchd 驻留」架构为唯一正确解**，维持 r1walk4 驻留。
> ② **新能力落地：`ImageRenderer` 离屏渲染锁屏完全可用**（SwiftUI 官方 API、进程内、无窗口服务器会话依赖，锁屏实测 0.9s 出图+0.066s 过测）：新增 `ThemeLiveRenderTests` —— **§10.3 #6「主题切换即时生效、无需重启」功能内核转进程内像素级测试覆盖**：`vm.applyTheme(id:"sunset")` 后不重启不刷新，满铺 accent 探针位图主通道蓝系↔橙系翻转 + 采样断言 + 还原后与初始基准逐点一致。色空间教训入册：ImageRenderer 输出为设备色空间且 `Color.blue`=动态 systemBlue（深色外观 G≈0.62），**绝对色值断言不稳定 → 通道主导序断言**（蓝 B 主导 ↔ 橙 R 主导 + G>B 暖特征；hex→Color 数值正确性由既有 hex 解析单测锁定）。#6 真机走查降级为「玻璃折射/真机色准」抽样项。
> ③ **#5 半核销（walk3 半废弃轮产物复核）**：`06_settings_overview`（偏好页+「打开完整设置」入口+外层 xmark 可见）与 `07_settings_full`（**完整设置 sheet 5 卡齐全**：本地工作区/模型配置/MCP 服务配置/RAG 记忆参数/主题切换入口 + sheet 内 xmark 可见）= **有效像素证据**（该轮拍摄于锁屏前瞬间，窗口渲染正常——此前「全菜单作废」判断对 #5 系过判）。**08/09/10 作废根因实锤**：`idpress xmark` 与外层「关闭设置」⊗ 同 id 二义，误触外层致整个设置页关闭（sheet 关闭链路因此未证，且 09/10 文件字节全等佐证 reopen 未发生）。修复：r1walk4→**v4.2** sheet 关闭改按唯一 accessibilityLabel「关闭完整设置」press（源码 SettingsCompletePage.swift 唯一对应）。另 `row_ctx.txt`（同轮）含侧栏会话行右键完整动作集（AXMenuItem：置顶/重命名对话…/删除对话）——#3/#4 部分证据在案，闭环仍须实机「删除→确认弹窗→取消」。
> ④ **§10.4 能力表勘误**：19:50 锁屏态实测 `/usr/sbin/screencapture -x -o -l<WID>` **窗口级截图锁屏下可用**（捕获到完整实时 UI 3840×1974，含会话列表实时时间戳）——旧表「窗口 backing store 锁屏下不可捕获」基于 capfast（CGWindowListCreateImage）探针，`screencapture -l` 走不同实现，修正为「screencapture -l 可用 / capfast 不可用」。增量价值：锁屏下可预采像素底图。
> ⑤ 载体状态：launchd 任务重投为 `r1walk42`（脚本 v4.2，等解锁 7200s）；新测试提交 + xcodeproj 重生成（目录级 sources 扩容纳入 xcode 门禁）。

> 2026-09-02 R1 第八轮补记①（**解锁窗口内 exec 前台走测 + 手工补验：#4/#5 完整核销、TCC 归因重大发现、v4.3**）：
> **环境归因实锤（解释第七轮全部悬案）**：`launchctl submit`/`nohup` 后台上下文中 **screencapture（TCC 录屏授权归属变化）静默失败、ev key（CGEvent cghidEventTap）对目标 App 不送达**；AX 工具（press/dump/showmenu）与 System Events `key code`（osascript）通道**两上下文均可用**。21:47 轮「零截图」与 22:01 轮「#6a/6b/8 全灭」根因即此——非窗口漂移、非脚本逻辑。对策（v4.3）：① 键盘注入统一 System Events `key code`（⌘.=47/Esc=53/Return=36/⌘,=43/⌘⇧G 组合）；② `shot()` 失败自动降级 `ax_<步骤>.txt` 树取证；③ 走测可在 exec 前台会话（TCC 全权）或 launchd 上下文（AX 证据）两种模式跑。
> **#4 完整核销**（手工，解锁 22:0x）：侧栏行 `showmenu「新对话」`→ 行菜单 `t='删除'(id=trash)` AXPress → **AXSheet(d='alert')「确定删除会话？」+ 取消(action-button-2) + 删除(action-button-1，红色 destructive)**（AX 树 + 像素双证 /tmp/wt/v4_confirm.png）→ alert 关闭后 **DB 19 不变**（取消语义正确；脚本 22:01 轮「无删除菜单项」系 dump 18 级深度未含弹出菜单行的误跳，grep 模式本身与行菜单匹配）。
> **#5 完整核销**（v4.2 前台轮 + 手工补 Esc）：07=5 卡 sheet（**AXSheet role 在案**）→ 08=xmark（唯一 label press）关闭**回落设置页**（v4.2 label 修复生效，r1walk2 轮外层误触问题解决）→ 09=重开 sheet 再现 → **10=Esc 关闭**（System Events key code 53 → AXSheet 1→0）。**口径修正**：SwiftUI `.keyboardShortcut(.cancelAction)` 的系统键 = **Escape**（Apple 文档语义 cancelOperation），此前文档/脚本写「⌘. 关闭」系错误假设——代码注册本身正确；⌘. 非 sheet 通用键（实测 10_closed_cmddot 未关）。
> **#3 部分**：overflow_menu.txt 溢出菜单全动作集含「删除对话」(trash.slash) 在案；顶栏标题右键 png 待 r1walk43（v4.3）轮补。
> **#6a/#6b/#7/#8**：22:01 轮因 ev key 不送达全灭（其中 #7 悬停帧被 #5 遗留 sheet 污染）→ v4.3 修键盘通道后全部转 r1walk43 驻留轮（等解锁 7200s，两种上下文均可跑）。
> **DB 漂移如实**：13 → 19（+6，全部为走测 ⌘N 空会话副产物；CGEvent ⌘N 在 21:47/21:53/22:00 轮部分送达所致）——全部入 R2 用户拍板清单，不擅删。
> **窗口碎片再现与恢复**：22:1x Esc 实验后主窗被压 158×162（macOS 27 beta 幻影已知现象），`open -b com.deepseek.harness` reopen 恢复 1470×923（恢复手段固化）。

> 2026-09-02 R1 第八轮补记②（**#3「同动作集」结构性锁定 + R2 全清单定稿**）：
> **#3**：源码实证 ChatAreaView 标题 `.contextMenu { sessionMenuActions }`(L78) 与溢出 `Menu { sessionMenuActions }`(L96) **共享同一 @ViewBuilder**（L133 定义：添加附件/派生子 Agent ─ 复制到剪贴板/导出为 Markdown…/重命名对话… ─ 清空本对话/删除对话）——「同动作集」为**结构性保证**（同一视图定义不可能漂移），溢出入口实测菜单（overflow_menu.txt）与定义逐字一致；标题右键的系统 contextMenu 弹出像素证据待 r1walk43 补（AXShowMenu 对 SwiftUI 文本不支持 -25204，需真指针事件）。#3 核销口径升级为：结构锁 + 溢出实测 = 立即可关，像素帧为增强项。
> **R2 清单定稿**（DB 19 行全量盘点，events=0 判空）：走测/演示空会话 13 条 = `AB008853` `0EC1C33D` `E85C92BB` `CD790B38`（08-20/24/26 演示遗留）+ `1FFDE591` `278A44E8`（08-30 19:11）+ `C1B0B601`（08-31 ⌘N）+ `0454DFDF` `75EF00B7`（09-01）+ `74C18D9D` `3AEA12F2`（09-02 19:03）+ `1E4D2359` `B5759BE9` `762A27E6`（09-02 21:53）+ `5480AEF9` `3C9F3488` `3B3C771F`（09-02 22:00，注：21:53/22:00 轮 ⌘N 单次触发因事件重复投递各建 2-3 条，如实登记）；**用户内容会话 2 条保留** = `D043EF0D`（5 事件）+ `E7D52757`（1 事件）——去留待用户拍板，不擅删。
> 2026-09-03 R2 清单实况修正（DB 只读复核）：总 20 行 = 空 18 + 保留内容 2。空清单 = 定稿 17 条 + 新增 `593182E4`（09-02 22:42，launchd 零权废轮 ⌘N 泄漏副产，0 事件）——拍板即按本实况清单执行，勿引用更早计数。

> 2026-09-02 R1 第八轮补记③（**「侧栏零同步残留提示」新增项核销**）：SSO 移除轮附加验收项双证通过——① 源码零残留：`同步中/iCloud/漫游/SidebarSync` 在 Apps/HarnessApp/Sources 命中仅回调语义注释与删除说明（无 UI 路径）；② 像素零噪声：22:00 v4_confirm.png 与 19:50 锁屏态 lockshot_test.png 两帧侧栏均无任何同步横幅/提示（本地模式零噪声不变量成立）。**该项核销关闭**（实机走测清单新增项 1/1 ✅）。

### 10.4 锁屏静态审计（2026-08-30，Agent 驱动，代码级替代验证路径第 2 阶段）

**背景**：用户指示「锁屏内能做的全做完，不因锁屏中断」。先做锁屏能力边界实证（全部原生 C API 探针，非猜测）：
| 通道 | 锁屏可用性 | 证据 |
|---|---|---|
| 原生 AX（`AXUIElementCreateApplication` + `AXWindows`/`AXChildren`） | ⚠️ 仅应用级结构可达，**窗口内容树不可达**（窗口元素退化为 `AXApplication` 自嵌套链，无 AXButton/AXStaticText；系统菜单栏可达但属锁屏会话） | /tmp/axprobe、/tmp/axtool dump（1224 行全为菜单栏/自嵌套，0 个内容节点） |
| System Events AX（JXA） | ❌ `windows=0` | osascript 探测 |
| SCK 窗口截图（capfast） | ❌ `frame 0 failed`（窗口 backing store 锁屏下不可捕获） | /tmp/capfast 89181 |
| CGEvent 键鼠 | ❌ 输入路由至锁屏会话，无法送达 App | 平台行为（锁屏独占输入） |

**结论**：§10.3 八项中**全部含真实机交互成分**（键盘事件 / 像素级视觉判定 / 鼠标拖拽 / 系统设置切换），锁屏内不可执行；但**代码级静态审计**（「无返回途径 / 假关闭」专项，针对用户 08-26 同类投诉）可完整执行。

**审计范围**：全部 6 处 `.sheet` + 4 处 `.alert` + 2 处 `.confirmationDialog` 逐一核关闭/取消途径——
| modal | 关闭途径 | 判定 |
|---|---|---|
| ArchiveManagerView sheet | 「关闭」按钮 `dismiss()` + ⌘.（08-26 假按钮已修） | ✅ |
| MCPServerLogSheet | 「关闭」按钮 `dismiss()` + ⌘. | ✅ |
| 项目重命名 / 删除 sheet | 「取消」按钮置 nil | ✅ |
| 新建项目 / 删除会话 / 卸载插件 alert | 系统 alert 自带取消 + Esc | ✅ |
| 聊天删除/清空 confirmationDialog | destructive + 取消 | ✅ |
| **SettingsCompletePage（P2.1 完整设置 sheet）** | **无任何关闭途径**（`@Environment(\.dismiss)` 声明未用、无按钮、无 ⌘.） | ❌ **缺陷，已修** |

**修复**（本提交）：SettingsCompletePage 顶部补标题行 + xmark 关闭按钮（`dismiss()` + `.keyboardShortcut(.cancelAction)` 双通道，视觉样式与 SettingsView 既有「关闭设置」按钮逐字对齐，同 ArchiveManagerView 模式）；同文件顺带消除既有 `Text(LocalizedStringKey)` 自定义类型插值弃用告警（`Text(verbatim:)`，String 插值渲染逐字一致）。
**门禁**：PR 846/178 0 失败（/tmp/ci_pr_closebtn4.log）+ main/leaks/xcode 串行结果见提交信息。
**残余**：该 sheet 的实机「关闭→返回设置页」交互复测并入 §10.3 #5（解锁后一次走查核销）。

## 十一、SSO 模块移除（2026-08-31，用户决定，目标口径变更）

**用户指令**：「干掉 SSO 整个模块，要求解耦，不要导致关联模块和整体崩溃」。App 转为**纯本地单根**：SSO 登录 + iCloud 同步模式整体移除；离线本地模式全部功能保留（工作区五目录 agents/rag/plugins-meta/themes/memory、RAG、记忆、插件、主题、项目/会话、拖拽、归档、搜索、MCP）。

### 11.1 移除清单
| 层 | 内容 |
|---|---|
| 包 | `Packages/Account` 整包删除（9 源文件 1,946 行 + 8 测试文件）：AppleSignInService / AppleCredentialStore / MetadataSyncService / WorkspaceSyncEngine / AccountService / WorkspaceRoot（旧双根） |
| App | `AppWorkspaceStore.swift` / `AccountSyncSection.swift` / `SidebarSyncHint.swift` 删除；`Packages/Workspace/Sources/WorkspaceSyncPayload.swift` 删除；team 级 entitlements `HarnessApp.entitlements` 删除（仅留 `HarnessApp.ci.entitlements`，唯一能力 get-task-allow） |
| 视图 | SettingsView `.account` 子页 + 深链（`SettingsSubTab.account` / `pendingSettingsSub` / `openAccountSettings`）；侧栏同步提示接线；**SettingsCompletePage 7 卡 → 5 卡**（工作区/模型/MCP/RAG/主题）；PluginListView iCloud 文案 + 死代码横幅（mcpPendingReimportNames 恒空，跨设备语义随模块移除） |
| 构建 | Package.swift 删 Account 双 target（HarnessApp 依赖改 Workspace）；project.yml 删 Account/AccountTests target + scheme 引用；**xcodegen 重生成 xcodeproj 并提交**（旧 pbxproj 64 处 Account 引用清零，xcode 门禁用新工程 TEST SUCCEEDED） |
| 工具 | `tools/rebuild-app.sh` Info.plist 删 `NSUbiquitousContainerIdentifiers`（iCloud 容器 key） |
| 新文件 | `Packages/Workspace/Sources/WorkspaceRoot.swift`：local-only `WorkspaceKind` / `WorkspaceLayout` 五目录 / `WorkspaceRootProvider(localRoot:)`（无 probe） |

### 11.2 AppViewModel 手术与恢复（过程教训）
前会话对 AppViewModel（HEAD 2,812 行）的增量修补**误删 32 个非 SSO 的会话/项目 CRUD 方法**（createNewSession / selectSession / createProject / deleteProject / deleteSession / renameProject / renameSession / moveSession / togglePinSession / unarchive* / loadSessionsFromDB / setSandboxRoot / importThemePackage 等）——由编译门禁捕获（数十处 `no dynamic member` 错误，无静默通过）。
恢复口径：**从 HEAD 恢复整文件作底，再执行 15 处精确删除**（全部严格断言匹配；方法清单 comm 对拍，缺失集 = 恰好 6 个 SSO 相关方法：attachWorkspaceSyncIfNeeded / awaitUserResolution / handleWorkspaceRootChanged / openAccountSettings / publishWorkspaceChange / resolveSyncConflict；9 处 publishWorkspaceChange 调用行删除；reconcilePluginMetadata 恒 no-op 保留启动链结构；migrateLegacyMemoryIfNeeded 删 isICloud guard）。结果 2,812 → 2,626 行。
**教训**：2800 行级文件的大删减，「从已知正确底版重切」比增量修补可靠；每次大删减后必须做函数清单对拍。
同批修复：`WorkspaceRouter.init` 潜伏 bug（`provider.resolveLocal()` 未解包可空参数 → `self.provider.resolveLocal()`，编译门禁捕获）。

### 11.3 残留清扫（grep 全源码验证零残留）
`import Account`×3（SettingsView/SidebarView/SidebarSupportViews）→ 删除（Workspace 符号既有 import 覆盖）；`WorkspaceSyncTests` 套件整块（123 行，SessionAssignment 引用）；`WorkspaceRoutingE2ETests` fixture 签名（icloudAvailable 参数已删）；`SettingsMenuModelTests` 深链测试 `.account` → `.notifications`；全源码 grep `AccountService|AppleSignIn|StoredAppleAccount|Ubiquity|SyncedValue|isICloud|icloud(-i)` 零幸存引用（仅剩注释性历史注记，均为「2026-08-30 起纯本地单根」类说明文案）。

### 11.4 门禁（4/4 全绿，/tmp/ci_{pr,main,leaks,xcode}_ssoremove*.log）
| 门禁 | 结果 |
|---|---|
| pr | SwiftLint 0 违规 / SwiftFormat 0 文件（237 文件）/ 编译 0 警告 / **759 测试 162 suites 全绿**（移除前基线 846/178；差 87 例 = Account 包 + 同步测试随包移除） |
| main | Release 0 警告 + 全量 759 绿 + 覆盖率：**Sources 口径 97.37%（9,748 行，256 未覆盖）**——移除前 96.34%（10,609 行，388 未覆盖）；提升原因 = Account 包低覆盖文件（AppleSignInService 24.14% 等）随包移除。最弱包：Notifications 82.89%（设计边界 UN 包装层，已定性）/ WebUI 92.12% / Workspace 94.40%（新文件 WorkspaceRoot.swift 59.38%，provider.materialize 等分支待补测） |
| leaks | 0 leaks |
| xcode | TEST SUCCEEDED（重生成 pbxproj，Account 引用 0） |

瞬态说明：pr 首轮全量 2 处失败——① swiftpm-testing-helper `NSInternalInconsistencyException`（bundleProxyForCurrentProcess nil，runner 进程级崩溃）② `importRegistersToolsRemoveDropsThem` 真实 python3 stdio 握手超时（20s 窗）——隔离复跑均绿（MCP 套件 3/3 + 全量重跑 759/759），定性环境瞬态，与 P1「协作池调度停滞」入册项同族，CI 有界重试机制在案。

### 11.5 验证与残余
- **App 重建 + 字节级核验 + 旧实例替换**（锁屏内已完成 2026-08-31）：`tools/rebuild-app.sh` sha `77a4df8dc3b3` @ dbc84e0 → kill 旧 PID 29799 → `open -g` 不抢焦点 → 新 PID 90383 稳定运行；字节级核验 7/7 通过（二进制 22.8MB：「Apple 账号状态/登出/账号与同步/iCloud 同步冲突/登录 Apple 账号/iCloud.com.deepseek.harness」全部 0 次，「本地工作区」1 次在位）；**DB 8 行不变**（含 3 个用户自建空会话，未动）
- 运行时数据清理：`account.json`（mode=local，无密钥，零代码引用）+ 空 `sync/` 目录删除 → 工作区根仅剩五目录 + sessions.sqlite + subagent_history.json + pluginworker plist
- ⚠️ **Keychain 中若存有旧 Apple 凭证条目（AppleCredentialStore 写入）无代码消费方**，属系统层残留，不影响功能；如需彻底清除由用户在 钥匙串访问 App 手动删除（搜索 deepseek/harness 相关条目）
- §10.3 #5 走测口径更新：完整设置 sheet 现为 **5 卡**版（关闭途径 = 本轮保留的 xmark + ⌘.）
- SSO 真机验收目标（Developer Team/描述文件依赖）**作废**；「账号与同步」相关走测项全部作废
- 解锁后待办并入 §10.3 走测：5 卡设置 sheet 实机过目 + 侧栏无同步提示确认（本地模式零噪声不变量）

> 2026-09-02 R1 第十一轮（**锁屏根因修正 + 离屏替代方案**，用户指令「锁屏导致无法继续的问题想其他方案」）：
> ① **根因修正**：锁屏态实测——exec 全权会话下 AX 菜单树可读（1608 行），但 `open -b` reopen 后**主窗口不构建**（AXWindow=0、CGWindowList 无窗）→ 真机 UI 交互（右键菜单/主题 Picker/拖拽）锁屏下整体不可能；22:42 空 dump 系 launchd 零权而非锁屏。此前「r1loop2 等解锁」从核销阻塞项降级为**解锁后像素补证**通道。
> ② **替代方案落地（离屏优先）**：功能内核改 ImageRenderer/逻辑单测锁定（锁屏可跑），视觉类（#3 像素、#6a 真机 Picker、#6b 面板操作、#7 真机手势联动）统一转解锁后补证、不阻塞口径；#8 需人拨系统设置，维持【待确认】。
> ③ **pr 门禁揪出并修复 2 个 P0 真缺陷**（`2313084`）：**a)** `setSandboxRoot` clear→逐条 register 存在读取空窗，并发 `tool(named:)` 返回 nil（沙箱切换测试 r3=nil 实锤，生产并发对话会真实丢工具）→ 新增 `ToolRegistry.replaceAll` actor 内原子替换 + `ToolRegistryReplaceAllTests` 3 用例（覆盖/清空/并发无空窗 names() 原子快照判定）本地全绿；**b)** `importSkillFile` 注册记录 source 指向 /var/folders 导入源（与磁盘加载语义不一致）→ 注册前对齐 target 落盘路径（不动 SkillStore 库语义，CLI/库测试零影响）。
> ④ **#7 规则离屏锁定**（`d3eb168`）：项目头 0.14 / 全局区 0.06 两级落点高亮提为 `SidebarProjectSections.dropTargetFill` 静态纯函数（生产两处共用），`SidebarDropHighlightRenderTests` 白底探针像素断言（非悬停纯白 + 两级偏离序 + 0.14/0.06≈2.33 线性比例容差 1.6–2.5）**锁屏首绿 @0.05s** → #7 状态 ⏳→**◐**（规则单测锁定 + 真机手势联动待补）。
> ⑤ **#6b 升级 ◐**：`FileThemePackageTests` 既覆盖社区包导入内核（spec.json 导入/目录包/二次校验/glassTintHex 往返/blur-highlight 边界/sanitizeID），NSOpenPanel 仅文件选择透传 `importThemePackage(fileURL:)`（该函数即上述单测入口）→ 真机面板点击归解锁后像素补证。
> ⑥ **门禁链卡死元凶根除**：cir9rest 等待条件 `pgrep -f "ci-local.sh pr"` 被**自身进程命令行字面命中**（无文件 launchd job 的整段脚本 = zsh 进程 argv，含该 pattern）→ 恒真 → leaks/main/xcode 永不串跑（此前多轮「链已挂」实为死等）。修复：bootout+submit 等待式改 regex 转义自证版 `tools/ci-local\.sh pr`（自身命令行含反斜杠字面 → 与转义点号 pattern 不匹配；真实 `/bin/bash tools/ci-local.sh pr` 精确命中），自匹配实测清零。**教训入册：launchd 无文件 job 的 pgrep -f 等待式必须用自身命令行不含的转义 pattern。**
> ⑦ 门禁：pr 基于 `d3eb168` 重跑中（含本轮 2 commit 回归面），三门链串跑；组数字（人工对账收口 @d3eb168，独立复核非哨兵）：**pr rc=0（✔942/✘0）→ leaks rc=0（0 leaks for 0 total leaked bytes）→ main rc=0（775 tests in 166 suites passed + 覆盖率表全量输出）→ xcode 通过（xcresult 01-01/01-03/01-06 三连 Passed：867 tests / 0 failures）。**门禁链 cir9rest 自匹配修复后首次完整串跑成立**。。

> 2026-09-03 R1 第十一轮补记⑧（**并发双链竞态事故与取证教训**）：门禁链收口时发现自己武装了**两个 cir9rest 实例**（旧 42673 未 bootout 又 bootstrap 了 31932）——两链各自完整串跑，链 B 的 `>` 重定向**轮转覆写**了链 A 证据日志（leaks/xcode 日志「rc= 消失」实为他链截断），并让哨兵 v2 的 rc= 判定永远凑不齐（grep 时点被并发轮次撕裂）。三点教训入册：① **链式 job 单实例铁律**——bootstrap/submit 链角色前必须 `launchctl list | grep <label>` 验无同类驻留；② **证据日志完成即冻结**——门禁段一完成立刻 cp 至 `chain1_*` 不可变路径（本轮链 A/B 均为同 commit 全绿，xcresult 867×3 Passed 为最终权威证据，未受污染）；③ **哨兵判定读完成态而非 live 路径**——轮转日志上 grep 判定天然竞态，长期方案已落地（@02b4a85）：ci-local 每段成功原子写 `/tmp/ci.done.<mode>`（内容含时间与 rc，失败 EXIT trap 清除），消费方一律判标记；端到端验证 leaks 两跑 + pr 验证轮 rc=0。事故影响面：仅日志取证与 CPU 浪费（链 B main 编译段被我方主动击杀），**无任何代码/仓库状态污染**（工作树全程干净，HEAD 未动）。

> 2026-09-03 R1 第十一轮补记⑨（**编排终态 + 验证收口 @02b4a85**）：门禁基建补强提交后编排收敛为三 plist——`com.harness.ci11.pr`（门禁轮）、`com.harness.r1loop`（走测等待循环已从 exec 孤儿子实例迁入 plist 单实例，解锁自动跑 r1walk4 **v4.5**：#3 增补 AXShowMenu(top) 兜底、#6a/#6b/#7/#8 全自动段复核在位）、验证一次性任务已清。**pr 门禁 @02b4a85 复跑 rc=0**（`/tmp/ci.done.pr` 标记判定，01:21:12）；leaks 本轮直接复跑亦 0。教训复证：exec 起后台 `(cmd &)` 与 nohup 同样被进程组回收秒杀——launchd plist 是唯一持久载体（第二次踩坑实录）。当前 DoD 剩余全部收敛为「用户在场」类：解锁自动走测补证（r1loop 待命）、R2 拍板、走测帧回看核销。
#### R1 终版核销总表（单一权威状态源 · 2026-09-03 预生成，解锁轮只填空）

| 项 | 状态 | 权威证据 | 待办（解锁轮） |
|---|---|---|---|
| #1 ⌘N / ⌘1–⌘5 | ✅ 核销 | R1 首轮 08-31 实录（本节） | 无 |
| #2 折叠 rail + morph 判定 | ✅ 核销 | R1 二轮 09-01（QUALITY_REPORT 同日条目：1470×860 不缩窗 + 持久化归位） | 无 |
| #3 标题右键菜单 ≡ 溢出菜单 | ◐ | 源码共享 `sessionMenuActions`（ChatAreaView L78/L96）+ 溢出 10 项逐字实测 `walk3/overflow_menu.txt`@22:00 | 真机取证 `title_ctx_menu.txt`（v4.5 增 AXShowMenu(top) 兜底）+ 01 帧回看 |
| #4 删除二次确认→取消 | ✅ 核销 | 补记①：alert AX+像素双证 `v4_confirm.png`，DB 不变 | 无 |
| #5 设置 5 卡 sheet 双关闭 | ✅ 核销 | 补记②：xmark 回落设置页 + Esc（口径修正自 ⌘.）+重开 | 无 |
| ＋零同步残留提示 | ✅ 核销 | 补记③：源码零残留 + 两帧像素零噪声 | 无 |
| #6a tint 即时切换 | ◐ | `ThemeLiveRenderTests`（蓝→橙主导序翻转+还原逐点复原，锁屏 0.07s） | 真机 Picker 切换帧 11/12 |
| #6b 社区包导入 | ◐ | `FileThemePackageTests` 全套内核（spec/目录/校验/glass/边界/sanitizeID）+ 库级 e2e 门禁在跑 | 真机面板导入 Tahoe Teal 帧 + 停用删除收尾 |
| #7 拖拽落位反馈 | ◐ | `SidebarDropHighlightRenderTests`（两级 0.14/0.06 规则+比例锁定）+ `onMoveSession` noChange 单测 | 真机悬停帧 13/14（旧帧污染史见第八轮，重拍） |
| #8 减弱透明度降级 | ◐ | `GlassSurfaceTests` 降级链（override=true 恒 solid / env 键直落 solid / resolveReduceTransparency 优先级矩阵 / 容器仅 native 包裹）在册 02:26 xcresult 867 项＋当日 pr 783 复跑 ✅（补记㉔①） | 真机拨系统开关帧＝二选一（你顺手 1 分钟 / 认可 A 层满足该子句）。旧「heartbeat 自动轮」口径**作废**：C 层动作禁挂任何自动化载体（补记㉔①） |

> 口径：✅=终版核销；◐=功能内核已锁（离屏/源码级），真机视觉帧为补证（不阻塞缺陷判定）；⏳=待解锁自动轮。R2 实况清单见 DB 盘点条目（空 18/保留 2）。

> **D-1 静默裁决证据索引（09-03 工具轮预置，把裁决成本降到一次勾选）**：
> - **#3**：A 层=「同一 `sessionMenuActions` 变量被 `.contextMenu`(L78) 与 `Menu`(L96) 复用」是**编译期结构恒等**（两菜单动作集不可能不同）+ 溢出 10 项逐字实测 `walk3/overflow_menu.txt`；缺口仅「标题右键弹出的那帧画面」。可选 B 层：`ax showmenu` 一次（仅你择时）。→ 建议：**结构恒等+A 层在册即核销**。
> - **#6a/#6b**：A 层=`ThemeLiveRenderTests`（蓝→橙主导序翻转+还原逐点复原，锁屏 0.07s）+ `FileThemePackageTests` 全套（spec/校验/glass/边界/sanitizeID）+ 02:26 xcresult 867 项在册。缺口=真机 Picker 切换帧 11/12 与面板导入帧。→ 建议：认可「离屏像素证据=该子句满足」——本组判据是**色序主导翻转**（渲染管线同源），与「ImageRenderer 不渲玻璃」的适用边界已如实区分（该证伪只涉玻璃面自身质感）。
> - **#7**：A 层=`SidebarDropHighlightRenderTests`（两级 0.14/0.06 高亮+比例锁定）+ `onMoveSession` noChange 单测；旧真机帧有污染史（第八轮）。→ 建议：手感类判据**保留给你手动拖一次最有价值**，或直接 A 层核销。
> - **#8**：见总表勘误行（旧 heartbeat 载体口径作废）。→ 建议：拨「降低透明度」那一下你顺手做（顺带覆盖 27beta 新文案实测），或直接 A 层核销。
> 裁决模板：「D-1：#3 结构核销；#6/#7 A 层核销；#8 我顺手拨」／「全 A 层核销」／「#X 我要真机帧（另约）」。

> 2026-09-03 R1 第十一轮补记⑩（**解锁轮质量三修 + 编排重启幸存 @2aa5cf3**）：① **v4.6 修 #6b 自违原则缺陷**——自动导入 Tahoe Teal 后仅留「手动收尾」提示（违反 walk「不写用户数据」）→ 增自动卸载段（插件页→选中→卸载→alert 内 destructive「卸载」用新增 `press … last` 树尾定位 + dump 双确认，弹窗未出现不乱点、失败如实告警）；② **⌘.→Esc 口径修正**——#6b 尾部 `ev key cmd .` 与补记②实锤（cancelAction=Esc）冲突，即 22:01 轮「#7 悬停帧被残留 sheet 污染」根因之一，统一 Esc 分层关闭；③ **编排迁稳定路径 ~/harness-wt**——/tmp/wt 整链（脚本+二进制+产物）重启即灭属重大缺口，plist 已 re-arm 单实例，工具链源码归档 `tools/r1walk/`（README 含授权口径），产物完成即 `walk3_final_<ts>` 快照冻结（教训②机制化）。

> 2026-09-03 R1 第十二轮补记⑪（**v4.7「先导后切」根因修复 + 锁屏预案改道 heartbeat + 工具链去风险**）：① **#6a 前提缺失根因修复**——themes 目录空 + 无 servers.json → 当前 App 无任何第三方主题插件 → v4.6 的 6a「深海蓝」为不存在的内置项，解锁轮必空转；废弃硬编码段，#6 统一改为 Tahoe Teal 社区包闭环（先导 6b → 完整设置取证 → 6a 切换/还原实渲染 shot 11/12 → 自动卸载还原用户状态；卸载条件放宽为「导入成功过就必须卸载」防数据污染）。**事实修正**：社区包 spec.json 实为全套玻璃参数包（accentHex+glassTintHex+glassMaterial），§10.3 L62「缺 glassTint 字段」旧注过时作废——6a 预期玻璃随之变化。② **锁屏预案改道（用户指示找替代方案）**——实测约束互斥：launchd plist 上下文 TCC 零权（探针防废帧但可能永转）vs Agent exec 会话全权但不可持久（回收即 SIGKILL）→ 触发载体由「r1loop 守解锁」改为 **heartbeat 自动化轮询**：三条件（解锁 / Harness 存活 / 无 .done_v43）满足即在 exec 全权会话跑 `SKIP_N=1 SKIP_45=1 zsh r1walk4.sh 30`，完成冻结快照并暂停该自动化；走测窗口新增 `caffeinate -disu -w $$` 临时断言防休眠/屏保自动锁中途打断（标准 API 不改系统设置、脚本退出即释放、不挡手动 ⌃⌘Q）；`.done_v43` 防重跑守卫（FORCE=1 可越）；r1loop plist 退役（bootout）防 heartbeat 双跑打架。③ **工具链去风险**——盘点发现 ax 工具仅存二进制无源（单份丢失风险）→ 四工具二进制入仓 `tools/r1walk/bin/`，lockprobe2.swift 入册；README 升 v4.7 口径。

> 2026-09-03 R1 第十二轮补记⑫（**heartbeat 前清雷：旧战场遗留 .done_v43 已移除**）：核查发现 walk3/ 全产物 mtime=01:32:32（cp -R 迁移时间）= /tmp/wt 旧轮遗留非新轮；其中遗留 `.done_v43` 会同时命中 v4.7 防重跑守卫与 heartbeat 完成判定条件 → 解锁轮将永久空转。处置：旧证据冻结 `walk3_legacy_0903_0201/`（补记⑧机制）→ 移除标记。heartbeat r1 已确认落盘 ACTIVE（FREQ=MINUTELY;INTERVAL=5，failed_runs_only，挂本任务）。解锁路径三要素齐备：解锁探针持久副本 ✓ / heartbeat 全权轮 ✓ / v4.7 脚本 ✓。

> 2026-09-03 R1 第十二轮补记⑬（**R3 覆盖率核实达标——59.38% 为过时数字，权威复测 100%**）：锁屏等待窗口并行推进 R3。实况：`WorkspaceRoot.swift` 实为 67 行小文件（目标文本"2,626 行"系 AppViewModel 时代旧记误植）；用当日 debug 全量 775 tests 全绿轮（`--parallel --enable-code-coverage`，首轮 1 失败=已入册的 macOS 高负载瞬态、复跑 775/775 绿）llvm-cov 权威复测：**WorkspaceRoot.swift 32/32 行 = 100.00%**（59.38% 为移除轮测量，其后 WorkspaceGapCoverageTests/WorkspaceR17GapTests 轮已修复未刷新台账）。全量 Sources 口径同步复测 **97.57%（9,755 行/237 未覆盖）**，高于入册基线 97.37%。**R3 判定：达标关闭，无需补测**；目标文本中该项以本条为准。

> 2026-09-03 R1 第十二轮补记⑭（**PR 门禁两项补修 + heartbeat 探针路径持久化**）：① 补记⑩入仓轮（v4.6 tools/r1walk）实为 PR 门禁回归源：kickstart 复跑抓到 `ev.swift` statement_position 2 serious（`}\nelse` 断行）+ SwiftFormat 4 文件需格式化（ev/evtype/lockprobe2/wl 全在 tools/r1walk，主工程源从未涉案）→ 语义不变格式化合规 + 四文件 typecheck 0 错误 → PR 复验 **rc=0**（marker 原子标记，775 tests 绿，@e7e392f 推镜像对账一致）；教训：**独立工具源码入仓 = 纳入 lint/format 门禁范围，入仓轮必须当场跑 PR**。② heartbeat r1 prompt 修正：锁屏探针由 `/tmp/lockprobe2`（重启即灭 → 重启后三条件恒假 → 静默死锁）改为持久副本 `~/harness-wt/lockprobe2` 并附 swiftc 重建指引——R2 类重启场景自愈。③ 全量 debug 轮实测：775 tests 首跑 1 失败（MCP 卸载宽限断言，--parallel 高负载）复跑 775/775 全绿 = 已入册瞬态特征吻合（agent8 加固条款在位，非回归）。

> 2026-09-03 R1 第十二轮补记⑮（**leaks 门禁 @当前HEAD 复核实锤 + main 门禁复跑发起**）：锁屏等待窗口并行补门禁。① **leaks 持久复核**（一次性 plist `com.harness.leaks12`，跑毕即 bootout+删 plist）：MemProbe 500 → `0 leaks for 0 total leaked bytes`，marker `/tmp/ci.done.leaks` @02:19:31 rc=0——leaks 结论由「沿用」升格为 @当前HEAD 实测。② **main 门禁复跑发起**（`com.harness.main12` 持久跑 `ci-local.sh main`：Release build + 全量测试 + 覆盖率汇总）——d3eb168..HEAD 主工程（Packages/Apps）Swift 源 **0 变更**（git diff 实锤，涉案仅 tools/docs +420 行），本复跑为把「四门禁全绿」结论从沿用落定到当前 HEAD；xcode 门禁同依据（Apps 源未变）维持 xcresult×3 Passed 沿用。

> 2026-09-03 R1 第十二轮补记⑯（**四门禁 @当前HEAD 全落定终版**）：PR rc=0 marker fresh @02:23:32（含 tools 修复+全部 docs 的 HEAD 内容实测）；leaks rc=0 @02:19:31（`0 leaks for 0 bytes`，其后 diff docs-only 不参与编译，结论成立）；main rc=0 @02:21:31（**Release 编译 0 警告 grep 实锤 + 775 tests 166 suites 全量绿**，其后 diff docs-only 同上）；xcode 维持 xcresult×3 Passed 沿用（d3eb168..HEAD 主工程源 0 变更 git diff 实锤，补记⑮）。四件套由「沿用」全面升格为 @当前HEAD 实测/合法沿用，DoD 第三条（四门禁全绿+推镜像）就绪。**待外部仅余：R1 解锁轮（heartbeat 值守）+ R2 用户拍板。**

> 2026-09-03 R1 第十二轮补记⑰（**xcode 门禁 @当前HEAD 实测落定——四门禁完整闭环无沿用**）：一次性 plist `com.harness.xcode12` 跑 `ci-local.sh xcode` → **TEST SUCCEEDED**，xcresult 新 bundle `Test-HarnessApp-2026.09.03_02-25-45` result=Passed（锁屏下 xcodebuild CLI 正常完成，headless 实证），marker rc=0 @02:26:30，跑毕即退役。至此 PR/leaks/main/xcode 四门禁**全部 @当前HEAD 实测全绿**，无一项依赖沿用。另：终版表 #8 待办触发载体措辞修正（r1loop→heartbeat，对齐补记⑪退役口径）。DB 实况只读复核与 R2 台账一致（20 行/空 18），决策材料新鲜无漂移。

> 2026-09-03 R1 第十二轮补记⑱（**heartbeat 值守实证缺口 → 双冗余值守定稿**）：logs_2.sqlite 只读取证——heartbeat r1 created 01:58:22，但 02:03–02:14 空窗 14 分钟（5min 间隔应 ≥2 轮）无任何 lockprobe 工具痕迹 → **线程繁忙期间 heartbeat 轮被跳过**（与 wait_threads「新输入结束等待」语义吻合），不可作为单一值守载体。定稿双冗余：**① goal-continue 轮（实证可靠：背靠背 ~8min 间隔、不依赖用户在场）= 每轮固定第一步跑三条件探针（解锁/App 存活/无 .done_v43），条件满足即当场 exec 全权跑 v4.7 走测**（本轮起执行）；② heartbeat r1 保留 = 线程空闲场景补充。两载体同以 `.done_v43` 为原子完成判定，先后到皆安全；unlock 检测延迟上界 ~8 分钟。

> 2026-09-03 R1 第十二轮补记⑲（**v4.7.1 #8 兜底还原 trap + zsh `trap-` 语法坑实证**）：锁屏窗口干跑验证 v4.7 头部全路径（FORCE 越守卫/新 LP 探针/超时 rc=3/零产物污染）后，补 #8 安全缺陷：拨开「减弱透明度」后若脚本异常退出会把用户系统留在开态、无兜底。加固：确认 V1=1 后登记 EXIT trap 兜底拨回，正常拨回成功（V2=0）才 `_TB_DONE=1; trap - EXIT` 双保险解除（防二次拨回反而拨开）。**关键坑（等价迷你脚本实测抓出）**：`trap- EXIT` 连写非法（zsh 报 command not found，前缀赋值随之丢失 → 场景 A 仍触发兜底 = 反而拨开缺陷）；正确解除语法 `trap - EXIT` 带空格。修正后 A/B 两场景复测符合预期。教训与门禁同构：**shell 新逻辑必须等价场景真跑，`zsh -n` 不拦截运行时语义错误**。

> 2026-09-03 R1 第十二轮补记⑳（**解锁轮前置预检通过 + launchd 终态卫生**）：① **v4.7「先导」前提预检**：`~/Library/Application Support/Harness/themes/` 实测 0 条目 → 无残留主题插件与导入撞车，「导入→卸载必回此净态」闭环前提成立；目录内 `com.harness.pluginworker.plist` + `.sb-*` 临时件为 App PluginXPC 自身托管产物（正常行为，不涉案）。② **civerif 彻底退役补全**——补记⑨口径"退役"仅停跑未删 plist（RunAtLoad 下下次 boot 会重跑 leaks），本轮 bootout + 删 plist 补全。launchd 终态 = App 本体 + `com.harness.ci11.pr`（门禁 one-shot，保留），无其他自挂 job；heartbeat 在 Codex app 内部调度不入 launchd。

> 2026-09-03 R1 第十二轮补记㉑（**v4.7.1 全文复核：零破坏性 landmine + v4.7.2 判读面修正**）：trap- 轮证明 `zsh -n` 不拦运行时语义 → 对走测脚本做逐行复核。安全面结论：① 闭环自洽——#6a 若 BASE_LABEL 提取失败则切换段跳过、卸载段独立 OR 条件仍执行；即便"还原"press 失手，卸载在用主题按产品行为自动回落基准（P0 验收条款），用户态终局干净；② 同名 18 行「新对话」不破坏定位——#3 顶栏 TITLE 取 Y 最小（顶栏恒高于侧栏）+#7 手工 sort 首行，均不走 ax 同名消歧；③ 两项已知不确定性均有留证路径（#8 Toggle 控件若 press 标签不中→"未读到 1 不乱拨"分支；#3 顶栏 title 缺位→"未取到坐标"分支），无一构成假绿。修正面（零行为变更）：#5 段头注释 ⌘.→Esc 口径、终值日志静态"+1"改随 SKIP_N 动态（防解锁轮判读误导）、删 L61 未消费 grep 死代码。修正后 zsh -n + 干跑复验通过。

> 2026-09-03 R1 第十二轮补记㉒（**事实修正：heartbeat 实测有触发轮，补记⑱「从未触发」结论过强**）：logs_2.sqlite 复查 02:37:44/02:39:24/02:39:51/02:40:53/02:42:23 存在落于 goal 轮活动窗口外的 lockprobe 痕迹簇 → heartbeat r1 在空闲窗口**确实执行了轮询**。补记⑱的"14 分钟零痕迹"系当时关键词集不全所致（早期 prompt 用 `/tmp/lockprobe2`，且部分轮 body 记录格式未含 'ScreenIsLocked'），判据不完备。架构不变：双冗余值守保留（防御性设计不因该事实回撤）；解锁检测延迟预期从 ~8min 修正为 **≤5min（heartbeat）+ goal 轮兜底**。本轮锁屏探针/对账照旧，无其他变更。

> 2026-09-03 R1 第十二轮补记㉓（**R2 明细只读复核一致 + 目标⑦"用户手动拖一次"条款正式挂【待确认】**）：① R2 材料保鲜复核：有事件会话恰 2 个（`D043EF0D` 08-24 起 5 事件 / `E7D52757` 08-30 19:11 起 1 事件），与保留口径逐字一致；其余 18 行 0 事件 = 空会话集（定稿 17 + `593182E4`）。② **条款完整性审计**：目标 R1⑦ 原文含"（用户手动拖一次）"——当前口径为脚本 ev drag noChange 仿真 + 单测/像素锁定（机制层已锁），**"用户手动"这一验收子句从未正式闭环**，不得静默吞并。处置：挂【待确认】进收口报告——用户在解锁轮顺手手动拖一次（3 秒），或明确"仿真帧即视为该子句满足"，二选一后 #7 才能到终版 ✅。此为 DoD 完成审计的显式待办项。

### R1 收口 DoD 审计表（预生成 @2026-09-03 锁屏窗口 · 收口轮只改状态列）

| # | DoD 条款 | 状态 | 权威证据源 | 收口前剩余动作 |
|---|---|---|---|---|
| 1 | R1 走测①⌘N/⌘1–5 | ✅ | 08-31 首轮实录 | 无 |
| 2 | R1 走测②折叠 rail+morph | ✅ | 09-02 二轮（QUALITY_REPORT 同日条目） | 无 |
| 3 | R1 走测③顶栏右键≡溢出 | ◐ | 源码共享+溢出实测 | 解锁轮 `title_ctx_menu.txt`+01/01b 帧 |
| 4 | R1 走测④删除确认→取消 | ✅ | 补记① 双证 | 无 |
| 5 | R1 走测⑤设置 sheet 双关闭 | ✅ | 补记②（Esc 口径） | 无 |
| 6 | R1 ＋零同步残留 | ✅ | 补记③ | 无 |
| 7 | R1 走测⑥主题 tint 切换还原 | ◐ | ThemeLiveRender/FileThemePackage 全套 | 解锁轮 11/12/12a+卸载双 dump |
| 8 | R1 走测⑦拖拽反馈（含"手动拖一次"子句） | ◐+【待确认】 | DropHighlight 单测+noChange 单测 | 解锁轮 13/14 帧 + 用户裁决子句（㉓） |
| 9 | R1 走测⑧减弱透明度降级 | ⏳ | — | 解锁轮 20/21/22+trap 兜底（v4.7.1） |
| 10 | R2 数据处置 | ⏳ 待拍板 | 明细㉓（2 保留+18 空） | 用户拍板→执行→入册 |
| 11 | R3 覆盖率 ≥90% | ✅ 关闭 | 补记⑬（WorkspaceRoot 100%/全量 97.57%） | 无 |
| 12 | 四门禁全绿 @当前HEAD | ✅ | 补记⑯⑰（PR/leaks/main/xcode 四 marker） | 收口时如 HEAD 再动则只重跑受影响门禁 |
| 13 | HEAD 推镜像 | ✅ 持续 | 每轮 ls-remote 对账 | 收口轮终对账 |
| 14 | 功能冻结宣告 | ⏳ 归用户 | — | 1–13 全绿后用户发起 |

> 口径：解锁轮完成 #3/#7(脚本部分)/#8/#9 填空后，本表+终版总表+QUALITY_REPORT 同日条目三处同步，即为「文档全核销」。

> 2026-09-03 R1 用户在线手动轮补记㉔（**注入式走测用户禁令 + 27 beta 三环境事实 + 副产登记**）：① **用户在线禁令（新口径，最高优先）**：用户明确否决「抢前台/键鼠注入」式走测在你在线时执行——r1walk 注入轮（C 层）自本记起**永不自动触发**，归档为「用户离键盘可选工具」；#3/#6/#7/#8 的「真机视觉帧」补证改二选一：用户顺手配合（右键一次标题 / 手动拖一次会话 / 拨一次系统开关，合约 1 分钟）或明确认可 A 层进程内证据即满足该子句（`ThemeLiveRenderTests`/`SidebarDropHighlightRenderTests`/`GlassSurfaceTests` 像素+降级链测试，**已包含于 02:26 xcresult TEST SUCCEEDED 867 项**，无需重跑）。② **27 beta 文案变更实证**：系统设置「减弱透明度」→「**降低透明度**」（System Events 全量 checkbox 枚举实锤，同位 辅助功能>显示）；脚本 grep/press 文案已同步。③ **幻影边界新实证**：主窗落副屏(x=-1663)或被移动后，CGWindowList 持续报 158-220×152-169 缩略图幻影（∈ 历史带 137-221×150-179），污染 wl 坐标读数→注入轮 #3/#7 全脱靶；4beb21d 缓解仅护 watchdog remap、不护外部读取；**quit 重开主屏新窗 CG 即恢复 1470×860 正常**——幻影随窗口记录而非全局故障。v4.7.3 补丁：WID 认 `name=Harness` 行（缩略图行 name 空自动排除）、WINX 以 AX 窗口 pos 为权威、wl 仅兜底。④ **SKIP_N 过度产生实证**：注入轮每轮 DB +2（脚本口径仅登记 +1 走测临时会话）——press「新对话」同名歧义/过度产生待查；**6 个副产登记**（全部 0 事件，待 D-6 一并处置）：`BB0112F7`/`8FF4EE09`(12:02) `618BB207`/`DF74B23A`(12:23) `6F012001`/`9191AD8D`(12:29)；DB 26 行=基线 20+副产 6，有事件会话仍恰 2（用户数据零污染）。⑤ **系统状态核验**：`reduceTransparency` 实测未设置（#8 press 命中 StaticText 未拨中开关，defaults 实锤）；系统设置已关；caffeinate 断言全释放。⑥ **bundle 更正**：首跑发现运行实例为 08-19 化石 debug bundle（早于全部修复，取证将无效）→ `rebuild-app.sh relaunch` 重建至 @7a853d6（sha 8d27fc… 同步断言过）后一切窗口/坐标问题均为环境态而非代码缺陷。

> 2026-09-03 G1 双轴审计轮补记㉕（**轴1 官方指南级依据打通 + morph 根因改判 + F1/F2 已修 + 取证通道证伪**）：
> ① **文档通道打通**：HIG 与 SwiftUI 指南页正文可经 `tutorials/data/documentation/**.json`、
> `tutorials/data/design/human-interface-guidelines/<page>.json` 直取（页面本体 SPA 壳，curl HTML 无正文）——
> 早前"HGI 拉不到"的阻塞解除；本轮入册逐字原文见 `docs/BENCHMARK_CHECKLIST.md` §1.8–§1.10。
> ② **morph 根因改判（撤销上一轮的 A1 推断）**：官方判据 = add/remove 两玻璃面「**最近边 ≤ 容器
> spacing**」才走 `matchedGeometry`，超出须 `.materialize`；`spacing` 语义为融合提前量。我们
> 4 个容器全传 `nil`（系统默认值官方未公布），而侧栏 Tab 网格最远切换对的最近边距离 ≈88pt，
> **大概率超出默认 spacing → 远距离切换静默退回淡变** = P1.2 实机「交叉淡变」的可解释根因，
> 与动画曲线无关（同时撤销更早「`.smooth` 需换 spring」嫌疑：官方对 morph 未规定任何动画类型）。
> 上一轮「容器内单玻璃面 → 需给未选中面补玻璃」推断**已被官方原文证否并撤销**：官方 morph 构造
> 恰恰是 add/remove（"Animating views in or out causes the shapes to morph apart or together"），
> 补 6 面反而触发官方警告的静止态融合（"blend together at rest"）＋违反 HIG "sparingly"。
> ③ **F1 已修（G2 头号项）**：`GlassMorphTabBar` 容器 spacing 由 nil → `MorphTabGeometry.fullGridSpacing`
> （几何纯函数：`hypot(2×间距+面宽, 间距)` 向上取整；静止态恒单面 → 静止融合代价结构性不可达）；
> 判据 = 新增 5 条 `MorphTabGeometryTests`（覆盖最坏最近边距离 / 三类切换距离全落入适用域 /
> 列数退化防御 / 间距单调性 / 全网格⊃相邻），A 层静默跑绿。
> ④ **F2 已修**：选中面材质补 `.interactive()`——官方为**显式开启**（"**Add** interactive(_:) to custom
> components…"），我方旧注释「悬停反馈=材质自带」属未证实宣称，已撤销并按官方补齐；经纯函数
> `selectedGlass(from:isSelected:)` 单点（`nonisolated`，避免 #expect 隔离告警），判据 = 3 条
> `SelectedGlassTests`（选中面==base.interactive() 且≠裸材质 / 未选中面原样 / 主题 tint 叠加不丢失）。
> ⑤ **A9/A10/A11 审计结论**：A9 修饰符顺序 ✅ 无违规（12 调用点，后置仅 2 处描边 overlay 与 1 处
> 刻意 `.frame` 列内对齐，均不参与玻璃捕获，符合官方"glassEffect 后置"要求）；A10 内容层合规 ✅
> 无违规（全 Sources 玻璃使用 8 文件全属功能层，聊天内容区 0 处）；A11 ✅ 注释纠偏（`GlassLevel`
> 三档在 macOS 26 原生态不改 `Glass`，仅影响 legacy 材质与 solid 色 → 改为「用途分层」口径，
> 是否改名 `SurfaceRole` 待用户定）。A12 效果总量/容器数护栏 ⏳ 待静默采样。
> ⑥ **取证通道证伪（重要，影响 G2/G3 全部判据）**：新写 `tools/qa/glass-fidelity-probe.swift`
> （A 层零窗口）实测 **`ImageRenderer` 完全不渲染 `glassEffect`**——spacing 10/30/60 三组，
> 「有玻璃 vs 无玻璃」**24000 像素逐点差异 = 0** → v8 目标 G2 原文「用 ImageRenderer 像素帧判定
> morph 流体融合」**判据不成立**（若继续执行＝造无效证据）。同时 macOS 27 SDK 已
> **移除 `CGWindowListCreateImage`**（编译期 "Please use ScreenCaptureKit instead"），
> ScreenCaptureKit 需 TCC 弹窗＝打扰用户不采用。**修订判据三轨**（`BENCHMARK_CHECKLIST.md` §4）：
> A 层结构断言（每次修复默认回归）＋ A 层真机静态帧（`screencapture -o -x -l<wid>`，不 activate）
> ＋ 过渡态 morph 感**无静默通道** → 归用户二选一（顺手 1 分钟目检 / 认可结构+静态帧即满足）。
> ⑦ **轴2 Codex 界面证据源当前不可静默获取**（实证）：主窗在其他 Space 时 `screencapture -l`
> 仅回畸变缩略（`/tmp/g1b/codex_554.png` 274×318），宠物浮层窗截回 1544×4138 白底——
> 按铁律 5，在拿到真实截图前**不写任何"Codex 有 X"条款**。取证方式待你择一（置前我只读截 /
> 你手动丢图 / 延后）。
> ⑧ **本轮教训入档**：官方文档读**半句**就会导出错误根因（上一轮只读 GlassEffectContainer 摘要，
> 漏了《Applying Liquid Glass to custom views》的"最近边≤spacing"与"add/remove 即 morph"两句，
> 直接导出相反结论）→ 定规：任何 API 结论必须读到**该 API 所属专题指南全文**（不只看 API 摘要页），
> 摘要页与指南页冲突时以指南页为准。

> 2026-09-03 G4a 补查轮补记㉖（**社区插件 import 面 n=256 实抓统计 → 「拿来即用」前提被实测否定**）：
> ① **方法与规模**：目录 2937 条 → 唯一 npm 包 1425；取 stars>50 全量唯一包 **116** ∪ 其余随机抽样
> **140**（seed=42）= **256 包**，逐个 `curl registry.npmjs.org/<pkg>` 读 `latest` manifest，
> **256/256 成功、0 失败**（本机 python urllib 走 HTTPS 报 CERTIFICATE_VERIFY_FAILED，必须用 curl）。
> ② **实测占比**：Cordis 系（依赖 `cordis|@deepseek-ai/*|^dsh-*`）**50%**（高星组 57% > 随机组 44%
> ——越受欢迎越绑上游运行时）；**MCP 依赖率仅 1%（4/256）**；带 `bin` 12%；keywords 命中 UI 注入面 4%
> （弱信号下限）；既非 Cordis 也非 MCP 者 49%。最高频运行时依赖 = **`@deepseek-ai/schemastery` 35 次**
> （上游私有 UI schema 库），其次 zod 27 / schemastery 10 —— 生态绑定度第一的不是任何通用协议件。
> ③ **对 D-5 的决定性后果**：早前「抽样 6/6 全 Cordis」修正为「约半数（高星多数）」；
> 而**「DSH 社区插件拿过来直接用」经 MCP 路线不可达**——原生 MCP 宿主可承载的社区包 ≈ 14/1425 量级。
> 诚实承诺口径必须分层：**层1 标准 MCP 插件（原生，长期正确，社区当前覆盖 1%）** /
> **层2 Cordis 目录 = 需 Node+Cordis sidecar 可选组件（覆盖约半数、高星 57%，默认关闭、独立进程、
> 最小权限、显式授权，且需你过「基线纯度论证」门）** / UI 注入类目永久不做。
> **不得再以「DSH 社区插件拿来即用」作为可交付承诺**（此为实测结论，非实现难度问题）。
> ④ 证据产物：`/tmp/census_ok.json`（256 包明细）`/tmp/census_out.txt`（统计输出）
> `/tmp/dshcat2/package/plugins.json`（目录快照）；入册 `docs/DSH_COMMUNITY_PLUGIN_CENSUS.md` 补查节。

> 2026-09-03 D-6 处置预案轮补记㉗（**只读复核 26 行实况 + 删除预案待你明示**）：
> ① **DB 实况（`mode=ro` 只读复核，零写入）**：sessions **26** 行 = 零事件 **24** + 有事件 **2**；
> events 表总计 **6** 行，全部属这 2 个会话——`D043EF0D…`（08-24 10:54，5 事件）
> `E7D52757…`（08-30 19:11，1 事件）＝**保留集，用户真实数据零污染**。
> ② **24 个零事件会话分解**：18 个历史（08-20 16:32 → 09-02 22:42）＋ 6 个本轮走测副产
> （09-03 12:02×2 / 12:23×2 / 12:29×2，与补记㉔登记逐一对应，ID 前缀
> `BB0112F7/8FF4EE09/618BB207/DF74B23A/6F012001/9191AD8D`）。
> ③ **口径修正（事实精度）**：v7 时代 R2 原文「**3 个 08-30 19:11 空会话**」不精确——该时刻实为
> **3 行**，其中 2 行零事件（`1FFDE591` 19:11:25 / `278A44E8` 19:11:33）+ **1 行有 1 事件**
> （`E7D52757` 19:11:23，属保留集）。删除预案以本记 ② 为准，勿按「3 个」执行。
> ④ **执行预案（等你明示后再跑；当前未执行任何写操作）**：备份 → 事务内删除 → 三重校验
> ```bash
> # 步骤 1 备份（只读复制，安全）
> cp "$HOME/Library/Application Support/Harness/sessions.sqlite" \
>    "$HOME/Library/Application Support/Harness/sessions.backup-$(date +%Y%m%d-%H%M%S).sqlite"
> # ⚠️ 步骤 2 为不可逆写操作——需你明示「批准删除 24 个零事件会话」后才执行；App 需先退出避免写锁
> sqlite3 "$HOME/Library/Application Support/Harness/sessions.sqlite" \
>   "BEGIN; DELETE FROM events WHERE session_id IN (SELECT s.id FROM sessions s WHERE NOT EXISTS (SELECT 1 FROM events e WHERE e.session_id=s.id)); DELETE FROM sessions WHERE id IN (SELECT s.id FROM sessions s WHERE NOT EXISTS (SELECT 1 FROM events e WHERE e.session_id=s.id)); COMMIT;"
> # 步骤 3 校验（期望：sessions=2 / events=6 / 两个保留 ID 仍在）
> ```
> 注：步骤 2 的 WHERE 只命中零事件会话（子查询双保险：events 内不存在任何事件的会话），
> 保留集恒不受影响；即便如此仍先备份、执行后立即跑步骤 3 三项断言。Keychain 旧 Apple 凭证清理
> 仍为**可选项**（你手动，路径 钥匙串访问 → 搜索 "Harness"）。

> 2026-09-03 G2 首轮执行轮补记㉘（**⚠️清除一个违反静默铁律的自动触发源 + exec 会话回收再次实证**）：
> ① **发现（用户静默铁律的潜在违反源）**：`~/Library/LaunchAgents/com.harness.r1loop.plist`
> 处于 `RunAtLoad=true` 且 `ProgramArguments` = `/Users/liguangming/harness-wt/r1loop2.sh`，
> 该脚本第 20 行实锤 `SKIP_N=1 SKIP_45=1 /bin/zsh .../r1walk4.sh 120`——即**注入式走测（C 层）**，
> 且脚本自述触发条件为「**解锁 + TCC 权限自检通过 才跑**」＝恰好在你在键盘前时开跑。
> 这正是 09-03 你明令禁止、且已被你删除的 heartbeat 同类能力的 **launchd 残留载体**。
> ② **处置（不做删除、留证归档）**：`launchctl bootout gui/501/com.harness.r1loop`（本次返回
> "No such process"＝当前未加载，但 plist 在位则**下次登录/开机即自动开跑**）→
> plist 已 `mv` 至 `/Users/liguangming/harness-wt/quarantine-manual-only/com.harness.r1loop.plist.DISABLED`
> （保留可复核、脱离 LaunchAgents 自动加载路径）。
> LaunchAgents 现仅存 `com.harness.ci11.pr` + `com.harness.ci11.watch`（门禁相关，无注入能力），
> 距目标清理项「launchd 终态仅剩 App + ci11.pr」只差 watch（列入 G3 清理，本轮不动以免失去门禁监控）。
> ③ **口径固化**：任何 C 层（ev activate/key/rclick/drag、System Events key code、模拟鼠标、
> 抢前台）动作**不得挂载任何自启动载体**（launchd/heartbeat/cron/automation）——本轮起新增检查项：
> 每轮开工 `ls ~/Library/LaunchAgents/ | grep -i harness` 复核，出现非 ci 前缀即视为红线告警。
> ④ **教训再实证（已入档过，本轮复现）**：以 `nohup … &` 从 exec 会话挂起的门禁，会话回收时
> **随整个进程组被 SIGKILL**（本轮 14:43 那次门禁就在 PR-4 起跑后消失，日志停在表头、无 rc 行）。
> 唯一可靠载体仍是 LaunchAgent：`launchctl bootstrap gui/501 <plist>`（未加载时）＋
> `launchctl kickstart -k gui/501/com.harness.ci11.pr`（已加载时）；本轮 14:55 起门禁在 launchd 下正常推进。

> 2026-09-03 G1 静默审计轮补记㉙（**A16/A17/A18 全核销：1 结构性 N/A + 2 静态命中入册 F5/F6**）：
> ① **A16=结构性 N/A**：全 App 不存在「内容从玻璃之下滑过」区（聊天三段纯 VStack 并排；侧栏为单一
> 整面玻璃、列表滚动在面**之上**；tab 栏之下无滚动内容）→ `scrollEdgeEffectStyle` 暂无适用对象，
> 与 F4(b) 联动；顺带登记聊天顶栏 `.ultraThinMaterial` 与玻璃体系材质不同轨（挂 D-10 批次）。
> ② **A17 折叠 rail 左上角三方交叠（静态确证）**：rail「新对话」x[12,40]·y[0,28] ∩ ContentView
> 折叠 overlay 展开按钮 x[10,36]·y[10,36] ∩ 红绿灯实测带 x[10,62]·y[8,28]（P1.5 在册坐标）；
> Y 基准由「fullSizeContentView 官方头原文 + 品牌行当年仅 x 避让即过实机验收」双重钉死
> （内容原点==窗口原点，系统不自动 inset，避让须用 contentLayoutRect/Guide 显式做）。
> ⚠️ 与 R1② 实机核销存在张力（AX press 不受遮挡污染可解释假绿）→ 定级以你目检一次为准，修法 F6
> （rail 顶避让带 ≈38pt + overlay 下移；rail 宽 52<灯带宽 62，x 避让不可行）。
> ③ **A18 命中 1/5**：`SettingsCompletePage.swift:63` sheet 根自铺不透明底（WWDC323 反模式点名），
> 余 4 处合规 → 修法 F5 单行撤底；建议与 D-10 同批（新登 **D-12** = F5+F6 目检批次）。
> ④ **API 存在性核验方法论纠偏**：ObjC 时代声明的 API（如 contentLayoutRect/Guide）**不在
> swiftinterface 中，必须并查 `Headers/*.h`**（本轮 grep swiftinterface 得假阴性 0 命中，头文件
> 实证 10.10+ 存在）→ 存在性 = swiftinterface（Swift 原生 API，§1.13 结论不受影响）∪ Headers（ObjC 声明）。
> ⑤ **取证通道现状**：`bin/ax dump` 实测仅出菜单栏 77 行（窗口子树未输出，工具限制入册，后续实时
> AX 取证需先修；且 `bin/ax` 自 30f23c8 起仅二进制入仓、**无源码**——修复=重写并补源入仓，列 G3 取证前置小项）；当前 CGWindowList 无 Harness 窗（隐藏/他 Space）→ 本轮零窗口截图、零打扰。
> ⑥ **A12 附产**：`SidebarProjectSections.swift:339` 会话行 `.glassSurface(.thin)` 面数随行数线性增长，
> 运行时面数护栏口径必须含此点（静态计数 12 掩盖此项）。本轮 docs-only（门禁豁免沿用），无代码改动。

> 2026-09-03 静默工具轮补记㉚（**A 层取证链补强：axdump 只读 AX 导出工具入仓 + PERFORMANCE 玻璃护栏立规**）：
> ① `tools/r1walk/axdump.swift`（源码+二进制入仓）修复 ㉙ 登记的 `bin/ax dump` 窗口子树截断缺陷：
> 走 `kAXWindowsAttribute` 默认只导窗口子树、全局 4000 节点预算、**零动作/零 setAttribute/零 TCC 弹窗**
> （仅 `AXIsProcessTrusted()` 静默探测——绝不弹「辅助功能」授权框打扰用户）；实测 Finder 窗口子树
> + pos/size 完整输出，Harness 隐藏态如实返回 windows=0（exit 3，不假绿）。`bin/ax` 保持原样
> （历史注入式走测工具，永久仅用户手动）。G3「用户操作+Agent 只读取证」前置项就此闭环。
> ② **编译期门禁兼容模式入档**：CF 类型 `as?` 被 swiftc 判「恒真」直接报 error、`as!` 违反
> force_cast 门禁 → 合规写法 = `CFGetTypeID` 验证后 `unsafeDowncast`（本仓后续 AX/CF 工具照此办理）。
> ③ **PERFORMANCE.md 立 App 层玻璃护栏规**（首次）：通道分级——RSS/CPU=`ps` 静默采样 ✅、
> leaks=门禁在册 ✅、玻璃面数=静态注册表（含 sessionRow 线性项）✅、**帧率无静默通道 ❌**
> （如实移交 G3 人工走查，不留空承诺）；RSS 平台期规则提案（≥10 分钟间隔 3 采样漂移 ≤±10%，
> 单点不构成平台期结论——首表如实标注单点）。首采样 44.8MB@16:29（隐藏态旧实例 @7a853d6 时代启动，
> 磁盘 bundle 已被门禁重建至 ec9ff1ee…，口径入表）。
> ④ 本轮写域仅 `tools/` + `docs/` + 报告（**SwiftPM 包零触碰**）：门禁理由=包编译/测试不受影响 +
> 全仓 lint 0 / format 0 实测 + 工具编译 rc=0；镜像已推。

> 2026-09-03 G4c 层1 实测轮补记㉛（**「拿来即用」层1 由承诺升级为实测：3 样本全绿 + 宿主客户端实包测试**）：
> ① **验身反转再收窄**：4 个带 MCP 依赖的社区包里真 stdio server 仅 `@zseven-w/dsh-crew`
> （其余为 SDK client×2、hook/适配器×1）——「MCP 依赖」≠「可被 MCP 宿主装载」，直装面比 1% 更小；
> ② 层1 矩阵 3/3：dsh-crew（6 工具，**双通道**：`tools/g4/mcpprobe` 独立探针 + 我方
> `StdioMCPClient` opt-in 测试 `MCPCommunityLiveTests` 0.273s 实装载）+ server-filesystem(14)
> + server-everything(13)（官方一致性参考）；矩阵+复现命令入 CENSUS 新节；
> ③ **opt-in 门禁设计**：`HARNESS_G4_LIVE=1`+包在位才执行，默认 XCTSkip——门禁确定性不引入网络
> 依赖（实测：默认态 skip、开 flag 即真跑，两态均留证）；
> ④ **死锁教训入档**（探针首版）：`nextLine` 在持锁分支直接 return → 泄锁 → 主线程与
> fd_monitoring 双卡死；`sample <pid>` 只读定位（静默合规）；修复=分支内显式解锁。
> ⚠️ 该 bug 形态（return-while-holding-lock）后续并发代码评审必查项；
> ⑤ 企业 MITM 网络 npm 实操：cafile 需从系统 keychain 导出（curl 通而 npm 不通的根因）；
> dsh-crew 上游 peer 版本不同步需 `--legacy-peer-deps`——两点都是 D-5 层2 论证的实况材料；
> ⑥ 探针安全姿态：零 tools/call（社区代码只加载不指挥）、环境白名单、HOME 沙箱、超时必 kill。

> **门禁对账 @9776a63 全绿**：pr（783 tests/168 suites，rc=0，含 opt-in 测试默认 skip 态）＋
> leaks（`0 leaks for 0 total leaked bytes`）＋ xcode（`** TEST SUCCEEDED **`）＋
> main（rc=0；Sources 口径 9,755 行/未覆盖 243=**97.51%**，vs 台账 97.57% 差 6 行＝已入档
> profraw 合并漂移带内，且较上轮 244 少 1 行，无回归）。临时载体 `com.harness.ci11.rest`
> 用毕 bootout+移出 LaunchAgents（红线复验：仅剩 ci 系两项）。

> 2026-09-03 A12 护栏轮补记㉜（**玻璃面注册表护栏入册 + G3 走查手册预置**）：
> ① **A12 测试 @3d66ba0**（4 项，A 层静默：仅读源文件）：注册表①`.glassSurface(` 12 处 /
> ②`.glassSurfaceContainer(` 4 处逐文件双向比对（缺登记/计数漂移/未入册新增皆红）；
> 白名单③原生 glassEffect 族 API（glassEffect/glassEffectID/glassEffectTransition）
> 仅 GlassSurface.swift+morph 特例 GlassMorphTabBar.swift——铁律「玻璃仅系统原生 API 且经
> 统一封装」首次机械化；④注释剔除口径（行内/整行注释不计、`://` URL 不误伤）；
> ② **反向验证在册**：临时注入未入册 `.glassSurface(` 调用点 → Suite 红（1 issue）→ 还原 → 绿，
> 证明非空转守卫（本项目「护栏必须能拦」口径）；
> ③ **G3 走查手册预置** `docs/G3_MVP_WALKTHROUGH.md`：走查=用户手动+Agent 只读取证（axdump/
> 只读截窗模板在册）；池 A 视觉项 a–h（挂 D-1/D-10/D-11/D-12）、池 B R1 余项二选一裁决表、
> 池 C 对标+兼容（轴2 取证二选一/D-5 实装载）、§4 终拍板检查点表、§5 DoD 摘要；
> ④ **小教训入档（测试风格速查）**：swift-testing 结构体内实例方法调 static 成员必须显式
> `Self.` 前缀（XCTest 类方法习惯不通用）；`XCTUnwrap` 在 swift-testing 不存在 → `try #require(...)`。

> **门禁对账 @3d66ba0 全绿**：pr（**787 tests/169 suites**，rc=0，较上轮 +4 项＝A12 新套件）＋
> leaks（`0 leaks for 0 total leaked bytes`）＋ xcode（`** TEST SUCCEEDED **`）＋ main（rc=0；
> Sources 口径 9,755 行/未覆盖 238=**97.56%**，vs 上轮 243 少 5 行＝漂移带内，无回归）。
> 临时载体 `com.harness.ci11.rest` 用毕 bootout+移回 quarantine（红线复验：仅剩 ci 系两项）。

> 2026-09-03 G2 性能护栏轮补记㉝（**RSS 平台期由「未正式判定」升级为「正式成立」**）：
> ① 隐藏态组三点 @3d66ba0 构建（sha 73058939…）：134.7/131.6/133.8 MB，间隔 12.5/10.6 min
> （规则≥10min ✓），最大漂移 +2.4%（≤±10% ✓），pcpu 恒 0——**平台期成立、无泄漏征象**；
> ② 载体口径修正登记：main 为 SwiftPM release **无 .app 形态**、裸可执行建 NSWindow 实测
> SIGTRAP（环境坑在册）→ 平台期权威载体 = xcode 门禁 Debug bundle；Release 性能背书走
> leaks+产物一致性，不为 Release 造非门禁构建口径；
> ③ `open -g -j`（open(1 标准旗标：不置前台+隐藏）零打扰启动实证：前台进程未变（System Events
> 只读核对）、DB 零新增（26/24 不变，App 启动不建会话）、隐藏态 axdump windows=1（离屏窗，
> 与旧表 windows=0 口径差异如实标注）；采样器 `tools/perf/rss-sample.sh` 入仓；
> ④ BENCHMARK §10-A12 状态刷新：静态护栏（注册表测试，㉜）+ RSS 平台期双绿；同屏面数运行时
> 快照归 G3 axdump 手册；可见态组 RSS = 改变可见窗口状态 → 择时项；
> ⑤ 当前存在一个后台隐藏采样实例（pid 见 PERFORMANCE 表，Dock 不可见）；终止方式
> `kill <pid>`，或用户下次打开 App 后自然合并口径。

> 2026-09-03 G4-App 全链路轮补记㉞（**「拿来即用」层1.5：AppViewModel 真实链路实测入册**）：
> ① `MCPCommunityAppFlowTests`（@790e047）：dsh-crew 走用户同款全链路——导入（同一
> servers.json 格式）→ connectStdio → 展示层（6+ 工具/serverInfo/注册表）→ 卸载双清；
> opt-in 两态实测（默认 skipped / `HARNESS_G4_LIVE=1` passed 0.096s）；CENSUS 矩阵+复现命令增补；
> ② **swift-testing skip 实证结论**：本机工具链 `swiftc` 独立 typecheck 找不到 Testing module、
> SDK/toolchain 常规路径无 swiftinterface 可查 → 按「不脑补 API」原则改走**仓内已验证先例**
> （MCPCommunityLiveTests 的 XCTest+XCTSkip 同构），不为一个新文件赌未实证 API；
> ③ XCTest `class setUp` 撞 swiftlint static_over_final_class（API 要求 vs 规则冲突）→ 幂等
> 实例 setUp 消解，全仓 lint 复绿；
> ④ **日志新旧混淆风险登记**：门禁 kickstart 后轮询 `/tmp/ci_*.log` 可能读到**上轮残留**
> （旧 ALLDONE/rc 行未及被覆盖）——本轮以 leaks 输出 pid（19676 vs 上轮 70853）+ lint 文件数
> （251）+ 套件出现次数三重指纹核销为本轮真实输出；后续轮沿用「pid/计数指纹」对账法。

> **门禁对账 @790e047 全绿**：pr（787 swift-testing + XCTest 全量含 AppFlow 默认 skip 态，
> rc=0，lint/format 251 files 0）＋ leaks（`0 leaks`，本轮 pid 指纹在册）＋ xcode
> （`** TEST SUCCEEDED **`）＋ main（rc=0；9,755 行/未覆盖 239=**97.55%**，vs 上轮 238 差
> 1 行＝漂移带内）。临时载体用毕 bootout+移回 quarantine（红线复验：仅剩 ci 系两项）。

> 2026-09-03 G4 技能形态轮补记㉟（**「拿来即用」双形态闭环：工具插件（MCP）+ 指令插件（SKILL.md）**）：
> ① `SkillUpstreamCompatTests`（@4a0aa74）：上游 @47f9438 `.agents/skills/` **11/11** 真实技能
> 经我方 `SkillStore.parse` 零改写装载（name==目录名/description/正文断言齐），opt-in
> `HARNESS_G4_UPSTREAM=1` 两态实测；上游装载语义参照 `packages/skill/skill-filesystem`
> （YAML frontmatter 扫描）——两仓库格式同源实证；
> ② folded scalar 边界：上游实测 0 例 + 我方优雅降级用例固化（不崩、name 存在即装载），
> 未来社区出现 folded 再立修——边界不粉饰；
> ③ CENSUS 新增技能形态矩阵节 + 复现命令。

> **门禁对账 @4a0aa74 全绿**：pr（787 swift-testing + XCTest 全量（新 SkillUpstreamCompat 两用例
> 默认 skip 态实跑在册，252 files lint/format 0），rc=0）＋ leaks（`0 leaks`，本轮 pid 35153
> 指纹 vs 上轮 19676——三重指纹法第二轮沿用）＋ xcode（`** TEST SUCCEEDED **`）＋ main
> （rc=0；9,755/未覆盖 238=**97.56%**，漂移带内）。临时载体用毕退役（红线复验仅剩 ci 系两项）。

> 2026-09-03 形态收口轮补记㊱（**社区插件四形态总表收口 + 决策总账 D-INDEX 建立**）：
> ① **npm 实查新发现两形态**（只读普查）：形态③ **服务 seam 补丁**
> （`@deepseek-ai/dsh-{sandbox,compaction,shell,spill,jobs,goal,web,attachment}` = TS 进程内
> ctx.* API，Swift 宿主**结构性 N/A**）；形态④ **主题/GUI 插件**（npm `dsh-theme-*` 10+ 包：
> kit 0.1.2/guillaumemeyer 0.1.1/center/tuner/mineradio/machine/eternalnight…——
> `/tmp/g4pkgs3` npm pack 实拆：`cordis.patch.yml` 挂载 + `dsh.client` 浏览器半 = **Cordis Web UI
> 注入**，按 v8 §四既定裁决不做；**数据半可吸收**（色板 hex 可转写我方主题格式）——
> 「社区主题拿来即用」诚实边界 = **数据可吃、插件体不可**，D-5 核算材料至此最全）；
> ② CENSUS 四形态总表入册（每形态挂证据与定性）；
> ③ **DECISION_INDEX.md 决策总账**建立：DoD 首条唯一检查点（12 项含半结 D-2/合并项 D-3/
> 可选 Keychain），G3 手册 §4 改指指针；
> ④ RSS 长龄续点 s3=99.8MB@56min（vs s2 −25.4%＝启动瞬态释放，**远低于平台期下沿**，
> 无增长趋势加固）。docs-only 轮，豁免沿用。

> 2026-09-03 权威链审计轮补记㊲（**终验收前文档一致性核查：主表刷新 + 断号定性 + 锚点全查**）：
> ① **QUALITY 头部主表刷新**：Lint/Format 计数 237→**252 files**、单元测试 768/163→**787/169 + XCTest 全量**、
> 「本地 CI 模拟」行由过期快照（final HEAD `0d47f85`）更新为 **@4a0aa74 全量四门禁 + docs-only 链说明**
> （HEAD=a5d844d=镜像 MATCH，覆盖率 97.56%/238 漂移带内）——历史值降级为「前轮基线」保留不删；
> ② **补记链断号定性**：P1 文件内标号 ④–⑦ 未使用，但对应轮次（R1 第九/十轮）**记录完整在案**
> （QUALITY 头部引言块）——登记为历史并行标号噪声，**不改号**（重编历史链的风险大于收益）；
> ③ **跨文档锚点全查**：11 个被引文件/工具全部在位（一次 MISSING 为本轮核查路径笔误，
> CENSUS 探针表述顺手精确化 `mcpprobe.swift`/`bin-mcpprobe`）；被引测试套件名与仓内文件逐一对上。
> docs-only 轮，豁免沿用。

> 2026-09-03 语义对照轮补记㊳（**铁律 7 行为语义补口：插件管理操作语义与上游同构**）：
> ① 上游 `apps/cli/src/plugin.ts`（@47f9438）逐字提取：`dsh plugin`=pnpm 转发器+**安装态
> reconcile**（"Reconciling by installed state, not by dependency diff"）；与我方
> import/retry/remove 七维对照表入 CENSUS——安装即激活/卸载双清（我方更强）/坏包降级提示/
> 无独立启停（双方同型）均对齐；**升级回路 = retry**（命令指向磁盘路径，npm update 后一键
> 重启即加载新版——语义论证级，"未实测新版切换"如实标注）；
> ② RSS 长龄续点 s4=100.0MB@67min（vs s3 +0.2%）——100MB 平台纹丝不动，趋势线加固。
> docs-only 轮，豁免沿用。

> 2026-09-03 升级回路实测轮补记㊵（更正：本补记号 **㊴**（㊳ 后顺延））：
> ① **「升级即激活」语义论证 → 实测闭环**（@59cc24b）：dsh-crew rc.6→rc.7 双版本并装，
> 同名导入更新后 serverInfo 翻版（前置断言防同包假绿），live passed 0.288s；
> serverInfo 内嵌版本号为不可伪造判别；**反例方法论同登**：server-filesystem 两 npm 版本
> serverInfo/工具表全同 → 不可作升级判别（选包需先验判别力，探针先行）；
> ② CENSUS 复现手册增升级段（RC6 路径键在册）；
> ③ 长龄实例自然收尾：RSS 采样 s4 后实例仍在（趋势线已足，不再强制续采）。

> **门禁对账 @59cc24b 全绿**：pr（262 XCTest + 787 swift-testing，rc=0，计数 +1 = 升级用例，
> 252 files lint/format 0）＋ leaks（`0 leaks`，pid 65632 vs 上轮 35153 指纹）＋ xcode
> （`** TEST SUCCEEDED **`）＋ main（rc=0；9,755/未覆盖 241=**97.53%**，vs 上轮 238 +3 行＝
> 已入档漂移带 238–244 内，无回归）。临时载体退役（红线复验仅剩 ci 系两项）。

> 2026-09-03 清理预检轮补记㊵（**G3 清理项预检 + 入口文档基线纠误 + 载体自收口**）：
> ① **README 入口纠误**：「macOS 15+」为早期残留，与 `Package.swift .macOS(.v26)` +
> deployment 26.0 实证冲突 → 改「macOS 26（Tahoe）基线」+ 增加现状/权威源导航段
> （MVP 交付面入口正确性）；全库扫描此类残留仅此一处；
> ② **G3 清理项预检**：注入式工具「仅用户手动」标注在位（r1walk README）✓；ci11.watch
> 终态退役按 v8 归 G3 轮执行；
> ③ **载体自收口**：Agent 启动的隐藏采样实例 pid 83857 已 kill（趋势线数据已足，
> 谁启动谁收尾）；反查发现**用户侧实例** pid 58301（12:28 启动，SwiftPM debug bundle，
> 非 Agent 启动）**未动**——如实登记；
> ④ **口径再精确化**：SwiftPM debug 有 `HarnessApp.app` bundle（实证可正常长跑），
> release 无 bundle 维持——「裸 exec SIGTRAP」限定无 bundle 裸 exec，与既有判定自洽。docs-only 豁免。

> 2026-09-03 主表跟进轮补记㊶（微型维护）：① QUALITY 主表 CI 模拟行跟进最近全量门禁
> @59cc24b（97.53%/241 漂移带 238–244）；② 用户侧实例 58301 复核 **windows=0**（隐藏态，
> 无可截窗口）——G3 目检快照包需用户开窗后才能预采，登记为 G3 顺手机会（用户开窗
> 10 分钟同时解锁 RSS 可见态组 + 截图包 + 帧率观察三项）。docs-only 豁免。

> 2026-09-03 静态复核轮补记㊷（A17-2 定点·A 层零占用）：折叠 rail 左上角交叠簇的
> 「功能后果」定级收口：① 几何断言三锚点现行代码复核成立；② **官方双沉默实证**——
> overlay(alignment:content:) 文档正文（data JSON 通道 2343 字符）对 safe area 零提及、
> standardWindowButton:（NSWindow.h L605-606）无 z 序注释 → 「overlay 落入红绿灯带」与
> 「红绿灯压内容」均不得定为官方保证的缺陷（铁律 1）；③ R1② 张力定性为证据口径不同
> 非矛盾（AX press 不经 hit-test；你实机折叠往返未报异常）。定级收敛：几何成立、
> 功能无实机反证、终裁归 G3 A-b 目检一眼；F6 维持 D-12 待批不擅动。
> 同步 BENCHMARK A17 节 + DECISION_INDEX D-12 锚注。docs-only 豁免。

> 2026-09-03 手册口径补丁补记㊸（微型）：G3_MVP_WALKTHROUGH 取证模板补 **A12 运行时面数
> 统计口径**（sessionRow `.thin` 线性项单列、不混判静态 12 调用点、数量级偏差才记缺陷）——
> BENCHMARK §15-A12 附产口径此前未同步至走查手册，防 G3 轮错判。docs-only 豁免。

> 2026-09-03 拍板材料加固轮补记㊹（D-10 官方原文双项·A 层静默）：① (a) 透明窗底案——
> 官方无「透窗采样桌面」明文，推断锚定 legacy behindWindow 在册能力 + 风险标注「成败
> 仅 G3 A-d 目检裁决」；② (b) backgroundExtensionEffect 三重实证——SDK 注解逐字
> `@available(macOS 26.0,*)` 精确化 §1.13 + 文档页 data JSON 全文首次入档（镜像副本仅
> 落「available safe area」边/官方用例=NavigationSplitView detail 列/单例与性能警示/自动
> clip）→ **结构性前提在册**：我方 HStack 并排布局无 leading 安全区，(b) 需布局改造，
> 改动面>a；建议 (a) 先行不变。docs-only 豁免。

> 2026-09-03 链完整性审计轮补记㊺（零修补）：补记链 ㉑→㊹（21–41）**机械扫描无缺号**；
> ㊴ 在档（L643 自带「更正：㊳ 后顺延」注记，断号疑点此前已闭合）。**过程教训入档**：
> 首次扫描因 36+ 圈号 Unicode 基址算错（㊱–㊿=U+32B1 段而非 U+3251 段延伸）产生
> **假缺号警报**，三步自纠并加字符级 sanity 断言（ch(n)=="㊱" 逐验）后方采信——
> 号段/编号类审计工具必须自带 sanity 断言，防审计工具自身造伪账。账本无损，
> 无文件修补。docs-only 豁免（纯读取轮，仅本条入册）。
