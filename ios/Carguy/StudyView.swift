import SwiftUI

struct StudyHome: View {
    @EnvironmentObject var store: StudyStore
    @State private var choosingExhibits = false
    @State private var selectedExhibits: Set<String?> = []
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
                        Text("\(store.queue(exhibit: nil).count) facts ready to review").font(.headline)
                        Text("From your garage").font(.subheadline).foregroundStyle(.secondary)
                        Button("Start quiz") { choosingExhibits = true }.buttonStyle(RallyButton())
                            .disabled(store.queue(exhibit: nil).isEmpty || store.diskFailed)
                        if store.queue(exhibit: nil).isEmpty {
                            Text("You're caught up. Research cars in Garage or return when your next review is due.").font(.caption)
                        }
                    }.padding(18).padding(.bottom, 5).background(Rally.paleYellow, in: RoundedRectangle(cornerRadius: 24))
                    DisclosureGroup("Your progress") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(store.snapshot.sessions.count) completed sessions")
                            Text("\(Learning.streak(store.snapshot.sessions).freezesLeft) of 3 monthly freezes remaining")
                            Text("Freezes automatically cover missed past days. They preserve your streak without adding study days.").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }.font(.subheadline)
                }.padding(20)
            }.background(Rally.cream)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $choosingExhibits, onDismiss: {
                if !selectedExhibits.isEmpty { studying = true }
            }) {
                ExhibitQuizPicker { selection in
                    selectedExhibits = selection
                    choosingExhibits = false
                }
            }
            .onChange(of: choosingExhibits) { _, choosing in
                if choosing { selectedExhibits = [] }
            }
            .fullScreenCover(isPresented: $studying) { QuizView(exhibitIds: selectedExhibits) }
        }
    }
}
struct ExhibitQuizPicker: View {
    @EnvironmentObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String?> = []
    let start: (Set<String?>) -> Void
    private var options: [(id: String?, name: String)] {
        var result = store.snapshot.exhibits.map { (id: Optional($0.id), name: $0.name + ($0.archived ? " (archived)" : "")) }
        let known = Set(store.snapshot.exhibits.map(\.id))
        for id in Set(store.snapshot.cars.compactMap(\.exhibitId)).subtracting(known).sorted() {
            result.append((id: id, name: "Other exhibit"))
        }
        if store.snapshot.cars.contains(where: { $0.exhibitId == nil }) || result.isEmpty {
            result.append((id: nil, name: "Unassigned cars"))
        }
        return result
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    checkbox("All exhibits", checked: selected == Set(options.map(\.id))) {
                        selected = selected == Set(options.map(\.id)) ? [] : Set(options.map(\.id))
                    }
                    ForEach(options, id: \.id) { option in
                        checkbox(option.name, checked: selected.contains(option.id)) {
                            if selected.contains(option.id) { selected.remove(option.id) }
                            else { selected.insert(option.id) }
                        }
                    }
                } header: { Text("Which exhibits would you like to review?") }
                Text("\(store.queue(exhibitIds: selected).count) facts ready · Multiple choice · No timer")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .navigationTitle("Choose exhibits")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Begin quiz") { start(selected) }.buttonStyle(RallyButton())
                    .disabled(selected.isEmpty || store.queue(exhibitIds: selected).isEmpty || store.diskFailed)
                    .padding().background(Rally.cream)
            }
            .onAppear { selected = Set(options.map(\.id)) }
        }
    }
    private func checkbox(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: checked ? "checkmark.square.fill" : "square").foregroundStyle(checked ? Rally.ink : .secondary)
                Text(title).foregroundStyle(.primary)
                Spacer()
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityValue(checked ? "Selected" : "Not selected")
            .accessibilityAddTraits(checked ? .isSelected : [])
    }
}
struct QuizView: View {
    @EnvironmentObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    let exhibitIds: Set<String?>
    @State private var sessionId = UUID().uuidString
    @State private var fact: Fact?
    @State private var choices: [String] = []
    @State private var response = ""
    @State private var answerError = ""
    @State private var result: Bool?
    @State private var finished = false
    @State private var correctCount = 0
    @State private var answerCount = 0
    @State private var photoIndex = 0
    @State private var photoRotation = CarPhotoRotation()
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
                        Text("\(answerCount) answered").font(.caption).foregroundStyle(.secondary)
                        if let fact {
                            if let car = store.snapshot.cars.first(where: { $0.id == fact.carId }) {
                                Text(car.name).font(.headline)
                                CarPhoto(car: car, photos: store.photos(for: car.id), index: photoIndex, compact: true)
                            }
                            Text(fact.prompt).font(.title2.bold())
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
            .navigationTitle("Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !finished { Button("Finish") { finish() } }
            }
            .interactiveDismissDisabled()
            .onAppear { advance() }
            .onChange(of: store.diskFailed) { _, failed in
                if failed && !finished { finish() }
            }
        }
    }
    private func submit() {
        guard result == nil, let fact,
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
        fact = store.queue(exhibitIds: exhibitIds).first
        if let carId = fact?.carId {
            photoIndex = photoRotation.nextIndex(carId: carId, count: store.photos(for: carId).count)
        }
        choices = fact?.choices.shuffled() ?? []
        response = ""; result = nil; answerError = ""
    }
    private func finish() { store.complete(sessionId: sessionId); finished = true }
}
