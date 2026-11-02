import Foundation

struct JourneyItem: Identifiable, Hashable {
    let fact: Fact
    let isNew: Bool
    var id: String { "\(fact.id):\(fact.revision)" }
}

struct JourneyPlan {
    let title: String
    let subtitle: String
    let car: Car?
    let items: [JourneyItem]
}

enum JourneyFamiliarity: String {
    case new, introduced, practicing, familiar
    var label: String { rawValue.capitalized }
}

/// Builds a small, finite lesson from the sourced facts already saved on the device.
/// Attempts at the current fact revision determine progress; viewing a teaching card
/// alone never marks an idea as learned or affects its review schedule.
enum JourneyPlanner {
    private enum Chapter: Int, CaseIterable {
        case meet, story, engineering
        var title: String {
            switch self {
            case .meet: return "Meet the car"
            case .engineering: return "Under the skin"
            case .story: return "The human story"
            }
        }
        init(category: String) {
            switch category.lowercased() {
            case "technical": self = .engineering
            case "story": self = .story
            default: self = .meet
            }
        }
    }

    static func plan(snapshot: Snapshot, exhibitIds: Set<String?>, now: Date = Date()) -> JourneyPlan? {
        let cars = snapshot.cars.filter { !$0.removed && exhibitIds.contains($0.exhibitId) }
        let carIds = Set(cars.map(\.id))
        let ideas = uniqueIdeas(facts: snapshot.facts.filter { eligible($0) && carIds.contains($0.carId) },
                                cars: cars, attempts: snapshot.attempts)
        let facts = ideas.map(\.fact)
        func history(_ fact: Fact) -> [Attempt] { ideas.first { $0.fact.id == fact.id && $0.fact.revision == fact.revision }?.history ?? [] }
        func due(_ fact: Fact) -> Date { Learning.due(fact, attempts: history(fact)) }
        let review = facts.filter { !history($0).isEmpty && due($0) <= now }
            .sorted {
                let first = due($0), second = due($1)
                return first == second ? $0.id < $1.id : first < second
            }
        let unseen = facts.filter { history($0).isEmpty }
        // Continue a car that is already introduced before opening another one.
        let candidates = cars.filter { car in unseen.contains { $0.carId == car.id } }.sorted { first, second in
            let firstStarted = facts.contains { $0.carId == first.id && !history($0).isEmpty }
            let secondStarted = facts.contains { $0.carId == second.id && !history($0).isEmpty }
            if firstStarted != secondStarted { return firstStarted }
            if first.name != second.name { return first.name.localizedStandardCompare(second.name) == .orderedAscending }
            return first.id < second.id
        }
        if let car = candidates.first {
            let carFacts = unseen.filter { $0.carId == car.id }
            let chapter = Chapter.allCases.first { chapter in carFacts.contains { Chapter(category: $0.category) == chapter } }!
            let newFacts = carFacts.filter { Chapter(category: $0.category) == chapter }.sorted { first, second in
                if chapter == .meet {
                    let firstBasic = first.category.lowercased() == "fundamentals"
                    let secondBasic = second.category.lowercased() == "fundamentals"
                    if firstBasic != secondBasic { return firstBasic }
                }
                return first.id < second.id
            }.prefix(3)
            let reviews = review.prefix(2)
            let items = reviews.map { JourneyItem(fact: $0, isNew: false) } + newFacts.map { JourneyItem(fact: $0, isNew: true) }
            let newLabel = "\(newFacts.count) new \(newFacts.count == 1 ? "idea" : "ideas")"
            let subtitle = reviews.isEmpty ? newLabel : "\(reviews.count) review \(reviews.count == 1 ? "question" : "questions") · " + newLabel
            return JourneyPlan(title: chapter.title, subtitle: subtitle, car: car, items: items)
        }
        guard !review.isEmpty else { return nil }
        let items = review.prefix(5).map { JourneyItem(fact: $0, isNew: false) }
        return JourneyPlan(title: "A lap around your garage", subtitle: "\(items.count) review \(items.count == 1 ? "question" : "questions")", car: nil, items: items)
    }

    static func hasEligibleFacts(car: Car, facts: [Fact]) -> Bool {
        !car.removed && facts.contains { $0.carId == car.id && eligible($0) }
    }

    static func familiarity(car: Car, facts: [Fact], attempts: [Attempt], calendar: Calendar = Learning.studyCalendar) -> JourneyFamiliarity {
        let current = uniqueIdeas(facts: facts.filter { $0.carId == car.id && eligible($0) }, cars: [car], attempts: attempts)
        guard !current.isEmpty else { return .new }
        let histories = current.map(\.history)
        guard histories.contains(where: { !$0.isEmpty }) else { return .new }
        guard histories.allSatisfy({ !$0.isEmpty }) else { return .introduced }
        let remembered = histories.allSatisfy { history in
            guard history.last?.correct == true else { return false }
            let days = Set(history.filter(\.correct).map { Learning.day(Date(timeIntervalSince1970: $0.answeredAt), calendar: calendar) })
            return days.count >= 2
        }
        return remembered ? .familiar : .practicing
    }

    private struct Idea {
        var fact: Fact
        var history: [Attempt]
    }

    /// Deduplication changes only the lesson projection. Source records and attempts
    /// remain untouched so every recorded answer retains its server identity/revision.
    private static func uniqueIdeas(facts: [Fact], cars: [Car], attempts: [Attempt]) -> [Idea] {
        var groups: [[Fact]] = []
        for fact in facts.sorted(by: { $0.id == $1.id ? $0.revision < $1.revision : $0.id < $1.id }) {
            let name = cars.first { $0.id == fact.carId }?.name ?? ""
            if let index = groups.firstIndex(where: { group in group.allSatisfy { equivalent(fact, $0, carName: name) } }) {
                groups[index].append(fact)
            } else { groups.append([fact]) }
        }
        var result: [Idea] = []
        for group in groups {
            let ranked = group.sorted { first, second in
                if first.statement.count != second.statement.count { return first.statement.count > second.statement.count }
                if first.explanation.count != second.explanation.count { return first.explanation.count > second.explanation.count }
                return first.id < second.id
            }
            let representative = ranked[0]
            var history: [Attempt] = []
            for fact in group {
                for attempt in currentAttempts(fact, attempts: attempts) {
                    var mapped = attempt
                    mapped.factId = representative.id
                    mapped.factRevision = representative.revision
                    history.append(mapped)
                }
            }
            history.sort { first, second in
                first.answeredAt == second.answeredAt ? first.id < second.id : first.answeredAt < second.answeredAt
            }
            result.append(Idea(fact: representative, history: history))
        }
        return result
    }

    private static func equivalent(_ first: Fact, _ second: Fact, carName: String) -> Bool {
        guard first.carId == second.carId, Chapter(category: first.category) == Chapter(category: second.category) else { return false }
        // Never inherit an old revision merely because its wording resembles the replacement.
        if first.id == second.id { return first.revision == second.revision }
        let firstTopic = topic(first.prompt, carName: carName)
        let secondTopic = topic(second.prompt, carName: carName)
        // A production run expressed as years and the same run expressed as precise
        // dates are one introductory idea. Do not generalize date precision elsewhere.
        if firstTopic == ["production"], secondTopic == ["production"],
           let years = productionYears(first.answer), years == productionYears(second.answer) { return true }
        guard answerKey(first.answer) == answerKey(second.answer), !answerKey(first.answer).isEmpty else { return false }
        if Learning.normalize(first.prompt) == Learning.normalize(second.prompt) ||
            Learning.normalize(first.statement) == Learning.normalize(second.statement) { return true }
        // Exact topic-token agreement is deliberately conservative: top/cruising speed,
        // dry/wet weight, different people, and story events stay separate.
        return !firstTopic.isEmpty && firstTopic == secondTopic
    }

    private static let rangeWords: Set<String> = ["from", "to", "through", "until", "between", "and", "roughly", "about", "approximately"]
    private static func answerKey(_ answer: String) -> String {
        Learning.normalize(answer).split(separator: " ").map(String.init).filter { !rangeWords.contains($0) }.joined(separator: " ")
    }
    private static func productionYears(_ answer: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:18|19|20)\d{2}\b"#) else { return nil }
        let years = regex.matches(in: answer, range: NSRange(answer.startIndex..., in: answer)).compactMap { match in
            Range(match.range, in: answer).map { String(answer[$0]) }
        }
        return years.count == 2 && years[0] != years[1] ? years : nil
    }
    private static func topic(_ prompt: String, carName: String) -> Set<String> {
        let carWords = Set(Learning.normalize(carName).split(separator: " ").map(String.init))
        let generic: Set<String> = ["what", "which", "when", "who", "where", "how", "was", "were", "is", "are", "the", "a", "an", "of", "for", "in", "at", "did", "does", "do", "has", "have", "its", "it", "car", "vehicle", "model", "years", "year", "dates", "date", "period", "range", "span", "run", "official", "start", "end"]
        return Set(Learning.normalize(prompt).split(separator: " ").map(String.init).filter {
            !carWords.contains($0) && !generic.contains($0) && !rangeWords.contains($0)
        }.map { word in
            ["produce", "produced", "producing", "production"].contains(word) ? "production" : word
        })
    }

    private static func eligible(_ fact: Fact) -> Bool {
        fact.status == "published" && !fact.sources.isEmpty && fact.choices.count >= 2 &&
            fact.choices.contains { Learning.grade($0, fact: fact) }
    }

    private static func currentAttempts(_ fact: Fact, attempts: [Attempt]) -> [Attempt] {
        attempts.filter { $0.factId == fact.id && $0.factRevision == fact.revision }
            .sorted { $0.answeredAt == $1.answeredAt ? $0.id < $1.id : $0.answeredAt < $1.answeredAt }
    }
}
