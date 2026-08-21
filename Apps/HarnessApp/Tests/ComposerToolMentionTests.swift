@testable import HarnessApp
import Testing

// MARK: - P0.5.2 输入框加号：插件工具入口（提及 token 纯函数）

@Suite("AppViewModel 工具提及 token")
struct ComposerToolMentionTests {
    @Test("toolMention 格式：@前缀 + 工具名")
    func mentionFormat() {
        #expect(AppViewModel.toolMention("exec_command") == "@exec_command")
        #expect(AppViewModel.toolMention("mcp_theme-mcp_get_theme_spec") == "@mcp_theme-mcp_get_theme_spec")
    }

    @Test("空文本追加：无前导空格")
    func appendToEmpty() {
        #expect(AppViewModel.appendingToolMention("", "read_file") == "@read_file")
        #expect(AppViewModel.appendingToolMention("   ", "read_file") == "@read_file")
    }

    @Test("非空文本追加：半角空格分隔，原有内容保留")
    func appendToNonEmpty() {
        #expect(AppViewModel.appendingToolMention("帮我看看日志", "read_file") == "帮我看看日志 @read_file")
        #expect(AppViewModel.appendingToolMention("已有内容 ", "read_file") == "已有内容 @read_file")
        #expect(AppViewModel.appendingToolMention("a", "b") == "a @b")
    }
}
