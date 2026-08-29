# P2 次要优化 — 阶段报告（P2.1 + P2.2 全阶段：设置完整页面 + 交互加固）

> 报告时间: 2026-08-28
> HEAD: `11152aa`（镜像 swift-harness-backup.git 双端同步）
> 状态: **P2.1 + P2.2 代码全完成，四门禁全绿**；剩余 = 用户侧实机走查（§五）+ 付费 Team ID 后的 SSO/iCloud entitlements 实机验收（非阻塞）

## 一、模块完成矩阵

| 子项 | 状态 | 证据索引 |
|---|---|---|
| P2.1.1 设置完整页面（7 卡片单页滚动） | ✅ | `Views/SettingsCompletePage.swift`（700×600 sheet；Apple 账号状态/iCloud 同步指示器/模型配置/MCP 服务/RAG 记忆/权限总览/主题切换入口）；入口 = SettingsView 头部横幅（`0e09868`） |
| P2.1.2 卡片数据源实证接线 | ✅ | 属性名全部实证后接入（accountService.state/.isICloudReady/.account、workspaceRouter.current、llmConfig.provider.displayName/.modelName、mcpServers.count、themeOptions/applyTheme/activeThemeSpec）；详细编辑跳转侧边栏设置 |
| P2.2.1 删除/归档/卸载确认弹窗 | ✅ | 会话删除：`onDelete (SessionRecord) -> Void` + 行级 `sessionToDelete` alert（`SidebarProjectSections`）；插件卸载：MarketplaceCard 确认后才 `onUninstall()`（`675f600`）；聊天顶栏删除/清空既有 confirmationDialog（P0 在案） |
| P2.2.2 iCloud 同步中/离线/冲突状态指示器 | ✅ | 冲突裁决 UI = `AccountSyncSection.conflictCard`（P0.1.4 在案）；设置内在线/离线行（P0 在案）；**本轮新增**：侧栏一眼指示器 `SidebarSyncHint`（纯逻辑 + 展开态行 + 折叠 rail 图标）+ 点击深链「账号与同步」+ AccountService 在线态 30s 轮询（`11152aa`） |
| P2.2.3 拖拽边界防护 | ✅ | 纯逻辑 `SessionDragPayload.resolution`：同项目/同全局落点 = `.noChange`（不落盘、不 toast）；`moveSession` `.noChange` 早退；**本轮补** AppViewModel 层专项 no-op 测试（状态不变 + 无 toast） |
| P2.2.3 权限异常引导 | ✅ | iCloud 权限拒绝 → `icloudDegradedLocal` → **本轮起**侧栏橙色提示行（原因 + 「点击重新申请」深链）进入主界面视野（此前仅设置页可见）；插件权限待决 = `NavPermissionBanner`（P0 在案）；API Key 缺失 = ChatTopBar 警告行（点击跳设置，P0 在案） |
| P2.2.4 右键菜单 | ✅ | 侧栏会话行（归档/删除确认）+ 项目头（重命名/归档/删除）P0 在案；**本轮新增**：ChatTopBar 会话标题 `contextMenu` 与溢出菜单共享同一动作集（`sessionMenuActions` 抽取，双入口同一动作；确认弹窗上提容器层共用） |

## 二、本轮变更清单（@11152aa，11 文件，+382/−40）

| 文件 | 变更 |
|---|---|
| `Views/SidebarSyncHint.swift` | 新建：`SidebarSyncHint` 纯枚举（resolve 状态机映射 + icon/tint/label/help）+ `SidebarSyncHintRow`（展开态行）+ `SidebarSyncHintIcon`（rail 图标） |
| `Views/SidebarSupportViews.swift` | `SidebarBottomBar` 加 `accountService`/`onOpenAccount`；设置行上方插入提示行 |
| `Views/SidebarView.swift` | 属性 + 展开/折叠双落点接线；含前次残留等价改动（删除回调 `$0` 透传） |
| `ViewModels/AppViewModel.swift` | `pendingSettingsSub` 一次性深链 + `openAccountSettings()` |
| `Views/SettingsView.swift` | `pendingSub`/`onConsumePendingSub` + onAppear/onChange 消费（已在设置 tab 再点按亦生效） |
| `ContentView.swift` | 侧栏/设置页接线 |
| `Views/ChatAreaView.swift` | ChatTopBar 标题 contextMenu + 动作集抽取 + 确认弹窗上提 |
| `Packages/Account/.../AccountService.swift` | 在线态 30s 轮询（激活期存在，deactivate 即取消） |
| 测试 ×3 | `SidebarSyncHintTests`（新建，7 用例）/ `AppViewModelProjectTests` +1（no-op 边界）/ `SettingsMenuModelTests` +1（深链导航） |

## 三、机制与铁律 1 注记

1. **在线判定源**：`NSUbiquitousKeyValueStore.synchronize()` 返回值（官方文档：同步尝试是否成功；网络不可达时失败返回 false）。30s 轮询周期为 P2 工程选择（指示器实时性 vs 同步开销权衡），仅 iCloud 激活期存在
2. **「同步中」口径简化**：`MetadataSyncService` 未暴露 publish-in-progress 状态（引擎内部无进行中出口，不脑补）→ P2 口径 = online/offline/connecting（connecting = ssoPending 流程中 + 激活后首探未返回的瞬态）
3. **降级 = 引导**：`icloudDegradedLocal(reason)` 经提示行携带原因 + 深链到「账号与同步」（`retryICloud()` 重新申请入口在案）
4. **本地模式零噪声**：`state == .local` → hidden（用户主动选择，无同步预期，不显示指示器）

## 四、门禁（@11152aa 四门禁全绿）

| 门禁 | 结果 | 日志 |
|---|---|---|
| PR | SwiftLint strict **0/259**、SwiftFormat **0/259**、**835 测试 177 suites 0 失败**（较 P1.4 基线 +9） | /tmp/ci_pr_p2_2b.log |
| main | Release build 0 警告 + 835/835 + 覆盖率 **96.10%**（Sources 口径 10,581 行，基线 96.12%/10,558 行，持平；+23 行 = 轮询代码）+ <90% 同基线 4 源文件（AppleSignInService 15.86% / LLMProvider 79.63% / NotificationService 82.89% / AppleCredentialStore 89.29%） | /tmp/ci_main_p2.log |
| leaks | **0 leaks**（MemProbe 500） | /tmp/ci_leaks_p2.log |
| xcode | **BUILD SUCCEEDED + TEST SUCCEEDED**（contactsd/AddressBook CoreData 报错 = 环境噪声，TEST SUCCEEDED 为准） | /tmp/ci_xcode_p2.log |

注：P2.1（`0e09868`）/ P2.2 确认弹窗（`675f600`）交付时已过 PR 门禁；本表 = P2 收口时的全量复核。

## 五、实机走查（用户侧，约 2 分钟）

1. **侧栏同步指示器**（需 iCloud 模式）：展开态底栏设置行上方出现「iCloud 同步：在线/离线」行；折叠 rail gear 上方出现云图标；断网 ~30s 内应变离线（本地优先文案）；本地模式下应**不显示**（无噪声）
2. **深链**：点按指示器 → 设置页应直达「账号与同步」子页（已在设置 tab 时再点按亦生效）
3. **聊天顶栏右键**：右键会话标题 = 与「⋯」溢出菜单同一动作集（置顶/附件/派生/复制/导出/重命名/清空/删除）
4. **拖拽 no-op**：把会话拖回其所在项目（或全局会话拖回全局区）→ 无任何变化、无 toast（静默 no-op）
5. **确认弹窗回归**：侧栏右键删除会话 / 插件市场卸载 → 均有二次确认（675f600 项）
6. **设置完整页**：设置页顶部横幅「打开完整设置」→ 7 卡片单页（P2.1）

## 六、完成度审计（P0 → P2 全阶段）

| 阶段 | 代码 | 门禁 | 实机验收 |
|---|---|---|---|
| P0 业务 MVP | ✅ 100% | ✅ | ✅ 用户 2026-08-26「P0 验收通过」 |
| P1 Liquid Glass（P1.1–P1.5） | ✅ 5/5 | ✅（每轮四门禁） | 🔄 用户侧走查清单累计 13 项未核销（P1.1×6 已按「继续推进」口径核销；P1.2×7 / P1.3×6 / P1.4×6 / P1.5×1 中的重叠项按单提交粒度核销——发现问题随时截图报障即可） |
| P2 次要优化 | ✅ 本表（含 P2.3 `17e9f22` 玻璃强度诚实闭环，2026-08-29） | ✅ 本轮复核（837 测试 0 失败 ×3 轮） | 🔄 §五 6 项 |

非阻塞尾巴（不改变完成度口径）：① 付费 Apple Developer Team → SSO/iCloud entitlements 实机验收（代码零改动，设计内优雅降级）——**2026-08-29 用户决定跳过挂起**（MVP 验收不以其为前置；ad-hoc 下 SSO 报 AS 1000 属设计内诚实文案；提供付费 Team 后可随时恢复该项验收）② GitHub Actions 远端（用户暂缓，ci-local 四模式本地模拟在案）③ macOS 27 beta 协作池调度停滞/幻影窗口观察项（QUALITY_REPORT §四在案）

## 七、提交链（P2 轮）

```
0e09868  P2.1 设置 Sheet 弹窗完整页面（七卡片概览）
675f600  P2.2 交互加固（删除与卸载二次确认）
11152aa  P2.2 剩余项（iCloud 同步状态指示器 + 聊天顶栏右键菜单 + 拖拽 no-op 边界测试）
17e9f22  P2.3 玻璃强度「假配置」诚实闭环（import 0...1 校验 + MCP 同口径回落 + 设置诚实明示行 + 测试 +2 + 主题包测试拆独立文件）
```

验收 bundle：`tools/rebuild-app.sh` sha `061c8284fc6d` @ 17e9f22（nm `glassIntensityText` 符号在位 + 4 条 P2.3 新文案字节级核验；前轮 sha `bc3fbae8` @ 11152aa / `4776e361` @ ef033bc 已归档）
