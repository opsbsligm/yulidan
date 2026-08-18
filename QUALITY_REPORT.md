# Swift Harness — 质量保障报告

> 生成时间: 2026-08-18 12:40
> 项目版本: v0.1.0（开发中，HEAD `ab1e41c`）
> 说明: 本版为 2026-08-14 v0.1.0-rc.2 报告的第二次基线更新（技能系统落地后）；测试数、覆盖率、门禁结果均为当前 HEAD 实测，未沿用旧数据。

---

## 一、质量门禁（当前 HEAD 实测）

| 门禁 | 状态 | 详情 |
|------|------|------|
| SwiftFormat | ✅ 0 改动 | `swiftformat . --config .swiftformat` |
| SwiftLint | ✅ 0 违规 | `swiftlint lint --strict`（warning 按 error 计） |
| 编译 | ✅ 通过 | `swift build`（Swift 6.3 / strict concurrency） |
| 单元测试 | ✅ 305/305 | XCTest 90 + Swift Testing 215（48 suites），0 失败 |
| 本地镜像备份 | ✅ 每次提交后 | `git push --mirror /Users/liguangming/code/swift-harness-backup.git` |
| GitHub 推送 | ⏸ 暂缓 | 按用户要求先本地版本控制，未推送远端 |

## 二、测试用例与行覆盖率（2026-08-18 实测，llvm-cov）

| 模块 | 测试用例 | 行覆盖 | 状态 |
|------|---------|--------|------|
| ServiceContainer | 101 | 94.2%（1658/1760） | ✅ ≥90% |
| Agent | 35 | 93.8%（709/756） | ✅ ≥90% |
| Skill | 15 | 96.4%（380/394） | ✅ ≥90% |
| Subagent | 18 | 95.3%（727/763） | ✅ ≥90% |
| Terminal | 10 | 94.9%（300/316） | ✅ ≥90% |
| PluginXPC | 8 | 94.3%（466/494） | ✅ ≥90% |
| Sandbox | 10 | 94.0%（156/166） | ✅ ≥90% |
| Session | 24 | 93.0%（690/742） | ✅ ≥90% |
| Tools | 20 | 91.2%（475/521） | ✅ ≥90% |
| HarnessApp（App 层） | 15 | 9.1%（979/10776） | ⚠️ SwiftUI 视图层无单测；AppViewModel/ViewModel 逻辑已部分覆盖 |
| MCP | 13 | 87.5%（649/742） | ⚠️ stdio 客户端少量分支未覆盖 |
| Notifications | 5 | 73.4%（91/124） | ⚠️ 授权/重试分支未覆盖 |
| LLM | 25 | 82.5%（1035/1254） | ⚠️ HTTP 层已有 17 个零网络桩测试；余 SSE 边界/流式错误分支 |
| HarnessCore | 0 | 66.7%（32/48） | ⚠️ 待补测试 |

**总计: 305 个测试用例（XCTest 90 + Swift Testing 215），全部通过。**

> 核心包（ServiceContainer / Agent / Session / Tools / Subagent / Skill / Terminal / Sandbox / PluginXPC）行覆盖全部 ≥90%，满足验收标准。

## 三、rc.2 之后新增能力（41 个提交）

### 模型与工具
- LLM 真实适配器：OpenAI / DeepSeek / Anthropic / 本地 Ollama·vLLM（OpenAI 兼容协议）
- MCP：协议类型 + 真实 JSON-RPC 2.0 stdio 客户端 + App 演示服务器（system_info / current_time）
- Terminal 包：TerminalRunner 真实执行，ExecCommandTool 委托
- PathSandbox 路径沙箱：文件工具越界拒绝，设置页可配置

### 多 Agent 协作链（本轮主线）
- `SubagentCoordinator`：并发槽位 / 超时 / 取消 / 事件回调 / whenIdle 真实等待
- App「多Agent」页：派生 / 取消 / 清理 / 阶段徽章 / 耗时 / 结果文本
- 执行过程可视化：AgentResult.steps 工具调用步骤时间线
- 子任务历史持久化：重启不丢（上限 50 条）
- 子任务终态系统通知（完成/失败/超时）
- 对话页「派生」按钮：当前输入 → 子任务
- CLI：`dsh agents run <任务...> --parallel --timeout`（与 App 同一协调器）
- **spawn_subagent 工具**：主 Agent 对话中自主委派子任务；子 Agent 用独立工具注册表（不含本工具），防递归死锁

### 技能系统（Skill）
- Skill 包：Skill 模型 + SKILL.md frontmatter 解析（~/.harness/skills）+ SkillRegistry actor（注册/检索/提示词列表）
- Agent 工具：list_skills（列技能）/ use_skill（按名加载指令，未找到返回 skill_not_found）
- 内置技能 ×3：git-commit / code-review / ops-troubleshoot
- App「技能」页：列表（内置/用户徽章）/ 新建 / 编辑（名称锁定）/ 删除 / 展开正文
- CLI：dsh skills list / show / export / import
- App 技能页导入（NSOpenPanel）/ 导出（NSSavePanel），与 CLI 文件格式互通

### App / 插件
- macOS 系统通知（生成完成/失败，设置可开关）
- 插件市场层 PluginMarketplace + 14 测试 + App 双视图（已安装/市场，真实安装/更新/卸载）
- XPC 进程隔离：PluginXPC + worker 可执行 + 真实 E2E 测试 + App 隔离开关（启动恢复 + 徽章）
- 性能：启动会话加载消除 N+1 与全量事件解码，实测 212×（docs/PERFORMANCE.md）
- Codex 风格 UI 重构 + 远程窗口看门狗 + 碎片化窗口重建兜底

### 工程
- LLM HTTP 层桩测试 17 用例（URLProtocol 注入 session，零网络）；修复 Anthropic system 提示词重复发送 bug + stream 回退路径 JSON 崩溃
- DSH CLI：provider 解析 + 真实对话
- `tools/rebuild-app.sh` 一键重建 .app 壳
- HarnessAppTests 测试目标（App 层单测）

## 四、CI/CD

| 流水线 | 状态 | 详情 |
|--------|------|------|
| PR Check（GitHub Actions） | ✅ 配置 | lint + 编译 + 单测 |
| Main Check（GitHub Actions） | ✅ 配置 | 全量测试 + 覆盖率 + CodeQL |
| 本地门禁（每轮提交前） | ✅ 执行 | format + lint --strict + build + test 四连 |
| 本地镜像备份 | ✅ 执行 | 每次提交后 `git push --mirror` 到本地裸库 |
| GitHub 远端 | ⏸ 暂缓 | 用户要求先本地版本控制 |

## 五、架构合规

| 约束 | 状态 | 证据 |
|------|------|------|
| 纯 macOS 原生 | ✅ | 无 WebView/WKWebView 依赖 |
| 无 JavaScript | ✅ | 零 JS/TS/Node 依赖 |
| Swift 6 并发 | ✅ | strict concurrency 编译通过 |
| Protocol 驱动 | ✅ | 所有接口为 Protocol |
| 模块化 | ✅ | SPM 14 个包 + App + CLI |
| 最低 macOS 15 | ✅ | Package.swift 声明 |

## 六、改进建议（按优先级）

1. **HarnessApp 视图层**：XCUITest 或快照测试（当前 9.1%；AppViewModel 已部分覆盖）——现为最大短板
2. ~~**LLM 适配器 HTTP 层**~~：✅ 已解决（2026-08-18）17 个 URLProtocol 零网络桩测试，35.5% → 82.5%
3. **HarnessCore 66.7%**：32/48，小模块待补测试
4. **Notifications 73.4%**：补授权拒绝/重试分支
5. **MCP 87.5%**：补 stdio 客户端异常分支
6. **Spotlight / Shortcuts**：需正式 bundle 签名注册，debug 壳不适用，暂缓
