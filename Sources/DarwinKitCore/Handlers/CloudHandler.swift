import Foundation

/// Handles all icloud.* JSON-RPC methods for coordinated iCloud file operations.
public final class CloudHandler: MethodHandler {
    private let provider: CloudProvider
    private weak var notificationSink: NotificationSink?

    public var methods: [String] {
        [
            "icloud.status",
            "icloud.read",
            "icloud.write",
            "icloud.write_bytes",
            "icloud.delete",
            "icloud.move",
            "icloud.list_dir",
            "icloud.start_monitoring",
            "icloud.stop_monitoring",
            "icloud.copy_file",
            "icloud.ensure_dir",
        ]
    }

    public init(provider: CloudProvider = AppleCloudProvider(), notificationSink: NotificationSink? = nil) {
        self.provider = provider
        self.notificationSink = notificationSink
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "icloud.status":
            return try handleStatus(request)
        case "icloud.read":
            return try handleRead(request)
        case "icloud.write":
            return try handleWrite(request)
        case "icloud.write_bytes":
            return try handleWriteBytes(request)
        case "icloud.delete":
            return try handleDelete(request)
        case "icloud.move":
            return try handleMove(request)
        case "icloud.list_dir":
            return try handleListDir(request)
        case "icloud.start_monitoring":
            return try handleStartMonitoring(request)
        case "icloud.stop_monitoring":
            return try handleStopMonitoring(request)
        case "icloud.copy_file":
            return try handleCopyFile(request)
        case "icloud.ensure_dir":
            return try handleEnsureDir(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        let available = provider.isAvailable()
        let note = available ? nil : "iCloud container not available (check Apple ID sign-in)"
        return MethodCapability(available: available, note: note)
    }

    // MARK: - Method Implementations

    private func handleStatus(_ request: JsonRpcRequest) throws -> Any {
        let available = provider.isAvailable()
        let containerURL = provider.containerURL()?.path ?? ""

        // Determine storage mode from Rust-side settings (simplified: we report availability)
        return [
            "available": available,
            "container_url": containerURL,
        ] as [String: Any]
    }

    private func handleRead(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let url = URL(fileURLWithPath: path)

        do {
            let data = try provider.coordinatedRead(at: url)
            guard let content = String(data: data, encoding: .utf8) else {
                throw JsonRpcError.internalError("File is not valid UTF-8: \(path)")
            }
            return ["content": content]
        } catch let error as JsonRpcError {
            throw error
        } catch {
            throw JsonRpcError.internalError("Failed to read file: \(error.localizedDescription)")
        }
    }

    private func handleWrite(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let content = try request.requireString("content")
        let url = URL(fileURLWithPath: path)

        guard let data = content.data(using: .utf8) else {
            throw JsonRpcError.invalidParams("Content is not valid UTF-8")
        }

        do {
            try provider.coordinatedWrite(data, to: url)
            return ["ok": true]
        } catch {
            throw JsonRpcError.internalError("Failed to write file: \(error.localizedDescription)")
        }
    }

    private func handleWriteBytes(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let base64String = try request.requireString("data")
        let url = URL(fileURLWithPath: path)

        guard let data = Data(base64Encoded: base64String) else {
            throw JsonRpcError.invalidParams("Invalid base64 data")
        }

        do {
            try provider.coordinatedWrite(data, to: url)
            return ["ok": true]
        } catch {
            throw JsonRpcError.internalError("Failed to write bytes: \(error.localizedDescription)")
        }
    }

    private func handleDelete(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let url = URL(fileURLWithPath: path)

        do {
            try provider.coordinatedDelete(at: url)
            return ["ok": true]
        } catch {
            throw JsonRpcError.internalError("Failed to delete file: \(error.localizedDescription)")
        }
    }

    private func handleMove(_ request: JsonRpcRequest) throws -> Any {
        let source = try request.requireString("source")
        let destination = try request.requireString("destination")
        let srcURL = URL(fileURLWithPath: source)
        let dstURL = URL(fileURLWithPath: destination)

        do {
            try provider.coordinatedMove(from: srcURL, to: dstURL)
            return ["ok": true]
        } catch {
            throw JsonRpcError.internalError("Failed to move file: \(error.localizedDescription)")
        }
    }

    private func handleListDir(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let url = URL(fileURLWithPath: path)

        do {
            let entries = try provider.listDirectory(at: url)
            let result = entries.map { entry -> [String: Any] in
                var dict: [String: Any] = [
                    "name": entry.name,
                    "is_directory": entry.isDirectory,
                    "size": entry.size,
                ]
                if let modified = entry.modified {
                    dict["modified"] = ISO8601DateFormatter().string(from: modified)
                }
                return dict
            }
            return ["entries": result]
        } catch {
            throw JsonRpcError.internalError("Failed to list directory: \(error.localizedDescription)")
        }
    }

    private func handleStartMonitoring(_ request: JsonRpcRequest) throws -> Any {
        guard let sink = notificationSink else {
            throw JsonRpcError.internalError("Notification sink not configured")
        }

        provider.startMonitoring { paths in
            sink.sendNotification(method: "icloud.files_changed", params: ["paths": paths])
        }

        return ["ok": true]
    }

    private func handleStopMonitoring(_ request: JsonRpcRequest) throws -> Any {
        provider.stopMonitoring()
        return ["ok": true]
    }

    private func handleCopyFile(_ request: JsonRpcRequest) throws -> Any {
        let source = try request.requireString("source")
        let destination = try request.requireString("destination")
        let srcURL = URL(fileURLWithPath: source)
        let dstURL = URL(fileURLWithPath: destination)

        do {
            try provider.coordinatedCopy(from: srcURL, to: dstURL)
            return ["ok": true]
        } catch {
            throw JsonRpcError.internalError("Failed to copy file: \(error.localizedDescription)")
        }
    }

    private func handleEnsureDir(_ request: JsonRpcRequest) throws -> Any {
        let path = try request.requireString("path")
        let url = URL(fileURLWithPath: path)

        do {
            try provider.ensureDirectory(at: url)
            return ["ok": true]
        } catch {
            throw JsonRpcError.internalError("Failed to create directory: \(error.localizedDescription)")
        }
    }
}
