import Foundation
import AVFoundation
import ScreenCaptureKit

// MARK: - System Audio Capture

/// Captures system audio (from apps like Zoom, Meet, Teams, etc.) using ScreenCaptureKit.
/// Converts captured audio to 16kHz mono Float32 samples and delivers them in chunks
/// suitable for streaming transcription.
///
/// Requires macOS 13.0+ (ScreenCaptureKit) and user permission for screen recording.
@available(macOS 13.0, *)
final class SystemAudioCapture {

    // MARK: Types

    /// Called whenever a chunk of audio samples is ready.
    typealias ChunkHandler = (_ samples: [Float], _ timestamp: TimeInterval) -> Void

    // MARK: Properties

    private var stream: SCStream?
    private let targetSampleRate: Double = 16000
    private var converter: AVAudioConverter?
    private var accumulatedSamples: [Float] = []

    var chunkDurationSeconds: Double = 3.0
    var overlapSeconds: Double = 1.0

    private var chunkSampleCount: Int { Int(targetSampleRate * chunkDurationSeconds) }
    private var overlapSampleCount: Int { Int(targetSampleRate * overlapSeconds) }

    private(set) var isCapturing = false
    private var chunkHandler: ChunkHandler?
    private var startTime: Date?

    // MARK: Public

    /// Check if screen recording permission is available by attempting to get display content.
    static func checkPermission() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return !content.displays.isEmpty
        } catch {
            Logger.error("ScreenCaptureKit permission check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Start capturing system audio.
    /// - Parameter chunkHandler: Called with each chunk of audio samples.
    func startCapture(chunkHandler: @escaping ChunkHandler) async throws {
        guard !isCapturing else { return }

        self.chunkHandler = chunkHandler
        accumulatedSamples.removeAll()

        // Get available display content
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else {
            throw TranscriptionError.audioProcessingFailed("No display found for audio capture")
        }

        // Configure the stream filter to capture audio only
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        // Disable video capture by setting dimensions to 0 — we only need audio
        config.width = 0
        config.height = 0
        config.sampleRate = Int(targetSampleRate)
        config.channelCount = 1

        // Create stream
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        self.stream = stream

        // Add audio output stream
        try stream.addStreamOutput(
            SCStreamAudioOutput(self),
            type: SCStreamOutputType.audio,
            sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated)
        )

        // Start the stream
        try await stream.startCapture()
        isCapturing = true
        startTime = Date()
        Logger.info("SystemAudioCapture started capturing system audio")
    }

    /// Stop capturing system audio.
    func stopCapture() async {
        guard isCapturing else { return }

        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        converter = nil
        isCapturing = false

        // Flush remaining samples
        if !accumulatedSamples.isEmpty {
            let timestamp = startTime?.timeIntervalSinceNow ?? 0
            chunkHandler?(accumulatedSamples, abs(timestamp))
            accumulatedSamples.removeAll()
        }

        Logger.info("SystemAudioCapture stopped capturing")
    }

    // MARK: - Private

    fileprivate func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        // Get the audio format from the sample buffer
        let audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        // Create target format if needed
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        // Create or reuse converter
        if converter == nil || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: audioFormat, to: targetFormat)
        }

        guard let converter = converter else { return }

        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let pcmBuffer = createPCMBuffer(from: sampleBuffer, format: audioFormat) else { return }

        // Calculate output capacity
        let ratio = targetFormat.sampleRate / audioFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio) + 1024

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else { return }

        var error: NSError?
        let inputBuffer = pcmBuffer

        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, error == nil else { return }

        // Extract float samples
        let frameLength = Int(outputBuffer.frameLength)
        guard frameLength > 0,
              let channelData = outputBuffer.floatChannelData?[0] else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        // Accumulate
        accumulatedSamples.append(contentsOf: samples)

        // Emit chunks
        let chunkSize = chunkSampleCount
        while accumulatedSamples.count >= chunkSize {
            let chunk = Array(accumulatedSamples.prefix(chunkSize))
            let timestamp = startTime?.timeIntervalSinceNow ?? 0
            chunkHandler?(chunk, abs(timestamp))

            let overlap = min(overlapSampleCount, chunkSize)
            accumulatedSamples = Array(accumulatedSamples.dropFirst(chunkSize - overlap))
        }
    }

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return nil }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            return nil
        }

        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        // Copy audio data from CMSampleBuffer
        var blockBuffer: CMBlockBuffer?
        let bufferListSize = MemoryLayout<AudioBufferList>.size
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: pcmBuffer.mutableAudioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        return pcmBuffer
    }
}

// MARK: - SCStreamAudioOutput

@available(macOS 13.0, *)
private final class SCStreamAudioOutput: NSObject, SCStreamOutput {
    private weak var capture: SystemAudioCapture?

    init(_ capture: SystemAudioCapture) {
        self.capture = capture
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        capture?.processAudioSample(sampleBuffer)
    }
}
