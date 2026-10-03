import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PassaggioCore

enum Fixture {
    static func data(_ name: String, extension ext: String = "json") throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
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

/// Like `StubLLM`, but also records every request, so tests can check exactly what
/// the model would be sent.
final class RecordingLLM: LLMProvider, @unchecked Sendable {
    struct Request {
        var system: String
        var user: String
        var output: StructuredOutput

        /// System prompt, user prompt and schema as one comparable text.
        func transcript() throws -> String {
            let schema = String(decoding: try output.schema.encoded(), as: UTF8.self)
            return "SYSTEM:\n\(system)\n\nUSER:\n\(user)\n\nSCHEMA \(output.name):\n\(schema)\n"
        }
    }

    private let lock = NSLock()
    private let reply: Data
    private(set) var requests: [Request] = []
    var displayName: String { "Recording" }

    init(reply: String) {
        self.reply = Data(reply.utf8)
    }

    func generateJSON(system: String, user: String, output: StructuredOutput) async throws -> Data {
        lock.withLock { requests.append(Request(system: system, user: user, output: output)) }
        return reply
    }
}

func segment(_ start: Double, _ end: Double, _ speaker: String = "teacher", _ text: String = "text") -> DiarizedTranscription.Segment {
    .init(speaker: speaker, start: start, end: end, text: text)
}
