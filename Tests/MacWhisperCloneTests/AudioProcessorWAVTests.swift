import XCTest
@testable import MacWhisperClone

/// Regression tests for AudioProcessor.convertFloatSamplesToWAV.
///
/// Bug: calling `uint16(Int(...))` with a negative Int16 sample value triggered
/// a Swift runtime trap (EXC_BREAKPOINT / SIGTRAP) because `UInt16(negative)`
/// is an overflow. This reproduces the crash from the live-transcription path
/// where ~half of all PCM samples are negative (anything below the zero crossing).
final class AudioProcessorWAVTests: XCTestCase {

    /// The exact symptom from the crash report: a single negative float sample
    /// must not crash when converted to WAV. Before the fix this trapped in
    /// `AudioProcessor.uint16(_:)` at AudioProcessor.swift:170.
    func testConvertFloatSamplesToWAV_withNegativeSampleDoesNotCrash() {
        // A negative sample (below zero crossing) — the case that trapped.
        let samples: [Float] = [-0.5, -1.0, -0.001]

        // This call must not trap. If the bug is present, the test process
        // crashes with SIGTRAP before XCTAssertNotNil runs.
        let wavData = AudioProcessor.convertFloatSamplesToWAV(samples, sampleRate: 16000)

        XCTAssertNotNil(wavData)
        XCTAssertGreaterThan(wavData.count, 44, "WAV data should include header plus PCM payload")
    }

    /// Full-range sweep including the boundary values that are most likely to
    /// expose overflow: -1.0, 0.0, +1.0, and a dense set of negatives.
    func testConvertFloatSamplesToWAV_fullRangeSweep() {
        var samples: [Float] = []
        for i in -1000...1000 {
            samples.append(Float(i) / 1000.0)
        }
        // Add exact clamping boundaries.
        samples.append(contentsOf: [-1.0, 0.0, 1.0, -2.0, 2.0])

        let wavData = AudioProcessor.convertFloatSamplesToWAV(samples, sampleRate: 16000)

        // Expected payload size: samples.count * 2 bytes (16-bit) + 44-byte header.
        let expectedMinSize = samples.count * 2 + 44
        XCTAssertGreaterThanOrEqual(wavData.count, expectedMinSize)
    }

    /// The WAV header's data-chunk size field must reflect the sample count.
    func testConvertFloatSamplesToWAV_headerDataSizeIsCorrect() {
        let samples: [Float] = Array(repeating: 0.0, count: 100)
        let wavData = AudioProcessor.convertFloatSamplesToWAV(samples, sampleRate: 16000)

        // "data" chunk is at offset 36, size is a little-endian UInt32 at offset 40.
        let dataTag = String(data: wavData.subdata(in: 36..<40), encoding: .ascii)
        XCTAssertEqual(dataTag, "data")

        let sizeBytes = wavData.subdata(in: 40..<44)
        let dataSize = sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(Int(dataSize), 100 * 2, "data chunk size must equal samples * bytesPerSample")
    }
}
