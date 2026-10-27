import Foundation

struct Exhibit: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var archived = false
    var updatedAt = Date().timeIntervalSince1970
}
struct Car: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var notes = ""
    var exhibitId: String?
    var previousExhibitIds: [String] = []
    var removed = false
    var photoData: String?
    var updatedAt = Date().timeIntervalSince1970
}
struct Source: Codable, Hashable { var title: String; var url: String }
struct UnitScale: Codable, Hashable { var unit: String; var multiplier: Double }
struct NumericAnswer: Codable, Hashable { var value: Double; var tolerance: Double; var units: [UnitScale] }
struct Fact: Codable, Identifiable, Hashable {
    var id: String
    var carId: String
    var revision: Int
    var status: String
    var checkedAt: Double
    var category: String
    var statement: String
    var prompt: String
    var answer: String
    var acceptedAnswers: [String]
    var choices: [String]
    var explanation: String
    var sources: [Source]
    var numericAnswer: NumericAnswer?
}
struct Attempt: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var sessionId: String
    var factId: String
    var factRevision: Int
    var response: String
    var correct: Bool
    var answeredAt = Date().timeIntervalSince1970
}
struct StudySession: Codable, Identifiable, Hashable {
    var id: String
    var attemptIds: [String]
    var completedAt: Double
    var studyDay: String
    var timeZone: String
}
struct FactReport: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var factId: String
    var factRevision: Int
    var reason: String
    var createdAt = Date().timeIntervalSince1970
    var status = "pending"
    var resolution = ""
}
struct ResearchState: Codable, Hashable {
    var carId: String
    var status: String
    var message: String
    var photoUrl: String?
    var photoSourceUrl: String?
    var photoCaption: String?
    var updatedAt: Double
}
struct Snapshot: Codable {
    var cars: [Car] = []
    var exhibits: [Exhibit] = []
    var facts: [Fact] = []
    var attempts: [Attempt] = []
    var sessions: [StudySession] = []
    var reports: [FactReport] = []
    var research: [ResearchState] = []
}
struct SyncRequest: Codable {
    var cars: [Car]
    var exhibits: [Exhibit]
    var attempts: [Attempt]
    var sessions: [StudySession]
    var reports: [FactReport]
}

extension Snapshot {
    static var starter: Snapshot {
        var result = Snapshot()
        result.cars = [
            Car(id: "detroit-electric-61", name: "Detroit Electric Model 61 Brougham", notes: "User supplied year 1905 is unverified and may conflict with the Model 61 identification. Verify using museum/primary sources before publishing year-specific facts; request a placard photo if needed."),
            Car(id: "lancia-delta-s4", name: "Lancia Delta S4", notes: "Confirm road Stradale versus competition car and particular exhibited vehicle."),
            Car(id: "duesenberg-1933", name: "1933 Duesenberg", notes: "Model, chassis and coachbuilder unknown. Ask for a placard or identifying photo; do not infer provenance."),
            Car(id: "ford-model-t", name: "Ford Model T", notes: "Year and body style unknown; research model-level facts only until identified."),
            Car(id: "benz-motorwagen", name: "Benz Patent-Motorwagen", notes: "Confirm original versus replica and vehicle number before specific provenance claims."),
            Car(id: "czinger-21c", name: "Czinger 21C", notes: "Confirm variant and production specification.")
        ]
        for index in result.cars.indices { result.cars[index].updatedAt = 0 }
        return result
    }
}
