import XCTest
import UIKit
@testable import Carguy

final class PlaqueTests: XCTestCase {
    func testSuggestedNameUsesPlaqueHeadingAndSeparateYear() {
        XCTAssertEqual(PlaqueRecognition.suggestedName(from: "PETERSEN AUTOMOTIVE MUSEUM\n1931\nBUGATTI TYPE 51\nOn loan"), "1931 BUGATTI TYPE 51")
        XCTAssertEqual(PlaqueRecognition.suggestedName(from: "Czinger 21C\n2021\nA hybrid hypercar"), "2021 Czinger 21C")
        XCTAssertEqual(PlaqueRecognition.suggestedName(from: "Museum collection\n1967 Ford Mustang\nCourtesy of owner"), "1967 Ford Mustang")
        XCTAssertEqual(PlaqueRecognition.suggestedName(from: "\n \n"), "")
    }

    @MainActor func testOnDeviceRecognitionReadsActualImageAndKeepsCompactPlaqueCopy() throws {
        let size = CGSize(width: 1800, height: 1100)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            let text = "1931 TEST MOTORS ROADSTER\nEight cylinders\nMuseum plaque test fixture"
            (text as NSString).draw(in: CGRect(x: 80, y: 100, width: 1640, height: 900), withAttributes: [
                .font: UIFont.systemFont(ofSize: 68), .foregroundColor: UIColor.black
            ])
        }
        let scan = try PlaqueRecognition.recognize(XCTUnwrap(image.jpegData(compressionQuality: 0.95)))
        XCTAssertTrue(scan.text.contains("1931"))
        XCTAssertTrue(scan.text.uppercased().contains("ROADSTER"))
        XCTAssertTrue(scan.suggestedName.contains("1931"))
        XCTAssertLessThanOrEqual(scan.imageData.count, 250 * 1024)
        XCTAssertNotNil(UIImage(data: scan.imageData))
    }

    func testInvalidImageFailsWithoutInventingPlaqueText() {
        XCTAssertThrowsError(try PlaqueRecognition.recognize(Data("not an image".utf8)))
    }

    @MainActor func testPlaqueAndReviewedNotesPersistSeparatelyFromQuizPhoto() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = StudyStore(file: file)
        var car = Car(name: "Plaque fixture")
        car.notes = PlaqueRecognition.notesPrefix + "Reviewed fixture text"
        car.plaquePhotoData = Data([0xff, 0xd8, 0xff, 0xd9]).base64EncodedString()
        XCTAssertTrue(store.saveCar(car))
        let restored = try XCTUnwrap(StudyStore(file: file).snapshot.cars.first { $0.id == car.id })
        XCTAssertEqual(restored.plaquePhotoData, car.plaquePhotoData)
        XCTAssertEqual(restored.notes, car.notes)
        XCTAssertNil(restored.photoData)
    }
}
