import SwiftUI

struct WelcomeAreaView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var prompt = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(RadialGradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.1)],
                    center: .center, startRadius: 0, endRadius: 40)).frame(width: 80, height: 80)
                Image(systemName: "sparkles").font(.system(size: 36)).foregroundStyle(HarnessTheme.accent)
            }
            Text("Harness").font(.system(.largeTitle, design: .rounded)).fontWeight(.light)
                .foregroundStyle(HarnessTheme.textPrimary).padding(.top, 12)
            Text("你的 macOS 原生 AI 助手").font(.system(.body, design: .rounded))
                .foregroundStyle(HarnessTheme.textSecondary)
            Spacer()
            HStack(spacing: 10) {
                TextField("有什么需要帮忙的？", text: $prompt, axis: .vertical)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: 48, maxHeight: 120)
                    .background(HarnessTheme.surface).cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(isInputFocused ? HarnessTheme.accent : HarnessTheme.border, lineWidth: 1))
                    .focused($isInputFocused)
                    .onSubmit {
                        if !prompt.trimmingCharacters(in: .whitespaces).isEmpty {
                            viewModel.createNewSession()
                            viewModel.sendMessage(prompt)
                            prompt = ""
                        }
                    }
                Button {
                    if !prompt.trimmingCharacters(in: .whitespaces).isEmpty {
                        viewModel.createNewSession()
                        viewModel.sendMessage(prompt)
                        prompt = ""
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                        .foregroundStyle(prompt.trimmingCharacters(in: .whitespaces).isEmpty ?
                            HarnessTheme.textTertiary : HarnessTheme.accent)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 80)
            HStack(spacing: 16) {
                FeatureCard(icon: "terminal.fill", title: "终端", desc: "执行命令", color: .green,
                    action: { viewModel.sendMessage("帮我执行终端命令") })
                FeatureCard(icon: "code.fill", title: "代码", desc: "编写和审查", color: .blue,
                    action: { viewModel.sendMessage("帮我编写代码") })
                FeatureCard(icon: "doc.text.magnifyingglass", title: "搜索", desc: "查找信息", color: .purple,
                    action: { viewModel.sendMessage("帮我搜索信息") })
                FeatureCard(icon: "puzzlepiece.extension", title: "插件", desc: "扩展能力", color: .orange,
                    action: { viewModel.selectedTab = .plugins })
            }
            .padding(.horizontal, 80).padding(.top, 32)
            Spacer()
        }
        .background(HarnessTheme.bgPrimary)
        .onAppear { isInputFocused = true }
    }
}

struct FeatureCard: View {
    let icon: String; let title: String; let desc: String; let color: Color
    let action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color)
                }
                Text(title).font(.system(.body, design: .rounded)).fontWeight(.medium)
                    .foregroundStyle(HarnessTheme.textPrimary)
                Text(desc).font(.system(size: 11)).foregroundStyle(HarnessTheme.textSecondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(isHovered ? HarnessTheme.surfaceHover : HarnessTheme.surface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? color.opacity(0.4) : HarnessTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain).frame(width: 130).onHover { isHovered = $0 }
    }
}
