import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Installed web extensions of a profile.
struct ExtensionsManagerView: View {
    @Bindable var session: BrowserSession
    @State private var profileID: Profile.ID?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Picker("Profile", selection: $profileID) {
                    ForEach(session.store.workspace.orderedProfiles) { Text($0.name).tag(Profile.ID?.some($0.id)) }
                }
                Button("Add Extension…") { chooseExtension() }
                if let message { Text(message).foregroundStyle(.secondary) }
            } footer: {
                Text(
                    """
                    Marc runs Chrome and Safari web extensions through WebKit. Install an unpacked folder, a .zip or a \
                    .crx file; installing directly from the Chrome Web Store isn't supported. Extensions are disabled in \
                    Incognito windows.
                    """,
                )
            }
            if let host {
                Section("Installed") {
                    if host.installed.isEmpty {
                        Text("No extensions installed").foregroundStyle(.secondary)
                    }
                    ForEach(host.installed) { entry in
                        HStack {
                            if let icon = host.contexts[entry.id]?.webExtension.icon(for: CGSize(width: 24, height: 24)) {
                                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "puzzlepiece.extension").frame(width: 24, height: 24)
                            }
                            VStack(alignment: .leading) {
                                Text(entry.displayName)
                                Text("Version \(entry.version)").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if host.optionsPageURL(for: entry.id) != nil {
                                Button("Options") {
                                    if let url = host.optionsPageURL(for: entry.id) { session.keyWindow?.open(url, placement: .newTab) }
                                }
                            }
                            Toggle("Enabled", isOn: Binding(
                                get: { entry.isEnabled },
                                set: { enabled in Task { await host.setEnabled(entry.id, enabled) } },
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            Button(role: .destructive) { host.uninstall(entry.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .onAppear { profileID = profileID ?? session.keyWindow?.profile?.id ?? session.store.workspace.orderedProfiles.first?.id }
    }

    private var host: WebExtensionHost? {
        guard let profileID, let profile = session.store.workspace.profiles[profileID] else { return nil }
        return session.extensionHost(for: profile)
    }

    private func chooseExtension() {
        guard let host else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .zip, UTType(filenameExtension: "crx") ?? .data]
        panel.message = "Choose an extension folder, .zip or .crx file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let installed = try await host.install(from: url)
                message = "Added \(installed.displayName)."
            } catch WebExtensionHost.InstallError.declined {
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

/// Toolbar actions of the profile's extensions, shown in Site Controls.
struct ExtensionActionsRow: View {
    @Bindable var window: BrowserWindowModel
    let tab: WebTab

    var body: some View {
        if let profile = window.profile, let host = window.session?.extensionHost(for: profile) {
            let actions = host.actions(for: tab)
            VStack(alignment: .leading, spacing: 6) {
                Text("Extensions").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(actions, id: \.id) { entry in
                        Button {
                            window.siteControlItemID = nil
                            host.performAction(entry.id, for: tab)
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                if let icon = entry.action.icon(for: CGSize(width: 20, height: 20)) {
                                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                } else {
                                    Image(systemName: "puzzlepiece.extension")
                                }
                                if !entry.action.badgeText.isEmpty {
                                    Text(entry.action.badgeText)
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 3)
                                        .background(Capsule().fill(.red))
                                        .offset(x: 6, y: 4)
                                }
                            }
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
                        }
                        .buttonStyle(.pressable)
                        .disabled(!entry.action.isEnabled)
                        .help(entry.action.label)
                    }
                    Button { window.session?.showSettings?(.extensions) } label: {
                        Image(systemName: "plus").frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
                    }
                    .buttonStyle(.pressable)
                    .help("Manage Extensions")
                }
                .id(host.actionsRevision)
            }
        }
    }
}
