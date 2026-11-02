import XCTest
@testable import Carguy

final class JourneyTests: XCTestCase {
    private var now: Date { Date(timeIntervalSince1970: 10 * 86400) }
    private func fact(_ id: String, car: String = "a", category: String = "fundamentals", revision: Int = 1, status: String = "published") -> Fact {
        Fact(id: id, carId: car, revision: revision, status: status, checkedAt: 0, category: category,
             statement: "Sourced idea \(id)", prompt: "Which idea \(id)?", answer: "Correct", acceptedAnswers: [],
             choices: ["Correct", "Other"], explanation: "Context", sources: [Source(title: "Museum", url: "https://example.org")], numericAnswer: nil)
    }
    private func attempt(_ fact: Fact, correct: Bool = true, day: Double = 1) -> Attempt {
        Attempt(sessionId: "session", factId: fact.id, factRevision: fact.revision, response: correct ? "Correct" : "Other", correct: correct, answeredAt: day * 86400)
    }
    private func snapshot(facts: [Fact], attempts: [Attempt] = []) -> Snapshot {
        Snapshot(cars: [Car(id: "a", name: "A", exhibitId: "one"), Car(id: "b", name: "B", exhibitId: "two"), Car(id: "c", name: "C")], facts: facts, attempts: attempts)
    }
    func testNewCarBeginsWithShortTeachingChapterBeforeEngineeringAndStories() throws {
        let facts = (0..<4).map { fact("meet-\($0)") } + [fact("engine", category: "technical"), fact("person", category: "story")]
        let plan = try XCTUnwrap(JourneyPlanner.plan(snapshot: snapshot(facts: facts), exhibitIds: ["one"], now: now))
        XCTAssertEqual(plan.title, "Meet the car")
        XCTAssertEqual(plan.car?.id, "a")
        XCTAssertEqual(plan.items.count, 3)
        XCTAssertEqual(plan.subtitle, "3 new ideas")
        XCTAssertTrue(plan.items.allSatisfy { $0.isNew && $0.fact.category == "fundamentals" })
        XCTAssertEqual(plan.items.map(\.fact.id), ["meet-0", "meet-1", "meet-2"])
    }
    func testMeetChapterStartsWithFundamentalsBeforeHistoricalDetail() throws {
        let facts = [fact("a-history", category: "history"), fact("z-basics", category: "fundamentals")]
        let plan = try XCTUnwrap(JourneyPlanner.plan(snapshot: snapshot(facts: facts), exhibitIds: ["one"], now: now))
        XCTAssertEqual(plan.items.map(\.fact.id), ["z-basics", "a-history"])
        XCTAssertEqual(plan.subtitle, "2 new ideas")
    }
    func testDueReviewComesBeforeNewIdeasWithoutSwallowingTheLesson() throws {
        let reviews = (0..<4).map { fact("review-\($0)", car: "b") }
        let facts = reviews + (0..<5).map { fact("new-\($0)") }
        let saved = snapshot(facts: facts, attempts: reviews.map { attempt($0) })
        let plan = try XCTUnwrap(JourneyPlanner.plan(snapshot: saved, exhibitIds: ["one", "two"], now: now))
        XCTAssertEqual(plan.items.count, 5)
        XCTAssertEqual(plan.items.map(\.isNew), [false, false, true, true, true])
        XCTAssertEqual(Set(plan.items.prefix(2).map(\.fact.carId)), ["b"])
    }
    func testContinuesIntroducedCarAndPrioritizesHumanStoryBeforeSpecifications() throws {
        let first = fact("first", car: "b")
        let saved = snapshot(facts: [fact("brand-new"), first, fact("technical", car: "b", category: "technical"), fact("story", car: "b", category: "story")], attempts: [attempt(first, day: 10)])
        let plan = try XCTUnwrap(JourneyPlanner.plan(snapshot: saved, exhibitIds: ["one", "two"], now: now))
        XCTAssertEqual(plan.car?.id, "b")
        XCTAssertEqual(plan.title, "The human story")
        XCTAssertEqual(plan.items.map(\.fact.id), ["story"])
    }
    func testRevisedFactIsNewAndFlaggedRemovedUnselectedOrUnusableFactsAreExcluded() throws {
        let old = fact("revised", revision: 1)
        var saved = snapshot(facts: [fact("revised", revision: 2), fact("flagged", status: "flagged"), fact("other", car: "b"), fact("unassigned", car: "c"), fact("removed", car: "removed")], attempts: [attempt(old)])
        saved.cars.append(Car(id: "removed", name: "Removed", exhibitId: "one", removed: true))
        var unsourced = fact("unsourced"); unsourced.sources = []
        var noCorrectChoice = fact("invalid"); noCorrectChoice.choices = ["Wrong", "Other"]
        saved.facts += [unsourced, noCorrectChoice]
        let plan = try XCTUnwrap(JourneyPlanner.plan(snapshot: saved, exhibitIds: ["one"], now: now))
        XCTAssertEqual(plan.items.map(\.fact.id), ["revised"])
        XCTAssertTrue(plan.items[0].isNew)
        XCTAssertNil(JourneyPlanner.plan(snapshot: saved, exhibitIds: [], now: now))
        let unassigned = try XCTUnwrap(JourneyPlanner.plan(snapshot: saved, exhibitIds: [nil], now: now))
        XCTAssertEqual(unassigned.items.map(\.fact.id), ["unassigned"])
    }
    func testCarCardsUseTheSameFactEligibilityAsLessons() {
        let car = Car(id: "a", name: "A")
        XCTAssertTrue(JourneyPlanner.hasEligibleFacts(car: car, facts: [fact("valid")]))
        var unsourced = fact("unsourced"); unsourced.sources = []
        var invalid = fact("invalid"); invalid.choices = ["Wrong", "Other"]
        XCTAssertFalse(JourneyPlanner.hasEligibleFacts(car: car, facts: [unsourced, invalid, fact("flagged", status: "flagged")]))
        XCTAssertFalse(JourneyPlanner.hasEligibleFacts(car: car, facts: [fact("other", car: "b")]))
        var removed = car; removed.removed = true
        XCTAssertFalse(JourneyPlanner.hasEligibleFacts(car: removed, facts: [fact("valid")]))
    }
    func testReviewOnlyHasFiniteStoppingPointAndRespectsDueDates() throws {
        let facts = (0..<7).map { fact("\($0)") }
        let saved = snapshot(facts: facts, attempts: facts.map { attempt($0) })
        let plan = try XCTUnwrap(JourneyPlanner.plan(snapshot: saved, exhibitIds: ["one"], now: now))
        XCTAssertNil(plan.car)
        XCTAssertEqual(plan.items.count, 5)
        XCTAssertTrue(plan.items.allSatisfy { !$0.isNew })
        XCTAssertNil(JourneyPlanner.plan(snapshot: saved, exhibitIds: ["one"], now: Date(timeIntervalSince1970: 86401)))
    }
    func testEquivalentProductionRangesUseOneRichTeachingIdea() throws {
        var broad = fact("broad")
        broad.prompt = "Between which years was the Ford Model T produced?"
        broad.answer = "1908–1927"
        broad.choices = [broad.answer, "Other"]
        broad.statement = "Production run of the Ford Model T."
        var precise = fact("precise")
        precise.prompt = "What are the official production start and end dates for the Ford Model T?"
        precise.answer = "October 1, 1908 – May 26, 1927."
        precise.choices = [precise.answer, "Other"]
        precise.statement = "The Ford Model T was produced from October 1, 1908 until May 26, 1927."
        let saved = Snapshot(cars: [Car(id: "a", name: "Ford Model T", exhibitId: "one")], facts: [broad, precise])
        let plan = try XCTUnwrap(JourneyPlanner.plan(snapshot: saved, exhibitIds: ["one"], now: now))
        XCTAssertEqual(plan.items.map(\.fact.id), ["precise"])
        XCTAssertEqual(saved.facts.count, 2)
        var reviewed = saved
        reviewed.attempts = [attempt(broad, day: 10)]
        XCTAssertNil(JourneyPlanner.plan(snapshot: reviewed, exhibitIds: ["one"], now: now))
        let later = try XCTUnwrap(JourneyPlanner.plan(snapshot: reviewed, exhibitIds: ["one"], now: now.addingTimeInterval(86401)))
        XCTAssertEqual(later.items.map(\.isNew), [false])
        XCTAssertEqual(later.items.map(\.fact.id), ["precise"])
    }
    func testSameAnswerOnDifferentTopicsAndTechnicalQualifiersStaysSeparate() throws {
        var production = fact("production")
        production.prompt = "Between which years was the Ford Model T produced?"
        production.answer = "1908–1927"; production.choices = [production.answer, "Other"]
        var racing = fact("racing")
        racing.prompt = "Between which years was the Ford Model T entered in this racing series?"
        racing.answer = production.answer; racing.choices = [racing.answer, "Other"]
        var dry = fact("dry", category: "technical")
        dry.prompt = "What is the car's dry weight?"; dry.answer = "900 kg"; dry.choices = [dry.answer, "Other"]
        var wet = fact("wet", category: "technical")
        wet.prompt = "What is the car's wet weight?"; wet.answer = dry.answer; wet.choices = [wet.answer, "Other"]
        let intro = try XCTUnwrap(JourneyPlanner.plan(snapshot: snapshot(facts: [production, racing]), exhibitIds: ["one"], now: now))
        XCTAssertEqual(intro.items.count, 2)
        let engineering = try XCTUnwrap(JourneyPlanner.plan(snapshot: snapshot(facts: [dry, wet]), exhibitIds: ["one"], now: now))
        XCTAssertEqual(engineering.items.count, 2)
    }
    func testDeduplicationDoesNotTransferOldRevisionAttempts() throws {
        var revised = fact("revision", revision: 2)
        revised.prompt = "When did this production period begin?"
        let oldAttempt = Attempt(sessionId: "old", factId: revised.id, factRevision: 1, response: revised.answer, correct: true, answeredAt: now.timeIntervalSince1970)
        let plan = try XCTUnwrap(JourneyPlanner.plan(snapshot: snapshot(facts: [revised], attempts: [oldAttempt]), exhibitIds: ["one"], now: now))
        XCTAssertEqual(plan.items.map(\.isNew), [true])
    }
    func testFamiliarityRequiresLaterDayRetrievalAndCurrentRevision() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let car = Car(id: "a", name: "A")
        let one = fact("one"), two = fact("two")
        func state(_ attempts: [Attempt], facts: [Fact] = []) -> JourneyFamiliarity {
            JourneyPlanner.familiarity(car: car, facts: facts.isEmpty ? [one, two] : facts, attempts: attempts, calendar: calendar)
        }
        XCTAssertEqual(state([]), .new)
        XCTAssertEqual(state([attempt(one)]), .introduced)
        let initial = [attempt(one), attempt(two)]
        XCTAssertEqual(state(initial), .practicing)
        XCTAssertEqual(state(initial + [attempt(one, day: 1.5), attempt(two, day: 1.5)]), .practicing)
        let repeated = initial + [attempt(one, day: 2), attempt(two, day: 2)]
        XCTAssertEqual(state(repeated), .familiar)
        XCTAssertEqual(state(repeated + [attempt(one, correct: false, day: 3)]), .practicing)
        XCTAssertEqual(state(repeated, facts: [fact("one", revision: 2), two]), .introduced)
    }
}
