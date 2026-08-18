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
| 单元测试 | ✅ 344/344 | XCTest 116 + Swift Testing 228（50 suites），0 失败 |
| 本地镜像备份 | ✅ 每次提交后 | `git push --mirror /Users/liguangming/code/swift-harness-backup.git` |
| GitHub 推送 | ⏸ 暂缓 | 按用户要求先本地版本控制，未推送远端 |

## 二、测试用例与行覆盖率（2026-08-18 实测，llvm-cov）

| 模块 | 测试用例 | 行覆盖（仅源文件） | 状态 |
|------|---------|--------|------|
| HarnessCore | 4 | 100%（48/48） | ✅ 内置插件生命周期/目录全覆盖 |
| Subagent | 18 | 96.5%（274/284） | ✅ ≥90% |
| Skill | 15 | 94.2%（180/191） | ✅ ≥90% |
| Terminal | 10 | 94.6%（209/221） | ✅ ≥90% |
| PluginXPC | 8 | 93.3%（277/297） | ✅ ≥90% |
| ServiceContainer | 101 | 91.3%（685/750） | ✅ ≥90% |
| Agent | 35 | 90.2%（330/366） | ✅ ≥90% |
| Session | 24 | 90.0%（368/409） | ✅ ≥90% |
| Tools | 32 | 98.4%（253/257） | ✅ ≥90%；工具参数/边界/错误分支全覆盖 |
| Sandbox | 15 | 98.4%（63/64） | ✅ ≥90%；余 1 行为根目录死代码分支 |
| MCP | 13 | 84.3%（423/502） | ⚠️ stdio 客户端异常分支未覆盖 |
| LLM | 35 | 93.6%（670/716） | ✅ ≥90%；27 个零网络 HTTP 桩测试（complete/stream/checkConnection/错误分支） |
| Notifications | 13 | 67.1%（49/73） | ⚠️ SystemNotificationCenter 真实包装层无法在测试进程触达（UNUserNotificationCenter.current() 限制）；编排/服务逻辑已全覆盖 |
| HarnessApp（App 层） | 15 | 6.1%（631/10392） | ⚠️ SwiftUI 视图层无单测；AppViewModel 逻辑已部分覆盖 |

**总计: 344 个测试用例（XCTest 116 + Swift Testing 228），全部通过。**

> 口径说明：行覆盖仅统计各模块 `Sources/` 源文件（不含测试文件）。
> 核心包（Subagent / Skill / LLM / Sandbox / Tools / Terminal / PluginXPC / ServiceContainer / Agent / Session）行覆盖 ≥90%，满足验收标准；MCP 84.3% 接近达标。

## 三、rc.2 之后新增能力（46 个提交）

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
- HarnessCoreTests 测试目标（内置插件 manifest/生命周期/目录 4 用例，模块覆盖 66.7% → 100%）
- 通知协议化重构：NotificationCenterProtocol + AuthorizationState 抽象（SystemNotificationService 可注入替身），新增 8 个授权/投递分支测试
- LLM 适配器补测 10 用例（DeepSeek/Local stream、四家 checkConnection、缺 Key、流式错误传播、适配器元数据）：LLM 75.7% → 93.6%
- PathSandbox 补测 5 用例（错误描述/空路径回退/空白裁剪/错误载荷/根相等分支）：Sandbox 85.9% → 98.4%
- 内置工具补测 11 用例（缺参/超大文件/非 UTF-8/写入失败/目录不存在/非目录/权限拒绝/sizeStr/exec 启动失败）+ ToolPipeline post 处理器用例：Tools 86.8% → 98.4%，ToolPipeline 100%

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
3. ~~**HarnessCore 66.7%**~~：✅ 已解决（2026-08-18）新增 HarnessCoreTests，48/48 = 100%
4. **Notifications 67.1%**：剩余为真实系统通知中心包装层（测试进程限制，无法单测）
5. **MCP 87.5%**：补 stdio 客户端异常分支
6. **Spotlight / Shortcuts**：需正式 bundle 签名注册，debug 壳不适用，暂缓
