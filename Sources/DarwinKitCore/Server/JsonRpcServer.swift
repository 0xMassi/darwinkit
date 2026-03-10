import Foundation

/// Protocol for handlers that need to push async notifications to the parent process.
public protocol NotificationSink: AnyObject {
    func sendNotification(method: String, params: Any)
}

/// Handles JSON-RPC communication over stdin/stdout.
/// Reads NDJSON requests from stdin, dispatches to registered handlers, writes responses to stdout.
public final class JsonRpcServer: NotificationSink {
    public static let version = "0.1.0"

    private let router: MethodRouter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(router: MethodRouter) {
        self.router = router
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    /// Start the server. Blocks until stdin is closed.
    public func start() {
        // Disable stdout buffering — critical when piped to a parent process.
        // Without this, responses accumulate in a 4KB buffer and the parent never sees them.
        setbuf(stdout, nil)

        // Send ready notification so parent knows we're alive and what we support
        let capabilities = router.availableMethods()
        sendNotification(method: "ready", params: [
            "version": JsonRpcServer.version,
            "capabilities": capabilities
        ])

        // Read stdin on a background thread, dispatch to main thread for framework calls
        let stdinThread = Thread { [self] in
            while let line = readLine(strippingNewline: true) {
                if line.isEmpty { continue }
                self.handleLine(line)
            }
            // stdin closed — parent process is done
            self.log("stdin closed, shutting down")
            exit(0)
        }
        stdinThread.name = "darwinkit.stdin"
        stdinThread.start()

        // Main thread runs RunLoop (needed for async Apple framework callbacks)
        RunLoop.main.run()
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            sendError(id: nil, error: .parseError("Invalid UTF-8 input"))
            return
        }

        let request: JsonRpcRequest
        do {
            request = try decoder.decode(JsonRpcRequest.self, from: data)
        } catch {
            sendError(id: nil, error: .parseError("Malformed JSON: \(error.localizedDescription)"))
            return
        }

        guard request.jsonrpc == "2.0" else {
            sendError(id: request.id, error: .invalidRequest("jsonrpc must be \"2.0\""))
            return
        }

        // Handle cancellation notifications
        if request.method == "$/cancel" {
            // TODO: implement cancellation for long-running operations
            return
        }

        do {
            let result = try router.dispatch(request)
            sendSuccess(id: request.id, result: result)
        } catch let error as JsonRpcError {
            sendError(id: request.id, error: error)
        } catch {
            sendError(id: request.id, error: .internalError(error.localizedDescription))
        }
    }

    private func sendSuccess(id: String?, result: Any) {
        let response = JsonRpcResponse.success(id: id, result: result)
        writeLine(response)
    }

    private func sendError(id: String?, error: JsonRpcError) {
        let response = JsonRpcResponse.failure(id: id, error: error)
        writeLine(response)
    }

    public func sendNotification(method: String, params: Any) {
        let json: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    private func writeLine(_ response: JsonRpcResponse) {
        if let data = try? encoder.encode(response),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    func log(_ message: String) {
        FileHandle.standardError.write(Data("[darwinkit] \(message)\n".utf8))
    }
}
