import AppKit
import MarcCore
import MarcWebKit
import SwiftUI

/// Saved passwords. The list shows sites and usernames; revealing or copying a password asks
/// for Touch ID or the account password.
struct PasswordsSettings: View {
    @Bindable var session: BrowserSession

    private var settings: Binding<BrowserSettings> {
        Bindable(session.settings).settings
    }

    @State private var profileID: Profile.ID?
    @State private var credentials: [Credential] = []
    @State private var query = ""
    @State private var revealed: [Credential.ID: String] = [:]
    @State private var isUnlocked = false

    var body: some View {
        Form {
            Section {
                Toggle("Offer to save passwords", isOn: settings.offersToSavePasswords)
                Toggle("Require Touch ID or password to fill", isOn: settings.requiresAuthenticationForPasswords)
                Picker("Profile", selection: $profileID) {
                    ForEach(session.store.workspace.orderedProfiles) { Text($0.name).tag(Profile.ID?.some($0.id)) }
                }
            }
            Section {
                if !isUnlocked {
                    Button("Show Saved Passwords…") { Task { await unlock() } }
                } else {
                    TextField("Search", text: $query)
                    ForEach(filtered) { credential in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(URL(string: credential.origin)?.displayHost ?? credential.origin)
                                Text(credential.username.isEmpty ? "No username" : credential.username).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let password = revealed[credential.id] {
                                Text(password).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            }
                            Button(revealed[credential.id] == nil ? "Show" : "Hide") { Task { await toggleReveal(credential) } }
                            Button { Task { await copy(credential) } } label: { Image(systemName: "doc.on.doc") }
                                .help("Copy Password")
                            Button(role: .destructive) { Task { await delete(credential) } } label: { Image(systemName: "trash") }
                        }
                        .buttonStyle(.borderless)
                    }
                    if filtered.isEmpty {
                        Text("No saved passwords").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Passwords are stored in your macOS Keychain on this Mac only. They are never synced or sent anywhere by Marc.")
            }
        }
        .onAppear { profileID = profileID ?? session.keyWindow?.profile?.id ?? session.store.workspace.orderedProfiles.first?.id }
        .onChange(of: profileID) { Task { await reload() } }
    }

    private var store: (any CredentialStore)? {
        guard let profileID, let profile = session.store.workspace.profiles[profileID] else { return nil }
        return session.profileServices(for: profile).credentials
    }

    private var filtered: [Credential] {
        credentials
            .filter {
                query.isEmpty || $0.origin.localizedCaseInsensitiveContains(query) || $0.username.localizedCaseInsensitiveContains(query)
            }
    }

    private func unlock() async {
        guard await session.services.authenticator.authenticate(reason: "show your saved passwords") else { return }
        isUnlocked = true
        await reload()
    }

    private func reload() async {
        guard isUnlocked else { return }
        credentials = await (try? store?.allCredentials()) ?? []
        revealed = [:]
    }

    private func toggleReveal(_ credential: Credential) async {
        if revealed[credential.id] != nil {
            revealed[credential.id] = nil
        } else {
            revealed[credential.id] = try? await store?.password(for: credential)
        }
    }

    private func copy(_ credential: Credential) async {
        guard let password = try? await store?.password(for: credential) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(password, forType: .string)
    }

    private func delete(_ credential: Credential) async {
        try? await store?.delete(credential)
        await reload()
    }
}

/// AI provider choice and the Claude API key.
struct AISettings: View {
    @Bindable var session: BrowserSession

    private var settings: Binding<BrowserSettings> {
        Bindable(session.settings).settings
    }

    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var onDeviceAvailable = false
    @State private var message: String?

    static let keychainKey = "anthropic-api-key"

    var body: some View {
        Form {
            Section {
                Picker("AI features", selection: settings.aiProvider) {
                    ForEach(AIProviderKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Apple Intelligence") {
                    Text(onDeviceAvailable ? "Available" : "Not available on this Mac").foregroundStyle(.secondary)
                }
            } footer: {
                Text(
                    """
                    Automatic uses the on-device model when it is available and Claude otherwise. Page text is sent to \
                    the selected model only when you ask for a summary, ask a question or tidy titles.
                    """,
                )
            }
            Section("Claude") {
                SecureField(hasStoredKey ? "API key saved in Keychain" : "API key", text: $apiKey)
                HStack {
                    Button("Save Key") { save() }.disabled(apiKey.isEmpty)
                    Button("Remove Key", role: .destructive) { remove() }.disabled(!hasStoredKey)
                }
                Picker("Model", selection: settings.claudeModel) {
                    ForEach(ClaudeModel.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            Section("Automations") {
                Toggle("Tidy tab titles on request", isOn: settings.tidiesTabTitles)
                Toggle("Rename downloads with descriptive names", isOn: settings.tidiesDownloadNames)
            }
        }
        .task {
            hasStoredKey = (try? session.services.secrets.secret(for: Self.keychainKey)) != nil
            onDeviceAvailable = await session.services.languageModels.provider(for: .onDevice) != nil
        }
    }

    private func save() {
        do {
            try session.services.secrets.setSecret(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.keychainKey)
            apiKey = ""
            hasStoredKey = true
            message = "Saved to Keychain."
        } catch {
            message = "Could not save the key: \(error.localizedDescription)"
        }
    }

    private func remove() {
        try? session.services.secrets.setSecret(nil, for: Self.keychainKey)
        hasStoredKey = false
        message = "Removed."
    }
}
