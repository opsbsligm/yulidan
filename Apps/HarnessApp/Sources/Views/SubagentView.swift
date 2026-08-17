import Foundation
import Subagent
import SwiftUI

// MARK: - 多 Agent 协作页

struct SubagentView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var newName = ""
    @State private var newTask = ""
    @State private var timeoutSeconds: Double = 120

    var runningCount: Int {
        viewModel.subagents.filter { !$0.phase.isTerminal }.count
    }

    var finishedCount: Int {
        viewModel.subagents.filter(\.phase.isTerminal).count
    }

    var canSpawn: Bool {
        !newName.trimmingCharacters(in: .whitespaces).isEmpty &&
            !newTask.trimmingCharacters(in: .whitespaces).isEmpty &&
            viewModel.hasAPIKey
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部（与插件页一致）
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("多Agent")
                        .font(.system(.title2, design: .rounded)).fontWeight(.semibold)
                    Text("\(runningCount) 运行中 · \(finishedCount) 已完成（SubagentCoordinator 真实编排）")
                        .font(.system(size: 13))
                        .foregroundStyle(HarnessTheme.textSecondary)
                }
                Spacer()
                if viewModel.subagents.contains(where: \.phase.isTerminal) {
                    Button("清理已完成") {
                        viewModel.clearFinishedSubagents()
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(HarnessTheme.textSecondary)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider()
            // 派生表单
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("任务名称（如：文档摘要）", text: $newName)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                    TextField("超时(秒)", value: $timeoutSeconds, format: .number)
                        .font(.system(size: 13))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                    Button {
                        spawn()
                    } label: {
                        Label("派生", systemImage: "fork")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSpawn)
                }
                TextField("任务描述（作为首条消息发给子 Agent）", text: $newTask, axis: .vertical)
                    .font(.system(size: 13))
                    .lineLimit(2 ... 4)
                    .textFieldStyle(.roundedBorder)
                if !viewModel.hasAPIKey {
                    Text("⚠️ 尚未配置模型 API Key，请先在「设置」中配置后再派生子任务")
                        .font(.system(size: 12))
                        .foregroundStyle(HarnessTheme.warning)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()
            // 子任务列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.subagents) { item in
                        SubagentCard(item: item) {
                            viewModel.cancelSubagent(item)
                        }
                    }
                    if viewModel.subagents.isEmpty {
                        ContentUnavailableView(
                            "暂无子任务",
                            systemImage: "person.3",
                            description: Text("在上方填写任务后派生，最多 4 个子任务并行执行")
                        )
                        .padding(.top, 40)
                    }
                }
                .padding(16)
            }
        }
        .background(HarnessTheme.bgPrimary)
    }

    private func spawn() {
        viewModel.spawnSubagent(name: newName, task: newTask, timeout: max(5, timeoutSeconds))
        newName = ""
        newTask = ""
    }
}

// MARK: - 子任务卡片

struct SubagentCard: View {
    let item: SubagentDisplayItem
    let onCancel: () -> Void

    var phaseLabel: String {
        switch item.phase {
        case .pending: "排队中"
        case .running: "运行中"
        case .succeeded: "已成功"
        case .failed: "失败"
        case .timedOut: "超时"
        case .cancelled: "已取消"
        }
    }

    var phaseColor: Color {
        switch item.phase {
        case .pending: HarnessTheme.textTertiary
        case .running: HarnessTheme.accent
        case .succeeded: HarnessTheme.success
        case .failed: HarnessTheme.error
        case .timedOut: HarnessTheme.warning
        case .cancelled: HarnessTheme.textSecondary
        }
    }

    var elapsedText: String {
        guard let e = item.elapsed else { return "—" }
        return e >= 60 ? String(format: "%.1f 分钟", e / 60) : String(format: "%.1fs", e)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.phase == .running ? "arrow.triangle.2.circlepath" : "person.crop.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(phaseColor)
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(elapsedText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(HarnessTheme.textTertiary)
                Text(phaseLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(phaseColor)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(phaseColor.opacity(0.12))
                    .clipShape(Capsule())
                if !item.phase.isTerminal {
                    Button("取消", action: onCancel)
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(HarnessTheme.error)
                }
            }
            if let error = item.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(HarnessTheme.error)
            }
            if let result = item.resultText {
                ScrollView {
                    Text(result)
                        .font(.system(size: 12))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .background(HarnessTheme.surface)
                .cornerRadius(HarnessTheme.radiusSmall)
            }
            if !item.stepLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(item.stepLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(HarnessTheme.textTertiary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(HarnessTheme.bgSecondary)
                .cornerRadius(HarnessTheme.radiusSmall)
            }
        }
        .padding(12)
        .background(HarnessTheme.surface)
        .cornerRadius(HarnessTheme.radiusMedium)
        .overlay(RoundedRectangle(cornerRadius: HarnessTheme.radiusMedium).stroke(HarnessTheme.border, lineWidth: 0.5))
    }
}

#Preview {
    SubagentView(viewModel: AppViewModel())
        .frame(width: 700, height: 500)
}
