import Foundation
import Testing
@testable import DarwinKitCore

// MARK: - Mock Provider

struct MockCoreMLProvider: CoreMLProvider {
    var models: [String: CoreMLModelInfo] = [:]
    var embedResult: [Float] = [0.1, 0.2, 0.3, 0.4]
    var embedBatchResult: [[Float]] = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
    var contextualEmbedResult: [Float] = Array(repeating: Float(0.01), count: 768)
    var shouldThrow: JsonRpcError? = nil

    func loadModel(id: String, options: CoreMLLoadOptions) throws -> CoreMLModelInfo {
        if let err = shouldThrow { throw err }

        return CoreMLModelInfo(
            id: id, path: options.path, dimensions: 384,
            computeUnits: options.computeUnits.rawValue,
            sizeBytes: 45_000_000, modelType: "coreml"
        )
    }

    func unloadModel(id: String) throws {
        if let err = shouldThrow { throw err }

        guard models[id] != nil else {
            throw JsonRpcError.invalidParams("No model loaded with id: \(id)")
        }
    }

    func modelInfo(id: String) throws -> CoreMLModelInfo {
        if let err = shouldThrow { throw err }

        guard let info = models[id] else {
            throw JsonRpcError.invalidParams("No model loaded with id: \(id)")
        }

        return info
    }

    func listModels() -> [CoreMLModelInfo] {
        Array(models.values)
    }

    func embed(modelId: String, text: String) throws -> [Float] {
        if let err = shouldThrow { throw err }

        return embedResult
    }

    func embedBatch(modelId: String, texts: [String]) throws -> [[Float]] {
        if let err = shouldThrow { throw err }

        return Array(embedBatchResult.prefix(texts.count))
    }

    func loadContextualEmbedding(id: String, language: String) throws -> CoreMLModelInfo {
        if let err = shouldThrow { throw err }

        return CoreMLModelInfo(
            id: id, path: "system://\(language)", dimensions: 768,
            computeUnits: "all", sizeBytes: 0, modelType: "contextual"
        )
    }

    func contextualEmbed(modelId: String, text: String) throws -> [Float] {
        if let err = shouldThrow { throw err }

        return contextualEmbedResult
    }
}

// MARK: - Helper

private func makeRequest(method: String, params: [String: Any] = [:]) -> JsonRpcRequest {
    let codableParams = params.mapValues { AnyCodable($0) }
    return JsonRpcRequest(id: "test", method: method, params: codableParams)
}

// MARK: - Tests

@Suite("CoreML Handler")
struct CoreMLHandlerTests {

    // MARK: - coreml.load_model

    @Test("load_model returns model info")
    func loadModelSuccess() throws {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.load_model", params: [
            "id": "minilm", "path": "/models/MiniLM.mlpackage"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["id"] as? String == "minilm")
        #expect(result["dimensions"] as? Int == 384)
        #expect(result["model_type"] as? String == "coreml")
    }

    @Test("load_model throws on missing id")
    func loadModelMissingId() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.load_model", params: [
            "path": "/models/MiniLM.mlpackage"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("load_model throws on missing path")
    func loadModelMissingPath() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.load_model", params: ["id": "test"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("load_model defaults compute_units to all")
    func loadModelDefaultComputeUnits() throws {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.load_model", params: [
            "id": "minilm", "path": "/models/MiniLM.mlpackage"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["compute_units"] as? String == "all")
    }

    @Test("load_model accepts custom compute_units")
    func loadModelCustomComputeUnits() throws {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.load_model", params: [
            "id": "minilm", "path": "/models/MiniLM.mlpackage",
            "compute_units": "cpuAndNeuralEngine"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["compute_units"] as? String == "cpuAndNeuralEngine")
    }

    @Test("load_model throws on invalid compute_units")
    func loadModelInvalidComputeUnits() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.load_model", params: [
            "id": "minilm", "path": "/models/MiniLM.mlpackage",
            "compute_units": "quantum"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - coreml.unload_model

    @Test("unload_model succeeds for loaded model")
    func unloadModelSuccess() throws {
        var mock = MockCoreMLProvider()
        mock.models["minilm"] = CoreMLModelInfo(
            id: "minilm", path: "/test", dimensions: 384,
            computeUnits: "all", sizeBytes: 100, modelType: "coreml"
        )
        let handler = CoreMLHandler(provider: mock)
        let request = makeRequest(method: "coreml.unload_model", params: ["id": "minilm"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["ok"] as? Bool == true)
    }

    @Test("unload_model throws on missing id")
    func unloadModelMissingId() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.unload_model", params: [:])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("unload_model throws on unknown model")
    func unloadModelUnknown() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.unload_model", params: ["id": "nonexistent"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - coreml.model_info

    @Test("model_info returns info for loaded model")
    func modelInfoSuccess() throws {
        var mock = MockCoreMLProvider()
        mock.models["minilm"] = CoreMLModelInfo(
            id: "minilm", path: "/test", dimensions: 384,
            computeUnits: "all", sizeBytes: 45_000_000, modelType: "coreml"
        )
        let handler = CoreMLHandler(provider: mock)
        let request = makeRequest(method: "coreml.model_info", params: ["id": "minilm"])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["id"] as? String == "minilm")
        #expect(result["dimensions"] as? Int == 384)
        #expect(result["size_bytes"] as? Int64 == 45_000_000)
    }

    @Test("model_info throws on unknown model")
    func modelInfoUnknown() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.model_info", params: ["id": "nonexistent"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - coreml.models

    @Test("models returns empty array when none loaded")
    func modelsEmpty() throws {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.models")
        let result = try handler.handle(request) as! [String: Any]
        let models = result["models"] as! [[String: Any]]

        #expect(models.isEmpty)
    }

    @Test("models returns loaded models")
    func modelsWithEntries() throws {
        var mock = MockCoreMLProvider()
        mock.models["minilm"] = CoreMLModelInfo(
            id: "minilm", path: "/test", dimensions: 384,
            computeUnits: "all", sizeBytes: 100, modelType: "coreml"
        )
        let handler = CoreMLHandler(provider: mock)
        let request = makeRequest(method: "coreml.models")
        let result = try handler.handle(request) as! [String: Any]
        let models = result["models"] as! [[String: Any]]

        #expect(models.count == 1)
        #expect(models[0]["id"] as? String == "minilm")
    }

    // MARK: - coreml.embed

    @Test("embed returns vector and dimensions")
    func embedSuccess() throws {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.embed", params: [
            "model_id": "minilm", "text": "hello world"
        ])
        let result = try handler.handle(request) as! [String: Any]

        let vector = result["vector"] as! [Float]
        #expect(!vector.isEmpty)
        #expect(result["dimensions"] as? Int == vector.count)
    }

    @Test("embed throws on missing model_id")
    func embedMissingModelId() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.embed", params: ["text": "hello"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("embed throws on missing text")
    func embedMissingText() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.embed", params: ["model_id": "minilm"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    @Test("embed throws on empty text")
    func embedEmptyText() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.embed", params: [
            "model_id": "minilm", "text": ""
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - coreml.embed_batch

    @Test("embed_batch returns multiple vectors")
    func embedBatchSuccess() throws {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.embed_batch", params: [
            "model_id": "minilm", "texts": ["hello", "world"]
        ])
        let result = try handler.handle(request) as! [String: Any]

        let vectors = result["vectors"] as! [[Any]]
        #expect(vectors.count == 2)
        #expect(result["count"] as? Int == 2)
    }

    @Test("embed_batch throws on empty texts")
    func embedBatchEmpty() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.embed_batch", params: [
            "model_id": "minilm", "texts": [] as [String]
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - coreml.load_contextual

    @Test("load_contextual returns model info with 768 dims")
    func loadContextualSuccess() throws {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.load_contextual", params: [
            "id": "apple-en", "language": "en"
        ])
        let result = try handler.handle(request) as! [String: Any]

        #expect(result["id"] as? String == "apple-en")
        #expect(result["dimensions"] as? Int == 768)
        #expect(result["model_type"] as? String == "contextual")
    }

    @Test("load_contextual throws on missing language")
    func loadContextualMissingLang() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.load_contextual", params: ["id": "apple-en"])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }

    // MARK: - coreml.contextual_embed

    @Test("contextual_embed returns 768-dim vector")
    func contextualEmbedSuccess() throws {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let request = makeRequest(method: "coreml.contextual_embed", params: [
            "model_id": "apple-en", "text": "The cat sat on the mat"
        ])
        let result = try handler.handle(request) as! [String: Any]

        let vector = result["vector"] as! [Float]
        #expect(vector.count == 768)
        #expect(result["dimensions"] as? Int == 768)
    }

    // MARK: - Method registration

    @Test("handler registers all 9 CoreML methods")
    func methodRegistration() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())
        let expected: Set<String> = [
            "coreml.load_model", "coreml.unload_model", "coreml.model_info",
            "coreml.models", "coreml.embed", "coreml.embed_batch",
            "coreml.load_contextual", "coreml.contextual_embed",
            "coreml.embed_contextual_batch"
        ]

        #expect(Set(handler.methods) == expected)
    }

    @Test("handler reports capabilities for all methods")
    func capabilities() {
        let handler = CoreMLHandler(provider: MockCoreMLProvider())

        for method in handler.methods {
            let cap = handler.capability(for: method)
            #expect(cap.available == true)
        }
    }

    // MARK: - Provider error propagation

    @Test("provider errors propagate through handler")
    func providerError() {
        var mock = MockCoreMLProvider()
        mock.shouldThrow = .frameworkUnavailable("CoreML not available")
        let handler = CoreMLHandler(provider: mock)
        let request = makeRequest(method: "coreml.embed", params: [
            "model_id": "test", "text": "hello"
        ])

        #expect(throws: JsonRpcError.self) {
            try handler.handle(request)
        }
    }
}
