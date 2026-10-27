import Foundation
import ImageIO
import UIKit
import Vision

struct PlaqueScan: Sendable {
    var text: String
    var suggestedName: String
    var imageData: Data
    var uncertainLines: Int
}

enum PlaqueRecognition {
    static let notesPrefix = "Museum plaque transcription:\n"

    static func suggestedName(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let headings = lines.filter {
            let lower = $0.lowercased()
            return !lower.contains("museum") && !lower.contains("collection") &&
                !lower.contains("on loan") && !lower.contains("courtesy") &&
                !lower.contains("test fixture")
        }
        for (index, line) in headings.enumerated() {
            if line.range(of: #"^(18|19|20)\d{2}\b"#, options: .regularExpression) != nil {
                if line.count > 4 { return line }
                // Plaques often put the year on its own line, above or below the name.
                let adjacent = index > 0 ? headings[index - 1] : headings.dropFirst(index + 1).first
                if let adjacent, adjacent.count <= 160 { return line + " " + adjacent }
            }
        }
        return headings.first ?? ""
    }

    static func recognize(_ data: Data) throws -> PlaqueScan {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2200
              ] as CFDictionary) else {
            throw failure("This image could not be opened. Choose another plaque photo.")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined(separator: "\n")
        let picture = UIImage(cgImage: image)
        var archived: Data?
        for quality in [0.85, 0.7, 0.55, 0.4, 0.25] {
            if let jpeg = picture.jpegData(compressionQuality: quality), jpeg.count <= 250 * 1024 {
                archived = jpeg; break
            }
        }
        guard let archived else { throw failure("This photo is too detailed to save. Crop closer to the plaque and try again.") }
        return PlaqueScan(text: text, suggestedName: suggestedName(from: text), imageData: archived,
                          uncertainLines: candidates.filter { $0.confidence < 0.65 }.count)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "CarguyPlaque", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
