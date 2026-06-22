import Foundation

protocol KeywordRepository {
    func keywords(accessToken: String) async throws -> [KeywordResponse]
    func createKeyword(_ request: KeywordCreateRequest, accessToken: String) async throws -> KeywordResponse
    func updateKeyword(
        id: String,
        request: KeywordUpdateRequest,
        accessToken: String
    ) async throws -> KeywordResponse
    func deleteKeyword(id: String, accessToken: String) async throws
}

struct APIClientKeywordRepository: KeywordRepository {
    let apiClient: APIClient

    func keywords(accessToken: String) async throws -> [KeywordResponse] {
        let response = try await apiClient.send(
            KeywordListResponse.self,
            path: "/api/keywords",
            accessToken: accessToken
        )
        return response.items
    }

    func createKeyword(_ request: KeywordCreateRequest, accessToken: String) async throws -> KeywordResponse {
        try await apiClient.send(
            KeywordResponse.self,
            method: .post,
            path: "/api/keywords",
            body: request,
            accessToken: accessToken
        )
    }

    func updateKeyword(
        id: String,
        request: KeywordUpdateRequest,
        accessToken: String
    ) async throws -> KeywordResponse {
        try await apiClient.send(
            KeywordResponse.self,
            method: .patch,
            path: "/api/keywords/\(id)",
            body: request,
            accessToken: accessToken
        )
    }

    func deleteKeyword(id: String, accessToken: String) async throws {
        try await apiClient.sendNoContent(
            method: .delete,
            path: "/api/keywords/\(id)",
            accessToken: accessToken
        )
    }
}

struct MockKeywordOperation: Equatable {
    enum Kind: Equatable {
        case list
        case create(KeywordCreateRequest)
        case update(id: String, request: KeywordUpdateRequest)
        case delete(id: String)
    }

    let kind: Kind
}

enum MockKeywordRepositoryError: Error, Equatable {
    case keywordNotFound(id: String)
}

final class MockKeywordRepository: KeywordRepository {
    private(set) var storedKeywords: [KeywordResponse]
    private(set) var recordedOperations: [MockKeywordOperation] = []

    var listFailure: Error?
    var createFailure: Error?
    var updateFailure: Error?
    var deleteFailure: Error?

    init(
        keywords: [KeywordResponse] = [
            KeywordResponse(id: "keyword-1", term: "SwiftUI", scope: "title", enabled: true, hits: 4),
            KeywordResponse(id: "keyword-2", term: "RSS", scope: "title", enabled: false, hits: 1)
        ],
        listFailure: Error? = nil,
        createFailure: Error? = nil,
        updateFailure: Error? = nil,
        deleteFailure: Error? = nil
    ) {
        self.storedKeywords = keywords
        self.listFailure = listFailure
        self.createFailure = createFailure
        self.updateFailure = updateFailure
        self.deleteFailure = deleteFailure
    }

    func keywords(accessToken: String) async throws -> [KeywordResponse] {
        recordedOperations.append(MockKeywordOperation(kind: .list))
        if let listFailure {
            throw listFailure
        }
        return storedKeywords
    }

    func createKeyword(_ request: KeywordCreateRequest, accessToken: String) async throws -> KeywordResponse {
        recordedOperations.append(MockKeywordOperation(kind: .create(request)))
        if let createFailure {
            throw createFailure
        }

        let keyword = KeywordResponse(
            id: nextKeywordID(),
            term: request.term,
            scope: request.scope,
            enabled: request.enabled,
            hits: 0
        )
        storedKeywords.append(keyword)
        return keyword
    }

    func updateKeyword(
        id: String,
        request: KeywordUpdateRequest,
        accessToken: String
    ) async throws -> KeywordResponse {
        recordedOperations.append(MockKeywordOperation(kind: .update(id: id, request: request)))
        if let updateFailure {
            throw updateFailure
        }

        guard let index = storedKeywords.firstIndex(where: { $0.id == id }) else {
            throw MockKeywordRepositoryError.keywordNotFound(id: id)
        }

        let current = storedKeywords[index]
        let updated = KeywordResponse(
            id: current.id,
            term: request.term ?? current.term,
            scope: current.scope,
            enabled: request.enabled ?? current.enabled,
            hits: current.hits
        )
        storedKeywords[index] = updated
        return updated
    }

    func deleteKeyword(id: String, accessToken: String) async throws {
        recordedOperations.append(MockKeywordOperation(kind: .delete(id: id)))
        if let deleteFailure {
            throw deleteFailure
        }

        guard let index = storedKeywords.firstIndex(where: { $0.id == id }) else {
            throw MockKeywordRepositoryError.keywordNotFound(id: id)
        }
        storedKeywords.remove(at: index)
    }

    private func nextKeywordID() -> String {
        var candidate = storedKeywords.count + 1
        while storedKeywords.contains(where: { $0.id == "keyword-\(candidate)" }) {
            candidate += 1
        }
        return "keyword-\(candidate)"
    }
}

private struct KeywordListResponse: Decodable {
    let items: [KeywordResponse]

    init(from decoder: Decoder) throws {
        if let items = try? [KeywordResponse](from: decoder) {
            self.items = items
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try container.decodeIfPresent([KeywordResponse].self, forKey: .items) {
            self.items = items
            return
        }
        self.items = try container.decode([KeywordResponse].self, forKey: .keywords)
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case keywords
    }
}
