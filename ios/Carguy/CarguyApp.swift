import SwiftUI

@main @MainActor struct CarguyApp: App {
    @StateObject private var store = StudyStore()
    var body: some Scene {
        WindowGroup {
            TabView {
                GarageView().tabItem { Label("Garage", systemImage: "car.side") }
                StudyHome().tabItem { Label("Study", systemImage: "brain.head.profile") }
                SettingsView().tabItem { Label("Settings", systemImage: "gear") }
            }
            .environmentObject(store)
            .safeAreaInset(edge: .bottom) {
                if !store.message.isEmpty {
                    HStack {
                        Text(store.message).font(.caption)
                        Spacer()
                        Button("Dismiss") { store.message = "" }
                    }.padding(10).background(.regularMaterial)
                }
            }
        }
    }
}
