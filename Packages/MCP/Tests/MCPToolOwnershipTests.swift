import Foundation
import MCP
import Testing
import Tools

// MARK: - D-18 工具归属判别器：卸载/重装配不得跨服务器误删

//
// 存在理由（D-18，09-06）：`MCPServerManager` 原按 `mcp_<server>_` **前缀**从注册表里删工具，
// 而本地工具名是 `"mcp_\(client.name)_\(spec.name)"` 拼接物 ⇒ 当一名恰为另一名的下划线前缀时，
// 前缀集合发生包含关系，卸载动作会命中别人的工具。实测复现（QUALITY_REPORT 09-06 补记⑨）：
//   服务器 `my` 工具 `server_x` → `mcp_my_server_x`
//   服务器 `my_server` 工具 `y` → `mcp_my_server_y`
//   disconnect("my") ⇒ before=["mcp_my_server_x","mcp_my_server_y"] → after=[]（后者**静默误删**）
// 修法＝归属改按工具对象自带的 `client.name` 判定（`MCPToolAdapter` 注册时即携带）。
// 本文件三条：两条误删面（disconnect / refreshTools）+ 一条防漏删正向面
// （「不连带删」若被实现成「干脆不删」同样是缺陷，必须有反向判别力）。

/// 造一对「一名是另一名下划线前缀」的碰撞服务器，并把工具装进注册表。
private func makePrefixCollidingFixture() async -> (MCPServerManager, ToolRegistry) {
    let manager = MCPServerManager()
    let registry = ToolRegistry()

    let my = MockMCPClient(name: "my")
    await my.addTool(MCPToolSpec(name: "server_x", description: "属于 my 的工具")) { _ in "x" }

    let myServer = MockMCPClient(name: "my_server")
    await myServer.addTool(MCPToolSpec(name: "y", description: "属于 my_server 的工具")) { _ in "y" }

    await manager.register(my)
    await manager.register(myServer)
    await manager.installTools(into: registry)
    return (manager, registry)
}

@Test("卸载 `my` 只注销归属 `my` 的工具，不连带删掉 `my_server` 的工具")
func disconnectDoesNotEvictCollidingServer() async {
    let (manager, registry) = await makePrefixCollidingFixture()

    let before = await registry.names().sorted()
    #expect(
        before == ["mcp_my_server_x", "mcp_my_server_y"],
        "前置不成立（装配面异常，本用例失去判别力）：\(before)"
    )

    await manager.disconnect(name: "my", into: registry)

    let after = await registry.names().sorted()
    #expect(
        after == ["mcp_my_server_y"],
        "前缀误删回归：`my_server` 的工具被 `my` 的卸载连带删除 ⇒ \(after)"
    )
}

@Test("重装配 `my` 的工具（tools/list_changed 路径）不得连带清掉 `my_server` 的工具")
func refreshToolsDoesNotEvictCollidingServer() async {
    let (manager, registry) = await makePrefixCollidingFixture()

    let count = await manager.refreshTools(for: "my", into: registry)
    #expect(count == 1, "应重新装配 `my` 的 1 个工具，实际 \(count)")

    let after = await registry.names().sorted()
    #expect(
        after == ["mcp_my_server_x", "mcp_my_server_y"],
        "refreshTools 的前缀清理越界：`my_server` 的工具被清 ⇒ \(after)"
    )
}

@Test("卸载必须删净自己的全部工具（防止把「不连带删」实现成「干脆不删」）")
func disconnectRemovesEveryOwnedTool() async {
    let manager = MCPServerManager()
    let registry = ToolRegistry()

    let alpha = MockMCPClient(name: "alpha")
    await alpha.addTool(MCPToolSpec(name: "one", description: "a1")) { _ in "1" }
    await alpha.addTool(MCPToolSpec(name: "two", description: "a2")) { _ in "2" }
    let beta = MockMCPClient(name: "beta")
    await beta.addTool(MCPToolSpec(name: "three", description: "b1")) { _ in "3" }

    await manager.register(alpha)
    await manager.register(beta)
    await manager.installTools(into: registry)

    let before = await registry.names().sorted()
    #expect(
        before == ["mcp_alpha_one", "mcp_alpha_two", "mcp_beta_three"],
        "前置不成立：\(before)"
    )

    await manager.disconnect(name: "alpha", into: registry)

    let after = await registry.names().sorted()
    #expect(
        after == ["mcp_beta_three"],
        "漏删回归：归属 `alpha` 的工具未随卸载注销（陈旧工具会继续下发给 Agent）⇒ \(after)"
    )
}
