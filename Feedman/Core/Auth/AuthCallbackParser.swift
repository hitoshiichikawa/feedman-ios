import Foundation

enum AuthCallbackParserError: Error, Equatable {
    case invalidScheme
    case invalidPath
    case missingAuthCode
}

enum AuthCallbackParser {
    static func authCode(from url: URL) throws -> String {
        guard url.scheme?.lowercased() == "feedman" else {
            throw AuthCallbackParserError.invalidScheme
        }

        guard url.host?.lowercased() == "auth", url.path == "/callback" else {
            throw AuthCallbackParserError.invalidPath
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let authCode = components?.queryItems?
            .first { $0.name == "auth_code" }?
            .value

        guard let authCode, !authCode.isEmpty else {
            throw AuthCallbackParserError.missingAuthCode
        }

        return authCode
    }
}
