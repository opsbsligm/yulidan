# G4c · D-5「做」实施设计 —— Cordis Bridge Sidecar（v1，09-04）

> 拍板依据：D-5=做（DECISION_INDEX 拍板记录区 09-04）；覆盖面收益 = Cordis 系 ≈50%
> （高星 57%，n=256 实查，CENSUS 补查节）。本文档只定**架构与阶段**；一切 API
> 细节实施时以 @47f9438 上游源码 + npm 实包 d.ts 实证（铁律 1/7），未实证参数在文中标 ⚠️待查。

## 1 架构（一条复用主线）

**Sidecar 即 MCP server**：Node 进程 `cordis-bridge` 内部实例化 Cordis host、装载
社区 Cordis 插件、把插件经 `apply(ctx)` 注册的工具转发为 MCP `tools/list` +
`tools/call` 面。Swift 宿主**零新协议**：复用 `Packages/MCP/Sources/StdioMCPClient.swift`
（initialize→initialized→tools/list→tools/call 全流程已在册 @L43）+ 既有插件管理面
（PluginListView / MCPDiscovery 通道）。

```
HarnessApp / DSHCLI ── StdioMCPClient(stdio JSON-RPC) ──▶ node cordis-bridge
                                                            ├─ Cordis host（@deepseek-ai/cordis ⚠️待查 API）
                                                            ├─ façade：dsh-* 服务最小子集映射
                                                            └─ 已授权插件包（npm 安装，--legacy-peer-deps 环境事实见 CENSUS）
```

## 2 默认策略（S 组，用户可否决）

- **S-1 Node 运行时 = 本机发现**（PATH + nvm/homebrew 常见位探测；不捆绑分发——体积/签名/维护成本）。缺失时显式提示，不静默降级。
- **S-2 Cordis 运行时 = 构建期 npm 安装到 sidecar 本地目录**（不 vendor 进主仓库二进制；bridge 包 `package.json` 钉版本，可复现）。
- **S-3 通信 = MCP stdio**（同 1 节；拒绝自定义 IPC）。
- **S-4 授权粒度 = 逐包显式启用**：`harness cordis add <pkg>` 落授权清单（包名+版本+尝试 import 的 façade 服务面）；默认全关。动态包（cordis_define 类）不落盘/不跨重启（借鉴上游语义，CENSUS §四）。

## 3 安全红线（不可让渡，引用上游自证）

tool-cordis README @47f9438 原文：「该沙箱隔离全局变量，但**不是安全边界**……应当像
对待 bash 访问一样对待该工具集」。因此：
1. sidecar 独立进程（崩溃/逃逸隔离），由宿主拉起与回收，禁常驻；
2. 环境洗刷：仅白名单 env 透传（HOME/PATH/npm 配置位），工作目录沙箱化到容器目录；
3. **显式授权文本必须声明「插件 JS 等同任意代码执行」**（授权清单首条）；
4. 网络不假装拦截：授权面如实声明「无法细粒度控制网络」；
5. 装载失败/façade 缺服务 → 显式错误文案（对齐 A6 诚实口径，❌假成功）。

## 4 阶段（全部 A 层验收，零前台）

| 阶段 | 内容 | A 层验收 |
|---|---|---|
| **C0 预检** | 本机 node/npx 探测脚本；@deepseek-ai/cordis npm 可达性 + d.ts 实读 | `node --version` 探测输出入册；registry 实查记录 |
| **C1 bridge 骨架** | `tools/cordis-bridge/`（Node 包，主仓 Xcode 门禁外）：手写最小 JSON-RPC 帧（jsonrpc2.0 三方法，零 npm 依赖面=MITM 环境供保性）+ Cordis host 实例化 + fixture 插件装载 | 本地 `node bridge --selftest`：initialize/tools/list 断言 |
| **C2 façade 契约** | 按 CENSUS import 面统计排服务映射优先级（最小子集起步）；缺服务显式报错 | 单测：façade 解析 + 缺服务错误路径 |
| **C3 宿主接入** | DSHCLI `harness cordis add/list/remove`；授权清单文件（JSON）；App 侧经既有 MCP 插件面呈现（预期零 UI 新增） | CLI 层 add→list→remove 全链 + StdioMCPClient 冒烟测试（fixture bridge） |
| **C4 实包验收** | 形态①高星实包 ≥3：add→tools/list 可见→tools/call 回值 | CLI 输出 + bridge 日志入册；UI 呈现为 B 层可选 |

DoD（G4c 子集）：C0–C4 全过 + 四门禁（bridge 不在 Swift 门禁面，宿主改动在）+ 兼容矩阵
追加「层2 实跑样例 ≥3」行 + 镜像 MATCH。

## 5 ⚠️待查清单（实施第一步就是查，不脑补）

1. `@deepseek-ai/cordis` 宿主 API：实例化/插件装载/ctx 服务注册的确切签名 → 读 @47f9438 上游 `cordis` 包源码 + 最新 npm tarball 的 `.d.ts`；
2. Cordis 插件的 `apply(ctx)` 工具注册如何枚举（tools/list 转发的前提）→ 读 tool-cordis README + 抽 1 包实拆（/tmp/g4pkgs* 残存则复用）；
3. `dsh-*` façade 最小集排序 → CENSUS import 面统计原始产物（若 /tmp 已清则重跑统计脚本，登记于 CENSUS「可复核产物」节）。
