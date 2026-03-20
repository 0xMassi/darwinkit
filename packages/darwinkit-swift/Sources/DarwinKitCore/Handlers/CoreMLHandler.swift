import Foundation

/// Handles all coreml.* methods: load, unload, embed, predict, contextual embeddings.
public final class CoreMLHandler: MethodHandler {
    private let provider: CoreMLProvider

    public var methods: [String] {
        [
            "coreml.load_model", "coreml.unload_model", "coreml.model_info",
            "coreml.models", "coreml.embed", "coreml.embed_batch",
            "coreml.load_contextual", "coreml.contextual_embed",
            "coreml.embed_contextual_batch"
        ]
    }

    public init(provider: CoreMLProvider) {
        self.provider = provider
    }

    public func handle(_ request: JsonRpcRequest) throws -> Any {
        switch request.method {
        case "coreml.load_model":
            return try handleLoadModel(request)
        case "coreml.unload_model":
            return try handleUnloadModel(request)
        case "coreml.model_info":
            return try handleModelInfo(request)
        case "coreml.models":
            return try handleListModels(request)
        case "coreml.embed":
            return try handleEmbed(request)
        case "coreml.embed_batch":
            return try handleEmbedBatch(request)
        case "coreml.load_contextual":
            return try handleLoadContextual(request)
        case "coreml.contextual_embed":
            return try handleContextualEmbed(request)
        case "coreml.embed_contextual_batch":
            return try handleEmbedContextualBatch(request)
        default:
            throw JsonRpcError.methodNotFound(request.method)
        }
    }

    public func capability(for method: String) -> MethodCapability {
        switch method {
        case "coreml.load_contextual", "coreml.contextual_embed", "coreml.embed_contextual_batch":
            return MethodCapability(available: true, note: "Requires macOS 14+")
        default:
            return MethodCapability(available: true)
        }
    }

    // MARK: - Method Implementations

    private func handleLoadModel(_ request: JsonRpcRequest) throws -> Any {
        let id = try request.requireString("id")
        let path = try request.requireString("path")
        let computeUnitsStr = request.string("compute_units") ?? "all"
        let warmUp = request.bool("warm_up") ?? true

        guard let computeUnits = CoreMLComputeUnits(rawValue: computeUnitsStr) else {
            throw JsonRpcError.invalidParams(
                "Invalid compute_units: '\(computeUnitsStr)'. Must be: \(CoreMLComputeUnits.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }

        let options = CoreMLLoadOptions(path: path, computeUnits: computeUnits, warmUp: warmUp)
        let info = try provider.loadModel(id: id, options: options)
        return info.toDict()
    }

    private func handleUnloadModel(_ request: JsonRpcRequest) throws -> Any {
        let id = try request.requireString("id")
        try provider.unloadModel(id: id)
        return ["ok": true] as [String: Any]
    }

    private func handleModelInfo(_ request: JsonRpcRequest) throws -> Any {
        let id = try request.requireString("id")
        let info = try provider.modelInfo(id: id)
        return info.toDict()
    }

    private func handleListModels(_ request: JsonRpcRequest) throws -> Any {
        let models = provider.listModels()
        return ["models": models.map { $0.toDict() }] as [String: Any]
    }

    private func handleEmbed(_ request: JsonRpcRequest) throws -> Any {
        let modelId = try request.requireString("model_id")
        let text = try request.requireString("text")

        guard !text.isEmpty else {
            throw JsonRpcError.invalidParams("text must not be empty")
        }

        let vector = try provider.embed(modelId: modelId, text: text)
        return [
            "vector": vector,
            "dimensions": vector.count,
        ] as [String: Any]
    }

    private func handleEmbedBatch(_ request: JsonRpcRequest) throws -> Any {
        let modelId = try request.requireString("model_id")

        guard let texts = request.stringArray("texts"), !texts.isEmpty else {
            throw JsonRpcError.invalidParams("texts must be a non-empty array of strings")
        }

        let vectors = try provider.embedBatch(modelId: modelId, texts: texts)
        return [
            "vectors": vectors,
            "dimensions": vectors.first?.count ?? 0,
            "count": vectors.count,
        ] as [String: Any]
    }

    private func handleLoadContextual(_ request: JsonRpcRequest) throws -> Any {
        let id = try request.requireString("id")
        let language = try request.requireString("language")
        let info = try provider.loadContextualEmbedding(id: id, language: language)
        return info.toDict()
    }

    private func handleContextualEmbed(_ request: JsonRpcRequest) throws -> Any {
        let modelId = try request.requireString("model_id")
        let text = try request.requireString("text")

        guard !text.isEmpty else {
            throw JsonRpcError.invalidParams("text must not be empty")
        }

        let vector = try provider.contextualEmbed(modelId: modelId, text: text)
        return [
            "vector": vector,
            "dimensions": vector.count,
        ] as [String: Any]
    }

    private func handleEmbedContextualBatch(_ request: JsonRpcRequest) throws -> Any {
        let modelId = try request.requireString("model_id")

        guard let texts = request.stringArray("texts"), !texts.isEmpty else {
            throw JsonRpcError.invalidParams("texts must be a non-empty array of strings")
        }

        var vectors: [[Float]] = []

        for text in texts {
            let vector = try provider.contextualEmbed(modelId: modelId, text: text)
            vectors.append(vector)
        }

        return [
            "vectors": vectors,
            "dimensions": vectors.first?.count ?? 0,
            "count": vectors.count,
        ] as [String: Any]
    }
}
