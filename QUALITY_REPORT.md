# Swift Harness — 质量保障报告

> 生成时间: 2026-08-21 11:05
> 项目版本: v0.5.0（后端 8 模块闭环 + 前端打磨 F1–F11 + **P0.1 Apple SSO + iCloud 基础层 + P0.2 侧边栏【项目】模块**，HEAD 见 §六）
> 说明: P0.1 交付轮 — ① 新增 `Packages/Account` 包（9 源文件 1,946 行，基于 ServiceContainer 扩展 DI，核心零重构）：SiA 登录请求/探测、Keychain 凭证存储、KVS 元数据离线优先同步、AccountService 状态机、工作区双根严格隔离、App「账号与同步」设置子页（最小 UI）；② API 取证（macOS 26.5 SDK / 27 运行时，编译+运行时双验证）：ASAuthorizationAppleIDProvider().createRequest() 唯一创建路径 / ASPresentationAnchor=NSWindow（macOS 无 ASPresentationContext）/ delegate 需 @objc 精确选择子 / KVS 无 accountStatus（账号状态三重判定）/ KVS setData= set(_:forKey:)；③ 双构建（SwiftPM/Xcode）bundle id 统一 com.deepseek.harness + 部署目标 15→26 + 双 entitlements 文件（Xcode ad-hoc 签名拒绝 team 级 entitlements → CI 用精简版）；④ 门禁 16:16–16:33 全量复跑（ci-local pr + xcode + main 全绿：SwiftLint 0 / SwiftFormat 0 / 编译 0 警告 / **711 用例全绿（XCTest 180 + Swift Testing 531，106 suites）**，Account 45/45）。SSO 真机验收待用户 Developer Team/描述文件（见 §四 P2），本轮按「无 entitlements 优雅降级」设计交付。

> P0.2 交付轮（`97f45e9`，2026-08-21）：① 新增 `Packages/Workspace` 包（5 源文件 282 行）：Project 实体（id/name/createdAt/archived/collapsed/sortOrder）/ 删除二选一（.deleteAllSessions / .releaseToGlobal）/ 会话归属与归档迁移纯函数（SessionTransfer/ProjectOperations/reorder）/ SessionDragPayload Transferable（全局⇄项目⇄跨项目拖拽）/ SidebarModel 投影纯函数（主区=活跃项目按 sortOrder + 全局区，归档全部剔除）/ WorkspaceSyncPayload（KVS 同步载荷，顶层 SessionAssignment 类型）；② SessionDB v2 迁移（纯增量建 projects 表，grdb_migrations 跟踪；旧 metadata_json 向后兼容解码，projectId/archived 缺省 nil/false；**save 全量重写 events 表 → metadata patch 必须先 load 完整记录**）；③ Account 扩展 WorkspaceSyncEngine（actor，publishLocalState/applyRemoteValue，坏数据/读失败/无差异静默 no-op，本地状态不被污染）+ AccountService.attachWorkspaceStore 幂等接线 + KVS 外部变更分支接工作区同步；④ App 层：AppWorkspaceStore（WorkspaceStateStoring 生产实现）+ AppViewModel 项目模块（projects/searchProjectScope/项目 CRUD/折叠/归档/删除二选一/moveSession 拖拽/取消归档回落/项目限定搜索，11 项场景测试）+ 侧边栏 UI 重构拆分（SidebarProjectSections/SidebarSupportViews：项目头行右键菜单、悬停高亮 dropDestination、归档管理面板、搜索范围 Menu）；⑤ **看门狗选屏反馈回路修复（双屏窗口碎片化根因）**：pickUserFacingScreen 计入自身窗口 → 目标屏 tick 间振荡 → 每 2s orderOut/setFrame 捶打窗口服务器 → 主窗口被压成 30px 碎片不可见；修复 = 排除本进程窗口 + 目标屏按屏幕配置签名缓存（详见 §四已闭环）；⑥ xcode 工程三处静态库依赖缺失修复（HarnessApp +Workspace 链接 / AccountTests·WorkspaceTests +GRDB product+CSQLite modulemap flag，静态库不传递链接 + Xcode 26 不传播 SPM systemLibrary modulemap，详见 §四已闭环）；⑦ 门禁 763 用例全绿（XCTest 186 + Swift Testing 577，116 suites，ci-local pr+xcode+main 三门禁全绿，日志 /tmp/p02_ci_{pr3,xcode8,main2}.log）；⑧ 实机演示验证：新构建 App 启动后侧边栏项目分区/全局区/归档隐藏/搜索范围全部实机可见（截图 /tmp/dsh/p02_harness_win.png，演示数据：2 项目 + 2 会话归属 + 1 归档会话，可右键删除清理）。

> P0.2 收尾轮（`4beb21d`，2026-08-21 14:30）：看门狗在 macOS 27 beta 窗口服务器幻影报告下的现场拉锯彻底闭环（三层修复链完成）。现象：macOS 27 beta 窗口服务器对本 App 窗口**间歇性报告幻影 CGWindowList 边界**（Dock 缩略图尺寸 137-221×150-179 / 屏外 x=-255~-271，同窗口服务器侧报告 true/false 翻转，新窗口首启动即中 4/4 实测）→ 旧逻辑「服务器边界不一致→强制 remap」每 2s orderOut+setFrame+makeKeyAndOrderFront 撕裂**可见**窗口并抢焦点（用户可见闪烁）。修复：① 窗口用户可见（userManaged）时**禁止 remap**（信任应用侧报告，CG 报告有真相反转证据）② 仅掉屏/未映射走 remap（n≥2）→ recreate（n≥4，预算 2 次/30s）升级链 ③ 用户可见但服务器报幻影碎片持续 n≥8 才允许 recreate 自愈（ghost 渲染唯一可靠恢复手段）。实机验证（HARNESS_DEBUG=1 /tmp/harness-debug.log）：新实例首窗口启动 2s 即中幻影 → userManaged 期间**零 remap** → n≥8 recreate 自愈 → 预算耗尽（30s 间隔规则）后仅日志无破坏操作，全程零拉锯零抢焦点；现场同期旧二进制残留实例（win#40001）仍 2s REMAP 循环，前后对照互证。另记录三坑（§四 P2）：SCK ShareableContent 不列幻影窗口 / screencapture -l 对幻影窗口捕获失败 / 窗口服务器 clamp setFrame 结果（visibleFrame 全屏 → 实映射 (221,63,1249,860)，根因待定，不阻塞）。ci-local pr 复跑全绿（763 用例，/tmp/p03_ci_pr.log）。

> P0.4/P0.5/P0.1.4 交付轮（2026-08-21 17:00–18:00）：P0 业务 MVP **功能开发全部闭环**。P0.4 MCP 插件完整闭环 6 项全落地（导入/日志/重启/权限/依赖/主题，含 executeTool 串槽 P1 修复 + 主题插件三源聚合与自动回落 + MCP 主题服务器真实 stdio e2e + 依赖缺失 semver 满足度检测与安装门禁 + mcpConfigURLOverride static 缝→实例级参数根除并行门禁跨套件互踩）；P0.5 对话 composer 三项缺口清零（加号插件工具入口/快捷提示填充输入框/composer 右下角模型下拉，顶栏与 composer 模型切换归一共享组件）；P0.1.4 iCloud 多设备冲突裁决 UI（回调挂起→设置页双栏预览→保留本地/云端→胜者写回 KVS，超时 10min 安全网保留本地=离线优先）。门禁：pr 全绿 **618 用例（XCTest 188 + ST 430，125 suites）0 警告 0 违规**。P0 遗留（用户依赖，不阻塞代码）：① Apple SSO + iCloud 真机验收待 Developer Team/描述文件（无 entitlements 优雅降级已实现）② 冲突裁决/三态失败态/依赖缺失/主题切换的**实机视觉验收**待用户在场演示（逻辑层测试全锁定）。下一步：P0 实机验收通过后进入 P1（Liquid Glass 全局玻璃化 + Tab Morph + 主题插件玻璃参数打通）。
>
> P0.3 交付轮（`2ada315`，2026-08-21 17:10）：侧边栏全部导航项消除假 UI + **加载三态异常 UI（loading/loaded/failed + 重试）**闭环。范围裁定（按 goal 严格审计）：6 导航项（新对话/会话列表/多Agent/插件/技能/工具）**已全部真实对接后端**（createNewSession/SessionDB/SubagentCoordinator+View/PluginManager/SkillStore/ToolRegistry，零假 UI）；唯一缺口 = 加载无 loading 态、失败静默=空数据不可区分。本轮：① **NavLoadState 状态层**（AppViewModel 四 Tab 状态传播：会话 loadSessionsFromDB（DB 打不开/加载失败显式 failed + sessionDBURL 重开缝）/ 插件 loadPluginsInfrastructure（双内置安装全败=failed、单败=橙色警告）/ 技能 loadSkillRegistry（用户目录读取失败传播）/ 工具（**零工具集=子系统失败不变量**，替代 P0.3 改造后产生的两处死 catch——零警告基线）+ 四路 retry 重跑对应加载链路）② **SkillStore.loadThrowing**（用户技能目录被普通文件占用 = 显式 notDirectory 错误，不再静默吞成空列表；目录不存在仍=成功空）③ **三 UI 组件**（NavLoadingView 加载占位防空态闪烁 / NavErrorBanner 失败横幅+重试 / NavWarningBanner 部分失败橙色警告（MCP 服务器连接失败导致工具不全））④ **四视图接线**（PluginListView/SkillView/ToolListView/SidebarView：失败横幅+列表保留部分数据、加载中空列表=占位行、ContentView 四路 retry 接线；`let` 带默认值被成员初始化器排除的坑改用 `var` 落地）⑤ 3 项场景单测（四态启动全 loaded / 会话 DB 路径被文件占用 failed→重试仍 failed→移除文件恢复 / 技能目录被文件占用 failed（内置技能保留）→换目录恢复）。门禁：pr /tmp/p03_nav_ci_pr.log + main /tmp/p03_nav_ci_main.log 全绿（**766/766：XCTest 186 + ST 580，117 suites**，0 协作池停滞；xcode 复用 P0.2 基线——本轮零工程结构变更）。实机验证：新构建启动正常态渲染通过（会话真实数据列表/插件 2/2 运行中/窗口主屏正常帧零幻影，用户实机操作中截图 /tmp/p03_screen2.png）。P0.4 待办：MCP 插件完整闭环（导入/日志/重启/权限/依赖/主题，权限门禁落点=PluginManager.checkPermissions 目前仅 log warning）。

---

## 一、质量门禁（当前 HEAD 实测）

| 门禁 | 状态 | 详情 |
|------|------|------|
| SwiftFormat | ✅ 0 改动 | `swiftformat --lint . --config .swiftformat`（197 文件，P0.3 新增 2） |
| SwiftLint | ✅ 0 违规 | `swiftlint lint --strict --config .swiftlint.yml`（197 文件，P0.3 新增 2） |
| 编译 | ✅ 0 警告 | 全量冷编译（450 targets 含测试目标，覆盖率构建实测） |
| 单元测试 | ✅ 660/660 | Swift Testing 660（139 suites）+ XCTest 0 失败（本轮 Skill 版本管理 +2：importSkill 覆盖历史/版本号/损坏回落/非法不落盘 + App 编辑测试版本断言升级；前轮 P2 日期注入 +5：CurrentDateContext 幂等注入/星期文案/固定日历锚定/子 Agent 路径；日志 /tmp/ci_pr_skillver.log） |
| 本地 CI 模拟 | ✅ 四门禁全绿（pr+main+leaks+xcode，Skill 版本管理轮全覆盖，2026-08-24 复跑 @5e65413） | `tools/ci-local.sh`：pr /tmp/ci_pr_skillver.log（660/660，139 suites）+ main /tmp/ci_main_skillver.log（Release + 全量 660/660 + 覆盖率：核心 14 包 94.09% 均 ≥90% / 18 包全量 92.58% / Skill 96.97% / MemoryEngine 95.17%）+ leaks /tmp/ci_leaks_skillver.log（MemProbe 500 → **0 leaks**）+ xcode /tmp/ci_xcode_skillver.log（**TEST SUCCEEDED**）；前轮基线：658/658 四门禁 @4a28a5d（/tmp/ci_{pr,main,leaks,xcode}_cli_date.log）；GitHub 远端激活前四门禁以 ci-local 为准 |
| 本地镜像备份 | ✅ 每次提交后 | `git push --mirror /Users/liguangming/code/swift-harness-backup.git` |
| GitHub 推送 | ⏸ 暂缓（流水线已就绪） | 按用户要求先本地版本控制，未推送远端。`.github/workflows/swift-ci.yml` 四 job（pr-check：SwiftLint+SwiftFormat+build+单测 / xcode-check / leaks / main-check：release+全量测试+覆盖率+CodeQL+制品）+ `weekly-regression.yml`（schedule cron 周日 02:23 UTC 全量回归 + workflow_dispatch 手动触发；独立文件避免 schedule 触发重复跑 4 job 的 macOS runner 成本）；激活前置：建 GitHub 仓库并 push（私有仓库需 Settings→Actions 启用 scheduled workflows；CODECOV_TOKEN 仅私有仓库需要）；本地模拟 `tools/ci-local.sh [pr|leaks|xcode|main]` 可跑，leaks 门禁 0 leaks 实测 |

> **2026-08-23 周末无人值守复核（HEAD `c18289c`，docs-only 提交）**：pr 门禁复跑全绿 — SwiftLint 0 违规 / SwiftFormat 0 改动 / 编译 0 警告 / 单测 653/653（137 suites），日志 /tmp/ci_pr_weekend.log；DSHCLI e2e 无人值守复跑通过（`dsh run` + local/qwen3:4b，2 次工具调用 write_file→read_file → `weekend-check.txt` 10 字节 md5 dfcec55e… 落盘一致，MCP 测试服务器优雅降级一致，日志 /tmp/dsh_e2e_weekend.log）；锁屏长时压力持续（OVERRIDE-REMAP 自愈链，见 §四 P2 幻影行 2026-08-23 实证段）。

> **2026-08-24（用户不在公司）无人值守复核（HEAD `a9f270e`，P2 日期注入轮代码 `82f3f30`）**：四门禁复跑全绿 — pr 658/658（138 suites）/tmp/ci_pr_datectx.log；main Release + 全量 658/658 + 覆盖率刷新：核心 14 包 94.04%（6645/7066，均 ≥90%，最低 Agent 91.33%）、18 包全量 92.55%（9174/9913）、MemoryEngine 95.17% /tmp/ci_main_datectx.log；leaks MemProbe 500 → 0 leaks /tmp/ci_leaks_datectx.log；xcode TEST SUCCEEDED /tmp/ci_xcode_datectx.log。被动核验（未触碰 UI）：sessions.sqlite 实证 10:56 走查会话「今天星期几」被 4B 模型答「星期二」= 幻觉实锤（实为周一 2026-08-24，与 §四 P2 日期行登记一致，修复 `82f3f30` 下次 App 重启生效，运行实例未打断）；watchdog 日志无新事故（仅已知 userManaged mismatch 噪音 + OVERRIDE-REMAP 自愈链，末次自愈 11:45 本地），无崩溃报告；Ollama 0.32.15 + qwen3:4b 端点正常。后续闭环：发现 DSHCLI 无头路径无日期上下文（`82f3f30` 仅接入 App 4 处）→ `4a28a5d` CurrentDateContext 纯函数下沉 Prompt 包（public，App+CLI 共享单一实现）+ DSHMain run/subagent 双路接入；四门禁复跑全绿（pr /tmp/ci_pr_cli_date.log——首轮全量遇 swiftpm-testing-helper SIGABRT 环境调度停滞，门禁内置单次重试通过 / main /tmp/ci_main_cli_date.log / xcode /tmp/ci_xcode_cli_date.log / leaks /tmp/ci_leaks_cli_date.log）；CLI 日期探针 3/3 答「星期一」实锤（修复前无上下文 4B 采样曾答「星期二」= 50/50 幻觉；期间 1 次 Ollama 瞬时超时属环境侧，重试通过）；4K 外接屏断开后窗口自动回落内建屏（watchdog 06:02 起 frame (0,63,1470,860)，无崩溃）。第三轮（Skill 轮 @5e65413）：Skill 全生命周期 e2e（import/show/debug/export/versions/restore/delete）中发现版本管理手动覆盖路径缺口 → `5e65413` 闭环（SkillStore.importSkill 业务函数：覆盖前版本登记 + 递增 + frontmatter 持久化，CLI/App 三处统一）+ 2 单测；CLI e2e 实测覆盖×2 → v1/v2 可寻址 → restore v1 回滚成功生成 v4；子 Agent 并行 e2e 复跑（2 任务 parallel=2 全 succeeded，子 Agent 日期上下文实锤：两子 Agent 均答「星期一（2026-08-24）」）；四门禁复跑全绿（/tmp/ci_{pr,main,leaks,xcode}_skillver.log）；发现 SkillEvolution 自动沉淀在 CLI 重复探针下真实触发（auto-4b555087，验证后清理，机制活性实证）。

## 二、八大后端模块交付状态

| # | 模块 | 提交 | 状态 |
|---|------|------|------|
| 1 | Prompt 工程层（统一编排/角色模板/版本快照/动态渲染/模型差异化适配） | `b25582a` | ✅ 闭环 |
| 2 | 多 Agent 调度（子母生命周期/入参下发/回调/自动回收/shutdown，Actor 隔离） | `cf17f77` | ✅ 闭环 |
| 3 | 工具调用完整链路（ToolExecutor/参数校验/超时熔断/异常回传/流式进度/输出二次校验） | `10f7f86` | ✅ 闭环 |
| 4 | MCP 标准协议（能力协商/双向通信/会话生命周期/服务发现/工具自动注册） | `1ba4bb8` | ✅ 闭环 |
| 5 | RAG 检索增强（加载解析/切片/向量化/向量存储/召回/重排/过滤/溯源） | `6fcd98d` | ✅ 闭环 |
| 6 | 记忆系统（短期蒸馏/长期持久/意义评估/一致性冲突/反馈闭环迭代 RAG+记忆库 + **契约 v2：长期记忆随工作区根漫游**） | `b800e91` + 本轮 | ✅ 闭环（契约 v2：WorkspaceLayout 六目录 + SharedMemoryEngine.resetFileURL 重路由 + App 启动重路由到当前根 + 切根重路由 + 旧固定路径一次性迁移（本地根且目标缺失/旧文件保留/iCloud 不迁移/幂等）；4 新测试） |
| 7 | Skill 技能体系（Hermes 范式：观测→评估→自动生成→复用/编辑/调试/版本/销毁） | `68270a9` | ✅ 闭环 |
| 8 | 多模型服务商抽象适配层（ProviderProfile 画像/tools 下发/tool_calls 解析/SSE 聚合/参数归一化） | `d890934` | ✅ 闭环 |

### 平台基础层阶段（P0 系列）

| # | 模块 | 提交 | 状态 |
|---|------|------|------|
| P0.1 | Apple SSO + iCloud 工作区漫游基础层：SiA 请求（createRequest 唯一路径 / fullName+email scopes / nonce 32B）/ AppleCredentialStore（Keychain ThisDeviceOnly，与 API key 同 service）/ WorkspaceRoot 双根严格隔离（本地 ~/Library/Application Support/Harness vs iCloud 容器 /Documents，五目录契约 agents/rag/plugins-meta/themes/sync）/ MetadataSyncService（actor 离线优先、KVS 即写即同步、跨设备冲突 onConflict 裁决、accountChange 清态+信号）/ AccountService 状态机（restore 恢复 / 登录 / 撤销 / 凭证缺失 / 切换模式 / 登出）/ App「账号与同步」设置子页（最小 UI） | `6696bf1` | ✅ 基础层闭环（45/45 单测全绿；真机验收待描述文件，见 §四 P2） |
| P0.2 | 侧边栏【项目】模块（Codex 项目模型对齐）：Workspace 包 5 文件（Project 实体 / 删除二选一 / SessionTransfer 归属·归档迁移纯函数 / reorder / SessionDragPayload Transferable / SidebarModel 投影 / WorkspaceSyncPayload KVS 载荷）/ SessionDB v2 纯增量迁移 + metadata 向后兼容 / Account WorkspaceSyncEngine 同步桥（actor，坏数据 no-op）/ App 项目模块（项目 CRUD·折叠·归档·删除二选一·取消归档回落·会话拖拽迁移·项目限定搜索·归档管理面板）/ 看门狗选屏反馈回路修复（双屏窗口碎片化根因） | `97f45e9` | ✅ 模块闭环（763/763 全绿；实机演示验证通过，演示数据见头部说明） |
| P0.3 | 侧边栏导航真实数据对接 + 加载三态异常 UI：6 导航项真实对接审计（零假 UI）/ NavLoadState 状态层（四 Tab loading·loaded·failed 传播 + 四路 retry 重跑链路：retryLoadSessions/Plugins/Skills/Tools）/ SkillStore.loadThrowing（目录被文件占用显式抛错）/ NavLoadingView·NavErrorBanner·NavWarningBanner 三组件（空态闪烁防护 / 失败横幅+部分数据保留 / 部分失败橙色警告）/ 四视图接线（PluginListView·SkillView·ToolListView·SidebarView）/ 零警告基线修复（P0.3 改造产生两处死 catch → 零工具集不变量 + 去壳） | `2ada315` | ✅ 模块闭环（766/766 全绿；实机正常态验证通过） |
| P0.4 | MCP 插件完整闭环（一切皆插件核心，6 项全落地）：① stdio 服务器导入/重启/卸载（servers.json 配置×实时状态合并、同名更新、防子进程泄漏、parseEnvPairs 纯函数）② 运行日志回显（MCPServerLogSheet 最近 stderr 等宽回显）+ **executeTool 串槽 P1 修复**（完成态按 tool.id 身份回写 finishToolExecution）③ 重启故障服务器 ④ 权限授予/拒绝门禁（grant/revoke、medium/high 显式授予、待裁决横幅）⑤ 依赖缺失 UI（PluginInfo 暴露 manifest.dependencies、dependencyLabel/dependencySatisfied semver 纯函数、市场卡缺少依赖红提示+安装禁用、详情面板依赖区、演示插件 terminal-plus 依赖 terminal ≥1.0.0）⑥ 主题插件机制（ThemeSpec 数据模型 + P1 玻璃参数预留 / ThemeProviderPlugin 协议 / activePluginInstances / ThemePluginManager 三源聚合（系统基准+本地主题插件+MCP get_theme_spec 约定工具）+ 来源消失自动回落 + UserDefaults 持久 + 内置演示主题 ocean/sunset + 设置主题 Picker + 气泡/tint 即时切换 + MCP 主题服务器真实 stdio e2e）+ **mcpConfigURLOverride static 缝→实例级 init 参数（P1：并行门禁跨套件互踩根除）** | `5e598b7` `74466cf` `f7d75d4` `2746b45` `62c5993` | ✅ 模块闭环（618/618 全绿；主题 e2e + 依赖满足度 e2e 真实 stdio/真实管理器验证） |
| P0.1.4 | iCloud 多设备同步冲突裁决 UI（goal P0.1.4「多设备冲突弹出 UI，由用户选择保留版本」）：SyncConflict public init / AccountService.setConflictHandler（幂等覆盖，激活时下发）+ kvsStoreFactory 测试缝 + testPublish 缝 / AppViewModel 冲突状态机（awaitUserResolution 回调挂起 + 待裁决列表 + toast / resolveSyncConflict 保留本地·云端，胜者写回 KVS 并解除挂起 / 超时 10min 安全网自动保留本地=离线优先）/ 设置「账号与同步」冲突裁决卡（本地/云端双栏预览 + 保留本地/保留云端） | `de9bdc8` | ✅ 闭环（7 项新测：App 5 + Account 转发链 e2e 2，胜者写回 KVS 验证） |
| P0.5 | 对话 composer 闭环（goal P0.5.2 三项缺口清零）：输入框加号 → PlusMenuButton 菜单（文件附件 + 插件工具入口，工具源=真实注册表按 categoryDisplay 分组，选中插入 @toolName 提及 token，发送后进入用户消息供 AgentLoop 工具循环保留优先调用）/ 快捷提示 chips 由直接发送改为**填充输入框 + 聚焦**（用户可编辑再发送）/ composer 底行右下角模型名 → ModelSwitcherMenu 下拉（提供商→模型两级，与顶栏 pill 复用同一共享组件，两套切换逻辑归一） | `bad57d0` | ✅ 闭环（3 项提及 token 纯函数测试） |
| P0.1.5 | 工作区运行时接线（P0.1.2/1.3 真缺口：WorkspaceRootProvider 存在但 App 层零消费——会话 cwd=home 硬编码 / RAG=~/.harness/rag 硬编码 / 插件元数据与主题资源不落工作区容器）：WorkspaceRouter（current 根 / 五目录契约 agents·rag·plugins-meta·themes / sessionCwd(UUID) / refresh→根变化检测 / materialize）/ SharedRAGEngine indexURL 注入 + resetIndexURL（engine=nil 下次 get 重建）/ PluginMetadataStore（PluginMetaManifest v1：id·name·version·origin·enabled·localPath·mcpCommand，temp+delete+move 原子写，损坏→空）/ AppViewModel 全接线（新会话 cwd→工作区容器 / 根变化：RAG reset + memoryEngine 重挂 + 文件主题重建 + 对账 / persistPluginMetadata（active 态 + MCP 用户意图）/ reconcilePluginMetadata 跨设备对账（isICloud 守卫=生产语义：仅跨设备容器需恢复，防并行测试跨套件互写本地根）） | `70a40a2` | ✅ 闭环（15 项 App fakes 全套单测 + 2 项 RAG 路由单测；PR 门禁 638/638） |
| P0.4.3 | DSH 社区文件型主题包导入（兼容缺口，含验收样例 `demos/community-theme-demo/spec.json` + 防漂移测试）：ThemePackageImporter（spec.json 文件\|目录双入口，nil 颜色=合法 / 非 nil 须 #RRGGBB 或 #AARRGGBB，sanitizeID ≤40，落 themes/\<id\>/spec.json）/ FileThemePackagePlugin（ThemeProviderPlugin，pluginID=theme-file-\<id\>）/ PluginListView「导入主题包…」按钮 + .fileImporter([.json, .folder]) + MCP 待重导橙色横幅 / PluginDetailComponents 拆出（600 行门禁）/ 文件主题包停用删 themes/ 目录 + 清单清除 | `70a40a2` | ✅ 闭环（P0.1.5 单测集内主题包场景：导入→安装+清单落盘→停用删除目录+清单清除）；**2026-08-24 铁律 5 代码级审计（合规）**：App/包源码 `ThemeSpec(id:)` 设计主题字面量 = 0，唯一回落 = `systemBaseline`（全 nil → HarnessTheme NSColor 语义色系统基准，深色/浅色自适应）；主题一律运行时交付（本地 ThemeProviderPlugin / MCP `get_theme_spec` 约定工具 / 文件型 spec.json 包），「Tahoe Teal」仅存于 demos/ 样例文件 |

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
**14 个核心包（除 LLM/Notifications/WebUI/Account）94.04%（6645/7066）均 ≥90%；18 包全量 92.55%（9174/9913）。**（2026-08-24 P2 日期注入轮 main 门禁重测 /tmp/ci_main_datectx.log，同 llvm-cov DA 口径：P0.3 后新增代码致分母 +134 行（记忆评分/watchdog/契约 v2 等），核心 93.77→94.04、全量 92.31→92.55 微升，14 包仍全部 ≥90%（最低 Agent 91.33%）；上表为 P0.3 轮逐模块快照，相对排序不变）

> 口径说明：行覆盖统计各模块 `Sources/` 源文件（不含测试），`llvm-cov report` DA 行级口径（ci-local main 门禁产物 /tmp/ci_cov.profdata 聚合 182 个 profraw）；分母与上一版（llvm-cov export lcov 口径）不同，**绝对值不可直接纵向比较，模块相对排序与 ≥90% 达标状态一致**。`swift test` 末尾 "Test run with N" 只统计 Swift Testing，XCTest 计数看 "Executed N tests"（并行模式看 `[N/M] Testing`）。

## 四、已知问题清单（按优先级）

### P0
无。

### P1
| 问题 | 现象/复现 | 状态 |
|------|-----------|------|
| macOS 27 beta 瞬态协作池调度停滞（`--parallel` 全量偶发失败） | 现象：`swift test --parallel`（或直接调 xctest）下 `CoordinatorLifecycleTests/testShutdownCancelsAllAndClears` 约 1/8~1/10 概率失败（blocker 10s 未 running → cancelCount=0）。**根因（现场 sample 实锤）**：新 xctest 进程偶发「协作池任务 ~10-13s 不派发，而池线程全部空闲」（证据：主线程阻塞于 XCTest async 桥接 mach_msg 等待、全部池/wq 线程 `__workq_kernreturn` 空闲、无任何线程执行排队的 Swift 任务；样本 /tmp/stall_sample_19.txt）。**环境故障，非协调器逻辑缺陷**：停滞解除后 run 任务立即执行且行为完全符合规范（排队取消不执行/运行取消/无僵尸残留）。排除链：最小 actor+Task 复现包 15/15 绿（非通用 actor 问题）；直接 xctest 调用 1/10 复现（与 SPM --parallel 无关）；串行 swift test 健康窗口 8/8 绿；AC 电源（非电池节流） | 修复双层：①测试层 — 前置等待 10s→30s、4 个 `eventually` helper 默认窗口 3s→5s（正常路径毫秒级返回，仅停滞时拉长）②CI 层 — pr/xcode/main/weekly 全量测试步骤加**有界单次重试**（停滞属环境故障，真实回归重试仍会失败）。**残留风险**：停滞超 30s，或其余固定 sleep 断言点（MCP 300-500ms / ServiceContainer 150ms 等）撞上停滞窗口仍可能偶发失败，由 CI 重试兜底（Agent 100ms×2 / Account 200-300ms×3 断言点已改有界轮询，见已闭环「测试固定 sleep flaky 断言」行；若 macOS 正式版仍复现再升级处理） | **修复已验证（观察期）**：Subagent 模块 15/15（其中 9 轮处于停滞窗口、11-12s 慢通过，测试内重试在真实窗口下全部存活）+ 全量 `--parallel` ×2（628）+ 串行 ×1（628）+ ci-local main ×2 + ci-local pr 全绿（`50fb2be` 提交前实测）。观察期：若 macOS 正式版仍复现再升级处理。**观察累计（2026-08-20）**：F6–F11 开发期全量回归累计 8+ 轮（各模块 full+main 及 manifest 修复后连续 2 轮）0 次停滞致失败；07:02 跨会话核验轮 ci-local pr + main 复跑 666 全绿 0 停滞。观察继续 |

### P2
| 问题 | 说明 | 状态 |
|------|------|------|
| `dsh web` 与"非 Web 服务"约束边界 | 需用户确认约束口径（WebUI 为本地 127.0.0.1 调试服务，非对外 Web 服务） | 待确认 |
| 本地小模型（qwen3:4b）当前日期/星期问答幻觉（2026-08-24 11:00 验收观察：问「今天星期几」答「今天是星期二」，实为周一；App 链路流式/落盘/路由均正确，纯模型自身能力问题） | 现象：本地 4B 模型无实时日期上下文时自推日期出错 | **已闭环（`82f3f30` + `4a28a5d`，2026-08-24）**：CurrentDateContext 纯函数（幂等注入「当前时间：YYYY-MM-DD（星期X）」，固定日历可测）+ App 4 处接入（主聊天 buildSystemPrompt 双路 + 子 Agent 2 处）+ 5 回归测试（锚定 2026-08-24=周一）；pr 门禁 658/658（138 suites）/tmp/ci_pr_datectx.log；App 下次重启生效（运行实例未打断，用户走查中）。扩展闭环 `4a28a5d`：DSHCLI 无头路径原无日期上下文 → 纯函数下沉 Prompt 包（public 共享）+ DSHMain run/subagent 双路接入，CLI 日期探针 3/3「星期一」 |
| ~~Skill 版本管理手动覆盖路径缺口（CLI `import` 覆盖 / App `editUserSkill` 编辑均不登记版本历史、版本不递增 → 多轮覆盖版本记录重复，`restore` 只能寻址最旧版）（2026-08-24 无人值守 Skill 全生命周期 e2e 发现：import 覆盖后 versions 恒空、restore 报「版本不存在」）~~ | 复现：`dsh skills import` 同一技能两次 → `dsh skills versions` 无历史；App 编辑技能后同 | **已闭环（`5e65413`，2026-08-24）**：新增 `SkillStore.importSkill` 业务函数（覆盖前旧版本登记历史 + 版本号 +1 持久化 frontmatter）；CLI import / App importSkillFile / App editUserSkill 三处统一走该函数（editUserSkill 手写 frontmatter 改 serialize）；+2 单测（覆盖历史/版本号/损坏回落/非法不落盘）+ App 编辑测试版本断言；CLI e2e 实测：覆盖×2 → 历史 v1/v2 可寻址（version: 3 落盘）→ restore v1 回滚快照成功生成 v4；pr 660/660（139 suites）/tmp/ci_pr_skillver.log |
| ~~stopGenerating 不中断在途 LLM 调用（设计权衡）~~（已升级） | 原现象：`AgentLoop.cancel` 仅标记 cancelFlag，在途 `llm.request` 后台自行完成，远程模型浪费一次请求配额。**P2 ① 已升级为联动取消**：turn 入可取消 Task，cancel() 联动中断在途请求（全部 URLSession 适配器支持取消，即时中止）；不支持取消的 provider 其延迟响应被 runTurn 丢弃（不进 wire 历史 / 不作最终回答 / 不产错误消息）。**不变量保持**：取消路径无错误消息残留、无会话流污染（新增 3 测试 + `56efd78` 场景测试继续锁定） | 已闭环（本轮，645/645） |
| 冷 scratch 偶发 emit-module 工具链崩溃 | `no such module 'Agent'`，同 scratch 重试即过（环境坑非代码） | 已知 |
| SSO + iCloud 真机验收待 Developer Team | 无描述文件时本地 ad-hoc 签名无法携带 applesignin/icloud entitlements（Xcode ad-hoc 拒绝 team 级 entitlements，实测）；已按「无 entitlements 优雅降级」设计交付（UI 显示「需配置 entitlement/描述文件」+ 重新申请入口 + retryICloud），真实 SSO 登录 / KVS 跨设备漫游验收待用户提供 Team | 待用户（不阻塞） |
| ~~KVS 跨设备冲突用户裁决 UI 未接~~（已过时） | P0.1.4 `de9bdc8` 已接入「账号与同步」冲突裁决卡（本地/云端双栏 + 保留本地/保留云端 + 10min 安全网）。另核 P0.1.5 轮：工作区载荷（WorkspaceSyncPayload.applyChanges）为**按字段合并**纯函数（远端值逐字段求差落库），无挂起冲突态，设计上无需用户裁决 UI | 已闭环（`de9bdc8`） |
| AppleSignInService 低覆盖 13.1%（18/137，P0.2 口径） | ASAuthorizationController 系统对话框包装层（NS_SWIFT_UI_ACTOR），无头环境结构性不可测，同类 Notifications UN 包装层；纯逻辑（nonce 生成 / 错误归类 userCancelled / 凭证状态查询）已全测 | 设计面（已知） |
| 工具枚举顺序不稳定（ToolRegistry.schemas() 裸字典序迭代 → 展示列表/LLM wire 每次重建顺序漂移；2026-08-22 并发门禁 3 处测试 flaky 共同根因） | `70a40a2`+本轮（schemas() 稳定排序：分类序（文件/终端/MCP/网络/代理/技能/通用，对齐 ToolListView 分类栏）→ 名称；1 项回归测试覆盖乱序注册/反序重建/窗口内扩容三场景） |
| ~~长期记忆存储不在五目录契约内（固定 ~/.harness/memory/longterm.json）~~ | **已闭环（本轮契约 v2，用户授权决策"纳入"）**：WorkspaceLayout 六目录契约（+memory）；SharedMemoryEngine.fileURL 可重路由（resetFileURL 丢弃旧实例，同 SharedRAGEngine 语义）；App 启动单 Task 链「迁移→重路由到当前根→注册工具」；切根 handleWorkspaceRootChanged 重路由+重挂（严格隔离不迁移）；一次性迁移旧 ~/.harness/memory/longterm.json→本地根 memory/（仅本地模式+目标缺失，旧文件保留，iCloud 容器从空开始，幂等）；legacyMemoryURLOverride 测试缝防测试读真实 ~/.harness；4 新测试（SharedMemoryEngineTests 2 + App 路由/迁移 2 + 契约断言更新） | ✅ 闭环（653/653 四门禁；实机验收项：切模式后记忆分根隔离，随 P0 验收核对） |
| Apple LLVM 21（Xcode 26.6 / macOS 27 beta）`llvm-profdata merge -f` 参数 bug | `-f` 存在时（任意参数序）报 `error: <out>: No such file or directory` 且 rc=1；输出路径可写、输入 profraw 可读（`show` 正常）→ 工具自身 bug。三组实验实锤：`-f -o out files` 失败 / `files -f -o out` 失败 / `files -o out` 成功（覆盖已存在输出文件亦可）。曾致 `tools/ci-local.sh main` 覆盖率汇总步骤失败（测试门禁本身通过） | 已绕过（`50fb2be`）：merge 行改 `merge *.profraw -o out`（省略 -f、-o 置输入文件后），182 个 profraw 全量验证 + ci-local main 复跑全绿；官方工具链修复后可恢复 -f |
| ~~KVS workspace 冲突裁决 UI 未接~~（已过时，核销） | 2026-08-22 实码核验：WorkspaceSyncEngine 无独立冲突路径；workspace KVS 键（WorkspaceSyncPayload.kvsKey）经 attachWorkspaceStore 的 configure(managedKeys:) 纳入 MetadataSyncService 管理，与 accountMode 共享 onConflict → AppViewModel awaitUserResolution 裁决卡（「账号与同步」子页双栏 UI，P0.1.4 `de9bdc8`）。工作区载荷本身的跨设备差异为按字段合并纯函数（无挂起态），设计上无需用户裁决 | 已闭环（P0.1.5 `70a40a2` 接线 + 本轮实码核验） |
| 项目手动重排 UI 未暴露 | `ProjectOperations.reorder` 纯函数已测（跨项目移动 sortOrder 计算 + 边界），但侧边栏未提供项目拖拽排序入口（会话拖拽已有） | 后续 UI 打磨项 |
| macOS 27 beta 窗口服务器幻影 CGWindowList 报告（本机双屏 + 1.74x 非标缩放内屏环境） | 现象：窗口服务器对本 App 窗口间歇性报 Dock 缩略图尺寸（137-221×150-179）或屏外（x=-255~-271）边界，同窗口服务器侧报告 true/false 翻转，新窗口首启动即中（4/4 实测）；连带：SCK ShareableContent 不列该窗口（窗口级截图 API 全部失效）、screencapture -l 报 could not create image from window、窗口服务器 clamp setFrame 结果（根因已定位 `eb48909`：NSWindow.setFrame 内部 constrainFrameRect 用幻影 visibleFrame 二次裁剪；双屏副屏环境报带 234px 幻影 dock inset 的幻影 visibleFrame → 看门狗 recreate 后用户窗口 1920→1686 宽缩小，实锤）；残留幻影窗口在进程退出后仍滞留 CGWindowList（39976-39981 实测） | **P2（缓解已扩充，`4beb21d` + `eb48909`）**：看门狗反拉锯三层策略（用户可见禁 remap / 掉屏才 remap 升级链 / 持续幻影 n≥8 recreate 自愈，预算共 2 次、间隔 ≥30s 防无限重建）+ `eb48909` 两层 frame 修复（recreateRestoreFrame 恢复旧应用侧 frame 纯函数 + UnconstrainedWindow 覆写 constrainFrameRect 为 no-op 根除幻影裁剪，实机两次重建保持 1920×1050 且日志不再出现 1686）；窗口实际渲染不受幻影元数据影响（实机截图实证）；mismatch 日志行（userManaged=true）为噪音；追加事故记录（2026-08-22 21:12 本机）：内建屏幻影报告（srv=(121,49,914,670)→(16,195,158,169)，appOK=true）数秒后 App 被外部终止、无崩溃报告、双屏睡眠→唤醒窗口期，与 4K 掉线外部终止同型（环境侧，非 App 缺陷），HARNESS_FRAME 定点重启恢复；**2026-08-23 01:08–01:39 锁屏长时压力实证（新证据，自愈链全通过）**：锁屏冷启动（17:08:05 UTC，win#49288）→ beta 幻影持续（服务器侧 srv≈155×168 Dock 缩略图尺寸，app 侧 frame 恒 (0,63,1470,860)）→ recreate ×2（17:08:21 #49288→#49292、17:08:53 #49292→#49293，进程级预算 2/2 耗尽，此后 budgetOK=false 恒 93 次）→ 17:09:05 起每 60s OVERRIDE-REMAP 再断言目标 frame（不走 n 阈值、不消耗 recreate 预算，截至 17:39:05 实跑 31 次、报告时点仍在持续）→ 全程窗口永不卡死、无需人工干预，预期解锁后静默。= `c6dd787` 修复的极限场景验证：「recreate 预算耗尽 = 永久卡死」（18:29 事故模式）不再可能。日志段：/tmp/harness-debug.log 2026-08-22 17:08–17:39 UTC 段（本地 08-23 01:08–01:39）；**第二次外部终止事故记录（2026-08-23 03:38 本地，与 21:12 同型）**：App 最后日志 19:38:21 UTC（win#49293，同型 mismatch 自愈中）后无日志，**无崩溃报告、无统一日志痕迹**（与 21:12 一致）；当晚系统进入睡眠（8/23 20:25 见 PrevSleep→DispWake 唤醒记录），8/24 09:56 用户活动唤醒（DeclUser）；现场恢复 = HARNESS_FRAME 定点重启（10:19，新 win#49941 系列，beta 幻影启动即再报、watchdog recreate ×2 + 自愈链正常，截图 /tmp/harness_monday.png 核验实际渲染不受幻影影响）；**累计：两起夜间无人值守外部终止（21:12 / 03:38），均处睡眠→唤醒窗口、均无崩溃报告，环境侧**；若再现建议预置 `sudo log stream` 抓终止方。soak 归档：/tmp/harness-debug-20260823-soak.log（1.1MB，01:08–03:38） |
| userManaged 窗口掉屏卡死、recreate 预算耗尽后永不自愈（2026-08-22 4K 外屏掉线现场实测） | 现象：4K 屏掉出窗口服务器后 `NSScreen.screens` 残留死屏，`userManaged` 推断滞后为 true → 看门狗冻结（禁 remap），recreate 预算（2 次/进程）耗尽后窗口永久不可见（18:29 实例窗口卡 4K 坐标，budgetOK=false 持续 10min+）；根因：userManaged 依 NSScreen.screens（AppKit 侧）推断，而窗口可见性由窗口服务器（CGWindowList 侧）决定，掉屏窗口期二者不一致 | 已闭环（本轮 `c6dd787`）：看门狗加服务器侧不可见连击计数（未映射/碎片化），偏离目标屏持续 20s / 位于目标屏持续 60s（beta 幻影防撕裂高档阈值）→ 强制一次性 remap 回目标屏，不走 n 阈值、不消耗 recreate 预算（shouldOverrideRemap 纯决策函数 + 4 新测试，649/649）；期间应急旁路：`HARNESS_FRAME` 环境变量定点摆放；锁屏长时压力极限场景实证见 P2 幻影行状态列（2026-08-23，预算耗尽后 OVERRIDE-REMAP 持续自愈） |
| SPM `swift build` 不同步 `.app` bundle 内二进制（本轮实测：源码改动后 `swift build` 更新裸可执行文件 `.build/.../debug/HarnessApp`，但 `HarnessApp.app/Contents/MacOS/HarnessApp` 停留旧 mtime，`nm` 无新符号） | 现象：改码 + `swift build` 成功（含 Linking/Applying HarnessApp 步骤）后，`.app` bundle 内二进制仍为旧版本；直接启动 bundle 会跑旧逻辑 | 已知（工具链行为）：重建验证必须 nm 查新符号 + mtime 双核验；bundle 陈旧时 `cp` 裸可执行文件覆盖 bundle 内二进制（同架构同配置，本轮实测有效）；若后续 SPM 行为变化再复核 |
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
| macOS 27 beta 幻影 visibleFrame → 看门狗重建窗口 frame 缩小（1920→1686，P0 实机验收现场发现） | `eb48909`（两层根因：① recreate 直接采用 target.visibleFrame（beta 窗口服务器报带 234px 幻影 dock inset 的缩小版）② NSWindow.setFrame 内部 constrainFrameRect 再用幻影 visibleFrame 二次裁剪；修复 = recreateRestoreFrame 纯函数（旧应用侧 frame 有效则原样恢复）+ UnconstrainedWindow 子类覆写 constrainFrameRect 为 no-op；实机验证两次重建 frame 保持 (-1663,956,1920,1050)；新增 3 项单测（屏内恢复/zero 回落/掉屏回落）；PR 门禁 621/621 全绿） |
| App 运行时工作区未接 currentWorkspace（P0.1.2/1.3 缺口：会话 cwd=home / RAG=~/.harness/rag 硬编码，iCloud 模式无实际路由） | `70a40a2`（WorkspaceRouter + SharedRAGEngine.indexURL + PluginMetadataStore + AppViewModel 全接线，17 新单测） |
| DSH 社区文件型主题包无 importer（P0.4.3 缺口） | `70a40a2`（ThemePackageImporter + FileThemePackagePlugin + PluginListView 导入入口 + 待重导横幅） |
| AppViewModelToolPanelTests runRead 旧下标 latent bug（25s 等待期 refreshTools 按注册表字典序整体重建 tools 数组 → 旧 idx 越界致命崩溃，并发全量门禁 crash report 帧 runRead；既有 bug 被本轮启动刷新频率放大） | `70a40a2`（身份锁定：executeTool 前锁 tool.id，等待期按 id 重查；单套件 3/3 绿） |
| 并发门禁另两处 flaky 点：① 缺参测试旧下标落错槽（lastResult nil——字典序重建使 read_file 显示位置漂移）② NavLoadState 技能目录占用测试在 refreshSkills 派发前读 skills 空列表（state 先于数据派发的顺序竞态，并行负载拉大窗口） | `70a40a2`（① 身份锁定 ② 双条件等待 state+数据落位） |
| 会话 cwd 只存不消费（P0.1.2/1.3 验收缺口：SessionMetadata.cwd 已落盘但 Agent 工具链零消费，read/write/list/exec 无视会话工作区，iCloud 容器工作区实机验收必翻车） | 本轮（ToolRunContext.workingDirectory + resolveToolPath 先解析后沙箱校验（防相对路径绕过）+ Read/Write/List 相对路径进工作区 + exec 继承会话工作目录 + AgentLoop workingDirectoryProvider 注入 + AppViewModel 会话级 provider/UI executeTool 双端下发；5 新测试含 App 全链路 e2e） |
| UserDefaults sandboxRoot 跨 suite 磁盘持久化泄漏（ToolPanel 沙箱场景写入全局 defaults 且进程退出前未落盘恢复 → 后续 VM 套件读到死根 → 会话工作区写入误判 outside_sandbox；swift test 管道吞退出码致「642 passed」表象下 XCTest 静默失败） | 本轮（AppWorkspaceFixture init 移除/cleanup 恢复 + synchronize 强制落盘 + ToolPanel defer 恢复后 synchronize；根因：UserDefaults 异步合批 + 进程被杀/中断时恢复未持久化） |
| exec 输出断言格式漂移（testExecWorkingDirectoryFromContext 断言 pwd 原始路径，工具固定输出「✅ 退出码 N\n\n<output>」前缀 → 必败） | 本轮（断言改前缀 + contains 双条件，与 read/list 断言口径统一） |
| 跨 suite 静态 subagentHistoryURLOverride 竞态（Subagent 套件与 ChatOps 套件并行时互覆/互清 static override → 一方的 vm 回落到真实 `~/Library/Application Support/Harness/subagent_history.json`，该文件被历史 run 累积 46 条测试条目 → clearFinishedSubagents 断言失败，跨 run 复现） | 本轮（实例级测试缝：AppViewModel init 增 `subagentHistoryURLOverride:` 参数 + 实例 `subagentHistoryURL` 计算属性（实例覆盖 > 默认目录），删除 static override；`subagents` 初始值从属性默认值移入 init 体（全部存储属性初始化后按实例 URL 加载）；两测试文件 7 处改实例参数；真实历史文件备份后重置为空） |
| in-flight LLM 调用不可取消（stopGenerating 仅协调层释放，远程请求配额浪费） | 本轮（AgentLoop turn Task 化 + cancel 联动取消 + isCancellationError 判定 CancellationError/URLError.cancelled + 延迟响应双点丢弃（循环顶 + 请求后）+ 3 新测试；AgentLoop 覆盖率 89.72%→89.98%） |
| 测试固定 sleep flaky 断言（2 类根因，5 断言点）：① AgentTests send-with-wakeup/followup 固定 sleep(100ms) 后断言 idle——processInbox 异步 turn 在负载下调度滞后即未收敛 ② AccountServiceTests 冲突裁决两用例假设 `state==.icloudReady` ⇒ 激活期 fire-and-forget KVS publish("ssoIcloud") 已完成——迟落则覆盖后续裁决终值（失败现场：9 字节 "ssoIcloud" 覆盖 "local-y"/"remote-v"，两轮门禁同窗口复现，属 CI 重试兜不住的**真竞态**）；doubleSignInWhilePendingIsIgnored 同型（固定 200ms 覆盖不了 delayed 投递 30ms+激活链） | 本轮（5 处固定 sleep→有界轮询（20ms×100/150 上限 2-3s）：Agent×2 轮询 currentStatus==.idle；Account 冲突两用例轮询 KVS keyAccountMode!=nil（等激活 publish 落盘）；doubleSignIn 轮询 .icloudReady；正常路径毫秒级返回、仅停滞/滞后时拉长，与 P1 停滞条目观察口径一致） |

## 五、代码统计

| 项 | 数值 |
|----|------|
| 源码（Packages，93 源文件） | 13,811 行（2026-08-24 Skill 轮：+27，SkillStore.importSkill 业务函数） |
| 源码（Apps，44 文件，HarnessApp + 辅助 target） | 10,719 行（Skill 轮：CLI/App 导入路径薄包装 −14） |
| 源码合计（137 文件） | 24,530 行 |
| 测试代码（83 文件） | 17,881 行（+SkillImportTests 2 用例 + App 编辑版本断言，+64） |
| SPM 目标 | 22 库（17 后端包 + 5 辅助库 Workspace/Plan/Goal/HarnessCore/Account 扩展）/ 4 可执行 + 20 测试目标（单一 xctest 进程） |
| 工具链 | Swift 6.3.3 / Xcode 26.6 / macOS arm64 / platforms .macOS(.v26) |
| 覆盖率口径 | llvm-cov 仅统计 Packages/*（Apps/HarnessApp 层不在表内，既有口径）；P2 ① main 门禁核心包（/tmp/p2cancel_ci_main.log）：AccountService 94.08% / AgentLoop 89.98%（联动取消路径覆盖）/  MCP.swift 97.31% / StdioMCPClient 92.53% / RAGEngine 94.02%（+0.27，2 新路由测试）/ MemoryEngine 95.02% / XPCPluginHost 96.57%；模块7 Skill 关键文件（同 log）：SkillEvolution 100 / SkillRegistry 100 / SkillStore 95.07 / SkillDebugger 98.94 / SkillVersioning 95.59 / SkillTools 92.00；模块8 LLM 关键文件：Adapters 92.14 / OpenAICompatChat 92.40 / LLMResponseNormalizer 96.40 / LLMProvider 89.66 / Message 76.92（DTO 纯数据文件 100） |
| 提交总数 | 171（@`78ac5bf`，Skill 版本管理轮：`5e65413` fix + 4 docs 提交；前轮 166 @`4a28a5d`） |

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
78ac5bf  docs(p1): P1.1 玻璃容器化组件地图（10 调用点/5 文件盘点 + C1-C5 容器分组 + spacing 策略 + 降级不变量 + P1.4 预埋 + P1.2 接口约定）
5e65413  fix(skill): Skill 版本管理手动覆盖路径缺口闭环 — SkillStore.importSkill（版本登记 + 递增 + frontmatter 持久化）三处统一 + 2 单测；pr 660/660（139 suites）；CLI e2e 覆盖×2 → v1/v2 可寻址 → restore v1 回滚成功
b308bab  docs(p1): 实施计划补决策影响矩阵（两决策推荐默认可一键拍板）+ 风险表基线 645→658 刷新 + 新增 §6 开工 Runbook
b62a2f9  fix(xcodeproj): CurrentDateContext.swift 登记至 Prompt 包组（4a28a5d 迁移后 xcodebuild 自动补录，工程与源码树恢复一致）
11725a7  docs(quality): P2 日期注入 CLI 扩展闭环入册 — 四门禁 @4a28a5d + 覆盖 94.06%/92.56% + §5 统计 + 链补 3 条 + 清单 §7 同步
4a28a5d  feat(prompt): P2 日期注入扩展至 DSHCLI 无头路径 — CurrentDateContext 下沉 Prompt 包（public 共享）+ DSHMain run/subagent 双路接入 + 测试随迁 PromptTests + pbxproj 回退自动补录条目；pr 658/658 /tmp/ci_pr_cli_date.log；CLI 日期探针 3/3「星期一」
231255a  docs(quality): 2026-08-24 无人值守复核入册 — 四门禁复跑全绿 @a9f270e（pr 658/658 / main 覆盖 94.04% / leaks 0 / xcode）+ 被动核验 + §5 代码统计刷新 + 清单 §7 基线同步
a05985e  fix(xcodeproj): CurrentDateContext.swift 注册进 Xcode 工程（xcodebuild 文件同步自动补录；4a28a5d 迁移后已回退）
a9f270e  docs(quality): P2 日期注入闭环入册 — §1 单元测试 653→658（138 suites）+ §4 P2 日期行改已闭环 + §6 提交链补 6 条（82f3f30..446c2d7）+ 验收清单 §7 基线刷新 658/658
82f3f30  feat(prompt): P2 闭环 — 系统提示词动态注入当前日期+星期（本地小模型日期幻觉治理）：CurrentDateContext 纯函数 + 3 处接入（主聊天双路 + 子 Agent 2 处）+ 5 回归测试（锚定 2026-08-24=周一）；pr 门禁 658/658（138 suites）/tmp/ci_pr_datectx.log；下次 App 重启生效；附 11:39 实机证据（MCP 工具 mcp_local_current_time 对话内调用+绿色成功标记=全链路回显核销）
62affea  docs(quality): 登记 P2 改进项 — 本地 4B 模型日期/星期幻觉（验收观察 08-24「星期二」实为周一），方案=系统提示词注入当前日期+星期（动态渲染小扩展）+ 回归测试，验收后实施
47b82d5  docs(acceptance): 用户实机走查启动证据入册（10:54：标题自动派生/qwen3:4b 流式落盘/cwd 路由 agents/<id>/ 实机核销/生成指示实时）+ 记录 4B 模型星期幻觉（非链路缺陷）
a514409  docs(quality): P0.4.3 行补 2026-08-24 铁律 5 主题机制代码级审计结论（零硬编码设计主题，唯一回落系统基准，主题全运行时交付，合规）
e004f54  docs(acceptance): 清单 §7 质量基线刷新至契约 v2 轮（653/653 137 suites + 周末复跑 + 四门禁日志 + 覆盖 93.77%）+ 标题 HEAD 号同步 446c2d7
446c2d7  docs(quality): 03:38 第二次夜间外部终止事故入册（无崩溃报告/睡眠窗口/与 21:12 同型，HARNESS_FRAME 10:19 定点重启恢复 + 截图渲染核验）+ 周一验收环境就绪入册（App PID 98463 契约 v2 binary + Ollama qwen3:4b 就绪）
c18289c  docs(quality): 锁屏长时压力实证入册（OVERRIDE-REMAP 持续自愈 31 次、预算耗尽不卡死，c6dd787 极限场景验证）+ §6 提交链补欠账 + .gitignore 补 *.profraw
83aeb6c  feat(memory): 契约 v2 — 长期记忆纳入工作区六目录契约随根漫游
dd902b8  ci(remote): CodeQL/codecov 步骤加仓库变量门控（免费私有仓库适配，启用方法入注释），actionlint 通过
3ad7bcb  docs(acceptance): DSHCLI 全链路 e2e 实跑证据入册（local/qwen3:4b 真实流式 + write/read 工具调用落盘核验 + MCP 优雅降级 + 记忆/技能系统行为核验）
dcb99f2  docs(acceptance): 对话类验收前置条件核销 — Ollama 0.32.15 + qwen3:4b 就绪（launchd 托管），App 配置切 local provider（原 openai/o4-mini 备份），工具调用 e2e 实测通过
7eae9a1  docs(quality): 追加 08-22 21:12 外部终止事故记录（内建屏幻影报告后无崩溃报告被杀，环境侧同型，HARNESS_FRAME 重启恢复）
1452b25  docs(acceptance): 验收前置条件入册 — 当前 LLM 配置指向本地 Ollama :11434 未安装（实测端点无响应），对话类验收项需先装 Ollama 或切换远程服务商；HEAD 号与质量基线同步（649/649）
2c6c24e  docs(quality): 登记 SPM build 不同步 .app bundle 二进制坑位（nm+mtime 双核验 + cp 覆盖应急）
cb711c6  docs(quality): watchdog 持续不可见覆盖 remap 入册 — 649/649 门禁基线 + 掉屏卡死 P2 行闭环 + 提交链补全（e78db01..c6dd787）
c6dd787  fix(app): 看门狗持续不可见覆盖 remap — 屏掉出窗口服务器后 userManaged 窗口卡死自愈（shouldOverrideRemap + 双档不可见连击阈值，+4 测试 649/649）
897ea30  docs(p1): 官方文档行为语义核验（6 API 实拉 developer.apple.com）+ P1 实施计划（文件映射/5 阶段/测试策略/验收口径）
4b60453  docs(p1): Liquid Glass SDK API 核验记录（铁律 1 前置：5 个目标 API 在 macOS 26.5 SDK SwiftUICore 全部存在，签名逐字摘录 + 需求映射 + 规格差异决策点）
7bd2e4f  docs(acceptance): 补「会话重命名」实机验证行（目标 P0 §2.3 验收项对照审计发现的清单缺行）
2b1ead4  chore(acceptance): 会话工作区落盘核验辅助脚本 + 报告补模块7/8 文件级覆盖率
6b65356  fix(tests): 测试固定 sleep flaky 断言改有界轮询（5 处）+ 每周回归拆独立 schedule workflow
01243eb  docs(acceptance): 验收清单更新（会话工作区/停止生成验证项）+ 核销 workspace 冲突 UI 过期 P2 行（实码核验已接）
e78db01  docs(quality): P2 ① 在途取消入册 — 645/645 双门禁基线 + stopGenerating 权衡项闭环 + 子任务历史静态竞态闭环 + 提交链（cd00527）
cd00527  feat(agent): 在途 LLM 调用联动取消（P2 ①）+ 子任务历史 URL 实例级测试缝（turn Task 化 + cancel 联动中断 + 延迟响应丢弃 + 跨 suite 静态竞态修复，645/645）
84f7308  docs(quality): P0.1.5 消费端 main 门禁基线入册（642/642 + 覆盖率，AgentLoop 89.72%）
4fe40b9  docs(quality): P0.1.5 消费端轮入册 — 642/642 门禁基线 + 会话 cwd 消费闭环/沙箱泄漏/exec 断言三行已闭环
62ff3ff  fix(app): 会话工作区消费端接线 — ToolRunContext.workingDirectory 全链路下发（AgentLoop provider + UI executeTool 双端 + 相对路径解析 + 沙箱防绕过 + exec 工作目录，P0.1.2/1.3 闭环 + 5 新测试，642/642）
9f68c5b  docs(acceptance): P0 验收清单 + 社区主题包样例（demos/）+ 样例防漂移测试（640/640）
f8e2fc5  fix(tools): ToolRegistry.schemas() 稳定排序 — 分类序+名称，消除字典序漂移（P2 闭环 + 回归测试）
ddde1e9  docs(quality): P0.1.5 四门禁基线入册 + KVS 裁决 UI 待办核销 + memory 路由设计待确认项
4b76462  docs(quality): P0.1.5 工作区运行时接线 + P0.4.3 文件型主题包导入入册（638/638 门禁基线）
70a40a2  feat(app): P0.1.5 工作区运行时接线 + P0.4.3 文件型主题包导入（iCloud 容器路由 + 元数据跨设备对账 + runRead 越界修复 + 17 新测试）
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

已完成（2026-08-22 P0.1.5 轮，`70a40a2`）：① 工作区运行时接线（P0.1.2/1.3 真缺口：WorkspaceRootProvider 存在但 App 层零消费）— WorkspaceRouter（current 根 / 五目录契约 / sessionCwd / refresh 根变化检测 / materialize）+ SharedRAGEngine indexURL 注入与 resetIndexURL（根变化重建索引）+ PluginMetadataStore（v1 清单原子写）+ AppViewModel 全接线（会话 cwd 路由 / 根变化 RAG reset + memoryEngine 重挂 + 文件主题重建 + reconcile 对账（isICloud 守卫）/ persistPluginMetadata）② P0.4.3 文件型主题包导入（spec.json 文件|目录、颜色校验、sanitizeID、themes/ 持久化 + 安装为 ThemeProviderPlugin + 停用删除 + MCP 待重导横幅 + fileImporter 入口 + PluginDetailComponents 拆出）③ runRead 越界崩溃修复（身份锁定，3/3 绿）+ 并发门禁两处 flaky 点（旧下标错槽 / skills state-数据竞态）④ 17 新单测（App 15 fakes 全套 + RAG 2）⑤ PR 门禁 638/638（131 suites）0 警告 0 停滞 ⑥ 工具枚举稳定序修复（schemas() 字典序漂移 → 分类序+名称，P2 闭环，639/639 + pr 连跑 3 轮稳定）。**P0 代码更完整闭环**（iCloud 存储分工 / 插件元数据跨设备同步 / 社区主题包兼容全部接线）。
已完成（2026-08-22 P0.1.5 消费端轮，本轮提交）：⑦ 会话工作区「消费端」接线闭环（P0 验收前审计发现的真缺口——cwd 只存不消费）：ToolRunContext.workingDirectory + resolveToolPath（相对路径先解析进会话工作区再沙箱校验，防绕过）+ Read/Write/ListFiles 相对路径解析 + exec 继承会话工作目录 + AgentLoop workingDirectoryProvider（@Sendable 会话级解析）+ AppViewModel obtainChatLoop provider 下发 + UI executeTool context 下发（双端一致）；5 新测试（相对路径三工具解析 / 越界相对路径沙箱拒绝 / exec pwd==工作区 / provider 下发 / App 全链路 e2e：消息→write_file 相对路径→文件落 agents/<sessionID>）；PR 门禁 642/642 + XCTest 0 失败。**P0 验收前高风险项审计全过**（拖拽悬停高亮 / 对话内工具回显 / iCloud 权限降级+重新申请 / 主题卸载回落 / 跨模块 e2e 主链 / 多 Agent 创建+销毁；持有循环 router→accountService 单向 + sink 全 weak）。同轮闭环 2 处测试基建缺陷：UserDefaults sandboxRoot 跨 suite 磁盘持久化泄漏（fixture 隔离 + synchronize）+ exec 输出断言格式漂移。

已完成（2026-08-21 P0.3 轮，`2ada315`）：① 6 导航项真实对接审计（零假 UI）② NavLoadState 三态状态层 + 四路 retry 重跑链路 ③ SkillStore.loadThrowing（目录被文件占用显式抛错）④ 三 UI 组件 + 四视图接线（空态闪烁防护/失败横幅/部分失败警告）⑤ 零警告基线修复（两处死 catch 消除）⑥ 3 场景单测 + 766/766 门禁（pr+main 全绿 0 停滞）⑦ 实机正常态验证（会话真实数据/插件 2/2 运行/窗口零幻影）。

已完成（2026-08-21 P0 验收轮，`eb48909`）：看门狗重建窗口 frame 缩小缺陷两层修复（幻影 visibleFrame + setFrame 内部约束裁剪），实机两次重建保持 1920×1050、日志不再出现 1686，3 项新单测 + PR 门禁 621/621 全绿。**P0 代码至此全部闭环**，当前处于用户实机验收阶段。

已完成（2026-08-21 P0.2 轮）：① Workspace 包 5 文件 282 行（Project 实体 / 删除二选一 / SessionTransfer / reorder / SessionDragPayload / SidebarModel 投影 / WorkspaceSyncPayload）+ 27 单测 ② SessionDB v2 纯增量迁移（向后兼容解码 + save 全量重写 events 的 patch 先 load 后 save 约束）③ Account WorkspaceSyncEngine 同步桥 + 8 单测 ④ App 项目模块 UI（分区/折叠/归档管理面板/搜索限定范围/会话拖拽迁移，11 场景 + 2 投影单测）⑤ 看门狗选屏反馈回路修复（双屏窗口碎片化根因，实机 20s+ 零 mismatch 验证）⑥ xcode 工程静态库依赖三处修复 + scheme 重复条目清理 ⑦ 763/763 门禁基线（ci-local pr+xcode+main 三门禁全绿）⑧ 实机演示验证（新构建启动 + 侧边栏项目分区实机可见，截图 /tmp/dsh/p02_harness_win.png）。

下一步：**P0 实机验收 → P1 Liquid Glass**。P0 功能开发已全部闭环（P0.1 SSO/iCloud 基础层 + 冲突裁决 UI / P0.2 项目模块 / P0.3 导航真实对接 / P0.4 MCP 六项 / P0.5 composer 三项 / P0.1.5 工作区运行时接线 / P0.4.3 主题包导入）。待办：① 用户在场实机验收（主题切换/冲突裁决卡/依赖缺失 UI/composer 插件工具菜单/项目拖拽/**P0.1.5：主题包导入（spec.json→主题启用→停用删除）+ iCloud 模式 MCP 待重导横幅 + 新会话 cwd 路由**，演示数据可右键清理）② Apple Developer Team/描述文件到位后 SSO+iCloud 真机验收（当前无 entitlements 优雅降级）③ 验收通过后按 goal 进入 P1：全局 glassEffect 玻璃化（GlassEffectContainer 同区域采样一致）+ Tab Morph 流动玻璃（@Namespace + glassEffectID）+ 主题插件玻璃参数（ThemeSpec.glassTint/blur/highlight 已预留）打通。

> P0.3 遗留观察（不阻塞 P0.4）：三态 UI 的**失败态实机视觉验收**待用户在场时演示（状态层 3 场景单测已锁定；正常态实机已通过）。

1. 用户依赖（不阻塞）：① Apple Developer Team/描述文件（SSO + iCloud 真机验收；当前按「无 entitlements 优雅降级」设计，UI 显示「需配置 entitlement/描述文件」+ 重新申请入口）② 「账号与同步」设置子页 + P0.2 项目模块实机视觉验收（演示数据已注入真实 DB，可右键删除项目清理）③ GitHub Actions 远端仍暂缓（ci-local 四模式本地模拟；KVS 冲突裁决 UI 已随 P0.1.4 闭环，原待办项核销）
2. 持续观察：P1 macOS 27 beta 协作池调度停滞（每轮全量回归观察，CI 有界重试兜底；macOS 正式版若复现再升级）+ P2 macOS 27 beta 窗口服务器幻影 CGWindowList 报告（缓解已上线 `4beb21d`，实机渲染不受影响；macOS 官方正式版修复后复核并移除缓解逻辑）
3. 持续迭代候选（均不阻塞）：① ~~in-flight LLM 调用 cancel 联动中断~~（**本轮已闭环**：turn Task 化 + 联动取消，645/645）② KVS 冲突裁决 UI（含 workspace 冲突）③ 项目拖拽排序 UI 暴露 ④ 覆盖率工具链口径统一（官方工具链修复 profdata -f bug 后恢复）
