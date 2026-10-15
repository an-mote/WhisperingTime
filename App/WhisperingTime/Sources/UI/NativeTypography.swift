import AppKit
import SwiftUI

private struct ImprintTextScaleKey: EnvironmentKey {
    nonisolated static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// An application typography input, not macOS Dynamic Type support.
    /// The shipping default is 1. Debug QA can inject 2 to exercise real font layout.
    var imprintTextScale: CGFloat {
        get { self[ImprintTextScaleKey.self] }
        set { self[ImprintTextScaleKey.self] = newValue }
    }
}

enum NativeTypography {
    /// Keep the normal rendering path lazy, using SwiftUI's semantic font tokens.
    /// AppKit font resolution is only needed for explicit non-default scale input.
    static func semanticFont(for style: NSFont.TextStyle) -> Font {
        switch style {
        case .largeTitle: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption1: .caption
        case .caption2: .caption2
        default: .body
        }
    }

    /// Preserve the platform's semantic size, face and weight at the default scale.
    static func platformFont(for style: NSFont.TextStyle, scale: CGFloat = 1) -> NSFont {
        let preferred = NSFont.preferredFont(forTextStyle: style, options: [:])
        guard scale.isFinite, scale > 0, scale != 1 else { return preferred }
        return NSFont(descriptor: preferred.fontDescriptor, size: preferred.pointSize * scale) ?? preferred
    }
}

private struct NativeTypographyModifier: ViewModifier {
    let style: NSFont.TextStyle
    var bold = false
    var monospaced = false
    var monospacedDigits = false
    @Environment(\.imprintTextScale) private var scale

    func body(content: Content) -> some View {
        var font: Font
        if scale.isFinite, scale > 0, scale != 1 {
            font = Font(NativeTypography.platformFont(for: style, scale: scale))
        } else {
            font = NativeTypography.semanticFont(for: style)
        }
        if bold { font = font.bold() }
        if monospaced { font = font.monospaced() }
        if monospacedDigits { font = font.monospacedDigit() }
        return content.font(font)
    }
}

extension View {
    func imprintFont(
        _ style: NSFont.TextStyle,
        bold: Bool = false,
        monospaced: Bool = false,
        monospacedDigits: Bool = false
    ) -> some View {
        modifier(NativeTypographyModifier(style: style, bold: bold, monospaced: monospaced, monospacedDigits: monospacedDigits))
    }
}
