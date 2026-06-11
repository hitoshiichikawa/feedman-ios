import SwiftUI
import UIKit

enum FeedmanTheme {
    struct Tokens {
        let background: Color
        let surface: Color
        let surfaceSecondary: Color
        let foreground: Color
        let muted: Color
        let mutedForeground: Color
        let border: Color
        let borderStrong: Color
        let accent: Color
        let accentOn: Color
        let accentSoft: Color
        let star: Color
        let danger: Color
        let scrim: Color
        let usesDarkChrome: Bool
    }

    struct ResolvedTokens: Equatable {
        let background: RGBAColor
        let surface: RGBAColor
        let surfaceSecondary: RGBAColor
        let foreground: RGBAColor
        let muted: RGBAColor
        let mutedForeground: RGBAColor
        let border: RGBAColor
        let borderStrong: RGBAColor
        let accent: RGBAColor
        let accentOn: RGBAColor
        let accentSoft: RGBAColor
        let star: RGBAColor
        let danger: RGBAColor
        let scrim: RGBAColor
        let usesDarkChrome: Bool

        var colors: Tokens {
            Tokens(
                background: background.color,
                surface: surface.color,
                surfaceSecondary: surfaceSecondary.color,
                foreground: foreground.color,
                muted: muted.color,
                mutedForeground: mutedForeground.color,
                border: border.color,
                borderStrong: borderStrong.color,
                accent: accent.color,
                accentOn: accentOn.color,
                accentSoft: accentSoft.color,
                star: star.color,
                danger: danger.color,
                scrim: scrim.color,
                usesDarkChrome: usesDarkChrome
            )
        }
    }

    struct RGBAColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double

        init(hex: Int, opacity: Double = 1) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
            self.opacity = opacity
        }

        var color: Color {
            Color(red: red, green: green, blue: blue, opacity: opacity)
        }

        var uiColor: UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: opacity)
        }

        var hexString: String {
            String(
                format: "#%02X%02X%02X",
                Int((red * 255).rounded()),
                Int((green * 255).rounded()),
                Int((blue * 255).rounded())
            )
        }
    }

    static let lightTokens = ResolvedTokens(
        background: RGBAColor(hex: 0xFAFAFA),
        surface: RGBAColor(hex: 0xFFFFFF),
        surfaceSecondary: RGBAColor(hex: 0xF7F7F7),
        foreground: RGBAColor(hex: 0x171717),
        muted: RGBAColor(hex: 0xF5F5F5),
        mutedForeground: RGBAColor(hex: 0x737373),
        border: RGBAColor(hex: 0xE5E5E5),
        borderStrong: RGBAColor(hex: 0xD4D4D4),
        accent: RGBAColor(hex: 0x4F46E5),
        accentOn: RGBAColor(hex: 0xFFFFFF),
        accentSoft: RGBAColor(hex: 0xE6EAFF),
        star: RGBAColor(hex: 0xE7AD01),
        danger: RGBAColor(hex: 0xE7000F),
        scrim: RGBAColor(hex: 0x000000, opacity: 0.32),
        usesDarkChrome: false
    )

    static let darkTokens = ResolvedTokens(
        background: RGBAColor(hex: 0x0A0A0A),
        surface: RGBAColor(hex: 0x171717),
        surfaceSecondary: RGBAColor(hex: 0x1E1E1E),
        foreground: RGBAColor(hex: 0xFAFAFA),
        muted: RGBAColor(hex: 0x262626),
        mutedForeground: RGBAColor(hex: 0xA1A1A1),
        border: RGBAColor(hex: 0xFFFFFF, opacity: 0.12),
        borderStrong: RGBAColor(hex: 0xFFFFFF, opacity: 0.20),
        accent: RGBAColor(hex: 0x6895F4),
        accentOn: RGBAColor(hex: 0xFFFFFF),
        accentSoft: RGBAColor(hex: 0x6895F4, opacity: 0.18),
        star: RGBAColor(hex: 0xF5BA26),
        danger: RGBAColor(hex: 0xFF6468),
        scrim: RGBAColor(hex: 0x000000, opacity: 0.60),
        usesDarkChrome: true
    )

    static func resolvedTokens(for colorScheme: ColorScheme) -> ResolvedTokens {
        colorScheme == .dark ? darkTokens : lightTokens
    }

    static func tokens(for colorScheme: ColorScheme) -> Tokens {
        resolvedTokens(for: colorScheme).colors
    }

    static let background = dynamicColor(\.background)
    static let surface = dynamicColor(\.surface)
    static let surfaceSecondary = dynamicColor(\.surfaceSecondary)
    static let foreground = dynamicColor(\.foreground)
    static let muted = dynamicColor(\.muted)
    static let mutedForeground = dynamicColor(\.mutedForeground)
    static let border = dynamicColor(\.border)
    static let borderStrong = dynamicColor(\.borderStrong)
    static let accent = dynamicColor(\.accent)
    static let accentOn = dynamicColor(\.accentOn)
    static let accentSoft = dynamicColor(\.accentSoft)
    static let star = dynamicColor(\.star)
    static let danger = dynamicColor(\.danger)
    static let scrim = dynamicColor(\.scrim)
    static let mutedText = mutedForeground

    private static func dynamicColor(_ keyPath: KeyPath<ResolvedTokens, RGBAColor>) -> Color {
        Color(uiColor: UIColor { traitCollection in
            let tokens = traitCollection.userInterfaceStyle == .dark ? darkTokens : lightTokens
            return tokens[keyPath: keyPath].uiColor
        })
    }
}
