import Foundation
import AVFoundation

// MARK: - Audio Processor

/// Handles audio file loading, format conversion, and PCM extraction.
/// Converts any supported audio format to 16kHz mono PCM float samples
/// as required by whisper.cpp.
final class AudioProcessor {

    // MARK: - Load Audio File

    /// Load an audio file and convert it to 16kHz mono PCM float samples.
    /// - Parameter url: URL of the audio file
    /// - Returns: Array of float samples at 16kHz, mono
    static func loadAudioAsPCMFloat(_ url: URL) throws -> (samples: [Float], duration: TimeInterval) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.fileNotFound(url.path)
        }

        let audioFile = try AVAudioFile(forReading: url)

        // Target format: 16kHz, mono, float32
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let convertFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionError.audioProcessingFailed("Failed to create conversion format")
        }

        // Read and convert
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: convertFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        ) else {
            throw TranscriptionError.audioProcessingFailed("Failed to create PCM buffer")
        }

        try audioFile.read(into: pcmBuffer)

        // If the source format doesn't match target, convert
        let sourceFormat = audioFile.processingFormat
        guard let converter = AVAudioConverter(from: sourceFormat, to: convertFormat) else {
            throw TranscriptionError.audioProcessingFailed("Failed to create audio converter from \(sourceFormat) to \(convertFormat)")
        }

        // Allocate output buffer for converted audio
        let ratio = convertFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(audioFile.length) * ratio) + 1024

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: convertFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            throw TranscriptionError.audioProcessingFailed("Failed to create output buffer")
        }

        // Perform conversion
        var error: NSError?
        var inputBuffer = pcmBuffer

        converter.convert(to: outputBuffer, error: &error) { _, status in
            status.pointee = .haveData
            return inputBuffer
        }

        if let error {
            throw TranscriptionError.audioProcessingFailed("Audio conversion failed: \(error.localizedDescription)")
        }

        // Extract float samples
        let frameLength = Int(outputBuffer.frameLength)
        let channelData = outputBuffer.floatChannelData![0]
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        let duration = Double(frameLength) / 16000.0

        Logger.info("Loaded audio: \(url.lastPathComponent), \(samples.count) samples, \(TimeFormatter.formatDuration(duration))")

        return (samples, duration)
    }

    // MARK: - Convert Float to WAV

    /// Convert float PCM samples to WAV Data for API upload.
    /// - Parameters:
    ///   - samples: Float audio samples
    ///   - sampleRate: Sample rate (default 16000)
    /// - Returns: WAV file as Data
    static func convertFloatSamplesToWAV(_ samples: [Float], sampleRate: Int = 16000) -> Data {
        let numChannels = 1
        let bitsPerSample = 16
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = numChannels * bytesPerSample
        let dataSize = samples.count * bytesPerSample
        let fileSize = 36 + dataSize

        // WAV header fields are unsigned 16/32-bit little-endian. Pre-cast the
        // 16-bit fields so they can be passed to uint16(_:) without trapping.
        let numChannelsU16 = UInt16(numChannels)
        let blockAlignU16 = UInt16(blockAlign)
        let bitsPerSampleU16 = UInt16(bitsPerSample)

        var data = Data()

        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(uint32(fileSize))
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(uint32(16)) // chunk size
        data.append(uint16(1))  // audio format = PCM
        data.append(uint16(numChannelsU16))
        data.append(uint32(sampleRate))
        data.append(uint32(sampleRate * blockAlign)) // byte rate
        data.append(uint16(blockAlignU16))
        data.append(uint16(bitsPerSampleU16))

        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(uint32(dataSize))

        // Convert float samples to 16-bit PCM.
        // intSample is a signed Int16 (range -32768...32767); for any sample
        // below the zero crossing it is negative. We must reinterpret its bit
        // pattern as UInt16 (little-endian two's-complement) — NOT convert via
        // UInt16(Int(...)), which traps on negative values. This was the cause
        // of the EXC_BREAKPOINT crash in the live-transcription path.
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * Float(Int16.max))
            data.append(uint16(UInt16(bitPattern: intSample)))
        }

        return data
    }

    // MARK: - Get Audio Duration

    /// Get the duration of an audio file without fully loading it.
    static func getAudioDuration(_ url: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return nil
        }
        let sampleRate = audioFile.processingFormat.sampleRate
        let frames = audioFile.length
        return Double(frames) / sampleRate
    }

    // MARK: - Get Audio Info

    /// Get metadata about an audio file.
    static func getAudioInfo(_ url: URL) -> (duration: TimeInterval, sampleRate: Double, channels: Int)? {
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            return nil
        }
        let format = audioFile.processingFormat
        let duration = Double(audioFile.length) / format.sampleRate
        return (duration, format.sampleRate, Int(format.channelCount))
    }

    // MARK: - Helpers

    private static func uint32(_ value: Int) -> Data {
        var v = UInt32(value)
        return Data(bytes: &v, count: 4)
    }

    /// Append a little-endian UInt16 to the WAV data.
    /// Accepts an unsigned value directly so the helper can never trap on
    /// negative inputs. All callers (audio format, channel count, block align,
    /// bits per sample, and PCM samples via `UInt16(bitPattern:)`) are unsigned.
    private static func uint16(_ value: UInt16) -> Data {
        var v = value
        return Data(bytes: &v, count: 2)
    }
}
