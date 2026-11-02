import SwiftUI

/// A finite lesson snapshot: reading an idea is separate from recording an answer.
struct JourneyLessonView: View {
    @EnvironmentObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    let exhibitIds: Set<String?>
    var carId: String? = nil
    @State private var plan: JourneyPlan?
    @State private var loaded = false
    @State private var started = false
    @State private var index = 0
    @State private var teaching = false
    @State private var choices: [String] = []
    @State private var response = ""
    @State private var result: Bool?
    @State private var error = ""
    @State private var completed = false
    @State private var answered = 0
    @State private var correct = 0
    @State private var sessionId = UUID().uuidString
    @State private var rotation = CarPhotoRotation()
    @State private var photoIndex = 0

    private var item: JourneyItem? {
        guard let plan, plan.items.indices.contains(index) else { return nil }
        return plan.items[index]
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if completed {
                            RallyGuide(size: 170, pose: .celebrating).frame(maxWidth: .infinity)
                            Text(answered > 0 ? "A little more car knowledge!" : "See you next lap.").font(.largeTitle.bold())
                            Text("\(correct) of \(answered) answers correct").font(.title3.bold())
                            Text(answered > 0 ? "This was a step in your journey. We’ll revisit these ideas in later lessons to help them stick." : "No answers recorded. This visit won’t count toward your streak.")
                            Text(store.diskFailed ? "Storage failed. Progress is not safely saved. Resolve the storage error before continuing." : "Progress stays on this device. Sync from Settings when online.").font(.caption).foregroundStyle(.secondary)
                        } else if let plan {
                            if !started {
                                introduction(plan)
                            } else if let item {
                                Text("\(index + 1) of \(plan.items.count) ideas · \(item.isNew ? "New discovery" : "Review lap")")
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                ProgressView(value: Double(index), total: Double(plan.items.count)).tint(Rally.yellow)
                                if let car = store.snapshot.cars.first(where: { $0.id == item.fact.carId }) {
                                    Text(car.name).font(.title3.bold())
                                    CarPhoto(car: car, photos: store.photos(for: car.id), index: photoIndex, compact: true)
                                }
                                if teaching {
                                    GuideMessage(text: item.fact.category == "story" ? "Here’s a story to share on your next museum visit." : "Let’s get to know this car, one idea at a time.", pose: .teaching)
                                    Text(item.fact.category == "story" ? "A story worth sharing" : "Take a closer look").font(.title2.bold())
                                    Text(item.fact.statement).font(.title3)
                                    if item.fact.explanation != item.fact.statement {
                                        Text(item.fact.explanation).foregroundStyle(.secondary)
                                    }
                                    sourceLinks(item.fact)
                                    Text("Read at your own pace. There’s no timer.").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    question(item)
                                }
                            }
                        } else {
                            GuideMessage(text: "You’re caught up. Meet another car in Garage, or return for your next review.", pose: .teaching)
                        }
                    }.padding(20)
                }.id("\(started)-\(index)-\(teaching)-\(completed)").background(Rally.cream)
                .navigationTitle(completed ? "Lesson complete" : (plan?.title ?? "Your next lap"))
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) { action.padding().background(Rally.cream) }
                .toolbar { if !completed { Button("Finish") { finish() } } }
                .interactiveDismissDisabled()
                .onAppear {
                    guard !loaded else { return }
                    loaded = true
                    var library = store.snapshot
                    if let carId { library.cars = library.cars.filter { $0.id == carId } }
                    plan = JourneyPlanner.plan(snapshot: library, exhibitIds: exhibitIds)
                }
                .onChange(of: store.diskFailed) { _, failed in if failed { finish() } }
                .onChange(of: result) { _, answer in
                    if answer != nil { scroll.scrollTo("lessonFeedback", anchor: .top) }
                }
            }
        }
    }

    private func introduction(_ plan: JourneyPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            RallyGuide(size: 150, pose: .teaching).frame(maxWidth: .infinity)
            Text(plan.car?.name ?? "A lap around your garage").font(.largeTitle.bold())
            Text(plan.subtitle).font(.headline)
            Text("We’ll learn a few ideas together, then try a multiple-choice check. Take as long as you like.")
            ForEach(plan.items) { item in
                Label(item.isNew ? "Discover an idea about \(carName(item.fact))" : "Revisit \(carName(item.fact))",
                      systemImage: item.isNew ? "sparkles" : "arrow.clockwise")
                    .font(.subheadline).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func question(_ item: JourneyItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.fact.prompt).font(.title2.bold())
            ForEach(choices, id: \.self) { choice in
                Button { response = choice } label: {
                    HStack {
                        Text(choice).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        if response == choice { Image(systemName: "checkmark.circle.fill") }
                    }.foregroundStyle(.primary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(response == choice ? Rally.paleYellow : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(response == choice ? Rally.yellow : .secondary.opacity(0.25), lineWidth: response == choice ? 2 : 1))
                }.buttonStyle(.plain).disabled(result != nil || store.diskFailed)
                    .accessibilityAddTraits(response == choice ? .isSelected : [])
            }
            if let result {
                GuideMessage(text: result ? "You’ve got it! Another idea to take with you." : "Let’s look at the story behind that answer.", pose: result ? .celebrating : .teaching)
                    .id("lessonFeedback")
                Label(result ? "Correct" : "Keep practicing", systemImage: result ? "checkmark.circle.fill" : "arrow.clockwise").font(.headline)
                Text("Answer: \(item.fact.answer)").font(.headline)
                Text(item.fact.explanation)
                sourceLinks(item.fact)
                Button("Flag this question") {
                    store.report(item.fact, reason: "Flagged during lesson: answer or wording appears incorrect.")
                    next()
                }
            } else {
                GuideMessage(text: item.isNew ? "Try the idea we just explored." : "Let’s see what you remember.")
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }
    }

    @ViewBuilder private var action: some View {
        if completed || plan == nil {
            Button("Done") { dismiss() }.buttonStyle(RallyButton())
        } else if !started {
            Button("Let’s begin") { started = true; prepare() }.buttonStyle(RallyButton())
        } else if teaching {
            Button("Try a question") { teaching = false }.buttonStyle(RallyButton())
        } else if result == nil {
            Button("Check answer") { submit() }.buttonStyle(RallyButton()).disabled(response.isEmpty || store.diskFailed)
        } else {
            Button(index + 1 == plan?.items.count ? "Finish lesson" : "Next idea") { next() }.buttonStyle(RallyButton())
        }
    }
    private func sourceLinks(_ fact: Fact) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("From the research").font(.caption.bold())
            ForEach(fact.sources, id: \.self) { source in
                if let url = URL(string: source.url) { Link(source.title, destination: url).font(.caption) }
            }
        }
    }
    private func carName(_ fact: Fact) -> String {
        store.snapshot.cars.first { $0.id == fact.carId }?.name ?? "your garage"
    }
    private func prepare() {
        guard let item else { finish(); return }
        teaching = item.isNew
        choices = item.fact.choices.shuffled()
        response = ""; result = nil; error = ""
        photoIndex = rotation.nextIndex(carId: item.fact.carId, count: store.photos(for: item.fact.carId).count)
    }
    private func submit() {
        guard result == nil, let item else { return }
        guard store.availableFacts.contains(where: { $0.id == item.fact.id && $0.revision == item.fact.revision }) else {
            error = "This idea changed or is no longer available. Continue to the next one."
            next(); return
        }
        guard let grade = store.record(fact: item.fact, response: response, sessionId: sessionId) else { error = store.message; return }
        result = grade; answered += 1
        if grade { correct += 1 }
    }
    private func next() {
        guard let plan else { return }
        index += 1
        if index >= plan.items.count { finish() } else { prepare() }
    }
    private func finish() { store.complete(sessionId: sessionId); completed = true }
}
