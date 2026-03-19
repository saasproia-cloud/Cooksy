import Foundation
import ImageIO
import UIKit
import Vision

enum IngredientPhotoClassifierService {
    static func classifyIngredients(from imageData: Data) async -> [String] {
        guard let image = UIImage(data: imageData) else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: classifyIngredients(from: image))
            }
        }
    }

    private static func classifyIngredients(from image: UIImage) -> [String] {
        let request = VNClassifyImageRequest()

        do {
            let handler = try imageRequestHandler(for: image)
            try handler.perform([request])
        } catch {
            return []
        }

        let observations = (request.results ?? []).prefix(18)
        var ingredients: [String] = []
        var seen = Set<String>()

        for observation in observations where observation.confidence >= 0.08 {
            for ingredient in mappedIngredients(for: observation.identifier) {
                if seen.insert(ingredient).inserted {
                    ingredients.append(ingredient)
                }
            }
            if ingredients.count >= 8 {
                break
            }
        }

        return ingredients
    }

    private static func imageRequestHandler(for image: UIImage) throws -> VNImageRequestHandler {
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        if let cgImage = image.cgImage {
            return VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        }

        if let ciImage = CIImage(image: image) {
            return VNImageRequestHandler(ciImage: ciImage, orientation: orientation)
        }

        throw IngredientPhotoClassifierError.unreadableImage
    }

    private static func mappedIngredients(for identifier: String) -> [String] {
        let normalized = identifier
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var matches: [String] = []

        for entry in mappings where entry.keywords.contains(where: normalized.contains) {
            if !matches.contains(entry.ingredient) {
                matches.append(entry.ingredient)
            }
        }

        return matches
    }

    private static let mappings: [(keywords: [String], ingredient: String)] = [
        (["tomato", "cherry tomato"], "tomate"),
        (["bell pepper", "pepper"], "poivron"),
        (["cucumber", "gherkin"], "concombre"),
        (["lettuce", "salad"], "salade"),
        (["spinach"], "epinard"),
        (["broccoli"], "brocoli"),
        (["mushroom"], "champignon"),
        (["onion"], "oignon"),
        (["garlic"], "ail"),
        (["carrot"], "carotte"),
        (["potato", "french fries"], "pomme de terre"),
        (["zucchini", "courgette"], "courgette"),
        (["eggplant"], "aubergine"),
        (["avocado"], "avocat"),
        (["lemon", "lime"], "citron"),
        (["orange"], "orange"),
        (["apple"], "pomme"),
        (["banana"], "banane"),
        (["strawberry"], "fraise"),
        (["blueberry"], "myrtille"),
        (["grape"], "raisin"),
        (["egg"], "oeuf"),
        (["milk"], "lait"),
        (["butter"], "beurre"),
        (["cheese"], "fromage"),
        (["bread", "bagel", "baguette"], "pain"),
        (["rice"], "riz"),
        (["pasta", "spaghetti", "macaroni"], "pates"),
        (["flour"], "farine"),
        (["sugar"], "sucre"),
        (["honey"], "miel"),
        (["chocolate"], "chocolat"),
        (["chicken"], "poulet"),
        (["turkey"], "dinde"),
        (["beef", "steak", "hamburger"], "boeuf"),
        (["pork", "bacon"], "porc"),
        (["salmon"], "saumon"),
        (["fish"], "poisson"),
        (["shrimp", "prawn"], "crevette"),
        (["cake", "pie", "tart"], "tarte"),
        (["soup"], "soupe"),
        (["pizza"], "pizza"),
        (["sandwich"], "sandwich")
    ]
}

private enum IngredientPhotoClassifierError: Error {
    case unreadableImage
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
