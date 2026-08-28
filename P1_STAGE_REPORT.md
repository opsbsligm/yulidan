# P1 Liquid Glass — 阶段报告（P1.1 全局玻璃化）

> 报告时间: 2026-08-28 14:10
> HEAD: `949759b`（镜像 swift-harness-backup.git 双端同步）
> 状态: **代码完成，四门禁全绿**；剩余 = 用户侧实机视觉走查（§四）

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

## 六、P1.2 解锁条件

- P1.1 验收通过（用户实机确认玻璃化正常 + 无交互回归）
- P1.2 范围（实施计划 §2）：Tab Morph 流动玻璃——侧边栏六分区头 `@Namespace` + `glassEffectID(id:in:)`（分段身份）+ `glassEffectUnion(id:namespace:)`（并集融合，**同 .regular 变体 + 同型 shape** 官方约束）+ `glassEffectTransition(.materialize)`；**禁 ZStack 滑块模拟**
