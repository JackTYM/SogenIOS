import Foundation
import CoreGraphics

final class ArcadeProfileStore {
    static let shared = ArcadeProfileStore()

    private(set) var profiles: [ArcadeProfile]
    private var lastUsedProfileID: [String: UUID]

    private let fileURL: URL

    static let builtInStarterProfile: ArcadeProfile = {
        let wasd = ArcadeJoystick(
            position: CGPoint(x: 0.15, y: 0.75),
            radius: 0.1,
            up: arcadeKeyCatalog.first { $0.id == "w" }?.action,
            down: arcadeKeyCatalog.first { $0.id == "s" }?.action,
            left: arcadeKeyCatalog.first { $0.id == "a" }?.action,
            right: arcadeKeyCatalog.first { $0.id == "d" }?.action)
        let space = ArcadeButton(
            id: UUID(), label: "Space", position: CGPoint(x: 0.85, y: 0.8),
            size: CGSize(width: 0.12, height: 0.12),
            action: arcadeKeyCatalog.first { $0.id == "space" }!.action)
        let e = ArcadeButton(
            id: UUID(), label: "E", position: CGPoint(x: 0.7, y: 0.8),
            size: CGSize(width: 0.1, height: 0.1),
            action: arcadeKeyCatalog.first { $0.id == "e" }!.action)
        let shift = ArcadeButton(
            id: UUID(), label: "Shift", position: CGPoint(x: 0.85, y: 0.6),
            size: CGSize(width: 0.12, height: 0.1),
            action: arcadeKeyCatalog.first { $0.id == "leftShift" }!.action)
        let ctrl = ArcadeButton(
            id: UUID(), label: "Ctrl", position: CGPoint(x: 0.7, y: 0.6),
            size: CGSize(width: 0.1, height: 0.1),
            action: arcadeKeyCatalog.first { $0.id == "leftControl" }!.action)
        return ArcadeProfile(
            id: UUID(), name: "WASD + Common Actions",
            buttons: [space, e, shift, ctrl], joystick: wasd)
    }()

    private struct PersistedState: Codable {
        var profiles: [ArcadeProfile]
        var lastUsedProfileID: [String: UUID]
    }

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = documents.appendingPathComponent("ArcadeProfiles.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersistedState.self, from: data) {
            self.profiles = decoded.profiles
            self.lastUsedProfileID = decoded.lastUsedProfileID
        } else {
            self.profiles = [ArcadeProfileStore.builtInStarterProfile]
            self.lastUsedProfileID = [:]
        }
    }

    private func save() {
        let state = PersistedState(profiles: profiles, lastUsedProfileID: lastUsedProfileID)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func upsert(_ profile: ArcadeProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    func delete(_ profileID: UUID) {
        profiles.removeAll { $0.id == profileID }
        lastUsedProfileID = lastUsedProfileID.filter { $0.value != profileID }
        save()
    }

    func activeProfile(forGuestExecutableName guestExecutableName: String) -> ArcadeProfile {
        if let id = lastUsedProfileID[guestExecutableName],
           let profile = profiles.first(where: { $0.id == id }) {
            return profile
        }
        return profiles.first ?? ArcadeProfileStore.builtInStarterProfile
    }

    func setActiveProfile(_ profileID: UUID, forGuestExecutableName guestExecutableName: String) {
        lastUsedProfileID[guestExecutableName] = profileID
        save()
    }
}
