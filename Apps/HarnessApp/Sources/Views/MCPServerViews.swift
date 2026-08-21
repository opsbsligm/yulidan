import SwiftUI

// MARK: - P0.4 MCP stdio 服务器行

struct MCPServerRow: View {
    let server: MCPDisplayItem
    let onRetry: () -> Void
    let onLogs: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(server.isAvailable ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .frame(width: 36, height: 36)
                Circle().fill(server.isAvailable ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(server.name).font(.system(.body, design: .rounded)).fontWeight(.medium)
                    Text(server.isAvailable ? "运行中" : "离线").font(.system(size: 11))
                        .foregroundStyle(server.isAvailable ? Color.green : Color.red)
                    if let count = server.toolCount {
                        Text("\(count) 个工具").font(.system(size: 11))
                            .foregroundStyle(HarnessTheme.textTertiary)
                    }
                    Spacer()
                    if !server.isAvailable {
                        Button {
                            onRetry()
                        } label: {
                            Label("重启", systemImage: "arrow.clockwise").font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    Button {
                        onLogs()
                    } label: {
                        Label("日志", systemImage: "scroll.document").font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    Button {
                        onRemove()
                    } label: {
                        Label("卸载", systemImage: "trash").font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.red)
                }
                Text(server.command +
                    (server.arguments.isEmpty ? "" : " " + server.arguments.joined(separator: " ")))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(HarnessTheme.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                if !server.isAvailable, let info = server.serverInfo {
                    Text(info).font(.system(size: 11)).foregroundStyle(HarnessTheme.textTertiary)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .padding(12)
        .background(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.4) : HarnessTheme.surface.opacity(0.5))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isHovered ? HarnessTheme.accent.opacity(0.3) : HarnessTheme.border, lineWidth: 0.5))
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}

// MARK: - P0.4 MCP 运行日志面板（最近 stderr 回显）

struct MCPServerLogSheet: View {
    let viewModel: AppViewModel
    let server: MCPDisplayItem
    @State private var logText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MCP 服务器运行日志：\(server.name)")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button("刷新") {
                    Task { logText = await viewModel.mcpServerLog(server) }
                }
                .controlSize(.small)
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(logText)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(HarnessTheme.surface.opacity(0.5))
                    .cornerRadius(8)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
        .onAppear {
            Task { logText = await viewModel.mcpServerLog(server) }
        }
    }
}
