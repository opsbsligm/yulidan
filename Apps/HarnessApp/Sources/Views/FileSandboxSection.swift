import AppKit
import SwiftUI

/// 通用设置 — 文件沙箱区块（限制文件工具可访问的目录范围）
struct FileSandboxSection: View {
    @State private var sandboxRoot: String?
    var onSandboxChange: ((String?) -> Void)?

    init(onSandboxChange: ((String?) -> Void)? = nil) {
        self.onSandboxChange = onSandboxChange
        _sandboxRoot = State(initialValue: UserDefaults.standard.string(forKey: "sandboxRoot"))
    }

    var body: some View {
        SettingsCard(title: "文件沙箱", icon: "lock.shield") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("限制文件工具只能访问指定目录")
                            .font(.system(.body))
                            .foregroundStyle(HarnessTheme.textPrimary)
                        Text(sandboxRoot == nil ? "未限制：文件工具可访问任意本地路径" : "文件工具仅允许访问该目录及其子目录")
                            .font(.system(size: 11))
                            .foregroundStyle(HarnessTheme.textTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: sandboxEnabled)
                        .labelsHidden()
                }
                if let root = sandboxRoot {
                    HStack(spacing: 8) {
                        Text(root)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(HarnessTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("更改…") { chooseSandboxDir() }
                        Button("停用") { disableSandbox() }
                    }
                } else {
                    Button("选择根目录…") { chooseSandboxDir() }
                }
            }
        }
    }

    // MARK: - 文件沙箱

    private var sandboxEnabled: Binding<Bool> {
        Binding(
            get: { sandboxRoot != nil },
            set: { enabled in
                if enabled {
                    chooseSandboxDir()
                } else {
                    disableSandbox()
                }
            }
        )
    }

    private func chooseSandboxDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择文件工具的沙箱根目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applySandbox(url.path)
    }

    private func disableSandbox() {
        applySandbox(nil)
    }

    private func applySandbox(_ root: String?) {
        if let root {
            UserDefaults.standard.set(root, forKey: "sandboxRoot")
        } else {
            UserDefaults.standard.removeObject(forKey: "sandboxRoot")
        }
        sandboxRoot = root
        onSandboxChange?(root)
    }
}
