import SwiftUI
import PhotosUI
import UIKit

struct CarPhoto: View {
    var car: Car
    var body: some View {
        Group {
            if let encoded = car.photoData, let data = Data(base64Encoded: encoded), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ContentUnavailableView("Add a car photo", systemImage: "camera", description: Text("Your selected photo is saved for offline quizzes."))
            }
        }.frame(maxWidth: .infinity, maxHeight: 220).accessibilityLabel("Photo of \(car.name)")
    }
}
struct GarageView: View {
    @EnvironmentObject var store: StudyStore
    @State private var exhibit: String?
    @State private var showRemoved = false
    @State private var addingCar = false
    @State private var addingExhibit = false
    @State private var exhibitName = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Exhibit", selection: $exhibit) {
                        Text("All exhibits").tag(nil as String?)
                        ForEach(store.snapshot.exhibits.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Toggle("Include removed cars", isOn: $showRemoved)
                }
                ForEach(store.snapshot.cars.filter { (showRemoved || !$0.removed) && (exhibit == nil || $0.exhibitId == exhibit) }) { car in
                    NavigationLink {
                        CarDetail(carId: car.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(car.name)
                            if car.removed { Text("Removed · history retained").font(.caption).foregroundStyle(.secondary) }
                            if let state = store.snapshot.research.first(where: { $0.carId == car.id }) {
                                Text(state.status.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button("Add car", systemImage: "plus") { addingCar = true }.disabled(store.busy)
                    Button("Add exhibit", systemImage: "rectangle.stack.badge.plus") { addingExhibit = true }
                    Button("Sync", systemImage: "arrow.triangle.2.circlepath") { Task { await store.sync() } }.disabled(store.busy)
                }
            }
            .navigationTitle("Carguy")
            .refreshable { await store.sync() }
            .sheet(isPresented: $addingCar) { CarEditor(car: Car(name: "", exhibitId: exhibit)) }
            .alert("New exhibit", isPresented: $addingExhibit) {
                TextField("Exhibit name", text: $exhibitName)
                Button("Save") {
                    if store.saveExhibit(exhibitName) { exhibitName = "" }
                }
                .disabled(exhibitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exhibitName.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > StudyInputLimits.exhibitName)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Use 1–120 characters for the exhibit name.")
            }
        }.disabled(store.diskFailed)
    }
}
struct CarEditor: View {
    @EnvironmentObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State var car: Car
    @State private var photo: PhotosPickerItem?
    @State private var error = ""
    var body: some View {
        NavigationStack {
            Form {
                if store.busy {
                    Text("Wait for sync or research to finish before editing. Your unsaved changes stay here.").font(.caption)
                }
                Section {
                    TextField("Car name", text: $car.name)
                    TextField("Identification notes / placard text", text: $car.notes, axis: .vertical)
                    Picker("Exhibit", selection: $car.exhibitId) {
                        Text("Unassigned").tag(nil as String?)
                        ForEach(store.snapshot.exhibits.filter { !$0.archived }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Toggle("Removed from exhibit", isOn: $car.removed)
                    Text("Removing a car excludes it from quizzes and preserves facts, attempts and exhibit history.").font(.caption)
                    CarPhoto(car: car)
                    PhotosPicker("Choose photo", selection: $photo, matching: .images)
                        .onChange(of: photo) { _, selected in
                            Task {
                                do {
                                    guard let data = try await selected?.loadTransferable(type: Data.self), let original = UIImage(data: data) else { return }
                                    let factor = min(1, 1000 / max(original.size.width, original.size.height))
                                    let size = CGSize(width: original.size.width * factor, height: original.size.height * factor)
                                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                                    let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
                                    var encoded: Data?
                                    for quality in [0.8, 0.6, 0.4, 0.2] {
                                        if let candidate = scaled.jpegData(compressionQuality: quality), candidate.count <= 250 * 1024 { encoded = candidate; break }
                                    }
                                    guard let encoded else { error = "Choose a smaller photo (250 KiB after compression)."; return }
                                    car.photoData = encoded.base64EncodedString()
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                    if car.photoData != nil { Button("Remove photo", role: .destructive) { car.photoData = nil } }
                }.disabled(store.busy || store.diskFailed)
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Car details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        car.name = car.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if store.saveCar(car) { dismiss() }
                        else { error = store.message }
                    }
                    .disabled(store.busy || store.diskFailed || car.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || car.name.count > 200 || car.notes.count > 3000)
                }
            }
        }
    }
}
struct CarDetail: View {
    @EnvironmentObject var store: StudyStore
    var carId: String
    @State private var editing = false
    var body: some View {
        if let car = store.snapshot.cars.first(where: { $0.id == carId }) {
            List {
                CarPhoto(car: car)
                Section("Identification") {
                    Text(car.notes.isEmpty ? "Add placard details to distinguish the museum vehicle from its model." : car.notes)
                    Text("Research uses the car name and text notes. Your selected photo is saved for offline study.").font(.caption)
                    Text("To answer a research question, tap Edit and add details or transcribe the placard in identification notes.").font(.caption)
                    if let research = store.snapshot.research.first(where: { $0.carId == car.id }) {
                        Text(research.message)
                        if let source = research.photoSourceUrl, let url = URL(string: source) {
                            Link(research.photoCaption ?? "Research photo reference", destination: url)
                            Text("Choose a licensed or personal photo in Edit to save it offline.").font(.caption)
                        }
                    }
                    Button("Research with OpenAI") { Task { await store.research(carId: car.id) } }.disabled(store.busy)
                }
                Section("Facts") {
                    ForEach(store.snapshot.facts.filter { $0.carId == car.id }) { fact in
                        NavigationLink { FactDetail(factId: fact.id) } label: {
                            VStack(alignment: .leading) {
                                Text(fact.statement)
                                Text("\(fact.category) · \(fact.status)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Learning history") {
                    let ids = Set(store.snapshot.facts.filter { $0.carId == car.id }.map(\.id))
                    Text("\(store.snapshot.attempts.filter { ids.contains($0.factId) }.count) answers retained")
                    ForEach(car.previousExhibitIds, id: \.self) { id in
                        Text("Previously: " + (store.snapshot.exhibits.first { $0.id == id }?.name ?? id))
                    }
                }
            }
            .navigationTitle(car.name)
            .toolbar { Button("Edit") { editing = true }.disabled(store.busy) }
            .sheet(isPresented: $editing) { CarEditor(car: car) }
        }
    }
}
struct FactDetail: View {
    @EnvironmentObject var store: StudyStore
    var factId: String
    @State private var reason = ""
    var body: some View {
        if let fact = store.snapshot.facts.first(where: { $0.id == factId }) {
            List {
                Section(fact.category.capitalized) { Text(fact.statement); Text(fact.explanation) }
                Section("Sources") {
                    ForEach(fact.sources, id: \.self) { source in
                        if let url = URL(string: source.url) { Link(source.title, destination: url) }
                    }
                    Text("Checked \(Date(timeIntervalSince1970: fact.checkedAt).formatted(date: .abbreviated, time: .omitted)) · revision \(fact.revision)").font(.caption)
                }
                Section("Report a problem") {
                    TextField("What seems incorrect?", text: $reason, axis: .vertical)
                    Button("Flag for rechecking") { store.report(fact, reason: reason); reason = "" }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 2000 || fact.status != "published")
                    Text("Flagged facts stay out of quizzes until a sourced review resolves them.").font(.caption)
                }
                ForEach(store.snapshot.reports.filter { $0.factId == factId }) { report in
                    Section(report.status.capitalized) {
                        Text(report.reason)
                        if !report.resolution.isEmpty { Text(report.resolution) }
                        if ["pending", "unresolved"].contains(report.status) {
                            Button("Ask agent to recheck") { Task { await store.review(reportId: report.id) } }.disabled(store.busy)
                        }
                    }
                }
            }.navigationTitle("Fact details")
        }
    }
}
