import XCTest
@testable import Carguy

final class LearningTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private func session(_ year: Int, _ month: Int, _ day: Int) -> StudySession {
        let completed = date(year, month, day)
        return StudySession(id: UUID().uuidString, attemptIds: ["a"], completedAt: completed.timeIntervalSince1970, studyDay: Learning.day(completed, calendar: calendar), timeZone: "UTC")
    }
    private var fact: Fact {
        Fact(id: "f", carId: "c", revision: 1, status: "published", checkedAt: 0, category: "technical", statement: "Fixture", prompt: "Displacement in litres?", answer: "4 litres", acceptedAnswers: ["four litres"], choices: ["4 litres", "6 litres", "8 litres", "12 litres"], explanation: "Fixture", sources: [Source(title: "Fixture", url: "https://example.org")], numericAnswer: NumericAnswer(value: 4, tolerance: 0.05, units: [UnitScale(unit: "litres", multiplier: 1), UnitScale(unit: "cc", multiplier: 0.001)]))
    }
    func testRecallAndNumericUnits() {
        XCTAssertTrue(Learning.grade(" FOUR litres ", fact: fact))
        XCTAssertTrue(Learning.grade("4000 cc", fact: fact))
        XCTAssertTrue(Learning.grade("4.04 litres", fact: fact))
        XCTAssertFalse(Learning.grade("4.1 litres", fact: fact))
        XCTAssertFalse(Learning.grade("4", fact: fact))
        XCTAssertFalse(Learning.grade("", fact: fact))
    }
    func testSpacingResetsForNewRevisionAndMisses() {
        let correct = Attempt(sessionId: "s", factId: "f", factRevision: 1, response: "4 litres", correct: true, answeredAt: 100)
        XCTAssertEqual(Learning.due(fact, attempts: [correct]).timeIntervalSince1970, 86500)
        let miss = Attempt(sessionId: "s", factId: "f", factRevision: 1, response: "6 litres", correct: false, answeredAt: 200)
        XCTAssertEqual(Learning.due(fact, attempts: [correct, miss]).timeIntervalSince1970, 260)
        var revised = fact; revised.revision = 2
        XCTAssertEqual(Learning.due(revised, attempts: [correct]), .distantPast)
    }
    func testMonthlyFreezesDoNotBankAndDoNotAddDays() {
        let sessions = [session(2026, 1, 27), session(2026, 1, 31), session(2026, 2, 4)]
        let state = Learning.streak(sessions, now: date(2026, 2, 4), calendar: calendar)
        XCTAssertEqual(state.days, 3)
        XCTAssertEqual(state.freezesLeft, 0)
        let broken = Learning.streak(sessions, now: date(2026, 2, 6), calendar: calendar)
        XCTAssertEqual(broken.days, 0)
        XCTAssertEqual(broken.freezesLeft, 0)
    }
    func testTodayIsNotAutomaticallyFrozen() {
        let state = Learning.streak([session(2026, 1, 1)], now: date(2026, 1, 2), calendar: calendar)
        XCTAssertEqual(state.days, 1)
        XCTAssertEqual(state.freezesLeft, 3)
        let next = Learning.streak([session(2026, 1, 1)], now: date(2026, 1, 3), calendar: calendar)
        XCTAssertEqual(next.days, 1)
        XCTAssertEqual(next.freezesLeft, 2)
    }
    func testStarterIdentityIsUnverifiedAndNeverOverwritesRemoteEdits() {
        let cars = Snapshot.starter.cars
        XCTAssertEqual(cars.count, 6)
        XCTAssertTrue(cars.allSatisfy { $0.updatedAt == 0 })
        XCTAssertFalse(cars[0].name.contains("1905"))
        XCTAssertTrue(cars[0].notes.contains("unverified"))
    }
    func testSnapshotRoundTrip() throws {
        let data = try JSONEncoder().encode(Snapshot.starter)
        XCTAssertEqual(try JSONDecoder().decode(Snapshot.self, from: data).cars.count, 6)
    }
}
