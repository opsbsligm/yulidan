import SwiftUI

/// Harness Design System — colors, modifiers, and Liquid Glass effects
struct HarnessTheme {
    // MARK: - Colors (auto-adapt to dark/light)
    
    static var bgPrimary: Color {
        Color(NSColor.windowBackgroundColor)
    }
    
    static var bgSecondary: Color {
        Color(NSColor.controlBackgroundColor)
    }
    
    static var surface: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.8)
    }
    
    static var surfaceHover: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.95)
    }
    
    static var accent: Color {
        Color.blue
    }
    
    static var textPrimary: Color {
        Color(NSColor.labelColor)
    }
    
    static var textSecondary: Color {
        Color(NSColor.secondaryLabelColor)
    }
    
    static var textTertiary: Color {
        Color(NSColor.tertiaryLabelColor)
    }
    
    static var border: Color {
        Color(NSColor.separatorColor)
    }
    
    static var userMessage: Color {
        Color.blue.opacity(0.12)
    }
    
    static var assistantMessage: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.3)
    }
    
    static var success: Color { Color.green }
    static var warning: Color { Color.orange }
    static var error: Color { Color.red }
    
    static var sidebarBg: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.6)
    }
    
    static var sidebarHover: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.9)
    }

    static var sidebarSelected: Color {
        Color(NSColor.selectedContentBackgroundColor)
    }
    
    // MARK: - Liquid Glass Materials
    static var glassLight: Color {
        Color(NSColor.windowBackgroundColor).opacity(0.75)
    }
    
    static var glassMedium: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.65)
    }
    
    static var glassDark: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.85)
    }
    
    // MARK: - Corners
    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 12
    static let radiusXLarge: CGFloat = 16
}

// MARK: - Modifiers

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(HarnessTheme.surface)
            .cornerRadius(HarnessTheme.radiusLarge)
            .overlay(
                RoundedRectangle(cornerRadius: HarnessTheme.radiusLarge)
                    .stroke(HarnessTheme.border, lineWidth: 0.5)
            )
    }
}

struct MessageBubbleModifier: ViewModifier {
    var isUser: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isUser ? HarnessTheme.userMessage : HarnessTheme.assistantMessage)
            .cornerRadius(HarnessTheme.radiusLarge)
            .overlay(
                RoundedRectangle(cornerRadius: HarnessTheme.radiusLarge)
                    .stroke(isUser ? HarnessTheme.accent.opacity(0.3) : HarnessTheme.border, lineWidth: 0.5)
            )
    }
}

/// Liquid Glass effect — applies NSVisualEffectView material
struct LiquidGlassModifier: ViewModifier {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func body(content: Content) -> some View {
        content
            .background(
                VisualEffectMaterial(material: material, blendingMode: blendingMode)
            )
    }
}

/// SwiftUI wrapper for NSVisualEffectView
struct VisualEffectMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - View Extensions

extension View {
    func harnessCard() -> some View { modifier(CardModifier()) }
    func messageBubble(isUser: Bool) -> some View { modifier(MessageBubbleModifier(isUser: isUser)) }
    
    // Liquid Glass effects
    func liquidGlassLight() -> some View {
        modifier(LiquidGlassModifier(material: .hudWindow))
    }
    func liquidGlassMedium() -> some View {
        modifier(LiquidGlassModifier(material: .popover))
    }
    func liquidGlassDark() -> some View {
        modifier(LiquidGlassModifier(material: .sidebar))
    }
}

// MARK: - Button Styles

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(configuration.isPressed ? Color.secondary.opacity(0.1) : .clear)
            .cornerRadius(HarnessTheme.radiusSmall)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tintColor: Color = HarnessTheme.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(tintColor)
            .cornerRadius(HarnessTheme.radiusMedium)
    }
}
