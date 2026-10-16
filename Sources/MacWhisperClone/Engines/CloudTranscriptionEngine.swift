import Foundation

// MARK: - Cloud Transcription Engine

/// Base class for cloud-based transcription engines that send audio to a remote API.
/// Subclasses configure the specific endpoint, headers, and response parsing.
class CloudTranscriptionEngine: TranscriptionEngine {

    let engineType: TranscriptionEngineType
    let apiEndpoint: URL
    let apiKey: String?

    private var currentTask: URLSessionDataTask?
    private var isCancelled = false

    var isReady: Bool {
        apiKey != nil && !apiKey!.isEmpty
    }

    init(engineType: TranscriptionEngineType, apiEndpoint: URL, apiKey: String?) {
        self.engineType = engineType
        self.apiEndpoint = apiEndpoint
        self.apiKey = apiKey
    }

    func prepare() async throws {
        guard isReady else {
            throw TranscriptionError.invalidAPIKey
        }
    }

    func transcribe(
        audioData: [Float],
        settings: TranscriptionSettings,
        progressHandler: @escaping (Double, [TranscriptionSegment]?) -> Void,
        completion: @escaping (Result<TranscriptionResult, TranscriptionError>) -> Void
    ) {
        isCancelled = false

        guard isReady else {
            completion(.failure(.invalidAPIKey))
            return
        }

        // Convert float samples back to WAV data for API upload
        let wavData = AudioProcessor.convertFloatSamplesToWAV(audioData, sampleRate: 16000)

        let startTime = Date()

        // Build multipart form request
        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey!)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // Audio file part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // Model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)

        // Language
        if let language = settings.language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }

        // Timestamp granularities
        if settings.wordTimestamps {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"timestamp_granularities[]\"\r\n\r\n".data(using: .utf8)!)
            body.append("segment\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"timestamp_granularities[]\"\r\n\r\n".data(using: .utf8)!)
            body.append("word\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if self.isCancelled {
                completion(.failure(.cancelled))
                return
            }

            if let error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.apiError("Invalid response")))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                completion(.failure(.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")))
                return
            }

            guard let data else {
                completion(.failure(.apiError("No response data")))
                return
            }

            // Parse the verbose JSON response
            do {
                let result = try self.parseVerboseJSONResponse(
                    data: data,
                    processingTime: Date().timeIntervalSince(startTime),
                    audioDuration: Double(audioData.count) / 16000.0
                )
                DispatchQueue.main.async {
                    progressHandler(1.0, result.segments)
                    completion(.success(result))
                }
            } catch {
                completion(.failure(.apiError("Failed to parse response: \(error.localizedDescription)")))
            }
        }

        currentTask = task
        task.resume()

        // Simulate progress while waiting
        DispatchQueue.global(qos: .utility).async {
            var p: Double = 0
            while !self.isCancelled && p < 0.9 && task.state == .running {
                Thread.sleep(forTimeInterval: 0.5)
                p = min(p + 0.05, 0.9)
                DispatchQueue.main.async {
                    progressHandler(p, nil)
                }
            }
        }
    }

    func cancel() {
        isCancelled = true
        currentTask?.cancel()
    }

    // MARK: - Response Parsing

    /// Parse OpenAI-compatible verbose JSON response.
    private func parseVerboseJSONResponse(
        data: Data,
        processingTime: TimeInterval,
        audioDuration: TimeInterval
    ) throws -> TranscriptionResult {
        struct VerboseJSONResponse: Decodable {
            let text: String
            let language: String?
            let duration: Double?
            let segments: [Segment]?
            let words: [Word]?

            struct Segment: Decodable {
                let id: Int
                let start: Double
                let end: Double
                let text: String
            }

            struct Word: Decodable {
                let word: String
                let start: Double
                let end: Double
                let probability: Double?
            }
        }

        let response = try JSONDecoder().decode(VerboseJSONResponse.self, from: data)

        let segments: [TranscriptionSegment] = (response.segments ?? []).map { seg in
            TranscriptionSegment(
                index: seg.id,
                startTime: seg.start,
                endTime: seg.end,
                text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return TranscriptionResult(
            segments: segments,
            detectedLanguage: response.language ?? "unknown",
            modelUsed: "whisper-1",
            engineUsed: engineType,
            processingTime: processingTime,
            audioDuration: response.duration ?? audioDuration
        )
    }
}

// MARK: - OpenAI Whisper Engine

/// OpenAI Whisper API transcription engine.
final class OpenAIWhisperEngine: CloudTranscriptionEngine {
    init(apiKey: String) {
        super.init(
            engineType: .openAI,
            apiEndpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            apiKey: apiKey
        )
    }
}

// MARK: - Groq Whisper Engine

/// Groq Whisper API transcription engine.
final class GroqWhisperEngine: CloudTranscriptionEngine {
    init(apiKey: String) {
        super.init(
            engineType: .groq,
            apiEndpoint: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
            apiKey: apiKey
        )
    }
}

// MARK: - OpenAI-Compatible Engine

/// Generic OpenAI-compatible Whisper API engine for custom endpoints.
final class OpenAICompatibleEngine: CloudTranscriptionEngine {
    init(endpoint: URL, apiKey: String) {
        super.init(
            engineType: .openAI,
            apiEndpoint: endpoint,
            apiKey: apiKey
        )
    }
}
