import Foundation

enum Learning {
    static var studyCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let chars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || ".+-".unicodeScalars.contains($0) ? String($0) : " " }.joined()
        return chars.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func grade(_ response: String, fact: Fact) -> Bool {
        let answer = normalize(response)
        guard !answer.isEmpty else { return false }
        if ([fact.answer] + fact.acceptedAnswers).map(normalize).contains(answer) { return true }
        guard let rule = fact.numericAnswer,
              let regex = try? NSRegularExpression(pattern: #"^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*(.*?)\s*$"#),
              let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)),
              let numberRange = Range(match.range(at: 1), in: response),
              let unitRange = Range(match.range(at: 2), in: response),
              let number = Double(response[numberRange]) else { return false }
        return rule.units.contains { normalize($0.unit) == normalize(String(response[unitRange])) && abs(number * $0.multiplier - rule.value) <= rule.tolerance + max(abs(rule.value), 1) * 1e-12 }
    }
    static func due(_ fact: Fact, attempts: [Attempt]) -> Date {
        let history = attempts.filter { $0.factId == fact.id && $0.factRevision == fact.revision }.sorted { $0.answeredAt < $1.answeredAt }
        guard let last = history.last else { return .distantPast }
        var successes = 0
        for attempt in history { successes = attempt.correct ? successes + 1 : 0 }
        let seconds = successes == 0 ? 60.0 : min(30, pow(2, Double(min(successes - 1, 5)))) * 86400
        return Date(timeIntervalSince1970: last.answeredAt + seconds)
    }
    static func day(_ date: Date, calendar: Calendar = Learning.studyCalendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    // Missing past days consume a freeze in that calendar month. No banking; today is never frozen.
    static func streak(_ sessions: [StudySession], now: Date = Date(), calendar: Calendar = Learning.studyCalendar) -> (days: Int, freezesLeft: Int) {
        let studied = Set(sessions.map(\.studyDay))
        guard let first = studied.min() else { return (0, 3) }
        let parts = first.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let start = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return (0, 3) }
        var cursor = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        var count = 0
        var used: [String: Int] = [:]
        while cursor <= today {
            let key = day(cursor, calendar: calendar)
            let month = String(key.prefix(7))
            if studied.contains(key) { count += 1 }
            else if cursor < today {
                if count > 0 && used[month, default: 0] < 3 { used[month, default: 0] += 1 }
                else { count = 0 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return (count, 3 - used[String(day(now, calendar: calendar).prefix(7)), default: 0])
    }
}
