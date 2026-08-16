import SwiftUI
import Session

struct SessionSidebarView: View {
    let sessions: [Session]
    @Binding var selectedSession: Session?
    let onNewSession: () -> Void
    @State private var searchText = ""
    
    var filteredSessions: [Session] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter { session in
            let title = sessionTitle(for: session)
            return title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with new session button
            HStack {
                Text("会话")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(HarnessTheme.textPrimary)
                
                Spacer()
                
                Button {
                    onNewSession()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(IconButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HarnessTheme.textTertiary)
                    .font(.system(size: 12))
                
                TextField("Search sessions...", text: $searchText)
                    .font(.system(.body, design: .rounded))
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(HarnessTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(HarnessTheme.surface)
            .cornerRadius(HarnessTheme.radiusMedium)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            
            // Session list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredSessions) { session in
                        SessionRowView(
                            session: session,
                            isSelected: selectedSession?.id == session.id
                        ) {
                            withAnimation(.smooth) {
                                selectedSession = session
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.top, 4)
            }
            
            // Footer
            Divider()
            
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(HarnessTheme.textTertiary)
                Text("\(sessions.count) 个对话")
                    .font(.system(size: 11))
                    .foregroundStyle(HarnessTheme.textTertiary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(HarnessTheme.sidebarBg)
    }
    
    private func sessionTitle(for session: Session) -> String {
        if let firstEvent = session.events.first {
            switch firstEvent {
            case .userMessage(let msg):
                if let firstBlock = msg.content.first {
                    switch firstBlock {
                    case .text(let text):
                        return String(text.prefix(30))
                    default: break
                    }
                }
            default: break
            }
        }
        return "对话 \(session.currentTurn + 1)"
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: Session
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? HarnessTheme.accent : HarnessTheme.textTertiary)
                    
                    Text(sessionTitle(for: session))
                        .font(.system(.body, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? HarnessTheme.textPrimary : HarnessTheme.textSecondary)
                    
                    Spacer()
                    
                    Text(sessionDate(for: session))
                        .font(.system(size: 11))
                        .foregroundStyle(HarnessTheme.textTertiary)
                }
                
                Text(sessionPreview(for: session))
                    .font(.system(size: 11))
                    .foregroundStyle(HarnessTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(isSelected ? HarnessTheme.sidebarSelected : 
                        isHovered ? HarnessTheme.sidebarHover : .clear)
            .cornerRadius(HarnessTheme.radiusMedium)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func sessionTitle(for session: Session) -> String {
        if let firstEvent = session.events.first {
            switch firstEvent {
            case .userMessage(let msg):
                if let firstBlock = msg.content.first {
                    switch firstBlock {
                    case .text(let text):
                        return String(text.prefix(30))
                    default: break
                    }
                }
            default: break
            }
        }
        return "对话 \(session.currentTurn + 1)"
    }
    
    private func sessionDate(for session: Session) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.metadata.createdAt, relativeTo: Date())
    }
    
    private func sessionPreview(for session: Session) -> String {
        if let lastEvent = session.events.last {
            switch lastEvent {
            case .assistantMessage(let msg):
                if let firstBlock = msg.content.first {
                    switch firstBlock {
                    case .text(let text):
                        return String(text.prefix(40))
                    default: break
                    }
                }
            default: break
            }
        }
        return "暂无消息"
    }
}

#Preview {
    SessionSidebarView(
        sessions: [],
        selectedSession: .constant(nil),
        onNewSession: {}
    )
}
