import XCTest
@testable import Carguy

final class StoreTests: XCTestCase {
    @MainActor func testOfflinePersistenceRemovalAndExhibitHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "study.json")
        let first = StudyStore(file: file)
        first.saveExhibit("Original exhibit")
        first.saveExhibit("New exhibit")
        var car = first.snapshot.cars[0]
        car.exhibitId = first.snapshot.exhibits[0].id
        first.saveCar(car)
        car = first.snapshot.cars[0]
        car.exhibitId = first.snapshot.exhibits[1].id
        first.saveCar(car)
        car = first.snapshot.cars[0]
        car.removed = true
        first.saveCar(car)
        let reopened = StudyStore(file: file)
        XCTAssertFalse(reopened.diskFailed)
        XCTAssertTrue(reopened.snapshot.cars[0].removed)
        XCTAssertEqual(reopened.snapshot.cars[0].previousExhibitIds, [first.snapshot.exhibits[0].id])
        XCTAssertEqual(reopened.snapshot.cars.count, 6)
    }
    @MainActor func testCorruptLocalFileIsPreserved() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let original = Data("not a snapshot".utf8)
        try original.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = StudyStore(file: file)
        XCTAssertTrue(store.diskFailed)
        store.persist()
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
