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
                    error: viewModel.generationError,
                    activeToolName: viewModel.activeToolName
                )
            }
            // 输入区域
            ChatInputArea(
                text: $messageText,
                attachments: viewModel.attachments,
                isGenerating: $viewModel.isGenerating,
                error: viewModel.generationError,
                viewModel: viewModel,
                tools: viewModel.tools,
                onInsertTool: { tool in
                    messageText = AppViewModel.appendingToolMention(messageText, tool.name)
                    isInputFocused = true
                },
                onSend: { viewModel.sendMessage($0) },
                onStop: { viewModel.stopGenerating() },
                onRetry: { viewModel.retryLastMessage() },
                onAttach: { viewModel.attachFiles() },
                onRemoveAttachment: { viewModel.removeAttachment($0) },
                isFocused: _isInputFocused
            )
            .frame(maxWidth: .infinity) // 居中（内层限宽 720）
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(HarnessTheme.bgPrimary)
        .onAppear { isInputFocused = true }
    }
}

// MARK: - 顶部栏（Codex 式：左=会话标题 / 右=模型 pill + 溢出菜单）

struct ChatTopBar: View {
    @ObservedObject var viewModel: AppViewModel
    let session: SessionRecord
    let draftText: String
    @State private var moreHovered = false
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var showDeleteConfirm = false
    @State private var showClearConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            // 会话标题（Codex 式：左侧主元素，当前任务名）
            Text(viewModel.sessionTitle(for: session))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(HarnessTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(viewModel.sessionTitle(for: session))
                .accessibilityLabel("会话：\(viewModel.sessionTitle(for: session))")

            if !viewModel.hasAPIKey {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    Text("未配置 API Key").font(.system(size: 11)).foregroundStyle(.orange)
                }
                .onTapGesture { viewModel.selectedTab = .settings }
                .help("点击前往设置配置 API Key")
            }

            Spacer()

            // 模型选择（Codex 式：右侧紧凑 pill，与 composer 底行共用 ModelSwitcherMenu）
            ModelSwitcherMenu(viewModel: viewModel)

            // 更多（Codex 式：动作按钮收纳进溢出菜单）
            Menu {
                Button { viewModel.togglePinSession(session) } label: {
                    Label(session.metadata.pinned ? "取消置顶" : "置顶",
                          systemImage: session.metadata.pinned ? "pin.slash" : "pin")
                }
                Button { viewModel.attachFiles() } label: { Label("添加附件", systemImage: "doc.badge.plus") }
                Button { viewModel.spawnSubagentFromChat(draftText) } label: { Label("派生子 Agent", systemImage: "fork") }
                Divider()
                Button { viewModel.shareChat() } label: { Label("复制到剪贴板", systemImage: "doc.on.doc") }
                Button { viewModel.exportChat() } label: { Label("导出为 Markdown…", systemImage: "square.and.arrow.down") }
                Button {
                    renameText = viewModel.sessionTitle(for: session)
                    showRenameAlert = true
                } label: { Label("重命名对话…", systemImage: "pencil") }
                Divider()
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: { Label("清空本对话", systemImage: "trash") }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: { Label("删除对话", systemImage: "trash.slash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(moreHovered ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(moreHovered ? HarnessTheme.surface : .clear)
                    )
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .onHover { moreHovered = $0 }
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
            .confirmationDialog("确定清空本对话的全部消息？此操作不可恢复。",
                                isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { viewModel.clearChat() }
                Button("取消", role: .cancel) {}
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}

// MARK: - 消息列表

struct MessageScrollView: View {
    let messages: [ChatMessage]
    let isGenerating: Bool
    let error: String?
    /// 正在执行的工具名（nil = 思考中）
    let activeToolName: String?
    /// 是否贴近底部（Codex 式：仅贴底时新消息自动跟随，上翻阅读历史不强制回底）
    @State private var isNearBottom = true
    @State private var showJumpToBottom = false

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
                        GeneratingIndicator(activeToolName: activeToolName).id("generating")
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 80
            } action: { _, nearBottom in
                isNearBottom = nearBottom
                showJumpToBottom = !nearBottom
            }
            .overlay(alignment: .bottomTrailing) {
                if showJumpToBottom {
                    Button {
                        if let lastId = messages.last?.id {
                            withAnimation(.smooth) { proxy.scrollTo(lastId, anchor: .bottomTrailing) }
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HarnessTheme.textPrimary)
                            .padding(8)
                            .background(Circle().fill(HarnessTheme.glassDark))
                            .overlay(Circle().stroke(HarnessTheme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .accessibilityLabel("回到底部")
                }
            }
            .onChange(of: messages.count) {
                // 贴近底部才自动跟随；用户上翻阅读历史时不打断
                if isNearBottom, let lastId = messages.last?.id {
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
            // Codex 式：用户消息无气泡纯文本（通栏左对齐，medium 字重区分角色）
            Text(message.content)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(HarnessTheme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if message.role == .tool {
            // 工具轨迹：Codex 式可折叠执行行（展开看入参/输出；无详情走简洁行）
            if let trace = message.toolTrace?.first {
                ToolTraceRow(item: trace)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                    Text(message.content)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(HarnessTheme.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.leading, 34) // 对齐助手文本列（24 头像 + 10 间距）
                .frame(maxWidth: 480, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("工具执行：\(message.content)")
            }
        } else {
            // 助手/系统：小头像 + 纯文本，去掉边框感
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
    /// 正在执行的工具名（nil = 模型思考中）
    let activeToolName: String?
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
            if let activeToolName {
                Text("Harness 正在运行工具：\(activeToolName) …")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(HarnessTheme.textTertiary)
            } else {
                Text("Harness 正在思考…").font(.system(size: 12)).foregroundStyle(HarnessTheme.textTertiary)
            }
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

// MARK: - 消息模型（UI 层）

enum MessageStatus: String { case sent, sending, delivered, error }

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let status: MessageStatus
    /// 工具轨迹详情（.tool 消息专用；历史恢复的消息为 nil → 走简洁行）
    let toolTrace: [ToolTraceItem]?

    init(id: UUID, role: ChatRole, content: String, timestamp: Date, status: MessageStatus = .sent,
         toolTrace: [ToolTraceItem]? = nil) {
        self.id = id; self.role = role; self.content = content
        self.timestamp = timestamp; self.status = status
        self.toolTrace = toolTrace
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
