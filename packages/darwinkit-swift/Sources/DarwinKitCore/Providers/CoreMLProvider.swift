import Foundation

// MARK: - Compute Units

public enum CoreMLComputeUnits: String, CaseIterable {
    case all
    case cpuAndGPU
    case cpuOnly
    case cpuAndNeuralEngine
}

// MARK: - Model Info

public struct CoreMLModelInfo {
    public let id: String
    public let path: String
    public let dimensions: Int
    public let computeUnits: String
    public let sizeBytes: Int64
    public let modelType: String  // "coreml" | "contextual"

    public init(
        id: String, path: String, dimensions: Int,
        computeUnits: String, sizeBytes: Int64, modelType: String
    ) {
        self.id = id
        self.path = path
        self.dimensions = dimensions
        self.computeUnits = computeUnits
        self.sizeBytes = sizeBytes
        self.modelType = modelType
    }

    public func toDict() -> [String: Any] {
        [
            "id": id,
            "path": path,
            "dimensions": dimensions,
            "compute_units": computeUnits,
            "size_bytes": sizeBytes,
            "model_type": modelType,
        ]
    }
}

// MARK: - Load Options

public struct CoreMLLoadOptions {
    public let path: String
    public let computeUnits: CoreMLComputeUnits
    public let warmUp: Bool

    public init(path: String, computeUnits: CoreMLComputeUnits = .all, warmUp: Bool = true) {
        self.path = path
        self.computeUnits = computeUnits
        self.warmUp = warmUp
    }
}

// MARK: - Provider Protocol

public protocol CoreMLProvider {
    /// Load a CoreML model from disk. Returns model info.
    func loadModel(id: String, options: CoreMLLoadOptions) throws -> CoreMLModelInfo

    /// Unload a previously loaded model, freeing memory.
    func unloadModel(id: String) throws

    /// Get info about a loaded model.
    func modelInfo(id: String) throws -> CoreMLModelInfo

    /// List all currently loaded models.
    func listModels() -> [CoreMLModelInfo]

    /// Embed a single text using a loaded model. Returns Float array (GPU-native precision).
    func embed(modelId: String, text: String) throws -> [Float]

    /// Embed multiple texts in batch. Returns array of Float arrays.
    func embedBatch(modelId: String, texts: [String]) throws -> [[Float]]

    /// Load NLContextualEmbedding (macOS 14+). Returns model info with 768 dimensions.
    func loadContextualEmbedding(id: String, language: String) throws -> CoreMLModelInfo

    /// Embed text using NLContextualEmbedding with vDSP-optimized mean pooling.
    func contextualEmbed(modelId: String, text: String) throws -> [Float]
}
