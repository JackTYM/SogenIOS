import SwiftUI

/// Lists all ArcadeProfiles (built-in starter first, then user-created) with per-row
/// duplicate/delete, reached from SetupView's "Controller Layouts" button.
struct ArcadeProfileListView: View {
    @State private var profiles: [ArcadeProfile] = ArcadeProfileStore.shared.profiles
    @State private var editingProfile: ArcadeProfile?

    var body: some View {
        List {
            ForEach(profiles) { profile in
                Button(profile.name) {
                    editingProfile = profile
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        ArcadeProfileStore.shared.delete(profile.id)
                        profiles = ArcadeProfileStore.shared.profiles
                    }
                    Button("Duplicate") {
                        var copy = profile
                        copy.id = UUID()
                        copy.name = profile.name + " Copy"
                        ArcadeProfileStore.shared.upsert(copy)
                        profiles = ArcadeProfileStore.shared.profiles
                    }
                }
            }
            Button("+ New Profile") {
                editingProfile = ArcadeProfile(id: UUID(), name: "New Profile", buttons: [], joystick: nil)
            }
        }
        .navigationTitle("Controller Layouts")
        .sheet(item: $editingProfile) { profile in
            ArcadeProfileEditorView(profile: profile) { saved in
                ArcadeProfileStore.shared.upsert(saved)
                profiles = ArcadeProfileStore.shared.profiles
                editingProfile = nil
            }
        }
    }
}
