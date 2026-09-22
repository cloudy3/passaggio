import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal transport so API clients can be tested against recorded responses.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPClient {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, http)
    }
}

public enum APIError: Error, LocalizedError, Equatable {
    case missingAPIKey(provider: String)
    case invalidResponse
    case http(status: Int, message: String)
    case refused(String)
    case truncated
    case emptyOutput
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "Add your \(provider) API key in Settings."
        case .invalidResponse:
            "The server sent a response the app couldn't read."
        case let .http(status, message):
            switch status {
            case 401: "The API key was rejected (401). Check it in Settings. \(message)"
            case 429: "Rate limited or out of credit (429). \(message)"
            default: "Request failed with status \(status). \(message)"
            }
        case .refused(let reason):
            "The model declined the request. \(reason)"
        case .truncated:
            "The response was cut off before it finished."
        case .emptyOutput:
            "The model returned no output."
        case .decoding(let detail):
            "Couldn't read the model's response: \(detail)"
        }
    }

    /// Worth retrying after a pause: rate limits, overload and server errors.
    public var isTransient: Bool {
        if case let .http(status, _) = self {
            return status == 408 || status == 409 || status == 429 || status >= 500
        }
        return false
    }

    /// Pulls the human-readable message out of an OpenAI- or Anthropic-style error body.
    static func fromResponse(status: Int, body: Data) -> APIError {
        struct Envelope: Decodable {
            struct Inner: Decodable { var message: String? }
            var error: Inner?
        }
        let message = (try? JSONDecoder().decode(Envelope.self, from: body))?.error?.message
            ?? String(decoding: body.prefix(300), as: UTF8.self)
        return .http(status: status, message: message)
    }
}

extension HTTPClient {
    /// Sends and retries transient failures with exponential backoff.
    func sendChecked(_ request: URLRequest, attempts: Int = 3) async throws -> Data {
        var delay: UInt64 = 1_000_000_000
        for attempt in 1...attempts {
            let (data, response) = try await send(request)
            if (200..<300).contains(response.statusCode) {
                return data
            }
            let error = APIError.fromResponse(status: response.statusCode, body: data)
            guard error.isTransient, attempt < attempts else { throw error }
            try await Task.sleep(nanoseconds: delay)
            delay *= 2
        }
        throw APIError.invalidResponse
    }
}

/// Builds `multipart/form-data` bodies. Array fields repeat the same name, which is
/// how the transcription endpoint expects `known_speaker_names[]`.
public struct MultipartFormData: Sendable {
    public let boundary: String
    private(set) var body = Data()

    public init(boundary: String = "passaggio-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append(value)
        body.append("\r\n")
    }

    public mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    public func finalized() -> Data {
        var result = body
        result.append("--\(boundary)--\r\n")
        return result
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
