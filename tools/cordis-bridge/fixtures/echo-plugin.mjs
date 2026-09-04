// G4c C1 fixture：模拟形态①社区插件最小契约（inject + apply + ctx.tools.register）
// 调用面对齐 dsh-crew@rc6 实拆：export const inject=[...] / export async function apply(ctx)
export const name = 'bridge-fixture-echo'
export const inject = ['tools']
export async function apply (ctx) {
  ctx.tools.register({
    name: 'bridge_fixture_echo',
    description: 'bridge selftest fixture tool',
    inputSchema: { type: 'object', properties: { msg: { type: 'string' } } },
    execute: async ({ msg }) => `echo:${msg ?? ''}`,
  })
}
