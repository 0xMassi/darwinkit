import ArgumentParser
import DarwinKitCore
import Foundation

@main
struct DarwinKitCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "darwinkit",
        abstract: "Expose Apple's on-device ML frameworks via JSON-RPC over stdio.",
        version: JsonRpcServer.version,
        subcommands: [Serve.self, Query.self],
        defaultSubcommand: Serve.self
    )
}

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run in server mode — reads JSON-RPC from stdin, writes responses to stdout."
    )

    mutating func run() {
        // swift-transformers' Hub resolves some download targets
        // relative to the current working directory. When we run as a
        // sidecar inside Stik.app/Contents/MacOS, cwd is read-only, so
        // any relative-path writes fail with
        // "tokenizer.json.X.incomplete couldn't be moved to whisper-small"
        // style errors. Pin cwd to ~/Library/Application Support/com.stik.app/
        // (which we create lazily) so Hub has a writable sandbox.
        let fm = FileManager.default
        if let appSupport = fm.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            let base = appSupport.appendingPathComponent("com.stik.app", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            fm.changeCurrentDirectoryPath(base.path)
        }

        let server = buildServerWithRouter()
        server.start()
    }
}

struct Query: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute a single JSON-RPC request and exit."
    )

    @Argument(help: "JSON-RPC request string")
    var json: String

    mutating func run() throws {
        let router = buildRouter()

        let decoder = JSONDecoder()
        guard let data = json.data(using: .utf8) else {
            throw ValidationError("Invalid UTF-8 input")
        }

        let request = try decoder.decode(JsonRpcRequest.self, from: data)
        let result = try router.dispatch(request)

        let response = JsonRpcResponse.success(id: request.id, result: result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let output = try encoder.encode(response)
        print(String(data: output, encoding: .utf8)!)
    }
}

/// Build server and router together so handlers can receive the server as NotificationSink.
func buildServerWithRouter() -> JsonRpcServer {
    let router = MethodRouter()
    let server = JsonRpcServer(router: router)

    router.register(SystemHandler(router: router))
    router.register(NLPHandler())
    router.register(VisionHandler())
    router.register(CloudHandler(notificationSink: server))
    router.register(AuthHandler())
    router.register(DictationHandler(notificationSink: server))

    return server
}

/// Central router factory — all handlers registered here (for single-shot Query mode).
func buildRouter() -> MethodRouter {
    let router = MethodRouter()
    router.register(SystemHandler(router: router))
    router.register(NLPHandler())
    router.register(VisionHandler())
    router.register(CloudHandler())
    router.register(AuthHandler())
    router.register(DictationHandler())
    return router
}
