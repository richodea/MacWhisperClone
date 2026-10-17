import Foundation
import Accelerate

/// On-device speaker diarization using MFCC audio features + k-means clustering.
///
/// This is a lightweight, model-free diarizer. It does NOT use a neural speaker
/// embedding model (which would require downloading additional weights). Instead
/// it extracts Mel-Frequency Cepstral Coefficients (MFCCs) from each segment's
/// audio window and clusters them with k-means. This works well for the common
/// case of 2–4 distinct speakers in a clean recording (meetings, interviews,
/// podcasts) and degrades gracefully on noisy or overlapping speech.
///
/// The pipeline:
///   1. For each segment, slice the corresponding audio samples by timestamp.
///   2. Frame the slice into ~30ms windows with 10ms hop.
///   3. Compute 13 MFCC coefficients per frame (FFT magnitude → mel filterbank → DCT).
///   4. Average MFCCs across frames → one 13-dim vector per segment.
///   5. Run k-means (k = estimated speaker count, default 2) on the vectors.
///   6. Map cluster IDs to "Speaker N" labels.
enum SpeakerDiarizer {

    /// Configuration for the diarizer.
    struct Config {
        /// Sample rate of the audio (Hz). WhisperKit uses 16000.
        var sampleRate: Int = 16000
        /// Frame size in milliseconds for MFCC windowing.
        var frameSizeMs: Double = 25
        /// Hop size in milliseconds between frames.
        var hopSizeMs: Double = 10
        /// Number of MFCC coefficients to keep.
        var numCoeffs: Int = 13
        /// Number of mel filterbank bins.
        var numMelBins: Int = 26
        /// FFT size (power of 2, >= frame size).
        var fftSize: Int = 512
        /// Minimum segment duration (seconds) to attempt diarization on.
        var minSegmentDuration: TimeInterval = 0.5
        /// Maximum number of speakers to detect.
        var maxSpeakers: Int = 6
        /// K-means iterations.
        var kmeansIterations: Int = 50

        static let `default` = Config()
    }

    /// Result of diarization: a speaker label per segment, in the same order
    /// as the input segments.
    struct DiarizationResult {
        let speakerLabels: [String]
        let speakerCount: Int
        /// Per-segment cluster index (0-based), parallel to speakerLabels.
        let clusterAssignments: [Int]
    }

    /// Run diarization over a set of segments.
    ///
    /// - Parameters:
    ///   - samples: Full mono PCM float audio (range -1...1) at `config.sampleRate`.
    ///   - segments: Segments with `startTime`/`endTime` in seconds.
    ///   - config: Pipeline configuration.
    /// - Returns: Speaker label per segment. Segments too short to analyze are
    ///   assigned to the nearest preceding speaker, or "Speaker 1" if none.
    static func diarize(
        samples: [Float],
        segments: [(startTime: TimeInterval, endTime: TimeInterval)],
        config: Config = .default
    ) -> DiarizationResult {
        guard !segments.isEmpty else {
            return DiarizationResult(speakerLabels: [], speakerCount: 0, clusterAssignments: [])
        }

        // 1. Extract one MFCC feature vector per segment.
        var featureVectors: [[Float]] = []
        var analyzableIndices: [Int] = [] // segments that produced a feature vector

        for (i, seg) in segments.enumerated() {
            let duration = seg.endTime - seg.startTime
            guard duration >= config.minSegmentDuration else { continue }

            let vector = mfccVector(
                samples: samples,
                startTime: seg.startTime,
                endTime: seg.endTime,
                config: config
            )
            if !vector.isEmpty {
                featureVectors.append(vector)
                analyzableIndices.append(i)
            }
        }

        // If nothing was analyzable, assign everything to Speaker 1.
        guard !featureVectors.isEmpty else {
            let labels = Array(repeating: "Speaker 1", count: segments.count)
            return DiarizationResult(
                speakerLabels: labels,
                speakerCount: 1,
                clusterAssignments: Array(repeating: 0, count: segments.count)
            )
        }

        // 2. Estimate number of speakers via silhouette-ish heuristic: try k=2..maxSpeakers,
        //    pick the k with lowest within-cluster variance that doesn't collapse.
        //    For simplicity and speed, default to k=2 unless variance suggests more.
        let estimatedK = estimateSpeakerCount(featureVectors: featureVectors, maxK: config.maxSpeakers)

        // 3. K-means clustering.
        let assignments = kmeans(
            points: featureVectors,
            k: estimatedK,
            iterations: config.kmeansIterations
        )

        // 4. Build full per-segment label array, filling gaps from nearest analyzable segment.
        var clusterBySegment = Array(repeating: 0, count: segments.count)
        for (idx, segIndex) in analyzableIndices.enumerated() {
            clusterBySegment[segIndex] = assignments[idx]
        }

        // Fill non-analyzable segments with the cluster of the nearest preceding analyzable one.
        var lastCluster = 0
        for i in 0..<segments.count {
            if analyzableIndices.contains(i) {
                lastCluster = clusterBySegment[i]
            } else {
                clusterBySegment[i] = lastCluster
            }
        }

        // 5. Map cluster IDs to "Speaker N" labels. Renumber so the first speaker
        //    to appear gets "Speaker 1", the next new one "Speaker 2", etc.
        var firstAppearanceOrder: [Int] = []
        for c in clusterBySegment where !firstAppearanceOrder.contains(c) {
            firstAppearanceOrder.append(c)
        }
        let labelMap: [Int: String] = Dictionary(
            uniqueKeysWithValues: firstAppearanceOrder.enumerated().map { idx, cluster in
                (cluster, "Speaker \(idx + 1)")
            }
        )
        let labels = clusterBySegment.map { labelMap[$0] ?? "Speaker 1" }

        return DiarizationResult(
            speakerLabels: labels,
            speakerCount: firstAppearanceOrder.count,
            clusterAssignments: clusterBySegment
        )
    }

    // MARK: - MFCC Extraction

    /// Compute a single averaged MFCC vector for an audio slice [startTime, endTime).
    private static func mfccVector(
        samples: [Float],
        startTime: TimeInterval,
        endTime: TimeInterval,
        config: Config
    ) -> [Float] {
        let sr = Float(config.sampleRate)
        let startSample = Int(startTime * Double(sr))
        let endSample = Int(endTime * Double(sr))
        guard startSample >= 0, endSample <= samples.count, endSample > startSample else {
            return []
        }

        let slice = Array(samples[startSample..<endSample])
        let frameSize = Int(Float(config.frameSizeMs) / 1000.0 * sr)
        let hopSize = Int(Float(config.hopSizeMs) / 1000.0 * sr)
        guard frameSize > 0, hopSize > 0, slice.count >= frameSize else { return [] }

        // Precompute mel filterbank (shared across frames).
        let filterbank = melFilterbank(
            numFilters: config.numMelBins,
            fftSize: config.fftSize,
            sampleRate: config.sampleRate
        )

        var frameVectors: [[Float]] = []
        var pos = 0
        while pos + frameSize <= slice.count {
            let frame = Array(slice[pos..<(pos + frameSize)])
            let coeffs = mfccFrame(
                frame: frame,
                fftSize: config.fftSize,
                numCoeffs: config.numCoeffs,
                filterbank: filterbank
            )
            if !coeffs.isEmpty {
                frameVectors.append(coeffs)
            }
            pos += hopSize
        }

        guard !frameVectors.isEmpty else { return [] }

        // Average across frames → one vector per segment.
        let numCoeffs = config.numCoeffs
        var averaged = [Float](repeating: 0, count: numCoeffs)
        for fv in frameVectors {
            for j in 0..<numCoeffs { averaged[j] += fv[j] }
        }
        let n = Float(frameVectors.count)
        for j in 0..<numCoeffs { averaged[j] /= n }

        return averaged
    }

    /// Compute MFCC for a single frame: window → FFT power → mel → log → DCT.
    private static func mfccFrame(
        frame: [Float],
        fftSize: Int,
        numCoeffs: Int,
        filterbank: [[Float]]
    ) -> [Float] {
        // 1. Zero-pad frame to fftSize and apply Hamming window.
        var signal = [Float](repeating: 0, count: fftSize)
        for i in 0..<min(frame.count, fftSize) {
            // Hamming window
            let w = 0.54 - 0.46 * cos(2 * Float.pi * Float(i) / Float(frame.count - 1))
            signal[i] = frame[i] * w
        }

        // 2. Real FFT via the classic vDSP C API (stable across SDK versions).
        let log2n = UInt(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfSize = fftSize / 2

        // Pack the real signal into a split complex (even samples → real, odd → imag),
        // then run the forward FFT.
        var realOut = [Float](repeating: 0, count: halfSize)
        var imagOut = [Float](repeating: 0, count: halfSize)

        signal.withUnsafeBufferPointer { signalPtr in
            realOut.withUnsafeMutableBufferPointer { realPtr in
                imagOut.withUnsafeMutableBufferPointer { imagPtr in
                    signalPtr.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self,
                        capacity: halfSize
                    ) { complexPtr in
                        var splitComplex = DSPSplitComplex(
                            realp: realPtr.baseAddress!,
                            imagp: imagPtr.baseAddress!
                        )
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfSize))
                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                    }
                }
            }
        }

        // 3. Power spectrum (magnitude squared). vDSP_zvabs writes |z| into
        //    `power`; then vDSP_vsq squares it for power.
        var power = [Float](repeating: 0, count: halfSize)
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var sc = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&sc, 1, &power, 1, vDSP_Length(halfSize))
            }
        }
        vDSP_vsq(power, 1, &power, 1, vDSP_Length(halfSize))

        // 4. Apply mel filterbank → log.
        var melEnergies = [Float](repeating: 0, count: filterbank.count)
        for (i, filter) in filterbank.enumerated() {
            var sum: Float = 0
            vDSP_dotpr(filter, 1, power, 1, &sum, vDSP_Length(filter.count))
            // Floor to avoid log(0).
            melEnergies[i] = log(max(sum, 1e-10))
        }

        // 5. DCT-II to get cepstral coefficients. Use a simple manual DCT
        //    (13 coeffs is small; vDSP DCT would also work but adds setup cost).
        var coeffs = [Float](repeating: 0, count: numCoeffs)
        let n = Float(melEnergies.count)
        for k in 0..<numCoeffs {
            var sum: Float = 0
            for (i, m) in melEnergies.enumerated() {
                sum += m * cos(Float.pi * Float(k) * (Float(i) + 0.5) / n)
            }
            coeffs[k] = sum
        }

        return coeffs
    }

    /// Build a mel-spaced triangular filterbank: numFilters rows, each fftSize/2 wide.
    private static func melFilterbank(numFilters: Int, fftSize: Int, sampleRate: Int) -> [[Float]] {
        let numBins = fftSize / 2
        let melMax = hzToMel(Float(sampleRate / 2))
        let melMin: Float = 0

        // Mel points equally spaced, then back to Hz.
        let melPoints = (0...numFilters).map { i in
            melMin + (melMax - melMin) * Float(i) / Float(numFilters)
        }
        let hzPoints = melPoints.map { melToHz($0) }
        let binPoints = hzPoints.map { Int(round($0 / Float(sampleRate) * Float(fftSize))) }

        var filterbank: [[Float]] = []
        for i in 0..<numFilters {
            var filter = [Float](repeating: 0, count: numBins)
            let left = binPoints[i]
            let center = binPoints[i + 1]
            let right = binPoints[i + 2]
            guard center > left, right > center else { continue }

            // Rising slope.
            for b in left..<center where b < numBins && b >= 0 {
                filter[b] = Float(b - left) / Float(center - left)
            }
            // Falling slope.
            for b in center..<right where b < numBins && b >= 0 {
                filter[b] = Float(right - b) / Float(right - center)
            }
            filterbank.append(filter)
        }
        return filterbank
    }

    private static func hzToMel(_ hz: Float) -> Float {
        2595 * log10(1 + hz / 700)
    }

    private static func melToHz(_ mel: Float) -> Float {
        700 * (pow(10, mel / 2595) - 1)
    }

    // MARK: - Speaker Count Estimation

    /// Estimate the number of distinct speakers by trying k=2..maxK and picking
    /// the k that gives the largest drop in within-cluster sum of squares (WSS),
    /// using an "elbow" heuristic. Falls back to 2 if no clear elbow.
    private static func estimateSpeakerCount(featureVectors: [[Float]], maxK: Int) -> Int {
        let n = featureVectors.count
        guard n >= 2 else { return 1 }

        let upperBound = min(maxK, n)
        guard upperBound >= 2 else { return 1 }

        var wssByK: [(k: Int, wss: Float)] = []
        for k in 2...upperBound {
            let assignments = kmeans(points: featureVectors, k: k, iterations: 30)
            let wss = withinClusterSumOfSquares(points: featureVectors, assignments: assignments, k: k)
            wssByK.append((k, wss))
        }

        // Elbow: pick the k where the relative drop to the next k is largest.
        // If only one k was tried, use it.
        guard wssByK.count >= 2 else { return wssByK.first?.k ?? 2 }

        var bestK = wssByK[0].k
        var bestDrop: Float = 0
        for i in 0..<(wssByK.count - 1) {
            let drop = wssByK[i].wss - wssByK[i + 1].wss
            if drop > bestDrop {
                bestDrop = drop
                bestK = wssByK[i].k
            }
        }
        return bestK
    }

    private static func withinClusterSumOfSquares(points: [[Float]], assignments: [Int], k: Int) -> Float {
        var centroids = Array(repeating: [Float](repeating: 0, count: points.first?.count ?? 0), count: k)
        var counts = Array(repeating: 0, count: k)
        for (i, a) in assignments.enumerated() {
            for j in 0..<centroids[a].count {
                centroids[a][j] += points[i][j]
            }
            counts[a] += 1
        }
        for c in 0..<k where counts[c] > 0 {
            for j in 0..<centroids[c].count {
                centroids[c][j] /= Float(counts[c])
            }
        }
        var total: Float = 0
        for (i, a) in assignments.enumerated() {
            for j in 0..<points[i].count {
                let d = points[i][j] - centroids[a][j]
                total += d * d
            }
        }
        return total
    }

    // MARK: - K-Means

    /// Plain k-means with k-means++ initialization. Returns cluster index per point.
    private static func kmeans(points: [[Float]], k: Int, iterations: Int) -> [Int] {
        let n = points.count
        guard n > 0, k > 0 else { return Array(repeating: 0, count: n) }
        let dim = points.first?.count ?? 0
        guard dim > 0 else { return Array(repeating: 0, count: n) }

        if n <= k {
            // Each point its own cluster.
            return (0..<n).map { $0 }
        }

        // k-means++ seeding.
        var centroids: [[Float]] = []
        centroids.append(points.randomElement()!)
        while centroids.count < k {
            var distances = [Float](repeating: 0, count: n)
            for i in 0..<n {
                var minDist: Float = .infinity
                for c in centroids {
                    let d = squaredDistance(points[i], c)
                    if d < minDist { minDist = d }
                }
                distances[i] = minDist
            }
            // Weighted random pick by distance.
            let total = distances.reduce(0, +)
            guard total > 0 else {
                centroids.append(points.randomElement()!)
                continue
            }
            let r = Float.random(in: 0...total)
            var acc: Float = 0
            var picked = 0
            for i in 0..<n {
                acc += distances[i]
                if acc >= r { picked = i; break }
            }
            centroids.append(points[picked])
        }

        var assignments = [Int](repeating: 0, count: n)
        for _ in 0..<iterations {
            // Assign step.
            var changed = false
            for i in 0..<n {
                var bestCluster = 0
                var bestDist: Float = .infinity
                for c in 0..<k {
                    let d = squaredDistance(points[i], centroids[c])
                    if d < bestDist {
                        bestDist = d
                        bestCluster = c
                    }
                }
                if assignments[i] != bestCluster {
                    assignments[i] = bestCluster
                    changed = true
                }
            }
            if !changed { break }

            // Update step.
            var sums = Array(repeating: [Float](repeating: 0, count: dim), count: k)
            var counts = [Int](repeating: 0, count: k)
            for i in 0..<n {
                let a = assignments[i]
                for j in 0..<dim { sums[a][j] += points[i][j] }
                counts[a] += 1
            }
            for c in 0..<k where counts[c] > 0 {
                for j in 0..<dim { sums[c][j] /= Float(counts[c]) }
                centroids[c] = sums[c]
            }
            // Re-seed empty clusters.
            for c in 0..<k where counts[c] == 0 {
                centroids[c] = points.randomElement()!
            }
        }

        return assignments
    }

    private static func squaredDistance(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for i in 0..<min(a.count, b.count) {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sum
    }
}
