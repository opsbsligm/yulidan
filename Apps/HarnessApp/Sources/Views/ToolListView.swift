import SwiftUI

struct ToolListView: View {
    @Binding var tools: [ToolDisplayItem]
    let onExecute: (Int, String) -> Void
    let onClear: (Int) -> Void
    @State private var searchText = ""
    @State private var selectedCategory: String = "全部"

    let categories = ["全部", "文件", "终端", "网络", "代理"]

    var filtered: [ToolDisplayItem] {
        var result = tools
        if selectedCategory != "全部" {
            let catMap: [String: String] = ["文件": "filesystem", "终端": "terminal", "网络": "network", "代理": "agent"]
            result = result.filter { catMap[selectedCategory] == $0.category }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("工具").font(.system(.title2, design: .rounded)).fontWeight(.semibold)
                    Text("\(tools.count) 个可用工具").font(.system(size: 13))
                        .foregroundStyle(HarnessTheme.textSecondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                    TextField("搜索工具...", text: $searchText).font(.system(size: 13))
                        .textFieldStyle(.plain).disableAutocorrection(true)
                }
                .frame(width: 200).padding(8).background(HarnessTheme.surface).cornerRadius(8)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider()

            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let count = cat == "全部" ? tools.count :
                        tools.filter {
                            let catMap: [String: String] = ["文件": "filesystem", "终端": "terminal", "网络": "network", "代理": "agent"]
                            return catMap[cat] == $0.category
                        }.count
                    CategoryChip(label: cat, isSelected: selectedCategory == cat, count: count) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(filtered, id: \.id) { tool in
                        let idx = tools.firstIndex(where: { $0.id == tool.id }) ?? 0
                        ToolCard(tool: tool, index: idx, onExecute: onExecute, onClear: onClear)
                    }
                    if filtered.isEmpty {
                        ContentUnavailableView("未找到工具", systemImage: "wrench.and.screwdriver",
                                               description: Text("尝试其他搜索或分类")).padding(.top, 40)
                    }
                }
                .padding(20)
            }
        }
        .background(HarnessTheme.bgPrimary)
    }
}

struct CategoryChip: View {
    let label: String; let isSelected: Bool; let count: Int; let action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 12, weight: isSelected ? .medium : .regular))
                Text("\(count)").font(.system(size: 10))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isSelected ? Color.blue.opacity(0.15) :
                isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : .clear)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? HarnessTheme.accent : HarnessTheme.border, lineWidth: 0.5))
            .foregroundStyle(isSelected ? HarnessTheme.accent : HarnessTheme.textSecondary)
        }
        .buttonStyle(.plain).onHover { isHovered = $0 }
    }
}

struct ToolCard: View {
    let tool: ToolDisplayItem
    let index: Int
    let onExecute: (Int, String) -> Void
    let onClear: (Int) -> Void
    @State private var paramText = ""
    @State private var isHovered = false

    var icon: String {
        switch tool.category {
        case "filesystem": "doc.badge.gear"
        case "terminal": "terminal.fill"
        case "network": "globe"
        case "agent": "person.2.fill"
        default: "wrench.and.screwdriver"
        }
    }

    var iconColor: Color {
        switch tool.category {
        case "filesystem": .blue
        case "terminal": .green
        case "network": .purple
        case "agent": .orange
        default: .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(iconColor.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name).font(.system(.body, design: .monospaced)).fontWeight(.medium)
                    Text(tool.categoryDisplay.isEmpty ? tool.category.capitalized : tool.categoryDisplay)
                        .font(.system(size: 10)).foregroundStyle(iconColor)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(iconColor.opacity(0.1)).cornerRadius(3)
                }
                Spacer()
                if tool.executing {
                    ProgressView().scaleEffect(0.7)
                } else if tool.isExecuted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            Text(tool.description).font(.system(size: 12)).foregroundStyle(HarnessTheme.textSecondary).lineLimit(2)
            HStack(spacing: 8) {
                TextField("参数 (JSON)", text: $paramText)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain).padding(6)
                    .background(HarnessTheme.surface).cornerRadius(6)
                Button {
                    onExecute(index, paramText)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("执行")
                    }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tool.executing ? Color.gray : HarnessTheme.accent)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(tool.executing)
            }
            if !tool.executing, let result = tool.lastResult {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("结果").font(.system(size: 10, weight: .semibold)).foregroundStyle(HarnessTheme.textTertiary)
                        Spacer()
                        Button("清除") { onClear(index) }
                            .font(.system(size: 10)).foregroundStyle(HarnessTheme.textTertiary)
                    }
                    Text(result).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HarnessTheme.textSecondary).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8).background(HarnessTheme.surface).cornerRadius(6)
            }
        }
        .padding(12)
        .background(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.4) : HarnessTheme.surface.opacity(0.5))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isHovered ? HarnessTheme.accent.opacity(0.3) : HarnessTheme.border, lineWidth: 0.5))
        .onHover { isHovered = $0 }
    }
}
