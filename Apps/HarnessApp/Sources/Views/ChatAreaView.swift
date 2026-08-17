import Session
import SwiftUI

struct ChatAreaView: View {
    let session: SessionRecord
    @ObservedObject var viewModel: AppViewModel
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            ChatTopBar(viewModel: viewModel, session: session, draftText: messageText)
                .background(.ultraThinMaterial)

            // 消息区域
            if viewModel.messages.isEmpty {
                EmptyChatPrompt(viewModel: viewModel)
            } else {
                MessageScrollView(
                    messages: viewModel.messages,
                    isGenerating: viewModel.isGenerating,
                    error: viewModel.generationError
                )
            }
            // 输入区域
            ChatInputArea(
                text: $messageText,
                attachments: viewModel.attachments,
                isGenerating: $viewModel.isGenerating,
                error: viewModel.generationError,
                modelName: "\(viewModel.llmConfig.provider.displayName) / \(viewModel.llmConfig.modelName)",
                onSend: { viewModel.sendMessage($0) },
                onStop: { viewModel.stopGenerating() },
                onRetry: { viewModel.retryLastMessage() },
                onAttach: { viewModel.attachFiles() },
                onRemoveAttachment: { viewModel.removeAttachment($0) },
                isFocused: _isInputFocused
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(HarnessTheme.bgPrimary)
        .onAppear { isInputFocused = true }
    }
}

// MARK: - 顶部栏

struct ChatTopBar: View {
    @ObservedObject var viewModel: AppViewModel
    let session: SessionRecord
    let draftText: String
    @State private var modelHovered = false
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var showDeleteConfirm = false
    var body: some View {
        HStack(spacing: 8) {
            // 模型选择（真实菜单：提供商 → 模型）
            Menu {
                ForEach(ModelProvider.allCases, id: \.self) { provider in
                    let models = provider.selectableModels.isEmpty
                        ? [viewModel.llmConfig.modelName]
                        : provider.selectableModels
                    Section(provider.displayName) {
                        ForEach(models, id: \.self) { model in
                            Button {
                                selectModel(provider: provider, model: model)
                            } label: {
                                if viewModel.llmConfig.provider == provider, viewModel.llmConfig.modelName == model {
                                    Label(model, systemImage: "checkmark")
                                } else {
                                    Text(model)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button {
                    viewModel.selectedTab = .settings
                } label: {
                    Label("模型设置…", systemImage: "gear")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.llmConfig.provider.icon)
                        .font(.system(size: 12))
                    Text("\(viewModel.llmConfig.provider.displayName) · \(viewModel.llmConfig.modelName)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(modelHovered ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(modelHovered ? Color.secondary.opacity(0.1) : .clear)
                .cornerRadius(6)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .onHover { modelHovered = $0 }
            .help("切换模型提供商与模型")

            if !viewModel.hasAPIKey {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    Text("未配置 API Key").font(.system(size: 11)).foregroundStyle(.orange)
                }
                .onTapGesture { viewModel.selectedTab = .settings }
                .help("点击前往设置配置 API Key")
            }

            Spacer()

            HStack(spacing: 2) {
                RealButton(icon: "doc.badge.plus", label: "附件", action: { viewModel.attachFiles() })
                RealButton(icon: "square.and.arrow.up", label: "分享", action: { viewModel.shareChat() })
                RealButton(icon: "trash", label: "清空", action: { viewModel.clearChat() })
                RealButton(icon: "fork", label: "派生", action: { viewModel.spawnSubagentFromChat(draftText) })
                // 更多（真实菜单）
                Menu {
                    Button { viewModel.shareChat() } label: { Label("复制到剪贴板", systemImage: "doc.on.doc") }
                    Button { viewModel.exportChat() } label: { Label("导出为 Markdown…", systemImage: "square.and.arrow.down") }
                    Button {
                        renameText = viewModel.sessionTitle(for: session)
                        showRenameAlert = true
                    } label: { Label("重命名对话…", systemImage: "pencil") }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: { Label("删除对话", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .padding(6)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("更多操作")
                .alert("重命名对话", isPresented: $showRenameAlert) {
                    TextField("对话名称", text: $renameText)
                    Button("确定") { viewModel.renameSession(renameText) }
                    Button("取消", role: .cancel) {}
                }
                .confirmationDialog("确定删除该对话？此操作不可恢复。",
                                    isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("删除", role: .destructive) { viewModel.deleteSession(session) }
                    Button("取消", role: .cancel) {}
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func selectModel(provider: ModelProvider, model: String) {
        var cfg = viewModel.llmConfig
        cfg.provider = provider
        cfg.modelName = model
        if provider == .local, cfg.modelName == "local" {
            viewModel.showToast("请在「设置 → 模型服务」填写本地模型名称（如 qwen2.5:7b）")
        }
        cfg.save()
        viewModel.showToast("已切换：\(provider.displayName) / \(model)")
    }
}

// MARK: - 通用按钮

struct RealButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 13))
                Text(label).font(.system(size: 12))
            }
            .foregroundStyle(isHovered ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isHovered ? HarnessTheme.surface : .clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - 消息列表

struct MessageScrollView: View {
    let messages: [ChatMessage]
    let isGenerating: Bool
    let error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if let error {
                        ErrorMessageView(error: error).id("error")
                    }
                    if isGenerating {
                        GeneratingIndicator().id("generating")
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .onChange(of: messages.count) {
                if let lastId = messages.last?.id {
                    withAnimation(.smooth) { proxy.scrollTo(lastId, anchor: .bottomTrailing) }
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            // 用户消息：右对齐浅色气泡，无头像无姓名
            HStack {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(HarnessTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(HarnessTheme.userMessage)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } else {
            // 助手/工具/系统：小头像 + 纯文本，去掉边框感
            HStack(alignment: .top, spacing: 10) {
                RoleAvatar(role: message.role)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if message.status == .sending {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        }
                        if message.status == .error {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                    }
                    MessageContent(content: message.content)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 32)
            }
        }
    }
}

struct ErrorMessageView: View {
    let error: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 16)).foregroundStyle(.orange)
            Text(error).font(.system(size: 13)).foregroundStyle(.orange)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08)).cornerRadius(10)
        .padding(.horizontal, 48)
    }
}

// MARK: - 消息内容（含代码块）

struct MessageContent: View {
    let content: String
    var body: some View {
        let paragraphs = content.components(separatedBy: "\n\n")
        Group {
            if paragraphs.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(paragraphs, id: \.self) { para in
                        if para.hasPrefix("```") {
                            CodeBlock(text: para)
                        } else {
                            Text(para).font(.system(.body, design: .rounded))
                                .foregroundStyle(HarnessTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else if content.hasPrefix("```") {
                CodeBlock(text: content)
            } else {
                Text(content).font(.system(.body, design: .rounded))
                    .foregroundStyle(HarnessTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CodeBlock: View {
    let text: String
    @State private var copied = false

    private var lang: String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        let cleaned = firstLine.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "```", with: "")
        return cleaned.isEmpty ? "code" : cleaned
    }

    private var codeText: String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") {
                s.removeSubrange(...nl)
            }
            if s.hasSuffix("```") {
                s.removeLast(3)
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang).font(.system(size: 10, weight: .semibold)).foregroundStyle(HarnessTheme.textTertiary)
                Spacer()
                Button(copied ? "已复制" : "复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(codeText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .font(.system(size: 10)).foregroundStyle(HarnessTheme.textTertiary)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
            Text(codeText).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(HarnessTheme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.08))
        .cornerRadius(8)
    }
}

struct RoleAvatar: View {
    let role: ChatRole
    var body: some View {
        ZStack {
            Circle().fill(role == .user ? Color.blue : Color.purple).opacity(0.18)
            Image(systemName: role == .user ? "person.fill" : "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(role == .user ? Color.blue : Color.purple)
        }
    }
}

struct GeneratingIndicator: View {
    @State private var pulse: CGFloat = 0.5
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoleAvatar(role: .assistant).frame(width: 24, height: 24)
            HStack(spacing: 6) {
                ForEach(0 ..< 3) { i in
                    Circle().fill(HarnessTheme.accent).frame(width: 6, height: 6)
                        .scaleEffect(pulse + CGFloat(i) * 0.15)
                        .opacity(1 - CGFloat(i) * 0.25)
                        .animation(.easeInOut(duration: 0.4).repeatForever(), value: pulse)
                }
            }
            Text("Harness 正在思考…").font(.system(size: 12)).foregroundStyle(HarnessTheme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .onAppear { withAnimation { pulse = 1.2 } }
    }
}

// MARK: - 空对话引导（复用胶囊组件）

struct EmptyChatPrompt: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 48)
            ZStack {
                Circle()
                    .fill(HarnessTheme.accent.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(HarnessTheme.accent)
            }
            Text("我能帮你做什么？")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("让我来编写代码、分析文件、执行命令或搜索信息")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(HarnessTheme.textSecondary)
            HStack(spacing: 8) {
                SuggestionChip(icon: "doc.badge.plus", text: "新建项目") { viewModel.sendMessage("帮我创建一个新项目") }
                SuggestionChip(icon: "code", text: "写代码") { viewModel.sendMessage("帮我编写一段代码") }
                SuggestionChip(icon: "terminal", text: "运行命令") { viewModel.sendMessage("帮我执行一个终端命令") }
                SuggestionChip(icon: "doc.text.magnifyingglass", text: "文件分析") { viewModel.sendMessage("帮我分析一个文件") }
            }
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 输入区

struct ChatInputArea: View {
    @Binding var text: String
    let attachments: [FileAttachment]
    @Binding var isGenerating: Bool
    let error: String?
    let modelName: String
    let onSend: (String) -> Void
    let onStop: () -> Void
    let onRetry: () -> Void
    let onAttach: () -> Void
    let onRemoveAttachment: (UUID) -> Void
    @FocusState var isFocused: Bool

    var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespaces).isEmpty || !attachments.isEmpty) && !isGenerating
    }

    var body: some View {
        VStack(spacing: 8) {
            // 错误条
            if let error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).lineLimit(2)
                    Spacer()
                    Button("重试") { onRetry() }.font(.system(size: 12)).foregroundStyle(HarnessTheme.accent)
                }
                .padding(8).background(Color.orange.opacity(0.1)).cornerRadius(8)
            }

            // 输入卡片：圆角 14，文本框无边框，底行 = 附件 / 模型 / 发送
            VStack(spacing: 0) {
                // 附件芯片
                if !attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(attachments) { att in
                                HStack(spacing: 4) {
                                    Image(systemName: "paperclip").font(.system(size: 9))
                                    Text(att.name).font(.system(size: 11)).lineLimit(1)
                                    if att.truncated {
                                        Text("（截断）").font(.system(size: 9)).foregroundStyle(.orange)
                                    }
                                    Button {
                                        onRemoveAttachment(att.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(HarnessTheme.surfaceHover).cornerRadius(6)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    }
                }

                TextField("给 Harness 发送消息…", text: $text, axis: .vertical)
                    .font(.system(.body, design: .rounded))
                    .textFieldStyle(.plain)
                    .lineLimit(1 ... 8)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .focused($isFocused)
                    .onSubmit {
                        if canSend {
                            onSend(text); text = ""
                        }
                    }

                // 底行
                HStack(spacing: 8) {
                    Button(action: onAttach) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
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

                    // 发送（实心圆↑）/ 停止（红■）
                    Button {
                        if isGenerating {
                            onStop()
                        } else if canSend {
                            onSend(text); text = ""
                        }
                    } label: {
                        ZStack {
                            Circle().fill(
                                isGenerating ? Color.red
                                    : canSend ? Color.primary
                                    : Color.secondary.opacity(0.12)
                            )
                            Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(
                                    isGenerating ? .white
                                        : canSend ? Color(nsColor: .windowBackgroundColor)
                                        : HarnessTheme.textTertiary
                                )
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(isGenerating ? "停止生成（真实取消请求）" : "发送")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .background(HarnessTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? HarnessTheme.accent.opacity(0.45) : HarnessTheme.border, lineWidth: 1)
            )

            // 提示行（卡片外）
            HStack(spacing: 12) {
                Text("Enter 发送 · Shift+Enter 换行")
                Text("Harness 使用 AI，请检查输出。")
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(HarnessTheme.textTertiary)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - 消息模型（UI 层）

enum MessageStatus: String { case sent, sending, delivered, error }

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let status: MessageStatus

    init(id: UUID, role: ChatRole, content: String, timestamp: Date, status: MessageStatus = .sent) {
        self.id = id; self.role = role; self.content = content
        self.timestamp = timestamp; self.status = status
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum ChatRole {
    case user, assistant, system, tool
    var displayName: String {
        switch self {
        case .user: "你"
        case .assistant: "Harness"
        case .system: "系统"
        case .tool: "工具"
        }
    }
}
