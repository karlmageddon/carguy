import XCTest
@testable import Carguy

final class PhotoTests: XCTestCase {
    func testRotationCyclesIndependentlyForEachCarAndHandlesMissingPhotos() {
        var rotation = CarPhotoRotation()
        XCTAssertEqual(rotation.nextIndex(carId: "ford", count: 3), 0)
        XCTAssertEqual(rotation.nextIndex(carId: "ford", count: 3), 1)
        XCTAssertEqual(rotation.nextIndex(carId: "lancia", count: 5), 0)
        XCTAssertEqual(rotation.nextIndex(carId: "ford", count: 3), 2)
        XCTAssertEqual(rotation.nextIndex(carId: "ford", count: 3), 0)
        XCTAssertEqual(rotation.nextIndex(carId: "missing", count: 0), 0)
        XCTAssertEqual(rotation.nextIndex(carId: "ford", count: 1), 0)
    }

    func testLegacyResearchDecodesWithoutGallery() throws {
        let data = Data(#"{"carId":"ford","status":"ready","message":"Saved","updatedAt":0}"#.utf8)
        let state = try JSONDecoder().decode(ResearchState.self, from: data)
        XCTAssertNil(state.photos)
        XCTAssertNil(state.photoMessage)
    }

    @MainActor func testGalleryBytesAndCreditPersistAcrossOfflineRestart() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = StudyStore(file: file)
        let data = Data(#"{"carId":"ford-model-t","status":"ready","message":"Saved","updatedAt":0,"photos":[{"url":"https://upload.wikimedia.org/car.jpg","sourceUrl":"https://commons.wikimedia.org/wiki/File:Car.jpg","caption":"Representative model","attribution":"Photographer","license":"CC0","licenseUrl":"https://creativecommons.org/publicdomain/zero/1.0/","imageData":"/9j/"}]}"#.utf8)
        store.snapshot.research = [try JSONDecoder().decode(ResearchState.self, from: data)]
        store.persist()
        let restarted = StudyStore(file: file)
        XCTAssertFalse(restarted.diskFailed)
        XCTAssertEqual(restarted.photos(for: "ford-model-t"), store.photos(for: "ford-model-t"))
        XCTAssertEqual(restarted.photos(for: "ford-model-t").first?.imageData, "/9j/")
        XCTAssertEqual(restarted.photos(for: "ford-model-t").first?.attribution, "Photographer")
    }
}
