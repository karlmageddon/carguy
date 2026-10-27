import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct PlaqueCarView: View {
    @EnvironmentObject private var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var car: Car
    @State private var transcription = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var reading = false
    @State private var status = ""
    @State private var generation = UUID()

    init(exhibitId: String?) {
        _car = State(initialValue: Car(name: "", exhibitId: exhibitId))
    }

    private var notes: String { PlaqueRecognition.notesPrefix + transcription }
    private var canSave: Bool {
        !reading && !store.busy && !store.diskFailed && car.plaquePhotoData != nil &&
        !car.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        car.name.unicodeScalars.count <= 200 &&
        !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        notes.unicodeScalars.count <= 3000
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photograph a museum plaque") {
                    Text("Take a clear, close photo with the plaque square in the frame. You can also choose an existing photo.")
                    Button("Take plaque photo", systemImage: "camera") {
                        Task {
                            guard await AVCaptureDevice.requestAccess(for: .video) else {
                                status = "Camera access is off. Enable it for Carguy in iOS Settings, or choose a photo."
                                return
                            }
                            showingCamera = true
                        }
                    }.disabled(reading || !UIImagePickerController.isSourceTypeAvailable(.camera))
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose plaque photo", systemImage: "photo")
                    }.disabled(reading)
                    if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Text("This device has no available camera. Choose a saved plaque photo instead.").font(.caption)
                    }
                    if reading { ProgressView("Reading plaque on this device…") }
                    if let encoded = car.plaquePhotoData, let data = Data(base64Encoded: encoded), let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                            .accessibilityLabel("Selected museum plaque")
                    }
                }.disabled(store.busy)
                Section("Review before saving") {
                    Text("Check the suggested name and every line of text, especially years, model numbers and units. Recognition can make mistakes.").font(.caption)
                    TextField("Car name", text: $car.name)
                    if car.name.unicodeScalars.count > 200 {
                        Text("Keep the car name within 200 characters. Your text has not been shortened.").foregroundStyle(.red)
                    }
                    TextField("Plaque transcription", text: $transcription, axis: .vertical).lineLimit(5...18)
                    Text("\(notes.unicodeScalars.count) / 3,000 characters in identification notes").font(.caption)
                        .foregroundStyle(notes.unicodeScalars.count > 3000 ? .red : .secondary)
                    Picker("Exhibit", selection: $car.exhibitId) {
                        Text("Unassigned").tag(nil as String?)
                        ForEach(store.snapshot.exhibits.filter { !$0.archived }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                    if !car.name.isEmpty && store.snapshot.cars.contains(where: {
                        $0.name.caseInsensitiveCompare(car.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                    }) {
                        Text("A car with this name is already in Garage. Cancel to edit that entry, or change the name if this is a different vehicle.").font(.caption)
                    }
                }.disabled(reading || store.busy)
                if !status.isEmpty { Section { Text(status) } }
                Section {
                    Button("Save and research") { save(research: true) }.disabled(!canSave)
                    Text("Save car works offline. Research needs your API connection. Sync stores the plaque photo in your private library; only the reviewed text is sent to OpenAI. The plaque is kept out of quiz photos.").font(.caption)
                }
            }
            .navigationTitle("Add car by plaque")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { generation = UUID(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save car") { save(research: false) }.disabled(!canSave)
                }
            }
            .onChange(of: selectedPhoto) { _, selection in
                guard let selection else { return }
                let ticket = UUID(); generation = ticket; reading = true; status = ""
                Task {
                    do {
                        guard let data = try await selection.loadTransferable(type: Data.self) else {
                            throw NSError(domain: "CarguyPlaque", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "That photo could not be loaded. Try another image."])
                        }
                        await scan(data, ticket: ticket)
                    } catch {
                        guard generation == ticket else { return }
                        reading = false; status = error.localizedDescription
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                PlaqueCamera(onPhoto: { data in
                    showingCamera = false
                    let ticket = UUID(); generation = ticket; reading = true; status = ""
                    Task { await scan(data, ticket: ticket) }
                }, onCancel: { showingCamera = false })
                .ignoresSafeArea()
            }
        }
    }

    private func scan(_ data: Data, ticket: UUID) async {
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try PlaqueRecognition.recognize(data)
            }.value
            guard generation == ticket else { return }
            car.plaquePhotoData = result.imageData.base64EncodedString()
            car.name = result.suggestedName
            transcription = result.text
            if result.text.isEmpty {
                status = "No readable text found. Try a clearer photo or type the plaque text below."
            } else if result.uncertainLines > 0 {
                status = "Some text was unclear. Review the transcription against the photo before saving."
            } else {
                status = "Text extracted. Review the name and transcription before saving."
            }
            reading = false
        } catch {
            guard generation == ticket else { return }
            reading = false; status = "Could not read this plaque. Try another photo. Your existing draft is retained."
        }
    }

    private func save(research: Bool) {
        guard canSave else { return }
        car.name = car.name.trimmingCharacters(in: .whitespacesAndNewlines)
        car.notes = notes
        guard store.saveCar(car) else { status = store.message; return }
        let id = car.id
        dismiss()
        if research { Task { await store.research(carId: id) } }
    }
}

private struct PlaqueCamera: UIViewControllerRepresentable {
    var onPhoto: (Data) -> Void
    var onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PlaqueCamera
        init(_ parent: PlaqueCamera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else { parent.onCancel(); return }
            // Normalize camera orientation before passing JPEG data to recognition.
            let scale = min(1, 2200 / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let data = normalized.jpegData(compressionQuality: 0.95) else { parent.onCancel(); return }
            parent.onPhoto(data)
        }
    }
}
