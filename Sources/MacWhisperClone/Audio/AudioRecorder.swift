import Foundation
import AVFoundation

// MARK: - Audio Recorder

/// Captures audio from the microphone in real-time using AVAudioEngine.
/// Converts incoming audio to 16kHz mono Float32 samples and delivers
/// them in chunks suitable for streaming transcription.
final class AudioRecorder {

    // MARK: Types

    /// Called whenever a chunk of audio samples is ready.
    /// - Parameters:
    ///   - samples: Float32 PCM samples at 16kHz, mono
    ///   - timestamp: The presentation timestamp of the first sample
    typealias ChunkHandler = (_ samples: [Float], _ timestamp: TimeInterval) -> Void

    // MARK: Properties

    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16000
    private var converter: AVAudioConverter?
    private var inputNode: AVAudioInputNode?

    /// The chunk duration in seconds. Smaller = lower latency but more overhead.
    var chunkDurationSeconds: Double = 3.0

    /// Overlap between consecutive chunks (seconds). Helps Whisper maintain context.
    var overlapSeconds: Double = 1.0

    private var accumulatedSamples: [Float] = []
    private var chunkSampleCount: Int { Int(targetSampleRate * chunkDurationSeconds) }
    private var overlapSampleCount: Int { Int(targetSampleRate * overlapSeconds) }

    private(set) var isRecording = false
    private var startTime: Date?
    private var chunkHandler: ChunkHandler?

    // MARK: Public

    /// Request microphone permission.
    /// On macOS 14+, uses AVAudioApplication. On older macOS, the system
    /// automatically prompts via TCC when the audio engine accesses the mic.
    static func requestPermission() async -> Bool {
        if #available(macOS 14.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            // macOS 13: TCC handles microphone permission automatically
            // when AVAudioEngine accesses the input node.
            return true
        }
    }

    /// Start recording from the microphone.
    /// - Parameter chunkHandler: Called with each chunk of audio samples.
    func startRecording(chunkHandler: @escaping ChunkHandler) throws {
        guard !isRecording else { return }

        self.chunkHandler = chunkHandler
        accumulatedSamples.removeAll()

        let inputNode = engine.inputNode
        self.inputNode = inputNode

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create target format: 16kHz, mono, float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionError.audioProcessingFailed("Failed to create target audio format")
        }

        // Create converter from input format to target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw TranscriptionError.audioProcessingFailed("Failed to create audio converter from \(inputFormat) to \(targetFormat)")
        }
        self.converter = converter

        // Install tap on input node
        let bufferSize = AVAudioFrameCount(targetFormat.sampleRate * 0.5) // 500ms buffer

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processInputBuffer(buffer, time: time)
        }

        engine.prepare()

        do {
            try engine.start()
            isRecording = true
            startTime = Date()
            Logger.info("AudioRecorder started recording (input: \(inputFormat.sampleRate)Hz, target: \(targetSampleRate)Hz)")
        } catch {
            inputNode.removeTap(onBus: 0)
            throw TranscriptionError.audioProcessingFailed("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    /// Stop recording.
    func stopRecording() {
        guard isRecording else { return }

        engine.stop()
        inputNode?.removeTap(onBus: 0)
        converter = nil
        isRecording = false

        // Flush any remaining samples
        if !accumulatedSamples.isEmpty {
            let timestamp = startTime.map { Date().timeIntervalSince($0) } ?? 0
            chunkHandler?(accumulatedSamples, timestamp)
            accumulatedSamples.removeAll()
        }

        Logger.info("AudioRecorder stopped recording")
    }

    // MARK: - Private

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let converter = converter else { return }

        // Calculate output frame capacity based on sample rate ratio
        let inputFormat = buffer.format
        let ratio = targetSampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            )!,
            frameCapacity: outputCapacity
        ) else { return }

        var error: NSError?
        let inputBuffer = buffer

        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, error == nil else {
            Logger.error("Audio conversion error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        // Extract float samples
        let frameLength = Int(outputBuffer.frameLength)
        guard frameLength > 0,
              let channelData = outputBuffer.floatChannelData?[0] else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        // Accumulate samples
        accumulatedSamples.append(contentsOf: samples)

        // Check if we have enough for a chunk
        let chunkSize = chunkSampleCount
        while accumulatedSamples.count >= chunkSize {
            // Extract chunk
            let chunk = Array(accumulatedSamples.prefix(chunkSize))

            // Calculate timestamp (elapsed seconds since recording started)
            let timestamp = startTime.map {
                Date().timeIntervalSince($0)
            } ?? 0

            chunkHandler?(chunk, timestamp)

            // Keep overlap for next chunk
            let overlap = min(overlapSampleCount, chunkSize)
            accumulatedSamples = Array(accumulatedSamples.dropFirst(chunkSize - overlap))
        }
    }
}
