import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PassaggioCore

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return try Data(contentsOf: url)
    }
}

/// Replays canned responses and records the requests it was given.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, Data)]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(status: Int, body: Data)]) {
        self.responses = responses.map { ($0.status, $0.body) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body): (Int, Data) = lock.withLock {
            requests.append(request)
            return responses.isEmpty ? (500, Data()) : responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }
}

/// An LLM provider that returns fixed JSON, for testing the analyst end to end.
struct StubLLM: LLMProvider {
    var reply: Data
    var displayName: String { "Stub" }
    func generateJSON(system: String, user: String, output: StructuredOutput) async throws -> Data { reply }
}

func segment(_ start: Double, _ end: Double, _ speaker: String = "teacher", _ text: String = "text") -> DiarizedTranscription.Segment {
    .init(speaker: speaker, start: start, end: end, text: text)
}
