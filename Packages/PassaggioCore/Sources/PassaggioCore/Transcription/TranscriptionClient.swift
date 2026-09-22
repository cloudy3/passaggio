import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A short clip of a known voice, sent with every request so labels stay stable
/// ("teacher" and "me") across chunks and lessons.
public struct SpeakerReferenceClip: Sendable {
    public var name: String
    /// Audio bytes (2–10 s per the API docs).
    public var audio: Data
    public var mimeType: String

    public init(name: String, audio: Data, mimeType: String = "audio/wav") {
        self.name = name
        self.audio = audio
        self.mimeType = mimeType
    }

    public var dataURL: String {
        "data:\(mimeType);base64,\(audio.base64EncodedString())"
    }

    public static let allowedDuration: ClosedRange<TimeInterval> = 2...10
    public static let maximumCount = 4
}

/// `POST /v1/audio/transcriptions` with `gpt-4o-transcribe-diarize`.
public struct OpenAITranscriptionClient: Sendable {
    public static let model = "gpt-4o-transcribe-diarize"
    public static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    public var apiKey: String
    public var http: any HTTPClient

    public init(apiKey: String, http: any HTTPClient) {
        self.apiKey = apiKey
        self.http = http
    }

    public func makeRequest(
        audio: Data,
        filename: String,
        mimeType: String = "audio/mp4",
        references: [SpeakerReferenceClip],
        boundary: String = "passaggio-\(UUID().uuidString)"
    ) -> URLRequest {
        var form = MultipartFormData(boundary: boundary)
        form.addField("model", Self.model)
        form.addField("response_format", "diarized_json")
        // Required for inputs over 30 s; harmless for shorter ones.
        form.addField("chunking_strategy", "auto")
        for reference in references.prefix(SpeakerReferenceClip.maximumCount) {
            form.addField("known_speaker_names[]", reference.name)
            form.addField("known_speaker_references[]", reference.dataURL)
        }
        form.addFile("file", filename: filename, mimeType: mimeType, data: audio)

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()
        return request
    }

    public func transcribe(audio: Data, filename: String, references: [SpeakerReferenceClip]) async throws -> DiarizedTranscription {
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey(provider: "OpenAI") }
        let request = makeRequest(audio: audio, filename: filename, references: references)
        let data = try await http.sendChecked(request)
        do {
            return try DiarizedTranscription.decode(data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
