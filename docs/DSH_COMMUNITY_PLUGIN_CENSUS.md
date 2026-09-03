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

### 层1 兼容矩阵（≥3 实跑样例达成）
| # | 服务器 | 命令 | serverInfo | 工具数 | 握手 | 证据通道 |
|---|---|---|---|---|---|---|
| 1 | **DSH 社区包** `@zseven-w/dsh-crew` | `node src/server.mjs`（解包+`npm i --omit=dev --ignore-scripts --legacy-peer-deps`） | `dsh-crew/0.1.0-rc.7` | 6（dsh_run_worker 等） | ✅ 726ms | **双通道**：独立探针 `tools/g4/mcpprobe` + **我方宿主 `StdioMCPClient` opt-in 测试**（`MCPCommunityLiveTests`，0.273s passed） |
| 2 | 官方参考 `@modelcontextprotocol/server-filesystem` | `npx -y …server-filesystem /tmp/g4sandbox` | `secure-filesystem-server/0.2.0` | 14 | ✅ 6.6s（含 npx 下载） | 探针 |
| 3 | 官方一致性 `@modelcontextprotocol/server-everything` | `npx -y …` | `mcp-servers/everything/2.0.0` | 13 | ✅ 4.6s | 探针 |

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
```
