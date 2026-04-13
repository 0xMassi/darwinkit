import Foundation

/// JSON-RPC surface for the WhisperKit-based dictation feature.
///
/// Methods fall into three groups:
///   1. Model management (list, download, delete, set active, status)
///   2. Recognition control (start, stop)
///   3. Notification channels (partials + download progress)
///
/// Long-running operations (download, recognition) return immediately
/// with a status reply and stream state back via push notifications so
/// the Rust side can surface them as Tauri events without blocking.
public final class DictationHandler: MethodHandler {
    private let provider: WhisperDictationProvider
    private weak var notificationSink: NotificationSink?

    public var methods: [String] {
        [
            "dictation.list_models",
            "dictation.status",
            "dictation.download_model",
            "dictation.cancel_download",
            "dictation.delete_model",
            "dictation.set_active_model",
            "dictation.start",
            "dictation.stop",
        ]
    }

    public init(
        provider: WhisperDictationProvider = WhisperDictationProvider(),
        notificationSink: NotificationSink? = nil
    ) {
        self.provider = provider
        self.notificationSink = notificationSink
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "dictation.list_models":
            return handleListModels()
        case "dictation.status":
            return handleStatus()
        case "dictation.download_model":
            return try handleDownloadModel(request)
        case "dictation.cancel_download":
            return handleCancelDownload()
        case "dictation.delete_model":
            return try handleDeleteModel(request)
        case "dictation.set_active_model":
            return try handleSetActiveModel(request)
        case "dictation.start":
            return try handleStart(request)
        case "dictation.stop":
            return try handleStop(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        // All dictation methods are available whenever the sidecar is
        // running on macOS 14+. Model availability is reported separately
        // via dictation.status so the client can branch its UI.
        return MethodCapability(available: true, note: nil)
    }

    // MARK: - Model management

    private func handleListModels() -> Any {
        let models = provider.listModels()
        let array: [[String: Any]] = models.map { m in
            [
                "id": m.id,
                "label": m.label,
                "size_mb": m.sizeMB,
                "description": m.description,
                "downloaded": m.downloaded,
            ]
        }
        return ["models": array]
    }

    private func handleStatus() -> Any {
        let s = provider.status()
        var result: [String: Any] = [
            "installed_models": s.installedModels,
        ]
        if let active = s.activeModel {
            result["active_model"] = active
        }
        if let inProgress = s.downloadInProgress {
            result["downloading"] = inProgress
        }
        return result
    }

    private func handleDownloadModel(_ request: JsonRpcRequest) throws -> Any {
        let modelId = try request.requireString("model_id")
        let sink = notificationSink

        provider.downloadModel(
            id: modelId,
            onProgress: { fraction, done, total in
                sink?.sendNotification(
                    method: "dictation.download_progress",
                    params: [
                        "model_id": modelId,
                        "progress": fraction,
                        "bytes_done": done,
                        "bytes_total": total,
                    ]
                )
            },
            onComplete: {
                sink?.sendNotification(
                    method: "dictation.download_complete",
                    params: ["model_id": modelId]
                )
            },
            onError: { error in
                sink?.sendNotification(
                    method: "dictation.download_error",
                    params: [
                        "model_id": modelId,
                        "message": error.localizedDescription,
                    ]
                )
            }
        )

        return ["status": "downloading", "model_id": modelId]
    }

    private func handleCancelDownload() -> Any {
        provider.cancelDownload()
        return ["ok": true]
    }

    private func handleDeleteModel(_ request: JsonRpcRequest) throws -> Any {
        let modelId = try request.requireString("model_id")
        do {
            try provider.deleteModel(id: modelId)
            return ["ok": true]
        } catch {
            throw JsonRpcError.internalError(
                "Failed to delete model: \(error.localizedDescription)"
            )
        }
    }

    private func handleSetActiveModel(_ request: JsonRpcRequest) throws -> Any {
        let modelId = try request.requireString("model_id")

        // Block synchronously on the load so the JSON-RPC response is
        // authoritative: success means the model is actually ready,
        // error means it genuinely failed. This removes the previous
        // async-notification flow that required the frontend to
        // correlate an immediate "loading" reply with a later
        // `model_loaded` event — a pattern that kept getting multiple
        // set_active_model calls stuck in in-flight dedupe loops.
        //
        // CoreML compilation for turbo can legitimately take 30–60 s
        // on first load; 180 s is generous headroom to cover a slow
        // Mac or a cold Neural Engine.
        let sem = DispatchSemaphore(value: 0)
        var loadError: Error?
        Task {
            do {
                try await self.provider.setActiveModel(id: modelId)
            } catch {
                loadError = error
            }
            sem.signal()
        }

        let timeoutResult = sem.wait(timeout: .now() + 180)
        if timeoutResult == .timedOut {
            throw JsonRpcError.internalError(
                "Model load timed out after 180 s. Check stderr for WhisperKit progress."
            )
        }

        if let loadError = loadError {
            throw JsonRpcError.internalError(
                "Model load failed: \(loadError.localizedDescription)"
            )
        }

        return ["model_id": modelId, "status": "loaded"]
    }

    // MARK: - Recognition

    private func handleStart(_ request: JsonRpcRequest) throws -> Any {
        guard let sink = notificationSink else {
            throw JsonRpcError.internalError("Notification sink not configured")
        }

        let language = request.string("language")
        let preferredModelId = request.string("model_id")

        // Decide which model should be active. Preference order:
        //   1. `model_id` explicitly passed by the frontend (persisted
        //      from Settings → Dictation → Active Model)
        //   2. If nothing is loaded at all, the first installed model
        //      as a safe fallback
        //   3. If a model is already loaded and no preference, keep it
        //
        // This bridges the async setActiveModel call back to the
        // synchronous handler via DispatchSemaphore. First-load of a
        // big model can take ~150 s for CoreML/ANE compilation, so we
        // give it 180 s of headroom.
        let currentlyLoaded = provider.activeModelId()
        let desiredModel: String? = {
            if let preferred = preferredModelId, !preferred.isEmpty {
                return preferred
            }
            if currentlyLoaded == nil {
                return provider.status().installedModels.first
            }
            return nil // already loaded, no preference → keep it
        }()

        if let desiredModel = desiredModel, desiredModel != currentlyLoaded {
            let loadSem = DispatchSemaphore(value: 0)
            var loadError: Error?
            Task {
                do {
                    try await self.provider.setActiveModel(id: desiredModel)
                } catch {
                    loadError = error
                }
                loadSem.signal()
            }
            _ = loadSem.wait(timeout: .now() + 180)
            if let loadError = loadError {
                throw JsonRpcError.internalError(
                    "Model load failed: \(loadError.localizedDescription)"
                )
            }
        } else if currentlyLoaded == nil {
            throw JsonRpcError.invalidParams(
                "No dictation model installed. Download one first."
            )
        }

        do {
            try provider.start(
                language: language,
                onPartial: { text in
                    sink.sendNotification(
                        method: "dictation.partial",
                        params: ["text": text]
                    )
                },
                onFinal: { text in
                    sink.sendNotification(
                        method: "dictation.final",
                        params: ["text": text]
                    )
                },
                onError: { error in
                    sink.sendNotification(
                        method: "dictation.error",
                        params: ["message": error.localizedDescription]
                    )
                }
            )
            return ["status": "started"]
        } catch WhisperDictationProvider.DictationError.noActiveModel {
            throw JsonRpcError.invalidParams(
                "No active dictation model. Download and select one first."
            )
        } catch {
            throw JsonRpcError.internalError(
                "Failed to start dictation: \(error.localizedDescription)"
            )
        }
    }

    private func handleStop(_ request: JsonRpcRequest) throws -> Any {
        do {
            let text = try provider.stop()
            return ["text": text]
        } catch WhisperDictationProvider.DictationError.notRecording {
            return ["text": ""]
        } catch {
            throw JsonRpcError.internalError(
                "Failed to stop dictation: \(error.localizedDescription)"
            )
        }
    }
}
