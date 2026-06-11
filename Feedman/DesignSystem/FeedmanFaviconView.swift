import SwiftUI
import UIKit

struct FeedmanFaviconView: View {
    let faviconURL: String?
    let displayName: String?
    let size: CGFloat
    let cornerRadius: CGFloat

    init(
        faviconURL: String?,
        displayName: String?,
        size: CGFloat = 32,
        cornerRadius: CGFloat = 8
    ) {
        self.faviconURL = faviconURL
        self.displayName = displayName
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let image = FaviconDataURLDecoder.image(from: faviconURL) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LetterAvatarView(displayName: displayName)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct FaviconDataURLPayload: Equatable {
    let mimeType: String
    let data: Data
}

enum FaviconDataURLDecoder {
    static func payload(from source: String?) -> FaviconDataURLPayload? {
        guard let source else {
            return nil
        }

        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSource.hasPrefix("data:") else {
            return nil
        }

        guard let payloadSeparatorRange = trimmedSource.range(
            of: ";base64,",
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let header = String(trimmedSource[..<payloadSeparatorRange.lowerBound])
        let mimeType = String(header.dropFirst("data:".count)).lowercased()
        guard mimeType.hasPrefix("image/") else {
            return nil
        }

        let base64Payload = String(trimmedSource[payloadSeparatorRange.upperBound...])
        guard !base64Payload.isEmpty,
              let data = Data(base64Encoded: base64Payload) else {
            return nil
        }

        return FaviconDataURLPayload(mimeType: mimeType, data: data)
    }

    static func image(from source: String?) -> UIImage? {
        guard let payload = payload(from: source) else {
            return nil
        }

        return UIImage(data: payload.data)
    }
}

struct LetterAvatarView: View {
    let descriptor: LetterAvatarDescriptor

    init(displayName: String?) {
        descriptor = LetterAvatarDescriptor(displayName: displayName)
    }

    var body: some View {
        ZStack {
            descriptor.background.color

            Text(descriptor.letter)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(descriptor.foreground.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct LetterAvatarDescriptor: Equatable {
    let letter: String
    let background: FeedmanTheme.RGBAColor
    let foreground: FeedmanTheme.RGBAColor

    init(displayName: String?) {
        let normalizedName = Self.normalizedDisplayName(displayName)
        letter = Self.letter(fromNormalizedDisplayName: normalizedName)
        background = Self.backgroundColor(forNormalizedDisplayName: normalizedName)
        foreground = FeedmanTheme.RGBAColor(hex: 0xFFFFFF)
    }

    static func letter(from displayName: String?) -> String {
        letter(fromNormalizedDisplayName: normalizedDisplayName(displayName))
    }

    static func backgroundColor(for displayName: String?) -> FeedmanTheme.RGBAColor {
        backgroundColor(forNormalizedDisplayName: normalizedDisplayName(displayName))
    }

    private static let palette: [FeedmanTheme.RGBAColor] = [
        FeedmanTheme.RGBAColor(hex: 0x2563EB),
        FeedmanTheme.RGBAColor(hex: 0x059669),
        FeedmanTheme.RGBAColor(hex: 0xDC2626),
        FeedmanTheme.RGBAColor(hex: 0x7C3AED),
        FeedmanTheme.RGBAColor(hex: 0x0891B2),
        FeedmanTheme.RGBAColor(hex: 0xBE123C),
        FeedmanTheme.RGBAColor(hex: 0x4D7C0F),
        FeedmanTheme.RGBAColor(hex: 0xC2410C)
    ]

    private static func normalizedDisplayName(_ displayName: String?) -> String {
        displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func letter(fromNormalizedDisplayName displayName: String) -> String {
        guard let firstCharacter = displayName.first else {
            return "?"
        }

        return String(firstCharacter).uppercased()
    }

    private static func backgroundColor(
        forNormalizedDisplayName displayName: String
    ) -> FeedmanTheme.RGBAColor {
        let key = displayName.isEmpty ? "?" : displayName
        let index = stableIndex(for: key, count: palette.count)
        return palette[index]
    }

    private static func stableIndex(for value: String, count: Int) -> Int {
        let hash = value.unicodeScalars.reduce(UInt32(2_166_136_261)) { result, scalar in
            (result ^ scalar.value) &* 16_777_619
        }

        return Int(hash % UInt32(count))
    }
}
