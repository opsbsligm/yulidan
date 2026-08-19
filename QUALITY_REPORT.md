# Swift Harness — 质量保障报告

> 生成时间: 2026-08-19 16:30
> 项目版本: v0.3.1（后端 8 模块闭环 + 前端阶段 1/2/3a/3b/3c 完成，HEAD `99ba131`）
> 说明: 前端打磨阶段基线刷新；测试数、覆盖率、门禁结果均为当前 HEAD 实测。

---

## 一、质量门禁（当前 HEAD 实测）

| 门禁 | 状态 | 详情 |
|------|------|------|
| SwiftFormat | ✅ 0 改动 | `swiftformat --lint . --config .swiftformat`（157 文件） |
| SwiftLint | ✅ 0 违规 | `swiftlint lint --strict --config .swiftlint.yml` |
| 编译 | ✅ 0 警告 | 全量冷编译（450 targets 含测试目标，覆盖率构建实测） |
| 单元测试 | ✅ 628/628 | XCTest 180 + Swift Testing 448（85 suites），0 失败 |
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

## 三、测试用例与行覆盖率（2026-08-19 全量实测，llvm-cov 当前工具链口径）

| 模块 | 行覆盖（仅源文件，628 用例 run 实测） | 状态 |
|------|--------|------|
| Sandbox | 98.4%（63/64） | ✅ ≥90% |
| Subagent | 97.5%（352/361） | ✅ ≥90% |
| Skill | 96.7%（670/693） | ✅ ≥90% |
| Tools | 95.7%（572/598） | ✅ ≥90% |
| PluginXPC | 94.6%（297/314） | ✅ ≥90% |
| RAG | 94.5%（659/697） | ✅ ≥90% |
| Prompt | 94.5%（363/384） | ✅ ≥90% |
| Terminal | 93.2%（206/221） | ✅ ≥90% |
| LLM | 92.8%（1243/1339） | ✅ ≥90%；wire 格式零网络桩（tools/tool_calls/reasoning/SSE 聚合/归一化边界） |
| MCP | 92.3%（728/789） | ✅ ≥90% |
| WebUI | 92.1%（608/660） | ✅ ≥90% |
| Session | 92.0%（412/448） | ✅ ≥90% |
| Memory | 91.7%（521/568） | ✅ ≥90% |
| ServiceContainer | 91.4%（687/752） | ✅ ≥90% |
| Agent | 91.1%（494/542） | ✅ ≥90%（本阶段 toolTraces 补测 6 项） |
| Notifications | 67.1%（49/73） | ⚠️ UNUserNotificationCenter 真实包装层测试进程不可达（系统限制） |
| HarnessApp（UI 层） | 10.9%（1216/11138） | 说明：SwiftUI 视图层，不计入 90% 核心基线（ViewModel 逻辑已由 HarnessAppTests 覆盖） |

**总计: 628 个测试用例（XCTest 180 + Swift Testing 448），全部通过。**
**15 个后端包行覆盖 93.2%（7924/8503）；14 个核心包（除 Notifications）93.4%（7875/8430）。**

> 口径说明：行覆盖统计各模块 `Sources/` 源文件（不含测试），llvm-cov 可执行插桩行口径（当前工具链；与上一版报告"全代码行"口径分母不同，百分比可比）。`swift test` 末尾 "Test run with N" 只统计 Swift Testing，XCTest 计数看 "Executed N tests"。

## 四、已知问题清单（按优先级）

### P0
无。

### P1
| 问题 | 现象/复现 | 状态 |
|------|-----------|------|
| XCTest 瞬态失败（根因已定位，修复验证中） | 单发全量偶发失败（本会话 14 轮抓到 1 轮 2 失败）。根因（高置信）：5 处测试「固定 sleep(100-150ms) 后断言异步回调已落盘」，事件循环抖动下回调未执行即断言；其中 MCP `testListChangedInvalidatesCache` 恰含 2 个此类断言，与『2 失败』特征吻合。已改 `eventually()` 条件轮询（`6ce51a0`）；修复后 6 轮全量 + 9 轮隔离全绿 | 观察中：下一观察周期零复现即闭环 |

### P2
| 问题 | 说明 | 状态 |
|------|------|------|
| `dsh web` 与"非 Web 服务"约束边界 | 需用户确认约束口径（WebUI 为本地 127.0.0.1 调试服务，非对外 Web 服务） | 待确认 |
| 冷 scratch 偶发 emit-module 工具链崩溃 | `no such module 'Agent'`，同 scratch 重试即过（环境坑非代码） | 已知 |

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

## 五、代码统计

| 项 | 数值 |
|----|------|
| 源码（Packages，77 文件） | 11,681 行 |
| 源码（Apps/HarnessApp，21 文件） | 6,128 行 |
| 源码合计（98 文件） | 17,809 行 |
| 测试代码（Packages 9,934 + Apps 1,004） | 10,938 行 |
| SPM 目标 | 16 库/可执行 + 17 测试目标（单一 xctest 进程） |
| 工具链 | Swift 6.3.3 / Xcode 26.6 / macOS arm64 / platforms .macOS(.v15) |
| 提交总数 | 75 |

## 六、提交链（近期）

```
6ce51a0  fix(test): P1 瞬态失败根因修复 — 固定 sleep + 异步回调断言改条件轮询
c386f55  docs(quality): 刷新质量报告 — 前端阶段3a/3b/3c 基线（628 全绿/llvm-cov 复测）
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
5f11dee  feat(app): 主聊天路径接 AgentLoop 工具循环（前端阶段2/P2 接线闭环）
```

## 七、下一阶段

已完成（本周期）：工具轨迹可折叠行端到端（`58a13d9`）、顶栏 Codex 式重排 + composer 限宽（`ead1742`）、冷编译警告清零（`851a100`）。

1. XCTest 瞬态失败：持续观察，复现即定位（P1）
2. `dsh web` 约束口径：待用户确认（P2）
3. UI 细节打磨（如需要）：Sidebar/Welcome 已确认 Codex 对齐；剩余为微调用
4. 收尾：全量门禁 + 阶段进度报告
