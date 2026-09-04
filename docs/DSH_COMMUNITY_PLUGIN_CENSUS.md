# G4a · DSH 社区插件生态普查（v1）

> 普查时间：2026-09-03（静默轮，全程只读）｜上游基线：deepseek-harness @`47f9438`
> 方法：本机上游源码逐包核对 + npm registry 实查 + 权威社区目录快照 + 代表性抽样 6 包依赖面分析
> 铁律 7 合规：全部结论挂证据源；抽样外推处显式标注

## 一、规模与权威源

| 项 | 值 | 证据 |
|---|---|---|
| 目录源 | `awesome-dsh-plugin`（https://awesome-dsh-plugin.com，GitHub: awesome-dsh-plugin/awesome-dsh-plugin，CC0-1.0） | 目录包自述；**社区聚合源，非 deepseek-ai 官方渠道**（标注） |
| 快照版本 | `dsh-plugin-catalog@2026.902.3089`（updated 2026-09-02） | npm registry 实查，tarball 已核验 |
| 条目数 | **2937**（23 类目） | plugins.json `count` 字段 |
| 生态热度 | 有 npm 包名 1425 / 独立 tarball 150 / 合计下载 **3,901,145** / stars>50 共 172 | plugins.json 聚合统计 |
| 官方安装通道 | 全部 2937 条统一 `dsh plugin --profile <p> add <pkg>` CLI | plugins.json install 字段（profile 取值分布待查） |

## 二、类目分布（前 12）

UI 增强 476 · 工具与能力 379 · 开发与运行时 239 · 会话与消息 185 · 工作流 173 · 用量计费 163 · 记忆 136 · 技能包 125 · 通知集成 122 · 模型接入 120 · **主题外观 105** · 安全权限 100（其余：娱乐96/视觉95/远程79/Git71/浏览器70/市场70/语音46/文档44/WSL33/身份9/AGI 1）

## 三、形态分类（核心结论）

**抽样 6/6 全为 Cordis 原生 TS 插件**（`@deepseek-ai/cordis` peer/dep + `@deepseek-ai/dsh-*` 服务包，main=lib/index.js，无 bin）：
`dshmarket`(市场,dl 30万) / `dsh-better-sidebar`(UI,dl 20.8万) / `dsh-dream-skin`(主题,client-ui/store 依赖=UI注入) / `dsh-context`(会话) / `dsh-config-manager`(工具,带bin) / `dsh-skills-manager`(技能)。

| 形态 | 判据 | 规模估计 | 与 DSH-Swift 兼容路线 |
|---|---|---|---|
| ① Cordis host-半（工具/命令/服务） | dep cordis + dsh-agent/tools/session 等 host 服务 | ~2/3（tools/dev/session/memory/workflow/model 等） | **仅 Node sidecar 承载可「拿来即用」**（apply(ctx) 进程内 JS，Swift 无法原生加载） |
| ② Cordis client-半（UI 注入） | dep dsh-client-ui-*/store/runtime | ≥476（ui 类目）+ 各类目 client 面 | **界面兼容明确不做**（❌WebView 铁律）；仅数据部分可经 spec.json 通道 |
| ③ 数据型（主题色板/技能 md） | theme 105 + skill 125 中含纯数据件 | ≤230（需逐包二查，部分实为②） | 既有 spec.json / Skill markdown 通道可适配 |
| ④ 纯 MCP 包装型 | npm 无 cordis dep、bin=MCP server | **抽样 0/6**（v7「层1 已在手」预期需下修；不排除少量长尾存在，待全量二查） | StdioMCPClient 直接装载（能力已在，样本待找） |

## 四、上游信任立场（G4b 安全论证直接引用）

tool-cordis README（@47f9438）原文：「该沙箱隔离全局变量，但**不是安全边界**……应当像对待 bash 访问一样对待该工具集」。上游自己都不把 Cordis 插件当安全沙箱 → 我方 sidecar 必须独立进程 + 最小权限 + 显式授权清单（红线不变），且**动态包（cordis_define）不落盘/不跨重启**语义可借鉴为默认策略。

## 五、对 D-5 决策材料的改写

- 主流生态（2700+）= Cordis 原生：**A（Node sidecar 全承载）是唯一能「拿来即用」覆盖主流的方案**；成本=Node 分发 + 用 dsh 服务 façade 覆盖插件实际 import 面（需先做全量 import 面统计定契约规模）。
- B（仅数据型适配 ~230 条 + 其余出《改写 MCP 指南》）成本最低，覆盖率最低。
- C（高星精选人工适配）折中；stars>50 共 172 条为候选池。
- 补充查证项（拍板前）：① 全量 1425 npm 包 import 面统计（定 sidecar façade 契约规模）；② `dsh plugin --profile` 的 profile 语义；③ 目录外插件（未入目录的增量）。

## 六、可复用发现（超出兼容轨）

- 社区主题插件=client-半注入（Web），印证我们「主题只走数据通道 + 原生玻璃表达」的路线在 2700+ 注入件面前不可同构兼容——不是缺陷，是基线选择。
- 官方 CLI `dsh plugin add` 的装载体验（目录源+CLI+profile）可作为我们插件市场社区源的对标物（G4c 装载体验清单）。

---

## 补查（09-03 G4a 第二轮）：import 面量化统计（n=256 实抓，替换早前 6 例抽样结论）

> 方法（纯只读）：目录 `plugins.json`（2937 条 → **唯一 npm 包 1425**）取 stars>50 全部唯一包 **116**
> ＋ 其余随机抽样 **140**（seed=42）＝ **256 个包**，逐个 `curl registry.npmjs.org/<pkg>` 取
> `dist-tags.latest` 的 `dependencies`/`devDependencies`/`bin`/`keywords`，**抓取成功 256/256（0 失败）**。
> 判据：`cordis` = 依赖名匹配 `cordis|@deepseek-ai/*|^dsh-*`；`mcp` = 依赖名含
> `modelcontextprotocol` 或 `mcp`；`bin` = manifest 声明可执行；`ui` = keywords/description 命中
> userscript/tampermonkey/content.script/inject/浏览器 等（关键词启发式，弱信号，仅用于下限估计）。

| 维度 | n=256 实测 | 高星组(n=116) | 随机组(n=140) |
|---|---|---|---|
| **依赖 Cordis/`@deepseek-ai`/`dsh-*`**（需 Cordis+Node 运行时） | **129 = 50%** | **57%** | 44% |
| 依赖 MCP SDK（我方可**原生**承载） | **4 = 1%** | 1% | 1% |
| 带 `bin`（配置/CLI 层可装载） | 32 = 12% | — | — |
| keywords 命中 UI 注入/浏览器面（弱信号下限） | 11 = 4% | — | — |
| 既非 Cordis 也非 MCP（数据/工具类） | 125 = 49% | — | — |

最高频运行时依赖 Top6：`@deepseek-ai/schemastery` 35 ｜ `zod` 27 ｜ `schemastery` 10 ｜
`undici` 9 ｜ `js-yaml` 8 ｜ `qrcode`/`yaml` 7 —— **第一高频即上游私有的 `@deepseek-ai/schemastery`**
（Cordis 侧 UI schema 库），非通用 MCP 生态件。

### 结论改写（对 D-5 的直接后果，铁律 7：以实查为准）

1. **早前「抽样 6/6 全 Cordis 原生」结论修正为更准的区间**：Cordis 系**约半数**（高星 57% > 随机 44%
   ——越受欢迎的包越依赖上游运行时），并非 100%，也**不是**可以忽略的少数。
2. **「社区插件拿过来直接用」经 MCP 路线不可达**：全目录 MCP 依赖率 **1%**。我们的原生 MCP 宿主
   能承载的社区包 ≈ **14 个量级/1425**（1% 外推），且这 1% 还需逐个验证入口兼容性。
   → **「拿来即用」的前提被实测否定**，这不是实现难度问题，是生态事实。
3. 于是 D-5 三案的真实覆盖面（以本次 n=256 为证据）：
   - **A｜Node + Cordis 运行时 sidecar**：覆盖 **≈50%（高星 57%）**，也是唯一能让"社区目录基本可用"
     的路；代价 = 第三方运行时入基线（需「基线纯度论证 + 用户裁决」门）+ 上游自述
     "沙箱不是安全边界，像 bash 一样对待" 的安全面 + 体积/更新面。
   - **B｜仅原生 MCP/CLI 承载（零新运行时）**：覆盖 **≈1%（MCP）∪ 12%（带 bin，仍需逐个包装）**
     → 实质等于「社区目录基本不可用，只兼容标准 MCP 插件」。诚实表述应为
     **"兼容 MCP 协议插件生态，不兼容 Cordis 目录"**，不得称"DSH 社区插件拿来即用"。
   - **C｜精选高星适配**：116 高星唯一包 → 57% 需 sidecar（回到 A 的运行时问题），
     余 43%（≈50 包）可逐个写薄适配层；成本随包数线性增长，且上游 API 变动需持续追平。
4. **决策口径建议（供你拍板，不代拍）**：把兼容目标从"社区目录拿来即用"改为**分层承诺**——
   层1 标准 MCP 插件（我们原生承载，长期正确，社区当前覆盖率 1%）；
   层2 Cordis 目录 = 明示"需 Node/Cordis sidecar（可选组件，默认关闭，独立进程+最小权限+显式授权）"，
   仅在你批准 A 时实施；UI 注入类（Cordis 476 条最大类目）永久不做（与纯原生基线结构性冲突）。

### 可复核产物
- `/tmp/dshcat2/package/plugins.json`（目录快照，tarball 源 `/tmp/dshcat.tgz`）
- `/tmp/census_ok.json`（256 包 deps/bin/keywords 明细）
- `/tmp/census_out.txt`（统计原始输出，含 Top12 依赖计数）
- 复现脚本要点：唯一化 by npm → stars>50 ∪ random.sample(seed=42, 140) → `curl -s -m 10
  https://registry.npmjs.org/<pkg 斜杠转 %2f>` → latest manifest 分类（本机 python urllib 走 HTTPS
  会 CERTIFICATE_VERIFY_FAILED，**必须用 curl**；已踩坑记录）


## G4c 层1 实包实测矩阵（2026-09-03 补记㉛，全静默 A 层）

### 验身：4 个带 MCP 依赖的包，真 stdio server 仅 1 个
| 包 | latest | 验身结论 | 证据 |
|---|---|---|---|
| `@zseven-w/dsh-crew` | 0.1.0-rc.7 | ✅ **真 stdio MCP server**（CC/Codex 侧 shim：`src/server.mjs` 顶层 `server.connect(new StdioServerTransport())`，注册 6 工具） | tarball 解包 grep + 实测握手 |
| `dsh-skill-mcp-manager` | 1.1.2 | ❌ SDK **client** 用法（`lib/index.js` 仅 client 命中）+ Cordis 插件壳（cordis.patch.yml） | 同上 |
| `dsh-web-search-zai` | 0.2.0 | ❌ SDK **client** 用法（`src/mcp.ts` 作 client 调上游配额 MCP） | 同上 |
| `@vectorize-io/hindsight-coding-agents` | 0.5.1 | ❌ 24 个 bin 全是 **hook/适配器**（`pi.registerTool` 注册进其他 Agent 宿主，非 stdio server） | 同上 |

→ 「MCP 依赖」≠「可被 MCP 宿主装载」：普查 1% 的 MCP 率里又筛掉 3/4，**社区直装面实际比 1% 更小**。
诚实口径不变且更强：层1（标准 MCP）可达且已实测；层2（Cordis 生态）仍需 D-5 裁决。



## 社区插件形态总表（09-03 收口：四形态 × 接管可行性）

| 形态 | 代表 | 载体/协议 | 我方接管 | 证据 |
|---|---|---|---|---|
| **① MCP stdio server** | `@zseven-w/dsh-crew`（社区唯一真 server） | JSON-RPC over stdio（跨语言协议） | ✅ **拿来即用**（三通道实测：探针/宿主客户端/App 全链路） | 层1 矩阵 + 层1.5（补记㉞） |
| **② 技能（SKILL.md）** | 上游 `.agents/skills/` 11 包 + npm `dsh-skill` 生态 | 目录扫描 + frontmatter（纯文本，跨语言） | ✅ **拿来即用**（11/11 零改写） | SkillUpstreamCompatTests（补记㉟） |
| **③ 服务 seam 补丁** | `@deepseek-ai/dsh-{sandbox,compaction,shell,spill,jobs,goal,web,attachment}` | TS **进程内 ctx.\* API**（npm 包 description 逐字 "Abstract … seam for the DeepSeek Harness"；capability-seams 架构图在册） | ❌ **结构性 N/A**：依赖 DSH TS 宿主进程内服务注册表，Swift 宿主无该 API 面——非缺陷，协议层错配 | npm search 实查 + docs/capability-seams.zh.md |
| **④ 主题/GUI 插件** | `dsh-theme-kit`(0.1.2)、`@guillaumemeyer/dsh-themes`(0.1.1)、dsh-theme-center/tuner/mineradio/machine/`@eternalnight/*`/`@yguillaumemeyer`等 10+ | **Cordis Web UI 注入**：`cordis.patch.yml` 挂载 + `package.json dsh.client` 浏览器半（browser JS 注入 DSH Web GUI）；资源半含 wallpapers | ❌ **按既定裁决不做**（v8 §四「Cordis UI 注入界面兼容」）；**数据半可吸收**：色板 hex（Tokyo Night/Catppuccin/中国传统色）可人工转写为我方主题插件格式——数据可复用、插件本体不可 | `/tmp/g4pkgs3` npm pack 实拆（--ignore-scripts）：index.js 空 apply + exports["./client"]；kit 的 cordis.patch.yml insert |

**对 D-5 的直接影响**：层2（让社区插件在 App 里跑）的收益面 = 形态①②，两者**层1 已全部实测成立、无需新代码**；
形态③④即便做 Cordis sidecar 也不适用（③=TS 进程内 API 不可跨宿主；④=Web DOM 注入与我方 SwiftUI 原生基线冲突，
且属 v8 §四不做项）。即：**「社区主题插件拿来即用」的诚实边界 = 数据可吃、插件体不可**，D-5 决策请据此核算。

### 技能（指令插件）形态兼容矩阵（09-03 新增，@4a0aa74）
DSH 生态的插件不止 MCP stdio server——**SKILL.md 指令技能**是另一主形态（上游
`packages/skill/skill-filesystem` 装载语义：目录扫描 + YAML frontmatter，name/description）。
我方 `SkillStore.parse` 对上游 **@47f9438 `.agents/skills/` 全部 11 个真实技能**
（dsh-code-review / dsh-prose-standard / record-browser-gif 等）零改写解析通过
（`SkillUpstreamCompatTests`，opt-in `HARNESS_G4_UPSTREAM=1`，两态实测 0.003s passed）：
name==目录名约定 ✓、description/正文齐 ✓。技能文件夹放进 `~/.harness/skills/` 即用。
**边界如实登记**：YAML folded scalar（`description: >`）上游 @47f9438 实测 **0 例**；
我方单行解析对 folded 的降级行为（description 取标记符、name 存在即装载不崩）已固化为
`testFoldedScalarBehaviorIsGraceful`——当前社区面不受影响，若未来社区出现 folded 样本再立修。
复现：`HARNESS_G4_UPSTREAM=1 swift test --filter SkillUpstreamCompatTests`
（可 `HARNESS_G4_DSH_UPSTREAM_DIR` 覆盖上游路径）。


### 插件管理**行为语义**对照（铁律 7 补口：09-03，上游源码 `apps/cli/src/plugin.ts` @47f9438 逐字）

上游 `dsh plugin` = **pnpm 转发器 + 安装态 reconcile**（module 头注释原文："reconcile the
`dsh.profile.bundles` layer list against the installed state … Reconciling by installed state,
not by dependency diff, means `update` activates a package that gained its `dsh.bundle`
declaration in a newer version"）。逐语义对照我方（`importMCPServer`/`retryMCPServer`/`removeMCPServer`）：

| 语义维度 | 上游 dsh CLI | 我方 App | 判定 |
|---|---|---|---|
| 安装即激活 | `pnpm add` 后声明 `dsh.bundle` 的包自动进层栈 | 导入表单 → servers.json 落盘 + **即时连接**（importMCPServer L2166 链路在册） | 同构（载体不同：npm 依赖树 vs JSON 配置） |
| 更新自动生效 | 安装态 reconcile：新版本带声明即自动进层 | **命令指向磁盘路径 → `retryMCPServer` 重启即加载更新后的包**（npm update + App 一键重启 = 升级回路，语义论证级，未实测新版切换） | 语义等价（我方=显式 retry 触发） |
| 卸载 | `pnpm remove` → reconcile 出层 | `removeMCPServer` 配置+子进程**双清**（AppFlow 测试在册） | 对齐且我方更强（显式进程清理） |
| 非插件包混入 | 装为普通库 + 一次性 warning（不崩不拒） | 连接失败 → `toolsLoadWarning` 提示 + 列表 available=false（AppViewModelMCPServerTests 在册） | 同型（优雅降级+提示） |
| enable/disable | 无独立命令（依赖在场性决定） | 无独立开关（连接态即启停，失败可 retry） | 对齐（双方均不加独立开关） |
| 模板自带层 | dsh-base 等非依赖，reconcile 永不触碰 | 内置插件（BuiltInPluginCatalog）与用户 servers.json 分离 | 对齐 |
| 主题发现 | ——（上游主题=Web 插件另成体系，见四形态表④） | 连接后 `get_theme_spec` 自动探测（refreshThemes） | 我方按 MCP 协议的自然扩展，无上游对应物 |

**升级回路已实测闭环（@59cc24b，语义论证 → 实测）**：`dsh-crew` 双版本并装（rc.6 `/tmp/g4pkgs3/dsh-crew-rc6-x`、rc.7 `/tmp/g4pkgs2/dsh-crew`），
`testCommunityServerUpgradeActivatesViaSameNameImport`：rc.6 装载（**前置断言 serverInfo 含 rc.6**，防两路径同包假绿）→
同名导入指向 rc.7 路径 → **serverInfo 翻至 0.1.0-rc.7** + 单条目 + toolCount≥6（live passed 0.288s / 默认 skipped）。
判别力来源：serverInfo **内嵌上游包版本**（探针双版本实测 rc.6↔rc.7 可区分；对照实验：server-filesystem
两 npm 版本 serverInfo 同为 0.2.0 且工具表相同——**不可作品味判别的反例亦登记**，选包方法论）。
复现：`npm pack @zseven-w/dsh-crew@0.1.0-rc.6` → 解包 `npm i --omit=dev --ignore-scripts --legacy-peer-deps --cafile=…` →
`HARNESS_G4_LIVE=1 swift test --filter MCPCommunityAppFlowTests`（RC6 路径键 `HARNESS_G4_DSH_CREW_RC6_DIR`）。

**结论**：插件管理**操作语义与上游同构**（安装即激活/移除即卸载/坏包降级提示/无独立启停开关），
「拿来即用」在行为层同样成立；升级回路=retry（语义论证，标"未实测新版切换"，如 G3 需要可择时实测）。

### 层1 兼容矩阵（≥3 实跑样例达成）
| # | 服务器 | 命令 | serverInfo | 工具数 | 握手 | 证据通道 |
|---|---|---|---|---|---|---|
| 1 | **DSH 社区包** `@zseven-w/dsh-crew` | `node src/server.mjs`（解包+`npm i --omit=dev --ignore-scripts --legacy-peer-deps`） | `dsh-crew/0.1.0-rc.7` | 6（dsh_run_worker 等） | ✅ 726ms | **双通道**：独立探针 `tools/g4/mcpprobe.swift`（可执行 `tools/g4/bin-mcpprobe`） + **我方宿主 `StdioMCPClient` opt-in 测试**（`MCPCommunityLiveTests`，0.273s passed） |
| 2 | 官方参考 `@modelcontextprotocol/server-filesystem` | `npx -y …server-filesystem /tmp/g4sandbox` | `secure-filesystem-server/0.2.0` | 14 | ✅ 6.6s（含 npx 下载） | 探针 |
| 3 | 官方一致性 `@modelcontextprotocol/server-everything` | `npx -y …` | `mcp-servers/everything/2.0.0` | 13 | ✅ 4.6s | 探针 |

**层1.5 升级（09-03，@790e047）**：dsh-crew 证据通道再加**App 真实链路**——`MCPCommunityAppFlowTests`（HarnessApp 测试目标，XCTest opt-in 两态实测：默认 skipped / flag 开 passed 0.096s）走**用户粘贴命令的同一代码路径**：`importMCPServer`（同一 servers.json 序列化格式落盘）→ `mcpManager.connectStdio`（运行时连接）→ `MCPDisplayItem`（isAvailable ✓ / toolCount≥6 ✓ / serverInfo=dsh-crew ✓ / 工具注册表含 dsh_run_worker ✓）→ `removeMCPServer`（配置+子进程双清 ✓）。「拿来即用」从「宿主客户端能连」升级为「App 导入框粘一行命令即装即卸」的代码级证明。

安全姿态（全部样本一致）：只 initialize+tools/list，**零 tools/call**；子进程环境最小化（PATH/HOME 白名单，HOME→`/tmp/g4home` 沙箱）；超时必 kill；`--ignore-scripts` 阻断 postinstall。

### 环境实操事实（企业 MITM 网络，复现必备）
- **npm/node TLS**：`UNABLE_GET_ISSUER_CERT`/`UNABLE_TO_GET_ISSUER_CERT_LOCALLY`——curl 可用而 npm 不可用（系统 keychain 有 MITM 根证书，node 不读）→ 复现：`security find-certificate -a -p` 导 System+SystemRoot 两 keychain 成 ca.pem（164 证书），npm `--cafile=` / 探针 `npm_config_cafile` 透传。
- **`@deepseek-ai` 系 peer 不同步**：dsh-crew 的 devDeps 内 `dsh-system-prompt@rc.8` 要 `dsh-llm@^rc.8`，其余钉 `rc.6` → ERESOLVE 死锁，需 `--legacy-peer-deps`（上游生态脆弱性数据点，供 D-5 层2 论证引用）。
- 老 python 教训复用：本机 homebrew python HTTPS 同样需绕证书——curl 一律优先。

### 复现命令（G3 走查同款可复用）
```bash
# 探针（独立 JSON-RPC 实现，不依赖构建产物）
PROBE_HOME=/tmp/g4home PROBE_PATH=/opt/homebrew/bin:/usr/bin:/bin \
  npm_config_cafile=/tmp/g4home/ca.pem \
  tools/g4/bin-mcpprobe <超时秒> <标签> -- <命令> [参数...]
# 我方宿主客户端实测（opt-in，门禁默认跳过）
HARNESS_G4_LIVE=1 swift test --filter MCPCommunityLiveTests
# App 全链路实测（用户同款 importMCPServer→connectStdio→展示层→卸载，opt-in）
HARNESS_G4_LIVE=1 swift test --filter MCPCommunityAppFlowTests
```

### 层2 兼容矩阵·正式流程四样本（09-04 G4c-C4，全 A 层 CLI 实测）

流程=`dsh cordis add <pkg> --i-understood → probe`（隔离 env，npm registry 正式安装+peer 闭包）：

| 样本 | 结果 | 工具面/根因 |
|---|---|---|
| `dsh-web-search-zai@0.2.0` | ✅ | 1 工具 `search_provider_1`（web façade 采集面收割） |
| `@zseven-w/dsh-crew@0.1.0-rc.7` | ✅ | 2 工具 `describe_image`/`generate_image`（ctx.tools 直采面；scoped+rc-pin+ERESOLVE 史包全通） |
| `@vectorize-io/hindsight-coding-agents@0.5.1` | ❌ | 需 DSH 宿主**未发布服务** `worktree`（npm 无 dsh-worktree，且插件未在 inject 声明）——第三方宿主结构性不可用，CENSUS 形态③「进程内私有 API」预判再证 |
| `dsh-skill-mcp-manager@1.1.2` | ❌ | 对**已声明服务调用真实方法**（C2 stub 显式报错拦截）——façade 语义边界，属宿主服务真实实现缺口，非桥缺陷 |
| `@michengai/dsh-skills-manager@0.1.38` | ✅ | **3 工具**含真实 `create_skill`（通用 registrar 采集面收割 `skills.registerProvider`+`webServer.register`；元数据投影口径，执行面仅条目自带可执行字段才接通） |

**矩阵更新（同日 collector 轮）**：3✅+2❌=五样本正式实跑；`@zseven-w/dsh-crew` 随采集面扩展升至 3 工具。失败分类学：①宿主未发布服务（结构性）；②façade 未实现真实语义（可评估扩展，但每服务真实实现=无限工程，收益按 CENSUS 四形态总表已论证≈0）。成功样本的 call 面=bridge selftest 在册（`impl:execute echo:hi`）；真实包 call 一律不实测（外部副作用红线）。矩阵基线：cordis 4.0.2 + loader 1.0.3 + node v26.6.0 @09-04。
