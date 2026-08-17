# Swift Harness — 开发计划

> 生成时间: 2026-08-14
> 项目位置: /Users/liguangming/code/swift-harness

---

## 一、项目定位

用 Swift 原生复刻 DeepSeek Harness 开源 Agent 框架，打造 macOS 桌面端原生 AI Agent 应用。

**核心哲学：一切皆插件** — 模型、工具、技能、会话、沙箱、存储、循环、调度、UI 全部可插拔替换。

---

## 二、架构设计

### 2.1 分层架构 + 依赖方向

```
┌─────────────────────────────────────────────────────────────┐
│  macOS App Layer (SwiftUI + Liquid Glass Design System)    │
├─────────────────────────────────────────────────────────────┤
│  Presentation Layer (ViewModels / Coordinators)             │
├─────────────────────────────────────────────────────────────┤
│  Domain Layer (Agent Core / Protocols)                      │
│  ├── ServiceContainer (Plugin Framework)                    │
│  ├── Agent Loop (Turn/Step/Inbox/Session)                   │
│  ├── Tool Pipeline (Waterfall Middleware)                   │
│  ├── LLM Adapters (AsyncSequence Stream)                   │
│  └── MCP Protocol (JSON-RPC 2.0)                           │
├─────────────────────────────────────────────────────────────┤
│  Infrastructure Layer (Network / Storage / Security)        │
│  ├── GRDB.swift (Persistence)                               │
│  ├── URLSession / AsyncHTTPClient (Network)                 │
│  ├── Keychain (Credentials)                                 │
│  ├── OSLog (Structured Logging)                             │
│  └── XPC (Plugin Isolation — Phase 3+)                      │
├─────────────────────────────────────────────────────────────┤
│  Plugin Modules (Independent SPM Packages)                  │
│  └── Phase 1: 进程内 Actor → Phase 3+: XPC 进程隔离        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 依赖方向约束

| 规则 | 说明 | 自动化 |
|------|------|--------|
| Domain 不依赖 UI | Domain 层禁止引用 SwiftUI/AppKit | ✅ CI 编译时检查 |
| 层间只通过 Protocol | 禁止直接依赖具体实现 | ✅ 代码审查 |
| 插件独立编译 | 每个插件是独立 SPM Package | ✅ SPM 天然支持 |
| 插件进程隔离 | Phase 3+ 通过 XPC Service 运行 | ✅ 渐进式升级 |

---

## 三、插件架构

### 3.1 渐进式隔离策略

| Phase | 隔离方式 | 优势 | 劣势 |
|-------|----------|------|------|
| **Phase 1-2** | 进程内 Actor 隔离 | 开发快、调试方便、零 IPC 开销 | 插件崩溃影响主进程 |
| **Phase 3+** | XPC 进程隔离 | 真正的崩溃隔离、权限沙箱 | IPC 开销、调试复杂 |

---

## 四、并发安全

### 4.1 Swift 6 完整并发安全

```swift
// 强制开启
// swift-settings: -strict-concurrency=complete

// ✅ Actor 隔离关键状态
actor Agent {
    private var status: AgentStatus = .idle
    private var inbox: Inbox
    
    func send(_ message: UserMessage) { /* ... */ }
}

// ✅ Sendable 协议
struct SessionEvent: Sendable { /* ... */ }

// ✅ @MainActor UI
@MainActor
class ChatViewModel: ObservableObject { /* ... */ }
```

### 4.2 防逻辑黑洞

| 风险 | 防护机制 | 代码模式 |
|------|----------|----------|
| **Actor 重入** | Re-verification Pattern | `await` 后重新验证状态 |
| **死锁** | 结构化并发 + 超时 | `withTimeout` wrapper |
| **内存泄漏** | `[weak self]` + Instruments | CI 集成 Leaks |
| **未释放资源** | `defer` + 结构化并发 | 自动清理 |
| **雪崩** | Circuit Breaker | 连续失败后熔断 |

---

## 五、质量保障

### 5.1 验收标准

| 检查项 | 标准 | 状态 |
|--------|------|------|
| 编译警告 | 0 个 | ✅ |
| SwiftLint | 0 错误 | ✅ |
| SwiftFormat | 格式化 | ✅ |
| ServiceContainer 覆盖率 | ≥90% | ✅ 91% |
| Agent 覆盖率 | ≥90% | ✅ 98% |
| Tools 覆盖率 | ≥90% | ✅ 94% |
| Session 覆盖率 | ≥90% | ✅ 96% |
| CI/CD | 双流水线 | ✅ |

---

## 六、与 DeepSeek Harness 对比

| 维度 | DeepSeek Harness | Swift Harness |
|------|-----------------|---------------|
| 语言 | TypeScript/Node.js | Swift 6 |
| 运行时 | Node.js + Electron | macOS 原生 |
| 并发模型 | async/await | Actor + Sendable |
| 插件隔离 | 进程内 | Phase 1: Actor, Phase 3+: XPC |
| 持久化 | SQLite | GRDB.swift |
| 测试框架 | Jest/Vitest | Swift Testing |
| 最低覆盖 | — | ≥90% (核心模块) |
| CI/CD | GitHub Actions | GitHub Actions |
| 包管理 | npm | SPM |

---

## 七、TODO

### Phase 1 (已完成)
- [x] 核心模块实现
- [x] 测试覆盖率 ≥90%
- [x] CI/CD 双流水线
- [x] SwiftUI 应用骨架
- [x] Liquid Glass 设计系统

### Phase 2 (已完成)
- [x] LLM 适配器实现 (OpenAI/DeepSeek)
- [x] 工具系统完善
- [x] MCP 协议实现
- [x] 沙箱集成
- [x] 终端集成

### Phase 3 (已完成)
- [x] XPC 进程隔离
- [x] 插件市场
- [x] 多 Agent 协作（包层 SubagentCoordinator + App「多Agent」页：派生/取消/超时/清理/完成通知/执行过程步骤时间线/历史持久化）
- [x] 性能优化（启动会话加载 N+1 修复，实测 212×；见 docs/PERFORMANCE.md）
- [x] macOS 系统通知（生成完成/失败，设置可开关）
- [ ] Spotlight / Shortcuts（需正式 bundle 签名注册，debug 壳不适用，暂缓）
