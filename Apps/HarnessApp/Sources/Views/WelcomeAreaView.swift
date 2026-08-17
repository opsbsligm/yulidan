import SwiftUI

/// Codex 式新任务页：
/// hero（图标+标题）垂直居中 → 底部固定区 = 胶囊建议（在文本框上面）+ composer 文本框（贴屏幕最下面）
struct WelcomeAreaView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var prompt = ""
    @FocusState private var isInputFocused: Bool

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.attachments.isEmpty
    }

    private var modelName: String {
        "\(viewModel.llmConfig.provider.displayName) · \(viewModel.llmConfig.modelName)"
    }

    var body: some View {
        ZStack {
            HarnessTheme.bgPrimary

            // hero：水平垂直完全居中
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(HarnessTheme.accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(HarnessTheme.accent)
                }
                Text("Harness")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(HarnessTheme.textPrimary)
                    .padding(.top, 12)
                Text("你的 macOS 原生 AI 助手")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(HarnessTheme.textSecondary)
                    .padding(.top, 4)
            }

            // 底部固定区：建议 chips（文本框上面）+ 文本框（最下面）
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    SuggestionChip(icon: "terminal", text: "在 /tmp 运行 ls 并展示输出") {
                        sendText("在 /tmp 运行 ls 并展示输出")
                    }
                    SuggestionChip(icon: "code", text: "写一个 Swift 函数判断素数") {
                        sendText("帮我写一个 Swift 函数判断素数，并附单元测试思路")
                    }
                    SuggestionChip(icon: "doc.text.magnifyingglass", text: "解释这个项目的目录结构") {
                        sendText("用中文简要解释 ~/code/swift-harness 项目的目录结构和各包职责")
                    }
                    SuggestionChip(icon: "puzzlepiece.extension", text: "看看有哪些插件") {
                        Task { await viewModel.refreshPlugins() }
                        viewModel.selectedTab = .plugins
                    }
                }

                // composer 卡片（Codex 式：全宽、底行 ＋ … 模型 … 黑色发送圈）
                VStack(spacing: 0) {
                    TextField("有什么需要帮忙的？", text: $prompt, axis: .vertical)
                        .font(.system(.body, design: .rounded))
                        .textFieldStyle(.plain)
                        .lineLimit(1 ... 6)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .focused($isInputFocused)
                        .onSubmit(send)

                    HStack(spacing: 8) {
                        // 附件（真实动作：打开文件选择器）
                        Button(action: attachFile) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HarnessTheme.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.secondary.opacity(0.08)))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("添加文件附件")

                        Spacer()

                        Text(modelName)
                            .font(.system(size: 11))
                            .foregroundStyle(HarnessTheme.textTertiary)
                            .lineLimit(1)

                        // 发送（黑色实心圆↑，Codex 风格）
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(canSend ? Color(nsColor: .windowBackgroundColor) : HarnessTheme.textTertiary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle().fill(canSend ? Color.primary : Color.secondary.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .help("发送")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .background(HarnessTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isInputFocused ? HarnessTheme.accent.opacity(0.5) : HarnessTheme.border,
                                lineWidth: 1)
                )
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { isInputFocused = true }
    }

    private func attachFile() {
        viewModel.attachFiles()
    }

    private func send() {
        sendText(prompt)
    }

    private func sendText(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !viewModel.attachments.isEmpty else { return }
        viewModel.createNewSession()
        viewModel.sendMessage(text)
        prompt = ""
    }
}

// MARK: - 胶囊建议（欢迎页 / 空对话共用）

struct SuggestionChip: View {
    let icon: String
    let text: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(HarnessTheme.textTertiary)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(HarnessTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isHovered ? HarnessTheme.surfaceHover : HarnessTheme.surface)
            )
            .overlay(
                Capsule().stroke(isHovered ? HarnessTheme.accent.opacity(0.4) : HarnessTheme.border,
                                 lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(text)
    }
}
