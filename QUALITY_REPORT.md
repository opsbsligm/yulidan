# Swift Harness — 质量保障报告

> 生成时间: 2026-08-21 11:05
> 项目版本: v0.5.0（后端 8 模块闭环 + 前端打磨 F1–F11 + **P0.1 Apple SSO + iCloud 基础层 + P0.2 侧边栏【项目】模块**，HEAD 见 §六）
> 说明: P0.1 交付轮 — ① 新增 `Packages/Account` 包（9 源文件 1,946 行，基于 ServiceContainer 扩展 DI，核心零重构）：SiA 登录请求/探测、Keychain 凭证存储、KVS 元数据离线优先同步、AccountService 状态机、工作区双根严格隔离、App「账号与同步」设置子页（最小 UI）；② API 取证（macOS 26.5 SDK / 27 运行时，编译+运行时双验证）：ASAuthorizationAppleIDProvider().createRequest() 唯一创建路径 / ASPresentationAnchor=NSWindow（macOS 无 ASPresentationContext）/ delegate 需 @objc 精确选择子 / KVS 无 accountStatus（账号状态三重判定）/ KVS setData= set(_:forKey:)；③ 双构建（SwiftPM/Xcode）bundle id 统一 com.deepseek.harness + 部署目标 15→26 + 双 entitlements 文件（Xcode ad-hoc 签名拒绝 team 级 entitlements → CI 用精简版）；④ 门禁 16:16–16:33 全量复跑（ci-local pr + xcode + main 全绿：SwiftLint 0 / SwiftFormat 0 / 编译 0 警告 / **711 用例全绿（XCTest 180 + Swift Testing 531，106 suites）**，Account 45/45）。SSO 真机验收待用户 Developer Team/描述文件（见 §四 P2），本轮按「无 entitlements 优雅降级」设计交付。

> P0.2 交付轮（`97f45e9`，2026-08-21）：① 新增 `Packages/Workspace` 包（5 源文件 282 行）：Project 实体（id/name/createdAt/archived/collapsed/sortOrder）/ 删除二选一（.deleteAllSessions / .releaseToGlobal）/ 会话归属与归档迁移纯函数（SessionTransfer/ProjectOperations/reorder）/ SessionDragPayload Transferable（全局⇄项目⇄跨项目拖拽）/ SidebarModel 投影纯函数（主区=活跃项目按 sortOrder + 全局区，归档全部剔除）/ WorkspaceSyncPayload（KVS 同步载荷，顶层 SessionAssignment 类型）；② SessionDB v2 迁移（纯增量建 projects 表，grdb_migrations 跟踪；旧 metadata_json 向后兼容解码，projectId/archived 缺省 nil/false；**save 全量重写 events 表 → metadata patch 必须先 load 完整记录**）；③ Account 扩展 WorkspaceSyncEngine（actor，publishLocalState/applyRemoteValue，坏数据/读失败/无差异静默 no-op，本地状态不被污染）+ AccountService.attachWorkspaceStore 幂等接线 + KVS 外部变更分支接工作区同步；④ App 层：AppWorkspaceStore（WorkspaceStateStoring 生产实现）+ AppViewModel 项目模块（projects/searchProjectScope/项目 CRUD/折叠/归档/删除二选一/moveSession 拖拽/取消归档回落/项目限定搜索，11 项场景测试）+ 侧边栏 UI 重构拆分（SidebarProjectSections/SidebarSupportViews：项目头行右键菜单、悬停高亮 dropDestination、归档管理面板、搜索范围 Menu）；⑤ **看门狗选屏反馈回路修复（双屏窗口碎片化根因）**：pickUserFacingScreen 计入自身窗口 → 目标屏 tick 间振荡 → 每 2s orderOut/setFrame 捶打窗口服务器 → 主窗口被压成 30px 碎片不可见；修复 = 排除本进程窗口 + 目标屏按屏幕配置签名缓存（详见 §四已闭环）；⑥ xcode 工程三处静态库依赖缺失修复（HarnessApp +Workspace 链接 / AccountTests·WorkspaceTests +GRDB product+CSQLite modulemap flag，静态库不传递链接 + Xcode 26 不传播 SPM systemLibrary modulemap，详见 §四已闭环）；⑦ 门禁 763 用例全绿（XCTest 186 + Swift Testing 577，116 suites，ci-local pr+xcode+main 三门禁全绿，日志 /tmp/p02_ci_{pr3,xcode8,main2}.log）；⑧ 实机演示验证：新构建 App 启动后侧边栏项目分区/全局区/归档隐藏/搜索范围全部实机可见（截图 /tmp/dsh/p02_harness_win.png，演示数据：2 项目 + 2 会话归属 + 1 归档会话，可右键删除清理）。

> P0.2 收尾轮（`4beb21d`，2026-08-21 14:30）：看门狗在 macOS 27 beta 窗口服务器幻影报告下的现场拉锯彻底闭环（三层修复链完成）。现象：macOS 27 beta 窗口服务器对本 App 窗口**间歇性报告幻影 CGWindowList 边界**（Dock 缩略图尺寸 137-221×150-179 / 屏外 x=-255~-271，同窗口服务器侧报告 true/false 翻转，新窗口首启动即中 4/4 实测）→ 旧逻辑「服务器边界不一致→强制 remap」每 2s orderOut+setFrame+makeKeyAndOrderFront 撕裂**可见**窗口并抢焦点（用户可见闪烁）。修复：① 窗口用户可见（userManaged）时**禁止 remap**（信任应用侧报告，CG 报告有真相反转证据）② 仅掉屏/未映射走 remap（n≥2）→ recreate（n≥4，预算 2 次/30s）升级链 ③ 用户可见但服务器报幻影碎片持续 n≥8 才允许 recreate 自愈（ghost 渲染唯一可靠恢复手段）。实机验证（HARNESS_DEBUG=1 /tmp/harness-debug.log）：新实例首窗口启动 2s 即中幻影 → userManaged 期间**零 remap** → n≥8 recreate 自愈 → 预算耗尽（30s 间隔规则）后仅日志无破坏操作，全程零拉锯零抢焦点；现场同期旧二进制残留实例（win#40001）仍 2s REMAP 循环，前后对照互证。另记录三坑（§四 P2）：SCK ShareableContent 不列幻影窗口 / screencapture -l 对幻影窗口捕获失败 / 窗口服务器 clamp setFrame 结果（visibleFrame 全屏 → 实映射 (221,63,1249,860)，根因待定，不阻塞）。ci-local pr 复跑全绿（763 用例，/tmp/p03_ci_pr.log）。

> P0.3 交付轮（`2ada315`，2026-08-21 17:10）：侧边栏全部导航项消除假 UI + **加载三态异常 UI（loading/loaded/failed + 重试）**闭环。范围裁定（按 goal 严格审计）：6 导航项（新对话/会话列表/多Agent/插件/技能/工具）**已全部真实对接后端**（createNewSession/SessionDB/SubagentCoordinator+View/PluginManager/SkillStore/ToolRegistry，零假 UI）；唯一缺口 = 加载无 loading 态、失败静默=空数据不可区分。本轮：① **NavLoadState 状态层**（AppViewModel 四 Tab 状态传播：会话 loadSessionsFromDB（DB 打不开/加载失败显式 failed + sessionDBURL 重开缝）/ 插件 loadPluginsInfrastructure（双内置安装全败=failed、单败=橙色警告）/ 技能 loadSkillRegistry（用户目录读取失败传播）/ 工具（**零工具集=子系统失败不变量**，替代 P0.3 改造后产生的两处死 catch——零警告基线）+ 四路 retry 重跑对应加载链路）② **SkillStore.loadThrowing**（用户技能目录被普通文件占用 = 显式 notDirectory 错误，不再静默吞成空列表；目录不存在仍=成功空）③ **三 UI 组件**（NavLoadingView 加载占位防空态闪烁 / NavErrorBanner 失败横幅+重试 / NavWarningBanner 部分失败橙色警告（MCP 服务器连接失败导致工具不全））④ **四视图接线**（PluginListView/SkillView/ToolListView/SidebarView：失败横幅+列表保留部分数据、加载中空列表=占位行、ContentView 四路 retry 接线；`let` 带默认值被成员初始化器排除的坑改用 `var` 落地）⑤ 3 项场景单测（四态启动全 loaded / 会话 DB 路径被文件占用 failed→重试仍 failed→移除文件恢复 / 技能目录被文件占用 failed（内置技能保留）→换目录恢复）。门禁：pr /tmp/p03_nav_ci_pr.log + main /tmp/p03_nav_ci_main.log 全绿（**766/766：XCTest 186 + ST 580，117 suites**，0 协作池停滞；xcode 复用 P0.2 基线——本轮零工程结构变更）。实机验证：新构建启动正常态渲染通过（会话真实数据列表/插件 2/2 运行中/窗口主屏正常帧零幻影，用户实机操作中截图 /tmp/p03_screen2.png）。P0.4 待办：MCP 插件完整闭环（导入/日志/重启/权限/依赖/主题，权限门禁落点=PluginManager.checkPermissions 目前仅 log warning）。

---

## 一、质量门禁（当前 HEAD 实测）

| 门禁 | 状态 | 详情 |
|------|------|------|
| SwiftFormat | ✅ 0 改动 | `swiftformat --lint . --config .swiftformat`（197 文件，P0.3 新增 2） |
| SwiftLint | ✅ 0 违规 | `swiftlint lint --strict --config .swiftlint.yml`（197 文件，P0.3 新增 2） |
| 编译 | ✅ 0 警告 | 全量冷编译（450 targets 含测试目标，覆盖率构建实测） |
| 单元测试 | ✅ 766/766 | XCTest 186 + Swift Testing 580（117 suites），0 失败（P0.3 新增 3 ST 用例：导航加载三态——启动四态全 loaded / 会话 DB 文件占用 failed→恢复 / 技能目录占用 failed（内置保留）→恢复） |
| 本地 CI 模拟 | ✅ pr+main 全绿（xcode 复用基线） | `tools/ci-local.sh`（P0.3：pr /tmp/p03_nav_ci_pr.log、main /tmp/p03_nav_ci_main.log，均 0 次协作池停滞；xcode 复用 P0.2 /tmp/p02_ci_xcode8.log 基线——本轮零工程结构变更（无新 target/依赖），结构变更时必复跑） |
| 本地镜像备份 | ✅ 每次提交后 | `git push --mirror /Users/liguangming/code/swift-harness-backup.git` |
| GitHub 推送 | ⏸ 暂缓 | 按用户要求先本地版本控制，未推送远端（`.github/workflows/swift-ci.yml` 四 job 已就位；本地模拟 `tools/ci-local.sh [pr|leaks|xcode|main]` 可跑，leaks 门禁 0 leaks 实测） |

## 二、八大后端模块交付状态

| # | 模块 | 提交 | 状态 |
|---|------|------|------|
| 1 | Prompt 工程层（统一编排/角色模板/版本快照/动态渲染/模型差异化适配） | `b25582a` | ✅ 闭环 |
| 2 | 多 Agent 调度（子母生命周期/入参下发/回调/自动回收/shutdown，Actor 隔离） | `cf17f77` | ✅ 闭环 |
| 3 | 工具调用完整链路（ToolExecutor/参数校验/超时熔断/异常回传/流式进度/输出二次校验） | `10f7f86` | ✅ 闭环 |
| 4 | MCP 标准协议（能力协商/双向通信/会话生命周期/服务发现/工具自动注册） | `1ba4bb8` | ✅ 闭环 |
| 5 | RAG 检索增强（加载解析/切片/向量化/向量存储/召回/重排/过滤/溯源） | `6fcd98d` | ✅ 闭环 |
| 6 | 记忆系统（短期蒸馏/长期持久/意义评估/一致性冲突/反馈闭环迭代 RAG+记忆库） | `b800e91` | ✅ 闭环 |
| 7 | Skill 技能体系（Hermes 范式：观测→评估→自动生成→复用/编辑/调试/版本/销毁） | `68270a9` | ✅ 闭环 |
| 8 | 多模型服务商抽象适配层（ProviderProfile 画像/tools 下发/tool_calls 解析/SSE 聚合/参数归一化） | `d890934` | ✅ 闭环 |

### 平台基础层阶段（P0 系列）

| # | 模块 | 提交 | 状态 |
|---|------|------|------|
| P0.1 | Apple SSO + iCloud 工作区漫游基础层：SiA 请求（createRequest 唯一路径 / fullName+email scopes / nonce 32B）/ AppleCredentialStore（Keychain ThisDeviceOnly，与 API key 同 service）/ WorkspaceRoot 双根严格隔离（本地 ~/Library/Application Support/Harness vs iCloud 容器 /Documents，五目录契约 agents/rag/plugins-meta/themes/sync）/ MetadataSyncService（actor 离线优先、KVS 即写即同步、跨设备冲突 onConflict 裁决、accountChange 清态+信号）/ AccountService 状态机（restore 恢复 / 登录 / 撤销 / 凭证缺失 / 切换模式 / 登出）/ App「账号与同步」设置子页（最小 UI） | `6696bf1` | ✅ 基础层闭环（45/45 单测全绿；真机验收待描述文件，见 §四 P2） |
| P0.2 | 侧边栏【项目】模块（Codex 项目模型对齐）：Workspace 包 5 文件（Project 实体 / 删除二选一 / SessionTransfer 归属·归档迁移纯函数 / reorder / SessionDragPayload Transferable / SidebarModel 投影 / WorkspaceSyncPayload KVS 载荷）/ SessionDB v2 纯增量迁移 + metadata 向后兼容 / Account WorkspaceSyncEngine 同步桥（actor，坏数据 no-op）/ App 项目模块（项目 CRUD·折叠·归档·删除二选一·取消归档回落·会话拖拽迁移·项目限定搜索·归档管理面板）/ 看门狗选屏反馈回路修复（双屏窗口碎片化根因） | `97f45e9` | ✅ 模块闭环（763/763 全绿；实机演示验证通过，演示数据见头部说明） |
| P0.3 | 侧边栏导航真实数据对接 + 加载三态异常 UI：6 导航项真实对接审计（零假 UI）/ NavLoadState 状态层（四 Tab loading·loaded·failed 传播 + 四路 retry 重跑链路：retryLoadSessions/Plugins/Skills/Tools）/ SkillStore.loadThrowing（目录被文件占用显式抛错）/ NavLoadingView·NavErrorBanner·NavWarningBanner 三组件（空态闪烁防护 / 失败横幅+部分数据保留 / 部分失败橙色警告）/ 四视图接线（PluginListView·SkillView·ToolListView·SidebarView）/ 零警告基线修复（P0.3 改造产生两处死 catch → 零工具集不变量 + 去壳） | `2ada315` | ✅ 模块闭环（766/766 全绿；实机正常态验证通过） |

### 前端打磨阶段（后端全部闭环后启动）

| # | 项 | 提交 | 状态 |
|---|------|------|------|
| F1 | 设置两级菜单 + 子页面导航跳转（SettingsTab/SettingsSubTab 模型 + SettingsNavigationState 纯状态机 + LLM 三子页共享 ViewModel） | `261e71a` | ✅ 闭环 |
| F2 | 主聊天路径接 AgentLoop 工具循环（history 种子/工具轨迹消息/stopGenerating 同步取消/技能进化真实工具序列） | `5f11dee` | ✅ 闭环 |
| F3a | Codex 式工具轨迹行 + 顶栏会话标题 | `7b3dc8c` | ✅ 闭环 |
| F3b | AgentLoop onProgress 实时工具进度 + Codex 式贴底滚动 | `2886435` | ✅ 闭环 |
| F3-轨迹 | 工具轨迹 Codex 式可折叠行（toolTraces 端到端 + UI 独立组件 + 6 项回归测试） | `58a13d9` | ✅ 闭环 |
| F3c | 顶栏 Codex 式重排（左标题/右模型 pill/动作收纳溢出菜单）+ composer 居中限宽 720 | `ead1742` | ✅ 闭环 |
| F4 | 会话级 AgentLoop 持久化（LRU 上限 8/上下文指纹变化重建/跨轮热切/删除即回收 + 启动竞态修复） | `fbe5600` | ✅ 闭环 |
| F5 | whenIdle 取消感知（OnceIdleContinuation + 任务取消立即唤醒，不中断运行中 turn） | `84c7b6f` | ✅ 闭环 |
| F6 | WWDC26 Liquid Glass 表面系统（GlassSurface：GlassLevel 三级 / resolveMode 纯函数降级链（减弱透明度 solid > macOS26+ 原生 glassEffect > NSVisualEffectView legacy）/ reduceTransparencyTestOverride 测试缝 / material(for:) 纯函数 / 核心表面应用：Sidebar prominent、composer regular r16、设置 chip thin、CardModifier 全局升级） | `a0cb8ab` | ✅ 闭环（视觉验收待实机，见 §七） |
| F7 | Codex 布局对齐差距盘点（`docs/UI_CODEX_ALIGNMENT.md`）+ 首批落地：生成中会话守卫（三入口拦截 + 一致性防御，P1）/ 列表生成指示 / 相对时间 / ⌘N/⌘,/⌘1–⌘6 / 死代码删除 | `171c881` | ✅ 闭环（B6 置顶 / B8 气泡微调登记待办） |
| F8 | 侧边栏折叠（B5）：isSidebarCollapsed UserDefaults 持久化 / 52pt 图标 rail（展开/新对话/5 面板/设置/头像，快捷键两态共用）/ 展开态折叠按钮 + 折叠态主区展开按钮 | `49d3626` | ✅ 闭环（视觉验收待实机） |
| F9 | 置顶会话（B6）：SessionMetadata.pinned（旧 metadata_json 兼容解码）+ withPinned / togglePinSession DB 持久化 / 置顶段最顶（Codex pinned）+ 行内 pin 标记 + hover 置顶/取消 + 溢出菜单入口 / SidebarView 拆分 SessionListItem.swift | `c32a856` | ✅ 闭环（视觉验收待实机） |
| F10 | 用户消息 Codex 式无气泡纯文本（B8）：右对齐气泡 → 通栏左对齐 medium 字重 | `b5486ec` | ✅ 闭环（**B1–B8 差距清单全部闭环**，视觉验收待实机） |
| F11 | 会话分组纯函数化：SessionGroups.group(_:now:)（置顶段最顶/今天/昨天/更早/组内倒序）+ 2 项单测 | `17a0fd8` | ✅ 闭环 |

## 三、测试用例与行覆盖率（2026-08-21 P0.3 全量重测，766 用例 run，llvm-cov DA 口径，main 门禁 /tmp/p03_nav_ci_main.log）

| 模块 | 行覆盖（仅源文件，P0.2 终版实测） | 状态 |
|------|--------|------|
| Sandbox | 98.4%（63/64） | ✅ ≥90% |
| Skill | 96.9%（685/707） | ✅ ≥90%（P0.3 loadThrowing +14 行：notDirectory 抛出/目录不存在=成功空两分支全测） |
| Tools | 95.7%（572/598） | ✅ ≥90% |
| Workspace（新增） | 95.4%（269/282） | ✅ ≥90%（Project 92.86 / ProjectOperations 100 / SidebarModel 90.74 / WorkspaceSyncPayload 98.78 / SessionTransfer 80.0） |
| Subagent | 95.1%（367/386） | ✅ ≥90% |
| PluginXPC | 94.6%（297/314） | ✅ ≥90% |
| RAG | 94.5%（659/697） | ✅ ≥90% |
| Prompt | 94.5%（363/384） | ✅ ≥90% |
| Terminal | 93.2%（206/221） | ✅ ≥90% |
| Session | 93.2%（585/628） | ✅ ≥90%（SessionDB 94.87，v2 迁移/项目行/删除二选一清事件表全测） |
| LLM | 92.8%（1243/1339） | ✅ ≥90% |
| MCP | 92.4%（729/789） | ✅ ≥90% |
| Memory | 92.3%（524/568） | ✅ ≥90% |
| WebUI | 92.1%（608/660） | ✅ ≥90% |
| ServiceContainer | 91.4%（687/752） | ✅ ≥90% |
| Agent | 91.1%（494/542） | ✅ ≥90% |
| Notifications | 82.9%（63/76） | ⚠️ 结构性上限：剩余 13 行为 `SystemNotificationCenter` UN 真实包装层（裸 xctest 进程调用实测 abort；授权状态映射已拆纯函数 `state(from:)` 全测） |
| Account | 79.1%（594/751，10 文件） | ⚠️ 新平台包，不计入 90% 核心基线：AppleSignInService 13.1%（18/137）为 ASAuthorization 系统对话框包装层（NS_SWIFT_UI_ACTOR，无头结构性不可测，同类 Notifications UN 包装层）；其余 9 文件 95.0%（576/608）：AccountService 93.77 / MetadataSync 90.62 / CredentialStore 89.29 / **WorkspaceSyncEngine 96.88（新增）** / Types·WorkspaceRoot·Storing·Probing·Provider 100 |
| HarnessApp（UI 层） | 未计入表（SwiftUI 视图层，不计入 90% 核心基线；ViewModel 逻辑已由 AppViewModelProjectTests 等覆盖，项目模块 11 场景 + AppWorkspaceStore 2 场景全绿） | 说明 |

**总计: 766 个测试用例（XCTest 186 + Swift Testing 580，117 suites），全部通过。**（并行门禁口径：XCTest 以 `[N/186] Testing` 计数、ST 以 "Test run with 580" 计数，两路全绿；P0.3 新增 3 ST = 116→117 suites 口径连续）
**14 个核心包（除 LLM/Notifications/WebUI/Account）93.77%（6500/6932）均 ≥90%；18 包全量 92.31%（9008/9758）。**（P0.3 变动仅 Skill +14 行 96.9% / Session +1 行 93.2%，其余模块与 P0.2 逐项一致；全量 92.30→92.31 持平微升）

> 口径说明：行覆盖统计各模块 `Sources/` 源文件（不含测试），`llvm-cov report` DA 行级口径（ci-local main 门禁产物 /tmp/ci_cov.profdata 聚合 182 个 profraw）；分母与上一版（llvm-cov export lcov 口径）不同，**绝对值不可直接纵向比较，模块相对排序与 ≥90% 达标状态一致**。`swift test` 末尾 "Test run with N" 只统计 Swift Testing，XCTest 计数看 "Executed N tests"（并行模式看 `[N/M] Testing`）。

## 四、已知问题清单（按优先级）

### P0
无。

### P1
| 问题 | 现象/复现 | 状态 |
|------|-----------|------|
| macOS 27 beta 瞬态协作池调度停滞（`--parallel` 全量偶发失败） | 现象：`swift test --parallel`（或直接调 xctest）下 `CoordinatorLifecycleTests/testShutdownCancelsAllAndClears` 约 1/8~1/10 概率失败（blocker 10s 未 running → cancelCount=0）。**根因（现场 sample 实锤）**：新 xctest 进程偶发「协作池任务 ~10-13s 不派发，而池线程全部空闲」（证据：主线程阻塞于 XCTest async 桥接 mach_msg 等待、全部池/wq 线程 `__workq_kernreturn` 空闲、无任何线程执行排队的 Swift 任务；样本 /tmp/stall_sample_19.txt）。**环境故障，非协调器逻辑缺陷**：停滞解除后 run 任务立即执行且行为完全符合规范（排队取消不执行/运行取消/无僵尸残留）。排除链：最小 actor+Task 复现包 15/15 绿（非通用 actor 问题）；直接 xctest 调用 1/10 复现（与 SPM --parallel 无关）；串行 swift test 健康窗口 8/8 绿；AC 电源（非电池节流） | 修复双层：①测试层 — 前置等待 10s→30s、4 个 `eventually` helper 默认窗口 3s→5s（正常路径毫秒级返回，仅停滞时拉长）②CI 层 — pr/xcode/main/weekly 全量测试步骤加**有界单次重试**（停滞属环境故障，真实回归重试仍会失败）。**残留风险**：停滞超 30s，或其余固定 sleep 断言点（MCP 300-500ms / Agent 10-100ms / ServiceContainer 150ms 等）撞上停滞窗口仍可能偶发失败，由 CI 重试兜底；若 macOS 正式版仍复现再升级处理 | **修复已验证（观察期）**：Subagent 模块 15/15（其中 9 轮处于停滞窗口、11-12s 慢通过，测试内重试在真实窗口下全部存活）+ 全量 `--parallel` ×2（628）+ 串行 ×1（628）+ ci-local main ×2 + ci-local pr 全绿（`50fb2be` 提交前实测）。观察期：若 macOS 正式版仍复现再升级处理。**观察累计（2026-08-20）**：F6–F11 开发期全量回归累计 8+ 轮（各模块 full+main 及 manifest 修复后连续 2 轮）0 次停滞致失败；07:02 跨会话核验轮 ci-local pr + main 复跑 666 全绿 0 停滞。观察继续 |

### P2
| 问题 | 说明 | 状态 |
|------|------|------|
| `dsh web` 与"非 Web 服务"约束边界 | 需用户确认约束口径（WebUI 为本地 127.0.0.1 调试服务，非对外 Web 服务） | 待确认 |
| stopGenerating 不中断在途 LLM 调用（设计权衡） | 现象：`AgentLoop.cancel` 仅标记 cancelFlag + 唤醒 whenIdle 等待者，在途 `llm.request` 在后台自行完成（代码注释明示「在途 LLM 调用在后台自行完成，不再阻塞协调器」，F5 决策）。本地模型无副作用；远程模型会浪费一次请求配额。**已验证不变量**（`56efd78` 场景测试锁定）：延迟响应到达后不追加进会话消息流、无错误消息残留 | 已知设计（观察项）：若后续远程多模型成本敏感，可升级为「cancel 联动中断在途请求」（需 AgentLoop 持有在途 Task 引用，属架构扩展，本轮不做） |
| 冷 scratch 偶发 emit-module 工具链崩溃 | `no such module 'Agent'`，同 scratch 重试即过（环境坑非代码） | 已知 |
| SSO + iCloud 真机验收待 Developer Team | 无描述文件时本地 ad-hoc 签名无法携带 applesignin/icloud entitlements（Xcode ad-hoc 拒绝 team 级 entitlements，实测）；已按「无 entitlements 优雅降级」设计交付（UI 显示「需配置 entitlement/描述文件」+ 重新申请入口 + retryICloud），真实 SSO 登录 / KVS 跨设备漫游验收待用户提供 Team | 待用户（不阻塞） |
| KVS 跨设备冲突用户裁决 UI 未接 | MetadataSyncService.setOnConflict 回调已实现 + 测试（裁决胜出 / 无回调保留本地），但「账号与同步」子页暂无冲突裁决 UI | P0.2 或后续接入 |
| AppleSignInService 低覆盖 13.1%（18/137，P0.2 口径） | ASAuthorizationController 系统对话框包装层（NS_SWIFT_UI_ACTOR），无头环境结构性不可测，同类 Notifications UN 包装层；纯逻辑（nonce 生成 / 错误归类 userCancelled / 凭证状态查询）已全测 | 设计面（已知） |
| Apple LLVM 21（Xcode 26.6 / macOS 27 beta）`llvm-profdata merge -f` 参数 bug | `-f` 存在时（任意参数序）报 `error: <out>: No such file or directory` 且 rc=1；输出路径可写、输入 profraw 可读（`show` 正常）→ 工具自身 bug。三组实验实锤：`-f -o out files` 失败 / `files -f -o out` 失败 / `files -o out` 成功（覆盖已存在输出文件亦可）。曾致 `tools/ci-local.sh main` 覆盖率汇总步骤失败（测试门禁本身通过） | 已绕过（`50fb2be`）：merge 行改 `merge *.profraw -o out`（省略 -f、-o 置输入文件后），182 个 profraw 全量验证 + ci-local main 复跑全绿；官方工具链修复后可恢复 -f |
| KVS workspace 冲突裁决 UI 未接 | WorkspaceSyncEngine 的 onConflict 未设（= 保留本地，同 P0.1 accountMode 口径）；「账号与同步」子页暂无工作区冲突裁决 UI | P0.3 或后续接入 |
| 项目手动重排 UI 未暴露 | `ProjectOperations.reorder` 纯函数已测（跨项目移动 sortOrder 计算 + 边界），但侧边栏未提供项目拖拽排序入口（会话拖拽已有） | 后续 UI 打磨项 |
| macOS 27 beta 窗口服务器幻影 CGWindowList 报告（本机双屏 + 1.74x 非标缩放内屏环境） | 现象：窗口服务器对本 App 窗口间歇性报 Dock 缩略图尺寸（137-221×150-179）或屏外（x=-255~-271）边界，同窗口服务器侧报告 true/false 翻转，新窗口首启动即中（4/4 实测）；连带：SCK ShareableContent 不列该窗口（窗口级截图 API 全部失效）、screencapture -l 报 could not create image from window、窗口服务器 clamp setFrame 结果（setFrame visibleFrame 全屏 → 实映射 (221,63,1249,860)，左侧 221pt 收窄，根因待定）；残留幻影窗口在进程退出后仍滞留 CGWindowList（39976-39981 实测） | **P2（缓解已上线，`4beb21d`）**：看门狗反拉锯三层策略（用户可见禁 remap / 掉屏才 remap 升级链 / 持续幻影 n≥8 recreate 自愈，预算 2 次/30s 防无限重建）；窗口实际渲染不受幻影元数据影响（实机截图实证）；macOS 官方正式版修复后复核移除缓解 |
| 演示数据注入脚本 SQL 拼接 bug（一次性 /tmp 脚本，非工程代码） | seed 脚本 heredoc 内 `'..."'$P1'"'` 缺 `|| '...'` 结构 → sqlite 把 UUID 当标识符解析（首跑报 parse error）；修复后二次注入又漏闭合 `}` 致 2 行 metadata_json 非法 JSON（json_valid 校验捕获），已逐行从备份重建并全表 json_valid=1 复核 | 现场教训已处理；真实 DB 操作前必须 json_valid 全表校验 + 备份（本轮备份 /tmp/harness_sessions_backup_20260820_231140.sqlite） |

### 已闭环（本周期）
| 问题 | 闭环提交 |
|------|-----------|
| HarnessPluginWorker 进程泄漏（P1） | `c5bdc41` |
| WebUIApp 超时取消后 whenIdle 有界挂起 | `84c7b6f` |
| RAG 同文件重复入库不去重 | `c5bdc41` |
| SSE 流式不转发 reasoning 增量 | `c5bdc41` |
| local 画像默认关闭工具调用 | `c5bdc41`（按模型名白名单细分） |
| 冷编译警告（RAG 测试 docs1 未使用） | `851a100` |
| 测试固定 sleep 时序脆弱点 4 处（P1 根因候选） | `6ce51a0` |
| Xcode 工程依赖漂移（xcodebuild job 编译/链接失败；5 处 target 依赖缺失 + 5 个 target 缺失 + CSQLite 注入） | `99ba131` |
| lint 扫描范围被 ci-derived-data 污染（swiftlint LLVM 崩溃 / swiftformat 1545 文件） | `99ba131` |
| AppViewModelToolLoopTests 两处既有 swiftformat 违规 | `58a13d9` |
| P1 macOS 27 beta 瞬态协作池调度停滞（根因定位 + 槽位门控竞态修复 + 测试加固 + CI 有界重试） | `50fb2be` |
| 跨 suite 静态 providerFactory 竞态（生命周期 suite 与 ToolLoop suite 并行时工厂被互覆，脚本化 LLM 错配：测试收到他套件 "done: hello"） | `2192233`（新增实例级测试缝 providerFactoryOverride，新 suite 走实例缝不触碰静态工厂） |
| App 层会话生命周期无场景测试（创建/对话/持久化/改名/切换/删除/跨实例重载） | `2192233`（5 项场景闭环，含 DB 持久化与异步删除清理断言） |
| 工具面板 executeTool / parseParams / 沙箱根切换无端到端场景 | `2192233`（5 项场景闭环，含沙箱根切换越界拒绝/放行/恢复） |
| stopGenerating 生成取消路径无测试覆盖（App 层缺口） | `56efd78`（在途取消场景闭环 + 延迟响应不污染会话回归守卫） |
| 通知开关 → NotificationCoordinator 消费链无测试 | `56efd78`（开/关异步同步 isEnabled + UserDefaults 持久） |
| 跨 suite 全局 SkillStore.userSkillsDirectoryOverride 竞态（App 侧 Skill 测试与并行 Skill 测试目标互覆，实锤致 evaluateSurvivesSaveFailure 偶发失败） | `19c7fb2`（App 侧改纯实例参数注入，不再写全局） |
| spawnSubagent 场景测试污染真实 subagent_history.json（跨 run 累积致 guard 断言失败） | `19c7fb2`（临时历史文件隔离 + 4 条污染条目清理） |
| App 层 clearChat / retryLastMessage / spawnSubagent 入口 / 插件启停无场景测试 | `19c7fb2`（4 项场景闭环） |
| Apple LLVM 21 llvm-profdata merge -f bug（ci-local 覆盖率汇总失败） | `50fb2be`（绕过） |
| 跨模块业务场景端到端自测缺口（8 模块集成链路无单一场景贯穿验证） | `dfe393e` |
| 跨轮上下文/记忆注入/技能复用回环无集成断言 | `bc8f3fc` |
| Notifications 授权状态映射不可单测（整体裹在 UN 真实包装层里） | 本轮提交（`state(from:)` 纯函数拆分 + 映射/透传全测，66.7%→82.7%） |
| 26 处 #ActorIsolatedCall 编译警告（本 SDK ViewModifier 为 @MainActor 隔离，GlassSurface 静态成员随类型隔离，非隔离测试代码调用触发，零警告基线破坏） | `a0cb8ab`（suite 加 @MainActor，与既有 App 测试惯例一致；`swift build --build-tests` 0 警告实测） |
| 生成中切换/新建/删除会话污染消息流（P1：performGeneration 后台写回落到切换后的新会话） | `171c881`（三入口拦截 + guardGenerationSession 写回前一致性防御 + 2 项场景测试锁定） |
| SessionSidebarView.swift 死代码（217 行，仅自身 #Preview 引用） | `171c881`（删除，UI 层分母 -93 插桩行） |
| 侧边栏不可折叠（F7 盘点 B5，Codex 对齐差距） | `49d3626`（52pt 图标 rail + 持久化 + 1 项测试） |
| 无置顶会话（F7 盘点 B6，Codex pinned 对齐差距） | `c32a856`（pinned 字段向后兼容 + 置顶段 + 持久化往返 3 项测试） |
| SidebarView.swift 超文件长度门禁（610>600，B3/B5/B6 累积） | `c32a856`（拆分 SessionListItem.swift：SessionListItem/RelativeTime） |
| 无置顶会话（F7 盘点 B6，Codex pinned 对齐差距） | `c32a856`（pinned 字段向后兼容 + 置顶段 + 持久化往返 3 项测试） |
| 用户消息气泡样式与 Codex 不符（F7 盘点 B8） | `b5486ec`（无气泡纯文本，视觉验收待实机） |
| 会话分组逻辑不可单测（groups 私有计算属性） | `17a0fd8`（SessionGroups 纯函数提取 + 2 项单测） |
| 双构建（SwiftPM/Xcode）bundle id 不一致 + 部署目标漂移（Xcode 侧 minos 15） | `6696bf1`（project.yml + rebuild-app.sh 统一 com.deepseek.harness + 部署目标 26，双清单同步 + xcodegen 再生） |
| Xcode ad-hoc 签名（-）拒绝 team 级 entitlements（applesignin/icloud 需 provisioning profile） | `6696bf1`（双 entitlements 文件方案：完整版 HarnessApp.entitlements 待 Team 启用 / CI 精简版仅 get-task-allow） |
| macOS KVS 账号状态无现成 API（无 accountStatus，35 方法实测枚举） | `6696bf1`（三重判定：url(forUbiquityContainerIdentifier:) nil=无容器 + ubiquityIdentityToken 属性非 nil + KVS 外部变更通知（reason raw 0/1/2/3 映射），探测脚本实机实测） |
| SiA 请求对象直接 init 运行时 crash | `6696bf1`（取证：唯一创建路径 = ASAuthorizationAppleIDProvider().createRequest()，编译+运行时双验证） |
| 双屏窗口服务器碎片化致主窗口不可见（P0.2 启动演示现场，复现 4 次） | `97f45e9`（根因链：watchdog 每 2s 调 pickUserFacingScreen 选目标屏，该函数按「屏上 layer0 窗口数」打分且**计入本 App 自身窗口** → 窗口被移屏后计数翻转 → 目标屏 tick 间振荡（内置⇄外屏）→ 每 2s orderOut/setFrame/makeKeyAndOrderFront 捶打窗口服务器 → 主窗口被压成 30px 碎片（CGWindowList 实测 4 片：1920x30×3 + 64x64）→ System Events 0 窗口、彻底不可见。修复：① pickUserFacingScreen 排除本进程窗口（断反馈回路）② watchdog 目标屏按屏幕配置签名缓存（仅屏幕增减/分辨率变化时重算）。修复后实机验证：20s+ watchdog 日志零 mismatch，窗口稳定内置屏全宽，System Events 正常枚举 1 窗口） |
| macOS 27 beta 窗口服务器幻影报告 → 看门狗对可见窗口拉锯/抢焦点（P0.2 收尾现场，用户可见闪烁） | `4beb21d`（修复链第三层：① 用户可见（userManaged）禁止 remap — 信任应用侧报告（CG 报告有真相反转证据）② 掉屏/未映射才 remap（n≥2）→ recreate（n≥4，预算 2 次/30s）升级链 ③ 用户可见 + 持续幻影（n≥8）才 recreate 自愈（ghost 渲染唯一可靠恢复手段）；实机验证：新实例首窗口启动 2s 中幻影 → 零 remap → n≥8 recreate 自愈 → 预算耗尽后仅日志零破坏操作；旧二进制实例（win#40001）同期 2s REMAP 循环互证。另：osascript `tell application "HarnessApp" to activate` 会经 LS 二次拉起实例（直启实例收 SIGTERM 退出）— 操作本 App 一律用 pgrep+PID 口径） |
| xcode 工程静态库依赖三处缺失（P0.2 xcode 门禁 4 连败根因） | `97f45e9`（① HarnessApp 漏 `- target: Workspace` → ld symbol not found（AppViewModel/Sidebar 引用 Workspace.ProjectID 等）② AccountTests/WorkspaceTests 间接依赖 GRDB 但无直接 GRDB product → 拿不到自动 CSQLite modulemap flag → unable to resolve module dependency: 'CSQLite'（直接依赖 GRDB product 的 target 由 SPM 集成自动注入 checkout modulemap，间接者必须显式声明）③ 同两 target 补 GRDB product 后移除手动 flag 避免 CSQLite 模块双重声明；静态库不传递链接是 Xcode 既定行为，项目惯例=测试 target 显式列全所需 target + GRDB product。另清理两 scheme 误重复的 WorkspaceTests 条目（xcodebuild test 会跑两遍）） |
| project.yml 重建事故（本轮现场，工程文件曾被截断） | 本轮 python 切片脚本 bug 误删 MemProbe 之后全部 target/scheme 段；用 HEAD 版本 + 本轮已知增量编辑重建，**xcodegen 再生成 pbxproj 与截断前备份逐行 diff 零差异（除预期新增 Workspace 链接）+ scheme 文件 diff 仅各减一条重复 WorkspaceTests** 双重校验后放行；教训：对工程清单文件做程序化编辑必须先备份 + 生成物 diff 校验 |

## 五、代码统计

| 项 | 数值 |
|----|------|
| 源码（Packages，91 源文件） | 13,486 行（P0.3：SkillStore.loadThrowing +25） |
| 源码（Apps，37 文件，HarnessApp + 辅助 target） | 8,855 行（P0.3：AppViewModel 三态层 +129 / NavLoadStateView 新文件 76 / 四视图接线 +96） |
| 源码合计（128 文件） | 22,341 行 |
| 测试代码（68 文件） | 15,245 行（P0.3 新增：AppViewModelNavLoadStateTests 124 行 3 场景） |
| SPM 目标 | 22 库（17 后端包 + 5 辅助库 Workspace/Plan/Goal/HarnessCore/Account 扩展）/ 4 可执行 + 20 测试目标（单一 xctest 进程） |
| 工具链 | Swift 6.3.3 / Xcode 26.6 / macOS arm64 / platforms .macOS(.v26) |
| 提交总数 | 118（P0.3：`2ada315` feat + 本次入册 docs 提交） |

### 八大后端模块代码级需求审计（2026-08-20 跨会话核验轮）

> 方法：对照目标模块清单逐条子能力 grep/阅读实码取证（非依赖提交信息/报告记忆）。**全部子能力均有实码证据，无缺口。**

| # | 模块·子能力 | 代码级证据 |
|---|------------|-----------|
| 1 | Prompt·统一编排 | `PromptService` 协议 + `PromptEngine`（PromptEngine.swift） |
| 1 | Prompt·角色模板 | agent/subagent 内建模板 + `PromptTemplateStore` + `BuiltInPromptTemplates` |
| 1 | Prompt·版本快照 | `PromptTemplateStore`：每次 update 生成 version+1 不可变快照，保留全历史（FIFO 上限），`template(named:version:)` 回查 |
| 1 | Prompt·动态渲染 | `PromptRenderer`/`TemplateRenderer`（变量替换 + 分节装配） |
| 1 | Prompt·模型差异化适配 | `ModelPromptAdapter.adapt(_:profile:)` + `ModelProfile`（family/toolCallStyle/contextWindow/promptNotes） |
| 2 | 多 Agent·生命周期 | `actor SubagentCoordinator`：spawn/cancel/waitFor/waitForAll/allStates/removeFinished/shutdown |
| 2 | 多 Agent·入参下发 | `SubagentSpec`（任务文本 + 结构化入参 + 单任务超时 + 父任务 ID） |
| 2 | 多 Agent·回调接收 | `onEvent` 生命周期事件 + `onFinished` 完成回调（独立直挂通知/统计） |
| 2 | 多 Agent·内存回收/防僵尸 | 终态宽限期自动回收（reap）+ 并发槽位门控（maxConcurrent，含竞态修复 `50fb2be`） |
| 2 | 多 Agent·Actor 隔离 | `actor SubagentCoordinator` + `actor AgentLoop`（并发隔离实码） |
| 3 | 工具·完整链路 | `ToolExecutor.execute`：查找 → 必填参数校验 → 按工具熔断 → `withToolTimeout` 单次超时 → 执行 → 输出二次校验（可选 JSON + 字符截断）→ 错误归一化回传 |
| 3 | 工具·流式结果 | `ToolExecEvent` 进度事件流（执行中增量上报） |
| 3 | 工具·多轮嵌套 | `AgentLoop` 工具循环：tool_calls → executeToolBatch → 结果回填上下文 → 下一轮（单轮步数上限 + toolTraces 轨迹） |
| 4 | MCP·客户端/会话 | `actor StdioMCPClient`：start（幂等）/ initialize 握手 / notifications/initialized / ping / stop / listTools / callTool |
| 4 | MCP·能力协商 | `negotiatedCapabilities` + `parseCapabilities`（initialize 响应解析） |
| 4 | MCP·双向通信 | `onNotification` 下行通知回调 + `onServerRequest` 服务器反向请求应答 |
| 4 | MCP·服务发现 | `MCPDiscovery.loadConfigs/probe/discover`（~/.harness/mcp/servers.json） |
| 4 | MCP·工具自动注册 | App 层 `MCPServerManager.connectStdio(config, into: toolRegistry)` + `makeTools()` → 主 Agent 注册表（含 listChanged 缓存失效重注册） |
| 5 | RAG·加载解析 | `DocumentLoader`（md/txt 等，含失败错误类型） |
| 5 | RAG·切片分块 | `Chunker`（targetSize 800 / overlap 120 / 段落感知） |
| 5 | RAG·向量化 | `TextVectorizer` 协议 + `HashingVectorizer`（512 维，零模型依赖） |
| 5 | RAG·向量存储 | `actor VectorStore`（持久化 fileURL + 去重） |
| 5 | RAG·召回/重排/过滤 | `RAGEngine`：召回 K=20 → final = cosine + 0.3×termOverlap 重排 → topK；`RetrievalOptions.filter` 元数据等值过滤 |
| 5 | RAG·来源溯源 | `RetrievedChunk.citation`：「来源 · 块 N · 字符 start-end」+ 召回分/终分双轨 |
| 6 | 记忆·短期总结 | `MemoryEngine.consolidateSession`（会话自动总结蒸馏入长期库） |
| 6 | 记忆·长期持久 | `LongTermMemoryStore` + save/recall/forget/stats/promptSection 注入 |
| 6 | 记忆·意义评估 | `SignificanceScorer` + `record` → `MemoryDecision` |
| 6 | 记忆·一致性/冲突 | `ConsistencyChecker` + 冲突信息取代（revision 递增） |
| 6 | 记忆·反馈闭环迭代 | `applyFeedback` → ① 长期记忆库（意义度保底 + 冲突取代）② RAG 知识库入库（origin=feedback 元数据，后续检索复用）；`attachRAG` 共享引擎注入 |
| 7 | Skill·Hermes 自动 | `actor SkillEvolutionEngine`：observe 任务观测 → evaluate 重复模式聚类（阈值）→ 自动生成技能 → 保存 + 注册表可复用 + 版本记录 |
| 7 | Skill·手动编辑 | `SkillStore.parse/serialize/save`（Markdown 技能文件，用户技能目录） |
| 7 | Skill·调试运行 | `SkillDebugger`（SkillDebugReport 问题清单 + passed 判定） |
| 7 | Skill·版本管理 | `SkillVersioning`（历史 ≤20 条 + changeNote/changedAt） |
| 7 | Skill·销毁删除 | `SkillStore.delete` |
| 8 | 多模型·画像 | `ProviderProfile`（family/supportsToolCalls/supportsReasoning/defaultMaxTokens；内建 openAI/deepSeek/local/anthropic/mock + `local(forModel:)` 模型名白名单细分） |
| 8 | 多模型·格式差异 | `Adapters`：OpenAI/DeepSeek/Local/Anthropic 四适配（Anthropic 消息结构 classify/assistantMsg/userMsg 映射 + tool_use/tool_result 块） |
| 8 | 多模型·JSON 归一 | `LLMResponseNormalizer`（`repairToolArguments` 参数 JSON 修复 / contentBlocks / 统一 `LLMResponse`） |
| 8 | 多模型·SSE 聚合 | `StreamChunk`（text/reasoning/done(finish,usage,toolCalls) delta 累积聚合） |
| 8 | 多模型·上层隔离 | `LLMProvider` 统一内部协议；上层（AgentLoop）仅经协议 + `profile.supportsToolCalls` 能力门控，零厂商分支 |

**架构约束核验**：全部业务能力（含新增 Account 平台层）经 `ServiceContainer`（DI 容器 + 插件系统 + EventBus + CircuitBreaker）扩展装配，容器核心未重构；纯原生 SwiftUI/AppKit（无 WebView/WKWebView/Electron）；deployment target `.macOS(.v26)`（`19f4961` 上提，macOS 26 Tahoe 基线）。


## 六、提交链（近期）

```
2ada315  feat(app): P0.3 侧边栏导航真实数据对接 + 加载三态异常 UI（NavLoadState 四 Tab 状态层 + 四路 retry + 三 UI 组件 + SkillStore.loadThrowing + 3 场景单测，766/766 全绿）
4beb21d  fix(app): 看门狗尊重用户可见窗口（macOS 27 beta 窗口服务器幻影报告反拉锯，763/763 复跑全绿）
97f45e9  feat(workspace): P0.2 侧边栏【项目】模块（Workspace 包 + SessionDB v2 + WorkspaceSyncEngine + 项目模块 UI + 看门狗选屏反馈回路修复，763/763 全绿）
da47c0d  docs(quality): P0.1 交付入册（SSO+iCloud 基础层 711 用例基线 + Account 模块覆盖率 DA 口径首测 + API 取证 4 项）（6696bf1）
6696bf1  feat(account): P0.1 Apple SSO + iCloud 工作区漫游基础层（Packages/Account + 账号与同步子页 + 双构建统一，711/711 全绿）
19f4961  chore(baseline): 部署目标 15→26 macOS Tahoe（WWDC25）+ tools-version 6.0→6.3
ead0c45  fix(project): ToolsTests 补声明 Agent 依赖（xcodebuild 依赖扫描警告根除，双清单同步）
50df89b  docs(quality): 666 用例基线 + F10/F11 入册 + B1–B8 全部闭环宣告
17a0fd8  test(ui): F11 会话分组纯函数化（SessionGroups）+ 置顶段/日分组 2 项单测
b5486ec  feat(ui): F10 用户消息 Codex 式无气泡纯文本（B8 闭环）— 通栏左对齐 medium 字重
c32a856  feat(ui): F9 置顶会话（B6 闭环）— SessionMetadata.pinned + 置顶段 + 持久化往返
49d3626  feat(ui): F8 侧边栏折叠（B5 闭环）— 窄图标 rail + 持久化 + 主区展开按钮
171c881  feat(ui): F7 Codex 布局对齐 — 生成中会话守卫 + 列表生成指示/相对时间 + ⌘ 快捷键 + 死代码删除
a0cb8ab  feat(ui): WWDC26 Liquid Glass 表面系统（原生 glassEffect + 三级降级链 + 4 项单测）+ 核心表面应用
19c7fb2  test(app): 会话操作 4 场景（clearChat/重试/子任务入口/插件启停）+ 技能目录全局覆盖竞态根除
56efd78  test(app): stopGenerating 在途取消 + 通知开关 2 场景（延迟响应不污染会话不变量）
2192233  test(app): 会话生命周期 5 场景 + 工具面板 5 场景端到端测试（providerFactory 实例缝隔离跨 suite 竞态）
bc8f3fc  test(scenario): 跨轮工具上下文保留 + 记忆注入系统提示词 + 技能复用回环（场景测试 4 项闭环）
dfe393e  test(scenario): 跨模块业务场景端到端测试（8 模块集成链路自测）
c34ee2f  docs(quality): P1 调度停滞修复验证闭环 + P2 profdata -f bug 入册 + 覆盖率 lcov 口径重测（50fb2be）
c969827  docs(quality): Xcode 工程依赖漂移修复入册（99ba131）
99ba131  fix(xcode): 修复 Xcode 工程依赖缺失（xcodebuild job 首次本地跑通）+ lint 排除 ci-derived-data
7e91c5d  ci(local): 本地 CI 模拟脚本（对齐 GitHub Actions 四 job：pr/leaks/xcode/main）
4ebd8c6  docs(quality): P1 瞬态失败根因定位与修复入册（6ce51a0 观察期）
6ce51a0  fix(test): P1 瞬态失败根因修复 — 固定 sleep + 异步回调断言改条件轮询
851a100  fix(test): 冷编译警告清零（RAGEngineTests docs1 未使用变量）
ead1742  feat(app): 顶栏 Codex 式重排 + composer 居中限宽（前端阶段3c）
84c7b6f  fix(agent): whenIdle 取消感知（P2 闭环：WebUI 超时后孤儿任务不再悬挂到 turn 结束）
fbe5600  feat(agent): 会话级 AgentLoop 持久化（跨轮工具上下文保留 + LRU 内存回收）
c5bdc41  fix(quality): P1+P2 后端四项闭环（PluginWorker 进程泄漏 / RAG 去重 / SSE reasoning 流式 / local 画像按模型细分）
2886435  feat(app): AgentLoop onProgress 实时工具进度 + Codex 式贴底滚动（前端阶段3b）
7b3dc8c  feat(app): Codex 式工具轨迹行 + 顶栏会话标题（前端阶段3a）
c8e3cc4  fix(test): 根除跨 suite 全局覆盖竞态（瞬态测试失败根因）
cf0e230  docs(quality): 刷新质量报告 — 前端阶段1/2 基线
```

## 七、下一阶段

已完成（2026-08-21 P0.3 轮，`2ada315`）：① 6 导航项真实对接审计（零假 UI）② NavLoadState 三态状态层 + 四路 retry 重跑链路 ③ SkillStore.loadThrowing（目录被文件占用显式抛错）④ 三 UI 组件 + 四视图接线（空态闪烁防护/失败横幅/部分失败警告）⑤ 零警告基线修复（两处死 catch 消除）⑥ 3 场景单测 + 766/766 门禁（pr+main 全绿 0 停滞）⑦ 实机正常态验证（会话真实数据/插件 2/2 运行/窗口零幻影）。

已完成（2026-08-21 P0.2 轮）：① Workspace 包 5 文件 282 行（Project 实体 / 删除二选一 / SessionTransfer / reorder / SessionDragPayload / SidebarModel 投影 / WorkspaceSyncPayload）+ 27 单测 ② SessionDB v2 纯增量迁移（向后兼容解码 + save 全量重写 events 的 patch 先 load 后 save 约束）③ Account WorkspaceSyncEngine 同步桥 + 8 单测 ④ App 项目模块 UI（分区/折叠/归档管理面板/搜索限定范围/会话拖拽迁移，11 场景 + 2 投影单测）⑤ 看门狗选屏反馈回路修复（双屏窗口碎片化根因，实机 20s+ 零 mismatch 验证）⑥ xcode 工程静态库依赖三处修复 + scheme 重复条目清理 ⑦ 763/763 门禁基线（ci-local pr+xcode+main 三门禁全绿）⑧ 实机演示验证（新构建启动 + 侧边栏项目分区实机可见，截图 /tmp/dsh/p02_harness_win.png）。

下一步：**P0.4 MCP 插件完整闭环** — ① 导入本地 MCP 包（servers.json 声明 + 安装流程 UI）② 运行日志（stdio 服务器输出回显）③ 重启故障插件（连接失败单服务器重连，区别于整页 retry）④ 权限授予/拒绝（PluginManager.checkPermissions 目前仅 log warning = P0.4 权限门禁落点）⑤ 依赖缺失提示（manifest 依赖检查 UI）⑥ 主题插件机制（主题包安装/应用/回退）。

> P0.3 遗留观察（不阻塞 P0.4）：三态 UI 的**失败态实机视觉验收**待用户在场时演示（状态层 3 场景单测已锁定；正常态实机已通过）。

1. 用户依赖（不阻塞）：① Apple Developer Team/描述文件（SSO + iCloud 真机验收；当前按「无 entitlements 优雅降级」设计，UI 显示「需配置 entitlement/描述文件」+ 重新申请入口）② 「账号与同步」设置子页 + P0.2 项目模块实机视觉验收（演示数据已注入真实 DB，可右键删除项目清理）③ KVS 跨设备冲突用户裁决 UI 接入（P0.3 或后续）④ GitHub Actions 远端仍暂缓（ci-local 四模式本地模拟）
2. 持续观察：P1 macOS 27 beta 协作池调度停滞（每轮全量回归观察，CI 有界重试兜底；macOS 正式版若复现再升级）+ P2 macOS 27 beta 窗口服务器幻影 CGWindowList 报告（缓解已上线 `4beb21d`，实机渲染不受影响；macOS 官方正式版修复后复核并移除缓解逻辑）
3. 持续迭代候选（均不阻塞）：① in-flight LLM 调用 cancel 联动中断（P2，AgentLoop 架构扩展）② KVS 冲突裁决 UI（含 workspace 冲突）③ 项目拖拽排序 UI 暴露 ④ 覆盖率工具链口径统一（官方工具链修复 profdata -f bug 后恢复）
