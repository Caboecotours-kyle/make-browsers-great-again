import SwiftUI

/// Creates or edits a space: name, icon, color and the profile whose
/// cookies, logins and favorites it uses.
struct SpaceEditor: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    let request: SpaceEditorRequest

    @State private var name = ""
    @State private var icon = ""
    @State private var color: UInt32 = Theme.spaceColors[0]
    @State private var profileID: UInt64 = 0
    @State private var newProfileName = ""

    private var editing: SpaceInfo? {
        request.spaceID.flatMap { id in store.snapshot.spaces.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "New Space" : "Edit Space")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("🙂", text: $icon)
                    .font(.system(size: 18))
                    .frame(width: 44)
                    .multilineTextAlignment(.center)
                    .onChange(of: icon) { _, value in
                        // An icon is a single character (usually an emoji).
                        if value.count > 1 { icon = String(value.suffix(1)) }
                    }
                TextField("Space name", text: $name)
                Button {
                    NSApp.orderFrontCharacterPalette(nil)
                } label: {
                    Image(systemName: "face.smiling")
                }
                .help("Pick an emoji")
            }

            HStack(spacing: 10) {
                ForEach(Theme.spaceColors, id: \.self) { swatch in
                    Circle()
                        .fill(RGB(swatch).color)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.primary.opacity(swatch == color ? 0.8 : 0), lineWidth: 2).padding(-3))
                        .onTapGesture { color = swatch }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("Profile", selection: $profileID) {
                    ForEach(store.snapshot.profiles, id: \.id) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                HStack {
                    TextField("New profile name", text: $newProfileName)
                    Button("Add Profile") {
                        let trimmed = newProfileName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        profileID = store.createProfile(trimmed)
                        newProfileName = ""
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Each profile keeps its own cookies, logins and site data. Spaces with the same profile share Favorites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let unused = store.snapshot.profiles.filter { $0.spaceCount == 0 && $0.id != profileID }
                if !unused.isEmpty && store.snapshot.profiles.count > 1 {
                    ForEach(unused, id: \.id) { profile in
                        HStack {
                            Text("Unused profile: \(profile.name)").font(.caption)
                            Spacer()
                            Button("Delete", role: .destructive) { store.deleteProfile(profile.id) }
                                .controlSize(.small)
                        }
                    }
                }
            }

            HStack {
                if let editing, store.snapshot.spaces.count > 1 {
                    Button("Delete Space", role: .destructive) {
                        store.deleteSpace(editing.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Create" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear(perform: load)
    }

    private func load() {
        if let space = editing {
            name = space.name
            icon = space.icon
            color = space.color
            profileID = space.profileId
        } else {
            name = ""
            icon = ["✨", "💼", "🎨", "📚", "🎮", "🧪", "🌿", "🚀"][store.snapshot.spaces.count % 8]
            color = Theme.spaceColors[store.snapshot.spaces.count % Theme.spaceColors.count]
            profileID = store.activeSpace.profileId
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let space = editing {
            store.updateSpace(space.id, name: trimmed, icon: icon, color: color, profileID: profileID)
        } else {
            store.createSpace(name: trimmed, icon: icon, color: color, profileID: profileID)
        }
        dismiss()
    }
}
