import Foundation
import UIKit
@preconcurrency import Vision

enum RecipeOCRServiceError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "L'image n'a pas pu etre lue."
        }
    }
}

enum RecipeOCRService {
    static func recognizeText(from imageData: Data) async throws -> String {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw RecipeOCRServiceError.unreadableImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .sorted { lhs, rhs in
                        if abs(lhs.boundingBox.maxY - rhs.boundingBox.maxY) > 0.02 {
                            return lhs.boundingBox.maxY > rhs.boundingBox.maxY
                        }
                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    }

                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: lines.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["fr-FR", "en-US"]
            request.minimumTextHeight = 0.015

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
