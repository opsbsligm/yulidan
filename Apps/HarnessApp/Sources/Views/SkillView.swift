import Foundation
import Skill
import SwiftUI

// MARK: - 技能页

struct SkillView: View {
    @ObservedObject var viewModel: AppViewModel

    // 新建技能表单
    @State private var showForm = false
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newTags = ""
    @State private var newInstructions = ""
    // 卡片展开（查看正文）
    @State private var expandedID: String?

    var builtInCount: Int {
        viewModel.skills.filter { $0.source == "builtin" }.count
    }

    var userCount: Int {
        viewModel.skills.count - builtInCount
    }

    var canSave: Bool {
        !newName.trimmingCharacters(in: .whitespaces).isEmpty &&
            !newInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部（与插件页一致）
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("技能")
                        .font(.system(.title2, design: .rounded)).fontWeight(.semibold)
                    Text("\(builtInCount) 内置 · \(userCount) 用户（Agent 可用 list_skills / use_skill 按需加载）")
                        .font(.system(size: 13))
                        .foregroundStyle(HarnessTheme.textSecondary)
                }
                Spacer()
                Button {
                    showForm.toggle()
                } label: {
                    Label(showForm ? "收起" : "新建技能", systemImage: showForm ? "chevron.up" : "plus")
                }
                .font(.system(size: 12))
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider()
            // 新建技能表单
            if showForm {
                newSkillForm
            }
            // 技能列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.skills) { skill in
                        SkillCard(skill: skill, expanded: expandedID == skill.id) {
                            expandedID = expandedID == skill.id ? nil : skill.id
                        } onDelete: {
                            viewModel.deleteUserSkill(skill)
                        }
                    }
                    if viewModel.skills.isEmpty {
                        ContentUnavailableView(
                            "暂无技能",
                            systemImage: "book",
                            description: Text("新建第一个技能，Agent 即可在对话中按需加载")
                        )
                        .padding(.top, 40)
                    }
                }
                .padding(16)
            }
        }
    }

    private var newSkillForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("名称（如 daily-report，空格自动转中划线）", text: $newName)
                    .font(.system(size: 13))
                    .textFieldStyle(.roundedBorder)
                TextField("标签（逗号分隔）", text: $newTags)
                    .font(.system(size: 13))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            TextField("一句话描述（Agent 据此判断何时加载）", text: $newDescription)
                .font(.system(size: 13))
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $newInstructions)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(HarnessTheme.border, lineWidth: 0.5))
            HStack {
                Text("保存到 ~/.harness/skills/<名称>/SKILL.md")
                    .font(.system(size: 11))
                    .foregroundStyle(HarnessTheme.textSecondary)
                Spacer()
                Button("保存") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func save() {
        viewModel.saveUserSkill(name: newName, description: newDescription, tags: newTags, instructions: newInstructions)
        newName = ""
        newDescription = ""
        newTags = ""
        newInstructions = ""
        showForm = false
    }
}

// MARK: - 技能卡片

private struct SkillCard: View {
    let skill: Skill
    let expanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var isBuiltIn: Bool {
        skill.source == "builtin"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(skill.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(isBuiltIn ? "内置" : "用户")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isBuiltIn ? HarnessTheme.bgSecondary : HarnessTheme.accent.opacity(0.15))
                    .foregroundStyle(isBuiltIn ? HarnessTheme.textSecondary : HarnessTheme.accent)
                    .clipShape(Capsule())
                if !skill.tags.isEmpty {
                    Text(skill.tags.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textSecondary)
                }
                Spacer()
                Button {
                    onToggle()
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(HarnessTheme.textSecondary)
                if !isBuiltIn {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HarnessTheme.error)
                    .help("删除用户技能")
                }
            }
            Text(skill.description)
                .font(.system(size: 13))
                .foregroundStyle(HarnessTheme.textSecondary)
            if expanded {
                Text(skill.instructions)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(HarnessTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(HarnessTheme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(HarnessTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HarnessTheme.border, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
