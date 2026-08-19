# Swift Harness — 质量保障报告

> 生成时间: 2026-08-20 04:55
> 项目版本: v0.3.4（后端 8 模块闭环 + 跨模块场景 4 项 + App 层场景 16 项 + 前端阶段 1/2/3a/3b/3c/3d/3e 完成，HEAD `171c881`）
> 说明: 本轮完成 F7 Codex 布局对齐差距盘点与首批落地（`docs/UI_CODEX_ALIGNMENT.md`）：**P1 修复** 生成中切换/新建/删除会话污染消息流（三入口拦截 + 写回一致性防御）+ 列表生成指示 + 行尾相对时间 + ⌘N/⌘,/⌘1–⌘6 快捷键 + 删除 SessionSidebarView 死代码；新增 5 项测试（660 用例基线）；覆盖率 llvm-cov export lcov 口径重测；门禁结果均为当前 HEAD 实测。

---

## 一、质量门禁（当前 HEAD 实测）

| 门禁 | 状态 | 详情 |
|------|------|------|
| SwiftFormat | ✅ 0 改动 | `swiftformat --lint . --config .swiftformat`（164 文件） |
| SwiftLint | ✅ 0 违规 | `swiftlint lint --strict --config .swiftlint.yml` |
| 编译 | ✅ 0 警告 | 全量冷编译（450 targets 含测试目标，覆盖率构建实测） |
| 单元测试 | ✅ 660/660 | XCTest 180 + Swift Testing 480（94 suites），0 失败（含 4 项跨模块场景 + 16 项 App 层场景端到端 + 4 项 GlassSurface + 2 项生成守卫 + 3 项 RelativeTime） |
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
| F7 | Codex 布局对齐差距盘点（`docs/UI_CODEX_ALIGNMENT.md`）+ 首批落地：生成中会话守卫（三入口拦截 + 一致性防御，P1）/ 列表生成指示 / 相对时间 / ⌘N/⌘,/⌘1–⌘6 / 死代码删除 | `171c881` | ✅ 闭环（B5 折叠 / B6 置顶 / B8 气泡微调登记待办） |

## 三、测试用例与行覆盖率（2026-08-20 04:45 全量重测，llvm-cov export lcov 口径）

| 模块 | 行覆盖（仅源文件，660 用例 run 实测） | 状态 |
|------|--------|------|
| Sandbox | 98.2%（54/55） | ✅ ≥90% |
| Skill | 98.3%（626/637） | ✅ ≥90%（较上版 +2 行，run-to-run 变异回升：技能进化时序路径，测试全绿非代码回归） |
| Prompt | 96.5%（329/341） | ✅ ≥90% |
| RAG | 96.4%（596/618） | ✅ ≥90% |
| Subagent | 96.3%（315/327） | ✅ ≥90%（含槽位门控转移语义修复代码 `50fb2be`） |
| Tools | 96.1%（489/509） | ✅ ≥90% |
| Memory | 93.5%（490/524） | ✅ ≥90% |
| Terminal | 91.7%（154/168） | ✅ ≥90%（较上版 -3 行，profraw union run-to-run 变异，测试全绿非代码回归） |
| LLM | 93.4%（937/1003） | ✅ ≥90%；wire 格式零网络桩（tools/tool_calls/reasoning/SSE 聚合/归一化边界） |
| MCP | 93.4%（606/649） | ✅ ≥90%（跨模块场景测试补测工具自动注册链路） |
| PluginXPC | 92.9%（197/212） | ✅ ≥90% |
| Agent | 92.5%（418/452） | ✅ ≥90%（本阶段 toolTraces 补测 6 项） |
| WebUI | 92.1%（499/542） | ✅ ≥90% |
| Session | 92.0%（287/312） | ✅ ≥90% |
| ServiceContainer | 91.8%（642/699） | ✅ ≥90% |
| Notifications | 82.7%（62/75） | ⚠️ 结构性上限：剩余 13 行为 `SystemNotificationCenter` UN 真实包装层（裸 xctest 进程调用实测 abort；授权状态映射已拆纯函数 `state(from:)` 全测） |
| HarnessApp（UI 层） | 25.8%（1277/4944） | 说明：SwiftUI 视图层，不计入 90% 核心基线（ViewModel 逻辑已由 HarnessAppTests 覆盖）。较上版 24.3%（1225/5037）：分母 -93 行（删除 SessionSidebarView 死代码）、命中 +52 行（守卫/相对时间路径，同口径：llvm-cov lcov 插桩行） |

**总计: 660 个测试用例（XCTest 180 + Swift Testing 480），全部通过。**
**16 个后端包（含 WebUI）行覆盖 94.1%（6701/7123）；不含 WebUI 15 包 94.2%（6202/6581）；14 个核心包（除 Notifications）均 ≥90%。**（口径：上版「15 包 6701/7123」实为含 WebUI，本版起拆分标注）

> 口径说明：行覆盖统计各模块 `Sources/` 源文件（不含测试），本版改用 `llvm-cov export --format=lcov` 按 DA 记录去重行统计（该 beta 工具链 `llvm-cov report/export --format=json` 不可用）；分母与上一版（llvm-cov report 口径）不同，**绝对值不可直接纵向比较，模块相对排序与 ≥90% 达标状态一致**。`swift test` 末尾 "Test run with N" 只统计 Swift Testing，XCTest 计数看 "Executed N tests"。

## 四、已知问题清单（按优先级）

### P0
无。

### P1
| 问题 | 现象/复现 | 状态 |
|------|-----------|------|
| macOS 27 beta 瞬态协作池调度停滞（`--parallel` 全量偶发失败） | 现象：`swift test --parallel`（或直接调 xctest）下 `CoordinatorLifecycleTests/testShutdownCancelsAllAndClears` 约 1/8~1/10 概率失败（blocker 10s 未 running → cancelCount=0）。**根因（现场 sample 实锤）**：新 xctest 进程偶发「协作池任务 ~10-13s 不派发，而池线程全部空闲」（证据：主线程阻塞于 XCTest async 桥接 mach_msg 等待、全部池/wq 线程 `__workq_kernreturn` 空闲、无任何线程执行排队的 Swift 任务；样本 /tmp/stall_sample_19.txt）。**环境故障，非协调器逻辑缺陷**：停滞解除后 run 任务立即执行且行为完全符合规范（排队取消不执行/运行取消/无僵尸残留）。排除链：最小 actor+Task 复现包 15/15 绿（非通用 actor 问题）；直接 xctest 调用 1/10 复现（与 SPM --parallel 无关）；串行 swift test 健康窗口 8/8 绿；AC 电源（非电池节流） | 修复双层：①测试层 — 前置等待 10s→30s、4 个 `eventually` helper 默认窗口 3s→5s（正常路径毫秒级返回，仅停滞时拉长）②CI 层 — pr/xcode/main/weekly 全量测试步骤加**有界单次重试**（停滞属环境故障，真实回归重试仍会失败）。**残留风险**：停滞超 30s，或其余固定 sleep 断言点（MCP 300-500ms / Agent 10-100ms / ServiceContainer 150ms 等）撞上停滞窗口仍可能偶发失败，由 CI 重试兜底；若 macOS 正式版仍复现再升级处理 | **修复已验证（观察期）**：Subagent 模块 15/15（其中 9 轮处于停滞窗口、11-12s 慢通过，测试内重试在真实窗口下全部存活）+ 全量 `--parallel` ×2（628）+ 串行 ×1（628）+ ci-local main ×2 + ci-local pr 全绿（`50fb2be` 提交前实测）。观察期：若 macOS 正式版仍复现再升级处理 |

### P2
| 问题 | 说明 | 状态 |
|------|------|------|
| `dsh web` 与"非 Web 服务"约束边界 | 需用户确认约束口径（WebUI 为本地 127.0.0.1 调试服务，非对外 Web 服务） | 待确认 |
| stopGenerating 不中断在途 LLM 调用（设计权衡） | 现象：`AgentLoop.cancel` 仅标记 cancelFlag + 唤醒 whenIdle 等待者，在途 `llm.request` 在后台自行完成（代码注释明示「在途 LLM 调用在后台自行完成，不再阻塞协调器」，F5 决策）。本地模型无副作用；远程模型会浪费一次请求配额。**已验证不变量**（`56efd78` 场景测试锁定）：延迟响应到达后不追加进会话消息流、无错误消息残留 | 已知设计（观察项）：若后续远程多模型成本敏感，可升级为「cancel 联动中断在途请求」（需 AgentLoop 持有在途 Task 引用，属架构扩展，本轮不做） |
| 冷 scratch 偶发 emit-module 工具链崩溃 | `no such module 'Agent'`，同 scratch 重试即过（环境坑非代码） | 已知 |
| Apple LLVM 21（Xcode 26.6 / macOS 27 beta）`llvm-profdata merge -f` 参数 bug | `-f` 存在时（任意参数序）报 `error: <out>: No such file or directory` 且 rc=1；输出路径可写、输入 profraw 可读（`show` 正常）→ 工具自身 bug。三组实验实锤：`-f -o out files` 失败 / `files -f -o out` 失败 / `files -o out` 成功（覆盖已存在输出文件亦可）。曾致 `tools/ci-local.sh main` 覆盖率汇总步骤失败（测试门禁本身通过） | 已绕过（`50fb2be`）：merge 行改 `merge *.profraw -o out`（省略 -f、-o 置输入文件后），182 个 profraw 全量验证 + ci-local main 复跑全绿；官方工具链修复后可恢复 -f |

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

## 五、代码统计

| 项 | 数值 |
|----|------|
| 源码（Packages，77 文件） | 11,723 行 |
| 源码（Apps/HarnessApp，21 文件） | 6,182 行（F7 净 +47：守卫/相对时间/快捷键 +129 − 删 SessionSidebarView 217 + 格式整理） |
| 源码（Apps 辅助 target：DSHCLI/HarnessCore/HarnessPluginWorker/MemProbe，10 文件） | 1,250 行 |
| 源码合计（108 文件） | 19,155 行 |
| 测试代码（Packages 10,094 + Apps 2,664） | 12,758 行（+165：SessionGuardTests 5 场景） |
| SPM 目标 | 16 库/可执行 + 17 测试目标（单一 xctest 进程） |
| 工具链 | Swift 6.3.3 / Xcode 26.6 / macOS arm64 / platforms .macOS(.v15) |
| 提交总数 | 98（含本报告提交） |

## 六、提交链（近期）

```
171c881  feat(ui): F7 Codex 布局对齐 — 生成中会话守卫 + 列表生成指示/相对时间 + ⌘ 快捷键 + 死代码删除
a0cb8ab  feat(ui): WWDC26 Liquid Glass 表面系统（原生 glassEffect + 三级降级链 + 4 项单测）+ 核心表面应用
19c7fb2  test(app): 会话操作 4 场景（clearChat/重试/子任务入口/插件启停）+ 技能目录全局覆盖竞态根除
56efd78  test(app): stopGenerating 在途取消 + 通知开关 2 场景（延迟响应不污染会话不变量）
2192233  test(app): 会话生命周期 5 场景 + 工具面板 5 场景端到端测试（providerFactory 实例缝隔离跨 suite 竞态）
bc8f3fc  test(scenario): 跨轮工具上下文保留 + 记忆注入系统提示词 + 技能复用回环（场景测试 4 项闭环）
dfe393e  test(scenario): 跨模块业务场景端到端测试（8 模块集成链路自测）
c34ee2f  docs(quality): P1 调度停滞修复验证闭环 + P2 profdata -f bug 入册 + 覆盖率 lcov 口径重测（50fb2be）
50fb2be  fix(subagent): 槽位门控转移语义修复并发上限竞态 + 停滞窗口测试加固 + CI 有界重试 + profdata 参数序绕过
c969827  docs(quality): Xcode 工程依赖漂移修复入册（99ba131）
99ba131  fix(xcode): 修复 Xcode 工程依赖缺失（xcodebuild job 首次本地跑通）+ lint 排除 ci-derived-data
7e91c5d  ci(local): 本地 CI 模拟脚本（对齐 GitHub Actions 四 job：pr/leaks/xcode/main）
4ebd8c6  docs(quality): P1 瞬态失败根因定位与修复入册（6ce51a0 观察期）
6ce51a0  fix(test): P1 瞬态失败根因修复 — 固定 sleep + 异步回调断言改条件轮询
851a100  fix(test): 冷编译警告清零（RAGEngineTests docs1 未使用变量）
ead1742  feat(app): 顶栏 Codex 式重排 + composer 居中限宽（前端阶段3c）
58a13d9  feat(agent): 工具轨迹 Codex 式可折叠行（toolTraces 端到端 + UI + 回归测试）
84c7b6f  fix(agent): whenIdle 取消感知（P2 闭环：WebUI 超时后孤儿任务不再悬挂到 turn 结束）
fbe5600  feat(agent): 会话级 AgentLoop 持久化（跨轮工具上下文保留 + LRU 内存回收）
c5bdc41  fix(quality): P1+P2 后端四项闭环（PluginWorker 进程泄漏 / RAG 去重 / SSE reasoning 流式 / local 画像按模型细分）
2886435  feat(app): AgentLoop onProgress 实时工具进度 + Codex 式贴底滚动（前端阶段3b）
7b3dc8c  feat(app): Codex 式工具轨迹行 + 顶栏会话标题（前端阶段3a）
c8e3cc4  fix(test): 根除跨 suite 全局覆盖竞态（瞬态测试失败根因）
cf0e230  docs(quality): 刷新质量报告 — 前端阶段1/2 基线
```

## 七、下一阶段

已完成（本轮）：F7 Codex 布局对齐差距盘点（`docs/UI_CODEX_ALIGNMENT.md`）+ 首批落地（`171c881`：B1 P1 生成中会话守卫 / B2 生成指示 / B3 相对时间 / B4 ⌘ 快捷键 / B7 死代码删除，660 用例基线）。

1. 下一步（F8 候选，按价值排序）：① B5 侧边栏折叠/展开（折叠态持久化 + 主区宽度释放）② B6 置顶会话（pinned 段 + SessionMetadata 扩展）③ B8 用户消息气泡 → 无气泡纯文本（随视觉验收一并对齐）
2. 视觉验收：GlassSurface（CardModifier 全局升级）+ F7 列表行/快捷键 需用户实机确认（无头环境结构性限制）
3. P1 观察期：后续每轮全量回归持续观察（CI 有界重试兜底）；macOS 正式版若仍复现再升级处理
4. 持续迭代候选（按价值排序）：① exportChat/exportSkill/attachFiles 模态 UI 人工验收（无头 xctest 结构性不可测，已判定）② Terminal/WebUI 覆盖观察 ③ 覆盖率工具链口径统一（官方工具链修复 -f bug 后恢复）④ in-flight LLM 调用 cancel 联动中断（P2 观察项，需 AgentLoop 架构扩展）
5. `dsh web` 约束口径：待用户确认（P2）
6. 部署目标口径：目标模式要求「最低支持 macOS 25」，当前 deployment target 为 macOS 15（超集兼容，满足要求）；是否将部署目标上提至 25 待用户确认
