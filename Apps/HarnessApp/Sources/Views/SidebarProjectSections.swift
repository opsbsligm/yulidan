import Session
import SwiftUI
import Workspace

// MARK: - 会话行（搜索列表与项目分区共用：拖拽载荷 + 归档右键菜单）

struct SidebarSessionRow: View {
    let session: SessionRecord
    /// 拖拽起点项目（nil = 全局顶层）
    let inProject: ProjectID?
    let title: String
    let isSelected: Bool
    let isGenerating: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onToggleArchive: () -> Void

    var body: some View {
        let payload = SessionDragPayload(
            sessionID: session.id.rawValue,
            fromProjectID: inProject?.rawValue
        )
        return SessionListItem(
            session: session,
            title: title,
            isSelected: isSelected,
            isGenerating: isGenerating,
            onSelect: onSelect,
            onTogglePin: onTogglePin,
            onDelete: onDelete
        )
        .draggable(payload)
        .contextMenu {
            Button {
                onToggleArchive()
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }
    }
}

// MARK: - 项目分区 + 全局顶层（P0.2：展开收起 / 右键菜单 / 拖拽迁移 / 悬停高亮）

struct SidebarProjectSections: View {
    let model: SidebarModel
    let sessions: [SessionRecord]
    let selectedSession: SessionRecord?
    let generatingSessionId: SessionID?
    let titleFor: (SessionRecord) -> String
    let onSelectSession: (SessionRecord) -> Void
    let onTogglePin: (SessionRecord) -> Void
    let onDeleteSession: (SessionRecord) -> Void
    let onNewProject: () -> Void
    let onToggleProjectCollapsed: (Project) -> Void
    let onRenameProject: (Project, String) -> Void
    let onArchiveProject: (Project) -> Void
    let onDeleteProject: (Project, DeleteProjectOption) -> Void
    let onMoveSession: (SessionRecord, ProjectDropTarget) -> Void
    let onToggleSessionArchived: (SessionRecord) -> Void

    /// 重命名项目（sheet 项目 + 名称）
    @State private var renameTarget: Project?
    @State private var renameProjectName = ""
    /// 删除项目确认（二选一）
    @State private var deleteTarget: Project?
    /// 拖拽悬停目标（高亮反馈：项目 id / "global"）
    @State private var targetedDrop: String?

    var body: some View {
        Group {
            // 项目分区（展示序；拖拽落点 = 项目头行）
            HStack(spacing: 6) {
                Text("项目")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HarnessTheme.textTertiary)
                Spacer()
                Button(action: onNewProject) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HarnessTheme.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("新建项目")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            ForEach(model.projectSections) { section in
                sectionCard(section)
            }

            // 全局顶层（无归属 + 未归档；拖拽落点 = 全局区）
            if !model.globalSessions.isEmpty || !model.projectSections.isEmpty {
                VStack(spacing: 2) {
                    Text("全局")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HarnessTheme.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                    let isGlobalTargeted = targetedDrop == "global"
                    ForEach(model.globalSessions) { session in
                        sessionRow(session, inProject: nil)
                    }
                    .background(isGlobalTargeted ? HarnessTheme.accent.opacity(0.06) : .clear)
                    if model.globalSessions.isEmpty {
                        Text("（空：项目内会话可拖回此处）")
                            .font(.system(size: 11))
                            .foregroundStyle(HarnessTheme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .dropDestination(for: SessionDragPayload.self) { payloads, _ in
                    guard let first = payloads.first,
                          let record = sessions.first(where: { $0.id.rawValue == first.sessionID }) else { return false }
                    // P1.3：落位动画事务（与项目落点同一口径）
                    withAnimation(.smooth(duration: 0.22)) {
                        onMoveSession(record, .global)
                        targetedDrop = nil
                    }
                    return true
                } isTargeted: { targeting in
                    targetedDrop = targeting ? "global" : (targetedDrop == "global" ? nil : targetedDrop)
                }
            } else if sessions.isEmpty {
                Text("暂无对话，点击上方 ⊕ 新建")
                    .font(.system(size: 12))
                    .foregroundStyle(HarnessTheme.textTertiary)
                    .padding(.vertical, 12)
            }
        }
        // 重命名项目
        .sheet(item: $renameTarget) { project in
            VStack(spacing: 14) {
                Text("重命名项目").font(.system(size: 14, weight: .semibold))
                TextField("项目名称", text: $renameProjectName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("取消") { renameTarget = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("确定") {
                        onRenameProject(project, renameProjectName)
                        renameTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
            // P1.3：弹窗 glassEffect 补齐（P1 §1 缺口）+ materialize 出入场
            .glassSurface(.regular, cornerRadius: 12, transition: .materialize)
        }
        // 删除项目确认（二选一）
        .sheet(item: $deleteTarget) { project in
            VStack(spacing: 14) {
                Text("删除项目「\(project.name)」？").font(.system(size: 14, weight: .semibold))
                Text("项目内的会话将按所选方式处理。")
                    .font(.system(size: 12))
                    .foregroundStyle(HarnessTheme.textSecondary)
                Button {
                    onDeleteProject(project, .deleteAllSessions)
                    deleteTarget = nil
                } label: {
                    Label("删除项目及内部全部会话", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                Button {
                    onDeleteProject(project, .releaseToGlobal)
                    deleteTarget = nil
                } label: {
                    Label("删除项目，会话释放至全局", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.bordered)
                Button("取消") { deleteTarget = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .frame(width: 340)
            // P1.3：弹窗 glassEffect 补齐（P1 §1 缺口）+ materialize 出入场
            .glassSurface(.regular, cornerRadius: 12, transition: .materialize)
        }
    }

    /// 会话行（拖拽 + 归档菜单）
    private func sessionRow(_ session: SessionRecord, inProject: ProjectID?) -> some View {
        SidebarSessionRow(
            session: session,
            inProject: inProject,
            title: titleFor(session),
            isSelected: selectedSession?.id == session.id,
            isGenerating: generatingSessionId == session.id,
            onSelect: { onSelectSession(session) },
            onTogglePin: { onTogglePin(session) },
            onDelete: { onDeleteSession(session) },
            onToggleArchive: { onToggleSessionArchived(session) }
        )
    }

    /// 项目头行（展开/收起 + 计数 + 右键菜单 + 拖拽落点）
    private func projectHeader(_ section: SidebarModel.ProjectSection) -> some View {
        let project = section.project
        let isTargeted = targetedDrop == project.id.rawValue.uuidString
        return HStack(spacing: 6) {
            Button {
                // P1.3：展开/收起动画事务（项目卡玻璃面 frame 形变 + 行组显隐）
                withAnimation(.smooth(duration: 0.2)) { onToggleProjectCollapsed(project) }
            } label: {
                Image(systemName: project.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(HarnessTheme.textTertiary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(HarnessTheme.textSecondary)

            Text(project.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(HarnessTheme.textPrimary)

            Spacer()

            Text("\(section.sessions.count)")
                .font(.system(size: 10))
                .foregroundStyle(HarnessTheme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isTargeted ? HarnessTheme.accent.opacity(0.14) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        // P1.3：与 chevron 同一动画事务口径（展开/收起 frame 动画）
        .onTapGesture { withAnimation(.smooth(duration: 0.2)) { onToggleProjectCollapsed(project) } }
        .contextMenu {
            Button {
                renameTarget = project
                renameProjectName = project.name
            } label: {
                Label("重命名…", systemImage: "pencil")
            }
            Button {
                onArchiveProject(project)
            } label: {
                Label("归档项目", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                deleteTarget = project
            } label: {
                Label("删除项目…", systemImage: "trash")
            }
        }
        .dropDestination(for: SessionDragPayload.self) { payloads, _ in
            guard let first = payloads.first,
                  let record = sessions.first(where: { $0.id.rawValue == first.sessionID }) else { return false }
            // P1.3：落位动画事务（目标卡行组变更 = 玻璃形变；系统拖拽预览为快照无法挂 live 玻璃，诚实口径）
            withAnimation(.smooth(duration: 0.22)) {
                onMoveSession(record, .project(project.id))
                targetedDrop = nil
            }
            return true
        } isTargeted: { targeting in
            targetedDrop = targeting ? project.id.rawValue.uuidString : (targetedDrop == project.id.rawValue.uuidString ? nil : targetedDrop)
        }
    }

    /// P1.3：项目分区 thin 玻璃卡（C4 式逐分区独立；玻璃锚定 view bounds →
    /// 展开/收起与行插入/移除的 frame 动画 = 玻璃原生形变，无自绘模拟，铁律 4）
    private func sectionCard(_ section: SidebarModel.ProjectSection) -> some View {
        VStack(spacing: 0) {
            projectHeader(section)
            if !section.project.collapsed {
                ForEach(section.sessions) { session in
                    sessionRow(session, inProject: section.id)
                }
                if section.sessions.isEmpty {
                    Text("（空项目：拖拽会话到此）")
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 2)
        .glassSurface(.thin, cornerRadius: 8)
    }
}
