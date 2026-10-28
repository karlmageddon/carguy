import SwiftUI

struct StudyHome: View {
    @EnvironmentObject var store: StudyStore
    @State private var minutes = 5
    @State private var mode = "Multiple choice"
    @State private var exhibit: String?
    @State private var studying = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("CARGUY").font(.title2.weight(.black)).italic()
                        Spacer()
                        Label("\(Learning.streak(store.snapshot.sessions).days) days", systemImage: "flame.fill")
                            .font(.subheadline.bold()).padding(10).background(Rally.paleYellow, in: Capsule())
                    }
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ready for another lap?").font(.largeTitle.weight(.heavy))
                            Text("A little car knowledge, every day.").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        RallyGuide(size: 145)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your next stage", systemImage: "flag.checkered").font(.title2.bold())
                        Text("\(store.queue(exhibit: exhibit).count) facts ready to review").font(.headline)
                        Text("From your garage").font(.subheadline).foregroundStyle(.secondary)
                        Button("Start quiz") { studying = true }.buttonStyle(RallyButton())
                            .disabled(store.queue(exhibit: exhibit).isEmpty || store.diskFailed)
                        if store.queue(exhibit: exhibit).isEmpty {
                            Text("You're caught up. Research cars in Garage or return when your next review is due.").font(.caption)
                        }
                    }.padding(18).padding(.bottom, 5).background(Rally.paleYellow, in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Make it your session").font(.title3.bold())
                        HStack {
                            Label("Time", systemImage: "clock")
                            Spacer()
                            Picker(selection: $minutes) {
                            ForEach(Array(stride(from: 5, through: 30, by: 5)), id: \.self) { Text("\($0) minutes").tag($0) }
                            } label: { Text("Time") }.labelsHidden()
                        }
                        Divider()
                        HStack {
                            Label("Quiz style", systemImage: "list.bullet.rectangle")
                            Spacer()
                            Picker(selection: $mode) {
                            Text("Multiple choice").tag("Multiple choice")
                            Text("Typed recall").tag("Typed recall")
                            } label: { Text("Quiz style") }.labelsHidden()
                        }
                        Divider()
                        HStack {
                            Label("Exhibit", systemImage: "car.side")
                            Spacer()
                            Picker(selection: $exhibit) {
                            Text("All exhibits").tag(nil as String?)
                            ForEach(store.snapshot.exhibits.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
                            } label: { Text("Exhibit") }.labelsHidden()
                        }
                    }.pickerStyle(.menu).padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Saved for offline study").font(.subheadline.bold())
                            Text("Answers stay on this device. Tap Sync when online.").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "checkmark.icloud").font(.title2) }
                    DisclosureGroup("Your progress") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(store.snapshot.sessions.count) completed sessions")
                            Text("\(Learning.streak(store.snapshot.sessions).freezesLeft) of 3 monthly freezes remaining")
                            Text("Freezes automatically cover missed past days. They preserve your streak without adding study days.").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }.font(.subheadline)
                    Button("Sync library", systemImage: "arrow.triangle.2.circlepath") { Task { await store.sync() } }.disabled(store.busy || store.diskFailed)
                }.padding(20)
            }.background(Rally.cream)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
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
    @State private var answerError = ""
    @State private var result: Bool?
    @State private var finished = false
    @State private var correctCount = 0
    @State private var answerCount = 0
    @State private var now = Date()
    @State private var photoIndex = 0
    @State private var photoRotation = CarPhotoRotation()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if finished {
                        RallyGuide(size: 180)
                        Text("Stage complete!").font(.largeTitle.bold())
                        Text("\(correctCount) of \(answerCount) correct")
                        Text(store.diskFailed ? "Storage failed. Progress is not safely saved; resolve the storage error before continuing." : (answerCount == 0 ? "No answers recorded. This session did not count toward your streak." : "Progress saved on this device. Sync when online."))
                        Button("Done") { dismiss() }.buttonStyle(RallyButton())
                    } else {
                        HStack {
                            ProgressView(value: min(1, max(0, now.timeIntervalSince(deadline.addingTimeInterval(-Double(minutes * 60)))) / Double(minutes * 60))).tint(Rally.yellow)
                            Text("\(max(0, Int(deadline.timeIntervalSince(now))) / 60):\(String(format: "%02d", max(0, Int(deadline.timeIntervalSince(now))) % 60))").font(.caption.monospacedDigit())
                        }.accessibilityElement(children: .combine).accessibilityLabel("Time remaining")
                        Text("\(answerCount) answered").font(.caption).foregroundStyle(.secondary)
                        if let fact {
                            if let car = store.snapshot.cars.first(where: { $0.id == fact.carId }) {
                                Text(car.name).font(.headline)
                                CarPhoto(car: car, photos: store.photos(for: car.id), index: photoIndex, compact: true)
                            }
                            Text(fact.prompt).font(.title2.bold())
                            if typed {
                                TextField("Your answer", text: $response).textFieldStyle(.roundedBorder)
                                    .disabled(result != nil).onSubmit { submit() }
                                    .onChange(of: response) { _, _ in answerError = "" }
                                if response.unicodeScalars.count > StudyInputLimits.response && answerError.isEmpty {
                                    Text("Keep your answer within 1,000 characters. Your text has not been changed.").foregroundStyle(.red)
                                }
                            } else {
                                ForEach(choices, id: \.self) { choice in
                                    Button { response = choice } label: {
                                        HStack {
                                            Text(choice).multilineTextAlignment(.leading)
                                            Spacer(minLength: 4)
                                            if response == choice { Image(systemName: "checkmark.circle.fill") }
                                        }.font(.body.weight(response == choice ? .semibold : .regular))
                                            .foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 28).padding(14)
                                            .background(response == choice ? Rally.paleYellow : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(response == choice ? Rally.yellow : Color.secondary.opacity(0.25), lineWidth: response == choice ? 2 : 1))
                                    }.buttonStyle(.plain).disabled(result != nil)
                                        .accessibilityAddTraits(response == choice ? .isSelected : [])
                                }
                            }
                            if result == nil {
                                GuideMessage(text: "Trust your car instincts.")
                            }
                            if !answerError.isEmpty { Text(answerError).foregroundStyle(.red) }
                            if let result {
                                GuideMessage(text: result ? "Nice driving! You got it." : "Another lap, another chance. Keep practicing!")
                                Label(result ? "Correct" : "Keep practicing", systemImage: result ? "checkmark.circle.fill" : "arrow.clockwise").font(.headline).foregroundStyle(result ? .green : .primary)
                                Text("Answer: \(fact.answer)")
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
            .background(Rally.cream)
            .safeAreaInset(edge: .bottom) {
                if !finished && fact != nil {
                    Group {
                        if result == nil {
                            Button("Check answer") { submit() }
                                .disabled(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || response.unicodeScalars.count > StudyInputLimits.response)
                        } else {
                            Button("Next question") { advance() }
                        }
                    }.buttonStyle(RallyButton()).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10).background(Rally.cream)
                }
            }
            .navigationTitle(typed ? "Typed recall" : "Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !finished { Button("Finish") { finish() } }
            }
            .interactiveDismissDisabled()
            .onAppear { deadline = Date().addingTimeInterval(Double(minutes * 60)); advance() }
            .onReceive(timer) { date in
                now = date
                if !finished && (date >= deadline || store.diskFailed) { finish() }
            }
        }
    }
    private func submit() {
        guard result == nil, let fact, Date() < deadline,
              store.availableFacts.contains(where: { $0.id == fact.id && $0.revision == fact.revision }) else { advance(); return }
        guard let correct = store.record(fact: fact, response: response, sessionId: sessionId) else {
            answerError = store.message
            return
        }
        result = correct; answerCount += 1
        if correct { correctCount += 1 }
        if answerCount >= 500 { finish() }
    }
    private func advance() {
        fact = store.queue(exhibit: exhibit).first
        if let carId = fact?.carId {
            photoIndex = photoRotation.nextIndex(carId: carId, count: store.photos(for: carId).count)
        }
        choices = fact?.choices.shuffled() ?? []
        response = ""; result = nil; answerError = ""
    }
    private func finish() { store.complete(sessionId: sessionId); finished = true }
}
