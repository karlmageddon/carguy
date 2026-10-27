import SwiftUI

struct StudyHome: View {
    @EnvironmentObject var store: StudyStore
    @State private var minutes = 10
    @State private var mode = "Multiple choice"
    @State private var exhibit: String?
    @State private var studying = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Your progress") {
                    let streak = Learning.streak(store.snapshot.sessions)
                    Label("\(streak.days) day streak", systemImage: "flame")
                    Text("\(streak.freezesLeft) of 3 monthly freezes remaining")
                    Text("\(store.queue(exhibit: exhibit).count) facts due · \(store.snapshot.sessions.count) completed sessions")
                    Text("Freezes automatically cover missed past days, with three available per calendar month. They preserve your streak without adding study days.").font(.caption)
                }
                Section("Plan a session") {
                    Stepper("\(minutes) minutes", value: $minutes, in: 5...30, step: 5)
                    Picker("Quiz style", selection: $mode) {
                        Text("Multiple choice").tag("Multiple choice")
                        Text("Typed recall").tag("Typed recall")
                    }
                    Picker("Exhibit", selection: $exhibit) {
                        Text("All exhibits").tag(nil as String?)
                        ForEach(store.snapshot.exhibits.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Start studying") { studying = true }
                        .disabled(store.queue(exhibit: exhibit).isEmpty || store.diskFailed)
                    if store.queue(exhibit: exhibit).isEmpty {
                        Text("No facts due. Research cars in Garage, sync your library, or come back when your next review is due.")
                    }
                }
                Section("Offline study") {
                    Text("Downloaded facts and your selected photos stay on this device. Answers sync when you tap Sync. Sources are visible in fact details, after you leave a quiz.")
                    Button("Sync library") { Task { await store.sync() } }.disabled(store.busy)
                }
            }
            .navigationTitle("Study")
            .fullScreenCover(isPresented: $studying) { QuizView(minutes: minutes, typed: mode == "Typed recall", exhibit: exhibit) }
        }
    }
}
struct QuizView: View {
    @EnvironmentObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    let minutes: Int
    let typed: Bool
    let exhibit: String?
    @State private var sessionId = UUID().uuidString
    @State private var deadline = Date()
    @State private var fact: Fact?
    @State private var choices: [String] = []
    @State private var response = ""
    @State private var result: Bool?
    @State private var finished = false
    @State private var correctCount = 0
    @State private var answerCount = 0
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if finished {
                        Text("Session complete").font(.largeTitle.bold())
                        Text("\(correctCount) of \(answerCount) correct")
                        Text(answerCount == 0 ? "No answers recorded. This session did not count toward your streak." : "Progress saved on this device. Sync when online.")
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    } else {
                        Text("\(max(0, Int(deadline.timeIntervalSince(now)))) seconds remaining").monospacedDigit().accessibilityLabel("Time remaining")
                        if let fact {
                            if let car = store.snapshot.cars.first(where: { $0.id == fact.carId }) {
                                Text(car.name).font(.headline)
                                CarPhoto(car: car)
                            }
                            Text(fact.prompt).font(.title2)
                            if typed {
                                TextField("Your answer", text: $response).textFieldStyle(.roundedBorder)
                                    .disabled(result != nil).onSubmit { submit() }
                                Button("Check answer") { submit() }
                                    .disabled(result != nil || response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            } else {
                                ForEach(choices, id: \.self) { choice in
                                    Button(choice) { response = choice; submit() }.buttonStyle(.bordered).disabled(result != nil)
                                }
                            }
                            if let result {
                                Label(result ? "Correct" : "Keep practicing", systemImage: result ? "checkmark.circle" : "arrow.clockwise")
                                Text("Answer: \(fact.answer)")
                                Button("Next question") { advance() }.buttonStyle(.borderedProminent)
                                Button("Flag this question") {
                                    store.report(fact, reason: "Flagged during quiz: answer or wording appears incorrect.")
                                    advance()
                                }
                            }
                        } else {
                            Text("You're caught up.").font(.title2)
                            Text("Any missed answers will become due again after a minute. You can finish now or wait for another review.")
                            Button("Check for due questions") { advance() }
                        }
                    }
                }.padding()
            }
            .navigationTitle(typed ? "Typed recall" : "Multiple choice")
            .toolbar {
                if !finished { Button("Finish") { finish() } }
            }
            .interactiveDismissDisabled()
            .onAppear { deadline = Date().addingTimeInterval(Double(minutes * 60)); advance() }
            .onReceive(timer) { date in
                now = date
                if !finished && date >= deadline { finish() }
            }
        }
    }
    private func submit() {
        guard result == nil, let fact, Date() < deadline,
              store.availableFacts.contains(where: { $0.id == fact.id && $0.revision == fact.revision }) else { advance(); return }
        let correct = store.record(fact: fact, response: response, sessionId: sessionId)
        result = correct; answerCount += 1
        if correct { correctCount += 1 }
    }
    private func advance() {
        fact = store.queue(exhibit: exhibit).first
        choices = fact?.choices.shuffled() ?? []
        response = ""; result = nil
    }
    private func finish() { store.complete(sessionId: sessionId); finished = true }
}
