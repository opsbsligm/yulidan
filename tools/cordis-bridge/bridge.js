// cordis-bridge · G4c sidecar（D-5=做，设计 docs/G4C_SIDECAR_DESIGN.md）
// 职责：装载「已授权」Cordis 社区插件，把其 ctx.tools.register 注册的工具
//       经 MCP stdio（initialize/tools/list/tools/call）转发给 Swift 宿主
//       （复用在册 Packages/MCP/StdioMCPClient，S-3）。
// 安全：单实例进程由宿主拉起（S-4 授权清单在宿主侧）；本进程只装载显式
//       传入的插件标识符，❌自动发现/❌cordis.yml 全量装载。
// API 依据（铁律 1/7，全部实包实证 @09-04 C0）：
//   - bootstrap 范式：cordis@4.0.2 自带 bin.js 逐字（new Context / baseUrl / ctx.plugin(Loader) / loader.create）
//   - Service 注册：service.d.ts「Subclasses call super(ctx, name) from their
//     constructor. The service is registered immediately...」
//   - 插件形态：registry.d.ts Plugin.Function/Constructor/Object（inject/apply）
//   - ⚠️tool 对象真实字段形状 C2 实拆落定；本文件 call 路径按候选字段防御式
//     探测并如实记录（❌假装已知 dsh tool 完整契约）。
import { Context, Service } from '@deepseek-ai/cordis'
import Loader from '@deepseek-ai/cordis-plugin-loader'
import { pathToFileURL } from 'node:url'
import { resolve } from 'node:path'
import { mkdir } from 'node:fs/promises'

/** façade 服务：承接社区插件 `ctx.tools.register(tool)`（dsh-crew 实拆调用面） */
class ToolsService extends Service {
  constructor (ctx) {
    super(ctx, 'tools')
    this.registry = new Map()
  }

  register (tool) {
    if (!tool || typeof tool.name !== 'string') {
      throw new Error('cordis-bridge: tool must have a string name (façade v1)')
    }
    this.registry.set(tool.name, tool)
    // dsh 语义返回值占位：宿主卸载经 fiber dispose 自动回收（service.d.ts）
    return () => this.registry.delete(tool.name)
  }

  unregister (name) { this.registry.delete(name) }

  list () { return [...this.registry.values()] }
}

/** 宿主侧 façade 插件：提供 tools 服务（后续 C2 扩 dsh-* 服务映射时同型追加） */
function FacadePlugin (ctx) { new ToolsService(ctx) }
FacadePlugin.provide = 'tools'

/** 桥内核：bootstrap 一次，rpc() 复用（stdio 循环与 --selftest 共享同一路径） */
export class Bridge {
  constructor (sandboxDir) {
    this.sandboxDir = sandboxDir
    this.ctx = undefined
    this.tools = undefined
  }

  async start (pluginSpecifiers) {
    await mkdir(this.sandboxDir, { recursive: true })
    const ctx = new Context()
    ctx.baseUrl = pathToFileURL(this.sandboxDir).href + '/'
    await ctx.plugin(FacadePlugin)
    await ctx.plugin(Loader)
    this.tools = ctx.tools
    for (const specifier of pluginSpecifiers) {
      // 逐包显式装载（S-4）；name=模块 specifier，loader.create 契约见
      // plugin-loader@1.0.3 config/tree.d.ts create(options: Omit<EntryOptions,'id'>)
      await ctx.loader.create({ name: specifier })
    }
    this.ctx = ctx
  }

  async rpc (req) {
    const { id, method, params } = req
    const reply = (result) => ({ jsonrpc: '2.0', id, result })
    const fail = (code, message) => ({ jsonrpc: '2.0', id, error: { code, message } })
    try {
      if (method === 'initialize') {
        return reply({
          protocolVersion: '2024-11-05',
          capabilities: { tools: {} },
          serverInfo: { name: 'swift-harness-cordis-bridge', version: '0.1.0' },
        })
      }
      if (method === 'tools/list') {
        // MCP 面只暴露 name/description/inputSchema（tool 其余字段不透传）
        const tools = this.tools.list().map((t) => ({
          name: t.name,
          description: t.description ?? '',
          inputSchema: t.inputSchema ?? t.parameters ?? { type: 'object', properties: {} },
        }))
        return reply({ tools })
      }
      if (method === 'tools/call') {
        const tool = this.tools.registry.get(params?.name)
        if (!tool) return fail(-32602, `unknown tool: ${params?.name}`)
        // ⚠️执行面形状待 C2 实拆落定——候选顺序探测，探测结果如实带出
        const impl = ['execute', 'handler', 'call', 'run'].find(
          (k) => typeof tool[k] === 'function',
        )
        if (!impl) {
          return reply({ content: [{ type: 'text', text: `bridge: no callable impl on tool '${tool.name}' (façade gap, logged for C2)` }], isError: true })
        }
        const out = await tool[impl](params?.arguments ?? {})
        const text = typeof out === 'string' ? out : JSON.stringify(out)
        return reply({ content: [{ type: 'text', text: `impl:${impl} ` + text }] })
      }
      if (method === 'notifications/initialized') return undefined // 通知无应答
      return fail(-32601, `method not found: ${method}`)
    } catch (e) {
      return fail(-32603, `bridge error: ${e?.message ?? e}`)
    }
  }
}

/* ---------------- CLI 入口 ---------------- */
if (import.meta.url === `file://${process.argv[1]}`) {
  const argv = process.argv.slice(2)
  const plugins = []
  let sandbox = '/tmp/cordis-bridge-sandbox'
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--sandbox') { sandbox = argv[++i]; continue }
    if (argv[i].startsWith('--')) continue
    // 本地路径→绝对 file URL；裸包名原样（由 node_modules 解析）——loader 的
    // name 即模块 specifier（entry.d.ts），相对路径按 sandbox baseUrl 解析的
    // 行为以本次实测为准（09-04：相对裸路径会被解析到 baseUrl，必须显式化）
    plugins.push(argv[i].startsWith('.') ? pathToFileURL(resolve(argv[i])).href : argv[i])
  }
  const bridge = new Bridge(sandbox)
  try {
    await bridge.start(plugins)
  } catch (e) {
    console.error(`bridge bootstrap failed: ${e?.stack ?? e}`)
    process.exit(2)
  }
  if (argv.includes('--selftest')) {
    const list = await bridge.rpc({ jsonrpc: '2.0', id: 1, method: 'tools/list' })
    const names = (list.result?.tools ?? []).map((t) => t.name)
    const call = await bridge.rpc({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'bridge_fixture_echo', arguments: { msg: 'hi' } } })
    const text = call.result?.content?.[0]?.text ?? ''
    const ok = names.includes('bridge_fixture_echo') && text === 'impl:execute echo:hi'
    console.log(JSON.stringify({ selftest: ok ? 'PASS' : 'FAIL', tools: names, call: text }))
    process.exit(ok ? 0 : 1)
  }
  // stdio JSON-RPC 循环（一行一条，MCP stdio 口径）
  const rl = await import('node:readline/promises').then((m) => m.createInterface({ input: process.stdin }))
  for await (const line of rl) {
    if (!line.trim()) continue
    let req
    try { req = JSON.parse(line) } catch { process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'parse error' } }) + '\n'); continue }
    const res = await bridge.rpc(req)
    if (res !== undefined) process.stdout.write(JSON.stringify(res) + '\n')
  }
  process.exit(0)
}
