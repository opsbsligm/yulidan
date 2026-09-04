// C2 fixture：模拟 dsh-web-search-zai 形态（inject web + registerSearchProvider）
export const name = 'bridge-fixture-web'
export const inject = ['web']
export async function apply (ctx) {
  ctx.web.registerSearchProvider({
    name: 'fixture',
    description: 'fixture search provider',
    search: async (q) => `results:${q}`,
  })
}
