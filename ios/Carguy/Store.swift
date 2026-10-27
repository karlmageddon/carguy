import Foundation
import SwiftUI

@MainActor final class StudyStore: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var message = ""
    @Published var busy = false
    @Published var diskFailed = false
    private let file: URL
    var endpoint: String { UserDefaults.standard.string(forKey: "apiURL") ?? "" }

    init() {
        file = URL.documentsDirectory.appending(path: "carguy.json")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
            } else { snapshot = .starter; persist() }
        } catch { diskFailed = true; message = "Could not open saved study data. Your file has been preserved: \(error.localizedDescription)" }
    }
    func persist() {
        guard !diskFailed else { return }
        do { try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { message = "Could not save study data: \(error.localizedDescription)" }
    }
    func saveCar(_ car: Car) {
        var car = car
        if let old = snapshot.cars.first(where: { $0.id == car.id }), old.exhibitId != car.exhibitId, let previous = old.exhibitId {
            car.previousExhibitIds = Array(Set(old.previousExhibitIds + [previous])).sorted()
        }
        car.updatedAt = Date().timeIntervalSince1970
        if let index = snapshot.cars.firstIndex(where: { $0.id == car.id }) { snapshot.cars[index] = car }
        else { snapshot.cars.append(car) }
        persist()
    }
    func saveExhibit(_ name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        snapshot.exhibits.append(Exhibit(name: name)); persist()
    }
    func report(_ fact: Fact, reason: String) {
        snapshot.reports.append(FactReport(factId: fact.id, factRevision: fact.revision, reason: reason))
        if let i = snapshot.facts.firstIndex(where: { $0.id == fact.id }) { snapshot.facts[i].status = "flagged" }
        persist()
    }
    var availableFacts: [Fact] {
        let cars = Set(snapshot.cars.filter { !$0.removed }.map(\.id))
        return snapshot.facts.filter { $0.status == "published" && cars.contains($0.carId) }
    }
    func queue(exhibit: String?, now: Date = Date()) -> [Fact] {
        let cars = Set(snapshot.cars.filter { exhibit == nil || $0.exhibitId == exhibit }.map(\.id))
        return availableFacts.filter { cars.contains($0.carId) && Learning.due($0, attempts: snapshot.attempts) <= now }
            .sorted { Learning.due($0, attempts: snapshot.attempts) < Learning.due($1, attempts: snapshot.attempts) }
    }
    func record(fact: Fact, response: String, sessionId: String) -> Bool {
        let correct = Learning.grade(response, fact: fact)
        snapshot.attempts.append(Attempt(sessionId: sessionId, factId: fact.id, factRevision: fact.revision, response: response, correct: correct))
        persist(); return correct
    }
    func complete(sessionId: String) {
        let attempts = snapshot.attempts.filter { $0.sessionId == sessionId }
        guard !attempts.isEmpty, !snapshot.sessions.contains(where: { $0.id == sessionId }) else { return }
        let now = Date()
        snapshot.sessions.append(StudySession(id: sessionId, attemptIds: attempts.map(\.id), completedAt: now.timeIntervalSince1970, studyDay: Learning.day(now), timeZone: TimeZone.current.identifier))
        persist()
    }
    private func request<T: Decodable>(_ path: String, body: Data? = nil, post: Bool = false) async throws -> T {
        guard let root = URL(string: endpoint), root.scheme == "https", root.host != nil, root.user == nil, root.password == nil, root.query == nil, root.fragment == nil else {
            throw NSError(domain: "Carguy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set a valid HTTPS API URL in Settings."])
        }
        var request = URLRequest(url: root.appending(path: path))
        request.httpMethod = post ? "POST" : "GET"
        request.timeoutInterval = 180
        request.setValue("Bearer " + DeviceToken.read(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "Carguy", code: status, userInfo: [NSLocalizedDescriptionKey: "API request failed (\(status)). Check pairing, connectivity and backend research configuration. Local study data is retained."])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func merge(_ remote: Snapshot) {
        var merged = remote
        for car in snapshot.cars {
            if let i = merged.cars.firstIndex(where: { $0.id == car.id }) {
                if car.updatedAt > merged.cars[i].updatedAt { merged.cars[i] = car }
            } else { merged.cars.append(car) }
        }
        for exhibit in snapshot.exhibits {
            if let i = merged.exhibits.firstIndex(where: { $0.id == exhibit.id }) {
                if exhibit.updatedAt > merged.exhibits[i].updatedAt { merged.exhibits[i] = exhibit }
            } else { merged.exhibits.append(exhibit) }
        }
        merged.attempts += snapshot.attempts.filter { local in !remote.attempts.contains { $0.id == local.id } }
        merged.sessions += snapshot.sessions.filter { local in !remote.sessions.contains { $0.id == local.id } }
        merged.reports += snapshot.reports.filter { local in !remote.reports.contains { $0.id == local.id } }
        for report in merged.reports where ["pending", "researching", "unresolved"].contains(report.status) {
            if let i = merged.facts.firstIndex(where: { $0.id == report.factId && $0.revision == report.factRevision }) { merged.facts[i].status = "flagged" }
        }
        snapshot = merged; persist()
    }
    private func upload() async throws {
        // Ordered, bounded batches stay below Firestore's 450-write transaction guard.
        let captured = snapshot
        for kind in 0..<5 {
            let count = [captured.exhibits.count, captured.cars.count, captured.attempts.count, captured.sessions.count, captured.reports.count][kind]
            for offset in stride(from: 0, to: count, by: 100) {
                var payload = SyncRequest(cars: [], exhibits: [], attempts: [], sessions: [], reports: [])
                let end = min(offset + 100, count)
                switch kind {
                case 0: payload.exhibits = Array(captured.exhibits[offset..<end])
                case 1: payload.cars = Array(captured.cars[offset..<end])
                case 2: payload.attempts = Array(captured.attempts[offset..<end])
                case 3: payload.sessions = Array(captured.sessions[offset..<end])
                default: payload.reports = Array(captured.reports[offset..<end])
                }
                let remote: Snapshot = try await request("v1/sync", body: JSONEncoder().encode(payload), post: true)
                merge(remote)
            }
        }
        let remote: Snapshot = try await request("v1/snapshot")
        merge(remote)
    }
    func sync() async {
        guard !busy, !diskFailed else { return }; busy = true; defer { busy = false }
        do { try await upload(); message = "Synced. Study is available offline." }
        catch { message = error.localizedDescription }
    }
    func research(carId: String) async {
        await perform("v1/cars/\(carId)/research")
    }
    func review(reportId: String) async {
        await perform("v1/reports/\(reportId)/review")
    }
    private func perform(_ path: String) async {
        guard !busy, !diskFailed else { return }; busy = true; defer { busy = false }
        do {
            try await upload()
            let remote: Snapshot = try await request(path, post: true)
            merge(remote); message = "Research updated. See the car's facts and identification notes."
        } catch { message = error.localizedDescription }
    }
}
