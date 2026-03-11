import Darwin
import Foundation
import Vision

// MARK: - Provider Protocol

public struct OCRResult {
    public let text: String
    public let blocks: [OCRBlock]
}

public struct OCRBlock {
    public let text: String
    public let confidence: Float
    public let bounds: CGRect  // Normalized 0..1 coordinates, origin bottom-left
}

public protocol VisionProvider {
    func recognizeText(imagePath: String, languages: [String], level: RecognitionLevel) throws -> OCRResult
}

public enum RecognitionLevel: String {
    case accurate
    case fast
}

// MARK: - Apple Implementation

public struct AppleVisionProvider: VisionProvider {

    public init() {}

    public func recognizeText(imagePath: String, languages: [String], level: RecognitionLevel) throws -> OCRResult {
        let url = URL(fileURLWithPath: imagePath)

        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw JsonRpcError.invalidParams("File not found: \(imagePath)")
        }

        let handler = VNImageRequestHandler(url: url, options: [:])
        var blocks: [OCRBlock] = []
        var fullText: [String] = []

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                let errMsg = "[darwinkit] OCR error: \(error.localizedDescription)\n"
                errMsg.utf8.withContiguousStorageIfAvailable { buf in
                    _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                fullText.append(candidate.string)
                blocks.append(OCRBlock(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    bounds: observation.boundingBox
                ))
            }
        }

        request.recognitionLevel = level == .accurate ? .accurate : .fast
        request.usesLanguageCorrection = true
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }

        try handler.perform([request])

        return OCRResult(
            text: fullText.joined(separator: "\n"),
            blocks: blocks
        )
    }
}
