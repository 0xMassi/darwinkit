import Foundation
import Testing
@testable import DarwinKitCore

@Suite("CoreML Integration — NLContextualEmbedding")
struct CoreMLIntegrationTests {

    @Test("NLContextualEmbedding loads for English")
    func loadContextualEnglish() throws {
        let provider = AppleCoreMLProvider()
        let info = try provider.loadContextualEmbedding(id: "test-en", language: "en")

        #expect(info.id == "test-en")
        #expect(info.dimensions > 0)
        #expect(info.modelType == "contextual")
    }

    @Test("contextual embed produces correct-dim vector")
    func contextualEmbedDimensions() throws {
        let provider = AppleCoreMLProvider()
        let info = try provider.loadContextualEmbedding(id: "integ-en", language: "en")
        let vector = try provider.contextualEmbed(modelId: "integ-en", text: "The quick brown fox")

        #expect(vector.count == info.dimensions)
    }

    @Test("contextual embed produces different vectors for different texts")
    func contextualEmbedDifferentTexts() throws {
        let provider = AppleCoreMLProvider()
        _ = try provider.loadContextualEmbedding(id: "diff-en", language: "en")

        let v1 = try provider.contextualEmbed(modelId: "diff-en", text: "I love programming")
        let v2 = try provider.contextualEmbed(modelId: "diff-en", text: "The weather is sunny")

        #expect(v1 != v2)
    }

    @Test("contextual embed vectors are normalized (L2 norm close to 1)")
    func contextualEmbedNormalized() throws {
        let provider = AppleCoreMLProvider()
        _ = try provider.loadContextualEmbedding(id: "norm-en", language: "en")
        let vector = try provider.contextualEmbed(modelId: "norm-en", text: "Test normalization")

        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        #expect(abs(norm - 1.0) < 0.01)
    }

    @Test("similar texts have higher cosine similarity")
    func contextualEmbedSimilarity() throws {
        let provider = AppleCoreMLProvider()
        _ = try provider.loadContextualEmbedding(id: "sim-en", language: "en")

        let vCat = try provider.contextualEmbed(modelId: "sim-en", text: "The cat is sleeping")
        let vKitten = try provider.contextualEmbed(modelId: "sim-en", text: "A kitten is napping")
        let vCar = try provider.contextualEmbed(modelId: "sim-en", text: "The car needs new tires")

        func cosine(_ a: [Float], _ b: [Float]) -> Float {
            zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        }

        let simCatKitten = cosine(vCat, vKitten)
        let simCatCar = cosine(vCat, vCar)

        #expect(simCatKitten > simCatCar)
    }

    @Test("unloading contextual model works")
    func unloadContextual() throws {
        let provider = AppleCoreMLProvider()
        _ = try provider.loadContextualEmbedding(id: "unload-en", language: "en")

        let before = provider.listModels()
        #expect(before.contains { $0.id == "unload-en" })

        try provider.unloadModel(id: "unload-en")

        let after = provider.listModels()
        #expect(!after.contains { $0.id == "unload-en" })
    }
}
