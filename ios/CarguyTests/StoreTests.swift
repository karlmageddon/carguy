import XCTest
@testable import Carguy

final class StoreTests: XCTestCase {
    @MainActor private func makeStore() -> (StudyStore, URL) {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = StudyStore(file: file)
        XCTAssertFalse(store.diskFailed)
        return (store, file)
    }
    private func encodedSnapshot(_ snapshot: Snapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }
    @MainActor private func assertUnchanged(_ store: StudyStore, at url: URL, snapshot: Data, disk: Data,
                                          file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try encodedSnapshot(store.snapshot), snapshot, file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: url), disk, file: file, line: line)
    }
    private var fact: Fact {
        Fact(id: "validation-fact", carId: "ford-model-t", revision: 1, status: "published", checkedAt: 0,
             category: "technical", statement: "Fixture", prompt: "Fixture question?", answer: "correct",
             acceptedAnswers: [], choices: ["correct", "wrong"], explanation: "Fixture",
             sources: [Source(title: "Fixture", url: "https://example.org")], numericAnswer: nil)
    }
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
    @MainActor func testExhibitNamesUseTrimmedUnicodeScalarLimits() throws {
        let (store, file) = makeStore()
        defer { try? FileManager.default.removeItem(at: file) }
        let accepted = [String(repeating: "x", count: 120), String(repeating: "🚗", count: 120),
                        String(repeating: "e\u{301}", count: 60)]
        for name in accepted {
            XCTAssertTrue(store.saveExhibit(" \n" + name + "\t "))
            XCTAssertEqual(store.snapshot.exhibits.last?.name, name)
        }
        let snapshot = try encodedSnapshot(store.snapshot)
        let disk = try Data(contentsOf: file)
        let rejected = ["", " \t\n", String(repeating: "x", count: 121),
                        String(repeating: "🚗", count: 121), String(repeating: "e\u{301}", count: 61)]
        for name in rejected {
            XCTAssertFalse(store.saveExhibit(name))
            try assertUnchanged(store, at: file, snapshot: snapshot, disk: disk)
        }
        XCTAssertEqual(StudyStore(file: file).snapshot.exhibits.map(\.name), accepted)
    }
    @MainActor func testResponseValidationPreservesHistoryAndDistinguishesWrongAnswers() throws {
        let (store, file) = makeStore()
        defer { try? FileManager.default.removeItem(at: file) }
        store.snapshot.facts = [fact]
        store.persist()
        XCTAssertEqual(store.record(fact: fact, response: "correct", sessionId: "validation-session"), true)
        XCTAssertEqual(store.record(fact: fact, response: "wrong", sessionId: "validation-session"), false)
        let accepted = [String(repeating: "x", count: 1000), String(repeating: "🚗", count: 1000),
                        String(repeating: "e\u{301}", count: 500)]
        for response in accepted {
            XCTAssertEqual(store.record(fact: fact, response: response, sessionId: "validation-session"), false)
            XCTAssertEqual(store.snapshot.attempts.last?.response, response)
        }
        store.busy = true
        XCTAssertEqual(store.record(fact: fact, response: "correct", sessionId: "validation-session"), true)
        store.busy = false
        let snapshot = try encodedSnapshot(store.snapshot)
        let disk = try Data(contentsOf: file)
        let rejected = ["", " \t\n", String(repeating: "x", count: 1001),
                        String(repeating: "🚗", count: 1001), String(repeating: "e\u{301}", count: 501)]
        for response in rejected {
            XCTAssertNil(store.record(fact: fact, response: response, sessionId: "validation-session"))
            try assertUnchanged(store, at: file, snapshot: snapshot, disk: disk)
        }
        XCTAssertEqual(StudyStore(file: file).snapshot.attempts, store.snapshot.attempts)
        XCTAssertEqual(store.snapshot.attempts.count, 6)
    }
    @MainActor func testBusyCarSavesLeaveDraftsAvailableForRetry() throws {
        let (store, file) = makeStore()
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(store.saveExhibit("Original exhibit"))
        XCTAssertTrue(store.saveExhibit("New exhibit"))
        let originalExhibit = store.snapshot.exhibits[0].id
        let newExhibit = store.snapshot.exhibits[1].id
        var original = store.snapshot.cars[0]
        original.exhibitId = originalExhibit
        XCTAssertTrue(store.saveCar(original))
        var draft = store.snapshot.cars[0]
        draft.name = "Updated car"
        draft.notes = "Updated identification notes"
        draft.exhibitId = newExhibit
        draft.photoData = Data([0xff, 0xd8, 0xff, 0xd9]).base64EncodedString()
        let added = Car(name: "New car", exhibitId: newExhibit)
        let snapshot = try encodedSnapshot(store.snapshot)
        let disk = try Data(contentsOf: file)
        store.busy = true
        XCTAssertFalse(store.saveCar(draft))
        try assertUnchanged(store, at: file, snapshot: snapshot, disk: disk)
        XCTAssertFalse(store.saveCar(added))
        try assertUnchanged(store, at: file, snapshot: snapshot, disk: disk)
        store.busy = false
        XCTAssertTrue(store.saveCar(draft))
        XCTAssertTrue(store.saveCar(added))
        let saved = try XCTUnwrap(store.snapshot.cars.first { $0.id == draft.id })
        XCTAssertEqual(saved.name, draft.name)
        XCTAssertEqual(saved.notes, draft.notes)
        XCTAssertEqual(saved.photoData, draft.photoData)
        XCTAssertEqual(saved.exhibitId, newExhibit)
        XCTAssertEqual(saved.previousExhibitIds, [originalExhibit])
        XCTAssertTrue(store.snapshot.cars.contains { $0.id == added.id })
        XCTAssertEqual(StudyStore(file: file).snapshot.cars, store.snapshot.cars)
    }
    @MainActor func testCarSavesRejectStorageFailureWithoutMutation() throws {
        let (store, file) = makeStore()
        defer { try? FileManager.default.removeItem(at: file) }
        var draft = store.snapshot.cars[0]
        draft.name = "Unsaved edit"
        let snapshot = try encodedSnapshot(store.snapshot)
        let disk = try Data(contentsOf: file)
        store.diskFailed = true
        XCTAssertFalse(store.saveCar(draft))
        try assertUnchanged(store, at: file, snapshot: snapshot, disk: disk)
        XCTAssertFalse(store.saveCar(Car(name: "Unsaved new car")))
        try assertUnchanged(store, at: file, snapshot: snapshot, disk: disk)
    }
}
