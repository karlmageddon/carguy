import SwiftUI

struct StudyHome: View {
    @EnvironmentObject var store: StudyStore
    @State private var choosingExhibits = false
    @State private var selectedExhibits: Set<String?> = []
    @State private var studying = false
    @State private var chosenCar: Car?
    private var nextPlan: JourneyPlan? {
        JourneyPlanner.plan(snapshot: store.snapshot, exhibitIds: Set(store.snapshot.cars.map(\.exhibitId)))
    }
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
                        Label(nextPlan?.title ?? "You’re caught up", systemImage: "flag.checkered").font(.title2.bold())
                        Text(nextPlan.map { ($0.car?.name ?? "From your garage") + " · " + $0.subtitle } ?? "Research a new car or return for a review.").font(.headline)
                        Text("A short chapter, a few questions, and a little discovery.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Continue learning") { choosingExhibits = true }.buttonStyle(RallyButton())
                            .disabled(nextPlan == nil || store.diskFailed)
                        if nextPlan == nil {
                            Text("You're caught up. Research cars in Garage or return when your next review is due.").font(.caption)
                        }
                    }.padding(18).padding(.bottom, 5).background(Rally.paleYellow, in: RoundedRectangle(cornerRadius: 24))
                    Text("Your car journeys").font(.title2.bold())
                    ForEach(store.snapshot.cars.filter { car in JourneyPlanner.hasEligibleFacts(car: car, facts: store.snapshot.facts) }) { car in
                        Button { chosenCar = car } label: { journeyCard(car) }.buttonStyle(.plain)
                            .disabled(!canStudy(car) || store.diskFailed)
                    }
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
            .fullScreenCover(isPresented: $studying) { JourneyLessonView(exhibitIds: selectedExhibits) }
            .fullScreenCover(item: $chosenCar) { car in JourneyLessonView(exhibitIds: [car.exhibitId], carId: car.id) }
        }
    }
    private func canStudy(_ car: Car) -> Bool {
        var library = store.snapshot
        library.cars = [car]
        return JourneyPlanner.plan(snapshot: library, exhibitIds: [car.exhibitId]) != nil
    }
    private func journeyCard(_ car: Car) -> some View {
        let familiarity = JourneyPlanner.familiarity(car: car, facts: store.snapshot.facts, attempts: store.snapshot.attempts)
        return HStack(spacing: 12) {
            CarThumbnail(car: car, photos: store.photos(for: car.id))
            VStack(alignment: .leading, spacing: 6) {
                Text(car.name).font(.headline)
                Text(familiarity.label).font(.caption.bold()).foregroundStyle(.secondary)
                Text(canStudy(car) ? "Continue this car’s story" : "Caught up for now").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(10).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
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
                Text(JourneyPlanner.plan(snapshot: store.snapshot, exhibitIds: selected)?.subtitle ?? "No lessons or reviews ready for these exhibits.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .navigationTitle("Choose exhibits")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Begin lesson") { start(selected) }.buttonStyle(RallyButton())
                    .disabled(selected.isEmpty || JourneyPlanner.plan(snapshot: store.snapshot, exhibitIds: selected) == nil || store.diskFailed)
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
