import AVFoundation
import Foundation
import WhisperKit

/// On-device dictation via WhisperKit. Replaces SFSpeechRecognizer for
/// real multilingual accuracy. Handles:
///   - model catalog (two curated tiers, per Stik product spec),
///   - per-model downloads with progress + cancellation,
///   - loading/unloading the WhisperKit pipeline,
///   - live streaming transcription from the mic with partial callbacks.
///
/// Thread safety: internal state is guarded by `stateLock`. The recognition
/// loop runs on a dedicated Task and the download runs on another, so
/// multiple public entry points may be called concurrently.
public final class WhisperDictationProvider {

    // MARK: - Model catalog

    /// Curated tier definitions. Model identifiers are the exact variant
    /// names published at https://huggingface.co/argmaxinc/whisperkit-coreml.
    public struct ModelTier: Sendable {
        public let id: String
        public let label: String
        public let sizeMB: Int
        public let description: String
    }

    public static let availableTiers: [ModelTier] = [
        ModelTier(
            id: "openai_whisper-small",
            label: "Balanced",
            sizeMB: 250,
            description:
                "Recommended. Good multilingual accuracy for everyday dictation."
        ),
        ModelTier(
            id: "openai_whisper-large-v3-v20240930_turbo_632MB",
            label: "High quality",
            sizeMB: 632,
            description:
                "Best accuracy. Larger download, slightly slower first load."
        ),
    ]

    // MARK: - State

    private let stateLock = NSLock()
    private let modelFolder: URL

    private var currentDownloadTask: Task<Void, Error>?
    private var currentDownloadProgress: Progress?
    private var currentDownloadModelId: String?

    private var loadedWhisperKit: WhisperKit?
    private var loadedModelId: String?

    // Recognition state
    private var recognitionTask: Task<Void, Never>?
    private var accumulatedText: String = ""
    private var isRecording: Bool = false

    // Serializes concurrent setActiveModel calls. Multiple callers
    // (first-run modal → model_loaded → startDictation, which also
    // calls setActiveModel as a safety net) can race and try to load
    // the same model twice, which WhisperKit's internal tokenizer
    // download can't handle — it tries to move the same .incomplete
    // file twice and the second one fails mid-way. One at a time.
    private var loadInFlight: Task<Void, Error>?

    // MARK: - Lock helper
    //
    // All state mutations go through `withLock`. This keeps lock/unlock
    // inside a single synchronous scope, which satisfies Swift 6's
    // strict-concurrency check that NSLock is not held across `await`.

    @discardableResult
    private func withLock<T>(_ block: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return block()
    }

    // MARK: - Init

    public init() {
        // ~/Library/Application Support/com.stik.app/WhisperModels/
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.modelFolder =
            appSupport
            .appendingPathComponent("com.stik.app", isDirectory: true)
            .appendingPathComponent("WhisperModels", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: modelFolder, withIntermediateDirectories: true
        )
    }

    // MARK: - Model catalog queries

    public struct ModelInfo {
        public let id: String
        public let label: String
        public let sizeMB: Int
        public let description: String
        public let downloaded: Bool
    }

    public func listModels() -> [ModelInfo] {
        let installed = installedModelIds()
        return Self.availableTiers.map { tier in
            ModelInfo(
                id: tier.id,
                label: tier.label,
                sizeMB: tier.sizeMB,
                description: tier.description,
                downloaded: installed.contains(tier.id)
            )
        }
    }

    public struct Status {
        public let installedModels: [String]
        public let activeModel: String?
        public let downloadInProgress: String?
    }

    public func status() -> Status {
        return withLock {
            Status(
                installedModels: Array(installedModelIdsLocked()),
                activeModel: loadedModelId,
                downloadInProgress: currentDownloadModelId
            )
        }
    }

    /// Path where a model's CoreML bundle lives on disk after
    /// `WhisperKit.download(downloadBase:)` finishes. Empirically,
    /// WhisperKit writes into `<downloadBase>/models/<repo>/<variant>/`,
    /// NOT `<downloadBase>/<repo>/<variant>/` — the extra `models/`
    /// directory is inserted by the underlying Hub download helper.
    private func modelOnDiskURL(for variant: String) -> URL {
        modelFolder
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(variant, isDirectory: true)
    }

    private func installedModelIds() -> Set<String> {
        return withLock { installedModelIdsLocked() }
    }

    private func installedModelIdsLocked() -> Set<String> {
        var result = Set<String>()
        for tier in Self.availableTiers {
            let url = modelOnDiskURL(for: tier.id)
            if FileManager.default.fileExists(atPath: url.path) {
                // Presence alone isn't enough — ensure the CoreML compilation
                // completed by checking for a known artifact inside.
                if hasCompiledModel(at: url) {
                    result.insert(tier.id)
                }
            }
        }
        return result
    }

    private func hasCompiledModel(at folder: URL) -> Bool {
        // WhisperKit variants contain an AudioEncoder.mlmodelc and
        // TextDecoder.mlmodelc folder when fully downloaded & compiled.
        let fm = FileManager.default
        let encoder = folder.appendingPathComponent("AudioEncoder.mlmodelc")
        let decoder = folder.appendingPathComponent("TextDecoder.mlmodelc")
        return fm.fileExists(atPath: encoder.path)
            && fm.fileExists(atPath: decoder.path)
    }

    // MARK: - Download

    public enum DictationError: Error {
        case unknownModel(String)
        case downloadCancelled
        case downloadAlreadyInProgress
        case noActiveModel
        case notRecording
        case alreadyRecording
        case modelLoadFailed(String)
    }

    /// Kick off a download. Returns immediately; progress arrives via
    /// `onProgress`, completion via `onComplete`, errors via `onError`.
    public func downloadModel(
        id: String,
        onProgress: @escaping (Double, Int64, Int64) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard Self.availableTiers.contains(where: { $0.id == id }) else {
            onError(DictationError.unknownModel(id))
            return
        }

        let alreadyDownloading: Bool = withLock {
            if currentDownloadTask != nil { return true }
            currentDownloadModelId = id
            return false
        }
        if alreadyDownloading {
            onError(DictationError.downloadAlreadyInProgress)
            return
        }

        let task = Task<Void, Error> { [weak self] in
            guard let self = self else { return }
            defer {
                self.withLock {
                    self.currentDownloadTask = nil
                    self.currentDownloadProgress = nil
                    self.currentDownloadModelId = nil
                }
            }

            Self.log("download started: \(id)")
            var progressTickCount = 0

            do {
                _ = try await WhisperKit.download(
                    variant: id,
                    downloadBase: self.modelFolder,
                    useBackgroundSession: false,
                    from: "argmaxinc/whisperkit-coreml",
                    progressCallback: { progress in
                        progressTickCount += 1
                        if progressTickCount <= 3 || progressTickCount % 20 == 0 {
                            Self.log(
                                "download tick #\(progressTickCount): "
                                    + "fraction=\(progress.fractionCompleted), "
                                    + "done=\(progress.completedUnitCount), "
                                    + "total=\(progress.totalUnitCount)"
                            )
                        }
                        self.withLock {
                            self.currentDownloadProgress = progress
                        }
                        onProgress(
                            progress.fractionCompleted,
                            progress.completedUnitCount,
                            progress.totalUnitCount
                        )
                    }
                )
                if Task.isCancelled {
                    Self.log("download cancelled: \(id)")
                    onError(DictationError.downloadCancelled)
                    return
                }
                Self.log("download complete: \(id), \(progressTickCount) progress ticks")
                onComplete()
            } catch {
                if Task.isCancelled {
                    Self.log("download cancelled on error: \(id)")
                    onError(DictationError.downloadCancelled)
                } else {
                    Self.log("download failed: \(id): \(error.localizedDescription)")
                    onError(error)
                }
            }
        }

        withLock {
            currentDownloadTask = task
        }
    }

    public func cancelDownload() {
        let snapshot: (Task<Void, Error>?, Progress?) = withLock {
            (currentDownloadTask, currentDownloadProgress)
        }
        snapshot.1?.cancel()
        snapshot.0?.cancel()
    }

    public func deleteModel(id: String) throws {
        guard Self.availableTiers.contains(where: { $0.id == id }) else {
            throw DictationError.unknownModel(id)
        }
        let url = modelOnDiskURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        withLock {
            if loadedModelId == id {
                loadedWhisperKit = nil
                loadedModelId = nil
            }
        }
    }

    // MARK: - Model loading

    /// Loads a model into memory. Idempotent — if already loaded, returns
    /// immediately. If a load is already in flight for this id, awaits
    /// that one instead of kicking off a duplicate (which would race on
    /// WhisperKit's tokenizer download).
    public func setActiveModel(id: String) async throws {
        guard Self.availableTiers.contains(where: { $0.id == id }) else {
            throw DictationError.unknownModel(id)
        }

        // Fast path: already loaded.
        let alreadyLoaded: Bool = withLock {
            loadedModelId == id && loadedWhisperKit != nil
        }
        if alreadyLoaded {
            Self.log("model already loaded: \(id)")
            return
        }

        // Dedupe: if another caller is already loading, await theirs.
        let existing: Task<Void, Error>? = withLock { loadInFlight }
        if let existing = existing {
            Self.log("awaiting in-flight load for: \(id)")
            try await existing.value
            return
        }

        // Kick off a fresh load task and register it.
        let loadTask = Task<Void, Error> { [weak self] in
            guard let self = self else { return }
            let modelPath = self.modelOnDiskURL(for: id).path
            Self.log("loading model from: \(modelPath)")
            let loadStart = Date()

            // `download: true` is required because WhisperKit loads the
            // Whisper tokenizer from the original `openai/whisper-<variant>`
            // HuggingFace repo at load time — that's a SEPARATE download
            // from the CoreML weights we pre-fetched. Blocking it breaks
            // tokenization with "tokenizer.json missing" failures.
            //
            // First-load is slow (measured: ~30 s for small, ~140 s for
            // turbo) because CoreML compiles the .mlmodelc bundles for
            // the Neural Engine. Subsequent loads are near-instant.
            // WhisperKit's internal verbose logs go through os_log
            // under subsystem `com.argmaxinc.whisperkit`, not stderr —
            // use `log stream --predicate 'subsystem == "…"'` if you
            // need to watch them.
            let config = WhisperKitConfig(
                model: id,
                modelFolder: modelPath,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true
            )

            do {
                let pipe = try await WhisperKit(config)
                self.withLock {
                    self.loadedWhisperKit = pipe
                    self.loadedModelId = id
                }
                let elapsed = Date().timeIntervalSince(loadStart)
                Self.log("model loaded: \(id) in \(String(format: "%.1f", elapsed))s")
            } catch {
                Self.log("model load failed: \(id): \(error.localizedDescription)")
                throw DictationError.modelLoadFailed(error.localizedDescription)
            }
        }
        withLock { loadInFlight = loadTask }

        defer {
            withLock { loadInFlight = nil }
        }

        try await loadTask.value
    }

    public func activeModelId() -> String? {
        return withLock { loadedModelId }
    }

    // MARK: - Recognition (skeleton; fleshed out in Phase 4)

    public func start(
        language: String?,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        // Atomic state transition: reserve the recording slot OR fail.
        let pipeOrFail: Result<WhisperKit, DictationError> = withLock {
            if isRecording { return .failure(.alreadyRecording) }
            guard let p = loadedWhisperKit else { return .failure(.noActiveModel) }
            isRecording = true
            accumulatedText = ""
            return .success(p)
        }
        let whisperKit: WhisperKit
        switch pipeOrFail {
        case .failure(let err): throw err
        case .success(let p): whisperKit = p
        }

        // Start the mic capture. WhisperKit's AudioProcessor accumulates
        // samples in `audioSamples` until we call stopRecording().
        do {
            try whisperKit.audioProcessor.startRecordingLive(inputDeviceID: nil) { _ in }
        } catch {
            withLock { isRecording = false }
            throw DictationError.modelLoadFailed(
                "Failed to start microphone: \(error.localizedDescription)"
            )
        }

        Self.log("recording started, language=\(language ?? "<auto>")")

        let langCode = language

        // Background polling loop. Re-transcribes the growing audio
        // buffer on a cadence tuned to balance latency against flicker:
        //
        //   - poll every 500 ms (was 250 ms) — decoder gets more context
        //     per pass, which stabilizes early tokens
        //   - require ≥ 1.0 s of new audio before re-running (was 0.5 s)
        //   - VAD-gate: skip the pass entirely if the new segment is
        //     silent; prevents Whisper from hallucinating words during
        //     pauses between sentences
        //   - anti-flicker on output: only emit a new partial if it
        //     extends the previous one as a prefix OR is substantively
        //     different (length delta > 8 chars). Rejects the common
        //     "hello" → "hallo" → "hello" word-level churn.
        let task = Task<Void, Never> { [weak self] in
            guard let self = self else { return }
            var lastSampleCount = 0
            var lastEmittedText = ""
            let pollSleepNs: UInt64 = 500_000_000
            let minNewSamples = Int(WhisperKit.sampleRate)  // 1.0 s
            let silenceThreshold: Float = 0.022  // relative energy

            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: langCode,
                temperature: 0.0,
                temperatureFallbackCount: 5,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                wordTimestamps: false,
                suppressBlank: true,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                noSpeechThreshold: 0.6
            )

            // Streaming loop
            while self.withLock({ self.isRecording }) {
                let currentBuffer = whisperKit.audioProcessor.audioSamples
                let newSamples = currentBuffer.count - lastSampleCount

                if newSamples < minNewSamples {
                    try? await Task.sleep(nanoseconds: pollSleepNs)
                    continue
                }

                // VAD — if the new chunk is silent, don't bother
                // re-transcribing. Whisper hallucinates on silence
                // (adds phrases like "Thanks for watching!" from its
                // training data). relativeEnergy is a rolling window
                // of per-buffer RMS values; isVoiceDetected checks
                // whether any of the most-recent entries clear the
                // threshold.
                let nextBufferSeconds = Float(newSamples) / Float(WhisperKit.sampleRate)
                let voiceDetected = AudioProcessor.isVoiceDetected(
                    in: whisperKit.audioProcessor.relativeEnergy,
                    nextBufferInSeconds: nextBufferSeconds,
                    silenceThreshold: silenceThreshold
                )
                if !voiceDetected {
                    lastSampleCount = currentBuffer.count
                    try? await Task.sleep(nanoseconds: pollSleepNs)
                    continue
                }

                do {
                    let results = try await whisperKit.transcribe(
                        audioArray: Array(currentBuffer),
                        decodeOptions: options
                    )
                    let text = Self.joinResultText(results)
                    if text.isEmpty {
                        lastSampleCount = currentBuffer.count
                        try? await Task.sleep(nanoseconds: pollSleepNs)
                        continue
                    }

                    // Anti-flicker: accept extensions of the previous
                    // emission; reject short shrinkbacks. Still accept
                    // the update if it's a meaningful re-interpretation
                    // of similar length (within ±8 chars of previous).
                    let extendsPrev = text.hasPrefix(lastEmittedText)
                    let shrankTooMuch = text.count + 8 < lastEmittedText.count
                    let shouldEmit = extendsPrev || !shrankTooMuch

                    if shouldEmit {
                        self.withLock { self.accumulatedText = text }
                        onPartial(text)
                        lastEmittedText = text
                    } else {
                        Self.log(
                            "flicker-guard dropped partial: "
                                + "len \(text.count) < prev \(lastEmittedText.count)"
                        )
                    }
                    lastSampleCount = currentBuffer.count
                } catch {
                    Self.log("transcribe error: \(error.localizedDescription)")
                    onError(error)
                    break
                }

                try? await Task.sleep(nanoseconds: pollSleepNs)
            }

            // Final transcribe pass — picks up any audio that arrived
            // after the last partial.
            let finalBuffer = whisperKit.audioProcessor.audioSamples
            var finalText = self.withLock { self.accumulatedText }
            if !finalBuffer.isEmpty {
                do {
                    let results = try await whisperKit.transcribe(
                        audioArray: Array(finalBuffer),
                        decodeOptions: options
                    )
                    finalText = Self.joinResultText(results)
                    self.withLock { self.accumulatedText = finalText }
                } catch {
                    Self.log("final transcribe error: \(error.localizedDescription)")
                    onError(error)
                }
            }

            whisperKit.audioProcessor.stopRecording()
            onFinal(finalText)
            Self.log("recording finished, final length=\(finalText.count)")
        }

        withLock { recognitionTask = task }
    }

    public func stop() throws -> String {
        let wasRecording: Bool = withLock {
            if !isRecording { return false }
            isRecording = false
            return true
        }
        if !wasRecording {
            throw DictationError.notRecording
        }

        // Block (with a generous timeout) until the streaming loop
        // finishes its final transcribe pass. This bridges the async
        // task back to the synchronous JSON-RPC handler so the response
        // already carries the authoritative final text — no race with
        // the speech.final notification.
        if let task = withLock({ recognitionTask }) {
            let sem = DispatchSemaphore(value: 0)
            Task<Void, Never> {
                await task.value
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 15)
        }

        let text = withLock {
            let t = accumulatedText
            accumulatedText = ""
            recognitionTask = nil
            return t
        }
        return text
    }

    // MARK: - Helpers

    private static func joinResultText(_ results: [TranscriptionResult]) -> String {
        let raw = results.map { $0.text }.joined(separator: " ")
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("[dictation] \(message)\n".utf8))
    }
}
