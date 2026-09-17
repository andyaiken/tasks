import SwiftUI
import TasksCore

/// Sharing, in Settings (§7): share your own list and see who's in it, or leave someone else's.
struct SharingSection: View {
    @Environment(Store.self) private var store
    @Environment(CloudSync.self) private var sync
    @State private var opening = false
    @State private var error: String?
    @State private var confirmingLeave = false

    var body: some View {
        Section {
            if !sync.isSignedIn {
                Text("Sign into iCloud to share this list.")
                    .foregroundStyle(.secondary)
            } else {
                switch store.sharing {
                case .notShared:
                    shareButton("Share This List…")
                case .owner:
                    people
                    shareButton("Manage Sharing…")
                case .member:
                    people
                    Button("Leave List", role: .destructive) { confirmingLeave = true }
                }
            }
            if let error {
                Text(error)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Sharing")
        } footer: {
            Text(footer)
        }
        .confirmationDialog("Leave \(ownerName)'s list?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave List", role: .destructive) {
                Task { await sync.leaveSharedList() }
            }
        } message: {
            Text("You'll go back to your own list. \(ownerName) and everyone else keep this one.")
        }
    }

    private var ownerName: String {
        store.listOwner.flatMap { store.participantLabels[$0.id] } ?? "the owner"
    }

    private var footer: String {
        guard sync.isSignedIn else { return "" }
        return switch store.sharing {
        case .notShared:
            "Invite people using the email address or phone number they use for iCloud. Everyone in the list can add, tick off and change tasks."
        case .owner:
            "You own this list. If you stop sharing it, everyone else loses it."
        case .member:
            "\(ownerName) owns this list. If you leave, you'll go back to your own list."
        }
    }

    private var people: some View {
        let labels = store.participantLabels
        let sorted = store.participants.sorted { a, b in
            if a.isOwner != b.isOwner { return a.isOwner }
            if a.status != b.status { return a.status == .joined }
            return (labels[a.id] ?? "").localizedStandardCompare(labels[b.id] ?? "") == .orderedAscending
        }
        return ForEach(sorted) { participant in
            HStack {
                Text(labels[participant.id] ?? "User")
                Spacer()
                Text(detail(for: participant))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detail(for participant: Participant) -> String {
        var parts: [String] = []
        if participant.userID == store.me { parts.append("You") }
        if participant.isOwner { parts.append("Owner") }
        if participant.status == .invited { parts.append("Invited") }
        return parts.joined(separator: " · ")
    }

    private func shareButton(_ title: String) -> some View {
        Button {
            Task { await openSharing() }
        } label: {
            HStack {
                Text(title)
                if opening {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(opening)
    }

    private func openSharing() async {
        opening = true
        error = nil
        defer { opening = false }
        do {
            let share = try await sync.shareForOwnList()
            SharingScreen.present(share, sync: sync)
        } catch {
            self.error = "Couldn't open sharing: \(error.localizedDescription)"
        }
    }
}
