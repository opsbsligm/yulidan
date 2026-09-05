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

## 5 ⚠️待查清单（09-04 C0 轮首查，实证落位）

1. **✅已落定｜cordis 宿主 API**：npm 实包 `@deepseek-ai/cordis@4.0.2`（time.modified 2026-08-30）自带 `bin.js` 官方 bootstrap 范式，逐字：
   `new Context()` → `ctx.baseUrl = pathToFileURL(cwd)+'/'` → `ctx.plugin(Loader)` → `ctx.loader.create({ name: '@deepseek-ai/cordis-plugin-include', config: { path: './cordis.yml' } })`
   （deps 仅 `@standard-schema/spec` + `@deepseek-ai/cosmokit`，依赖面极小；类型面=context/events/fiber/logger/registry/service/utils，registry.d.ts 经 `declare module './context.ts'` 扩展 ctx）。
2. **✅已落定（09-05 核销，原标 ◐）｜loader 与工具枚举**：`@deepseek-ai/cordis-plugin-loader@1.0.3` registry 可达 ✅（C0）；「插件注册工具如何从 ctx 枚举」**已实测定型三个注册面**：① `ctx.tools.register`（C2 直采）② `ctx.web.registerSearchProvider`（C2 web 采集）③ `skills.registerProvider`（§12 collector 轮实证）；②③ 由通用 registrar 采集（register/add 前缀→元数据投影，执行面仅条目自带 handler 字段才接通，❌猜语义）。双 fixture selftest 全 PASS 在册。
3. **✅路径已变更（09-05 核销，原标 ☐未启动）｜façade 最小集排序**：C2 未走「CENSUS import 面统计重跑」这条前置路，而改为**更优的运行时静态读插件自身 `inject` 声明自动铺 stub/tools**（§8「façade v2 落位」＝`provideStub(ctx,name)` + `ctx.reflect.provide`，有 service.d.ts 注释原文自证）⇒ 原前置任务不再需要，登记为**被取代**而非完成。

## 6 C0 预检实录（09-04，全 A 层只读）

- 本机 Node：`/opt/homebrew/bin/node` **v26.6.0**，npx 同路径 ✅（S-1 通过）；
- registry（npmjs.org）直连可达：cordis 4.0.2 / plugin-loader 1.0.3 ✅（S-2 供保成立；MITM 环境 cafile 口径沿 CENSUS「环境实操事实」节）；
- 实包下载 `npm pack --ignore-scripts` 成功；取证残留 `/tmp/g4c/`（注：loader 与 cordis 解包同名目录互相覆盖，正式实施按包名分目录重拆）；
- 上游源码 @47f9438 在位（monorepo packages/ 内无 cordis 包——cordis 为独立发版件，以 npm 实包为准，铁律 7）。

## 7 C1 实录（09-04，全 A 层，零前台）

- 落位 `tools/cordis-bridge/`（package.json 钉 cordis 4.0.2 + plugin-loader 1.0.3；
  node_modules 不入库；`npm install --ignore-scripts` 4 包 6s，MITM 直连再证）。
- **契约实证补录**（全部运行时反馈，非脑补）：
  ① loader 的 `name` 对相对路径按 sandbox `baseUrl` 解析（裸相对路径被解析成
    目录导入报错实录，错误源曾是脚本 argv 解析 bug 把 sandbox 值当插件）→
    bridge 侧本地路径统一转绝对 file URL，裸包名交 node_modules 解析；
  ② `Service` 子类构造即注册（service.d.ts 原文 + selftest 生效证实）；
  ③ 插件 `export const inject = ['tools']` + `export async function apply(ctx)`
    形态经 fixture 实跑装载成功（dsh-crew 实拆同款契约）；
  ④ `loader.create` 运行时返回 entry id（tree.d.ts 签名一致）。
- **A 层证据**：`--selftest` **PASS**（tools/list 含 fixture + tools/call 返回
  `impl:execute echo:hi`）；stdio 冒烟三帧全过（initialize 应答含
  protocolVersion/capabilities/serverInfo = StdioMCPClient 期望形制）。
- 边界如实：tool 执行面为候选字段探测（impl 命中 `execute`；真实社区包形状
  C2 实拆落定）；Swift 宿主 StdioMCPClient 对桥冒烟测试 = C3 首批。
- 门禁注记：本批零 Swift 文件改动（git diff 全在 tools/cordis-bridge + docs），
  pr 门禁 Swift 面零影响沿用；三大门禁清偿计划不变。
- **过程教训（已同步 QUALITY）**：文档写入 heredoc 必须用引号定界符——本轮
  未引号 `$C6` 展开虽然成功，但内容内反引号被 zsh 当命令执行（§7 首写受损+
  混入命令噪声一行，已重写修复）。

## 8 C2 实录（09-04，全 A 层）

- **inject 普查**（n=4 实拆样本）：dsh-crew rc6/rc7 `inject=[agents,sessions,
  agentDefaultModel,tools,llm,attachments]`+`ctx.tools.register`；
  dsh-web-search-zai `inject=[invariants,web]`+**第二注册面 `ctx.web.
  registerSearchProvider(p)`**；theme-kit（UI 形态已裁决不做）。
- **façade v2 落位**：① `provideStub(ctx,name)` 显式 stub（满足 inject 存在性，
  方法调用即显式报错；注册走 `ctx.reflect.provide`——service.d.ts 注释原文证实
  Service 构造内部即此调用）；② `makeWebFacade` 采集半：provider→MCP tool 转换
  （`search_<name>`，execute→provider.search(query)）；③ 装载前静态读 `inject`
  自动铺 stub/tools 保持真实。
- **实包试跑（结果如实）**：
  - ✅ **dsh-crew rc7 装载成功**：tools/list 返回真实工具 `describe_image`+
    `generate_image`（完整 description/inputSchema）——**形态①「拿来即用」首例
    实锤**（走 file URL 快捷路径，包自带 node_modules 使依赖自足）；
    真实 tool 形状含 execute——C1 探测字段命中，**call 面不实测**（两工具均外部
    副作用，安全红线：验证名义不驱动第三方执行）。
  - ❌ zai：`Cannot find package '@deepseek-ai/dsh-credentials'`——tarball 裸拆
    缺自身依赖（非 façade 问题）→ **正式口径=宿主 add 时 `npm install <pkg>` 到
    bridge 环境**（S-2 设计意图，本轮手工验证走了快捷路径）；
  - ❌ hindsight：lib/index.js 不存在（main 猜测路径错误，实施 add 流程时以
    package.json main 为准）。
- selftest 扩为**双 fixture**（tools 直采+web 采集）全 PASS。
- C4 入口定型：add 流程=npm install --no-save（或独立安装目录）+ specifier=包名；
  call 面验收改用**无副作用工具**样本或 mock provider，不驱动真实外部服务。

## 9 下一步（C3/C4 入口）

- C3：DSHCLI `harness cordis add/list/remove` + 授权清单文件 +
  StdioMCPClient↔bridge 冒烟测试（opt-in，模式沿 MCPCommunityLiveTests；
  Swift 改动批进全量门禁）。
- C4：add=正式 npm install 流程 + ≥3 包 tools/list 矩阵 + 无副作用 call 样例。

## 10 C3 实录（09-04，CLI 全链 + 在册宿主客户端实锤）

- **落位**：`dsh cordis add|list|remove|probe`（`CordisCommands.swift` @DSHCLI）；
  授权清单 `~/.harness/cordis/allowlist.json`（S-4，consent 文本=上游 README 口径）；
  测试缝 `DSH_CORDIS_ROOT`/`DSH_CORDIS_BRIDGE_SRC`（同 reduceTransparencyTestOverride 模式）。
- **env 洗刷达成**：`/usr/bin/env -i HOME PATH 白名单` 作 StdioMCPClient command，
  **零改在册客户端**。probe 未授权即拒（实测 S-4 门）；remove 撤销后 probe 复拒 ✔。
- **三轮运行时教训（全部实证修复）**：
  ① **peer 传递闭包**：`--legacy-peer-deps` 跳过 peers，@deepseek-ai 生态 peer=硬依赖
    且递归（zai→dsh-web→dsh-llm/credentials/…）→ `installPeerClosure` 迭代安装
    （实测第 3 轮收敛）；
  ② **npm reify 清 extraneous**：bridge 包不可放 node_modules（装完插件即被清）→
    `env/bridge-src/`（node 解析向上可达）；
  ③ **/tmp→/private/tmp symlink 击穿主模块判定**：`import.meta.url === file://argv[1]`
    被 Swift 宿主绝对路径差异打断 → realpath 双侧比较（症状=握手"传输断开"且 stderr 空）。
- **loader 解析锚=baseUrl（sandbox）非 node_modules**：裸包名不可用 → 包名经已装
  `package.json.main` 转 file URL（`cordisResolveSpecifier`；exports-only 包未支持已登记）。
- **A 层验收证据**：`HOME` 隔离（测试缝）全链 add→list→probe→remove→probe 复拒；
  probe 输出「✅ 握手成功：dsh-web-search-zai 暴露 1 个工具 search_provider_1」
  （=在册 StdioMCPClient + env 洗刷 + 真实社区包，DoD「拿来即用」CLI 层实锤）；
  `CordisBridgeLiveTests` opt-in（正例断言 + 守卫 skip 判别力双验）。
- probe 失败路径带 bridge stderr 透出（recentStderr，CLI 可运维性）。
- 门禁：C3 代码批触发 pr 全量（载体 com.harness.ci11.pr，日志 /tmp/ci_r9_pr.log rc 入册）。

## 11 C4 实录（09-04，矩阵入 CENSUS「层2 兼容矩阵」节）

四样本正式流程实跑：**2 ✅（zai 1 工具 / crew 2 工具，含 scoped+rc-pin）+ 2 ❌（根因归类：宿主未发布服务 worktree / façade 语义边界）**。call 面口径=selftest 在册+真实包不实测（红线）。成功=「拿来即用」CLI 层成立且失败样本给生态普查贡献分类学；「≥3 成功样例」冲刺=下一轮（候选：第五真实包 或 add 本地包支持+demo 发包，两案已在册）。运行时新证：正式版 `hindsight` main=dist/index.js（早前手猜 lib/index.js 错误被正式流程读 main 自动纠正——main 字段读取设计的价值实证）。

## 12 collector 轮（09-04 同日续）：矩阵 3✅+2❌ 达成
- 第三注册面 `skills.registerProvider` 实证 → 通用 registrar 采集（register/add 前缀→
  元数据投影；执行面仅条目自带 execute/handler/... 字段接通，❌猜语义）；web 专用
  语义（search 执行）与通用采集**并存**（一度被通用替换致 zai 执行面降级——当场回归
  网住，selftest 判别力实证）。
- crew 随采集扩展 2→3 工具；skills-manager 3 工具（含真实 `create_skill`）。
- 教训入档：JS 块注释内 `*/` 字样（register*/add*）提前闭合注释——注释文案禁裸 `*/`。

## 13 G4 轨道 DoD 核对（09-05，纯文档核销，A 层）

| v8 DoD 子句 | 达成证据（可复现锚点） | 判定 |
|---|---|---|
| G4a 普查（上游源码＋npm 实查，只读） | `docs/DSH_COMMUNITY_PLUGIN_CENSUS.md` 层1／层2／**层3** 三节；层3 决定性证据＝宿主 `client-modules.md` L49 `platform: 'web'` ＋ `dev-web.ts` L42 严格相等 ＋ 全仓 `package.json` 39/39 全 web | ✅ |
| G4b 路线拍板（D-5） | `DECISION_INDEX` D-5 ＝ ✅ 09-04「做（G4c 启动）」 | ✅ |
| G4c 实施 | 本文件 §6–§12：C0 预检 → C1 bridge selftest → C2 façade v2 → C3 CLI 全链（`dsh cordis add/list/remove/probe` ＋ `~/.harness/cordis/allowlist.json` 授权门 ＋ env 洗刷）→ C4 矩阵 → collector 轮第三注册面 | ✅ |
| 「拿来即用」CLI/配置层验收 | §10：`HOME` 隔离下 add→list→probe→remove→probe 复拒全链；probe 实输出「✅ 握手成功：dsh-web-search-zai 暴露 1 个工具」 | ✅ |
| 兼容矩阵 ≥3 实跑样例 | **双口径达成**：层1 矩阵 3 行（社区 `@zseven-w/dsh-crew` rc.6↔rc.7 升级回路 ＋ 官方 filesystem ＋ everything，含 App 真实链路 `MCPCommunityAppFlowTests`）；层2 矩阵 **3✅**（zai 1 工具／crew 3 工具／skills-manager 3 工具含真实 `create_skill`）＋2❌ 归因入分类学 | ✅ |
| 安全红线（默认不信任／sidecar 独立进程／最小权限／显式授权） | §2 S 组 ＋ §10：授权清单文件门（未授权 probe 即拒）、`env -i` 白名单、`--ignore-scripts`、只 initialize＋tools/list **零 tools/call**、超时必 kill | ✅ |

⇒ **G4 轨道 DoD 全部达成**，剩余为生态边界而非我方待办：主题/UI 类插件属结构性不适用（层3 第③类失败：宿主平台枚举不含我方平台），
已在 CENSUS 层3 与「❌不做 Cordis UI 注入界面兼容」一致登记。
⚠️ 唯一未实测面如实申报：**call 面**（真实第三方执行）按安全红线不驱动，采「selftest 在册＋无副作用样本」口径。
