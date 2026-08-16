import SwiftUI
import Session

struct SidebarView: View {
    @Binding var selectedTab: AppTab
    @Binding var selectedSession: Session?
    let sessions: [Session]
    let onNewSession: () -> Void
    let onSelectSession: (Session) -> Void
    let onDeleteSession: (Session) -> Void
    @State private var newHover = false
    
    var body: some View {
        HStack(spacing: 0) {
            // 图标栏
            VStack(spacing: 0) {
                Button(action: onNewSession) {
                    ZStack {
                        Circle().fill(newHover ? Color.blue.opacity(0.2) : .clear).frame(width: 36, height: 36)
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(newHover ? .blue : HarnessTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain).padding(.top, 12).padding(.bottom, 8)
                .onHover { newHover = $0 }
                
                Divider().frame(height: 1).padding(.horizontal, 8)
                Spacer().frame(height: 8)
                
                ForEach(AppTab.allCases, id: \.self) { tab in
                    IconBarButton(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(.smooth) { selectedTab = tab }
                    }
                }
                
                Spacer()
                ZStack {
                    Circle().fill(HarnessTheme.surface).frame(width: 32, height: 32)
                    Text("U").font(.system(size: 13, weight: .semibold)).foregroundStyle(HarnessTheme.accent)
                }
                .padding(.bottom, 12)
            }
            .frame(width: 52)
            .background(HarnessTheme.sidebarBg)
            
            // 会话面板
            if selectedTab == .chat {
                SessionListPanel(
                    sessions: sessions, selectedSession: $selectedSession,
                    onSelect: onSelectSession, onDelete: onDeleteSession
                ).frame(width: 220)
            }
        }
    }
}

struct IconBarButton: View {
    let tab: AppTab; let isSelected: Bool; let action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.15)).frame(width: 40, height: 40)
                }
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? HarnessTheme.accent :
                        isHovered ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
            }
            .frame(height: 40)
        }
        .buttonStyle(.plain).onHover { isHovered = $0 }
    }
}

struct SessionListPanel: View {
    let sessions: [Session]
    @Binding var selectedSession: Session?
    let onSelect: (Session) -> Void
    let onDelete: (Session) -> Void
    @State private var searchText = ""
    
    var filtered: [Session] {
        searchText.isEmpty ? sessions : sessions.filter { sessionTitle($0).localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("对话").font(.system(size: 13, weight: .semibold)).foregroundStyle(HarnessTheme.textSecondary)
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 8)
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(HarnessTheme.textTertiary)
                TextField("搜索", text: $searchText).font(.system(size: 12)).textFieldStyle(.plain).disableAutocorrection(true)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(HarnessTheme.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(6).background(HarnessTheme.surface).cornerRadius(6)
            .padding(.horizontal, 8).padding(.bottom, 6)
            
            Divider().frame(height: 1)
            
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered, id: \.id) { session in
                        SessionRow(session: session, isSelected: selectedSession?.id == session.id,
                            onSelect: { onSelect(session) }, onDelete: { onDelete(session) })
                            .padding(.horizontal, 6)
                    }
                }
                .padding(.top, 4)
            }
            
            Spacer()
            HStack {
                Text("\(sessions.count) 个对话").font(.system(size: 10)).foregroundStyle(HarnessTheme.textTertiary)
                Spacer()
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
        .background(HarnessTheme.sidebarBg)
    }
    
    private func sessionTitle(_ s: Session) -> String {
        if let firstEvent = s.events.first, case .userMessage(let msg) = firstEvent,
           let firstBlock = msg.content.first, case .text(let text) = firstBlock {
            let t = String(text.prefix(25))
            return t.isEmpty ? "新对话" : t
        }
        return "新对话"
    }
}

struct SessionRow: View {
    let session: Session; let isSelected: Bool
    let onSelect: () -> Void; let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button { onSelect() } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.right").font(.system(size: 11))
                    .foregroundStyle(isSelected ? HarnessTheme.accent : HarnessTheme.textTertiary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: session)).font(.system(size: 12, design: .rounded)).lineLimit(1)
                        .foregroundStyle(isSelected ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
                    Text(date(for: session)).font(.system(size: 10)).foregroundStyle(HarnessTheme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(isSelected ? Color.blue.opacity(0.12) :
                isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain).onHover { isHovered = $0 }
        .overlay(alignment: .trailing) {
            if isHovered {
                Button { onDelete() } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                        .foregroundStyle(HarnessTheme.error).padding(4)
                }.buttonStyle(.plain).padding(.trailing, 4)
            }
        }
    }
    
    private func title(for s: Session) -> String {
        if let firstEvent = s.events.first, case .userMessage(let msg) = firstEvent,
           let firstBlock = msg.content.first, case .text(let text) = firstBlock {
            let t = String(text.prefix(25))
            return t.isEmpty ? "新对话" : t
        }
        return "新对话"
    }
    
    private func date(for s: Session) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: s.metadata.createdAt, relativeTo: Date())
    }
}
