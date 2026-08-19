import SwiftUI

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
